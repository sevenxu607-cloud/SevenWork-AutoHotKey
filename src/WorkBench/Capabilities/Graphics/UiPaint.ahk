#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  UiPaint —— Win32 染色原语（Capability）
; ═══════════════════════════════════════════════════════════════════════════
;  纯能力，守 .clinerules/02 的 Capability 契约：
;    · 只收 hwnd / 颜色字符串 / 布尔，**不读 Config、不读 State、不发事件**；
;    · 不认识 ThemeService —— 主题是业务策略，这里只认「给我一个颜色」。
;
;  为什么这些要单独抽出来：它们是「GUI 上色」的平台知识，跨模块复用（笔记的
;  日期对话框 / 提示词的列表 / 启动提示都要），而且都靠 DllCall + Windows 消息，
;  散在 Feature 里既容易写错、也没法统一改。
;
;  ⚠ 深色主题下 Edit / ComboBox 走 EditColors()（WM_CTLCOLOREDIT 全局分发 +
;    CreateSolidBrush/DeleteObject 成对管理）—— 见下方的「Edit / ComboBox 底色」段。
;    别半成品地只改背景不改文字（白底黑字 → 深底黑字，比不改还糟）。
class UiPaint {
    ; ─── 窗口标题栏 ───────────────────────────────────────────────────────
    ; 深色主题连标题栏一起变深 —— Windows 默认画白标题栏，压在深色窗口上很扎眼。
    ;
    ; ① immersive dark mode：属性号随版本变，Win10 1903+ / Win11 用 20，1809 用 19；
    ;    先试 20，DllCall 返回非 0（不支持）再退到 19。
    ; ② 整块染色（Win11 build 22000+ 才有 35 / 36 / 34 三个属性）：
    ;      35 = CAPTION_COLOR  标题栏底色，取 win
    ;      36 = TEXT_COLOR     标题文字色，取 text —— 深底配亮字、浅底配深字，自动成对
    ;      34 = BORDER_COLOR   外框，与标题栏同色
    ;    颜色是 COLORREF（0x00BBGGRR），正好复用 Bgr()。
    ; ⚠ Win10 上这三个属性不存在，DllCall 直接返回非 0 —— 静默丢掉、系统配色照旧，
    ;   所以不必写版本判断（上面那段 immersive dark mode 已经兜住了深浅）。
    ;
    ; caption 开关（v2.12）：
    ;   true  = 整块染色。Win10 / 背板不生效时用它兜住观感（浅色主题也不会白得刺眼）。
    ;   false = **只设文字色 36**，标题栏底色交给系统背板 —— 这是让 Win11 的
    ;           mica / acrylic 真的透上来的关键：CAPTION_COLOR 是不透明实色，
    ;           一调就把刚设好的背板整个盖掉（实测：标题栏变成纯主题深蓝，
    ;           背板设置"成功"了却一点也看不见）。调用方先 Glass() 拿 mode 再决定。
    static TitleBar(hwnd, winHex, textHex, caption := true) {
        if !hwnd
            return false

        dark := this.IsDark(winHex) ? 1 : 0
        v := Buffer(4, 0)
        NumPut("int", dark, v, 0)
        try {
            for attr in [20, 19] {
                if !DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                    , "int", attr, "ptr", v, "int", 4, "int")
                    break
            }
        }

