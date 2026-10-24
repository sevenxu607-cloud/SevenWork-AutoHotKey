#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  FoldersModule —— 文件夹模块（资源的入口）
; ═══════════════════════════════════════════════════════════════════════════
; 定位：**本模块不建自己的窗口**，只负责把系统的资源管理器窗口喊出来 / 收起来。
;   对一个「文件夹」而言，容器是 Explorer 自己提供的 —— 我们只做热键与定位。
;
; 核心设计：**热键写死、目标可换**。
;   文件夹太多，一个目录一个热键会吃光键盘；所以固定 Alt+1/2/3 三个槽位，
;   每个槽位绑哪个目录写在 _config.ini，随时可按需替换。
;   替换入口在 Alt+S 呼出的工作台面板里（模块自己声明设置字段，平台负责渲染）。
;
; 生命周期（照平台的 Init → RegisterAll → Start 三段式）：
;   Init()   读一次槽位，把「哪个槽位没配 / 目录没了」记进日志 —— 只碰配置，不碰窗口
;   Start()  无对外可见动作，不实现
;   GetContexts  只声明一个 explorer 上下文 —— Alt+M（转 Markdown）只在资源管理器
;                前台生效；三条槽位热键仍是全局的。

class FoldersModule {
    static Id := "Folders"
    static Name := "文件"

    static _initialized := false

    static Init() {
        if this._initialized
            return
        this._initialized := true

        ; 槽位配错的提示放在启动时写一次，而不是等用户按了才发现：
        ; 这只是磁盘/配置检查，不碰窗口，符合「Init 只做内部就绪」的约定。
        loop FolderSlotService.Count {
            state := FolderSlotService.GetUsable(A_Index)
            if (state.ok)
                continue
            label := FolderSlotService.HotkeyLabel(A_Index)
            if (state.reason = "missing")
                LogError("文件夹槽位 " . label . " 指向的目录不存在：" . state.path)
            ; 空槽位是**正常状态**（第一次用还没配），不记日志。
        }
    }

    ; ═══ 热键 ═══
    ; 三个槽位各一条，外加一条 Alt+M（转 Markdown，走 explorer 上下文）。
    ; 加槽位只需把 FolderSlotService.Count 调大，并在这里补一行 ——
    ; 帮助窗口与面板都从 GetHotkeys / 服务读，不用再改别处。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!1", group: "文件"
                , line: "   Alt+1            呼出 / 隐藏槽位 1 的文件夹"
                , fn: (*) => FolderWindowFeature.Toggle(1)},
            {ctx: "global", key: "!2", group: "文件"
                , line: "   Alt+2            呼出 / 隐藏槽位 2 的文件夹"
                , fn: (*) => FolderWindowFeature.Toggle(2)},
            {ctx: "global", key: "!3", group: "文件"
                , line: "   Alt+3            呼出 / 隐藏槽位 3 的文件夹"
                , fn: (*) => FolderWindowFeature.Toggle(3)},
            ; 前三条是全局的；这条只在资源管理器前台生效（见 GetContexts）——
            ; 它的输入是「资源管理器里选中的文件」，在别的程序里按到毫无意义。
            {ctx: "explorer", key: "!m", group: "文件"
                , line: "   Alt+M            选中的文件转成 Markdown（存到同级目录）"
                , fn: (*) => ConvertFeature.Run()}
        ]
    }

    ; ═══ 热键上下文 ═══
    ; Alt+M 只在**资源管理器前台**生效：它对着「选中的文件」干活，而 Alt+M 在
    ; Excel / Word 里是有意义的组合键 —— 全局注册会把人家按菜单的那一下抢走。
    ; 类名取 ExplorerProbe.WindowClass：与那边「先圈定候选窗口、再问 COM 要路径」用
    ; 同一个常量，将来窗口类若变，只改一处。
    ; ⚠ 声明了却没人实现的热键会「一条都不注册」并写 _error.log（HotkeyRouter 的行为），
    ;   所以这里的名字必须与 GetHotkeys() 里的 ctx 一字不差。
    static GetContexts() {
        ; 资源管理器窗口 + 桌面：两处都能「选中文件」。
        ; ⚠ 桌面的类名是 Progman / WorkerW（不同 Windows 版本用其中一个），
        ;   而它**不是** Shell.Application 的 Window —— 选中项读不出来，
        ;   所以桌面只负责「让热键有反应并给出说明」，真正的转换仍在资源管理器里做。
        ;   反之，不把桌面列进来时，用户在最常用的地方按 Alt+M 会**完全没反应**
        ;   （钩子条件不满足就放行给系统），看起来就像「功能坏了」。
        isExplorer := (*) => (WinActive("ahk_class " . ExplorerProbe.WindowClass)
            || WinActive("ahk_class Progman")
            || WinActive("ahk_class WorkerW"))
        return {explorer: isExplorer}
    }

    ; ═══ 面板设置声明 ═══
    ; 平台（WebPanelUI）只认 {label, kind, value} 三个字段，**不认识「槽位」这个词**；
    ; 保存时把 values 原样交回这里的 apply 函数，由本模块自己写配置。
    ; 这样平台零业务耦合，将来别的模块加设置照抄这份形状即可。
    ; kind 目前支持 "folder"（输入框 + 浏览按钮）；后续可扩 "text" / "number" / "toggle"。
    ; ⚠ 平台调用时**必须先把 apply 取到局部变量再调**：AHK v2 的 obj.prop(args)
    ;   走方法查找，属性里存的 Func 不会被调用（见 .clinerules/03）。
    static GetSettingsSpec() {
        fields := []
        loop FolderSlotService.Count {
            slot := A_Index
            fields.Push({
                key:   "Slot" . slot,
                label: FolderSlotService.HotkeyLabel(slot) . " →",
                kind:  "folder",
                value: FolderSlotService.Get(slot),
                ; 平台支持的可选字段：空输入框里的灰色提示（EM_SETCUEBANNER）。
                ; 只显示、不写入 —— 不填直接保存，存进去的仍是空串（= 该槽位未启用）。
                placeholder: "留空 = 不启用，也可直接粘贴路径"
            })
        }
        return {
            title:  "文件槽位",
            hint:   "热键固定为 Alt+1/2/3，指向哪个文件夹随时换；留空 = 该槽位未启用。"
                . "`n浏览窗口的地址栏能直接粘贴路径（如 D:\Work），上次浏览的位置会被记住。",
            fields: fields,
            apply:  (values) => FolderSlotService.SaveAll(values)
        }
    }

    ; 帮助窗口（Alt+S）用：order 决定模块在面板里的先后。
    ; 七个核心应用按「笔记 / 文本 / 文件 / 应用 / 视界 / 按键 / 主题」排列；
    ; 视界占 50，本模块占 30。
    static GetMetadata() {
        return {name: this.Name, desc: "文件槽位与转 Markdown · Alt+1/2/3 / Alt+M", order: 30
            , hotkeys: this.GetHotkeys()}
    }
}
