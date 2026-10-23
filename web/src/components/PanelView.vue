<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  isHosted,
  ahkCall,
  applyTheme,
  applySettings,
  fetchPanel,
  markReady,
  type PanelData,
  type PanelRow,
  type Theme,
} from '../ahk'

/* ═══════════════════════════════════════════════════════════════════════
   工作台面板（Alt+S）—— 原 WorkBenchUI 的 WebView2 版

   · 平台只给数据（rows = 「全部热键」视图 + 各模块，各自带热键与可选的
     设置声明），这个组件只负责「摆」。加模块、改布局都不用来这里改。
   · 整份数据一次取完，切页是纯前端行为；只有「保存 / 浏览」会回 AHK 一趟。
   · 原生版换主题要关窗重开（30+ 个控件逐块上色比重建还慢），这里换主题
     只换 CSS 变量，**停在哪页保持不变**。
   ═══════════════════════════════════════════════════════════════════════ */

const hosted = isHosted()

const data = ref<PanelData | null>(null)
const currentId = ref('')
/** 当前页设置字段的编辑值：field.key → 值（与 spec.fields 一一对应） */
const vals = ref<Record<string, string>>({})
const status = ref('')
const statusKind = ref<'dim' | 'ok' | 'err' | 'warn'>('dim')
const saveText = ref('保存设置')
const busy = ref(false)

const rows = computed<PanelRow[]>(() => data.value?.rows ?? [])
const cur = computed<PanelRow | null>(
  () => rows.value.find((r) => r.id === currentId.value) ?? rows.value[0] ?? null,
)

/* ── 浏览器预览的示例数据 ─────────────────────────────────────────────
   `npm run dev` 里没有 hostObjects。留一份最小的样子，调样式时不必每次起 AHK。
   数值刻意写得像真的（条数、失败态、folder 字段都覆盖到）。 */
const MOCK: PanelData = {
  app: 'SevenWork',
  version: 'dev',
  vault: 'D:\\Notes',
  total: 4,
  modules: 1,
  focus: '',
  rows: [
    {
      id: '__all',
      kind: 'view',
      name: '全部热键',
      desc: '所有模块的热键汇总 · 按分组排列',
      count: 4,
      failed: false,
      groups: [
        {
          name: '平台',
          items: [
            { key: 'Alt+S', label: '工作台面板（帮助 + 设置）' },
            { key: 'Alt+T', label: '循环切换界面主题' },
          ],
        },
        { name: '窗口', items: [{ key: 'Alt+Z', label: '呼出 / 隐藏' }] },
        { name: '日期与标签', items: [{ key: 'Alt+↑', label: '前一天' }] },
      ],
      spec: null,
    },
    {
      id: 'Folders',
      kind: 'module',
      name: '文件夹',
      desc: '三个槽位指向的目录 · Alt+1…3',
      count: 1,
      failed: false,
      hotkeys: [{ key: 'Alt+1', label: '呼出 / 隐藏槽位 1 的文件夹' }],
      spec: {
        title: '文件夹槽位',
        hint: '热键固定，指向哪个目录可以随时换；留空表示该槽位未启用。',
        hasApply: true,
        fields: [
          { key: 'Slot1', label: 'Alt+1 →', kind: 'folder', value: 'D:\\Work', placeholder: '' },
          { key: 'Slot2', label: 'Alt+2 →', kind: 'folder', value: '', placeholder: '未启用' },
        ],
      },
    },
  ],
}


/* ── 数据 ───────────────────────────────────────────────────────────── */
function pickValues(row: PanelRow | null) {
  const out: Record<string, string> = {}
  for (const f of row?.spec?.fields ?? []) out[f.key] = f.value ?? ''
  vals.value = out
}

function setStatus(text: string, kind: typeof statusKind.value = 'dim') {
  status.value = text
  statusKind.value = kind
}

/** 切页：鼠标点 / 上下键 / AHK 的 goto 都走这里 —— 只留一条路径就不会有半更新状态 */
function goto(id: string) {
  if (!id || id === currentId.value) return
  currentId.value = id
  pickValues(cur.value)
  setStatus('', 'dim')
}

/**
 * 拉一次全量。first = 首屏：按 AHK 给的 focus 定位（ShowHelp(id) 记下的目标页），
 * 否则保留当前页 —— 保存后回读不该把用户甩回第一页。
 */
