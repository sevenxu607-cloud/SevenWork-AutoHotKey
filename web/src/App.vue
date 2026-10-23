<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import NoteEditor from './components/NoteEditor.vue'
import GlassLab from './components/GlassLab.vue'
import PanelView from './components/PanelView.vue'
import PromptView from './components/PromptView.vue'
import { isHosted, ahkCall, applyTheme, markReady, type Theme } from './ahk'

/* ── 页面切换：现在是五个视图，模块化路由留到 S3 ─────────────────── */
// 支持 ?view=note 直达 —— 真机验证与将来从 AHK 唤起特定页面都用得上
// ?view=lab：材质样板（S0），浏览器里单独验收「琉璃」观感，不接 AHK
// ?view=panel：工作台面板（Alt+S），数据全部来自 AHK 的 PanelHostBridge
// ?view=prompts：提示词库（Alt+P），数据来自 Text 模块的 HostBridge
const _q = new URLSearchParams(location.search).get('view')
const view = ref<'self' | 'note' | 'lab' | 'panel' | 'prompts'>(
  _q === 'note'
    ? 'note'
    : _q === 'lab'
      ? 'lab'
      : _q === 'panel'
        ? 'panel'
        : _q === 'prompts'
          ? 'prompts'
          : 'self',
)

/* ── 自检页 ─────────────────────────────────────────────────────── */
const hosted = isHosted()
const pong = ref('—')
const ver = ref('—')
const themeName = ref('—')
const err = ref('')
const text = ref('')

/* ── 笔记页 ───────────────────────────────────────────────────────
   ⚠ **不预置任何演示内容。**
     从前这里塞了一篇「笔记编辑器 / 验证清单 / 表格」的样例，本意是构建后一眼
     能看出哪块没渲染；真机上它的实际效果是：首次载入失败、或页面被重新导航，
     屏幕上就是一整篇网页示例，而用户以为那是自己的笔记 —— 更糟的是保存链路
     会把它写进当天的 .md。要验渲染就在浏览器里 `?view=lab`，别拿真实窗口当样板。 */
const noteMd = ref('')

/** 是否已经真正载入过一篇文档（AHK 推 setMarkdown 成功后才置 true）。
 *  ⚠ 少了它，「编辑器是空的」与「还没载入」分不出来：前者该拦住保存，
 *    否则一次读取失败就能把用户那一篇覆盖成空。 */
let docLoaded = false

/* ── 底栏状态行 ──────────────────────────────────────────────────
   AHK 侧保存完会推一行过来（`__swnote.setStatus(text, kind)`）：
   已保存 HH:mm / 无改动 / 空笔记不落盘 / 保存失败：xxx。
   ⚠ 从前底栏只有字数，保存失败和「其实没存」在界面上完全看不出来 ——
     用户按完 Ctrl+S 只能靠猜。 */
const statusText = ref('')
const statusKind = ref<'ok' | 'info' | 'err'>('info')
/** 每次推状态 +1：模板用它当 key，让元素重建一次、重放「闪一下」动画。
 *  ⚠ 没有它的时候，内容没改动的保存（底栏仍写「无改动」）看起来像**按了没反应** ——
 *    文字没变，DOM 也没变。 */
const statusSeq = ref(0)
/** 状态行的自动清除定时器：旧版 StatusBar 的提示 2 秒后清空。 */
let statusTimer: ReturnType<typeof setTimeout> | undefined

/* ── 宿主（AHK）入口 ───────────────────────────────────────────────
   AHK 用 WebHostService.Eval('window.__swnote.setMarkdown("…")') 灌内容。
   Eval 和组件的 onMounted 谁先到不确定：编辑器没建好时先把值挂起来，
   @ready 之后补灌 —— 否则第一次载入会静默丢掉（画面还是演示内容）。 */
const editorRef = ref<any>()
let pendingMd = ''

/* ── 底栏元信息（日期 / 星期 / 标签）──────────────────────────────────
   对应原生版 StatusBar 的 `📅 日期 星期` 与 `🏷 标签` —— 迁移到 WebView2 后
   底栏只剩保存状态和字数，这两条丢了。
   数据由 AHK 推来（标签取决于文件名，前端判断不了）；页面挂载后再拉一次兜底。 */
const metaDate = ref('')
const metaWeekday = ref('')
const metaTag = ref('')

