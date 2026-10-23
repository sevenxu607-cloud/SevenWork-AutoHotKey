#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ExplorerProbe —— 资源管理器窗口查询（平台能力层）
; ═══════════════════════════════════════════════════════════════════════════
; 只回答「这个文件夹有没有已经打开的窗口 / 现在开着哪些」：
;   · 不读 Config / State，不发事件，不搬窗口，不写日志；
;   · 返回 hwnd（整数）或数组，失败就返回 0 / 空数组 —— 由调用方决定怎么回退。
;
; ⚠ 为什么不用窗口标题：资源管理器的标题是**文件夹名**（`Documents`、`本地磁盘 (C:)`），
;   重名与本地化都靠不住，同一个目录在两个盘上同名就没法分辨。
;   这里走 `Shell.Application.Windows` 读 `Document.Folder.Self.Path` —— 真实路径，
;   与标题无关。
;
; 实测（AHK v2.0.27 / Win11 26200，2026-10-20 探针）：
;   · `for w in shell.Windows` 可直接遍历，`Windows` 的 Type 是 `ShellWindows`；
;   · `w.HWND` 与 `w.Document.Folder.Self.Path` 均可读（本例 hwnd=263866
;     path=`D:\00-SevenFiles\Documents`）；
;   · `wins.Count` / `wins.Item(i)` 同样可用（本类用前者之外的遍历方式，只为少一个索引）。
; ⚠ 能力层契约见 .clinerules/02-architecture.md：本文件不出现 Config. / State. / EventBus. / LogError( 的调用。
; ⚠ 反斜杠在 AHK 字符串里不是转义符（只有反引号是）：下面写的 "\" 就是一个反斜杠。

class ExplorerProbe {
    ; 外壳窗口的类名。只用于「先圈定候选、再问 COM 要路径」这类交叉校验，
    ; 单靠它没法判断是哪个目录 —— 类名对所有资源管理器窗口都一样。
    static WindowClass := "CabinetWClass"

    ; 列出当前所有资源管理器窗口：数组，每项 {hwnd, path}。
    ; path 为 "" 的会被丢掉 —— 「此电脑」/「快速访问」/ 桌面这类壳窗口没有文件夹路径，
    ; 读 `Document.Folder` 会抛错或返回空，try 一挡就跳过。
    static ListWindows() {
        out := []
        try shell := ComObject("Shell.Application")
        catch
            return out
        try wins := shell.Windows
        catch
            return out

        try {
            for w in wins {
                hwnd := 0, path := ""
                try hwnd := w.HWND
                try path := w.Document.Folder.Self.Path
                if (hwnd && path != "")
                    out.Push({hwnd: hwnd, path: path})
            }
        } catch {
            ; 遍历中途出错（某个项是 IE 窗口 / 已关闭的残项）：
            ; 已经收上来的照常返回，调用方自己判断够不够用。
        }
        return out
    }

    ; 找某个文件夹已经打开的窗口；没有就返回 0。
    ; 同一路径开着多个窗口时取第一个 —— 显隐语义下多窗口是用户自己开的，
    ; 这里只负责「能找到就行」，不再替用户合并。
    static FindFor(path) {
        if (path = "")
            return 0
        for item in this.ListWindows() {
            if this.SamePath(item.path, path)
                return item.hwnd
        }
        return 0
    }

    ; 列出某个资源管理器窗口里**当前选中**的项：数组，每项是绝对路径。
    ; 文件与文件夹都会返回（`item.Path` 对两者都适用），是否该换目录由调用方判断 ——
    ; 本能力只负责「问 shell 要真相」，不做存在性与类型校验。
    ;
    ; ⚠ 选中项走 `Document.SelectedItems`（`FolderItems` 集合，可直接 for-in）。
    ;   壳窗口（此电脑 / 快速访问）的 `Document` 是 Null —— 实测 `Name=Windows`、
    ;   `LocationURL` 为空、`Document` 取出来是 Null —— 这时 for-in 会抛错，外层 try 兜住。
    ; ⚠ hwnd 统一转整数再比：调用方可能从 WinActive / 字符串配置里拿到 "0x12345"。
    static SelectedPaths(hwnd) {
        out := []
        if !hwnd
            return out
        try target := Integer(hwnd)
        catch
            return out

        try shell := ComObject("Shell.Application")
        catch
            return out
        try wins := shell.Windows
        catch
            return out

        try {
            for w in wins {
                h := 0
                try h := w.HWND
                if (!h || h != target)
                    continue
                try {
                    for item in w.Document.SelectedItems
                        out.Push(item.Path)
                }
                break
            }
        } catch {
            ; 读到一半出错（壳窗口 / 视图正在切换）：已收上来的照常返回
        }
        return out
    }

    ; 这个 hwnd 现在是不是还对应某个资源管理器窗口（COM 侧确认，防残项）。
    static IsExplorerWindow(hwnd) {
        if !hwnd
            return false
        for item in this.ListWindows() {
            if (item.hwnd = hwnd)
                return true
        }
        return false
    }

    ; 两段路径是否指同一个文件夹。
    ; 归一化：去两端空白与末尾反斜杠（盘根 `D:\` 保留一个）、统一大小写 ——
    ; Windows 路径不区分大小写。
    static SamePath(a, b) {
        if (a = "" || b = "")
            return false
        return StrLower(this.NormalizePath(a)) = StrLower(this.NormalizePath(b))
    }

    ; 路径归一化（纯字符串，不碰磁盘）。
    static NormalizePath(path) {
        p := RTrim(Trim(path), "\")
        ; `D:` / `C:` 去掉反斜杠后与「该盘的当前目录」含义相同，容易误判，
        ; 补回反斜杠明确表示盘根。
        if RegExMatch(p, "^[A-Za-z]:$")
            p .= "\"
        return p
    }
}
