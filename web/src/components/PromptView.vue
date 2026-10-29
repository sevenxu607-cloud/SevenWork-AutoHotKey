<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from 'vue'
import { ahkCall, applyTheme, isHosted, markReady, type Theme } from '../ahk'
import {
  closePrompt,
  copyPrompt,
  editPrompt,
  fetchPrompts,
  getLib,
  switchLib,
  logPrompt,
  type PromptData,
  type PromptItem,
} from '../prompt'

/* ═══════════════════════════════════════════════════════════════════════
   提示词库（Alt+P）—— 原 PromptWindowFeature 的 WebView2 版

   · 数据一次取完（root / categories / items / focus），筛选是纯前端；
     只有「复制 / 编辑 / 关窗」会回 AHK 一趟。加分类、改目录都不用动这里。
   · AHK 只发指令：Enter / Ctrl+N / F5 由**模块热键**触发，再 Eval 到
     window.__swprompt。「当前选中哪条」留在前端 —— 反过来「每次点击都同步
     一次 path」等于给一次鼠标点击加一趟跨进程调用，不值。
   · 换主题只换 CSS 变量，搜索词 / 滚动位置 / 选中项全部保留（原生版要关掉重开）。
   ═══════════════════════════════════════════════════════════════════════ */

const hosted = isHosted()

const data = ref<PromptData | null>(null)
const kw = ref('')
/** 选中项的 path；用它而不是下标 —— 重新扫描后顺序可能变，下标会指错条 */
const sel = ref('')
const status = ref('')
const loading = ref(false)
/** 真机上拉取失败 —— 与「目录里本来就没有提示词」是两回事，列表区要分开说 */
const loadFailed = ref(false)
const lib = ref('prompts')

async function doSwitch(id: string) {
  if (id === lib.value) return
  const r = await switchLib(id)
  if (r !== 'ok') return
  lib.value = id
  sel.value = ''
  kw.value = ''
  await load()
}
const searchRef = ref<HTMLInputElement | null>(null)
let statusTimer = 0

/* ── 浏览器预览的样本数据 ─────────────────────────────────────────────
   `npm run dev` 里没有 hostObjects，给一份最小的样子调样式。
   刻意覆盖三种情况：有分类 / 无分类（根目录）/ 多级分类。 */
const MOCK: PromptData = {
  root: 'D:\\Notes\\_prompts',
  categories: ['', 'Chat', 'Code', 'Code\\代码审查', 'Work'],
  items: [
    {
      title: '角色设定',
      category: 'Chat',
      path: 'D:\\Notes\\_prompts\\Chat\\角色设定.md',
      summary: '你是一名资深的中文技术编辑。改写时保持原意，只压缩冗余、不添加事实……',
      mtime: '20261020103000',
    },
    {
      title: '代码审查清单',
      category: 'Code\\代码审查',
      path: 'D:\\Notes\\_prompts\\Code\\代码审查\\清单.md',
      summary: '先看边界条件与错误路径，再看命名；不要提格式问题，格式化交给工具。',
      mtime: '20261021141500',
    },
    {
      title: '周报骨架',
      category: 'Work',
      path: 'D:\\Notes\\_prompts\\Work\\周报骨架.md',
      summary: '本周完成 / 下周计划 / 风险与求助。每项不超过三行。',
      mtime: '20261019090200',
    },
    {
      title: '随手记',
      category: '',
      path: 'D:\\Notes\\_prompts\\随手记.md',
      summary: '未分类的条目落在根目录，分类一栏显示为「未分类」。',
      mtime: '20261022081500',
    },
  ],
  focus: '',
}

/* ── 派生 ───────────────────────────────────────────────────────────── */

const items = computed<PromptItem[]>(() => data.value?.items ?? [])

/** 只按标题 + 分类过滤（不搜正文 —— 提示词短，标题能命中就够，也快得多） */
const shown = computed<PromptItem[]>(() => {
  const k = kw.value.trim()
  if (!k) return items.value
  return items.value.filter((it) => it.title.includes(k) || it.category.includes(k))
})