function setMeta(m: { date?: string; weekday?: string; tag?: string } | null): string {
  metaDate.value = String(m?.date ?? '')
  metaWeekday.value = String(m?.weekday ?? '')
  metaTag.value = String(m?.tag ?? '')
  return 'ok'
}

/* ── 底栏字数：取**纯文本**长度，不是 Markdown 长度 ────────────────────
   ⚠ `noteMd.length` 把 `# `、`**`、链接 URL 全算进去，显示出来比眼里看到的
     正文多一截（旧版 RichEdit 的字数就是纯文本长度）。
   ⚠ 每敲一个字都遍历一遍文档没必要：跟旧版一样做节流（120ms 够跟上手感）。 */
const noteChars = ref(0)
let charTimer: ReturnType<typeof setTimeout> | undefined

function refreshChars() {
  noteChars.value = Number(editorRef.value?.getTextLength?.() ?? 0)
}

function scheduleChars() {
  if (charTimer) return
  charTimer = setTimeout(() => {
    charTimer = undefined
    refreshChars()
  }, 120)
}

// 存储态一变就算一次；真正的字符数仍以编辑器里的文档为准（见 refreshChars）。
watch(noteMd, () => scheduleChars())

function onEditorReady() {
  // 编辑器建好 = 笔记视图首屏落定。⚠ 必须放在下面那个提前 return **之前** ——
  // 没有待灌内容时（打开当天的空笔记）pendingMd 是空串，早退会让 AHK 白等到超时。
  markReady()
  // 编辑器可能已经带着内容起来（比如页面重导航），字数先算一次。
  refreshChars()
  if (!pendingMd) return
  const md = pendingMd
  const r = String(editorRef.value?.setMarkdown(md))
  if (r !== 'ok') {
    // 还是没灌进去：继续挂着，等下一次 ready / AHK 重推
    ;(window as any).__swnoteLastError = 'ready: ' + r
    return
  }
  pendingMd = ''
  docLoaded = true
}

function setMarkdown(md: string): string {
  // ⚠ 必须有返回值：AHK 侧用 ExecuteScriptAsync 收结果，undefined 序列化成字符串
  //   "null"，Eval 就判成失败，整次灌入看起来没执行。
  // ⚠ 异常也要自己兜住并转成字符串 —— 抛出去的异常同样变成 "null"，
  //   只剩「脚本返回 null」这句，查不出到底是哪一步坏的。
  // ⚠ 只有返回 'ok' 才算「真的换上了」：AHK 侧据此才提交日期、才允许保存。
  try {
    noteMd.value = md
    const r = String(editorRef.value?.setMarkdown(md))
    if (r !== 'ok') {
      pendingMd = md
      return 'pending:' + r
    }
    pendingMd = ''
    docLoaded = true
    refreshChars()
    return 'ok'
  } catch (e) {
    return 'ERR ' + String(e)
  }
}

/* ── 编辑器内快捷键（v2.9：从 AHK 的 editor 上下文搬进来）──────────────
   这几条都要在光标处插字，前端拿 ProseMirror 的 transaction 一次就够；
   从前在 AHK 里对着 RichEdit 算偏移，既不准，还得维护两套状态。
   ⚠ Ctrl+S / Ctrl+G / Ctrl+Shift+T 不在这里 —— 那三条由 AHK 的 editor 上下文
     热键拦下（要碰文件与对话框），前端抢走反而打不通。
   ⚠ 监听用捕获阶段：ProseMirror 自己会处理 Tab 等键，冒泡阶段轮不到我们。 */
function onKeydown(e: KeyboardEvent) {
  if (view.value !== 'note') return
  const el = editorRef.value
  if (!el) return
  const k = e.key.toLowerCase()

  // Ctrl+T：另起一段写时间戳（旧版就是手动插入，程序从不自动补）
  if (e.ctrlKey && !e.altKey && !e.shiftKey && k === 't') {
    e.preventDefault()
    const now = new Date()
    const hh = String(now.getHours()).padStart(2, '0')
    const mm = String(now.getMinutes()).padStart(2, '0')
    // ⚠ 走 insertBlockAfter 而不是插字符串：文本节点里的 `\n` 不是换行，
    //   塞进去只会变成一段带 `🕐 HH:mm` 的普通文字，下次打开才露馅。
    el.insertBlockAfter('paragraph', `🕐 ${hh}:${mm}`)
    return
  }
  // ⚠ 这里原来还有两条：Ctrl+H 插分隔线、Ctrl+Shift+H 插「新分段」二级标题。
  //   v2.16 删除（用户 2026-10-23 反馈）：两者在 Markdown 里直接打 `---` / `## `
  //   就会即时渲染，快捷键反而多一步；「新分段」还要求先选中占位文字再改写。
  //   一个工具只保留编辑器做不到的事（输入时间戳）。
  // Tab / Shift+Tab：列表内改层级，段落内增删行首四空格
  // ⚠ 从前这里只认 Tab、不看 shiftKey —— Shift+Tab 也走进来插了四个空格，
  //   等于「反缩进」这个功能根本不存在（旧文档里曾写着有）。
  if (!e.ctrlKey && !e.altKey && e.key === 'Tab') {
    e.preventDefault()
    if (e.shiftKey) el.outdent()
    else el.indent()
  }
}

