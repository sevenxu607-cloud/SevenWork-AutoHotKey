#Requires AutoHotkey v2.0
; ======================================================================
;  HostBridge.ahk
;  笔记模块暴露给前端（WebView2）的宿主对象。
;
;  前端用法：chrome.webview.hostObjects.ahk.<方法>(…)  见 web/src/ahk.ts
;  AHK 侧注册：WebHostService.Bind("ahk", NoteHostHandlers())
;
;  ⚠ 这里是**顶层函数**不是类静态方法：AddHostObjectToScript 走 IDispatch，
;    类静态方法不在实例上、调用时抛「对象不支持此属性或方法」。S2b 用顶层
;    函数验证通过，照这个来。
;  ⚠ 方法名必须与 ahk.ts 里的字符串逐个对齐 —— 拼错不报错，只是前端抛
;    「AHK 未提供方法：xxx」，而 storeImage 会把这条 catch 掉、静默退回 base64。
;  ⚠ 返回值一律**字符串**：对象 / 数字要额外实现接口，字符串最省事，前端自己解析。
; ======================================================================

NoteHostPing() => "pong"
NoteHostVersion() => A_AhkVersion

; 语义色板 → JSON。实现已上收到 WorkBench\PanelHostBridge.ahk 的 ThemeJson()：
; 面板也要同一份主题，而「平台去调模块里的函数」是反向依赖（.clinerules/02）。
; 这里只留转发，字段顺序 / 名字以平台侧那份为准。
;
; 编辑区字体 / 字号是**笔记模块的业务**（Alt+Shift+F 那些档位），不能塞进平台的
; ThemeJson() —— 平台调模块里的 FontService 同样是反向依赖。做法：平台那份原样
; 取来，去掉收口的 `}`，补两个字段再收口。前端拿到 --sw-ed-font / --sw-ed-size，
; 面板那张网页不消费它们（那里该用系统 UI 字体）。
; ⚠ 字号单位是**磅（pt）**，与旧版 RichEdit 的 yHeight = size*20 twips 同源；
;   前端直接写 `14pt`，别自己换算成 px —— 换错的观感差异恰好就是「字变大」。
NoteHostTheme() {
    j := ThemeJson()
    return SubStr(j, 1, -1)
        . ',"font":'     . JsText.Escape(FontService.GetName())
        . ',"fontSize":' . FontService.GetSize()
        . "}"
}

; 状态栏元信息 → JSON（日期 / 中文星期 / 标签）。
; 对应原生版 StatusBar 的「📅 日期 星期」与「🏷 标签」两条 —— 迁移到 WebView2 后
; 底栏只剩保存状态与字数，这两条丢了。恢复它们，数据仍只在 AHK 侧有一份。
; ⚠ 标签以**当前文件路径**为准（文件名就是标签），不读正文里的写法。
NoteHostMeta() {
    m := NoteSessionService.Meta()
    return "{"
        . '"date":'    . JsText.Escape(m.date)    . ","
        . '"weekday":' . JsText.Escape(m.weekday) . ","
        . '"tag":'     . JsText.Escape(m.tag)
        . "}"
}

; 粘贴的图片落盘：base64 → <vault>\_assets\<日期>\sw_*.png，返回 ./_assets/… 相对路径。
; 失败返回空串 —— 前端据此回退成内联 data URL，不会让整次粘贴失败。
NoteHostSaveImage(b64, ext := "png") {
    try {
        rel := NoteImageService.SaveBase64(b64, ext, State.GetDate(), Config.GetVault())
        return rel
    } catch as e {
        LogError("图片落盘失败：" . e.Message)
        return ""
    }
}

; 交给 WebHostService.Bind 的方法表
NoteHostHandlers() {
    return {
        ping:      NoteHostPing,
        version:   NoteHostVersion,
        getTheme:  NoteHostTheme,
        meta:      NoteHostMeta,
        saveImage: NoteHostSaveImage
    }
}