async function load(first = false) {
  let d: PanelData | null = null
  if (hosted) {
    try {
      d = await fetchPanel()
    } catch (e) {
      setStatus('读取面板数据失败：' + String(e), 'err')
      markReady() // 失败态同样「落定」—— 得让人看见这行红字
      return
    }
  } else {
    d = MOCK
  }
  if (!d) {
    setStatus('AHK 没有返回面板数据（见 %AppData%\\SevenWork\\_error.log）', 'err')
    markReady()
    return
  }
  data.value = d

  const want = first ? d.focus : currentId.value
  const hit = d.rows.find((r) => r.id === want)
  currentId.value = (hit ?? d.rows[0])?.id ?? ''
  pickValues(cur.value)
  saveText.value = '保存设置'
  busy.value = false
  // 首屏数据已落定 → 放行 AHK 的入场（见 ahk.ts 的 markReady 说明）。
  // 放在最后一行：数据没到就喊就绪，等于让入场从空壳开始淡入。
  markReady()
}

/* ── 保存：三段反馈（保存设置 → 保存中… → ✓ / ✗）──────────────────────
   ⚠ 值按 fields 的声明顺序送，applySettings 负责补满 8 个槽位 ——
     AHK 侧是固定 8 个形参（原因见 PanelHostBridge.ahk 里 PanelHostApply 上方）。 */
async function save() {
  const row = cur.value
  if (!row?.spec?.hasApply || busy.value) return
  const values = (row.spec.fields ?? []).map((f) => vals.value[f.key] ?? '')

  busy.value = true
  saveText.value = '保存中…'

  try {
    if (!hosted) {
      setStatus('（浏览器预览）不落盘：' + values.filter(Boolean).join(' · '), 'ok')
      saveText.value = '✓ 已保存'
      return
    }
    const r = await applySettings(row.id, values)
    if (r === 'ok') {
      // 回读：模块可能在 apply 里把值规整过（去尾斜杠 / 空串归一），
      // 不回读的话输入框里还是用户刚敲的原始样子。
      await load()
      setStatus('✓ 已保存，下次按热键即生效', 'ok')
      saveText.value = '✓ 已保存'
    } else {
      setStatus('保存失败：' + r.replace(/^err:/, ''), 'err')
      saveText.value = '✗ 失败'
    }
  } catch (e) {
    setStatus('保存失败：' + String(e), 'err')
    saveText.value = '✗ 失败'
  } finally {
    busy.value = false
    setTimeout(() => {
      saveText.value = '保存设置'
    }, 1200)
  }
}

/* ── 浏览文件夹：交给 AHK 的 DirSelect（网页 <input type=file> 拿不到目录路径）*/
async function browse(fieldKey: string) {
  if (!hosted) {
    setStatus('（浏览器预览）选不了文件夹', 'warn')
    return
  }
  setStatus('正在选择文件夹…', 'dim')
  try {
    const sel = await ahkCall<string>('browse', vals.value[fieldKey] ?? '')
    if (!sel) {
      setStatus('已取消，输入框保持原值', 'dim')
      return
    }
    vals.value[fieldKey] = sel
    // 只回填输入框，很多人会以为已经生效了 —— 明确说一句
    setStatus('已选择，记得点「保存设置」', 'warn')
  } catch (e) {
    setStatus('打不开文件夹选择框：' + String(e), 'err')
  }
}

function closePanel() {
  if (hosted) ahkCall('close').catch(() => {})
}

/* ── 键盘上下切页（照原生 ListView 的习惯）────────────────────────────
   ⚠ 焦点在输入框里时不抢键：那里上下键该走光标 / 补全。 */
function onKeydown(e: KeyboardEvent) {
  const t = e.target as HTMLElement | null
  if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA')) return
  const i = rows.value.findIndex((r) => r.id === currentId.value)
  if (i < 0) return
  if (e.key === 'ArrowDown' && i + 1 < rows.value.length) {
    e.preventDefault()
    goto(rows.value[i + 1].id)
  } else if (e.key === 'ArrowUp' && i > 0) {
    e.preventDefault()
    goto(rows.value[i - 1].id)
  }
}

/* ── 未保存检测：退出时 AHK 会 Eval 这里，判断「面板里有没有改了没保存的设置」──
   ⚠ 必须**纯前端**完成（只比较内存里的编辑值与 spec 带回的原值），
     绝不能再回调 hostObjects —— 这条路径跑在 AHK 的退出流程里，
     一次跨进程等待就足以让退出卡住。
   ⚠ 只有带 apply 的页才有「保存」语义；热键页没有可改的值，直接算未改。 */
