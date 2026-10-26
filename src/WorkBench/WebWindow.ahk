#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WebWindow —— 平台界面骨架：一个「装着 WebView2 的窗口」该有的全部动作
; ═══════════════════════════════════════════════════════════════════════════
;  v2.9 把 Alt+S 面板搬进 WebView2，v2.10 把这份生命周期抽出来并搬了提示词库；
;  编辑窗 / 日期跳转 / 启动提示沿用同一套。这几个窗口的**生命周期**完全一样：
;    建窗 → 隐藏态定位 → 露面 → 挂 WebView2 → 注册 Esc → 收起 / 再打开 → 换主题
;  差别只在「多大、停在哪、装哪个页面、提供哪些宿主方法」。所以把生命周期收在这里，
;  各窗口只留自己的那点业务 —— 否则同一份「隐藏态定位 + 露面后挂载」要抄好几遍，
;  而它俩正是踩过最多坑的地方（见 .clinerules/03）。
;
;  用法（每个窗口一个实例；Feature 自己 static 存着）：
;
;    win := WebWindow({
;        title:    Config.AppName . " · 提示词库"
;      , w: 620, h: 520                     ; 逻辑单位，缺省 520x480
;      , view:   "prompts"                  ; → /index.html?view=prompts
;      , dataDir: "prompts"                 ; → %LOCALAPPDATA%\SevenWork\WebView2-prompts
;      , handlers: PromptHostHandlers       ; 函数，调用后返回 hostObjects 方法表
;      , place:  "topright"                 ; center（缺省）/ topright / ""（不动）
;      , esc:    () => PromptWindowFeature.Hide()
;    })
;    win.Open() / win.Close() / win.IsOpen() / win.Hwnd() / win.ApplyTheme()
;
;  ⚠ 每个窗口的 **dataDir 必须不同**：同一个 user data folder 建不出第二个
;    CoreWebView2Environment（Chromium 的 profile 锁），而失败发生在 await() 里 ——
;    表现只是「窗口一片纯底色」。
; ═══════════════════════════════════════════════════════════════════════════

class WebWindow {
    ; ⚠ 字段名**不能与任何方法同名**（AHK v2 的属性名不区分大小写，也和方法共用
    ;   同一个命名空间）：这里原来叫 `_place`，与下面的私有方法 `_Place()` 撞车，
    ;   `this._place := x` 就被解析成「给方法赋值」→ 抛 "Property is read-only."，
    ;   而它发生在 __New 里，表现成「按 Alt+S 没反应、_error.log 只有一行 read-only」。
    ;   另一条同源的坑：字段也不能声明在类体里（类体变量是静态的）。
    ;   所以一律在 __New 里赋初值，且名字与方法错开（`_placeMode` vs `_Place()`）。
    __New(opts := "") {
        this._title    := this._Opt(opts, "title", "SevenWork")
        this._w        := this._Opt(opts, "w", 520)
        this._h        := this._Opt(opts, "h", 480)
        this._view     := this._Opt(opts, "view", "")
        this._dataDir  := this._Opt(opts, "dataDir", "")
        this._handlers := this._Opt(opts, "handlers", "")
        this._escFn    := this._Opt(opts, "esc", "")
        this._placeMode := this._Opt(opts, "place", "center")
        this._placeTop := this._Opt(opts, "placeTop", 120)
        ; place: "zone" 时落到哪个区域（record / aux / work 或中文标签）。
        this._zone := this._Opt(opts, "zone", "aux")
        this._onReady  := this._Opt(opts, "onReady", "")
        ; 标题栏是否保留「最小化」按钮。
        ; ⚠ 不能走 _Opt：它的规则是「空串即缺省」，而这里缺省值是 false，
        ;   false 与空串在它的判断里区分不开。只有管理面板这种**会停留操作的**
        ;   窗口才明确传 true；提示词库 / 笔记预览之类随手呼出的窗口保持原样。
        this._minimizeBox := (IsObject(opts) && opts.HasProp("minimizeBox"))
            ? !!opts.minimizeBox : false

        ; 运行时状态
        this._gui := ""
        this._hwnd := 0
        this._mounted := false
        this._escRegistered := false
        ; 入场重试的定时器闭包与轮次序号（见 _RevealWhenReady 的说明）
        ; ⚠ 存的是**函数对象**不是 ID：AHK v2 的 SetTimer 没有「传 ID 停表」这回事，
        ;   停表必须把当初那个 Callback 再交回去一次（`SetTimer(fn, 0)`）。
        this._revealTimer := ""
        this._revealSeq := 0
    }

