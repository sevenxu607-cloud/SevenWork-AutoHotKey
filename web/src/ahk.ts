/* ═══════════════════════════════════════════════════════════════════════
   AHK 桥 —— 前端唯一允许碰宿主的入口
   · hostObjects：AHK 用 AddHostObjectToScript("ahk", {...}) 注册，
     JS 侧 chrome.webview.hostObjects.ahk.<method>() 返回 Promise
   · 拿不到 chrome.webview 时（普通浏览器里跑 vite dev）全部降级为假数据，
     这样 `npm run dev` 也能调样式，不必每次都起 AHK
   ═══════════════════════════════════════════════════════════════════════ */

type ChromeWebView = {
  hostObjects?: Record<string, any>
  postMessage(msg: unknown): void
  addEventListener(type: string, cb: (e: MessageEvent) => void): void
}

export function webview(): ChromeWebView | null {
  const wv = (window as any).chrome?.webview
  return wv ?? null
}

/** 是否真的跑在 WebView2 里（而不是 npm run dev 的浏览器） */
export function isHosted(): boolean {
  return !!webview()?.hostObjects?.ahk
}

export function bridge(): Record<string, any> | null {
  return webview()?.hostObjects?.ahk ?? null
}

/** 调 AHK 侧方法；AHK 函数返回值会被包成 Promise */
export async function ahkCall<T = string>(method: string, ...args: unknown[]): Promise<T> {
  const b = bridge()
  if (!b) throw new Error('hostObjects 未注入（不在 WebView2 里）')
  const fn = b[method]
  if (typeof fn !== 'function') throw new Error(`AHK 未提供方法：${method}`)
  return (await fn(...args)) as T
}

/**
 * 语义色板 —— 与 AHK 侧 ThemeService.Palette() 的字段一一对应。
 * 名字沿用 --sw-* 的语义，AHK 一次算全再推过来（派生规则只写在一处）。
 */
export interface Theme {
  name: string
  win: string // 窗口底 / 标题栏   → --sw-bg-alt
  edBg: string // 内容底           → --sw-bg
  text: string // 正文             → --sw-fg
  dim: string // 次要文字          → --sw-dim
  accent?: string // 强调色        → --sw-accent
  border?: string // 分隔线        → --sw-border
  codeBg?: string // 代码块 / 列表底 → --sw-code-bg
  dark?: boolean // 是否深色（AHK 判，避免两边公式不一致）

  /** 材质风格：glass = 琉璃；缺省或其它值 = flat（现有米黄外观） */
  style?: string
  /**
   * ⚠ v2.15 起**没有** radius / motion / density / dur* 这些字段：
   *   「外观」模块不再提供那四项滑杆，圆角与动效改用 tokens.css 的默认值。
   *   主题真要换形状，改主题表 / tokens.css，而不是让用户拼参数。
   */
  /**
   * 编辑区字体名（笔记模块的 FontService 给，如「楷体」）。
   * 只作用于编辑区（--sw-ed-font）；面板那类网页仍用系统 UI 字体。
   */
  font?: string
  /** 编辑区字号，单位是**磅（pt）** —— 与旧版 RichEdit 的 14pt 同源，别当 px 用 */
  fontSize?: number
  /**
   * 材质参数 —— 键名直接映射成 --sw-<key>，值是**可直接写进 CSS 的字符串**。
   * 例：{tint: "rgba(190,245,255,.055)", blur: "14px"}
   * AHK 侧只负责给值，不认识任何 DOM。缺字段就沿用 glass.css 的默认值。
   */
  material?: Record<string, string>
}

/* ── 主题应用状态（模块级）──────────────────────────────────────────────
   · appliedKey：上一次**完整**应用的指纹（色板 + 材质 + 字体）。
     唯一作用：幂等 —— AHK 建窗推一次、页面 onMounted 再拉一次，同一套主题
     不该重绘两遍（重绘还会白跑一次过场，看起来像窗口自己闪了一下）。
   · visualKey：上一套主题的**视觉**指纹（不含字体 / 字号）。
     字体是编辑区的私事：换字体只需重写变量，让整窗交叉溶解一次纯属噪音。
   · themeSeq：应用序号。切主题走 View Transition 时 paint / done 都是**异步**
     回调；快速连按 Alt+T 时，前一回过场的 finished 可能后到 —— 它会按旧参数
     重画一遍、还会把新一回刚加的 .theming 摘掉。序号让过期回调自己退场。
   · lastMaterialKeys：上一次由 material 写进 <html> 的变量名。
     ⚠ 必须记住并逐个移除 —— 只写不清的话，A 主题的 --sw-blur 会残留到
       不提供该字段的 B 主题上，B 看起来就像「参数根本没生效」，而且极难查。 */