/** 当前选中的那一条；选中的被过滤掉时退回第一行（与改造前的 _ApplyFilter 一致） */
const cur = computed<PromptItem | null>(() => {
  const hit = shown.value.find((it) => it.path === sel.value)
  return hit ?? shown.value[0] ?? null
})

const footText = computed(() => {
  const tail = `${shown.value.length} 条 · Enter 编辑 · 双击复制 · Esc 关闭`
  return status.value ? `${status.value}　·　${tail}` : tail
})

/* ── 状态行 ─────────────────────────────────────────────────────────── */

/** 与改造前 Notify 一致的 4 秒回落；回落归前端，AHK 不排定时器 */
function setStatus(text: string) {
  status.value = text
  window.clearTimeout(statusTimer)
  if (text) statusTimer = window.setTimeout(() => (status.value = ''), 4000)
}

/* ── 数据 ───────────────────────────────────────────────────────────── */

async function load(first = false) {
  loading.value = true
  let d: PromptData | null = null
  if (hosted) {
    try {
      d = await fetchPrompts(true)
    } catch (e) {
      await logPrompt('拉取提示词失败：' + String(e))
      setStatus('读取提示词目录失败')
    }
  }
  // ⚠ 真机上失败**不能**退回 MOCK —— 那是给 `npm run dev` 调样式用的样本。
  //   把样本当真数据，用户会看到 4 条根本不存在的提示词（复制 / 编辑全报错），
  //   比空列表更难懂。失败就留空，由列表区写明「读取失败」。
  loadFailed.value = hosted && !d
  data.value = d ?? (hosted ? { root: '', categories: [], items: [], focus: '' } : MOCK)

  // 定位：编辑窗保存后 AHK 会带上 focus（删除后是空串 —— 那条已经没了）
  const focus = d?.focus ?? ''
  const list = shown.value
  if (focus && list.some((it) => it.path === focus)) sel.value = focus
  else if (!list.some((it) => it.path === sel.value)) sel.value = list[0]?.path ?? ''

  loading.value = false
  if (first) nextTick(() => searchRef.value?.focus())
  // 首屏数据已落定 → 放行 AHK 的入场（见 ahk.ts 的 markReady 说明）
  markReady()
}

/* ── 键盘移动（↑↓；页面内处理，AHK 没给这两个键注册热键）─────────────── */

function move(delta: number) {
  const list = shown.value
  if (!list.length) return
  const i = list.findIndex((it) => it.path === cur.value?.path)
  const base = i < 0 ? 0 : i
  const j = Math.min(list.length - 1, Math.max(0, base + delta))
  sel.value = list[j].path
  nextTick(() => {
    document
      .querySelector<HTMLElement>('.sw-list__item.is-active')
      ?.scrollIntoView({ block: 'nearest' })
  })
}

/* ── 三个动作 ───────────────────────────────────────────────────────── */

async function doCopy(it: PromptItem | null) {
  if (!it) return
  if (!hosted) {
    setStatus(`（预览）已复制「${it.title}」`)
    return
  }
  try {
    const r = await copyPrompt(it.path)
    // 成功 = 窗口立刻收起（复制是高频动作：一发拿到就走，接着 Ctrl+V）。
    // AHK 侧已经用 ToolTip 在鼠标旁确认过，这里不必再说什么。
    if (r === 'ok') await closePrompt()
    else setStatus(r.replace(/^err:/, ''))
  } catch (e) {
    await logPrompt('复制失败：' + String(e))
    setStatus('复制失败（详见 _error.log）')
  }
}

async function doEdit(it: PromptItem | null) {
  if (!hosted) {
    setStatus('（预览）编辑窗只在真机里开')
    return
  }
  try {
    const r = await editPrompt(it?.path ?? '')
    if (r !== 'ok') setStatus(r.replace(/^err:/, ''))
  } catch (e) {
    await logPrompt('打开编辑窗失败：' + String(e))
    setStatus('打开编辑窗失败（详见 _error.log）')
  }
}