function hasPending(): boolean {
  const row = cur.value
  if (!row?.spec?.hasApply) return false
  return (row.spec.fields ?? []).some(
    (f) => (vals.value[f.key] ?? '') !== (f.value ?? ''),
  )
}

onMounted(async () => {
  window.addEventListener('keydown', onKeydown)

  // AHK 侧面板已经开着时再按 Alt+S（或某个模块请求「打开我这一页」）：
  // ShowHelp 会 Eval('__swpanel.goto(id)')。挂在这里而不是模板里 ——
  // Eval 的字符串碰不到模块作用域（同 main.ts 的 __sevenwork）。
  // hasPending 由退出流程调用（Alt+Shift+S），没有它就只能当「没有改动」。
  ;(window as any).__swpanel = { goto, hasPending }

  // 主题：AHK 推送优先，拿不到就用 CSS 里的默认值（npm run dev 时走这条）
  if (hosted) {
    try {
      const raw = await ahkCall<string>('getTheme')
      if (raw) applyTheme(JSON.parse(raw) as Theme)
    } catch {
      /* 主题是锦上添花，拿不到不该挡住面板 */
    }
  }

  await load(true)
})
</script>

<template>
  <div class="panel">
    <!-- ═══ 左：导航 ═══ 名称 / 条数两列 —— 后端一个数字也能告诉用户「这页有多少内容」 -->
    <aside class="pnav sw-plate">
      <div class="pbrand">
        <span class="pdot" />
        <span class="papp">{{ data?.app ?? 'SevenWork' }}</span>
        <span class="pver">v{{ data?.version ?? '?' }}</span>
      </div>

      <nav class="plist">
        <button
          v-for="row in rows"
          :key="row.id"
          class="pitem"
          :class="{ on: row.id === cur?.id, bad: row.failed }"
          @click="goto(row.id)"
        >
          <span class="pitem-name">
            <span v-if="row.kind === 'view'" class="pmark">≡</span>{{ row.name }}
          </span>
          <span class="pitem-count">{{ row.count }}</span>
        </button>
      </nav>

      <div class="pfoot">
        {{ data?.modules ?? 0 }} 个模块 · 共 {{ data?.total ?? 0 }} 条热键
      </div>
    </aside>

    <!-- ═══ 右：内容 ═══ -->
    <section class="pmain sw-plate">
      <header class="phead">
        <h1>{{ cur?.name ?? '工作台' }}</h1>
        <p class="sub">{{ cur?.desc }}</p>
      </header>

      <div class="pbody">
        <!-- ⚠ 用 :key 让切页时**整块重建**：这是让 CSS 入场动画重新播放的唯一干净办法
             （同一个 DOM 上换内容，animation 不会重跑）。代价只有滚动位置重置 ——
             切页本来就该回到顶部，不算损失。输入值存在 vals 里，不随 DOM 丢。 -->
        <div :key="cur?.id" class="pbody-in">
        <!-- 视图页按分组；模块页平铺（模块通常只占 1~2 组，再分组只会把两行字拆成三块） -->
        <template v-if="cur?.kind === 'view'">
          <section v-for="g in cur.groups ?? []" :key="g.name" class="pgroup">
            <div class="pglabel">{{ g.name }}</div>
            <div v-for="(hk, i) in g.items" :key="g.name + '-' + i" class="prow">
              <code class="pkey">{{ hk.key }}</code>
              <span class="plabel">{{ hk.label }}</span>
              <span v-if="hk.note" class="pnote">{{ hk.note }}</span>
            </div>
          </section>
        </template>

        <template v-else>
          <p v-if="cur?.failed" class="pwarn">
            该模块启动失败，热键一条都没注册。详情见 .logs\_error.log，修复后重启程序即可
            —— 其它模块不受影响。
          </p>
          <p v-else-if="!(cur?.hotkeys ?? []).length" class="pempty">（该模块没有热键）</p>
          <div v-for="(hk, i) in cur?.hotkeys ?? []" :key="i" class="prow">
            <code class="pkey">{{ hk.key }}</code>
            <span class="plabel">{{ hk.label }}</span>
            <span v-if="hk.note" class="pnote">{{ hk.note }}</span>
          </div>
        </template>

        <!-- 设置区：模块自己声明才有（平台只认 {label, kind, value}，不认识业务名词）-->
        <section v-if="cur?.spec" class="pspec">
          <div class="psptitle">{{ cur.spec.title }}</div>
          <p class="psphint">{{ cur.spec.hint }}</p>
          <div v-for="f in cur.spec.fields ?? []" :key="f.key" class="pfield">
            <label class="pf-label">{{ f.label }}</label>

            <!-- 下拉：值即显示，不需要 id→label 映射（模块也不必维护两份表） -->
            <select
              v-if="f.kind === 'select'"
              v-model="vals[f.key]"
              class="sw-input pf-select"
            >
              <option v-for="o in f.options ?? []" :key="o" :value="o">{{ o }}</option>
            </select>

            <!-- 滑杆：数字同步显示在右侧 —— 只看滑杆位置根本不知道「现在是几」 -->
            <template v-else-if="f.kind === 'range'">
              <input
                v-model="vals[f.key]"
                class="pf-range"
                type="range"
                :min="f.min || '0'"
                :max="f.max || '100'"
                :step="f.step || '1'"
              />
              <span class="pf-num">{{ vals[f.key] }}{{ f.unit }}</span>
            </template>

            <template v-else>
              <input
                v-model="vals[f.key]"
                class="sw-input pf-input"
                :placeholder="f.placeholder"
                spellcheck="false"
                @keydown.enter="save"
              />
              <button
                v-if="f.kind === 'folder'"
                class="sw-btn sw-btn--ghost pf-browse"
                @click="browse(f.key)"
              >
                浏览…
              </button>
            </template>
          </div>
        </section>
        <p v-else-if="cur?.kind === 'module' && !cur?.failed" class="pempty">
          该模块没有可调设置 —— 参数是写死的（或由它自己的窗口管），上面的热键随时可用。
        </p>
        </div>
      </div>

      <!-- 底栏：状态 + 笔记目录 + 操作。没有它，按钮就「浮在空气里」 -->
      <footer class="pfoot2">
        <span class="pstatus" :class="statusKind">{{ status }}</span>
        <span class="pvault" :title="data?.vault">{{ data?.vault }}</span>
        <button
          v-if="cur?.spec?.hasApply"
          class="sw-btn sw-btn--primary"
          :disabled="busy"
          @click="save"
        >
          {{ saveText }}
        </button>
        <button class="sw-btn sw-btn--ghost" @click="closePanel">关闭</button>
      </footer>
    </section>
  </div>
