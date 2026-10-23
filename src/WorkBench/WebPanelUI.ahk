#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WebPanelUI —— 平台级界面：Alt+S 工作台面板（WebView2 版）
; ═══════════════════════════════════════════════════════════════════════════
;  v2.10 起面板从原生 Gui 搬进 WebView2：原生控件做不出 backdrop-filter，
;  面板要与笔记窗穿同一套「琉璃」材质，只能走网页。
;
;  **窗口生命周期不在这里** —— 建窗 / 隐藏态定位 / 露面后挂载 / Esc / 换主题
;  全在 WebWindow.ahk（v2.11 抽出，提示词库、编辑窗、日期跳转共用同一份）。
;  本文件只剩「面板特有」的三件事：
;    ① 打开时停在哪一页（_focus，被 PanelData.Json() 读走）；
;    ② 把「未配置槽位」这类跨模块请求翻译成「打开某页」；
;    ③ 已经开着时直接切页，不重建窗口。
;
;  「怎么摆」全在 web\src\components\PanelView.vue —— 加模块、改布局不动本文件。
; ═══════════════════════════════════════════════════════════════════════════

class WebPanelUI {
    static _win := ""

    ; 打开时停在哪一页（模块 Id；空 = 第一页「全部热键」）
    static _focus := ""

    static _Title() => Config.AppName . " · 工作台"

    ; PanelData.Json() 读它。用方法而不是属性：v2 的静态属性 getter 写起来啰嗦，
    ; 而这里只是把字段读出来 —— 页面靠它决定首屏停在哪页。
    static FocusId() => this._focus

    static Init() {
        ; 某个槽位没配好这类请求由模块发事件进来（模块不认识平台类），
        ; 平台负责把面板开到对应的页 —— Feature → EventBus → 平台 的解耦写法。
        EventBus.On("Panel.OpenRequested", (data) => this._OnOpenRequested(data))
        ; 面板也跟主题走：它是「平台界面」，不属于任何模块
        EventBus.On("Theme.Changed", (*) => this._OnThemeChanged())
    }

    ; ─── Alt+S ─────────────────────────────────────────────────────────
    ; 两种语义，靠 moduleId 区分：
    ;   · **裸调用**（Alt+S 热键）= 随手键 → 开关。第一次打开、再按收起。
    ;     旧版只在「打开 / 切页」上做文章，面板开着时按 Alt+S 毫无反应 ——
    ;     用户只能改按 Esc 或右上角的 ×，与 .clinerules/02「Alt+S 是随手按的键」
    ;     那句话正好相反（那里的 `Hide` 而不是 `Destroy` 也是为这个准备的）。
    ;   · **带 moduleId**（模块发的 Panel.OpenRequested）= 明确的「打开我这一页」，
    ;     **永远不关窗** —— 请求方要的是看见自己的设置，关掉等于把请求吞了。
    static ShowHelp(moduleId := "") {
        ; 目标页记下来：页面 onMounted 会从 getPanel 的 focus 字段读，
        ; 不依赖「导航完再 Eval」的时序（那次可能落在脚本就绪之前，静默丢掉）。
        this._focus := moduleId

        if !IsObject(this._win)
            this._win := this._NewWindow()

        if this._win.IsShown() {
            if (moduleId != "") {
                this._win.Activate()
                ; 已经开着 → 页面早就在跑，直接让它切页（首次打开那股走 focus）
                WebHostService.Eval("window.__swpanel&&window.__swpanel.goto("
                    . JsText.Escape(moduleId) . ")", this._win.Hwnd())
                return
            }
            ; 裸 Alt+S = 收起。窗口是 Hide 不是 Destroy，再按一次回来还停在原页。
            this._win.Close()
            return
        }
        this._win.Open()
    }

    static Close() {
        if IsObject(this._win)
            this._win.Close()
    }

    static IsOpen() => IsObject(this._win) ? this._win.IsOpen() : false

    static Hwnd() => IsObject(this._win) ? this._win.Hwnd() : 0

    ; 面板自己的那一份窗口参数。
    ; ⚠ dataDir 必须与笔记窗、其它 Web 窗口**都不同**（见 WebWindow 文件头）。
    ; ⚠ Esc 走 WebWindow 的 HotIfWinActive 钩子，不靠 Gui 的 Escape 事件 ——
    ;   键盘焦点在 WebView2 子窗口里，Gui 收不到那个事件。
    static _NewWindow() {
        return WebWindow({
            title:    this._Title(),
            w:        940,
            h:        700,
            view:     "panel",
            dataDir:  "panel",
            handlers: PanelHostHandlers,
            place:    "center",
            ; 管理面板是「会停留操作」的窗口：允许最小化到任务栏，
            ; 而 Esc / × 仍然是隐藏（不退出程序）—— 两者语义不同，别合并。
            minimizeBox: true,
            esc:      () => this.Close()
        })
    }

    ; ─── 换主题 ────────────────────────────────────────────────────────
    ; 从原生控件搬过来最大的收益之一：**不用重建窗口**。原生版 30+ 个控件逐块
    ; 上色比重建还慢，只能关掉重开、还会退回第一页；现在窗口底色换一下、把
    ; --sw-* 推给页面即可，当前停在哪页保持不变。
    static _OnThemeChanged() {
        if IsObject(this._win)
            this._win.ApplyTheme()
    }

    ; ─── 模块请求：「把我这一页打开」────────────────────────────────────
    ; 现在只有 Folders 在用（某个槽位没配好 → 直接开到它的设置页）。
    static _OnOpenRequested(data) {
        moduleId := (IsObject(data) && data.HasProp("moduleId")) ? data.moduleId : ""
        this.ShowHelp(moduleId)
    }
}
