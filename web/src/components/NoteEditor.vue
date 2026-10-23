<script setup lang="ts">
/* ═══════════════════════════════════════════════════════════════════════
   Milkdown 编辑器封装
   · 只做「Markdown 进、Markdown 出」，不认识笔记存储、不认识 AHK 文件名
   · 图片粘贴 / 拖入由 upload 插件接管，uploader 里换成自己的落盘逻辑
   ═══════════════════════════════════════════════════════════════════════ */
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { Editor, rootCtx, defaultValueCtx, editorViewCtx } from '@milkdown/kit/core'
import { commonmark } from '@milkdown/kit/preset/commonmark'
import { gfm } from '@milkdown/kit/preset/gfm'
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener'
import { history } from '@milkdown/kit/plugin/history'
import { upload, uploadConfig } from '@milkdown/kit/plugin/upload'
import { dropCursor } from '@milkdown/kit/prose/dropcursor'
import { gapCursor } from '@milkdown/kit/prose/gapcursor'
import { getMarkdown, replaceAll, $prose } from '@milkdown/kit/utils'
import { sinkListItem, liftListItem } from '@milkdown/kit/prose/schema-list'
import { TextSelection } from '@milkdown/kit/prose/state'
import { storeImage, toDisplayMarkdown, toDisplayUrl, toStoredMarkdown } from '../ahk'
import '@milkdown/kit/prose/gapcursor/style/gapcursor.css'

const props = defineProps<{ modelValue?: string }>()
const emit = defineEmits<{
  (e: 'update:modelValue', v: string): void
  (e: 'ready'): void
}>()

const host = ref<HTMLDivElement>()
let editor: Editor | null = null
let disposed = false
// 上一次 emit 出去的「存储态」markdown。拿它做比较而不是 listener 给的 prev ——
// prev 是显示态（图片 src 带 vault.local 前缀），跟存储态永远不相等，
// 那样每次敲键都会 emit 一遍，App.vue 的存盘也跟着白跑。
let lastStored = props.modelValue ?? ''

onMounted(async () => {
  const mark = (s: string) => { ;(window as any).__noteStage = s }
  mark('mount')
  if (!host.value) return
  const el = host.value
  mark('make')
  const builder = Editor.make()
    .config((ctx) => {
      ctx.set(rootCtx, el)
      // 进来的 markdown 是存储态（./_assets/…），渲染前换成可加载的 URL
      ctx.set(defaultValueCtx, toDisplayMarkdown(props.modelValue ?? ''))

      // 内容变化回吐 markdown（Milkdown 内部有节流，不用自己 debounce）
      ctx.get(listenerCtx).markdownUpdated((_, md) => {
        const stored = toStoredMarkdown(md)
        if (stored === lastStored) return
        lastStored = stored
        emit('update:modelValue', stored)
      })

      // 图片粘贴 / 拖入：不交给默认 uploader（它只会转 base64 内联），
      // 换成我们的 storeImage —— WebView2 里落盘成文件，浏览器里才内联。
      ctx.update(uploadConfig.key, (prev) => ({
        ...prev,
        uploader: async (files, schema) => {
          const nodes = []
          for (const f of Array.from(files)) {
            if (!f.type.startsWith('image/')) continue
            // AHK 回的是 ./_assets/…（可移植），节点 src 得是能加载的 URL
            const rel = await storeImage(f)
            // ⚠ 落盘失败时 AHK 返回空串（见 NoteHostSaveImage）。
            //   从前这里照插不误：节点 src 变成空，页面上是一个永远加载不出来的破图，
            //   存进 .md 就是 `![]()` —— 图没存上，正文还被污染了。宁可不插。
            if (!rel) continue
            const src = toDisplayUrl(rel)
            nodes.push(schema.nodes.image.create({ src, alt: f.name || 'image' }))
          }
          return nodes
        },
      }))
    })
    .use(commonmark)
    .use(gfm)
    .use(listener)
    .use(history)
    .use($prose(() => dropCursor()))
    .use($prose(() => gapCursor()))
    .use(upload)
  mark('built')
  let created: any
  try {
    created = await Promise.race([
      builder.create(),
      new Promise<never>((_, rej) => setTimeout(() => rej(new Error('create timeout 10s')), 10000)),
    ])
  } catch (e: any) {
    mark('create-fail: ' + String(e) + ' @@ ' + String(e?.stack).slice(0, 500))
    throw e
  }
  mark('created')

  // 卸载与创建赛跑：组件可能在 await 期间就被销毁了
  if (disposed) {
    created.destroy()
    return
  }
  editor = created
  mark('ready')
  emit('ready')
})