</template>

<style scoped>
/* ═══ 骨架 ═══════════════════════════════════════════════════════════
   两块「板」，中间留缝，四周留边 —— 板外留边才有玻璃感（满窗均匀柔光 =
   又变回一块深色主题，这是 S1 踩过的坑）。
   材质（背景 / 模糊 / 边框 / 反光）归 glass.css，这里只摆结构。 */
.panel {
  height: 100%;
  box-sizing: border-box;
  /* 18px 留边 + 16px 板缝：玻璃感全靠「板外那一圈」——
     14px 在 150% 缩放下只有 21 物理像素，光场几乎没地方落，
     整窗看起来就是「两块深色方块拼在一起」。 */
  padding: 18px;
  display: grid;
  grid-template-columns: 216px minmax(0, 1fr);
  /* ⚠ 必须显式声明行高：不写的话行是 auto，会被「全部热键」那一长串内容撑开，
     于是 .pmain 比容器还高 —— 内部的 flex:1 也就失去约束，正文溢出到底栏下面。
     表现很有迷惑性：滚动条在、底栏也在，只是底部两三行永远被底栏压住。
     minmax(0, 1fr) 而不是 1fr：0 的下限才允许子项收缩到比内容更小（配合 min-height:0）。 */
  grid-template-rows: minmax(0, 1fr);
  gap: 16px;
}

.pnav,
.pmain {
  min-height: 0;
  overflow: hidden;
  /* 14 → 16px：板越大，圆角要跟着大一点才不像「切了角的正方形」。
     ⚠ 与 .sw-plate 的 border-radius 必须一致，否则 conic 环边会偏出去一圈。 */
  border-radius: 16px;
  /* 兜底底色：glass 主题下由 glass.css 的 rgba + backdrop-filter 盖掉
     （specificity 0,2,1 > 这里的 0,2,0）。非 glass / npm run dev 时靠它分层。 */
  background: var(--sw-bg-alt);
}

