#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ThemeService —— 工作台主题（平台服务）
; ═══════════════════════════════════════════════════════════════════════════
;  v2.9 从 modules\SevenNote\Services\ 上收到平台。主题不是笔记的私事：
;  提示词库 / 日期对话框 / 启动提示都该跟着它走 —— 控制面板（Alt+S）是
;  **刻意的例外**，它有自己一套配色，不订阅 Theme.Changed。
;
;  职责只有三件：
;    ① 持有主题表与当前下标（[Appearance] ThemeIndex 持久化）
;    ② 把 4 个基色派生成窗口要用的**语义色板**（Palette）
;    ③ 换主题时广播 Theme.Changed —— 谁窗口开着谁自己重绘
;
;  ⚠ 它**不碰任何窗口**：上色由窗口自己读 Palette()，平台只回答「当前是哪一套」。
;    别加「窗口 / 编辑区没就绪就 return」的守卫 —— 那会让 SaveToConfig 也不执行，
;    主题永远停在第一套。
;
;  ⚠ 语义名与前端 web/src/style.css 的 --sw-* 一一对应，派生公式两边一致
;    （见 _Shift / _Mix）：网页里的米黄与 AHK 窗口的米黄必须是同一个米黄。
;
;  加新主题：Themes **末尾追加**一行（ThemeIndex 存的是数组下标，插中间会顶掉
;  老用户当前的主题），并且前一条结尾补 `},` —— 漏逗号报 Unexpected "{"，
;  方案 A 的预检查不出来。
;  ⚠ 主题只含**纯色**四项 + 可选 style / material。v2.16 删掉 BackdropService 后
;    不再有背景图字段（bg / bgAlpha / bgFit）：它把图贴成窗口里的 Static 控件，
;    而 WebView2 客户区是独立合成表面、整片盖在上面 —— 贴了也看不见，
;    只剩一条「配了却没效果」的链路。要装饰就改 glass.css 的材质层。
class ThemeService {
    ; ⚠ 主题表只剩**琉璃·极光霜**一套。纯米黄（flat 基线）在 v2.10 彻底下线：
    ;   整套 UI 只走材质设计，留着一条 flat 路径等于留一条「永远没人回归的岔路」。
    ;   护眼绿 / 纸白 / 星空 / 金克斯仍然下线（历史版本见 git）；
    ;   带背景图的那几套随 BackdropService 一起删除，理由见文件头。
    ;
    ;   要再加主题**只追加到末尾**，别插到前面：ThemeIndex 存的是下标。
    ;   条目的字段：win / edBg / text / dim 四个基色，其余由 Palette() 派生。
    static Themes := [
        ; 琉璃：纯代码主题，**故意不带 bg** —— 观感全部由前端 glass.css 的材质层做
        ; （光雾 / 霜 / 冰面 / 冰棱 / specular 都在 WebView2 里），AHK 只负责底色、
        ; 标题栏和原生窗的玻璃背衬（GlassPaint）。
        ;   style 是皮肤开关：前端据此把 html[data-style] 设成 glass，整套材质才启用。
        ;   v2.13 起**去色**：win / edBg / text / dim / accent 全部 r=g=b。
        ;     玻璃的透明感来自「明暗层次 + 高光棱」，不来自色相 —— 带色只会
        ;     读成「一块蓝色亚克力」。原来那版是深青 → 浅蓝，两版都还是「有色的板」。
        ;   ⚠ 必须严格 r=g=b：Palette() 的 border / panel / codeBg 由这几个基色
        ;     混合派生，输入带一点点偏色，派生结果就会被放大成可见的色偏。
        ;   ⚠ 明度上限仍是 WCAG：正文 #F2F2F2 在 #1C1C1C 上约 15.8:1、
        ;     次级 #B4B4B4 约 8.6:1 —— 中性底可以放心压暗，不需要为对比度提亮。
        ;   ⚠ 强调色只做「装饰级」用途（焦点环 / 光标 / 光点）；正文一律用 text。
        ;   material 是材质参数的覆盖点（键名映射成 --sw-<key>）；缺省即
        ;   tokens.css 里的「薄透」档（blur 15 / sat 120% / tint .028 / edge .4 /
        ;   frost .016 / spec .8）—— 默认值只写一处，这里不跟着抄一遍。
        {name: "哑光灰", win: "242424", edBg: "2E2E2E", text: "F2F2F2", dim: "BABABA"
            , accent: "E4E4E4", style: "glass"}
    ]