        attrs := caption ? [[35, winHex], [36, textHex], [34, winHex]]
                         : [[36, textHex]]
        for it in attrs {
            cv := Buffer(4, 0)
            NumPut("uint", this.Bgr(it[2]), cv, 0)
            try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                , "int", it[1], "ptr", cv, "int", 4, "int")
        }
        return true
    }

    ; ─── 滚动条 / 原生控件主题 ────────────────────────────────────────────
    ; 滚动条画在**非客户区**、由系统主题上色 —— 深色主题下它仍是一条亮白，
    ; 压在暗底上格外扎眼（浅色主题下则相反：深色滚动条同样突兀）。
    ; 把窗口主题交给 DarkMode_Explorer / Explorer 即随之明暗，其余观感分毫不动。
    ; ⚠ 走 DllCall 而不是内置的 SetWindowTheme()：第三参恒为 0（不重置子控件主题），
    ;   这里写全参数最省心。老系统上没有 DarkMode_Explorer，DllCall 静默失败、
    ;   退回系统配色 —— 不必写版本判断。
    static WindowTheme(hwnd, dark) {
        if !hwnd
            return false
        theme := dark ? "DarkMode_Explorer" : "Explorer"
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", theme, "ptr", 0)
        return true
    }

    ; ─── 玻璃背衬 ─────────────────────────────────────────────────────────
    ; 转调 GlassPaint（同领域纯能力）：style 为空（flat 主题）时**什么都不做** ——
    ; 米黄的窗口一个像素都不该变；圆角也只在玻璃主题下给（flat 保持直角，与旧版一致）。
    ; ⚠ 只收「字符串 / 数字」，不收 Palette 对象 —— 能力层不认识业务色板。
    static Glass(hwnd, style, tintHex) {
        if (style != "glass") {
            ; 从玻璃主题切回扁平：撤掉背板与圆角，否则窗口还挂着半透明那层
            return GlassPaint.Clear(hwnd)
        }
        GlassPaint.Rounded(hwnd)
        ; 客户区交给 WebView2，accent 只染标题栏与边框 —— 浅染才像亚克力而不是色板。
        return GlassPaint.Apply(hwnd, tintHex, 0x50)
    }

    ; ─── ListView 底色 ────────────────────────────────────────────────────
    ; ListView **不吃** Gui.BackColor，必须整块走 Windows 消息单独上色。
    ;   0x1001 LVM_SETBKCOLOR        控件底
    ;   0x1024 LVM_SETTEXTCOLOR      正文
    ;   0x1026 LVM_SETTEXTBKCOLOR    文字底（必须与控件底一致，否则整块行区仍是系统白）
    ;          ⚠ 写成 0x1025 是 **GET**TEXTBKCOLOR —— 不报错、只是什么也没设，
    ;          症状是「控件底变深了、每一行还是白的」（2026-10-22 实测踩到）。
    ;   0x1036 LVM_SETEXTENDEDLISTVIEWSTYLE + LVS_EX_DOUBLEBUFFER：
    ;          每敲一个字就整表重填，不双缓冲会看到闪白。
    static ListView(hwnd, bgHex, fgHex) {
        if !hwnd
            return false
        bg := this.Bgr(bgHex)
        fg := this.Bgr(fgHex)
        ; ⚠ 必须先摘掉视觉样式：带主题的 ListView 会**忽略** LVM_SETBKCOLOR，
        ;   白底照旧 —— 「侧栏导航白底写白字」就是这么来的（2026-10-22 实测）。
        ;   DarkMode_Explorer 顺带把滚动条与选中行一起带进深色；浅色主题走 Explorer。
        this.WindowTheme(hwnd, this.IsDark(bgHex))
        try {
            this._Lvm(hwnd, 0x1001, 0, bg)
            this._Lvm(hwnd, 0x1024, 0, fg)
            this._Lvm(hwnd, 0x1026, 0, bg)
            this._Lvm(hwnd, 0x1036, 0x00010000, 0x00010000)
            ; 改完立刻重画：调用点通常在 Show() 之前，不重画会先看到一帧系统白
            DllCall("user32\InvalidateRect", "ptr", hwnd, "ptr", 0, "int", 1)
        }
        return true
    }

    ; 直接对控件 hwnd 发消息（同步等结果，`SendMessageW` 本身是同步的）。
    ; ⚠ 别用内置 SendMessage(0x1001, 0, bg, "ahk_id " . hwnd)：它**第 4 个参数是
    ;   Control 不是 WinTitle**（见 .clinerules/03），要靠 "last found window" 兜底 ——
    ;   实测窗口一多就落空，症状是"列表还是系统白、代码看着明明调了"。
    static _Lvm(hwnd, msg, wParam, lParam) {
        return DllCall("SendMessageW", "ptr", hwnd, "uint", msg, "ptr", wParam, "ptr", lParam, "ptr")
    }

    ; ─── Edit / ComboBox 底色 ─────────────────────────────────────────────
    ; Edit / ComboBox **也不吃** Gui.BackColor —— 系统在 WM_CTLCOLOREDIT 里问
    ; 「用哪个刷子擦底、用哪个颜色写字」。所以这里做两件事：
    ;   ① EditColors() 登记「这个 hwnd 用这两个色」，顺手建一个 SolidBrush；
    ;   ② _Hook() 只挂**一次** OnMessage，按 lParam（控件 hwnd）查表回答。
    ;
    ; ⚠ 为什么要登记而不是全局一个色：同一个进程里可能同时开着深色窗口与浅色控件
    ;   （控制面板就是刻意例外），只能一个控件一个答案；而 OnMessage 全进程挂一次
    ;   就够 —— 挂多次会叠加，回调跑多遍。
    ; ⚠ brush 必须自己管生命周期：每换一次主题就建一个新 brush，**旧的必须
    ;   DeleteObject**，否则切 20 次主题就漏 20 个 GDI 对象（任务管理器里
    ;   「GDI 对象」一列只涨不落）。Sweep() 顺手清掉已销毁控件的条目。
    ; ⚠ 只改背景不改文字 = 白底黑字变深底黑字，比不改更糟 —— 所以这两个色
    ;   永远成对传，别加只收 bg 的重载。
    static _ctl := ""
    static _hooked := false
    static _msgEdit := ""      ; OnMessage 回调的引用（必须声明，类对象不能凭空加属性）

    static EditColors(hwnd, bgHex, fgHex) {
        ok := this._Register(hwnd, bgHex, fgHex)
        ; ⚠ 可编辑 ComboBox 是**两层窗口**：控件本身 + 内部的 Edit 子窗口。
        ;   实测 WM_CTLCOLOREDIT 的 lParam 是**内部 Edit**（parent = ComboBox），
        ;   只登记 ComboBox 的 hwnd 会让编辑区继续是系统白 —— 深色主题下"分类"那一栏
        ;   白得刺眼，浅色主题下则是一块和列表不同色的白板。顺藤摸瓜一起登记。
        inner := this._ComboInnerEdit(hwnd)
        if inner
            this._Register(inner, bgHex, fgHex)
        return ok
    }

    ; ComboBox 内部 Edit 的 hwnd；不是 ComboBox（或不可编辑的 dropdownlist）返回 0。
    ; ⚠ 别改用 GetComboBoxInfo：本机实测它一直返回 0（cbSize / 结构对齐踩坑），
    ;   FindWindowEx 找 "Edit" 子窗口更直白，拿不到就是 0、没有副作用。
    static _ComboInnerEdit(hwnd) {
        cls := Buffer(64, 0)
        if !DllCall("GetClassNameW", "ptr", hwnd, "ptr", cls, "int", 32)
            return 0
        if (StrGet(cls, "UTF-16") != "ComboBox")
            return 0
        return DllCall("FindWindowExW", "ptr", hwnd, "ptr", 0, "wstr", "Edit", "ptr", 0, "ptr")
    }

    static _Register(hwnd, bgHex, fgHex) {
        if !hwnd || !DllCall("user32\IsWindow", "ptr", hwnd, "int")
            return false

        ctl := this._ctl
        if !IsObject(ctl)
            ctl := this._ctl := Map()

        ; 同色重复登记（每次呼出窗口都会调一次）就别白建 brush
        if ctl.Has(hwnd) {
            e := ctl[hwnd]
            if (e.bg = bgHex && e.fg = fgHex) {
                this._Repaint(hwnd)
                return true
            }
            try DllCall("gdi32\DeleteObject", "ptr", e.brush)
            ctl.Delete(hwnd)
        }

        brush := DllCall("gdi32\CreateSolidBrush", "uint", this.Bgr(bgHex), "ptr")
        ctl[hwnd] := {bg: bgHex, fg: fgHex, brush: brush}
        this._Hook()
        this.Sweep()
        this._Repaint(hwnd)
        return true
    }

    ; 清掉 hwnd 已失效的条目，返回清掉的个数（探针 / 排障用）。
    static Sweep() {
        ctl := this._ctl
        if !IsObject(ctl)
            return 0
        dead := []
        for h, e in ctl {
            if !DllCall("user32\IsWindow", "ptr", h, "int")
                dead.Push(h)
        }
        for h in dead {
            try DllCall("gdi32\DeleteObject", "ptr", ctl[h].brush)
            ctl.Delete(h)
        }
        return dead.Length
    }

    ; 只挂一次；回调存成字段 —— OnMessage 不去重，重复挂会叠加，且要能记住引用。
    static _Hook() {
        if this._hooked
            return
        this._hooked := true
        ; ⚠ 类静态方法不能裸传（this 绑不上，见 .clinerules/03）：包一层箭头函数。
        this._msgEdit := (w, l, m, h) => UiPaint._CtlColor(w, l, m, h)
        fn := this._msgEdit
        OnMessage(0x0133, fn)      ; WM_CTLCOLOREDIT      Edit / ComboBox 的编辑区
        OnMessage(0x0134, fn)      ; WM_CTLCOLORLISTBOX   ComboBox 的下拉列表
        ; 0x0138 是防御性挂的（ComboBox 外框那块偶尔走它）；**它并没有修好 ComboBox** ——
        ; 实测加了 0x0138 编辑区照样是系统白，真正的原因在 EditColors() 里：
        ; 可编辑 ComboBox 的编辑区是**它自己的内部 Edit 子窗口**，lParam 给的是那个子窗口。
        OnMessage(0x0138, fn)      ; WM_CTLCOLORSTATIC
    }

    ; 消息处理：wParam = 控件 DC，lParam = 控件 hwnd。返回 brush 即"已处理"。
    ; 表里没有的控件返回空 —— 让系统按默认画（别去动别人的控件）。
    static _CtlColor(wParam, lParam, msg, hwnd) {
        ctl := this._ctl
        if !IsObject(ctl) || !ctl.Has(lParam)
            return
        e := ctl[lParam]
        try {
            DllCall("gdi32\SetTextColor", "ptr", wParam, "uint", this.Bgr(e.fg))
            DllCall("gdi32\SetBkColor", "ptr", wParam, "uint", this.Bgr(e.bg))
        }
        return e.brush
    }

    static _Repaint(hwnd) {
        try {
            DllCall("user32\InvalidateRect", "ptr", hwnd, "ptr", 0, "int", 1)
            DllCall("user32\UpdateWindow", "ptr", hwnd)
        }
    }

    ; ─── 颜色工具 ─────────────────────────────────────────────────────────

    ; "RRGGBB" → COLORREF（0x00BBGGRR）：Win32 的颜色是**反着**存的
    static Bgr(hex) {
        r := Integer("0x" . SubStr(hex, 1, 2))
        g := Integer("0x" . SubStr(hex, 3, 2))
        b := Integer("0x" . SubStr(hex, 5, 2))
        return (b << 16) | (g << 8) | r
    }

    ; 加权亮度 < 128 = 深色。与 ThemeService.IsDark / 前端 ahk.ts 的 luminance() 同式。
    static IsDark(hex) {
        r := Integer("0x" . SubStr(hex, 1, 2))
        g := Integer("0x" . SubStr(hex, 3, 2))
        b := Integer("0x" . SubStr(hex, 5, 2))
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128
    }
}