.pnav {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 12px 12px;
}

.pmain {
  display: flex;
  flex-direction: column;
}

/* ═══ 左：品牌 + 导航 ═══════════════════════════════════════════════ */
.pbrand {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 6px;
  font-size: 13px;
  font-weight: 600;
}

.pdot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--sw-accent);
  flex: none;
  /* 一个小光源：没有它，「SevenWork」只是一个词；有了它就是这块板的品牌灯。
     ⚠ 只给这一点点外发光 —— 全站只有这一个装饰性光源，多了就廉价。 */
  box-shadow:
    0 0 0 3px rgba(255, 255, 255, 0.055),
    0 0 10px rgba(255, 255, 255, 0.42);
}

.papp {
  flex: 1;
  letter-spacing: 0.02em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pver {
  flex: none;
  font-size: 11px;
  font-weight: 400;
  color: var(--sw-dim);
}

.plist {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.pitem {
  position: relative;
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 7px 10px;
  border: 1px solid transparent;
  border-radius: 8px;
  background: transparent;
  color: var(--sw-fg);
  font: inherit;
  font-size: 13px;
  text-align: left;
  cursor: pointer;
  /* box-shadow 也要过渡：选中态的左侧光条是 box-shadow 画的，
     漏了它就会出现「底色渐入、光条瞬现」的半截动画。 */
  transition:
    background 140ms ease,
    border-color 140ms ease,
    box-shadow 140ms ease;
}

/* ⚠ 悬停 / 选中一律用**半透明白**，不用 var(--sw-bg)：
   后者是实色 #2E2E2E，铺在玻璃板上就是一块实心深灰补丁 —— 玻璃感当场消失。
   半透明白会跟板后的光一起走，选中态才像「玻璃上高亮了一块」。 */
.pitem:hover:not(.on) {
  background: rgba(255, 255, 255, 0.045);
}

.pitem.on {
  /* 选中 = 「这块玻璃被照亮了一格」：横向渐弱的白 + 顶部受光 + 左侧光条。
     ⚠ 别用实色底（var--sw-bg 是 #2E2E2E，铺上去就是一块补丁，玻璃感当场没了）。
     ⚠ 底下的 -4px 阴影是「贴住板面」的那点接触影，去掉会显得浮起来。 */
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0.115) 0%,
    rgba(255, 255, 255, 0.06) 58%,
    rgba(255, 255, 255, 0.03) 100%
  );
  border-color: rgba(255, 255, 255, 0.1);
  font-weight: 600;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.16),
    0 2px 10px -4px rgba(0, 0, 0, 0.35);
}

/* 左沿光条单独做成伪元素，而不是 box-shadow 的 inset ——
   只有独立元素才能**展开**：切页时从 30% 高度长到满高（180ms），
   眼睛会跟着它走，「换到哪一页」是看出来的，不是找出来的。
   ⚠ 用 scaleY 而不是 height：走合成层，不触发布局。 */
.pitem.on::before {
  content: "";
  position: absolute;
  left: 0;
  top: 5px;
  bottom: 5px;
  width: 2px;
  border-radius: 2px;
  background: var(--sw-accent);
  transform-origin: center;
  animation: pbar 180ms cubic-bezier(0.2, 0.9, 0.2, 1) both;
}

@keyframes pbar {
  from {
    transform: scaleY(0.25);
    opacity: 0.35;
  }
  to {
    transform: scaleY(1);
    opacity: 1;
  }
}

/* 切页入场：整块内容轻微上浮 + 淡入。180ms / 4px ——
   再久就是在等动画，再深就是在抖。 */
.pbody-in {
  animation: pin 180ms cubic-bezier(0.2, 0.9, 0.2, 1) both;
}