    static _current := 1
    static _loading := false

    ; ─── 查询 ─────────────────────────────────────────────────────────────

    static GetCurrent() => this._current
    static GetName() => this.Themes[this._current].name

    ; ─── 语义色板 ─────────────────────────────────────────────────────────
    ; 与前端 --sw-* 同名同义：
    ;   win    窗口底        ← --sw-bg-alt      （标题栏 / 面板底色）
    ;   edBg   内容底        ← --sw-bg          （正文 / 列表底）
    ;   text   正文          ← --sw-fg
    ;   dim    次要文字      ← --sw-dim
    ;   accent 强调色        ← --sw-accent      主题可自带，缺省按明暗取
    ;   border 分隔线        ← --sw-border      派生：win 往 text 偏 18%
    ;   panel  区域底        ← 无（面板例外不用它）派生：win 再偏一档
    ;   codeBg 代码块 / 列表底 ← --sw-code-bg   派生：与 ahk.ts 的 shift 同式
    ;
    ; ⚠ panel 的偏移量不是随手取的：原工作台面板正是 FFF8E7 → F2E8D2（≈ -13），
    ;   而 .clinerules/02 实测「只差一档几乎看不出分区」—— 这里取 14，比原来还深一点。
    static Palette(idx := 0) {
        t := this.Themes[idx ? idx : this._current]
        dark := this.IsDark(t.win)

        ; ⚠ v2.15 起不再合并 [Appearance] 的「材质浓度 / 圆角 / 动效 / 密度」四项：
        ;   那四档的实际观感差几乎看不出来，却要占一整套配置读写 + 重刷链路。
        ;   现在观感由**主题自己**给全，旧配置里的那四个键保留但不再读取 ——
        ;   手改过的值也不会再把界面带偏。
        ;   前端缺省值仍由 tokens.css 提供：半径 16px、动效 120/200/480、密度标准。

        p := {
            name: t.name, dark: dark,
            win: t.win, edBg: t.edBg, text: t.text, dim: t.dim,
            accent: t.HasProp("accent") ? t.accent : (dark ? "7FB4D8" : "4A7C9E"),
            border: this._Mix(t.win, t.text, 0.18),
            panel:  this._Shift(t.win, dark ? 14 : -14),
            codeBg: this._Shift(t.edBg, dark ? 12 : -8),
            ; ── 材质（glass）────────────────────────────────────────────────
            ; style 为空 = flat（米黄的默认行为，前端一个字节都不改）；
            ; 给了 "glass" 才启用 glass.css 整套材质（前端把 html[data-style] 设成它）。
            ; material 是**可选**的手动覆盖：键名直接映射成 --sw-<key>，
            ; 值必须是可直接写进 CSS 的字符串（"14px" / "rgba(...)"）。
            ; 缺省时前端用 glass.css 里的默认值 —— 默认值只写一处，这里不抄一遍。
            ; ⚠ v2.15 起**没有「用户档位」这一层**：material 只由主题自己给，
            ;   不再有「用户选了浓郁就盖过主题」的分支（那套滑杆已撤）。
            style:  t.HasProp("style") ? t.style : "",
            material: t.HasProp("material") ? t.material : ""
        }
        return p
    }

    ; ─── 换主题 ───────────────────────────────────────────────────────────

    static Next() {
        ; 只有一套时 Alt+T 是**空操作**：不写配置、不发事件 ——
        ; 发了也只是让各窗口白重绘一遍（每次都要重建 brush），纯属折腾。
        if (this.Themes.Length <= 1)
            return this._current
        this.Apply(this._current >= this.Themes.Length ? 1 : this._current + 1)
        return this._current
    }