    ; opts 是普通对象（字面量）；缺字段 / 空串一律退回缺省值 —— 调用方少写一项不至于报错
    _Opt(opts, key, def) {
        if !IsObject(opts) || !opts.HasProp(key)
            return def
        v := opts.%key%
        return (v = "") ? def : v
    }

    ; ─── 对外 ─────────────────────────────────────────────────────────

    Hwnd() => this._hwnd

    IsOpen() {
        return IsObject(this._gui) && this._hwnd
            && DllCall("user32\IsWindow", "ptr", this._hwnd, "int")
    }

    ; 窗口**当前看得见**吗 —— 与 IsOpen() 不是一回事。
    ; ⚠ IsOpen() 判的是「窗口存在」，而本类的收起是 Hide（保留 WebView2 不重建），
    ;   所以藏起来的窗口 IsOpen() 依然为真。拿它做「开关」判断会永远走同一分支：
    ;   按一次收起、再按还是收起 —— 面板从此打不开（实测过）。
    ; ⚠ 最小化也算「没显示」：它的 WS_VISIBLE 仍是 1，但 WinGetPos 会返回
    ;   -21333 一类的停放位，用户眼前什么也没有（.clinerules/03 记过这条）。
    IsShown() {
        return this.IsOpen()
            && DllCall("user32\IsWindowVisible", "ptr", this._hwnd, "int")
            && !DllCall("user32\IsIconic", "ptr", this._hwnd, "int")
    }

    ; 开着就直接露 + 补一次 Resize；没建 / 已被销毁就整座建起来
    Open() {
        if this.IsOpen()
            this.Activate()
        else
            this._Build()
    }

    Close() {
        if !this.IsOpen()
            return
        ; 收起前先停掉待执行的入场重试。
        ; ⚠ 这里**不能**再同步 Eval 让页面复位：ExecuteScriptAsync().await() 在页面
        ;   卡住 / 正在销毁时会把 Close 线程一起拖住，表现就是「叉和 Alt+P 都关不掉」。
        ;   窗口先隐藏；入场状态下次 Open 时页面自己重建即可，宁可少一次动画。
        this._CancelReveal()
        this._revealSeq += 1
        ; 隐藏失败（窗口已被系统销毁 / 句柄失效）不能让 Close 抛到 GUI Close 回调里，
        ; 否则下一次 Open 之前的状态永远清不干净。
        try this._gui.Hide()
        catch as e
            LogError(this._title . " 隐藏失败：" . e.Message)
        this._UnregisterEsc()
    }

    Toggle() {
        ; ⚠ 用 IsShown() 不是 IsOpen()：藏起来的窗口 IsOpen() 仍为真（见那两个方法）
        if this.IsShown()
            this.Close()
        else
            this.Open()
    }