onBeforeUnmount(() => {
  disposed = true
  editor?.destroy()
  editor = null
})

/**
 * 派发一次「插入块」事务，并把光标放到 caret（越界就不动选区）。
 * 抽出来是因为分隔线、标题、段落三条路都要做同一件事：
 * 没有光标的块插完，用户下一次按快捷键还会落在原地。
 */
function dispatchAt(view: any, tr: any, caret: number): string {
  if (caret >= 0 && caret <= tr.doc.content.size) {
    try {
      tr = tr.setSelection(TextSelection.create(tr.doc, caret))
    } catch {
      // 位置落在叶子块内部（如 hr）—— 不设选区，保持原光标即可
    }
  }
  view.dispatch(tr.scrollIntoView())
  return 'ok'
}

defineExpose({
  /**
   * 在光标处插入一段文本（时间戳 / 分隔线 / 缩进都走它）。
   *
   * ⚠ 必须走 ProseMirror 的 transaction：直接改 DOM 会被下一次状态同步抹掉，
   *   而且不进历史栈 —— Ctrl+Z 撤不回来。
   */
  insertText(text: string): string {
    if (!editor) return 'no-editor'
    try {
      const view = editor.ctx.get(editorViewCtx)
      view.dispatch(view.state.tr.replaceSelectionWith(view.state.schema.text(text)).scrollIntoView())
      return 'ok'
    } catch (e) {
      return 'ERR ' + String(e)
    }
  },

  getMarkdown(): string {
    if (!editor) return props.modelValue ?? ''
    // 出编辑器就转回存储态 —— 这才是能写进 .md 的那一版
    return toStoredMarkdown(editor.action(getMarkdown()) as unknown as string)
  },

  /**
   * 正文可见字符数（**不含 Markdown 标记**）。
   *
   * ⚠ 不能用 `props.modelValue.length`：那是存储态 Markdown，`# `、`**`、链接 URL
   *   全都算进去 —— 显示出来会比眼里看到的正文多一截。旧版 RichEdit 的字数就是
   *   纯文本长度（EM_GETTEXTLENGTHEX），这里对齐那个口径。
   * ⚠ 用 `textBetween` 而不是 `doc.textContent`：后者把相邻块直接拼起来，
   *   跨段落的字数会偏少；这里用 `\n` 补回块间分隔（只取长度，不影响内容）。
   */
  getTextLength(): number {
    if (!editor) return 0
    try {
      const view = editor.ctx.get(editorViewCtx)
      const doc = view.state.doc
      return doc.textBetween(0, doc.content.size, '\n', '\n').length
    } catch {
      return 0
    }
  },

  /**
   * 增加一级缩进：列表项内真的下沉一层（Markdown 嵌套列表）。
   *
   * ⚠ **普通段落里什么都不做**，这是有意的：
   *   Markdown 里行首四个空格是「代码块」，不是缩进。原来插四空格的结果是
   *   Milkdown 为保真把首空格序列化成 `&#x20;` —— 存进 .md 就是一堆 HTML 实体，
   *   旧笔记里从来没有这种东西。而在 Obsidian 里打开，四个空格又变成代码块。
   *   缩进在 Markdown 里只对列表有意义，所以只对列表生效。
   */
  indent(): string {
    if (!editor) return 'no-editor'
    try {
      const view = editor.ctx.get(editorViewCtx)
      const { state } = view
      if (sinkListItem(state.schema.nodes.list_item)(state, view.dispatch)) return 'ok'
      return 'no-op'
    } catch (e) {
      return 'ERR ' + String(e)
    }
  },

  /**
   * 减少一级缩进：列表项提层；普通段落删掉用户手打的行首空格（最多四个）。
   *
   * ⚠ 这里保留删空格 —— 那是**用户自己敲进去的**字符，属于内容，该能删。
   *   （indent 不往里加，是为了不凭空制造 Markdown 里的非法缩进。）
   */
  outdent(): string {
    if (!editor) return 'no-editor'
    try {
      const view = editor.ctx.get(editorViewCtx)
      const { state } = view
      if (liftListItem(state.schema.nodes.list_item)(state, view.dispatch)) return 'ok'

      const { $from } = state.selection
      if ($from.depth < 1) return 'no-block'
      const start = $from.start($from.depth)
      const end = Math.min(start + 4, $from.end($from.depth))
      if (end <= start) return 'no-indent'
      const m = /^[ \u3000]{0,4}/.exec(state.doc.textBetween(start, end))
      const n = m ? m[0].length : 0
      if (!n) return 'no-indent'
      view.dispatch(state.tr.delete(start, start + n).scrollIntoView())
      return 'ok'
    } catch (e) {
      return 'ERR ' + String(e)
    }
  },

  /**
   * 在当前段落**之后**插入一个真正的块：段落 / 分隔线 / 二级标题。
   *
   * ⚠ 时间戳、分隔线、分段标题从前都是把 `"\n\n---\n\n"` 这样的字符串塞进光标处。
   *   ProseMirror 的文本节点里没有「换行」这个概念，`\n` 会被压成空格或直接吃掉 ——
   *   于是 Ctrl+H 看起来「插了一条线」，实际存进 .md 的是一段带 `---` 的普通文字，
   *   下次打开才露馅。这里直接建 schema 节点，结构与手工敲出来的一模一样。
   */
  insertBlockAfter(kind: 'paragraph' | 'hr' | 'heading', text = ''): string {
    if (!editor) return 'no-editor'
    try {
      const view = editor.ctx.get(editorViewCtx)
      const { state } = view
      const { schema } = state
      const { $to } = state.selection
      // ⚠ 光标可能落在文档最外层（刚插完分隔线、它后面没有块时就是这种）。
      //   那种情况不能直接 return —— 否则「插完一条线，再按 Ctrl+H / Ctrl+T
      //   全都没反应」。退化成「追加到文末」，与用户的直觉一致。
      const pos = $to.depth >= 1 ? $to.after(1) : state.doc.content.size

      const para = schema.nodes.paragraph

      if (kind === 'hr') {
        // ⚠ **不要**在 hr 后面补空段落：Milkdown 把空段落序列化成 `<br />`，
        //   存进 .md 就是一行 HTML 标签（旧笔记里没有这种东西）。
        //   光标交给 ProseMirror 就近解析 —— hr 后面没有块时它落在 hr 之前的
        //   段落末尾，连续按 Ctrl+H 也就是在同一处再添一条线，视觉上看不出差别。
        return dispatchAt(view, state.tr.insert(pos, schema.nodes.hr.create()), pos + 1)
      }

      const content = text ? schema.text(text) : null
      const node =
        kind === 'heading'
          ? schema.nodes.heading.create({ level: 2 }, content)
          : para.create(null, content)

      // 光标落在新块的文字之后：用户接着敲的字写进新的一行
      // （旧版插完时间戳也是这个位置）。
      return dispatchAt(view, state.tr.insert(pos, node), pos + node.nodeSize - 1)
    } catch (e) {
      return 'ERR ' + String(e)
    }
  },

  /**
   * 整体换文档：载入笔记 / 切日期都走这里。
   * 只靠 props 换不动 —— defaultValueCtx 只在创建时读一次。
   *
   * flush = true 重建 EditorState，连带清掉撤销栈：换的是另一篇笔记，
   * 让它还能 Ctrl+Z 回上一篇的内容是错的。返回 false 表示编辑器还没建好，
   * 调用方需要先挂起来、等 ready 再灌。
   */
  setMarkdown(md: string): string {
    if (!editor) return 'no-editor'
    // ⚠ 必须先写 lastStored：markdownUpdated 是同步触发的，晚一步就会把旧值 emit 回去
    lastStored = md
    try {
      editor.action(replaceAll(toDisplayMarkdown(md), true))
      return 'ok'
    } catch (e) {
      return 'ERR ' + String(e)
    }
  },
})
</script>

<template>
  <div ref="host" class="sw-editor" />
</template>