@keyframes pin {
  from {
    opacity: 0;
    transform: translateY(4px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

@media (prefers-reduced-motion: reduce) {
  .pitem.on::before,
  .pbody-in {
    animation: none;
  }
}

/* 启动失败的模块：仍占一行，靠亮度下沉 + 「(失败)」两字提示。
   ⚠ v2.13 去色后这里不再是红色 —— 全站只剩明度层次，识别靠文字不靠色相。 */
.pitem.bad .pitem-name {
  color: var(--sw-dim);
}

.pitem-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pitem-count {
  flex: none;
  font-size: 11px;
  color: var(--sw-dim);
  font-variant-numeric: tabular-nums;
}

.pmark {
  margin-right: 6px;
  opacity: 0.8;
}

.pfoot {
  flex: none;
  padding: 8px 6px 0;
  border-top: 1px solid var(--sw-border);
  font-size: 11px;
  color: var(--sw-dim);
}

/* ═══ 右：页眉 / 正文 ═══════════════════════════════════════════════
   页眉回答「我在哪一页」，副标题回答「这一页是干什么的」。拆两级而不是挤成
   一行 —— 一行里两种字号层级就没了（.clinerules/02「面板布局」）。 */
.phead {
  position: relative;
  flex: none;
  padding: 18px 22px 14px;
}

/* 页眉的分隔线：**渐隐**，不是整条实线。
   ⚠ 实线（1px var(--sw-border)）横贯整块板，会把这页切成上下两张表；
     从正文左边缘起、向右淡出，才像「光落在板面上的一条折痕」。 */
.phead::after {
  content: "";
  position: absolute;
  left: 22px;
  right: 22px;
  bottom: 0;
  height: 1px;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0.17) 0%,
    rgba(255, 255, 255, 0.05) 62%,
    transparent 100%
  );
  pointer-events: none;
}

.phead h1 {
  margin: 0 0 4px;
  /* 18px → 24px：页标题是整块内容板的「视觉锚点」，18px 在 940px 宽的面板里
     只比正文大一号，标题层级读不出来，整页看着就像一张表格。
     ⚠ 负字距是配合大字号用的（大字母间距天然显松），别拿去套小字。 */
  font-size: 24px;
  font-weight: 600;
  letter-spacing: -0.015em;
  line-height: 1.25;
}

.phead .sub {
  margin: 0;
  font-size: 12px;
  color: var(--sw-dim);
}

.pbody {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  padding: 14px 22px 18px;
}

.pgroup + .pgroup {
  margin-top: 16px;
}

/* 分组标签：标签 + 一条渐隐的细线。
   线不是装饰 —— 一屏几十条热键，光靠 11px 小字分组，眼睛分不开段；
   一条从标签后延伸出去、渐隐收尾的线能把分组切开，又不至于像表格边框。 */
.pglabel {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 6px;
  padding-left: 2px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.08em;
  color: var(--sw-dim);
}

.pglabel::after {
  content: "";
  flex: 1;
  height: 1px;
  /* ⚠ 不用 var(--sw-border)：那是 0.14 的白，压在玻璃板上几乎看不见，
     整条线等于白画。0.09 的纯白在深底上刚好「有但不抢」。 */
  background: linear-gradient(90deg, rgba(255, 255, 255, 0.09), transparent);
}

/* 一条热键：键名 / 说明两栏。键名定宽 —— 说明从左边缘对齐才扫得快 */
.prow {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 6px 10px;
  border-radius: 8px;
  transition: background 120ms ease;
}

/* ⚠ 半透明白，不用 var(--sw-bg)：后者是实色 #2E2E2E，
   铺在玻璃板上就是一块实心深灰补丁（与 .pitem 同一个坑）。 */
.prow:hover {
  background: rgba(255, 255, 255, 0.035);
}

/* 键帽：一块真正的「按键」而不是一行等宽字。
   宽度写死（不是 min-width）—— 说明列的左边缘必须严格对齐，否则一屏扫下来参差不齐。
   ⚠ 100px 是「最长键名 + 呼吸」的实测下限：本项目最长是 Alt+Shift+C（12px 等宽 ≈ 79px），
     留 21px 富余；再宽（原来的 118）键帽右侧会空出 40px，说明列被推远、整屏发散。 */
.pkey {
  flex: none;
  display: block;
  box-sizing: border-box;
  width: 100px;
  padding: 2px 0;
  border-radius: 5px;
  /* 键帽要**凸起**：上亮下暗 + 一点向下投影。
     ⚠ 原来是单一 rgba(.035) + 一圈 inset 环，读起来是「一个浅色矩形」；
       这块面板上每一行都有一个，平了就整屏像表格。 */
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.07), rgba(255, 255, 255, 0.022));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.1),
    inset 0 -1px 0 rgba(0, 0, 0, 0.24),
    0 1px 2px rgba(0, 0, 0, 0.2);
  font-family: ui-monospace, Consolas, 'Courier New', monospace;
  font-size: 12px;
  line-height: 1.45;
  color: var(--sw-accent);
  text-align: center;
  white-space: nowrap;
}