    ; 已经藏着的时候再呼出：Show + 激活 + 补一次 Fill。
    ; ⚠ Fill 必须补：Chromium 子窗口在父窗口隐藏期间尺寸停滞，回来后会是一块
    ;   旧尺寸的画面（右侧留一条底色）。
    Activate() {
        ; 只有「显示窗口」失败才真正中止。
        ; ⚠ 不要把 WinActivate 和后面的 Fill / Esc 放进同一个 try：这两个项目里
        ;   反复出现过 Target window not found，而它一抛，Resize 和 Esc 重注册都会被
        ;   跳过 —— 表现成「窗口出来了，但内容区是旧尺寸 / 按 Esc 关不掉」。
        try {
            ; 最小化的窗口直接 Show() 只是把任务栏按钮点亮，用户眼前仍然什么都没有；
            ; 而它此刻的 WinGetPos 是屏幕外的停放位（-21333 一类），按它算 Fill / 摆位
            ; 都会落到看不见的地方。所以先恢复，再走常规的 Show + Fill。
            ; ⚠ 用 ShowWindow 而不是 WinRestore：后者按 WinTitle 匹配，在
            ;   「最小化 → 可见」那一瞬会抛 Target window not found；而且它一失败，
            ;   下面的 Show() 只会把任务栏按钮点亮，窗口仍停在 -32000。
            if DllCall("user32\IsIconic", "ptr", this._hwnd, "int")
                try DllCall("user32\ShowWindow", "ptr", this._hwnd, "int", 9)
            this._gui.Show()
        } catch as e {
            LogError(this._title . " 显示失败：" . e.Message)
            return
        }

        ; 激活是锦上添花；失败没有用户可见后果，不能连带跳过后面的步骤。
        if WinExist("ahk_id " . this._hwnd)
            try WinActivate("ahk_id " . this._hwnd)

        WebHostService.Resize(this._hwnd)
        ; ⚠ Esc 必须在这里补注册：Close() 会把它注销，而这条路径**不重建窗口**，
        ;   少了这一句就只有「第一次打开」能按 Esc —— 之后每次呼出都是死的，
        ;   而且日志里一个字都没有（注册失败才会记日志，这里是压根没注册）。
        if !this._escRegistered
            this._escRegistered := this._RegisterEsc()

        ; 已经建好的窗口再呼出：页面多半早就 ready，第一轮就命中；
        ; 但窗口是刚建完就藏、又马上打开的话仍在路上 —— 交给同一套重试，
        ; 别在这里直接 _Reveal()（那会在页面没就绪时白喊一次）。
        try this._RevealWhenReady()
        catch as e
            LogError(this._title . " 入场失败：" . e.Message)
    }

    ; 呼出粒子（冰晶迸发）。所有 Web 窗口共用一个入口 ——
    ; 从前只有笔记窗在自己的 Shown 事件里喊，面板 / 提示词窗一直没有粒子。
    ; ⚠ 页面还没挂好时 Eval 返回 {ok:false}，前端那句 `__swfx &&` 会短路，
    ;   不报错也不写日志 —— 首次打开没看见粒子是正常现象。
    ; ⚠ 与笔记窗自己的 reveal() 撞上无害：burst() 重复调用只打断上一次。
    _Reveal() {
        if !this._mounted || !this.IsOpen()
            return
        WebHostService.Eval("window.__swfx&&window.__swfx.reveal()", this._hwnd)
    }

    ; 页面就绪判据：**Vue 已挂载** + **主题已应用**。
    ; ⚠ 不能只看 NavigationCompleted：那只说明文档加载完，Vue 的 onMounted 里
    ;   还在 await getTheme()，此时 reveal() 会被页面里的 `!dataset.style` 短路
    ;   （主文档 .clinerules/02 记过这条：早喊会被 && 吞掉，表现为首开没有入场）。
    ; ⚠ #app 有子元素才说明 Vue 真的渲染了 —— 脚本下载完但挂载失败时会一直为空。
    ; ⚠ 判据字符串**不要**存进类变量再 this. 取：实测 v2 报
    ;   「This value of type "WebWindow" has no property named "_READY_JS"」，
    ;   而 OnError 之后整段重试直接被跳过 —— 表现是「窗口一切正常、只是没有入场」，
    ;   日志里只有那一行 property 报错。直接内联，少一层运行时查找。