let appliedKey = ''
let visualKey = ''
let themeSeq = 0
let lastMaterialKeys: string[] = []

/* 材质键白名单。
   ⚠ 原来那支 /^[a-z][a-z0-9-]*$/ 只约束**格式**、不约束**是不是我们的变量**：
     主题表里一个笔误就会写出一个永不生效的 --sw-xxx，排查时毫无线索。
     这里只放 tokens.css 里真实定义过的材质类变量；新增材质变量时两处一起加。 */
const MATERIAL_KEYS = new Set([
  'tint',
  'scrim',
  'edge',
  'edge-a',
  'sheen',
  'blur',
  'sat',
  'bright',
  'frost',
  'spec',
])

/**
 * 视觉指纹：换它才值得播一次交叉溶解。
 * ⚠ 必须覆盖 paint() **真正会写**的每一个字段 —— 少一个就会出现「主题换了、
 *   界面没变」：因为完整指纹相同而被当成重复应用直接 return。
 *   这里不含 font / fontSize（见 themeKey）。
 */
function visualKeyOf(t: Theme): string {
  const m = t.material ?? {}
  const mk = Object.keys(m)
    .filter((k) => MATERIAL_KEYS.has(k))
    .sort()
    .map((k) => `${k}=${m[k]}`)
    .join(',')
  return [
    t.name,
    t.style ?? '',
    t.win,
    t.edBg,
    t.text,
    t.dim,
    t.accent ?? '',
    t.border ?? '',
    t.codeBg ?? '',
    String(t.dark ?? ''),
    mk,
  ].join('|')
}

/** 完整指纹 = 视觉指纹 + 字体 / 字号（字体变了要重写变量，但不必过场） */
function themeKey(t: Theme): string {
  return [visualKeyOf(t), t.font ?? '', String(t.fontSize ?? '')].join('#')
}