.plabel {
  flex: 1;
  min-width: 0;
  font-size: 13px;
}

.pnote {
  flex: none;
  font-size: 11px;
  color: var(--sw-dim);
}

/* 提示块：v2.13 去色，不再是红色 —— 左侧 2px 亮边 + 略亮的底替代色相提示 */
.pwarn {
  margin: 0 0 14px;
  padding: 10px 12px;
  border: 1px solid var(--sw-border);
  border-left: 2px solid var(--sw-fg);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.05);
  color: var(--sw-fg);
  font-size: 12px;
  line-height: 1.7;
}

.pempty {
  margin: 0 0 12px;
  color: var(--sw-dim);
  font-size: 12px;
  line-height: 1.7;
}

/* ═══ 设置区 ═══════════════════════════════════════════════════════ */
.pspec {
  margin-top: 20px;
  padding-top: 16px;
  border-top: 1px solid var(--sw-border);
}

.psptitle {
  margin-bottom: 4px;
  font-size: 14px;
  font-weight: 600;
}

.psphint {
  margin: 0 0 12px;
  color: var(--sw-dim);
  font-size: 12px;
  line-height: 1.7;
}

.pfield {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.pf-label {
  flex: none;
  width: 96px;
  color: var(--sw-dim);
  font-size: 12px;
}

/* 路径用等宽字体：比例字体下 "l" 与 "1"、"/" 与 "\" 几乎分不清 */
.pf-input {
  flex: 1;
  min-width: 0;
  font-family: ui-monospace, Consolas, 'Courier New', monospace;
  font-size: 12px;
}

.pf-browse {
  flex: none;
}

/* 下拉：外形跟输入框一致，但**不用等宽字体** —— .pf-input 那一档是给路径的 */
.pf-select {
  flex: 1;
  min-width: 0;
  cursor: pointer;
  font-family: inherit;
  font-size: 12px;
}

/* 滑杆：浏览器默认样式在深色底上几乎看不见（轨道是浅灰、拇指是白方块），
   所以只保留原生交互、把颜色交给 --sw-accent —— 自己画滑块会把键盘可达性
   一起丢掉（原生 range 本来就支持方向键、Home/End）。 */
.pf-range {
  flex: 1;
  min-width: 0;
  height: 18px;
  accent-color: var(--sw-accent);
  cursor: pointer;
}

/* 右侧数值：定宽 + tabular-nums，拖动时数字不会左右抖 */
.pf-num {
  flex: none;
  min-width: 44px;
  text-align: right;
  color: var(--sw-dim);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

/* ═══ 底栏 ═══════════════════════════════════════════════════════════
   状态 + 笔记目录 + 按钮一条带子收住页尾；没有它按钮就「浮在空气里」。 */
.pfoot2 {
  flex: none;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 22px;
  /* 底栏是板内**下沉**的一格：上面一层淡光、下面压暗。
     ⚠ 原来是单一 rgba(0,0,0,.16)，读起来只是「深一点的横条」；
       给个垂直走向 + 顶部一道内影，正文滚到底时才像被这条带子收住。 */
  border-top: 1px solid rgba(255, 255, 255, 0.07);
  background: linear-gradient(180deg, rgba(0, 0, 0, 0.1), rgba(0, 0, 0, 0.24));
  box-shadow: inset 0 1px 0 rgba(0, 0, 0, 0.2);
}

/* 语义三态：绿 = 成、红 = 败、琥珀 = 提醒。弱了就等于没反馈 */
.pstatus {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 600;
  color: var(--sw-dim);
}

/* 三态去色后靠「正常 / 更亮更粗 / 暗一档」分层。
   ⚠ 可辨识性本来就不靠色相：每条状态都自带 ✓ / 「保存失败：」这类文字前缀
     （见 setStatus 的调用点），色相只是锦上添花 —— 这里换成明度差。 */
.pstatus.ok {
  color: var(--sw-fg);
}

.pstatus.err {
  color: #ffffff;
  font-weight: 700;
}

.pstatus.warn {
  color: var(--sw-dim);
}

.pvault {
  flex: none;
  max-width: 40%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--sw-dim);
  font-size: 11px;
}

/* 保存中 / 保存完成时禁用，防止连点两次写两遍 */
.pfoot2 button:disabled {
  opacity: 0.55;
  cursor: default;
}
</style>