onMounted(() => {
  // 宿主入口只挂一次；重新导航页面会重建，不需要额外清理
  // ⚠ 未捕获的 Promise 拒绝在 WebView2 里完全静默（不写 console、不弹窗），
  //   而编辑器的 create() 是异步的 —— 它抛了就等于「DOM 出来了但变量是 null」
  window.addEventListener('unhandledrejection', (e: any) => {
    ;(window as any).__noteStage = 'reject: ' + String(e?.reason)
  })
  window.addEventListener('keydown', onKeydown, true)
  ;(window as any).__swnote = {
    setMarkdown,
    // ⚠ 没载入过文档就返回空串：AHK 侧把它当「这次不许存」。
    //   从前这里兜底 `?? noteMd.value` —— 首次载入失败时 noteMd 里还是那篇
    //   演示内容，于是「什么都没打开」也能被当成一次正常保存写进当天的 .md。
    getMarkdown: () => (docLoaded ? (editorRef.value?.getMarkdown() ?? noteMd.value) : ''),
    // 字数口径 = 正文纯文本长度（不含 Markdown 标记），与底栏显示同一个来源。
    getChars: () => Number(editorRef.value?.getTextLength?.() ?? 0),
    // 底栏的日期 / 星期 / 标签：AHK 侧载入、切日期、保存、改标签后推过来。
    setMeta,
    // 编辑命令也挂出来：Ctrl+T 时间戳、Tab 缩进走的就是这几个，
    // 探针与 AHK 可以直接调它验证行为，不必模拟键盘事件。
    // ⚠ insertBlockAfter 仍支持 hr / heading（通用能力），但 v2.16 起没有快捷键调用它们。
    insertBlockAfter: (kind: string, text?: string) =>
      editorRef.value?.insertBlockAfter(kind, text ?? '') ?? 'no-editor',
    indent: () => editorRef.value?.indent() ?? 'no-editor',
    outdent: () => editorRef.value?.outdent() ?? 'no-editor',
    // 保存状态：AHK 侧推过来，底栏显示。kind 只认 ok / info / err 三档。
    setStatus: (text: string, kind?: string) => {
      statusText.value = String(text ?? '')
      const k = kind === 'ok' ? 'ok' : kind === 'err' ? 'err' : 'info'
      statusKind.value = k
      statusSeq.value += 1
      // 旧版 StatusBar 的提示 2 秒后就清空（用户 2026-10-23 反馈「太死板」）。
      // ⚠ 错误**不清**：那是要用户看见的；它会被下一次操作覆盖。
      if (statusTimer) clearTimeout(statusTimer)
      statusTimer = undefined
      if (k !== 'err') {
        statusTimer = setTimeout(() => {
          statusTimer = undefined
          statusText.value = ''
        }, 2200)
      }
      return 'ok'
    },
    // 给 AHK 探针看的状态：ready = 编辑器建好，loaded = 真的灌过一篇文档
    getState: () =>
      JSON.stringify({
        ready: !!editorRef.value,
        loaded: docLoaded,
        chars: noteMd.value.length,
        textChars: Number(editorRef.value?.getTextLength?.() ?? 0),
      }),
    // 临时诊断：ref 到底绑上没有、expose 出来的是不是我们要的那几个方法
    diag: () => {
      const r: any = editorRef.value
      return JSON.stringify({
        hasRef: !!r,
        keys: r ? Object.keys(r) : [],
        setMarkdown: typeof r?.setMarkdown,
        getMarkdown: typeof r?.getMarkdown,
        noteLen: noteMd.value.length,
        pending: pendingMd.length,
        loaded: docLoaded,
        dom: !!document.querySelector('.ProseMirror'),
        stage: (window as any).__noteStage ?? '(none)',
      })
    },
  }
})

