#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PromptEditFeature —— 提示词的查看 / 新建 / 编辑 / 删除（模块：Text）
; ═══════════════════════════════════════════════════════════════════════════
; 双击列表某行或按 Ctrl+N 打开。同一个窗口两用：
;   Open("")      → 新建（标题 / 分类留空，删除按钮禁用）
;   Open(item)    → 编辑（三个字段填好，删除按钮可用）
;
; 保存一律交给 PromptStoreService.Save()：它负责清理标题、建分类目录、
; 撞名自动 -2、改名走「先写新后删旧」。本类只管把界面上的三个值递过去。
;
; ⚠ 正文用 Edit（不是 RichEdit）：提示词是纯文本 md，不需要字符格式，
;   而 Edit 的背景 / 文字色可控、也不需要 EditorService 那套 RTF 逻辑。

class PromptEditFeature {
    static _gui := ""
    static _title := ""
    static _cat := ""       ; ComboBox：可从已有分类里选，也能手输新分类
    static _body := ""
    static _del := ""
    static _hint := ""
    static _editing := ""   ; 正在编辑的条目（对象）；"" = 新建

    ; 新建时预填的分类（上次保存用过的那个）。只放内存 —— 重启回落到「未分类」，
    ; 不为一个便利值去动 Config（Kernel 冻结区）。
    static _lib := ""

    static _lastCat := ""

    ; 打开时记下的内容基线（标题 / 分类 / 正文）。
    ; 退出守卫靠它判断「改了没保存」；空串 = 当前没有正在编辑的内容
    ; （保存成功或按 Esc 放弃后都会清掉，用户再按退出就不该被拦）。
    static _dirtyBase := ""

    ; 删除是否已「上膛」（第一次点过、等第二次点）。见 OnDeleteClick()
    static _delArmed := false
    ; 倒计时定时器的闭包引用 —— 第二次点击 / 关窗时要能用同一个引用把它停掉
    static _delTimer := ""

    ; ─── 句柄 / 可见性 ───
    static Hwnd() {
        if !IsObject(this._gui)
            return 0
        try hwnd := this._gui.Hwnd
        catch
            return 0
        ; ⚠ 只看 Gui 对象不够：窗口被系统销毁后，Gui 对象可能还活着，
        ;   旧 HWND 也仍是非零值。不校验 IsWindow，下次 Open() 会以为窗口
        ;   还在，然后去操作已经销毁的控件 —— 表现就是「新建提示词异常」。
        if !hwnd || !DllCall("user32\IsWindow", "ptr", hwnd, "int")
            return 0
        return hwnd
    }

