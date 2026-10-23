#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  SevenNoteModule —— 笔记模块生命周期
;  v2.9 起编辑区是 WebView2 + Milkdown：AHK 只负责建窗口、挂宿主、注册热键，
;  内容与界面全在 web/ 里。Init → 热键 → Start 的顺序未变。
; ═══════════════════════════════════════════════════════════════════════════

class SevenNoteModule {
    static Id := "SevenNote"
    static Name := "笔记"
    ; 笔记模块自己的显示名（标题栏用）。工作台叫 SevenWork（Config.AppName），
    ; 而 Alt+Z 呼出的是**笔记窗口** —— 标题用模块名才与目录 / 模块 Id / 事件名自洽。
    ; 平台级界面（Alt+S 帮助、启动提示、报错框）仍用 Config.AppName。
    static Title := "SevenNote"

    ; WebView2 是否已挂上（OnSize 据此决定要不要 Fill —— 没挂上时 Fill 会抛错）
    static _mounted := false

    ; 创建主窗口 + 挂载 Feature（原组合根 3901-3997）
    static Init() {
        ; ─── 创建主窗口 ───
        g := Gui(, this.Title)
        ; +E0x02000000 = WS_EX_COMPOSITED 已不需要：整个客户区交给 WebView2，
        ; 合成由 Chromium 自己做，没有 RichEdit 那种「先擦后画」的频闪。
        g.Opt("+AlwaysOnTop +Resize +MinSize450x300")
        ; 首帧底色：Chromium 起来前不铺东西会露白。取当前主题的窗底色同档。
        g.SetFont("s14", "楷体")
        pInit := ThemeService.Palette()
        g.BackColor := pInit.win
        ; 玻璃背衬（只有玻璃主题给）。主窗客户区被 WebView2 整块盖住，这里要的是
        ; **非客户区**（标题栏 / 边框）与圆角 —— 那正是 DWM 背板真正生效的地方。
        UiPaint.Glass(g.Hwnd, pInit.style, pInit.win)

        ; ─── 客户区整个交给 WebView2 ───
        ; 字数 / 标签 / 主题名 / 日期 / 提示原本是 6 个 Text 控件，现在全在页面里
        ; （前端拿到 markdown 自己算字数、自己显示日期）。AHK 侧不再持有任何子控件 ——
        ; 少一层「AHK 控件 vs 页面元素」的双份状态，就不会出现两边不一致。

        ; ─── 注册到 State ───
        State.SetGui(g)
        ; RichEdit 退场：State.GetEd() 从此恒为 0。
        ; 骨架层冻结，setter 保留（别的模块仍可调用，只是拿不到控件）。
        State.SetEd(0)

        ; ─── 窗口事件 ───
        ; ⚠ 标题栏的 × 必须与 Alt+Z 走同一条路（WindowFeature.Hide）：
        ;   从前是裸的 g.Hide() —— 绕过 `Window.BeforeHide`（保存）与位置记忆，
        ;   用户点一下 × 就等于「这次编辑既不存盘、下次也从默认落点重开」。
        g.OnEvent("Close", (*) => (WindowFeature.Hide(), true))
        g.OnEvent("Size", (guiObj, mm, w, h) => SevenNoteModule.OnSize(guiObj, mm, w, h))

        ; ═══ 挂载 Feature ═══
        ; v2.9 起只剩四件：窗口 / 保存 / 自动保存 / 日期跳转。
        ; 搜索、撤销、行编辑、纯文本粘贴、光标记忆、字数、背景图全部由页面接管 ——
        ; 它们本来就是「编辑器内部」的事，从前借着 RichEdit 的 SendMessage 硬做；
        ; 现在 Milkdown 自己就是编辑器，前端一套 keymap 就够。
        WindowFeature.Init()
        SaveFeature.Init()
        AutoSaveFeature.Init(Config.AutoSaveInterval)
        DateJumpFeature.Init()

        ; 每次露面后补一次 Fill：Chromium 子窗口的尺寸只在父窗口可见时才有意义，
        ; 而 Mount 发生在隐藏态（见 _Mount）。不补的话窗口出来了、编辑区仍是 0×0 ——
        ; 画面一片纯底色，看起来像「WebView2 根本没显示」。
        EventBus.On("Window.Shown", (*) => SevenNoteModule._AfterShown())

        ; 换主题（Alt+T）时跟着变：平台只广播，窗口自己决定怎么响应 ——
        ; 这样删掉笔记模块，别的模块窗口照样跟着主题走。
        EventBus.On("Theme.Changed", (*) => SevenNoteModule._OnThemeChanged())

        ; 字体 / 字号变了，走同一条重刷路径（NoteHostTheme 会把 --sw-ed-* 一起推过去）。
        EventBus.On("Font.Changed", (*) => SevenNoteModule._OnThemeChanged())

        ; 旧版 StatusBar 会在切换后说一句「✓ 字体：华文行楷 16pt」。
        ; 不做这一步的话，按完 Alt+Shift+T 只看到字变了、不知道现在用的是哪一款。
        EventBus.On("Font.Changed", (data) => SevenNoteModule._PushStatus(
            {text: "字体：" . data.name . " " . data.size . "pt", kind: "info"}))

        ; 保存结果的可视反馈：底栏那一行。窗口没开时推送会失败，忽略即可。
        EventBus.On("Note.Status", (data) => SevenNoteModule._PushStatus(data))

        ; 改标签 = 文件改名：底栏的「🏷 标签」要跟着换（路径已在 TitleFeature 里更新）。
        EventBus.On("Title.Changed", (*) => NoteSessionService.PushMeta())

        ; ⚠ 字体 / 字号偏好必须在这里显式加载 —— 全项目没有第二处调它。
        ;   从前 `FontService.Apply()` 开头就 `if !State.GetEd() return`，而这个调用
        ;   压根不存在，于是用户在旧版调过的字号（[Appearance] FontSizeIndex）
        ;   一直躺在配置里没用上，新编辑区永远 14pt。
        FontService.LoadFromConfig()

        ; 退出守卫：Alt+Shift+S 时平台逐条问这里的检查函数。
        ; ⚠ 登记在 Init（不是 Start）：它只回答「能不能退」，不碰窗口、不读内容。
        EventBus.Emit("Exit.Guard", {id: "笔记", check: (*) => SevenNoteModule.ExitCheck()})
    }

