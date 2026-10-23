#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PandocRunner —— 用 pandoc 把一个文件转成另一个格式（平台能力层 · 文档）
; ═══════════════════════════════════════════════════════════════════════════
; 只回答两件事：「这台机器上的 pandoc 在哪」和「这个文件转不转得成」：
;   · 不读 Config / State，不发事件，不写日志 —— pandoc 路径由调用方传入；
;   · 失败返回 {ok:false, reason, code?}，由调用方决定回退与记录。
;
; ⚠ 为什么不传 -f（输入格式）：pandoc 3.11 的 --list-input-formats 里有 docx / odt /
;   rtf / epub / html / latex / rst / org / csv / ipynb / pptx / xlsx 等 50 余种，且随版本
;   增长。写死 -f 就得跟着版本维护一张表，还会把「它其实认得」的新格式挡在外面。
;   不传 -f，pandoc 自己按扩展名推断：认得就转，认不得的直接以非 0 退出（退出码带回去）。
;
; ⚠ **不经 `cmd /c`**：pandoc 由 `RunWait` 直接拉起。实测（2026-10-21，AHK v2.0.27 +
;   pandoc 3.11）三种写法，只有直接运行能成：
;     · `cmd /c ""<exe>" <args>"`      → 退出码 1，目标文件没生成
;     · `cmd /s /c ""<exe>" <args>"`   → 退出码 1，同上
;     · `"<exe>" <args>` 直接 RunWait   → 退出码 0，正常出 md
;   代价：拿不到 pandoc 的 stderr 原文（重定向只有 shell 支持）。失败时只给退出码，
;   调用方记 reason + code；真要原文得手工跑一次。
;   ⚠ 别为了「顺手加个 2>err.txt」把整串塞回 `cmd /c` —— 上面两条就是这么坏的。
;
; ⚠ 与 modules/SevenNote/Services/PandocService.ahk 是两份实现，不是漏改：
;   那份是笔记保存链路专用（RTF 输入 + 图片搬到 _assets + 可用性缓存 + 后处理），
;   改它要动「每次 Alt+Z 都跑」的路径，风险与收益不成比例。本类只做通用单文件转换。
;
; ⚠ 能力层契约见 .clinerules/02-architecture.md：本文件不出现 Config. / State. / EventBus. / LogError( 的调用。
; ⚠ 反斜杠在 AHK 字符串里不是转义符（只有反引号是）。

class PandocRunner {
    ; 打包版 pandoc 约 150~230MB；小于 1MB 基本是 FileInstall 失败留下的 0KB / 半截文件。
    ; 判据与 PandocService._IsValidPandoc 一致 —— 两边都踩过「0KB 坏 pandoc 挡住好 pandoc」。
    static MinExeSize := 1048576

    ; ═══ 定位 ═══

    ; 返回可直接拼进命令行的 pandoc：带引号的绝对路径，或退化成 PATH 里的 "pandoc.exe"。
    ; preferredPath 一般传 Config.PandocPath —— 但本类不读它，由调用方给。
    static ResolveCmd(preferredPath) {
        if this.IsUsableExe(preferredPath)
            return '"' . preferredPath . '"'
        return "pandoc.exe"
    }

    static IsUsableExe(path) {
        if (path = "")
            return false
        if !FileExist(path)
            return false
        try return FileGetSize(path) >= this.MinExeSize
        catch
            return false
    }

    ; ═══ 转换 ═══

    ; 转一个文件 → {ok:true, size} / {ok:false, reason, code?}
    ;   cmd         ResolveCmd() 的返回值
    ;   src         源文件绝对路径
    ;   dst         目标文件绝对路径
    ;   mediaDir    图片抽取目录；传 "" 表示不抽图
    ;
    ; reason 取值：no-cmd / bad-arg / src-missing / run-failed / pandoc-exit / no-output
    static Convert(cmd, src, dst, mediaDir := "") {
        if (cmd = "")
            return {ok: false, reason: "no-cmd"}
        if (src = "" || dst = "")
            return {ok: false, reason: "bad-arg"}
        if !FileExist(src)
            return {ok: false, reason: "src-missing", detail: src}

        ; ⚠ `--markdown-headings=atx` 不能省：pandoc 的 markdown writer 默认 **setext**，
        ;   H1/H2 会写成 `标题` 下面跟一行 `====` / `----`。多数编辑器的**大纲面板只认 ATX**
        ;   （`#` 开头），setext 标题在它们眼里就是普通段落 —— 实测用户截图里大纲列的全是正文。
        ;   三级及以下本来就是 ATX，所以只有文档真有 H1/H2 时这个差别才显形。
        ; ⚠ 表格必须显式锁成 **pipe table**（GFM / Obsidian / Milkdown 只认这一种）。
        ;   实测（pandoc 3.8，2026-10-23）：不指定 -t 时，pandoc 的 markdown writer
        ;   会按内容挑 grid / multiline / simple 三种表格 —— 本项目的笔记编辑器对它们
        ;   全都不渲染，整张表变成一串纯文本。这就是「表格转换异常」的根因。
        ;   `-grid_tables-multiline_tables-simple_tables` 只禁用这三种语法，保留
        ;   pipe_tables（markdown 扩展默认开启），其他元素的行为不变。
        ; ⚠ 合并单元格在 GFM 里无法表达，pandoc 会退回 <table> HTML —— 内容不丢，
        ;   但编辑器多半不渲染。调用方据此给警告（FileConvertService._HasHtmlTable）。
        args := '--wrap=none --markdown-headings=atx'
            . ' -t markdown-grid_tables-multiline_tables-simple_tables'
        if (mediaDir != "")
            args .= ' --extract-media="' . mediaDir . '"'
        args .= ' "' . src . '" -o "' . dst . '"'

        try code := RunWait(cmd . " " . args, , "Hide")
        catch as e
            return {ok: false, reason: "run-failed", detail: e.Message}

        if (code != 0) {
            ; pandoc 可能已经建出一个 0 字节目标文件。留着它会让下次判断成
            ; 「已存在同名 .md，跳过」，用户按多少次都出不来东西 —— 而 Plan 已保证
            ; dst 原本不存在，所以此刻它一定是本次的产物，删掉是安全的。
            if FileExist(dst) {
                try FileDelete(dst)
            }
            return {ok: false, reason: "pandoc-exit", code: code}
        }

        ; pandoc 偶尔会「退出码 0 但没写出文件」（目标目录被占 / 磁盘满）。
        ; 不校验就会给用户报「已转换 1 个」而磁盘上什么都没有。
        if !FileExist(dst)
            return {ok: false, reason: "no-output", code: 0}

        return {ok: true, size: FileGetSize(dst)}
    }
}
