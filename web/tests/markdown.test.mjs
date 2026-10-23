/* ═══════════════════════════════════════════════════════════════════════
   web/src/markdown.ts 的纯逻辑回归

   跑法：  node --test web/tests
   （tools\run-tests.ps1 会自动带上这一步）

   为什么要测它：这几个函数在**每次保存**时都会跑一遍，而且改的是用户
   自己的笔记正文。它们安静地改错一个字符，界面上完全看不出来 —— 直到
   用户在 Obsidian 里打开才发现代码块变了。
   ═══════════════════════════════════════════════════════════════════════ */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import Module from 'node:module'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require('typescript')
const webRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const srcPath = path.join(webRoot, 'src', 'markdown.ts')

/** 把 markdown.ts 就地转译成 CJS 再加载 —— 只为跑测试，不产出文件 */
function loadMarkdown() {
  const js = ts.transpileModule(readFileSync(srcPath, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    fileName: srcPath,
  }).outputText
  const m = new Module(srcPath)
  m.filename = srcPath
  m._compile(js, srcPath)
  return m.exports
}

const { toDisplayMarkdown, toDisplayUrl, toStoredMarkdown } = loadMarkdown()

const FENCE = '`'.repeat(3)
const BS = '\\'
const assertSame = (actual, expected, what) =>
  assert.equal(actual, expected, `${what}\n  expected=[${expected}]\n  actual  =[${actual}]`)

/* ── 图片路径双态 ───────────────────────────────────────────────────── */
test('存盘态图片路径 → 显示态带 vault.local 前缀', () => {
  assertSame(
    toDisplayMarkdown('![a](./_assets/2026-10-24/x.png)'),
    '![a](https://vault.local/_assets/2026-10-24/x.png)',
    '相对路径要换成可加载的 URL',
  )
})

test('显示态图片路径 → 落盘还原成 ./', () => {
  assertSame(
    toStoredMarkdown('![a](https://vault.local/_assets/2026-10-24/x.png)'),
    '![a](./_assets/2026-10-24/x.png)',
    '落盘必须是可移植的相对路径',
  )
})

test('普通链接不参与图片路径改写', () => {
  assertSame(toDisplayMarkdown('[doc](./notes/a.md)'), '[doc](./notes/a.md)', '只动 ![..](..)')
})

test('已带协议的图片路径原样返回', () => {
  assertSame(toDisplayUrl('https://x.test/a.png'), 'https://x.test/a.png', 'http 不重复加前缀')
  assertSame(toDisplayUrl('data:image/png;base64,AA'), 'data:image/png;base64,AA', 'data: 同理')
})

/* ── 代码区：一个字节都不许改 ───────────────────────────────────────── */
test('围栏代码块里的 *** 不被改成分隔线', () => {
  const input = `${FENCE}text\n***\n${FENCE}`
  assertSame(toStoredMarkdown(input), input, '代码里的 *** 是内容')
})

test('围栏代码块里的行尾反斜杠不被删', () => {
  const input = `${FENCE}\nline${BS}\n${FENCE}`
  assertSame(toStoredMarkdown(input), input, '代码里的 \\ 是内容')
})

test('围栏代码块里的 HTML 实体不被还原', () => {
  const input = `${FENCE}\n&#x20;\n${FENCE}`
  assertSame(toStoredMarkdown(input), input, '代码里的实体是内容')
})

test('缩进代码块里的行尾反斜杠不被删', () => {
  const input = `    first${BS}\n    second`
  assertSame(toStoredMarkdown(input), input, '缩进代码也要认出来')
})

test('行内代码里的实体与反斜杠不被改写', () => {
  assertSame(toStoredMarkdown(`${FENCE.slice(0, 1)}&#x20;${FENCE.slice(0, 1)}`), '`&#x20;`', '行内代码是内容')
})

test('代码块里的空行原样保留', () => {
  const input = `${FENCE}\na\n\n\nb\n${FENCE}`
  assertSame(toStoredMarkdown(input), input, '代码里的空行是内容')
})

/* ── 旧格式：用户实际反馈过的那两类残留 ─────────────────────────────── */
test('正文行尾单个反斜杠 → 段落分隔（不再把 \\ 写回文件）', () => {
  assertSame(toStoredMarkdown(`first${BS}\nsecond`), 'first\n\nsecond', '奇数个 = 硬换行标记')
})

test('正文行尾偶数个反斜杠原样保留（字面反斜杠）', () => {
  assertSame(toStoredMarkdown(`path${BS}${BS}`), `path${BS}${BS}`, '偶数个 = 一个字面 \\')
})

test('正文里的 &#x20; 还原成空格', () => {
  assertSame(toStoredMarkdown('&#x20;line3'), ' line3', '行首空格被转义过')
})

test('独占一行的 <br /> 被删掉，连续空行压成一个', () => {
  assertSame(toStoredMarkdown('a\n<br />\nb\n\n\nc'), 'a\nb\n\nc', '空段落没有语义')
})

test('行内 <br /> 不删（它两侧都有文字）', () => {
  assertSame(toStoredMarkdown('x<br />y'), 'x<br />y', '行内硬换行是正文的一部分')
})

/* ── 兜底 ───────────────────────────────────────────────────────────── */
test('空文档往返仍是空文档', () => {
  assertSame(toStoredMarkdown(''), '', '不凭空造内容')
})

test('普通正文经显示 → 落盘一轮后不变形', () => {
  const input = '# 标题\n\n正文一段。\n\n- 列表项\n\n---\n\n![图](./_assets/a.png)'
  assertSame(toStoredMarkdown(toDisplayMarkdown(input)), input, '往返必须一字不差')
})