/** AHK 推主题：__sevenwork.applyTheme({name, win, edBg, text, dim, accent, style, material}) */
export function applyTheme(t: Theme): void {
  const root = document.documentElement
  const r = root.style
  const hex = (v: string) => (v.startsWith('#') ? v : '#' + v)

  // 同一套主题重复应用：不重绘、不过场（见 appliedKey 的说明）
  const key = themeKey(t)
  if (key === appliedKey) return
  const prevVisual = visualKey
  const nextVisual = visualKeyOf(t)
  const firstApply = appliedKey === ''
  appliedKey = key
  visualKey = nextVisual

  // 只有字体 / 字号变了：重写变量即可，让整窗溶解一次纯属噪音
  const needTransition = !firstApply && nextVisual !== prevVisual

  // 序号：任何异步回调（View Transition 的 finished、兜底定时器）都要先比对它，
  // 过期就退场 —— 否则连按两次 Alt+T 会看到「后一个主题被前一个覆盖回去」。
  const seq = ++themeSeq

  const paint = () => {
    if (seq !== themeSeq) return
    r.setProperty('--sw-bg', hex(t.edBg))
    r.setProperty('--sw-bg-alt', hex(t.win))
    r.setProperty('--sw-fg', hex(t.text))
    r.setProperty('--sw-dim', hex(t.dim))

    // accent / border / codeBg / dark 全部由 AHK 的 ThemeService.Palette() 派生后推来。
    // 从前这几个前端自己算（border 干脆一直用 CSS 里那支米黄 #d8cdb0）—— 深色主题下
    // 既不像分隔线也不像强调色。派生只写一处，网页与 AHK 窗口才对得上。
    // 缺字段时退回本地推导：`npm run dev` 在浏览器里跑，没有 AHK 推值。
    const dark = t.dark ?? luminance(t.edBg) < 128
    r.setProperty('--sw-accent', hex(t.accent ?? (dark ? '7FB4D8' : '4A7C9E')))
    r.setProperty('--sw-border', hex(t.border ?? (dark ? shift(t.edBg, 12) : shift(t.edBg, -14))))
    r.setProperty('--sw-code-bg', hex(t.codeBg ?? (dark ? shift(t.edBg, 12) : shift(t.edBg, -8))))
    r.setProperty('--sw-select', hexToRgba(t.accent ?? t.dim, 0.26))
    r.setProperty('--sw-ring', hexToRgba(t.accent ?? t.dim, 0.3))
    root.dataset.theme = t.name

    // ── 全局外观 ─────────────────────────────────────────────────────────
    // ⚠ v2.15 起不再从 AHK 接收 radius / dur* / density：
    //   那四项滑杆已撤掉（观感差几乎看不出，却要维护一整条「保存 → 重刷」链路）。
    //   圆角 / 动效回落到 tokens.css 的默认值 —— 默认值只写一处，不再两边各存一份。

    // 材质：先撤掉上一套主题写过的覆盖，再按白名单写本套的。
    // ⚠ 顺序不能反 —— 先写后清会把本套刚写的值一并删掉。
    // ⚠ 只 removeProperty 自己写过的键，绝不 style.cssText = '' / removeAttribute('style')：
    //   那会连 --sw-ed-font、--sw-ed-size 这些「非主题」状态一起抹掉。
    for (const oldKey of lastMaterialKeys)
      r.removeProperty(`--sw-${oldKey}`)
    lastMaterialKeys = []

    root.dataset.style = t.style || 'flat'
    if (t.material) {
      for (const mk of Object.keys(t.material)) {
        if (!MATERIAL_KEYS.has(mk)) continue
        const mv = t.material[mk]
        if (typeof mv === 'string' && mv) {
          r.setProperty(`--sw-${mk}`, mv)
          lastMaterialKeys.push(mk)
        }
      }
    }

    // 编辑区字体 / 字号（笔记模块的 FontService 给）。
    // ⚠ 字号必须原样按 pt 写：旧版 RichEdit 是 14pt，若换成 px（≈18.7px）再叠上
    //   不同字体的字面差，观感就会「字变大」—— 这正是 Markdown 化之后用户报
    //   「编辑区字体太大」的根因，别在这里再换一次单位。
    // ⚠ 字体名可能带空格（华文行楷 / 华文新魏），必须加引号。
    if (t.font) r.setProperty('--sw-ed-font', `"${t.font}", KaiTi, "楷体", serif`)
    if (t.fontSize) r.setProperty('--sw-ed-size', `${t.fontSize}pt`)

    // 通知 Vue 层（顶部「主题 · 字体」那行）。applyTheme 是全局函数，拿不到组件实例，
    // 派发事件是唯一不给各视图加耦合的做法。
    window.dispatchEvent(new CustomEvent('sw-theme', { detail: t }))
  }

  // 首次应用没有「旧外观」可溶解 —— 直接落定。播了反而像页面自己闪了一下。
  // 仅字体变化同理：视觉指纹没变，没有任何东西需要溶解。
  if (!needTransition) {
    paint()
    // ⚠ 这一次应用已经把 themeSeq 推进了 —— 上一次过场的清理回调会因序号不符而退场。
    //   而本分支**从不加** .theming，也就没人摘：它会永远留在 <html> 上，
    //   整页的 transition / animation 从此全被禁掉（悬停、切页都没过渡，
    //   重开窗口才恢复）。字体更新同样算一次完整应用，由它负责收尾。
    if (root.classList.contains('theming')) root.classList.remove('theming')
    return
  }

  // 换主题走一次 View Transition：整窗交叉溶解，而不是逐个属性慢慢变。
  // ⚠ .theming 期间禁掉所有 transition/animation —— 不然后台那些 :hover 过渡
  //   会跟着一起触发，看起来像有人把整窗亮度拧了一遍。
  root.classList.add('theming')

  // ⚠ 必须有兜底：View Transition 的 finished 在某些情况下不会 resolve
  //   （transition 被跳过 / 页面在后台）。只靠它摘 .theming 会把动画永久禁掉。
  // ⚠ 每个出口都先比对 seq：过期的过场不得摘掉**新**过场的 .theming。
  let guard = 0
  const clearTheming = () => {
    if (seq === themeSeq) root.classList.remove('theming')
  }
  const done = () => {
    if (seq !== themeSeq) return
    window.clearTimeout(guard)
    window.setTimeout(clearTheming, 40)
  }
  guard = window.setTimeout(clearTheming, 900)

  const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches
  const vt = (document as any).startViewTransition
  if (!reduce && typeof vt === 'function') {
    try {
      const trans = (document as any).startViewTransition(paint)
      Promise.resolve(trans?.finished).then(done, done)
      return
    } catch {
      // 掉回同步路径，别让换主题因为一个过场 API 失败
    }
  }
  paint()
  done()
}

