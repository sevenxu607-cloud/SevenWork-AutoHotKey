# 状态卡

> **覆盖式更新**：每次会话结束改这一份，不追加流水、不留历史版本（历史在 Git）。
> 新会话先读这里，再核对代码与 `git log` —— 这张卡是**起点，不是真理**。
>
> 更新于 `2026-10-24`　基线提交 `a2fcc22` + 本轮未提交改动

---

## 当前焦点

「精简」第二批收尾：批次 A（Markdown 清洁逻辑独立 + 代码区保护 + 前端测试）与
批次 B（删零调用代码、实验前端移出生产构建）已完成并验证；剩下是文档收尾与用户目视。

## 已完成（括号内是验证范围）

### 本轮（2026-10-24）

- **Markdown 清洁逻辑抽成 `web/src/markdown.ts`**，并补上**代码区保护**：围栏 / 缩进 /
  行内代码里的 `***`、行尾反斜杠、`&#x20;`、`<br />` 一律不动。此前 `toStoredMarkdown`
  会改写代码注释里的字节。
  （`node --test web/tests/markdown.test.mjs` 17 条全绿，其中 4 条专测代码区；
  反向验证：故意改坏 → 4 条变红且退出码 1，恢复 → 全绿）
- **`tools\run-tests.ps1` 同时跑两套测试**：AHK 71 条 + web 17 条，`=== TESTS PASSED ===`、退出码 0。
- **面板切页不再丢未保存设置**：每页各留一份编辑值，`hasPending()` 查**所有页**。
  （真机探针：改文件夹槽位 → `pending-same-page=true`；切到别的页 →
  `pending-other-page=true`；切回来 `kept-value=Z:\probe`，值还在）
- **删零调用代码**：`BackdropService`（19KB，贴图被 WebView2 合成表面整片盖住）+
  `bg` / `bgAlpha` / `bgFit` 三字段；`FolderSlotService.GetAll/Describe`、
  `LoadFeature.ReadNote`、`SaveFeature.Take`、`NoteSessionService.GetPath/IsLoaded`、
  `PromptStoreService.PathFor`、`ExplorerProbe.IsExplorerWindow`、
  `ModuleRegistry.Unregister`、`WebHostService._bgUnsupported`；
  `PeerCoordinator` 的「记录最近落位」半截（含它的 `Init()`）；`msftedit.dll` 预加载。
- **`NoteEditor.insertBlockAfter` 收窄**到只插段落（分隔线 / 二级标题在 Markdown 里直接打）。
- **实验前端移出生产构建**：`GlassLab.vue` 改异步加载、`lab.css` 随组件走。
  （`npm run build`：`index.css` 49.36 → 40.63 kB，另出 `GlassLab.js/css` 各 8.7 kB）
- **回归**：`tsc --noEmit` 退出码 0；AHK 语法预检 0；真机启动 6 秒 stderr 空、
  `_error.log` 无新增；`Alt+Z` 出 `SevenNote`、`Alt+S` 出「SevenWork · 工作台」。

### 此前几轮（细节见 `git log`，只留仍需知道的范围）

- 三份资料拆开（意图 / 状态 / 经验）+ 对话档案放仓库外；`check-docs.ps1` 收尾。
- 删 `EditorService` 与笔记 `PandocService`（721 行）；笔记直接写 `.md`。
- 数据安全六项：大小写敏感比对、退出/隐藏前先存盘、标签改名同步路径、DOCX `numPr` 警告等。
  （真机 + 文件独占锁，副本隔离）
- 面板最小化；退出键改 `Alt+Shift+S` + 退出守卫（笔记 / 提示词 / 面板三项）。
- 外观去参数化（撤四档滑杆）；笔记底栏日期 / 星期 / 标签；字数 = 正文纯文本。
- 字体字号入口恢复（`Alt+Shift+T` / `Alt+=` / `Alt+-`）；字体档位缩到 4 款。
- Pandoc 锁 pipe table + 合并单元格退回 HTML 时记 warning（真实 docx：1.4s / 86KB）。
- Markdown 输入转换恢复（`# ` / `---` / `- ` / `**x**`），标题与 `strong` 字重压到 500。
- 排版与底色：首行同字号、编辑区不透明 `--sw-bg`、去 `backdrop-filter`、
  `scrollbar-gutter: stable`；`Ctrl+H` / `Ctrl+Shift+H` 删除，`Ctrl+T` 保留。

## 未完成 / 已知风险

| 项 | 状态 |
| --- | --- |
| **提示词「放弃」链路** | 依赖 `Hide()` 清基线；Esc / × / 保存三条路径只做了代码审查 |
| **笔记字体观感** | 字重与空行已修；楷体 16pt 是否合意仍需目视（`Alt+-` / `Alt+=` 可现场比） |
| **打字频闪** | 已去编辑页 `backdrop-filter` 并固定滚动条槽位；若仍闪需要录屏或具体触发条件 |
| **桌面选中项读不到** | 桌面不是 `Shell.Application` 的窗口，`Alt+M` 在桌面只给提示 |
| **`Alt+M` 自动化不可靠** | 上下文热键走钩子，注入的 `SendKeys` 未必触发；只能手按或探针直接调 `Run()` |
| **标签显示** | 复用 `TagFromFileName`，但只验过空标签 |
| **Pandoc 真实 docx** | 普通表格已验证；合并单元格在 Milkdown 里是否可见未验 |
| **保存失败无自动化用例** | 文件锁路径手工验过，自动化仍缺可注入的路径与锁 |
| **`markdown.ts` 的代码区判据是词法级** | 围栏、缩进、行内代码已覆盖；**列表里再缩进的代码块**未覆盖 |
| **`_=<tick>` 防缓存** | `WebWindow._Mount` 给 URL 加时间戳 —— 是否真的必要仍是推断，未做过对照 |
| **旧外观配置未清理** | `[Appearance]` 的 Material / Radius / Motion / Density 留在 ini 但不读 |
| 同日多文件只认第一个 | `日期.md` 与 `日期-标签.md` 并存时按日期只匹配第一个 |
| 分发未验收 | `web/dist` 入库可用，但运行时打包、跨机器首次运行都没试过 |
| 首次 `Alt+Z` 偶发只出任务栏 | 已补最小尺寸判据；三次首次呼出正常，**偶发是否根治待观察** |

## 下一步（按顺序，一次做一件事）

1. 用户目视：字体 / 字号是否合意、打字是否还闪、带标签笔记的底栏「🏷 标签」。
2. 若 Markdown 仍有变形，给**具体那一段**的原文 / 落盘 md / 截图对照。
3. 首次呼出继续观察几次（偶发只出任务栏）。
