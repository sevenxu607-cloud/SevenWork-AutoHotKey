#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  AppSlotService —— 应用槽位（模块：Launcher）
; ═══════════════════════════════════════════════════════════════════════════
; 设计要点与文件槽位完全对称：**热键写死、目标可换**。
;   Alt+Shift+1/2/3 固定三个槽位，背后绑哪条命令行、落到哪个区域写在 _config.ini。
;
;   [Apps]
;   Slot1=notepad.exe
;   Slot1Zone=工作区
;   Slot2="C:\Program Files\App\app.exe" --arg
;   Slot2Zone=辅助区
;   Slot3=
;   Slot3Zone=辅助区
;
; ⚠ 槽位里是**完整命令行**：第一段必须是 exe（含 .exe 扩展名），认窗靠
;   CommandLine.ExeOf 取它。不支持 `cmd /c start ...` 这类启动器套启动器。
; ⚠ 区域只存中文标签；几何由平台 ZoneService 负责，本服务不做窗口操作。
; ⚠ 与 Alt+C / Alt+X 的关系：那两条是 PowerShell / DeepSeek 的固定快捷键，
;   不听本配置；槽位用于「其他程序」。

class AppSlotService {
    static Section := "Apps"

    ; 槽位数量。加槽位要同步两处：
    ;   ① 这里；② LauncherModule.GetHotkeys() 里补一条 Alt+Shift+N。
    static Count := 3

    ; ═══ 读 ═══
    static Get(slot) {
        return ConfigService.Read(this.Section, "Slot" . slot)
    }

    ; 未配置 = 辅助区（应用槽位最常见的去处）。
    static GetZone(slot) {
        z := ConfigService.Read(this.Section, "Slot" . slot . "Zone")
        if (z = "")
            return "辅助区"
        return z
    }

    ; ═══ 写 ═══
    static Set(slot, cmd) {
        return ConfigService.Write(this.Section, "Slot" . slot, Trim("" . cmd))
    }

    static SetZone(slot, zone) {
        z := Trim("" . zone)
        if (z = "")
            z := "辅助区"
        return ConfigService.Write(this.Section, "Slot" . slot . "Zone", z)
    }

    ; 面板保存：顺序 = 命令、区域、命令、区域……
    static SaveAll(values) {
        if !IsObject(values)
            return false
        ok := true
        loop this.Count {
            slot := A_Index
            ci := (slot - 1) * 2 + 1
            zi := ci + 1
            if (ci > values.Length)
                break
            if !this.Set(slot, values[ci])
                ok := false
            if (zi <= values.Length && !this.SetZone(slot, values[zi]))
                ok := false
        }
        return ok
    }

    ; ═══ 纯函数 ═══
    static HotkeyLabel(slot) => "Alt+Shift+" . slot

    ; 命令行 → exe 文件名（含扩展名）；解析规则见 CommandLine。
    static ExeOf(cmd) => CommandLine.ExeOf(cmd)
}