    ; 等页面就绪再播入场。tries 上限 40 × 120ms ≈ 4.8s：
    ; 超时也照样播一次 —— 宁可晚一点，也别让首开彻底没有入场。
    ; ⚠ 判据是**两个 data 属性**：
    ;   data-theme 说明 applyTheme 跑过了（前端据此决定整套 --sw-*）；
    ;   data-ready 由各视图在**首屏数据落定**后自己挂上（ahk.ts 的 markReady）。
    ;   原来只看「#app 有子元素」—— 那只是 Vue 挂上了，PanelView 的 rows 还在
    ;   fetchPanel() 路上，入场会从空壳开始淡入、数据后到再跳一次。
    ; ⚠ 每轮都过两道闸：窗口还在显示（不是被收起）、WebView2 还挂着。
    ;   用户按完 Alt+S 立刻再按一次收起时，这里必须停手，否则页面在后台把
    ;   动画跑完，下次打开第一帧就是终态（就是 .clinerules/02 说的「闪一下」）。
    ;
    ; ⚠ 重试必须**可取消**，并且带序号：
    ;   · 定时器闭包存进 _revealTimer —— 否则 Close() 停不掉它，窗口藏了还在跑；
    ;   · 每次 _RevealWhenReady 领一个 seq，回调先比对 _revealSeq：
    ;     快速「开 → 关 → 开」时，前一轮排的 -120ms 会在新窗口里执行，
    ;     它带着**旧**的 tries 计数，会提前撞到 40 上限、或者抢在新一轮之前播入场。
    ;   ⚠ SetTimer 的箭头函数每次新建都是新对象，停它必须靠存下来的那个引用。
    _RevealWhenReady(tries := 0) {
        if (tries = 0) {
            this._CancelReveal()
            this._revealSeq += 1
        }
        seq := this._revealSeq
        if !this._mounted || !IsObject(this._gui)
            return
        if !DllCall("user32\IsWindowVisible", "ptr", this._hwnd, "int")
            return
        ; 最小化也算「用户看不见」：它的 WS_VISIBLE 仍是 1，此时播入场等于
        ; 在后台把 480ms 跑完，还原窗口时第一帧就是终态（看起来「没有动画」）。
        if DllCall("user32\IsIconic", "ptr", this._hwnd, "int")
            return
        r := WebHostService.Eval(
            "!!document.documentElement.dataset.theme && !!document.documentElement.dataset.ready"
            , this._hwnd)
        if (r.ok && r.value = "true") || tries >= 40 {
            this._Reveal()
            return
        }
        ; ⚠ 闭包必须存进字段：不存就没法取消（见 _CancelReveal）。
        ;   每次新建的箭头函数都是新对象，别指望 SetTimer 能按「内容相同」认回来。
        fn := () => this._RevealStep(seq, tries + 1)
        this._revealTimer := fn
        SetTimer(fn, -120)
    }

    ; 一轮重试的入口：先确认自己还是当前那一轮（序号没被新一轮顶掉）再往下走
    _RevealStep(seq, tries) {
        if (seq != this._revealSeq)
            return
        this._RevealWhenReady(tries)
    }

    ; 停掉待执行的重试。Close() 与每一轮的第一拍都会调 —— 幂等。
    ; ⚠ 必须把**存下来的那个函数对象**交回去：`SetTimer(数字, 0)` 在 v2 里是把数字
    ;   当 Callback 用，直接抛错（而这里在 try 里，表现成「定时器根本没停」）。
    ; ⚠ 已经触发过的一次性定时器再停一次会失败 —— try 兜住，不该打断收窗流程。
    _CancelReveal() {
        fn := this._revealTimer
        this._revealTimer := ""
        if IsObject(fn) {
            try SetTimer(fn, 0)
        }
    }

    ; 换主题：只换窗口底色 + 把 --sw-* 推给页面，**不重建**。
    ; 这样当前停在哪一页、输入框里的字都保持不变（原生控件版只能关掉重开）。
    ApplyTheme() {
        if !this.IsOpen()
            return
        p := ThemeService.Palette()
        try this._gui.BackColor := p.win
        UiPaint.WindowTheme(this._hwnd, p.dark)
        ; ⚠ 顺序：先立背板、再决定标题栏染不染。
        ;   v2.14 起 caption 恒为 true —— 原设计是「背板成功就把底色交给 mica/acrylic」，
        ;   但实测（.clinerules/03）WebView2 一挂上，材质就不再出现，等于永远在等一个
        ;   不会来的背板：标题栏保持系统浅色、内容却是深灰，一窗两种明暗。
        UiPaint.Glass(this._hwnd, p.style, p.win)
        UiPaint.TitleBar(this._hwnd, p.win, p.text, true)
        ; 页面没起来时 Eval 返回 {ok:false}，忽略即可 —— 页面 onMounted 还会
        ; 再 getTheme 一次，不会留旧色。
        if this._mounted
            WebHostService.Eval("window.__sevenwork&&window.__sevenwork.applyTheme("
                . ThemeJson() . ")", this._hwnd)
    }