onMounted(async () => {
  if (!hosted) {
    err.value = '浏览器预览模式：未注入 hostObjects，数据为占位'
    markReady()
    return
  }
  try {
    pong.value = String(await ahkCall('ping'))
    ver.value = String(await ahkCall('version'))
    const raw = await ahkCall<string>('getTheme')
    if (raw) {
      const t = JSON.parse(raw) as Theme
      applyTheme(t)
      themeName.value = t.name
    }
    // 底栏那两条（日期 / 星期 / 标签）：AHK 建窗时会先推一次，页面晚到时靠这里补。
    const rawMeta = await ahkCall<string>('meta')
    if (rawMeta) setMeta(JSON.parse(rawMeta))
  } catch (e) {
    err.value = String(e)
  }
  // 自检页 / 材质样板没有「首屏数据」这一步 —— 渲染完就算就绪。
  // note 走 onEditorReady，panel / prompts 由各自组件在 load() 末尾放行。
  if (view.value === 'self' || view.value === 'lab') markReady()
})
</script>

<template>
  <!-- 材质样板独立成页：它自带全屏底（光雾 + 霜），不套 .shell 骨架 -->
  <GlassLab v-if="view === 'lab'" />
  <!-- 工作台面板同理：自己整页布局（两块玻璃板 + 底栏），不套 .shell -->
  <PanelView v-else-if="view === 'panel'" />
  <!-- 提示词库：整页列表（搜索 + 条目 + 状态行），也不套 .shell -->
  <PromptView v-else-if="view === 'prompts'" />
  <div v-else class="shell" :class="{ solo: view === 'note' }">
    <aside v-if="view !== 'note'" class="side">
      <div class="brand">
        <span class="dot" />SevenWork
      </div>
      <nav>
        <a class="nav" :class="{ on: view === 'self' }" @click="view = 'self'">底座自检</a>
        <a class="nav" :class="{ on: view === 'note' }" @click="view = 'note'">笔记</a>
        <a class="nav off">提示词</a>
        <a class="nav off">文件夹</a>
      </nav>
      <div class="foot">v0.2 · S2a 编辑器</div>
    </aside>

    <main v-if="view === 'self'" class="main">
      <header>
        <h1>前端底座</h1>
        <p class="sub">Vue 3 + Vite · 通过 https://app.local/ 加载</p>
      </header>

      <section class="cards">
        <div class="card">
          <div class="k">AHK 版本</div>
          <div class="v">{{ ver }}</div>
        </div>
        <div class="card">
          <div class="k">hostObjects 应答</div>
          <div class="v">{{ pong }}</div>
        </div>
        <div class="card">
          <div class="k">主题</div>
          <div class="v">{{ themeName }}</div>
        </div>
      </section>

      <p v-if="err" class="warn">{{ err }}</p>

      <section class="probe">
        <div class="k">输入法 / 键盘探针</div>
        <textarea
          v-model="text"
          rows="3"
          placeholder="在这里打几个中文，检查候选框位置与上屏；再按一次 Esc 看是否被吞"
        />
        <div class="hint">已输入 {{ text.length }} 字</div>
      </section>
    </main>

    <!-- 纯编辑器：**不设题头** —— 标题由笔记正文第一行（`📅 日期 速记`）承担，
         窗口标题已是 SevenNote；再挂一块「笔记 / Milkdown · …」只会把正文挤下去，
         说明文字还会在小窗口里折成两行。字数放底部状态行，对应原生版 StatusBar 的位置。 -->
    <main v-else class="main note">
      <div class="note-body">
        <!-- v-model 是单向回吐：编辑器是唯一真源，不反向覆写它 -->
        <NoteEditor ref="editorRef" v-model="noteMd" @ready="onEditorReady" />
      </div>
      <div class="note-foot">
        <span v-if="metaDate" class="meta">📅 {{ metaDate }} {{ metaWeekday }}</span>
        <span v-if="metaTag" class="meta">🏷 {{ metaTag }}</span>
        <span class="st" :class="statusKind" :key="statusSeq">{{ statusText }}</span>
        <span class="wc">{{ noteChars }} 字</span>
      </div>
    </main>
  </div>
</template>

<style scoped>
.shell {
  display: grid;
  grid-template-columns: 232px 1fr;
  height: 100%;
}

