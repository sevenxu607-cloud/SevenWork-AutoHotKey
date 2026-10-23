#Requires AutoHotkey v2.0
; ======================================================================
;  WindowFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class WindowFeature {
    ; ═══ 伴生窗口适配（peer docking）═══
    ; 「呼出一个外部窗口 → 笔记窗口自动让位 / 堆叠」这套机制对所有 Feature 通用，
    ; 不限于终端 —— 以后要换成资源管理器、Obsidian、浏览器，照同一份契约做即可。
    ; 契约就三个事件，详见 README「开发指南 → 添加呼出外部窗口的功能」：
    ;   Launcher.Preparing  外部窗口**即将露面**   → 笔记窗口先退场（别当着用户的面搬它）
    ;   Launcher.Opened     已落位，带 {hwnd, x, y, w, h}（**真实**窗口矩形）→ 笔记窗口按它摆
    ;   Launcher.Failed     最终没起来              → 把刚才退场的笔记窗口还回来
    ; 发布方只管广播这三条；订阅、摆放算法全在本类里，接入新窗口不用改它。
    ;
    ; Phase 5b：真正搬窗口改由 Move 事件执行 —— 平台协调器算好堆叠几何后广播
    ;   SevenNote.Move（本类订阅，搬笔记窗口）与 Launcher.Move（LauncherModule 订阅，
    ;   搬伙伴窗口）。本类不再直接 WinMove 伴生窗口。
    ;
    ; ⚠ **只适配一次**：真正会动笔记窗口的只有「第一次」，适配完就置位 _docked，
    ;   此后三条事件一律不再碰它（语义与理由见 _docked 的注释）。所以上面那句
    ;   「先退场」也只发生在第一次 —— 过了那一回，伙伴再怎么呼出隐藏，笔记都纹丝不动。
    ;
    ; 伴生窗口的位置与尺寸（发布方摆好后广播过来）。
    ; 非对象 = 屏幕上没有伴生窗口，呼出时按记忆位置 / 默认落点走。
    static _peerRect := ""

    ; 当前窗口位置是不是「与伴生窗口上下堆叠」摆出来的。是的话收窗口时不覆盖位置记忆 ——
    ; 那份坐标和高度都是临时算的（见 _StackWithPeer），不该被当成用户摆的格局。
    static _stacked := false

    ; 堆叠前窗口的位置与尺寸。堆叠是临时布局，脱离（伴生窗口关掉）后要照这份底稿还原 ——
    ; 堆叠会把窗口压矮（实测 885 → 513），不还原的话单独显示时窗口就又扁又小。
    static _preStackRect := ""

    ; 是否已经为伴生窗口「适配过一次」。置位之后，Launcher.* 三条事件一律不再碰笔记窗口 ——
    ; 这是本机制现在的核心语义：用顺了之后，笔记的尺寸位置就是用户自己的格局，
    ; 不该每次呼出终端 / DeepSeek 都被重算、重摆一遍。
    ;
    ; ⚠ 刻意**不落盘**。位置记忆（State._hiddenX 那一组）本来就是纯内存的，重启即丢、
    ;   笔记回到默认落点 —— 那时本来就需要重新落位一次。于是「重启程序 = 重新适配一次」
    ;   这个逃生门是自然存在的，不必额外加配置项，也不必往用户的 _config.ini 里写状态。
    static _docked := false

    ; ═══ 首开默认客户区（**逻辑单位**）═══
    ; 原来这里不设尺寸、「交给 AHK 按 DPI 决定」—— 那时有 6 个原生控件把窗口撑到
    ; 合理大小。v2.9 控件全搬进网页后，空 Gui 只剩 `+MinSize450x300` 撑着，
    ; 实测首开外框 772×573 物理 = **514×382 逻辑**（客户区更小），写两行字就要手动拉。
    ; 540×660 的比例（0.82）偏竖，适合成篇文字；本机 150% 下占屏高 62%。
    ; ⚠ 只用于「没有可用记忆」的首开；有记忆时一律按记忆的尺寸还原。
    static DefaultW := 540
    static DefaultH := 660

    ; ─── 挂载：订阅伴生窗口生命周期 ───
    ; 组合根在 LauncherModule.Init() 之前调用 —— 监听要在第一次 Alt+C 之前就位。
    static Init() {
        EventBus.On("Launcher.Opened",    (rect) => this._OnLauncherOpened(rect))
        EventBus.On("Launcher.Preparing", (*)    => this._CollapseForLauncher())
        EventBus.On("Launcher.Failed",    (*)    => this._RestoreAfterFailedLauncher())
        ; Phase 5b：平台算好的笔记窗口目标矩形（物理像素）由这里落到窗口上。
        EventBus.On("SevenNote.Move",     (data) => this._OnNoteMove(data))
    }

    ; 伴生窗口马上要露面，先让笔记窗口退场。**只在第一次** —— 已经适配过的格局不再动。
    ;
    ; 收起来不是目的，是为了让随后的「适配」退化成一次纯粹的呼出：伙伴落位后
    ; _AdaptToPeer 会看到窗口并不在显示，于是走 Show() —— 而那条路径本来就是
    ; 「隐藏态下把位置尺寸算好、最后一次性露面」（见 _PlaceWindow）。不这么做的话，
    ; 就是当着用户的面把一个**已经显示**的窗口搬去堆叠位，平移与控件重排连在一起，
    ; 看着就是「飘一下」。
    ;
    ; 用 Hide() 而不是裸的 g.Hide()：Hide() 内含位置记忆（堆叠态下改用堆叠前的底稿），
    ; 与用户自己按 Alt+Z 收起完全同一条路。这份记忆随后正好被 _AdaptToPeer 拿来
    ; 判断「伙伴会不会压到笔记原来待的地方」。
    static _CollapseForLauncher() {
        if this._docked
            return
        if !State.GetGuiHwnd()
            return
        if this.IsShowing()
            this.Hide()
    }

    ; 伴生窗口最终没起来（Run 抛错，或等满超时都找不到窗口）—— 刚才为它让位而收起的
    ; 窗口得还回来。少了这条兜底，用户按一次 Alt+C，屏幕上就什么都剩不下。
    ; 记忆里那份 _peerRect 若指向已消失的窗口，_StackWithPeer 开头有 alive
    ; 检查兜着，Show() 会自行回落到记忆位置 / 默认落点。
    static _RestoreAfterFailedLauncher() {
        if !State.GetGuiHwnd()
            return
        if this.IsShowing()
            return
        this.Show()
    }

    ; 记下伴生窗口的位置，再让笔记窗口适配 —— 两步都要做：
    ; 少记一步（this._peerRect := rect）的话，_StackWithPeer 没有分区依据，
    ; 会直接退回记忆位置。
    static _OnLauncherOpened(rect) {
        this._peerRect := rect
        this._AdaptToPeer(rect)
    }

    ; 伴生窗口落位了 → 决定笔记窗口要不要动。三种情形：
    ;   ① 已经适配过       → 一个坐标都不改（_docked）
    ;   ② 伙伴没压到它身上 → 原样还回来，一个坐标都不改，然后固定下来
    ;   ③ 真压上了         → 按原设计适配一次，然后固定下来
    ;
    ; 「② 不冲突就不动」是这套机制现在的要害：笔记摆在左边、伙伴在右下，两者互不
    ; 妨碍 —— 那就谁也别动谁。改之前是无条件重算重摆，于是每次呼出都把用户自己
    ; 摆好的格局冲掉，笔记窗口次次跟着伙伴动。
    static _AdaptToPeer(rect) {
        if !State.GetGuiHwnd()
            return
        if this._docked
            return

        ghwnd := State.GetGuiHwnd()

        ; 笔记此刻多半已被 _CollapseForLauncher 收走，位置取 Hide 时刚记下的那份 ——
        ; 那正是「笔记原来待的地方」，该拿它去比。万一它还显示着（订阅缺失，或将来
        ; 有别的来源广播 Launcher.Opened），就现量一个。
        noteRect := State.HasHiddenRect()
            ? State.GetHiddenRect()
            : this._CurrentRect(ghwnd)

        if IsObject(noteRect) && IsObject(rect) && !this._RectsOverlap(noteRect, rect) {
            ; ── 不冲突：原样还回来，坐标尺寸一字不动 ──
            ; ⚠ 必须**先固定、再 Show**。Show 内部会走 _PlaceWindow → _StackWithPeer，
            ;   那时 _docked 已置位，于是它退回「记忆位置」= 刚 Hide 时记下的那份，
            ;   窗口正好回到原处。顺序反了就会在 Show 里被重新堆叠一次，白固定。
            this._FreezeDocked(ghwnd)
            if !this.IsShowing()
                this.Show()
            return
        }

        ; ── 冲突（或量不到笔记矩形，保守当作冲突）：按原设计适配一次 ──
        ; ⚠ 先收再摆：_StackWithPeer 要改位置改尺寸，这一整段不该被看见
        ;   （理由同 _CollapseForLauncher）。若它已经收过，这次调用会跳过。
        if this.IsShowing()
            this.Hide()
        this.Show()
        ; 真摆成了才算「适配过一次」：没摆成（屏幕太矮等，_StackWithPeer 返回 false
        ; 让窗口退回了记忆位置）就不置位，留着以后还有机会再试。
        if this._stacked
            this._FreezeDocked(ghwnd)
    }

    ; SevenNote.Move：平台协调器算好的笔记窗口**物理外框**。
    ; 实际搬运交给平台能力 PlacementExecutor —— 它自己处理隐藏窗口与最小化守卫，
    ; 失败时返回 {ok:false, reason}，这里只负责记录，不再让异常穿透到事件总线。
    static _OnNoteMove(data) {
        if !IsObject(data)
            return
        if !(data.HasProp("hwnd") && data.HasProp("x") && data.HasProp("y")
            && data.HasProp("w") && data.HasProp("h"))
            return
        if !(IsNumber(data.x) && IsNumber(data.y)
            && IsNumber(data.w) && IsNumber(data.h))
            return
        if (data.w <= 0 || data.h <= 0)
            return
        ; 只接自己这扇笔记窗口的 Move，避免误搬别的 hwnd
        if (data.hwnd != State.GetGuiHwnd())
            return

        res := PlacementExecutor.Move(data.hwnd
            , {x: data.x, y: data.y, w: data.w, h: data.h}, true)
        if !res.ok
            LogError("笔记窗口移动失败：" . res.reason)
    }

    ; 两个矩形是否相交 —— 即「有没有一块地方同时被两个窗口占着」。
    ; 两个入参都只用到 {x, y, w, h} 这四个字段，不关心别的。
    static _RectsOverlap(a, b) {
        return RectMath.Overlaps(a, b)
    }

    ; 窗口当前的矩形；窗口没了、或位置不可用（最小化停放位）时返回 ""。
    ; ⚠ 要允许隐藏窗口：笔记可能正处在 Hide() 之后的状态，而 WinGetPos
    ;   默认忽略隐藏窗口、直接抛错。细节收在 WindowProbe.RectOf。
    static _CurrentRect(hwnd) {
        rect := WindowProbe.RectOf(hwnd, true)
        if !IsObject(rect)
            return ""
        if !this.IsUsableRect(rect.x, rect.y, rect.w, rect.h)
            return ""
        return rect
    }

    ; 把这次适配的结果「转正」成用户格局，此后不再联动。三件事都要做，少一件都露馅：
    ;   ① 留下的矩形成为正式格局 —— 在这之前它是 _preStackRect 那份临时底稿；
    ;   ② 清掉堆叠态标记，_RememberPosition 从此走非堆叠分支，日后如实记录用户的拖动；
    ;   ③ 置位 _docked。
    ; ⚠ 只有窗口正显示着才量矩形：隐藏态下 State 里已经有 Hide() 记下的那份（就是
    ;   用户原来的位置），留着它才对 —— 那时量出来的也是同一个值，多此一举。
    static _FreezeDocked(ghwnd) {
        this._docked := true
        this._stacked := false
        this._preStackRect := ""
        if !this.IsShowing()
            return
        rect := this._CurrentRect(ghwnd)
        if IsObject(rect)
            State.SetHiddenRect(rect.x, rect.y, rect.w, rect.h)
    }

    ; ─── 入口：Alt+Z ───
    static Toggle() {
        if this.IsShowing()
            this.Hide()
        else
            this.Show()
    }

    ; 判断“当前是否正在显示”。
    ; 注意：最小化窗口的 WS_VISIBLE 仍是 1，必须连同 IsIconic 一起排除；
    ; 否则最小化状态下按 Alt+Z 会被误判成“正在显示”而执行隐藏，越按越找不着。
    static IsShowing() {
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return false
        return DllCall("IsWindowVisible", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
    }

    ; ─── 收起：先广播、再记位置、最后隐藏 ───
    static Hide() {
        g := State.GetGui()
        ; ⚠ 先存盘、存住了才收：收起等于「这次的改动先放着」，而保存失败时窗口一藏，
        ;   用户连状态栏那行提示都看不见，下次打开还是旧内容。
        ;   recoverable = 当前没有可丢的内容（冷启动 / 页面还没挂），那种放行。
        saved := NoteSessionService.Save()
        if !saved.ok && !(saved.HasProp("recoverable") && saved.recoverable)
            return false

        ; 通知「即将收起」—— 保存已在上面做完，订阅者不用再存一次
        EventBus.Emit("Window.BeforeHide")
        ; ⚠ 必须显式传 hwnd：WebHostService 是多实例的（面板 / 提示词库 / 笔记窗各一份），
        ;   无参会落到「最近挂载的窗口」—— 收了笔记窗却把面板的入场状态复位掉，
        ;   两个窗口的动画从此互相干扰，而日志里一个字都不会有。
        if g
            WebHostService.Eval("window.__swfx&&window.__swfx.reset()", g.Hwnd)
        this._RememberPosition(g.Hwnd)
        g.Hide()
    }

    ; ─── 呼出：定位 → 激活 ───
    ; v2.9：编辑区换成 WebView2 后，这里不再有 RichEdit 的「暂停重绘 / 还原光标」——
    ; 光标由页面自己管（Milkdown 会记住选区），重绘由 Chromium 合成。
    ; ⚠ 别把 _PlaceWindow 包进 try：它前后曾经挂着 SendMessage(0x000B)，而
    ;   GetEd() 现在恒为 0，那条 SendMessage 会抛错、把定位整段跳过 ——
    ;   表现是「按 Alt+Z 什么窗口都不出来」，而且日志里只有一句 Target window not found。
    static Show() {
        g := State.GetGui()
        ghwnd := g.Hwnd
        this._PlaceWindow(g, ghwnd)
        ; ⚠ g.Show() 已经激活过一次；这一句是为了「窗口早就存在、只是被别的窗口
        ;   盖住」的情况。它偶发抛 Target window not found（隐藏→可见那一瞬
        ;   WinTitle 匹配不到），而窗口其实已经出来了 —— 失败没有用户可见后果，
        ;   不该让它变成一条错误日志。先确认窗口确实可匹配，再激活。
        if WinExist("ahk_id " . ghwnd)
            try WinActivate("ahk_id " . ghwnd)
        ; Phase 3b：把「笔记已落位」交给平台协调器记录。放在 Window.Shown 之前，
        ; 让订阅者拿到的是最终矩形；事件本身不改变窗口行为。
        rect := this._CurrentRect(ghwnd)
        if IsObject(rect)
            EventBus.Emit("SevenNote.WindowReady"
                , {hwnd: ghwnd, x: rect.x, y: rect.y, w: rect.w, h: rect.h})
        EventBus.Emit("Window.Shown")
    }

    ; ═══ 位置记忆与定位 ═══

    ; 记住当前窗口位置，供下次呼出还原。
    ; 只记屏幕内的有效位置；屏幕外坐标（最小化停放位、已拔掉的外接屏）一律丢弃
    ; 并清空记忆，让 Show() 回落到默认落点——否则窗口会被永久搬到看不见的地方。
    ;
    ; 若当前是按「与伴生窗口上下堆叠」摆出来的，位置和高度都是临时算的 —— 改用堆叠前的底稿，
    ; 不覆盖记忆；否则下次终端不在时，窗口会以那个被压矮的尺寸单独现身（实测 744x513）。
    static _RememberPosition(hwnd) {
        ; ⚠ 底稿**用完不丢**：堆叠态下隐藏只是「暂时收起来」，用户随时会 Alt+C 再摆回来，
        ;   那时仍要按同一份底稿记。真正作废是在下面的非堆叠分支 —— 那时窗口的位置
        ;   就是用户自己的格局，底稿已完成使命。
        if this._stacked {
            this._stacked := false
            pre := this._preStackRect
            if IsObject(pre) && this.IsUsableRect(pre.x, pre.y, pre.w, pre.h) {
                State.SetHiddenRect(pre.x, pre.y, pre.w, pre.h)
                return
            }
            State.ClearHiddenRect()
            return
        }
        ; 非堆叠态：当前坐标就是用户自己的格局 —— 正常记忆，并作废旧底稿
        this._preStackRect := ""
        try
            WinGetPos(&rectX, &rectY, &rectW, &rectH, "ahk_id " . hwnd)
        catch
            return
        if this.IsUsableRect(rectX, rectY, rectW, rectH)
            State.SetHiddenRect(rectX, rectY, rectW, rectH)
        else
            State.ClearHiddenRect()
    }

    ; 位置可用性：必须与某个显示器的工作区相交。
    ; 最小化窗口的坐标是 -32000 一类的停放位（会按 DPI 缩放成 -21333 等），
    ; 而它的 WS_VISIBLE 仍为真，只靠可见性判断拦不住。
    static IsUsableRect(x, y, w, h) {
        return WindowProbe.IsUsableRect(x, y, w, h)
    }

    ; 定位：坐标优先取记忆位置，不可用则回落默认落点。
    ;
    ; ⚠ 全程在「隐藏」状态下完成 —— 先 Show 再 Move 会让窗口先在 AHK 的默认落点露面，
    ;   约 190ms 后才跳到目标位置（实测 924,357 → 1629,238），视觉上就是「飘一下」。
    ;   Show("Hide") 先把窗口建好、让 OnSize 把控件布局跑完，位置算准了再一次性露面。
    ;
    ; ⚠ 尺寸不硬设 —— 本机 150% 缩放（A_ScreenDPI = 144）下 Gui 控件坐标会按 DPI 放大 1.5 倍，
    ;   窗口最小尺寸由控件固有尺寸决定（逻辑 +MinSize450x300 → 物理 675x450），
    ;   而 Gui 控件坐标是「逻辑单位」、WinMove 收「物理像素」。
    ;   实测把 450x550 直接传给 WinMove：宽被 675 的最小宽拒绝、高却通过了，窗口被压矮
    ;   （881 → 550）。故尺寸交给 AHK 按 DPI 自行决定。
    static _PlaceWindow(g, ghwnd) {
        ; 定位全程在隐藏状态下做：Show("Hide") 过的窗口 WS_VISIBLE 仍是 0，
        ; 而 WinGetPos 默认不认隐藏窗口（会直接抛错）—— 项目里 BackdropFeature 踩过同一个坑。
        ; 用完恢复原值，免得改变其它代码的可见性语义。
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            ; ⚠ 首开与再开的尺寸来源不同：
            ;   · 没有可用记忆 → 按 DefaultW/DefaultH 建窗（Gui.Show 收**逻辑单位**）；
            ;   · 有记忆 → **不带尺寸**，交由下面那句 WinMove 按记忆（**物理像素**）还原。
            ;   两者混用会二次放大（.clinerules/03 记过 g.Move 的 1629→2444）。
            mem := State.GetHiddenRect()
            if State.HasHiddenRect() && this.IsUsableRect(mem.x, mem.y, mem.w, mem.h)
                g.Show("Hide")
            else
                g.Show("Hide w" . this.DefaultW . " h" . this.DefaultH)

            ; 伴生窗口在屏幕上时按「同宽上下堆叠」摆放 —— 两个窗口拼成一列，界面规整。
            ; 摆不成（伙伴已被关掉、或屏幕塞不下两窗）才退回记忆位置 / 默认落点。
            if !this._StackWithPeer(ghwnd) {
                rect := State.GetHiddenRect()
                if State.HasHiddenRect() && this.IsUsableRect(rect.x, rect.y, rect.w, rect.h) {
                    ; ⚠ 必须用 WinMove 而非 g.Move：g.Move 收的是「逻辑单位」，会自动乘 DPI 比
                    ;   （本机 1.5）。而 rect 来自 WinGetPos，是「物理像素」——喂给 g.Move 会被
                    ;   二次放大（实测 1629,238 → 2444,357）。WinMove 与 WinGetPos 同一单位，配套。
                    WinMove(rect.x, rect.y, rect.w, rect.h, "ahk_id " . ghwnd)
                } else {
                    State.ClearHiddenRect()
                    this._MoveToDefault(g, ghwnd)
                }
            }
        } finally {
            DetectHiddenWindows(detectOld)
        }

        g.Show()
        ; ⚠ 原来这里无条件 WinRestore。它偶发抛 Target window not found（_error.log 里
        ;   反复出现），而窗口其实已经显示出来了 —— Show 刚把窗口从隐藏翻成可见的
        ;   那一瞬，WinTitle 匹配仍按「不含隐藏窗口」算，连 ahk_id 也命中不到。
        ;   真正需要恢复的只有「已最小化」这一种情况，交给 _EnsureVisible 判。
        this._EnsureVisible(ghwnd)
    }

    ; 把窗口从「最小化 / 隐藏残留」拉回正常显示。拿不到窗口就什么都不做 ——
    ; 这条路径上的失败没有用户可见后果（窗口已经 Show 出来了），不该刷日志。
    ;
    ; ⚠ 直接对 **hwnd** 调 ShowWindow(SW_SHOWNORMAL=9)，不用 WinRestore：
    ;   后者按 WinTitle 匹配，在「隐藏 → 可见」那一瞬会抛 Target window not found
    ;   （_error.log 里反复出现过）。ShowWindow 只认句柄，没有这个时间窗。
    ; ⚠ 这不是防御性冗余：实测重启后**第一次** Alt+Z，窗口已经 Show 出来、
    ;   WS_VISIBLE 也是 1，但 IsIconic 仍是 1 —— 屏幕上什么都没有，任务栏里躺着一个。
    ;   那一刻 WinRestore 正好匹配失败，而窗口看起来「按了没反应」。
    ;   对已是正常态的窗口调 SW_SHOWNORMAL 是无操作，可以每次调。
    static _EnsureVisible(ghwnd) {
        if !ghwnd
            return
        try DllCall("user32\ShowWindow", "ptr", ghwnd, "int", 9)
    }

    ; 与伴生窗口上下堆叠成规整的一列：同宽、左边对齐、上下紧贴。
    ; 笔记窗口固定在伴生窗口上方，顶边贴工作区顶部，宽度跟着伴生窗口走。
    ;
    ; 伴生窗口若已在屏幕下半区（上方能容下笔记窗口）就原地不动；
    ; 若它贴着屏幕顶部、上方塞不下，就把它**下移**到底边贴工作区底 ——
    ; 只改位置、尺寸一字不动，腾出上半屏给笔记窗口。
    ; 两步都不成立（屏幕太矮、两窗叠起来放不下）才返回 false，交回记忆位置处置。
    ;
    ; ⚠ 这套算法假定「伙伴在下、笔记在上」。以后接入的窗口若更适合左右并排，
    ;   改的就是这里 —— 发布方一行不用动（见 README 同名小节）。
    ; 调用方需已开 DetectHiddenWindows（窗口可能还是 Show("Hide") 状态）。
    static _StackWithPeer(ghwnd) {
        pr := this._peerRect
        if !IsObject(pr)
            return false

        ; 已经适配过一次 → 格局已定，绝不再按伴生窗口的位置重算。
        ;   本方法有两条调用路径，这一条把两条都管住：
        ;     · _PlaceWindow —— Alt+Z 展开笔记时，于是走「记忆位置」= 用户自己的格局；
        ;     · _AdaptToPeer —— 伴生窗口落位时，那里另有 _docked 守卫，这里是双保险。
        ;   返回 false 让调用方回落到记忆位置，正是想要的：不动坐标。
        if this._docked
            return false

        ; 伴生窗口可能已经被关掉了 —— 那份坐标就没意义了，交回记忆位置 / 默认落点处置
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            alive := WinExist("ahk_id " . pr.hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if !alive
            return false

        ; 先把窗口尺寸量定型：Show("Hide") 之后控件固有尺寸要等 OnSize 跑完才反映到
        ; 外框上，这之后设的尺寸才不会被随后的布局盖回去
        nw := 0, nh := 0
        if !this._MeasureStable(ghwnd, &nw, &nh)
            return false

        ; 头一次堆叠时留个底 —— 堆叠会把窗口压矮，收窗口时要照这份原始位置尺寸还原。
        ; ⚠ 只在「还没有底稿」时留：底稿的语义是**用户自己的窗口格局**。
        ;   若每次堆叠都重留，就会把上一次堆叠后的压扁尺寸当作新旧稿 ——
        ;   「堆叠 → Alt+Z 收起 → Alt+Z 展开」一轮下来，实测 711x885 会被写成 744x533，
        ;   之后终端不在时窗口就再也回不到原来的大小。
        ;   底稿由 _RememberPosition 在**非堆叠态**隐藏时刷新（见那里的注释）。
        if !IsObject(this._preStackRect) {
            try {
                WinGetPos(&ox, &oy, &ow, &oh, "ahk_id " . ghwnd)
                this._preStackRect := {x: ox, y: oy, w: ow, h: oh}
            } catch
                this._preStackRect := ""
        }

        ; 几何计算已上收到平台层 PeerCoordinator（Phase 3b）：Phase 5b 起这里只负责
        ; 状态判断与底稿，落点由 PlanStack(..., true) 广播的 Move 事件应用到窗口上。
        plan := PeerCoordinator.PlanStack(ghwnd, pr, true)
        if !plan.ok
            return false

        ; Phase 5b：PlanStack(..., true) 已在计算完成时同步广播 Move 事件 ——
        ;   伙伴由 LauncherModule._OnMove() 下移，笔记由本类 _OnNoteMove() 摆位。
        ;   这里只更新状态：方案二会改伙伴位置，记下新矩形供下次呼出使用。
        if IsObject(plan.peer)
            this._peerRect := plan.peerRect
        this._stacked := true
        return true
    }

    ; 几何实现已上收到平台能力 WindowProbe / RectMath；本类只保留业务状态与底稿。

    ; 移到默认落点
    static _MoveToDefault(g, ghwnd) {
        w := 0, h := 0
        if !this._MeasureStable(ghwnd, &w, &h)
            return
        rect := this._DefaultRect(w, h)
        ; 同样用 WinMove（物理像素），只设位置不设尺寸 —— 尺寸交给 AHK 按 DPI 决定
        WinMove(rect.x, rect.y, , , "ahk_id " . ghwnd)
    }

    ; 等窗口尺寸稳定下来。Show 之后控件的固有尺寸要等 OnSize 跑完才反映到窗口外框上，
    ; 连续两次量到同一个值才认为定型。全程窗口不可见，多花几毫秒用户看不见。
    ;
    ; ⚠ **最小尺寸下限不能省**：Show("Hide") 之后 WinGetPos 可能先读到 10 一类的中途值，
    ;   而「连续两次相同」会把那个 10px 当成终值 —— 拿它算默认落点，窗口会整体偏到
    ;   屏幕右侧（只剩任务栏或边上一道缝）。`WebWindow._Place` 早就带了这个判据，
    ;   这边此前漏了，正好对上「首次 Alt+Z 偶尔只出任务栏」。
    ;   本机窗口最小尺寸是 675×450（逻辑 450×300 @150%），200×120 足够宽裕。
    static MinStableW := 200
    static MinStableH := 120

    static _MeasureStable(hwnd, &w, &h) {
        prevW := -1, prevH := -1, same := 0
        loop 60 {
            try
                WinGetPos(&_, &_, &w, &h, "ahk_id " . hwnd)
            catch
                return false
            if (w >= this.MinStableW && h >= this.MinStableH && w = prevW && h = prevH) {
                if (++same >= 2)
                    return true
            } else {
                same := 0
            }
            prevW := w, prevH := h
            Sleep 10
        }
        ; 超时：只有量到一个「像样的」尺寸才让调用方继续定位。
        ; 否则宁可不动（窗口停在 AHK 默认落点），也别把它摆到屏幕外。
        return (w >= this.MinStableW && h >= this.MinStableH)
    }

    ; 默认落点坐标：贴主屏工作区右上角 —— 右边距 Config.PlaceRight、顶边距 Config.PlaceTop。
    ;
    ; ⚠ 尺寸必须按窗口的「实际」值算 —— A_ScreenWidth 是物理像素，而窗口实际宽含 DPI
    ;   放大后的控件与边框（本机约 711），远大于 450 这样的逻辑值。
    ; ⚠ 用 MonitorGetWorkArea 而非 A_ScreenWidth / A_ScreenHeight：后者是全屏尺寸，
    ;   多屏时也只反映主屏。
    static _DefaultRect(winW, winH) {
        MonitorGetWorkArea(MonitorGetPrimary(), &wkLeft, &wkTop, &wkRight, &wkBottom)
        posX := wkRight - winW - Config.PlaceRight
        posY := wkTop + Config.PlaceTop
        ; 窗口比工作区还大（或边距过大）时兜底，免得落到负坐标、跑到屏幕外
        if (posX < wkLeft + 10)
            posX := wkLeft + 10
        if (posY < wkTop + 10)
            posY := wkTop + 10
        if (posY + winH > wkBottom)
            posY := wkBottom - winH - 10
        return {x: posX, y: posY}
    }

    ; ═══ 光标与重绘 ═══
    ; v2.9：编辑器换成 WebView2 后这两件事都不在 AHK 侧了 ——
    ;   · 光标：S3a 起由 Milkdown 自己维护，切日期时 replaceAll 会重置到文首；
    ;   · 重绘：Chromium 合成，没有 WM_SETREDRAW 这回事。
    ; 留个空段只为说明「不是漏掉了」。
}