    ; ─── 建窗口 ───────────────────────────────────────────────────────

    _Build() {
        p := ThemeService.Palette()

        ; 不加 +AlwaysOnTop：窗口一置顶，DirSelect 之类的系统对话框会被压在
        ;   下面看不见（它是独立的顶层窗口，owner 置顶时它也跟着被盖）。
        ; ⚠ 最小化按钮由调用方决定（WebWindow 的 minimizeBox）：管理面板是常驻窗口，
        ;   用户会把它挪去任务栏；其余小窗仍禁用，免得标题栏多一个用不到的按钮。
        guiOpts := "-MaximizeBox" . (this._minimizeBox ? "" : " -MinimizeBox")
        g := Gui(guiOpts, this._title)
        g.SetFont("s10", "Microsoft YaHei UI")
        g.BackColor := p.win
        ; 非客户区（标题栏 / 边框）的玻璃背衬 —— 客户区整个交给 WebView2。
        ; ⚠ caption 恒 true：WebView2 挂上后背板材质不出现（实测，见 .clinerules/03），
        ;   把底色交给系统只会得到一条浅色标题栏压着深色内容。
        ; ⚠ 这里只立背板 + 暗色窗口主题；**标题栏染色在 Show() 之后**（见下）。
        UiPaint.WindowTheme(g.Hwnd, p.dark)
        UiPaint.Glass(g.Hwnd, p.style, p.win)

        this._gui := g
        this._hwnd := g.Hwnd

        ; 点 × 只藏不销毁 —— WebView2 重建要 300ms 上下，而这些窗口都是随手呼出的。
        ; ⚠ 回调返回 true 明确阻止默认关闭：别指望「Close() 里 Hide 了就不销毁」，
        ;   否则窗口被销毁后 WebView2 槽位与 _mounted 还会留在旧句柄上。
        g.OnEvent("Close", (*) => (this.Close(), true))

        ; 隐藏态完成定位再露面：先 Show 再 WinMove 会「飘一下」（.clinerules/03）
        g.Show("w" . this._w . " h" . this._h . " Hide")
        this._Place()
        g.Show()

        ; ⚠ 标题栏染色必须在 **Show() 之后**：Show 之前设的 DWM 属性会被窗口的
        ;   创建/首次显示流程重置。实测 Win11 26200：在 Show 前调 TitleBar，
        ;   标题栏一个字都没变（而且 DllCall 全返回 0，看起来「成功了」）。
        UiPaint.TitleBar(this._hwnd, p.win, p.text, true)

        this._escRegistered := this._RegisterEsc()

        ; ⚠ 挂载放在**露面之后**：隐藏态挂 WebView2 时 Chromium 会留在 SW_HIDE，
        ;   父窗口再显示也不回来（表现为「窗口出来了、内容区一片纯底色」）。
        ;   代价是首帧多等 ~300ms，由 Mount 的 bgColor 兜住（不闪白）。
        this._Mount()

        fn := this._onReady
        if IsObject(fn)
            try fn(this)

        ; 首次露面的入场：等页面**真的**就绪再喊，而不是赌一个 700ms。
        ; 就绪判据与重试上限见 _RevealWhenReady。
        this._RevealWhenReady()
    }

