#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PromptStoreService —— 提示词仓库管理员（模块：Text）
; ═══════════════════════════════════════════════════════════════════════════
; 存储契约：**目录即分类，文件名即标题，文件全文即正文**。
; 不写 front matter、不用 JSON —— AHK v2.0 没有内置 JSON 对象（见 .clinerules/03）。
;
;   <PromptsDir>\
;   ├─ Chat\                      ← 目录名 = 分类
;   │  └─ 角色设定.md              ← 文件名 = 标题，文件全文 = 正文
;   ├─ Code\
;   │  └─ 代码审查\
;   │     └─ 清单.md              ← 子目录 = 多级分类（Code/代码审查）
;   └─ 随手记.md                  ← 根目录下的文件 = 未分类
;
; ⚠ 分类是**相对路径**，允许多级、不写死：在资源管理器里建目录，或新建提示词时
;   输入 Work/会议 都会自动 DirCreate。首次运行只**播种** Chat / Code / Work 三个
;   顶层目录当起步结构（EnsureRoot），之后完全自由。
; ⚠ 该目录挂在笔记库（Vault）下的 `_prompts\`：NoteStoreService 只扫 Vault **根**
;   的 *.md（不递归），不会把这些文件误当成笔记。
; ⚠ 目录可换：`[Paths] PromptsDir` 非空时用它，否则退回 `<Vault>\_prompts`。

; ⚠ 反斜杠在 AHK 字符串里**不是**转义符（只有反引号是）：代码里的 "\" 就是一个反斜杠。
;   本类路径拼接统一用单反斜杠，必须与 LoadAll() 从文件系统读到的 dirPart 格式一致 ——
;   两边格式不一致会让 Save() 把「只改正文」误判成「改名搬家」而生成 `标题-2.md`。
;   （注意：某些编辑器 / 工具在展示时会把单个反斜杠显示成两个，别照着改。）

class PromptStoreService {
    ; 首次运行播种的三个顶层分类。只用于「没有目录时给个起步结构」，
    ; 不是白名单 —— 之后想建什么分类都行。
    static SeedDirs := ["Chat", "Code", "Work"]

    ; 扫描结果的进程内缓存（数组）。"" = 尚未加载。
    ; ⚠ 文件可能在程序外被改（用户在 VS Code 里编辑），所以 F5 与保存 / 删除后
    ;   都会把它清空强制重扫；平时呼出窗口直接用缓存，不必每次读一遍磁盘。
    static _cache := ""

    ; ─── 路径 ───
    static Lib := "prompts"

    static Root() => (this.Lib = "skills" ? Config.GetSkillsDir() : Config.GetPromptsDir())

    ; ─── 首次运行：建根目录 + 播种三个顶层分类 ───
    ; 在模块 Init() 里调用（只碰磁盘，不碰窗口，符合「Init 只做内部就绪」的约定）。
    static EnsureRoot() {
        root := this.Root()
        try DirCreate(root)
        if (this.Lib != "prompts")
            return
        for name in this.SeedDirs
            try DirCreate(root . "\" . name)
    }

    static SetLib(lib) {
        if (lib != "prompts" && lib != "skills")
            return false
        this.Lib := lib
        this._cache := ""
        this.EnsureRoot()
        return true
    }

    ; ═══ 读取 ═══

    ; 扫描全部提示词。返回数组，每项：
    ;   {title, category, path, summary, text, mtime}
    ;   category 是**相对路径**（`Code\代码审查` 这种，分隔符统一成反斜杠）；
    ;   根目录下的文件 category 为空串。
    ; force = true 时忽略缓存重扫（F5 / 保存后）。
    static LoadAll(force := false) {
        if (!force && IsObject(this._cache))
            return this._cache

        root := this.Root()
        items := []
        if DirExist(root) {
            base := RTrim(root, "\")
            ; R = 递归子目录：多级分类靠它扫出来
            Loop Files, base . "\*.md", "R" {
                rel := SubStr(A_LoopFileFullPath, StrLen(base) + 2)
                fileName := "", dirPart := ""
                SplitPath(rel, &fileName, &dirPart)
                title := RegExReplace(fileName, "\.md$", "")
                ; `_` 开头的文件当作备注 / 草稿，不进列表（与笔记库的约定一致）
                if (title = "" || SubStr(title, 1, 1) = "_")
                    continue

                text := ""
                try text := FileRead(A_LoopFileFullPath, "UTF-8")

                items.Push({
                    title:    title,
                    category: dirPart,
                    path:     A_LoopFileFullPath,
                    summary:  this.Summary(text),
                    text:     text,
                    mtime:    A_LoopFileTimeModified
                })
            }
        }

        items := this._SortByCategoryTitle(items)
        this._cache := items
        return items
    }

    ; 列出所有分类目录（含**空目录**）。新建提示词时的下拉建议用它 ——
    ; 只看 LoadAll() 的话，刚建好还没放文件的分类会「消失」，用户会以为建失败。
    static ListCategories() {
        root := this.Root()
        result := []
        if !DirExist(root)
            return result
        base := RTrim(root, "\")
        Loop Files, base . "\*.*", "D R" {
            result.Push(SubStr(A_LoopFileFullPath, StrLen(base) + 2))
        }
        if (result.Length <= 1)
            return result
        ; 内置 Sort 收的是「行分隔字符串」而不是数组；拼一次排一次，
        ; 避免逐对 StrCompare 的 O(n²)（与 NoteStoreService.ListAllTags 同法）。
        joined := ""
        for i, v in result
            joined .= (i = 1 ? "" : "`n") . v
        out := []
        for v in StrSplit(Sort(joined, "C"), "`n")
            out.Push(v)
        return out
    }

    ; 分类 + 标题双键升序。同样走「拼字符串一次排序」：
    ;   键 = 分类 TAB 标题 TAB 6 位下标（下标保证键唯一、同键时顺序稳定）；
    ;   TAB(0x09) 比任何可打印字符都小，所以「有没有分类」不会把顺序搅乱。
    static _SortByCategoryTitle(items) {
        n := items.Length
        if (n <= 1)
            return items
        byKey := Map()
        keys := []
        for i, it in items {
            k := it.category . "`t" . it.title . "`t" . Format("{:06}", i)
            byKey[k] := it
            keys.Push(k)
        }
        joined := ""
        for i, k in keys
            joined .= (i = 1 ? "" : "`n") . k
        out := []
        for k in StrSplit(Sort(joined, "C"), "`n")
            out.Push(byKey[k])
        return out
    }

    ; ═══ 写入 ═══

    ; 保存一条提示词。oldPath 非空 = 编辑已有条目（标题 / 分类改了就要搬家）。
    ; 返回 {ok:true, path} / {ok:false, reason, error?}
    ; reason: empty-title / mkdir-failed / write-failed
    static Save(category, title, text, oldPath := "") {
        ttl := this.SanitizeName(title)
        if (ttl = "")
            return {ok: false, reason: "empty-title"}

        cat := this.SanitizeCategory(category)
        dir := this.Root() . (cat = "" ? "" : "\" . cat)
        if !DirExist(dir) {
            try DirCreate(dir)
            catch as e
                return {ok: false, reason: "mkdir-failed", error: e.Message}
        }

        path := dir . "\" . ttl . ".md"
        ; 目标已存在（新建同名条目，或改名撞名）时自动追加 -2 / -3，
        ; 不覆盖已有内容 —— 覆盖是不可撤销的。
        ; ⚠ 新建时 oldPath 为空，原条件把它排除掉，正好会静默覆盖同名提示词。
        if (path != oldPath && FileExist(path))
            path := this._UniquePath(dir, ttl)

        try {
            ; UTF-8-RAW = 不写 BOM：md 文件保持干净，与仓库里 .gitattributes 的
            ; 「*.md 用 LF 无 BOM」一致（用户拿这些文件去做 git 备份时不会满屏 diff）。
            f := FileOpen(path, "w", "UTF-8-RAW")
            if !IsObject(f)
                throw Error("无法写入：" . path)
            f.Write(this.NormalizeNewline(text))
            f.Close()
        } catch as e {
            return {ok: false, reason: "write-failed", error: e.Message}
        }

        ; 搬家是「先写新、后删旧」：写失败时原文还在，不会两边都没有。
        if (oldPath != "" && oldPath != path) {
            try FileDelete(oldPath)
        }

        this._cache := ""
        return {ok: true, path: path}
    }

    static Delete(path) {
        if (path = "" || !FileExist(path))
            return {ok: false, reason: "not-found"}
        try FileDelete(path)
        catch as e
            return {ok: false, reason: "delete-failed", error: e.Message}
        this._cache := ""
        return {ok: true}
    }

    ; ═══ 纯函数 ═══

    ; 摘要：把正文压成一行前 maxLen 字，用来做列表的第三列。
    ; 去掉代码块与 markdown 标记，免得列表里全是 ``` 和 **。
    static Summary(text, maxLen := 60) {
        s := this.NormalizeNewline(text)
        ; ⚠ 反引号在 AHK 字符串里是转义符：三连反引号写不出来（实测报 Missing """）。
        ;   用 Chr(96) 拼出 ``` 再交给正则。
        fence := Chr(96) . Chr(96) . Chr(96)
        s := RegExReplace(s, fence . "[\s\S]*?" . fence, " ")   ; 代码块整段丢掉
        s := RegExReplace(s, "(?m)^\s*#{1,6}\s*", " ")    ; 行首标题井号
        s := RegExReplace(s, "[*_``>|~]", " ")           ; 行内 markdown 标记
        s := RegExReplace(s, "\s+", " ")                 ; 换行与连续空白压成一个空格
        s := Trim(s)
        if (s = "")
            s := "(空)"
        ; StrLen / SubStr 按字符算，中文不会被截半
        if (StrLen(s) > maxLen)
            s := SubStr(s, 1, maxLen) . "…"
        return s
    }

    ; 换行归一化成 LF：读进来是 CRLF 还是 LF 都统一，
    ; 这样正文比较、摘要、写回文件三处的行为只有一种。
    static NormalizeNewline(s) {
        s := StrReplace(s, "`r`n", "`n")
        return StrReplace(s, "`r", "`n")
    }

    ; 标题 → 文件名。非法字符换成下划线（Windows 不允许 \/:*?"<>|）。
    static SanitizeName(name) {
        name := Trim(name)
        name := RegExReplace(name, '[\\/:*?"<>|]', "_")
        name := RegExReplace(name, "\s+", " ")
        if (StrLen(name) > 80)
            name := SubStr(name, 1, 80)
        return Trim(name)
    }

    ; 分类 → 相对目录路径。`/` 与 `\` 都认（用户两种都可能输入），
    ; 空段 / `.` / `..` 丢掉 —— 不允许跳出提示词根目录。
    static SanitizeCategory(cat) {
        cat := Trim(cat)
        cat := StrReplace(cat, "/", "\")
        out := []
        for p in StrSplit(cat, "\") {
            p := Trim(p)
            if (p = "" || p = "." || p = "..")
                continue
            p := Trim(RegExReplace(p, '[\\/:*?"<>|]', "_"))
            if (p != "")
                out.Push(p)
        }
        s := ""
        for i, p in out
            s .= (i = 1 ? "" : "\") . p
        return s
    }

    ; 同目录下找一个不冲突的文件名：标题-2.md / 标题-3.md / …
    static _UniquePath(dir, title) {
        loop 99 {
            p := dir . "\" . title . "-" . (A_Index + 1) . ".md"
            if !FileExist(p)
                return p
        }
        return dir . "\" . title . "-" . A_TickCount . ".md"
    }

}