/* ── 给 AHK 的入口 ──────────────────────────────────────────────────────
   PromptWindowFeature / 模块热键用 Eval 调这几个：
     window.__swprompt.reload()        重拉（F5 / 保存后 / 删除后 / 每次呼出）
     window.__swprompt.status(msg)     状态行显示一句，4 秒回落
     window.__swprompt.editSelected()  编辑当前选中的那一条（Enter）
   ⚠ 名字改了两边一起改：AHK 侧写死在 WebHostService.Eval 的字符串里。 */
;(window as unknown as Record<string, unknown>).__swprompt = {
  reload: () => load(),
  status: (m: unknown) => setStatus(String(m ?? '')),
  editSelected: () => doEdit(cur.value),
}

/* ── 启动 ─────────────────────────────────────────────────────────────
   ⚠ 主题要在页面这边再拉一次：AHK 建窗时推过一次，但那时页面还没就绪
   （见 WebWindow.ApplyTheme 的注释）。 */
onMounted(async () => {
  lib.value = await getLib()
  await load(true)
  if (!hosted) return
  try {
    const raw = await ahkCall<string>('getTheme')
    if (raw) applyTheme(JSON.parse(raw) as Theme)
  } catch {
    /* 用 CSS 默认色板，不影响功能 */
  }
})
</script>

<template>
  <!-- ↑↓ 绑在根上：焦点在搜索框时也能移动列表选中（AHK 没给这两个键注册热键） -->
  <div class="pv" @keydown.down.prevent="move(1)" @keydown.up.prevent="move(-1)">
    <div class="pv-tool">
      <button class="pv-tab" :class="{ on: lib === 'prompts' }" type="button" @click="doSwitch('prompts')">提示词</button>
      <button class="pv-tab" :class="{ on: lib === 'skills' }" type="button" @click="doSwitch('skills')">Skill</button>
      <input
        ref="searchRef"
        v-model="kw"
        class="pv-search"
        type="text"
        placeholder="搜标题或分类…"
        spellcheck="false"
      />
      <button class="pv-new" type="button" @click="doEdit(null)">新建</button>
    </div>

    <!-- 整行可点；双击 = 复制并收窗（复制是高频动作，改内容才按 Enter） -->
    <div class="pv-list sw-list">
      <button
        v-for="it in shown"
        :key="it.path"
        type="button"
        class="pv-item sw-list__item"
        :class="{ on: it.path === cur?.path, 'is-active': it.path === cur?.path }"
        :data-tip="it.path"
        @click="sel = it.path"
        @dblclick="doCopy(it)"
      >
        <span class="pv-cat" :class="{ none: !it.category }">{{ it.category || '未分类' }}</span>
        <span class="pv-title">{{ it.title }}</span>
        <span class="pv-sum">{{ it.summary }}</span>
      </button>

      <!-- ⚠ 顺序有意义：读取中 → 读取失败 → 空 / 无匹配。
           原来「空」排在「读取中」前面，加载那一瞬会先闪一句「还没有提示词」。 -->
      <div v-if="loading && !shown.length" class="pv-empty">读取中…</div>
      <div v-else-if="loadFailed && !shown.length" class="pv-empty">
        读取提示词目录失败 —— 详见 _error.log，按 F5 重试
      </div>
      <div v-else-if="!shown.length" class="pv-empty">
        {{ items.length ? '没有匹配的条目' : '还没有提示词 —— 点「新建」写第一条' }}
      </div>
    </div>

    <div class="pv-foot">{{ footText }}</div>
  </div>
</template>

<style scoped>
/* 整页三块：工具条 / 列表（唯一可滚）/ 状态行。
   不写死高度 —— 窗口尺寸变了也不会出现「列表盖住状态行」。 */