    ; 摆位：center    = 主屏工作区居中偏上（不写死坐标，换显示器 / 改分辨率都不用改代码）
    ;       topright  = 工作区右上角，右边距 Config.PlaceRight、顶边下移 _placeTop
    ;       zone      = 指定区域（_zone）的中心；比区域宽时向左溢出，再夹到工作区
    ;       left      = 工作区左上角，保留窗口自身尺寸（管理面板用）
    ;       其它      = 交给窗口系统
    _Place() {
        if (this._placeMode != "center" && this._placeMode != "topright"
            && this._placeMode != "zone" && this._placeMode != "left")
            return

        ; left：管理面板初始落在工作区左上角，保留面板自身的宽高，不填满工作区；
        ; 右侧记录区 / 辅助区留给笔记和终端，三者不互相覆盖。
        if (this._placeMode = "left") {
            res := ZoneService.Place(this._hwnd, "work", {fill: false, allowHidden: true})
            if res.ok
                return
            ; 小屏 / 区域不可用时继续走 center 兜底，至少窗口在屏幕内。
        }

        rect := WindowProbe.PrimaryWorkArea()
        if !IsObject(rect)
            return

        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)   ; Show("Hide") 过的窗口 WinGetPos 读不到
        try {
            x := 0, y := 0, w := 0, h := 0
            ; 刚 Show("Hide") 的窗口尺寸要几轮才稳定（DPI 缩放是异步的）。
            ; ⚠ 判据里必须有 `w > 200`：窗口刚建出来时 WinGetPos 可能先读到
            ;   10 一类的中途值，而「两次相同就 break」会把它当终值 —— 那样居中
            ;   用的是「一个 10px 宽的窗口」，落点会整体偏到屏幕右侧；下面的高度
            ;   上限判断也会因为 h 同样是中途值而失效。
            ;   本机终值 1432x1106（940x700 逻辑 @150% 缩放）。
            ; ⚠ 上限 60×10ms：DPI 稳定要一点时间，原先的 40×5ms（200ms）不够。
            ; ⚠ 2026-10-23 更正：曾把 `(2560-1432)/2 = 564` 当成「本该是 137」
            ;   的错误落点 —— 那是截图工具按虚拟化坐标裁剪造成的误判（物理屏
            ;   2560x1600、缩放下 PowerShell 报 1707x1067）。564 本身是对的。
            prevW := -1, prevH := -1
            loop 60 {
                try WinGetPos(&x, &y, &w, &h, "ahk_id " . this._hwnd)
                if (w = prevW && h = prevH && w > 200)
                    break
                prevW := w, prevH := h
                Sleep 10
            }
            if (w <= 0 || h <= 0)
                return

            ; ⚠ 高度上限：窗口不能高过工作区（防御小屏用）。
            ;   窗口物理高度固定 ≈ 1106（700 逻辑 × 150% + 标题栏）。本机 2560×1600
            ;   绰绰有余，但 1366×768 一类的屏会放不下 —— 那时底栏（保存 / 关闭）
            ;   会被裁到屏幕外，用户会以为「这个面板根本没有底栏」。
            ;   正文是 overflow-y:auto，收缩后自己出滚动条，不丢内容。
            ;   ⚠ 必须在算位置之前收缩：居中公式用了 h，先摆位再缩会让窗口上下错位。
            ;   ⚠ rect 来自 MonitorGetWorkArea，是**物理**像素；窗口 w/h 来自 WinGetPos，
            ;     也是物理 —— 两者同单位才能比较。别拿 Gui.Move 的逻辑单位混进来。
            if (h > rect.h - 8) {
                WinMove(, , , rect.h - 8, "ahk_id " . this._hwnd)
                try WinGetPos(&x, &y, &w, &h, "ahk_id " . this._hwnd)
            }

            if (this._placeMode = "zone") {
                z := ZoneService.Rect(this._zone)
                if IsObject(z) {
                    ; 填满区域（与终端 / 浏览器同宽同高）：浮层也走「严丝合缝」。
                    ; 可见矩形 → 物理外框，交给 WinMove；WebView2 在 OnSize 后自己 Fill。
                    frame := WindowProbe.InvisibleFrame(this._hwnd)
                    phys := RectMath.Physical({x: z.x, y: z.y, w: z.w, h: z.h, frame: frame})
                    WinMove(phys.x, phys.y, phys.w, phys.h, "ahk_id " . this._hwnd)
                    return
                }
                ; 区域不可用（小屏 no-fit）→ 退回 center，别停在 AHK 默认点
            }

            if (this._placeMode = "topright") {
                pos := RectMath.TopRightRect(rect, w, h, Config.PlaceRight, this._placeTop)
                if IsObject(pos)
                    WinMove(pos.x, pos.y, , , "ahk_id " . this._hwnd)
            } else {
                ; ⚠ WinMove 收**物理像素**，与 WinGetPos 同单位；别用 Gui.Move —— 那会再乘一次 DPI。
                WinMove(rect.x + (rect.w - w) // 2, rect.y + (rect.h - h) // 3
                    , , , "ahk_id " . this._hwnd)
            }
        } catch as e {
            LogError(this._title . " 摆位失败：" . e.Message)
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }

