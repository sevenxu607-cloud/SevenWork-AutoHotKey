#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  DeepSeekFeature —— Alt+X 呼出 DeepSeek 网页端
;  Phase 3 从 SevenNote.ahk 原样搬入；热键交由 LauncherModule.GetHotkeys()。
; ═══════════════════════════════════════════════════════════════════════════

; ─── Alt+X 呼出 DeepSeek 网页端 ───
; 与 PowerShellFeature 同一套玩法：启动 / 认窗 / 唤醒，落辅助区（ZoneService）。
; 不再广播 Launcher.* 事件，也不再管笔记窗口的位置。
;
; 有三处与终端不同，值得记下：
;   ① **窗口怎么认**：终端能靠标题（"SevenWork PowerShell"）认，浏览器不能 ——
;      本机日常 Edge 里也开着 DeepSeek 网页，标题一样含 "DeepSeek"，靠标题一认就错。
;      这里改用「专用 profile → 独立进程树」的办法：窗口按 PID 认。
;   ② **尺寸与位置要自己给**：终端由 Windows Terminal 的 profile 决定落点（本机 744x1020），
;      浏览器却每次都落在 Chromium 的默认点。这里按目标尺寸摆到「和终端同一处」——
;      右侧贴工作区右缘、底边贴工作区底，于是两种伙伴产出的堆叠效果一模一样。
;   ③ **换了窗口模式就得退掉老实例**：Chromium 单实例复用会让「最先那次启动」的窗口
;      类型一直沿用到该进程结束 —— 老实例还活着时，改了命令行也照旧开出旧模式窗口。
;      详见 _RetireLegacyInstance() 与 _FindBrowserHwnd() 开头的模式校验。
class DeepSeekFeature {
    static _initialized := false
    static _url := "https://chat.deepseek.com/"

    ; 专用浏览器 profile —— 与用户日常浏览器**完全隔离**。两条理由：
    ;   ① 不往用户的收藏夹 / 历史 / 扩展里掺东西；
    ;   ② 独立 user-data-dir 会让 Chromium 起一条独立进程树，窗口才能被唯一定位。
    ; ⚠ 代价：首次要用它登录一次 DeepSeek，之后 profile 会记住。
    static _profileDir := Config.AppDataDir . "\_deepseek-profile"
    ; PID 落盘，好在「笔记程序重启」后认回已有窗口 —— 内存缓存随进程丢，文件不丢。
    static _pidFile := Config.AppDataDir . "\_deepseek.pid"

    ; 本文件启动过的实例属于哪种窗口 —— 也要落盘，理由见 _RetireLegacyInstance()：
    ; Chromium 单实例复用会让老进程继续提供它那种窗口，换了命令行也白换。
    static _windowMode := "window"
    static _modeFile := Config.AppDataDir . "\_deepseek.mode"

    static _hwnd := 0   ; 进程内缓存，省掉每次读文件

    static Init() {
        if (this._initialized)
            return
        ; 热键由 LauncherModule.GetHotkeys() 交给 HotkeyRouter；Feature 不再自注册。
        this._initialized := true
    }

    static Toggle() {
        hwnd := this._FindBrowserHwnd()
        if (hwnd = 0) {
            this._Launch()
            return
        }

        ; ⚠ 必须同时看「可见」：WinHide 之后 GetForegroundWindow 仍指着那个隐藏窗口
        ;   （本机实测 1.2s 后依然如此），只看 WinActive 会判定成「在前台 → 再藏一次」，
        ;   于是按了没反应、再也呼不出来。
        if (this._IsVisible(hwnd) && WinActive("ahk_id " . hwnd)) {
            WinHide("ahk_id " . hwnd)
            return
        }

        this._ShowAndFocus(hwnd)
    }