.pv {
  /* 板外留边。⚠ 同时被 height 与 margin 使用 —— 改这一处，板的大小与位置一起动。 */
  --pv-pad: 18px;
  position: relative;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  /* 板内留白（与外留边分开：margin 是「板外那圈光」，padding 是「板内边距」） */
  height: calc(100vh - var(--pv-pad) * 2);
  margin: var(--pv-pad);
  padding: 14px 16px 10px;
  gap: 10px;
  overflow: hidden;
  color: var(--sw-fg);
  font-size: 13px;
}

.pv-tool {
  flex: none;
  display: flex;
  gap: 8px;
}

.pv-search {
  flex: 1;
  min-width: 0;
  height: 34px;
  padding: 0 11px;
  border: 1px solid var(--sw-border);
  border-radius: 10px;
  /* 下沉表面：内影给「凹进去」的暗示，与面板的输入框同一口径 */
  background: var(--sw-code-bg);
  box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.18);
  color: var(--sw-fg);
  font: inherit;
  outline: none;
  transition:
    border-color var(--sw-dur-fast) var(--sw-ease),
    box-shadow var(--sw-dur-fast) var(--sw-ease);
}

.pv-search::placeholder {
  color: var(--sw-dim);
}

.pv-search:focus {
  border-color: var(--sw-accent);
  box-shadow:
    inset 0 1px 2px rgba(0, 0, 0, 0.18),
    0 0 0 3px var(--sw-ring);
}

.pv-new {
  flex: none;
  height: 34px;
  padding: 0 15px;
  border: 1px solid var(--sw-border);
  border-radius: 10px;
  /* 凸起：上亮下暗的渐变 —— 与面板的键帽同一套“实体感” */
  background: linear-gradient(180deg,
    rgba(255, 255, 255, 0.1),
    rgba(255, 255, 255, 0.028));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.24),
    0 1px 2px rgba(0, 0, 0, 0.18);
  color: var(--sw-fg);
  font: inherit;
  cursor: pointer;
  transition:
    border-color var(--sw-dur-fast) var(--sw-ease),
    transform var(--sw-dur-fast) var(--sw-ease-out);
}

.pv-new:hover {
  border-color: var(--sw-accent);
}

.pv-new:active {
  transform: translateY(1px);
  box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.24);
}

/* 列表撑满剩余高度，只有它滚（gap 由 glass.css 的 .sw-list 给） */
.pv-list {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
}

/* 三列：分类 / 标题 / 摘要 —— 与改造前 ListView 的 110/180/270 同一个信息顺序 */
.pv-item {
  display: grid;
  grid-template-columns: 96px 132px 1fr;
  align-items: baseline;
  gap: 10px;
  width: 100%;
  border: 1px solid transparent;
  background: transparent;
  color: var(--sw-fg);
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.pv-item:hover {
  background: var(--sw-code-bg);
}

.pv-item.on {
  background: var(--sw-code-bg);
  border-color: var(--sw-border);
}

.pv-cat,
.pv-title,
.pv-sum {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pv-cat {
  font-size: 11px;
  color: var(--sw-accent);
}

/* 根目录下的条目：分类写「未分类」并压暗，比留白更明确 */
.pv-cat.none {
  color: var(--sw-dim);
}

.pv-title {
  font-weight: 600;
}

.pv-sum {
  font-size: 12px;
  color: var(--sw-dim);
}

.pv-empty {
  padding: 28px 0;
  text-align: center;
  font-size: 12px;
  color: var(--sw-dim);
}

.pv-foot {
  flex: none;
  /* 状态行与列表分开：一条分隔线 + 8px —— 没有它，这行字就漂在列表底下，
     内容多时读起来像是列表的最后一条。 */
  margin-top: 2px;
  padding: 8px 2px 0;
  border-top: 1px solid var(--sw-border);
  font-size: 12px;
  color: var(--sw-dim);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>