    ; ─── 挂 WebView2 ───────────────────────────────────────────────────

    _Mount() {
        dist := WebHostService.DistDir()
        if (dist = "") {
            LogError(this._title . " 挂载失败：找不到前端产物目录（web\dist，先跑 npm run build）")
            return
        }

        p := ThemeService.Palette()
        ; ⚠ dataDir 必须逐窗不同，理由见文件头。
        ; ⚠ 首帧色是 AARRGGBB（COREWEBVIEW2_COLOR），不是 Win32 的 COLORREF，
        ;   别把 R/B 反过来（那会把米黄变成淡蓝）。
        r := WebHostService.Mount(this._hwnd, dist, "app.local"
            , 0xFF000000 | Integer("0x" . p.edBg)
            , EnvGet("LOCALAPPDATA") . "\SevenWork\WebView2-" . this._dataDir)
        if !r.ok {
            LogError(this._title . " WebView2 挂载失败：" . r.reason)
            return
        }

        ; ⚠ hostObjects 按 WebView 实例注册：每个窗口有自己的一张表，不能指望
        ;   别的窗口绑过的 "ahk" 在这边也在。
        fn := this._handlers
        if IsObject(fn)
            WebHostService.Bind("ahk", fn(), this._hwnd)

        url := "/index.html?" . (this._view = "" ? "" : "view=" . this._view . "&")
            . "_=" . A_TickCount
        ; ⚠ 末尾那个 `_=` 是**防缓存**用的，不是装饰：WebView2 会把 app.local 的
        ;   index.html / index.css 缓存在 user data folder 里，构建后 URL 不变就可能
        ;   一直加载旧文件 —— 表现成「改了前端、重启也没变」。
        ;   本地文件重读一次的成本可以忽略，换一个参数换一份新构建。
        n := WebHostService.Navigate(url, this._hwnd)
        if !n.ok {
            LogError(this._title . " 导航失败：" . n.reason)
            return
        }
        this._mounted := true
        ; 可见态挂载本来就该有尺寸，但 Fill 一次更保险（子窗口刚建出来是 0×0）
        WebHostService.Resize(this._hwnd)
    }

    ; ─── Esc：只在这个窗口激活时生效 ────────────────────────────────────
    ; 不进模块热键表：这是窗口自己的键，藏起来时立刻注销。
    ; ⚠ 必须用 HotIfWinActive 钩子、**不能**靠 Gui 的 Escape 事件 ——
    ;   键盘焦点在 WebView2 子窗口里，Gui 收不到那个事件。
    ; ⚠ 回调要包成**变参**箭头函数 `(*) => …`：Hotkey 会往回调里塞热键名，
    ;   零参闭包（`() => …`）直接报 `Invalid callback function`。
    ; ⚠ 注册失败要记日志 —— 声明了却没人实现的键表现为「按了没反应」。
    _RegisterEsc() {
        userFn := this._escFn
        if IsObject(userFn)
            cb := (*) => userFn()
        else
            cb := (*) => this.Close()
        HotIfWinActive(this._title)
        try
            Hotkey("Esc", cb, "On")
        catch as e {
            LogError(this._title . " Esc 注册失败：" . e.Message)
            HotIf()
            return false
        }
        HotIf()
        return true
    }

    _UnregisterEsc() {
        if !this._escRegistered
            return
        this._escRegistered := false
        try {
            HotIfWinActive(this._title)
            Hotkey("Esc", "Off")
        } catch as e {
            LogError(this._title . " Esc 注销失败：" . e.Message)
        }
        HotIf()
    }
}