/* 笔记视图是「纯编辑器」：侧栏退场，整块客户区交给 Milkdown。
   ⚠ 不写这条的话 grid 仍留着 232px 空列 —— 右边全空，看着像编辑器没铺满。 */
.shell.solo {
  grid-template-columns: 1fr;
}

.side {
  background: var(--sw-bg-alt);
  border-right: 1px solid var(--sw-border);
  padding: 20px 16px;
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--sw-accent);
}

nav {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.nav {
  padding: 7px 10px;
  border-radius: 6px;
  color: var(--sw-fg);
  cursor: default;
  font-size: 13px;
}

.nav.on {
  background: var(--sw-bg);
  font-weight: 600;
}

.foot {
  margin-top: auto;
  font-size: 12px;
  color: var(--sw-dim);
}

.main {
  padding: 24px 28px;
  overflow: auto;
}

h1 {
  margin: 0 0 4px;
  font-size: 22px;
  font-weight: 600;
}

.sub {
  margin: 0 0 22px;
  color: var(--sw-dim);
  font-size: 13px;
}

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 12px;
  margin-bottom: 20px;
}

.card {
  background: var(--sw-bg-alt);
  border: 1px solid var(--sw-border);
  border-radius: var(--sw-radius);
  padding: 12px 14px;
}

.k {
  font-size: 12px;
  color: var(--sw-dim);
  margin-bottom: 4px;
}

.v {
  font-size: 15px;
  font-weight: 600;
  word-break: break-all;
}

.warn {
  color: var(--sw-fg);
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid var(--sw-border);
  border-radius: var(--sw-radius);
  padding: 8px 12px;
  font-size: 13px;
}

.probe {
  border: 1px solid var(--sw-border);
  border-radius: var(--sw-radius);
  padding: 14px;
}

textarea {
  width: 100%;
  margin-top: 8px;
  padding: 8px 10px;
  border: 1px solid var(--sw-border);
  border-radius: 6px;
  background: var(--sw-bg);
  color: var(--sw-fg);
  font: inherit;
  resize: vertical;
}

textarea:focus {
  outline: 2px solid var(--sw-accent);
  outline-offset: -1px;
}

.hint {
  margin-top: 6px;
  font-size: 12px;
  color: var(--sw-dim);
}

/* ── 笔记页：编辑器自己滚，外层不滚 ─────────────────────────────── */
.main.note {
  padding: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.note-body {
  flex: 1 1 auto;
  min-height: 0;
}

/* 底部状态行：对应原生版 `StatusBar` 的位置（日期 / 星期 / 标签 + 提示 + 字数）。
   ⚠ 中间那格（保存状态）用 flex:1 撑开，字数自然贴右 —— 别再写
     justify-content: space-between，否则四个元素会被均摊到整行两头。
   ⚠ 日期为空（还没载入）时不渲染，别留一个空的「📅 」。 */
.note-foot {
  flex: none;
  display: flex;
  align-items: baseline;
  gap: 14px;
  padding: 6px 22px;
  font-size: 12px;
  color: var(--sw-dim);
  border-top: 1px solid var(--sw-border);
  background: var(--sw-bg-alt);
}

.note-foot .meta {
  flex: none;
  opacity: 0.9;
  white-space: nowrap;
}

.note-foot .st {
  flex: 1 1 auto;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  /* 每次保存 / 状态变化闪一下：内容没改动时文字与上次相同，
     不加这一步就「看不出按过 Ctrl+S」。 */
  animation: status-flash 260ms ease-out;
}

@keyframes status-flash {
  from {
    opacity: 0.3;
  }
  to {
    opacity: 1;
  }
}

@media (prefers-reduced-motion: reduce) {
  .note-foot .st {
    animation: none;
  }
}

/* 三档只用明度与一条左边框区分 —— 主题是无色的，别在这里引入红绿。 */
.note-foot .st.ok {
  color: var(--sw-fg);
}

.note-foot .st.err {
  color: var(--sw-warn);
  border-left: 2px solid var(--sw-warn-border);
  padding-left: 8px;
}

.note-foot .wc {
  flex: none;
  opacity: 0.85;
}

.nav {
  cursor: pointer;
}

.nav.off {
  opacity: 0.45;
  cursor: default;
}

.nav:hover:not(.off):not(.on) {
  background: var(--sw-bg-alt);
}
</style>