/* ── 颜色小工具（主题推下来的是 6 位 hex，不带 #）───────────────────── */

function parseHex(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [
    parseInt(h.slice(0, 2), 16) || 0,
    parseInt(h.slice(2, 4), 16) || 0,
    parseInt(h.slice(4, 6), 16) || 0,
  ]
}

function toHex(rgb: [number, number, number]): string {
  return (
    '#' +
    rgb
      .map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0'))
      .join('')
  )
}

/**
 * 相对亮度（Rec.601 加权），只用来判明暗，不用于精确对比度。
 * ⚠ 系数与 AHK 侧 ThemeService.IsDark / UiPaint.IsDark 必须完全一致 ——
 *   两边对同一主题判出不同明暗，就会出现「网页深、标题栏浅」。
 */
function luminance(hex: string): number {
  const [r, g, b] = parseHex(hex)
  return 0.299 * r + 0.587 * g + 0.114 * b
}

/** 整体加减同一档亮度 */
function shift(hex: string, delta: number): string {
  const [r, g, b] = parseHex(hex)
  return toHex([r + delta, g + delta, b + delta])
}

function hexToRgba(hex: string, alpha: number): string {
  const [r, g, b] = parseHex(hex)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

/* ═══════════════════════════════════════════════════════════════════════
   图片落盘
   WebView2 里交给 AHK（saveImage(base64, ext) → 相对路径）；
   浏览器预览里内联 data URL —— 让 `npm run dev` 也能验粘贴，不必起 AHK。
   ═══════════════════════════════════════════════════════════════════════ */

/** Uint8Array → base64。分块拼，别一次性 spread —— 5 MB 图会爆调用栈 */
function bytesToBase64(bytes: Uint8Array): string {
  let out = ''
  const step = 0x8000
  for (let i = 0; i < bytes.length; i += step) {
    out += String.fromCharCode(...bytes.subarray(i, i + step))
  }
  return btoa(out)
}

function extOf(file: File): string {
  const m = /^image\/([a-z0-9]+)/i.exec(file.type)
  if (!m) return 'png'
  return m[1].toLowerCase() === 'jpeg' ? 'jpg' : m[1].toLowerCase()
}

export async function storeImage(file: File): Promise<string> {
  const b64 = bytesToBase64(new Uint8Array(await file.arrayBuffer()))
  if (isHosted()) {
    try {
      return await ahkCall<string>('saveImage', b64, extOf(file))
    } catch {
      // AHK 侧还没实现 saveImage 时退回内联 —— 别让整次粘贴失败
    }
  }
  return `data:${file.type || 'image/png'};base64,${b64}`
}

/* 图片路径的双态转换与旧格式清理已搬到 ./markdown.ts —— 那里是纯函数、
   可以单测（web/tests/markdown.test.mjs）；本文件只管宿主通信。 */


/* ═══════════════════════════════════════════════════════════════════════
   工作台面板（Alt+S）—— 数据契约
   与 src\WorkBench\PanelHostBridge.ahk 的 PanelData.Json() 逐字对齐。
   ⚠ 改字段名必须两边同改：前端拿到 undefined 不报错，只会静默少一行 / 少一栏。
   ═══════════════════════════════════════════════════════════════════════ */

export interface PanelHotkey {
  key: string
  label: string
  note?: string
}

/** 「全部热键」视图按组分段；模块页没有 groups（平铺在 hotkeys 里） */
export interface PanelGroup {
  name: string
  items: PanelHotkey[]
}

export interface PanelField {
  key: string
  label: string
  /** "folder" = 带「浏览…」；"select" = 下拉；"range" = 滑杆；缺省 / "text" = 文本框 */
  kind: string
  value: string
  /** 空输入框里的灰字提示，只显示、不进值 */
  placeholder: string
  /** select 的候选值（值即显示）。非 select 一律是空数组 */
  options?: string[]
  /** range 的三个数字，字符串形式（前端 parseFloat）。非 range 是空串 */
  min?: string
  max?: string
  step?: string
  /** range 右侧的单位后缀，如 "px"；纯显示 */
  unit?: string
}

export interface PanelSpec {
  title: string
  hint: string
  /** 后端 spec 里有没有 apply —— 没有就不显示「保存设置」 */
  hasApply: boolean
  fields: PanelField[]
}

export interface PanelRow {
  id: string
  /** view = 「全部热键」那一页；module = 各模块 */
  kind: 'view' | 'module'
  name: string
  desc: string
  count: number
  failed: boolean
  groups?: PanelGroup[]
  hotkeys?: PanelHotkey[]
  spec: PanelSpec | null
}

export interface PanelData {
  app: string
  version: string
  vault: string
  total: number
  modules: number
  /** 首屏停在哪一页（模块 Id；空串 = 第一页）。由 AHK 的 ShowHelp(id) 记下 */
  focus: string
  rows: PanelRow[]
}

/** 拉整份面板数据；浏览器预览里返回 null（调用方退回内置示例） */
export async function fetchPanel(): Promise<PanelData | null> {
  if (!isHosted()) return null
  const raw = await ahkCall<string>('getPanel')
  return raw ? (JSON.parse(raw) as PanelData) : null
}

/**
 * 存某模块的设置：值按 fields 的声明顺序送。
 *
 * ⚠ **必须补满 8 个**：AHK 侧 PanelHostApply 是固定 8 个形参 —— hostObjects 走
 *   IDispatch，变参（`args*`）在这种调用方式下不可靠，而前端也拿不到「AHK 想要几个」。
 *   超过 8 个字段要同步加长 AHK 那边（目前最多的是文件夹的 3 个）。
 *
 * ⚠ AHK 侧的方法键名是 **saveSettings** 而不是 apply：hostObjects 在 JS 侧是 Proxy，
 *   `b['apply']` 会先命中内置的 Function.prototype.apply —— 拿到的是原生函数，
 *   一调就抛「TypeError: Function.prototype.apply was called on ...」，
 *   而调用点大多在 try 里，表现成「点保存没反应 + 状态栏一行看不懂的错」。
 *
 * 返回 "ok" | "err:原因"。
 */
export async function applySettings(moduleId: string, values: string[]): Promise<string> {
  const pad = values.slice(0, 8)
  while (pad.length < 8) pad.push('')
  return String(await ahkCall<string>('saveSettings', moduleId, ...pad))
}

/* ═══════════════════════════════════════════════════════════════════════
   首屏就绪信号 —— 给 AHK 的入场时机用
   ═══════════════════════════════════════════════════════════════════════
   AHK 侧（WebWindow._RevealWhenReady）轮询 `data-ready` 决定何时播入场。
   ⚠ 为什么不再用「#app 有子元素」：那只说明 Vue 挂上了，而 PanelView 的 rows
     还在 fetchPanel() 的路上 —— 这时播入场，画面会从空壳淡入、数据后到再跳
     一次，比不播还难看。
   ⚠ 各视图要在**首屏数据落定**后调它：成功、或者已进入可解释的失败态都算落定
     —— 失败态也得让人看见错误，不能一直当作「没就绪」。
   ⚠ 忘了调不会永久黑屏：AHK 有 4.8s 上限，到点照样播一次入场。
   ═══════════════════════════════════════════════════════════════════════ */

export function markReady(): void {
  document.documentElement.dataset.ready = '1'
}
