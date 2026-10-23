/* ═══════════════════════════════════════════════════════════════════════
   Markdown 文本的双态处理 —— 纯函数，不认识宿主
   · 存盘态：`./_assets/…`（可移植，Obsidian / Typora / VS Code 都读得到）
   · 显示态：`https://vault.local/…`（页面跑在 app.local，相对路径会 404）
   · 顺带清掉旧笔记里的历史残留（行尾 `\`、`&#x20;`）

   ⚠ **代码不是正文**：围栏代码块、缩进代码块、行内代码里的字节一律不动。
     那里的 `\`、`***`、`&#x20;` 都是内容 —— 改一个字符就是数据事故。
     （2026-10-24 实测：改造前这四处都会被改写，见 web/tests/markdown.test.mjs）
   ═══════════════════════════════════════════════════════════════════════ */

export const VAULT_HOST = 'vault.local'
const VAULT_BASE = `https://${VAULT_HOST}/`

/** 相对路径 → 可显示的 URL；已经带协议的原样返回 */
export function toDisplayUrl(src: string): string {
  if (/^(https?:|data:|blob:)/i.test(src)) return src
  return VAULT_BASE + src.replace(/^\.\//, '').replace(/^\/+/, '')
}

/* ── 代码区判定 ────────────────────────────────────────────────────────
   逐行扫一遍，标出「这一行属于代码块」。两种都要认：
     · 围栏：``` 或 ~~~ 开始，同字符、长度不短于开始那个才算收起；
     · 缩进：行首 4 空格 / 1 个 tab，**且前面是空行**（紧接段落的缩进行是
       续行，不是代码块）。进入之后，缩进行与空行都算代码，遇到第一个
       非缩进非空行才结束。

   ⚠ 只做词法层面的近似，不解析「列表项里的缩进代码」。这类写法本项目
     没有出现过；真遇到也只是「没被认成代码」= 与改造前行为一致。
   ═══════════════════════════════════════════════════════════════════════ */
function codeLineFlags(md: string): boolean[] {
  const lines = md.split('\n')
  const flags: boolean[] = new Array(lines.length).fill(false)
  let fence = ''
  let indented = false

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (fence) {
      flags[i] = true
      const close = /^\s*(`{3,}|~{3,})\s*$/.exec(line)
      if (close && close[1][0] === fence[0] && close[1].length >= fence.length) fence = ''
      continue
    }

    const open = /^\s*(`{3,}|~{3,})/.exec(line)
    if (open) {
      fence = open[1]
      flags[i] = true
      continue
    }

    const isIndented = /^( {4,}|\t)/.test(line)
    if (indented) {
      // 空行在缩进代码里是内容，不结束它
      flags[i] = isIndented || line.trim() === ''
      if (!flags[i]) indented = false
      continue
    }
    if (isIndented && (i === 0 || lines[i - 1].trim() === '')) {
      indented = true
      flags[i] = true
    }
  }
  return flags
}

/* ── 行内代码保护 ──────────────────────────────────────────────────────
   把一行按反引号串切开，只对「代码外」的片段应用 fn。
   反引号按长度配对（`` 里可以写一个 `），未闭合的那个当普通字符处理 ——
   Markdown 里它本来就没有代码语义。

   ⚠ 已知不覆盖：`a \` b` 这种反斜杠转义的反引号。本项目不产生这种写法，
     真出现也只会「少保护一段」，不会破坏内容结构。
   ═══════════════════════════════════════════════════════════════════════ */
function mapOutsideInlineCode(line: string, fn: (s: string) => string): string {
  let out = ''
  let open = ''
  for (const part of line.split(/(`+)/)) {
    if (/^`+$/.test(part)) {
      if (!open) open = part
      else if (part === open) open = ''
      out += part
      continue
    }
    out += open ? part : fn(part)
  }
  return out
}

/* ── 旧格式归一 ────────────────────────────────────────────────────────
   两个残留来自早期版本，用户 2026-10-23 反馈「每行末尾都带一个反斜杠」：

   · 行尾反斜杠：**奇数个**是 Markdown 的硬换行标记（`\` + 换行），
     这类行改写成段落分隔（空行）—— 之前它既不被渲染成换行、也不隐藏，
     于是正文里直接显示成 `\`，保存时又原样写回，越存越多。
     **偶数个**是字面反斜杠（`path\\` 表示 path 后跟一个 `\`），原样留着。
   · `&#x20;` 是行首空格被转义后的样子，还原成空格。

   ⚠ 只对「非代码、非行内代码」的部分生效。
   ═══════════════════════════════════════════════════════════════════════ */
function normalizeLegacyMarkdown(md: string): string {
  const lines = md.split('\n')
  const flags = codeLineFlags(md)
  const out: string[] = []

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (flags[i]) {
      out.push(line)
      continue
    }
    const tail = /\\+$/.exec(line)
    if (tail && tail[0].length % 2 === 1) {
      out.push(line.slice(0, -1).replace(/[ \t]+$/, ''))
      out.push('') // 段落分隔
      continue
    }
    out.push(mapOutsideInlineCode(line, (s) => s.replace(/&#x20;/g, ' ')))
  }
  return out.join('\n')
}

/* ═══════════════════════════════════════════════════════════════════════
   对外两个入口
   ═══════════════════════════════════════════════════════════════════════ */

/**
 * 存盘态 → 显示态。只动 `![alt](src)`，普通链接 `[t](u)` 不碰。
 * ⚠ 不支持 `![a](x.png "标题")` 这种带 title 的写法 —— 本项目不产生它。
 */
export function toDisplayMarkdown(md: string): string {
  return normalizeLegacyMarkdown(md).replace(
    /(!\[[^\]]*\]\()([^)\s]+)(\))/g,
    (_m, head: string, src: string, tail: string) => head + toDisplayUrl(src) + tail,
  )
}

/**
 * 显示态 → 存盘态。落盘的 markdown 必须是这一版。
 *
 * 顺序有讲究：先还原图片路径，再统一分隔线，最后才做旧格式归一与空行压缩
 * —— 反过来会让「归一插入的空行」被当成用户内容压掉。
 */
export function toStoredMarkdown(md: string): string {
  let out = md.replace(
    /(!\[[^\]]*\]\()https:\/\/vault\.local\/([^)\s]+)(\))/g,
    '$1./$2$3',
  )

  // 分隔线统一回旧写法：Milkdown 的 hr 序列化成 `***`，旧版写的是 `---`。
  // 两者都是合法 Markdown，但同一堆笔记里一半一半，在 Obsidian 源码视图里
  // 就是「格式和以前不一样了」。⚠ 只认代码区之外、独占一行的 `***`
  //（行内 `***粗斜体***` 不碰，代码块里的 `***` 更是内容）。
  const dl = out.split('\n')
  const dlFlags = codeLineFlags(out)
  for (let i = 0; i < dl.length; i++) {
    if (!dlFlags[i] && /^[ \t]*\*{3,}[ \t]*$/.test(dl[i])) dl[i] = '---'
  }
  out = dl.join('\n')

  out = normalizeLegacyMarkdown(out)

  // 空段落：Milkdown 把「只有一个硬换行的段落」序列化成独占一行的 `<br />`。
  // Markdown 里段落之间本来就靠空行分隔，空段落没有语义 —— 留着它会让同一篇
  // 笔记里「有的空行是空行、有的是 HTML 换行」。整行删掉，连续空行压成一个。
  // ⚠ 代码区里的空行必须原样保留（缩进代码里的空行也是内容）。
  // ⚠ 行内硬换行（`文字<br />文字`）不在行首行尾，不碰。
  const lines = out.split('\n')
  const flags = codeLineFlags(out)
  const kept: string[] = []
  let blanks = 0
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (flags[i]) {
      kept.push(line)
      blanks = 0
      continue
    }
    if (/^\s*<br\s*\/?>\s*$/i.test(line)) continue
    if (line.trim() === '') {
      blanks += 1
      if (blanks > 1) continue
      kept.push('')
      continue
    }
    blanks = 0
    kept.push(line)
  }
  return kept.join('\n')
}
