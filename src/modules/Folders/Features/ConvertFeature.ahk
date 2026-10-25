#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ConvertFeature —— Alt+M：把资源管理器里选中的文件转成 Markdown
; ═══════════════════════════════════════════════════════════════════════════
; 触发条件在 FoldersModule.GetContexts() 的 explorer 上下文里（资源管理器前台才响应）。
; 本类只做三件事：取当前窗口 → 问 shell 要选中项 → 汇总结果并提示。
;   · 转换策略（输出路径 / 跳过规则 / 批量编排）在 FileConvertService；
;   · pandoc 怎么调在能力层 PandocRunner；
;   · 这里只有「编排 + 展示」。
;
; ⚠ 反馈一律 ToolTip，不弹模态框：模态框会挡住热键、只能手动关
;   （见 .clinerules/03 的「未捕获异常默认弹模态框」）。
; ⚠ 同名 .md 已存在时**跳过不覆盖**，理由见 FileConvertService 头注释。
; ⚠ 与 FolderWindowFeature 是同模块内的兄弟 Feature，直接调它的 Tip 是有先例的写法
;   （Text 模块的 PromptEditFeature → PromptWindowFeature 同理）；跨模块则只能走 EventBus。

class ConvertFeature {
    ; 结果提示停留时长（ms）。比 FolderWindowFeature 默认的 1800 长一些 ——
    ; 批量结果要读得完，而 ToolTip 不会挡住任何操作。
    static TipMs := 3000

    ; ═══ 主入口（热键直接指过来）═══

    static Run() {
        hwnd := WinExist("A")
        if !hwnd {
            this._Tip("没有找到当前窗口")
            return
        }

        paths := ExplorerProbe.SelectedPaths(hwnd)
        if (paths.Length = 0) {
            ; 桌面也能按到这个热键了（见 FoldersModule.GetContexts），但桌面不是
            ; Shell.Application 的窗口，选中项读不出来 —— 说清楚该去哪操作。
            cls := WinGetClass("ahk_id " . hwnd)
            if (cls = "Progman" || cls = "WorkerW") {
                this._Tip("桌面上的选中项读不到`n请在资源管理器窗口里选中文件再按 Alt+M", 5000)
            } else {
                this._Tip("请先在资源管理器里选中要转换的文件`n（Alt+M 只在资源管理器 / 桌面生效）"
                    , 5000)
            }
            LogError("Alt+M：没有读到选中项（前台类名 " . cls . "）")
            return
        }

        ; ⚠ 转换是**同步**的（PandocRunner 用 RunWait），几十 MB 的课件要跑好几秒，
        ;   期间主线程不响应任何热键。不先给一句提示的话，用户会以为程序卡死；
        ;   再按一次 Alt+M 只会把第二次请求排到这次后面，更像「转换坏了」。
        ;   转换结束那一行由 _Tip 覆盖掉（它自己带清除定时器）。
        try ToolTip(paths.Length = 1 ? "正在转换…" : "正在转换 " . paths.Length . " 个文件…")

        r := FileConvertService.ConvertMany(paths)

        ; 失败原因进日志：ToolTip 只放一句结论，退出码与细节都落到 _error.log。
        for item in r.failed {
            detail := item.HasProp("detail") ? item.detail : ""
            why := item.reason
            if (item.HasProp("code") && item.code)
                why .= "（退出码 " . item.code . "）"
            if (detail != "")
                why .= " | " . detail
            LogError("转换失败：" . item.path . " —— " . why)
        }

        ; 警告进日志：ToolTip 只放一句结论
        for item in r.warnings
            LogError("转换警告：" . item.path . " —— " . item.msg)

        this._Tip(this._Summarize(r))
    }

    ; ═══ 结果汇总 ═══

    ; 一句话结论。单个文件时给**具体原因**（「已存在同名 .md」比「跳过 1 个」有用得多）；
    ; 多个文件时只说数量 —— ToolTip 太长会糊住半个屏幕。
    static _Summarize(r) {
        total := r.done.Length + r.skipped.Length + r.failed.Length

        if (total = 1) {
            if r.done.Length {
                msg := "已转换：" . this._Name(r.done[1])
                ; 「没能完全还原」不能在这一支里丢掉 —— 单个文件时用户只看到这一句，
                ; 吞掉警告等于告诉他「完全正常」
                if r.warnings.Length
                    msg .= "`n有 " . r.warnings.Length . " 处未能完全还原（详见 _error.log）"
                return msg
            }
            if r.skipped.Length
                return this._SkipText(r.skipped[1].reason)
            if r.failed.Length
                return "转换失败：" . this._FailText(r.failed[1].reason)
        }

        parts := []
        if r.done.Length
            parts.Push("已转换 " . r.done.Length . " 个")
        if r.skipped.Length
            parts.Push("跳过 " . r.skipped.Length . " 个")
        if r.failed.Length
            parts.Push("失败 " . r.failed.Length . " 个")

        msg := this._Join(parts, " · ")
        if r.warnings.Length
            msg .= "`n有 " . r.warnings.Length . " 处未能完全还原（详见 _error.log）"
        if r.failed.Length
            msg .= "`n失败详情见 %AppData%\SevenWork\_error.log"
        return msg
    }

    ; 跳过原因 → 人话
    static _SkipText(reason) {
        if (reason = "is-folder")
            return "选中的是文件夹，跳过（本功能只转文件）"
        if (reason = "is-markdown")
            return "已经是 Markdown，不用转"
        if (reason = "unsupported")
            return "pandoc 读不了 pdf / doc`n请先另存为 .docx 再转"
        if (reason = "exists")
            return "已存在同名 .md，跳过（不覆盖）`n要重转请先删掉旧的"
        if (reason = "no-extension")
            return "文件没有扩展名，pandoc 认不出格式"
        if (reason = "pandoc-missing")
            return "未检测到 Pandoc，文档转换是可选功能`n安装 Pandoc 后重试；核心笔记功能不受影响"
        return "跳过：文件不可用"
    }

    ; 失败原因 → 人话
    static _FailText(reason) {
        if (reason = "pandoc-exit")
            return "pandoc 报错"
        if (reason = "no-output")
            return "pandoc 说成功但没写出文件"
        if (reason = "src-missing")
            return "源文件不见了"
        if (reason = "run-failed")
            return "启动 pandoc 失败"
        if (reason = "no-cmd")
            return "找不到 pandoc"
        return reason
    }

    ; ═══ 小工具 ═══

    ; 文件名（含扩展名）—— SplitPath 的第一个输出参数才是它，第二个是目录。
    static _Name(path) {
        SplitPath(path, &fileName)
        return fileName
    }

    ; AHK 没有内置 join，数组拼串统一走这里
    static _Join(arr, sep) {
        out := ""
        for i, v in arr
            out .= (i > 1) ? sep . v : v
        return out
    }

    static _Tip(msg, ms := 0) {
        FolderWindowFeature.Tip(msg, ms ? ms : this.TipMs)
    }
}