    ; 退出前把当前笔记存一次（平台只认 {ok, reason}）。
    ; ⚠ 保存失败**不放行**：退出等于放弃这次改动，而窗口一关状态栏那行提示也看不见了。
    ;   唯一例外是 recoverable —— 冷启动 / 页面还没挂，本来就没有可丢的内容。
    static ExitCheck() {
        r := NoteSessionService.Save()
        if r.ok
            return {ok: true, reason: ""}
        if r.HasProp("recoverable") && r.recoverable
            return {ok: true, reason: ""}
        return {ok: false, reason: "笔记没能保存（"
            . (r.HasProp("reason") ? r.reason : "未知原因") . "）"}
    }

    ; 换主题：窗口底色 + 标题栏 + 推给前端页面。
    ; ⚠ 异步回调碰窗口前必须过闸（见 .clinerules/03「异步回调里碰窗口」）：
    ;   窗口可能已经销毁，WinAPI 抛错会被全局 OnError 记一条看不懂的日志。
    static _OnThemeChanged() {
        g := State.GetGui()
        if !g
            return
        if !DllCall("user32\IsWindow", "ptr", g.Hwnd, "int")
            return

        p := ThemeService.Palette()
        g.BackColor := p.win
        UiPaint.TitleBar(g.Hwnd, p.win, p.text)
        ; 玻璃背衬跟着主题走：切到 glass 时铺、切回 flat 时由 UiPaint.Glass 撤掉
        UiPaint.Glass(g.Hwnd, p.style, p.win)

        ; 前端：--sw-* 全套一次推过去。页面没起来时 Eval 返回 {ok:false}，忽略即可 ——
        ; 前端 onMounted 还会再 getTheme 一次，不会留旧色。
        if this._mounted
            WebHostService.Eval("window.__sevenwork&&window.__sevenwork.applyTheme("
                . NoteHostTheme() . ")", g.Hwnd)
    }

    ; 把一行状态推到页面底栏（保存成功 / 无改动 / 失败）。
    ;
    ; ⚠ 显式传 hwnd：面板与提示词库各有一份 WebView2，无参会落到最近挂载的那个窗口上。
    ; ⚠ 前端没起来时 Eval 返回 {ok:false}，这里**不记日志** —— 冷启动阶段底栏还没渲染，
    ;   每次按 Alt+Z 都刷一条错误只会把真问题淹掉。
    static _PushStatus(data) {
        if !this._mounted || !IsObject(data)
            return
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return
        text := data.HasProp("text") ? data.text : ""
        kind := data.HasProp("kind") ? data.kind : "info"
        WebHostService.Eval("window.__swnote&&window.__swnote.setStatus("
            . JsText.Escape(text) . "," . JsText.Escape(kind) . ")", hwnd)
    }