    ; 切换并广播。**不看窗口**：谁开着窗口谁订阅 Theme.Changed 自己重绘 ——
    ; 平台不知道有几个窗口，也不该知道（模块可插拔）。
    static Apply(idx) {
        if (idx < 1 || idx > this.Themes.Length)
            idx := 1
        this._current := idx

        if !this._loading
            this.SaveToConfig()

        p := this.Palette()
        EventBus.Emit("Theme.Changed", {name: p.name, idx: idx, dark: p.dark})
        return p
    }

    ; ─── 持久化 ───────────────────────────────────────────────────────────

    static SaveToConfig() {
        ConfigService.Write("Appearance", "ThemeIndex", this._current)
    }

    ; 启动时恢复。**只改状态、不广播**：调用点在 WorkBench.Init() 开头，
    ; 那时窗口一个都还没建，广播出去也没人接；而且模块 Init 正要读 GetCurrent()
    ; 来定主窗口底色与 WebView2 首帧色。
    static LoadFromConfig() {
        this._loading := true
        idx := ConfigService.ReadInt("Appearance", "ThemeIndex", 1)
        idx := this._MigrateIndex(idx)
        if (idx < 1 || idx > this.Themes.Length)
            idx := 1
        this._current := idx
        this._loading := false
        return idx
    }

    ; ─── 旧下标迁移 ───────────────────────────────────────────────────────
    ; 主题表被精简过三次，而配置里存的始终是**下标**：
    ;   schema 1 = 8 套（v2.4 之前）   schema 2 = 5 套（v2.4–v2.8）
    ;   schema 3 = 1 套（v2.9：只留纯米黄）   schema 4 = 1 套（v2.10：只留琉璃）
    ; 现在只有 1 套，所以**老配置的 1–8 一律归 1**，逐条映射已无意义。
    ; ⚠ 迁移只能做一次，并且**必须把新值写回配置** —— 否则每次启动都拿 ThemeIndex=5
    ;   去撞越界兜底，配置里永远躺着一个不存在的下标。
    static _MigrateIndex(idx) {
        if (ConfigService.ReadInt("Appearance", "ThemeSchema", 1) >= 4)
            return idx
        ConfigService.Write("Appearance", "ThemeIndex", 1)
        ConfigService.Write("Appearance", "ThemeSchema", 4)
        return 1
    }

    ; ─── 颜色工具 ─────────────────────────────────────────────────────────

    ; 「深色」判据：底色按加权亮度 < 128 即视为深色。标题栏 / 滚动条 / 派生态共用这一条，
    ; 前端 ahk.ts 的 luminance() 也用同一公式 —— 两边判出来的明暗必须一致。
    static IsDark(hex) {
        r  := Integer("0x" . SubStr(hex, 1, 2))
        g  := Integer("0x" . SubStr(hex, 3, 2))
        b  := Integer("0x" . SubStr(hex, 5, 2))
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128
    }

    ; 整体加减同一档亮度（三个通道同量）—— 保色相，用于 panel / codeBg。
    ; 与 web/src/ahk.ts 的 shift(hex, delta) 逐字等价。
    static _Shift(hex, delta) {
        r := Integer("0x" . SubStr(hex, 1, 2)) + delta
        g := Integer("0x" . SubStr(hex, 3, 2)) + delta
        b := Integer("0x" . SubStr(hex, 5, 2)) + delta
        return Format("{:02X}{:02X}{:02X}", this._Clamp(r), this._Clamp(g), this._Clamp(b))
    }

    ; 两个颜色线性混合：t = 0 取 a，t = 1 取 b。用于 border（win 往 text 偏），
    ; 比单纯加减亮度好在**色相跟着正文走** —— 深棕字配深棕线、冷白字配冷灰线。
    static _Mix(a, b, t) {
        out := ""
        for i in [1, 3, 5] {
            av := Integer("0x" . SubStr(a, i, 2))
            bv := Integer("0x" . SubStr(b, i, 2))
            out .= Format("{:02X}", this._Clamp(Round(av + (bv - av) * t)))
        }
        return out
    }

    static _Clamp(v) => v < 0 ? 0 : (v > 255 ? 255 : v)
}