    static IsShowing() {
        hwnd := this.Hwnd()
        if !hwnd
            return false
        return !!DllCall("IsWindowVisible", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
    }

    ; ═══ 打开 ═══

    ; item = ""（新建）或 PromptStoreService.LoadAll() 里的一项
    static Open(item := "") {
        this._lib := PromptStoreService.Lib
        ; 任何控件失效 / 旧句柄 / 分类下拉异常都转成明确的 false，
        ; 不让异常穿到 hostObjects 调用栈里，变成前端一句看不懂的 TypeError。
        try
            return this._Open(item)
        catch as e {
            LogError("打开提示词编辑窗失败：" . e.Message)
            return false
        }
    }

    static _Open(item := "") {
        if !this.Hwnd() {
            this._gui := ""
            this._Build()
        }

        ; 每次打开都复位删除按钮 + 重扫分类下拉：
        ;   _ResetDelete —— 上次可能停在「确认删除」状态（用户点了删除又关窗）
        ;   _FillCategories —— 目录可能刚在资源管理器 / VS Code 里新建
        this._ResetDelete()
        this._FillCategories()

        this._editing := item
        if IsObject(item) {
            this._title.Value := item.title
            this._SetCatText(StrReplace(item.category, "\", "/"))
            this._body.Value  := item.text
            this._del.Enabled := true
            this._gui.Title   := Config.AppName . " · 编辑提示词"
        } else {
            this._title.Value := ""
            this._SetCatText(this._lastCat)
            this._body.Value  := ""
            this._del.Enabled := false
            this._gui.Title   := Config.AppName . " · 新建提示词"
        }

        this._gui.Show("w520 h480")
        try WinActivate("ahk_id " . this.Hwnd())
        try this._title.Focus()

        ; 基线必须在填完值之后取：_SetCatText 走 WM_SETTEXT，值要落定；
        ; 放在赋值之前会记成上一次的残留，于是「刚打开就算脏」。
        this._dirtyBase := this._Snapshot()
        return true
    }

    static Hide() {
        ; 停掉删除倒计时并复位 —— 否则下次打开窗口还停在「确认删除」状态
        this._StopDeleteTimer()
        this._ResetDelete()
        ; 收起 = 这次编辑结束（保存成功 / 用户按 Esc 放弃）。清掉基线，
        ; 免得用户明明放弃了改动、退出时还被问一次。
        this._dirtyBase := ""
        if IsObject(this._gui)
            try this._gui.Hide()
    }

    ; ─── 未保存检测（退出守卫用）────────────────────────────────────────
    static _Snapshot() {
        return {title: this._title.Value
            , cat: this._GetCatText(), body: this._body.Value}
    }

    static IsDirty() {
        if !IsObject(this._gui) || !IsObject(this._dirtyBase)
            return false
        ; 控件可能已经跟着窗口一起没了（系统注销 / 异常销毁）。这时「算不出改没改」，
        ; 按「没改」放行 —— 否则守卫抛错会永远拦着退出，用户只能杀进程。
        if !IsObject(this._title) || !IsObject(this._body)
            return false
        b := this._dirtyBase
        try {
            ; ⚠ 必须用 `!==`（区分大小写）。写成 `!=` 的话，「只把 hello 改成
            ;   Hello」会被判成没改 —— 退出时不拦，改动就丢了。
            return this._title.Value !== b.title
                || this._GetCatText() !== b.cat
                || this._body.Value !== b.body
        } catch {
            return false
        }
    }

    ; 退出守卫：有未保存内容就把窗口摆到眼前并拦下退出，返回 {ok, reason}。
    ; ⚠ 不用 MsgBox 做「保存 / 放弃 / 取消」三选：编辑窗是 AlwaysOnTop，模态框
    ;   会被压在后面（删除确认那段注释记过同一个坑），用户只会觉得「按退出没反应」。
    ;   这里改成：拒绝退出 + 在提示行写清下一步 —— 保存在 Ctrl+S，放弃按 Esc。
    static ExitCheck() {
        if !this.IsDirty()
            return {ok: true, reason: ""}

        ; 窗口可能已经隐藏（Esc 只是 Hide，内容还在）—— 原样露出来。
        ; ⚠ 不能调 Open()：它会按 _editing 重新填一遍，把用户刚敲的字覆盖掉。
        if !this.IsShowing()
            this._RevealKeepingEdit()
        else
            try WinActivate("ahk_id " . this.Hwnd())

        this._ShowHint("有未保存的修改：Ctrl+S 保存，或按 Esc 放弃后再退出", true)
        return {ok: false, reason: "提示词「" . this._DirtyName() . "」有未保存的修改"}
    }

    ; 把已隐藏的编辑窗原样露出来：不重填内容、不重置基线
    static _RevealKeepingEdit() {
        if !IsObject(this._gui)
            return
        try {
            this._gui.Show("w520 h480")
            WinActivate("ahk_id " . this.Hwnd())
        }
    }

    static _DirtyName() {
        if IsObject(this._editing)
            return this._editing.title
        t := Trim(this._title.Value)
        return (t = "") ? "新建的提示词" : t
    }

    ; 提示行统一入口：warn = true 时加 ⚠ 前缀并换警示色。
    static _ShowHint(text, warn := false) {
        if !IsObject(this._hint)
            return
        try {
            this._hint.Value := (warn ? "⚠ " : "") . text
            this._hint.SetFont("s9 c"
                . (warn ? this._WarnColor() : ThemeService.Palette().dim), "楷体")
        }
    }

    ; ═══ 建窗 ═══

    static _Build() {
        ; 建窗时按当期主题上色；之后按 Alt+T 走 OnThemeChanged() 重刷。
        p := ThemeService.Palette()

        g := Gui("+AlwaysOnTop +OwnDialogs -MinimizeBox -MaximizeBox", Config.AppName . " · 提示词")
        g.BackColor := p.win
        g.SetFont("s11", "楷体")

        g.AddText("x12 y16 w44 h20", "标题")
        this._title := g.AddEdit("x60 y12 w448 h24")

        g.AddText("x12 y48 w44 h20", "分类")
        ; 可编辑下拉 = 「选」+「输」两全：列表列出 ListCategories() 的全部目录
        ; （含空目录、含 Code/代码审查 这种多级），用户也可直接敲新分类，
        ; Save() 里 SanitizeCategory + DirCreate 会自动建目录。
        ; ⚠ h200 是**下拉列表总高**（约 8 行），不是控件自身高度 —— 控件仍是一行，
        ;   下面 y80 的正文框不会因此移位。
        this._cat := g.AddComboBox("x60 y44 w448 h200")

        ; +Multi：多行；+VScroll：内容长了能滚；+WantReturn：Enter 在正文里换行，
        ; 不会跑去点「保存」（这个窗口激活时主窗口的 Enter 热键本来也不生效）
        this._body := g.AddEdit("x12 y80 w496 h326 +Multi +VScroll +WantReturn")
        this._body.SetFont("s11", "楷体")

        ; 提示行兼作「删除待确认 / 保存失败」的提示位，所以宽度给足（w420）
        this._hint := g.AddText("x12 y416 w420 h20", "分类可从列表选，也可手输（多级：Work/会议）")
        this._hint.SetFont("s9 c" . p.dim, "楷体")

        ; 宽 96 是为了放下「确认删除」四个字（w80 会挤成省略号）
        this._del := g.AddButton("x12 y442 w96 h26", "删除")
        this._del.OnEvent("Click", (*) => this.OnDeleteClick())

        cancelBtn := g.AddButton("x344 y442 w80 h26", "取消")
        cancelBtn.OnEvent("Click", (*) => this.Hide())

        saveBtn := g.AddButton("x432 y442 w76 h26", "保存")
        saveBtn.OnEvent("Click", (*) => this.Save())

        ; 点标题栏 X = 隐藏（不保存）。与主窗口同一套处理：
        ; 返回 true 阻止默认销毁，下一次 Open() 直接复用同一个窗口。
        g.OnEvent("Close", (*) => (this.Hide(), true))

        this._gui := g

        ; 标题栏 / 滚动条 / 原生控件跟着主题明暗
        UiPaint.TitleBar(g.Hwnd, p.win, p.text)
        UiPaint.WindowTheme(g.Hwnd, p.dark)
        ; 玻璃背衬（只有玻璃主题给）：见 GlassPaint 的降级链
        UiPaint.Glass(g.Hwnd, p.style, p.win)
        ; 三个输入控件：Edit / ComboBox 都不吃 BackColor，走 WM_CTLCOLOREDIT 登记
        ; （ComboBox 的输入区与下拉列表分别发 0x0133 / 0x0134，同一份登记够用）
        UiPaint.EditColors(this._title.Hwnd, p.codeBg, p.text)
        UiPaint.EditColors(this._cat.Hwnd, p.codeBg, p.text)
        UiPaint.EditColors(this._body.Hwnd, p.codeBg, p.text)
    }

    ; 换主题（Alt+T）：整窗重刷。窗口没建 / 已销毁就直接返回 ——
    ; 下次 Open() 重建时会读当期色板。
    static OnThemeChanged() {
        hwnd := this.Hwnd()
        if !hwnd
            return
        p := ThemeService.Palette()
        try this._gui.BackColor := p.win
        UiPaint.TitleBar(hwnd, p.win, p.text)
        UiPaint.WindowTheme(hwnd, p.dark)
        try UiPaint.EditColors(this._title.Hwnd, p.codeBg, p.text)
        try UiPaint.EditColors(this._cat.Hwnd, p.codeBg, p.text)
        try UiPaint.EditColors(this._body.Hwnd, p.codeBg, p.text)
        ; 提示行可能正停在"确认删除"（红字）状态：_ResetDelete 会把它写回常规措辞 + dim
        this._ResetDelete()
    }

    ; 警示红：C0392B 压在深色底上几乎看不见，深色主题换亮一档的红。
    static _WarnColor() {
        return ThemeService.Palette().dark ? "FF7B72" : "C0392B"
    }

    ; ─── 分类框读写（走 Win32 消息，绕开 ComboBox.Value）───
    ; ⚠ 不能用 ComboBox.Value 读写：实测下拉已填好 5 项（含 "Code"）再 `Value := "Code"`
    ;   照样抛 "Invalid value"。而可编辑下拉的语义本来就是「值可以不在列表里」——
    ;   目录被删了、或用户正要输一个新分类，都是常态。所以读写都走消息：
    ;   WM_SETTEXT(0x0C) / WM_GETTEXT(0x0D) 直接对编辑区动手，不做任何校验。
    static _SetCatText(v) {
        if IsObject(this._cat)
            try DllCall("SendMessage", "ptr", this._cat.Hwnd, "uint", 0x000C, "ptr", 0, "ptr", StrPtr(v))
    }

    static _GetCatText() {
        if !IsObject(this._cat)
            return ""
        cb := this._cat.Hwnd
        len := DllCall("SendMessage", "ptr", cb, "uint", 0x000E, "ptr", 0, "ptr", 0, "ptr")
        if (len <= 0)
            return ""
        buf := Buffer((len + 1) * 2, 0)
        DllCall("SendMessage", "ptr", cb, "uint", 0x000D, "ptr", len + 1, "ptr", buf.Ptr, "ptr")
        return StrGet(buf, "UTF-16")
    }

    static Save() {
        if !IsObject(this._gui)
            return
        oldPath := IsObject(this._editing) ? this._editing.path : ""
        catText := this._GetCatText()
        prevLib := PromptStoreService.Lib
        if (this._lib != "" && this._lib != prevLib)
            PromptStoreService.Lib := this._lib
        res := PromptStoreService.Save(catText, this._title.Value, this._body.Value, oldPath)
        PromptStoreService.Lib := prevLib
        if !res.ok {
            this._ShowError(res)
            return
        }
        ; 记住这次用的分类：下一条新建时直接预填（本轮内有效，重启回落到「未分类」）
        this._lastCat := PromptStoreService.SanitizeCategory(catText)
        ttl := PromptStoreService.SanitizeName(this._title.Value)
        this.Hide()
        PromptWindowFeature.Reload(true)
        PromptWindowFeature.FocusPath(res.path)
        PromptWindowFeature.Notify("已保存「" . ttl . "」")
    }

    ; ═══ 删除：窗口内二次确认 ═══
    ; ⚠ 为什么不用 MsgBox 确认：它是**模态**的、会阻塞脚本线程，而编辑窗口是
    ;   AlwaysOnTop —— 对话框被压在窗口后面，用户体验就是「点了删除没反应，
    ;   把窗口关掉才看到确认框」（2026-10-20 实测反馈）。现在全程在窗口内：
    ;   第一次点 → 按钮变「确认删除」+ 提示行写「3 秒内有效」；
    ;   第二次点 → 真删；超时 / 关窗 / 保存 → 自动复位。
    static OnDeleteClick() {
        if !IsObject(this._editing)
            return
        if !this._delArmed {
            this._ArmDelete()
            return
        }
        this._StopDeleteTimer()          ; 先停倒计时，免得回调在删除后又跑一次
        this._delArmed := false
        this._DoDelete()
    }

    static _ArmDelete() {
        this._delArmed := true
        try this._del.Text := "确认删除"
        ; ⚠ 标准 Button 控件不响应文字颜色（只认字体），所以红色只体现在提示行。
        if IsObject(this._hint)
            try {
                this._hint.Value := "再点一次「确认删除」· 3 秒内有效"
                this._hint.SetFont("s9 c" . this._WarnColor(), "楷体")
            }
        ; ⚠ 这里**只能**用箭头函数：AHK v2.0.27 的 SetTimer 不接受类静态方法的
        ;   函数对象（实测 `T.Reset` 的 Type 是 Func，传给 SetTimer 却报
        ;   "Invalid callback function"）。闭包引用存在 _delTimer 里，才能用
        ;   同一个引用调 SetTimer(fn, 0) 停掉。
        this._StopDeleteTimer()
        timerFn := () => this._ResetDelete()
        this._delTimer := timerFn
        SetTimer(timerFn, -3000)
    }

    static _StopDeleteTimer() {
        timerFn := this._delTimer        ; ⚠ 必须先取局部变量，属性求值才稳定
        this._delTimer := ""
        if IsObject(timerFn)
            try SetTimer(timerFn, 0)
    }

    ; 复位按钮与提示行：超时、第二次点击、关窗、再次打开都走这里。
    ; ⚠ 定时器回调可能跑在窗口已销毁之后，所以每个控件都先做 IsObject 守卫。
    static _ResetDelete(*) {
        this._delArmed := false
        if IsObject(this._del)
            try this._del.Text := "删除"
        if IsObject(this._hint)
            try {
                this._hint.Value := "分类可从列表选，也可手输（多级：Work/会议）"
                this._hint.SetFont("s9 c" . ThemeService.Palette().dim, "楷体")
            }
    }

    static _DoDelete() {
        if !IsObject(this._editing)
            return
        ttl := this._editing.title
        res := PromptStoreService.Delete(this._editing.path)
        if !res.ok {
            this._ShowError(res)         ; 失败不关窗，原因写在提示行
            return
        }
        this.Hide()
        PromptWindowFeature.Reload(true)
        PromptWindowFeature.Notify("已删除「" . ttl . "」")
    }

    ; 分类下拉：每次打开重扫目录（几十个目录 <5ms）。
    ; 显示用正斜杠 —— `Code/代码审查` 比 `Code\代码审查` 好读，而 SanitizeCategory
    ; 两种分隔符都认，所以「显示值 → 保存」是可逆的。
    static _FillCategories() {
        if !IsObject(this._cat)
            return
        try this._cat.Delete()           ; 无参 = 清空全部项
        for c in PromptStoreService.ListCategories()
            this._cat.Add([StrReplace(c, "\", "/")])
    }

    ; 失败统一在窗口内反馈（写提示行）+ 详情进 _error.log，不弹模态框。
    static _ShowError(res) {
        if IsObject(this._hint)
            try {
                this._hint.Value := "⚠ " . StrSplit(this._Explain(res), "`n")[1]
                this._hint.SetFont("s9 c" . this._WarnColor(), "楷体")
            }
        if res.HasProp("error")
            LogError("提示词操作失败：" . res.reason . " / " . res.error)
    }

    ; 失败原因翻成中文。Service 只给机器可读的 reason（能力层 / 服务层的约定）。
    static _Explain(res) {
        err := res.HasProp("error") ? "`n" . res.error : ""
        switch res.reason {
            case "empty-title":   return "标题不能为空（文件名就是标题）。"
            case "mkdir-failed":  return "无法创建分类目录。" . err
            case "write-failed":  return "写入文件失败，原文件未改动。" . err
            case "delete-failed": return "删除失败。" . err
            case "not-found":     return "文件已经不在了（可能被外部删掉）。"
            default:              return "操作失败：" . res.reason . err
        }
    }
}