    static _AfterShown() {
        if !this._mounted
            return
        ; ⚠ 显式传 hwnd：WebHostService v2.10 起多实例，无参会落到「最近挂载的窗口」上 ——
        ;   面板一开，这里就会把笔记窗的尺寸补给面板（笔记窗自己反而还是 0×0）。
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return
        WebHostService.Resize(hwnd)
        ; 玻璃主题的入场编排：必须在窗口**已经可见**之后调 ——
        ; 隐藏态下 WebView2 不合成，动画等于在后台跑完，用户看到的第一帧就是终态。
        if ThemeService.Palette().style
            WebHostService.Eval("window.__swfx&&window.__swfx.reveal()", hwnd)
    }

    ; ─── 启动：挂 WebView2 → 载入当天 ───
    ; ⚠ 必须晚于热键注册（Router 先 RegisterAll 再 StartAll），否则用户按 Alt+Z
    ;   时窗口先露面、热键还没就位，表现成「按了没反应」。
    static Start() {
        if !this._Mount()
            return
        ; ⚠ 不在 Start() 里同步等编辑器：WaitFor 最长 8 秒，会把整个启动流程卡住
        ;   （StartAll 是同步遍历，别的模块得陪着等）。排到后台，热键先就位。
        SetTimer(() => SevenNoteModule._FirstLoad(), -50)
    }

    static _FirstLoad() {
        try LoadFeature.Load()
        catch as e
            LogError("首次载入失败：" . e.Message)
    }

    ; 把 WebView2 挂到主窗口上。
    ; ⚠ 全程在隐藏态完成（Show("Hide") → Mount → Navigate）：先 Show 再摆位会让
    ;   窗口在默认落点闪一下（实测 +31ms 出现在错误位置、+219ms 才跳过去）。
    static _Mount() {
        g := State.GetGui()
        try
            g.Show("Hide")
        catch as e {
            LogError("笔记窗口创建失败：" . e.Message)
            return false
        }

        ; 标题栏跟着主题染（深底配亮字 / 浅底配深字，由 UiPaint 自己按亮度判）。
        ; 放在隐藏态做：属性设好，窗口一露面就是正确的颜色，不会先闪一下白标题栏。
        p := ThemeService.Palette()
        UiPaint.TitleBar(g.Hwnd, p.win, p.text)

        dist := this._DistDir()
        if (dist = "") {
            LogError("前端产物不存在，先到 web\ 下 npm run build")
            return false
        }

        ; 首帧底色必须跟主题走：这里的默认值是深蓝（0xFF0B1624），米黄主题下
        ; Chromium 起来前会先闪一帧深蓝。传 edBg（内容底）而不是 win（窗口底）——
        ; WebView2 铺满整个客户区，它盖住的正是内容区。
        ; ⚠ 这里是 AARRGGBB（COREWEBVIEW2_COLOR），不是 Win32 的 COLORREF ——
        ;   别套 RGBtoBGR，那会把 R/B 反过来（FFF8E7 → E7F8FF，米黄变淡蓝）。
        r := WebHostService.Mount(g.Hwnd, dist, "app.local"
            , 0xFF000000 | Integer("0x" . p.edBg))
        if !r.ok {
            LogError("WebView2 挂载失败：" . r.reason)
            return false
        }

        ; 笔记图片在 vault 下，markdown 里写的是 ./_assets/<date>/x.png；
        ; 相对 app.local 会解析成 app.local/_assets/… → 404。把 vault 另挂一个主机，
        ; 前端显示时加前缀、存盘时剥掉（见 web/src/ahk.ts 的路径双态）。
        m := WebHostService.MapHost("vault.local", Config.GetVault(), g.Hwnd)
        if !m.ok
            LogError("vault 映射失败：" . m.reason)

        WebHostService.Bind("ahk", NoteHostHandlers(), g.Hwnd)

        n := WebHostService.Navigate("/index.html?view=note", g.Hwnd)
        if !n.ok {
            LogError("导航失败：" . n.reason)
            return false
        }
        this._mounted := true
        ; 隐藏态也铺一次：给 Chromium 一个初始尺寸，免得首次显示时先闪一帧空白。
        ; 真正的尺寸要等父窗口可见（Window.Shown → _AfterShown）。
        WebHostService.Resize(g.Hwnd)
        return true
    }

