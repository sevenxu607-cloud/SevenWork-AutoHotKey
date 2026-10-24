#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  FolderSlotService —— 文件夹槽位（模块：Folders）
; ═══════════════════════════════════════════════════════════════════════════
; 设计要点：**热键写死、目标可换**。
;   文件夹太多，一个目录配一个热键会把键盘吃光；所以固定三个热键 Alt+1/2/3，
;   背后绑哪个目录写在 _config.ini，随时可换（入口在 Alt+S 工作台面板里）。
;
;   [Folders]
;   Slot1=D:\Work\Current
;   Slot1Zone=工作区
;   Slot2=D:\00-SevenFiles\Documents
;   Slot2Zone=辅助区
;   Slot3=              ← 空 = 未配置，按下时提示去面板设置
;   Slot3Zone=工作区
;
; ⚠ 区域只存中文标签（工作区 / 辅助区 / 记录区）；几何由平台 ZoneService 负责，
;   本服务不认识 ZoneMath，也不做任何窗口操作。
;
; ⚠ 存进 _config.ini 而不是独立文件：与主题 / Vault 同一套持久化，备份只有一处。
; ⚠ 不放 Kernel/Config.ahk：槽位是 Folders 模块的业务配置，Kernel 只管通用路径
;   （Vault / PromptsDir / 日志落点）。Kernel 冻结，只加不改。
; ⚠ 配置读取走 ConfigService（有进程内缓存）：**运行期手改 _config.ini 不会被读到**，
;   改配置请走面板或重启程序（这是 Kernel 既有行为，不是本类引入的）。

class FolderSlotService {
    static Section := "Folders"

    ; 槽位数量。加槽位要同步三处：
    ;   ① 这里；② FoldersModule.GetHotkeys() 里补一条 Alt+N；③ 面板的 slots 循环（自动跟随本值）。
    static Count := 3

    ; ═══ 读 ═══

    ; slot 从 1 开始。未配置返回 ""。
    static Get(slot) {
        return ConfigService.Read(this.Section, "Slot" . slot)
    }

    ; 打开到哪个区域（中文标签）。未配置 = 工作区。
    static GetZone(slot) {
        z := ConfigService.Read(this.Section, "Slot" . slot . "Zone")
        if (z = "")
            return "工作区"
        return z
    }

    ; 读出来做「能不能直接开」的判断：空 / 目录不存在都算不可用。
    ; 返回 {ok:true, path} 或 {ok:false, reason:"empty"|"missing", path?}
    static GetUsable(slot) {
        path := this.Get(slot)
        if (path = "")
            return {ok: false, reason: "empty"}
        if !DirExist(path)
            return {ok: false, reason: "missing", path: path}
        return {ok: true, path: path}
    }

    ; ═══ 写 ═══

    static Set(slot, path) {
        return ConfigService.Write(this.Section, "Slot" . slot, this.Normalize(path))
    }

    ; 区域存中文标签；空值归一成「工作区」（与 GetZone 的默认一致）。
    static SetZone(slot, zone) {
        z := Trim("" . zone)
        if (z = "")
            z := "工作区"
        return ConfigService.Write(this.Section, "Slot" . slot . "Zone", z)
    }

    ; 面板保存时一次交回全部槽位。
    ; values 的顺序 = GetSettingsSpec().fields 的声明顺序：
    ;   槽位 1 路径、槽位 1 区域、槽位 2 路径、槽位 2 区域 …
    ; 逐条写、任何一条失败就整体返回 false —— 部分写入比不写更让人困惑
    ; （用户以为改了三项，实际只生效了一项）。
    static SaveAll(values) {
        if !IsObject(values)
            return false
        ok := true
        loop this.Count {
            slot := A_Index
            pi := (slot - 1) * 2 + 1
            zi := pi + 1
            if (pi > values.Length)
                break
            if !this.Set(slot, values[pi])
                ok := false
            if (zi <= values.Length && !this.SetZone(slot, values[zi]))
                ok := false
        }
        return ok
    }

    ; ═══ 纯函数 ═══

    ; 去两端空白与末尾反斜杠；盘根（`D:\`）保留反斜杠。
    ; 与 ExplorerProbe.NormalizePath 同一套规则 —— 存进来的与比对时的写法必须一致，
    ; 否则 `D:\Work\` 和 `D:\Work` 会被当成两个目录。
    static Normalize(path) {
        p := RTrim(Trim(path), "\")
        if RegExMatch(p, "^[A-Za-z]:$")
            p .= "\"
        return p
    }

    ; 热键显示名：槽位 1 → "Alt+1"
    static HotkeyLabel(slot) => "Alt+" . slot
}