    ; 窗口此刻是否真的在屏幕上（WinHide 过 = false）。
    ; ⚠ 别用 IsIconic 组合来判断这里的「在显示」—— 那是判断最小化的写法：
    ;   本窗口只会被 WinHide 藏起来，不会被最小化，看 IsWindowVisible 一个就够。
    static _IsVisible(hwnd) => !!DllCall("IsWindowVisible", "ptr", hwnd, "int")

    ; 认回自己的窗口，两级兜底：进程内缓存 → PID 文件 → 没有（那就重新拉起）
    static _FindBrowserHwnd() {
        ; ⚠ 模式校验必须放在最前：老版本（--app 时代）留下的实例还活着时，认回它只会
        ;   得到应用窗口（无标签栏）。宁可当成「没有窗口」，让 Toggle() 转去 _Launch()
        ;   把老实例退掉、按新模式重开。
        if (this._ReadMode() != this._windowMode)
            return 0
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if (this._hwnd && WinExist("ahk_id " . this._hwnd)
                && WinGetClass("ahk_id " . this._hwnd) = "Chrome_WidgetWin_1")
                return this._hwnd
            this._hwnd := 0

            pid := this._ReadPid()
            if (pid > 0) {
                hwnd := this._TopWindowOf(pid, true)
                if hwnd {
                    this._hwnd := hwnd
                    return hwnd
                }
            }
        } finally {
            DetectHiddenWindows(detectOld)
        }
        return 0
    }

    ; 取某进程「属于我们的那扇窗」。
    ; Chromium 一个实例会带一串窗口：Chrome_WidgetWin_0 的辅助窗、IME、
    ; Base_PowerMessageWindow…（本机实测一个实例 5 个），界面本身是 Chrome_WidgetWin_1。
    ;
    ; ⚠ 不能只看 class + 可见：`fallback` 那一支是必须的。窗口被 WinHide 藏着时它
    ;   依然是我们自己那扇窗 —— 重启程序后靠 pid 文件认回隐藏窗口就是此场景；
    ;   若要求可见，会认不回、于是又拉起一个新窗口，越按越多。
    ; ⚠ 可见性只用来「挑」：一个进程可能同时有多个 Chrome_WidgetWin_1（本机实测同一个
    ;   实例里两个），优先拿可见的那个，都没可见才退回第一个。
    static _TopWindowOf(pid, relax := false) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        fallback := 0        ; 第一扇「不可见」的候选（认回被藏起来的窗口用）
        visibleAny := 0      ; 第一扇「可见」的候选（尺寸对不上时的退路）
        t := this._TargetSize()
        tw := t.w, th := t.h
        try {
            for h in WinGetList("ahk_exe " . this._ExeName()) {
                if (WinGetPID("ahk_id " . h) != pid)
                    continue
                if (WinGetClass("ahk_id " . h) != "Chrome_WidgetWin_1")
                    continue
                if !DllCall("IsWindowVisible", "ptr", h, "int") {
                    if !fallback
                        fallback := h
                    continue
                }
                ; 同一个 profile 可能同时开着好几扇窗（用户在窗口里又开了窗、或 Edge 恢复了
                ; 上次的窗口 —— 实测第二次带 --new-window 启动后同 PID 下有 3 扇），
                ; 于是「第一个可见的」未必是我们摆过的那扇，认哪扇全看枚举顺序。
                ; 我们的窗口由 _CheckSize 反复校正成目标尺寸，用户手开的通常对不上 ——
                ; 用尺寸把它挑出来。
                ; ⚠ 尺寸是异步校正的：刚启动那一刻还没摆到位，所以这里只是「优先」，
                ;   没命中就退回第一个可见窗口，绝不会因为量不准而认不回窗口。
                WinGetPos(, , &aw, &ah, "ahk_id " . h)
                if (aw = tw && ah = th)
                    return h
                if !visibleAny
                    visibleAny := h
            }
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if (visibleAny != 0)
            return visibleAny
        return relax ? fallback : 0
    }

    static _ReadPid() {
        try {
            v := Trim(FileRead(this._pidFile, "UTF-8"))
            return IsNumber(v) ? Integer(v) : 0
        } catch {
            return 0
        }
    }

    static _WritePid(pid) {
        try {
            FileDelete(this._pidFile)
        } catch {
        }
        try {
            FileAppend(pid, this._pidFile, "UTF-8")
        } catch {
        }
    }

    static _ReadMode() {
        try
            return Trim(FileRead(this._modeFile, "UTF-8"))
        catch
            return ""
    }

    static _WriteMode(mode) {
        try {
            FileDelete(this._modeFile)
        } catch {
        }
        try {
            FileAppend(mode, this._modeFile, "UTF-8")
        } catch {
        }
    }

    ; 退掉「窗口模式不对」的残留实例，让本次 --new-window 真正生效。
    ;
    ; 背景：Chromium 是**单实例**的 —— 只要那个 profile 进程还活着，后到的命令行就只被
    ; 当成「在已有实例里开个地址」，窗口类型仍由**最先那次启动**决定。实测从 --app 时代
    ; 升级上来后，那个进程一直活着（用户只是关了窗口、没退进程），于是改了命令行也照旧
    ; 开出应用窗口 —— 认窗逻辑再对，窗口类型还是错的。
    ;
    ; 判据用落盘的 _modeFile：写的是 "window" 就说明实例是本版启动的，直接放行；文件
    ; 缺失或内容不符 = 老版本留下的实例，退掉重开。所以这是**升级路径上的一次性清理**，
    ; 正常运行时一次都不会动手。
    static _RetireLegacyInstance() {
        if (this._ReadMode() = this._windowMode)
            return
        pids := this._ProfilePids()
        if (pids.Length) {
            ; 先礼后兵：先对有窗口的那个发 WM_CLOSE，让 Chromium 正常收尾（会话与标签都保住）。
            pid := this._ReadPid()
            if (pid && ProcessExist(pid)) {
                hwnd := this._TopWindowOf(pid, true)
                if (hwnd)
                    try WinClose("ahk_id " . hwnd)
            }
            deadline := A_TickCount + 1200
            while (A_TickCount < deadline && this._AnyAlive(pids))
                Sleep(60)
            for p in pids {
                if (ProcessExist(p))
                    try ProcessClose(p)
            }
            ; 等它们把 profile 的锁放掉，否则紧接着那次启动会被判成「已有实例」又并进去。
            Sleep(300)
        }
        this._WriteMode(this._windowMode)
    }

    ; 占用专用 profile 的全部活进程。
    ;
    ; ⚠ 不能只信 _deepseek.pid：它可能落后（上次没认回窗口就没写）或指向已退出的进程（PID
    ;   还可能被复用给别人），那样都会漏掉真正占着 profile 的那个实例 —— 它一活着，本次
    ;   启动就注定被并进去、窗口模式照旧。所以再按命令行里的 profile 路径全库筛一遍。
    ;   WMI 拿不到（异常 / 被策略挡住）时退回「只认 pid 文件那一个」，功能不因此失效。
    static _ProfilePids() {
        out := []
        seen := Map()
        pid := this._ReadPid()
        ; ⚠ 校验进程名：PID 会被复用，光看「存在」可能杀到不相干的程序。
        if (pid && ProcessExist(pid) && ProcessGetName(pid) = this._ExeName()) {
            seen[pid] := true
            out.Push(pid)
        }
        try {
            wmi := ComObjGet("winmgmts:")
            q := "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='"
                . this._ExeName() . "'"
            for proc in wmi.ExecQuery(q) {
                cmd := proc.CommandLine
                if (IsObject(cmd) || cmd = "")       ; 跨权限的进程读不到命令行，跳过
                    continue
                if !InStr(cmd, this._profileDir)     ; 认 profile 路径，不认进程名
                    continue
                p := proc.ProcessId + 0
                if seen.Has(p)
                    continue
                seen[p] := true
                out.Push(p)
            }
        } catch {
        }
        return out
    }

    static _AnyAlive(pids) {
        for p in pids {
            if (ProcessExist(p))
                return true
        }
        return false
    }

    static _Launch() {
        exe := this._BrowserPath()
        if (exe = "") {
            MsgBox("未找到可用的 Chromium 系浏览器（Edge / Chrome）。`n"
                . "可在 _config.ini 的 [Paths] BrowserPath 指定浏览器路径。"
                , Config.AppName, "Icon!")
            return
        }

        ; ⚠ 升级路径上的一次性清理：老实例（--app 时代的进程）还活着就先退掉它，
        ;   否则本次 --new-window 会被 Chromium 的单实例复用吃掉，照旧开出应用窗口。
        this._RetireLegacyInstance()

        ; 启动前先记下现有的同族 PID，之后「新出现的那个」就是我们的 ——
        ; 专用 profile 保证了它必定是条新进程树，不会并进用户自己的浏览器里。
        before := this._PidSnapshot()

        try {
            ; ⚠ --window-size 收的是**逻辑像素**（DIP），而 WinMove / WinGetPos 认物理像素。
            ;   本机 150% 缩放（A_ScreenDPI = 144）下传 513x680，实际得到 772x1020 —— 正合目标。
            ;   换个缩放比例就得跟着变，所以按 A_ScreenDPI 反算，别写死。
            ; ⚠ 宽度再减 2：Edge 把内容区尺寸套到窗口外框时会替自己补两像素调整边框 ——
            ;   本机实测请求 770（物理）时外框落在 772，而终端是 770，两者左右边缘就差这
            ;   2px。请求值先扣掉它，外框才与终端严格等宽（高度实测不差，不用减）。
            ;   真机上若换版本后仍差，以 WinGetPos 量到的**外框**为准调这个常量 ——
            ;   别去猜那圈边框算几像素（随系统版本与缩放而变）。
            t := this._TargetSize()
            w := (t.w - 2) * 96 // A_ScreenDPI
            h := t.h * 96 // A_ScreenDPI
            ; --new-window：开一扇**普通浏览器窗口**（有标签栏与完整工具栏），窗口内可直接浏览网页。
            ;       早先走 --app=<url> 开「应用窗口」求桌面应用观感，实测不划算 —— Edge 155 起
            ;       app 窗口照样自带地址栏（UIA 查到 view_1017「地址和搜索栏」），却没有标签栏：
            ;       既不像应用，也算不上好用的浏览器。改普通窗口后能自己开新标签 / 前进后退。
            ;       ⚠ 认窗逻辑不受影响：仍是「专用 profile → 独立进程树 → 按 PID 认窗」，
            ;       普通窗口的 class 同样是 Chrome_WidgetWin_1，`_TopWindowOf` 照样认得出。
            ;       标题归页面管（形如 "DeepSeek - Microsoft Edge"），别拿标题找它。
            ; --user-data-dir：独立 profile（理由见类头）。
            ; --no-first-run / --no-default-browser-check：跳过首次运行的欢迎页与
            ;       「是否设为默认浏览器」的询问 —— 新 profile 每次都问，很烦。
            cmd := '"' . exe . '" --new-window ' . this._url
                . ' --user-data-dir="' . this._profileDir . '"'
                . ' --window-size=' . w . ',' . h
                . ' --no-first-run --no-default-browser-check'
            Run(cmd)
        } catch as err {
            MsgBox("启动浏览器失败：`n" . err.Message, Config.AppName, "Icon!")
            return
        }

        ; 浏览器冷启动比终端快（本机实测起进程 ~0.1s、窗口到位 ~0.9s），但仍要轮询：
        ; 抢在窗口出现前 WinShow 会报「窗口不存在」。
        deadline := A_TickCount + 15000
        relaxAt := A_TickCount + 3000      ; 3 秒后仍没找到，就连「还没显示」的窗口也算（放宽）
        ; 上一轮认过的 profile 进程。Chromium 是**单实例**的：若它还活着（用户只关了窗口、
        ; 没退进程 —— 普通窗口模式下这是常态），这次启动根本不会产生新进程，
        ; `_NewPidsSince` 永远为空，只认新 PID 就会一路超时弹「找不到窗口」。
        knownPid := this._ReadPid()
        while (A_TickCount < deadline) {
            relax := A_TickCount >= relaxAt
            for pid in this._NewPidsSince(before) {
                hwnd := this._TopWindowOf(pid, relax)
                if (hwnd != 0) {
                    this._WritePid(pid)
                    this._hwnd := hwnd
                    this._ShowAndFocus(hwnd)
                    return
                }
            }
            ; 老进程仍在 → 它多半只是新开了扇窗（--new-window 保证了这一点），按老 PID 认。
            ; ⚠ 只在「认回」这一支放宽：平时要求窗口可见，免得把别处残留的隐藏窗当成目标。
            if (knownPid && ProcessExist(knownPid)) {
                hwnd := this._TopWindowOf(knownPid, relax)
                if (hwnd != 0) {
                    this._hwnd := hwnd
                    this._ShowAndFocus(hwnd)
                    return
                }
            }
            Sleep(20)
        }

        MsgBox("浏览器已启动，但未能找到它的窗口。", Config.AppName, "Icon!")
    }

    ; 当前同族进程的 PID 集合（含只有隐藏窗口的宿主进程）
    static _PidSnapshot() {
        s := Map()
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            for h in WinGetList("ahk_exe " . this._ExeName())
                try s[WinGetPID("ahk_id " . h)] := true
        } finally {
            DetectHiddenWindows(detectOld)
        }
        return s
    }

    ; 启动后「新出现、且已经有窗口」的全部 pid。
    ;
    ; ⚠ 返回**全集**而不是「第一个」，这是本功能的关键：用户自己的浏览器一直在跑，
    ;   随时会冒出新的渲染进程（它们没有 Chrome_WidgetWin_1 窗，永远匹配不上）。
    ;   只返回第一个的话，一旦它排在真正那个前面，就会整段超时卡死到「找不到窗口」——
    ;   本机实测：新进程 22072 挡住真正的 23064，连卡 8 秒。全集逐个过就没有这个问题。
    static _NewPidsSince(before) {
        out := []
        for pid, _ in this._PidSnapshot() {
            if !before.Has(pid)
                out.Push(pid)
        }
        return out
    }

    static _ShowAndFocus(hwnd) {
        WinShow("ahk_id " . hwnd)
        ; ⚠ WinRestore 只在「已最小化」时才有意义。Chromium 窗口被 WinHide 藏起来后
        ;   有可能把自己标成最小化，也可能只是普通隐藏 —— 后者照样调 WinRestore 会抛
        ;   Target window not found（_error.log 里反复出现，而窗口其实已经回来了）。
        if DllCall("user32\IsIconic", "ptr", hwnd, "int")
            WinRestore("ahk_id " . hwnd)
        WinActivate("ahk_id " . hwnd)
        try {
            WinSetAlwaysOnTop("On", "ahk_id " . hwnd)
        }
        this._PlaceLikeTerminal(hwnd)
    }

    ; 落辅助区并复核尺寸：Edge 会在窗口露面之后重新套用它自己的 --window-size。
    static _PlaceLikeTerminal(hwnd) {
        this._PlaceTarget(hwnd)
        this._WatchSize(hwnd, 0)
    }

    ; 落辅助区：保留浏览器自身尺寸（--window-size 已按区域给过），只对齐左上角。
    ; 失败里「不可摆 / 已最小化 / 区域不可用」都是正常路径，不刷日志。
    static _PlaceTarget(hwnd) {
        res := ZoneService.Place(hwnd, "aux", {fill: false, allowHidden: false})
        if !res.ok && res.reason != "not-placeable" && res.reason != "minimized" && res.reason != "no-zone"
            LogError("浏览器落辅助区失败：" . res.reason)
    }

    ; ─── 尺寸复核：Edge 会在窗口露面之后重新套用它自己的 --window-size ───
    ; ⚠ `--window-size` 说的是**内容区**，Edge 套到窗口外框上还要再补一圈调整边框 ——
    ;   本机实测请求 770 的外框最后落在 768，而终端恰是 770x1020：两个伙伴左右边缘
    ;   错开两个像素，就是「终端和 DeepSeek 没对齐」。
    ;   实测（probe：WinMove 到 770 后每 500ms 量一次）证明它**不是**持续校正 ——
    ;   稳定窗口上 770 一直保持。它会重新套用，是在窗口被 show/restore **之后**；
    ;   而那个时刻晚于第一次 350ms 复核，只核一次必然漏掉。故在 350 / 950 / 1550 /
    ;   2150ms 四处各核一次，量到与目标不符就按目标重摆。单次开销只是一次 WinGetPos。
    ;   ⚠ 不去猜那圈边框有几像素（随系统版本与缩放变），也不跟 Edge 抢时序 ——
    ;     只事后核对，以实际外框为准。
    static _WatchSize(hwnd, round) {
        if (round > 3)
            return
        delay := (round = 0) ? 350 : 600
        SetTimer(() => this._CheckSize(hwnd, round), -delay)
    }

    static _CheckSize(hwnd, round) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if !WinExist("ahk_id " . hwnd)
                return
            ; 窗口已被用户藏起来（连按两次 Alt+X）= 用户不想看见它，别再管它的尺寸：
            ; 直接返回，也不再排下一轮复核 —— 否则会反复去重摆一个看不见的窗口，
            ; 而 WinMove 对隐藏窗口会抛 "Target window not found"（实测卡死脚本）。
            if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
                return
            ; 最小化的窗口量不出尺寸（读数是停放位的垃圾值），别据此重摆
            if DllCall("IsIconic", "ptr", hwnd, "int")
                return
            WinGetPos(, , &aw, &ah, "ahk_id " . hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
        t := this._TargetSize()
        if (aw != t.w || ah != t.h)
            this._PlaceTarget(hwnd)
        this._WatchSize(hwnd, round + 1)
    }

    ; 辅助区的当前尺寸（可见边界）。区域算不出来时退回 772x1020（旧默认值）。
    static _TargetSize() {
        r := ZoneService.Rect("aux")
        if IsObject(r)
            return {w: r.w, h: r.h}
        return {w: 772, h: 1020}
    }

    ; 浏览器：优先 _config.ini 指定；否则按 Edge → Chrome 顺序探测（Windows 自带 Edge，
    ; 命中率最高）。只要是 Chromium 系（支持 --new-window / --user-data-dir）都能用。
    static _BrowserPath() {
        p := ConfigService.Read("Paths", "BrowserPath")
        if (p != "" && FileExist(p))
            return p
        for candidate in [
            A_ProgramFiles . "\Microsoft\Edge\Application\msedge.exe",
            EnvGet("ProgramFiles(x86)") . "\Microsoft\Edge\Application\msedge.exe",
            A_ProgramFiles . "\Google\Chrome\Application\chrome.exe",
            EnvGet("ProgramFiles(x86)") . "\Google\Chrome\Application\chrome.exe",
            EnvGet("LOCALAPPDATA") . "\Google\Chrome\Application\chrome.exe",
        ] {
            if FileExist(candidate)
                return candidate
        }
        return ""
    }

    ; 进程名（WinGetList 的 ahk_exe 参数用）—— 跟着上面选中的浏览器走，
    ; 免得用户把 BrowserPath 改成 Chrome 后这里还在找 msedge.exe。
    static _ExeName() {
        p := this._BrowserPath()
        if (p = "")
            return "msedge.exe"
        SplitPath(p, &name)
        return name
    }
}