    ; 前端产物目录：开发态在 <repo>\web\dist（src\ 的同级）；编译版与 exe 同级。
    ; 实现搬进 WebHostService —— 面板也要同一个目录，谁都不该是「标准的来源」。
    static _DistDir() => WebHostService.DistDir()

    static OnSize(guiObj, MinMax, Width, Height) {
        ; 最小化时 Width/Height 是图标尺寸（实测约 158x26），
        ; Fill() 会把 Chromium 压成一条，直接跳过
        if (MinMax = -1)
            return
        if this._mounted
            WebHostService.Resize(guiObj.Hwnd)
    }

    ; 笔记模块的热键
    ; v2.9：27 条 → 7 条。编辑器内部的键（撤销 / 行编辑 / 缩进 / 纯文本粘贴 /
    ; 时间戳 / 分隔线 / 分段标题 / 搜索）统统交给页面 —— 那些操作都要看光标与选区，
    ; 前端一套 keymap 天然有上下文；AHK 这边从前只能对着 RichEdit SendMessage 猜。
    ; 平台热键（Alt+S / Alt+Shift+S）不在这里，见 WorkBench.GetHotkeys()。
    static GetHotkeys() {
        return [
            ; ── 【窗口】──
            {ctx: "global", key: "!z", group: "窗口", line: "   Alt+Z            呼出 / 隐藏"
                , fn: (*) => WindowFeature.Toggle()},

            ; ── 【外观】──
            ; v2.15 恢复：这三条在迁到 WebView2 时丢了 —— FontService 还在、配置也还在读，
            ; 但没有任何入口能改它，用户只能去改 ini（「字体和以前割裂」的一半原因）。
            ; 档位：7 种字体 × 5 档字号（12/14/16/18/20），改完广播 Font.Changed，
            ; 页面据此重写 --sw-ed-font / --sw-ed-size（见 HostBridge.NoteHostTheme）。
            {ctx: "global", key: "!+t", group: "外观", line: "   Alt+Shift+T      切换正文字体"
                , fn: (*) => FontService.NextFont()},
            {ctx: "global", key: "!=", group: "外观", line: "   Alt+=            调大正文字号"
                , fn: (*) => FontService.BiggerSize()},
            {ctx: "global", key: "!-", group: "外观", line: "   Alt+-            调小正文字号"
                , fn: (*) => FontService.SmallerSize()},

            ; ── 【保存】──
            {ctx: "editor", key: "$^s", group: "保存", line: "   Ctrl+S           手动保存"
                , fn: (*) => SaveFeature.Save()},

            ; ── 【日期与标签】──
            {ctx: "global", key: "!Up", group: "日期与标签", line: "   Alt+↑            前一天"
                , fn: (*) => DateSwitchFeature.Switch(-1)},
            {ctx: "global", key: "!Down", group: "日期与标签", line: "   Alt+↓            后一天"
                , fn: (*) => DateSwitchFeature.Switch(1)},
            {ctx: "global", key: "!Home", group: "日期与标签", line: "   Alt+Home         回到今天"
                , fn: (*) => GoTodayFeature.Go()},
            {ctx: "editor", key: "$^g", group: "日期与标签", line: "   Ctrl+G           搜索跳转（日期 / 标签）"
                , fn: (*) => DateJumpFeature.ShowDialog()},
            {ctx: "editor", key: "$^+t", group: "日期与标签", line: "   Ctrl+Shift+T     为当前日期设置标签"
                , fn: (*) => TitleFeature.ShowDialog()}
        ]
    }

    static GetMetadata() {
        return {name: this.Name, desc: "笔记编辑与检索 · Alt+Z", order: 10
            , hotkeys: this.GetHotkeys()}
    }

    ; 只剩一个上下文：笔记窗口在前台。
    ; 搜索条退场后 editor / search 二选一收敛成一条 ——
    ; ⚠ 声明了却没人提供实现的 ctx，它的热键一条都不注册（见 .clinerules/02）。
    static GetContexts() {
        return {editor: (*) => WinActive("ahk_id " . State.GetGuiHwnd())}
    }
}