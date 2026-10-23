# 状态卡

> **覆盖式更新**：每次会话结束改这一份，不追加流水、不留历史版本（历史在 Git）。
> 新会话先读这里，再核对代码与 `git log` —— 这张卡是**起点，不是真理**。
>
> 更新于 `2026-10-23`　基线提交 `b5cb803` + 本轮未提交改动

---

## 当前焦点

管理面板、退出链路、外观去参数化、笔记状态栏都已收敛；Pandoc 表格的根因也已定位
（输出格式不是 pipe table）。下一步用**真实 docx** 验收表格结果，再决定字体排版怎么对齐。

## 已完成（括号内是验证范围）

- **管理面板最小化**：`WebWindow` 新增可选 `minimizeBox`，只有面板开启。
  （真机：窗口 `WS_MINIMIZEBOX` 为真；`ShowWindow(SW_MINIMIZE)` 后按 `Alt+S`
  能从最小化恢复且仍可见）
- **退出键改为 `Alt+Shift+S`**，撤销 `Alt+Shift+Z`。
  （真机：旧键按了不退出；无未保存内容时新键正常退出）
- **退出守卫**：平台 `EventBus "Exit.Guard"` 收集模块检查，返回 `{ok, reason}`；
  笔记存盘 + 提示词未保存 + 面板 `hasPending`。
  （探针：`guards=2`、`dirty=1`、`RequestExit()` 返回后进程仍活着；
  面板页 `hasPending()` 可调用、默认返回 false，外观页 `hasApply=false`；
  **「面板里有改动 → true」这一支未真机点验**）
- **外观去参数化**：撤掉材质浓度 / 圆角 / 动效 / 密度四项；`ThemeService` 不再读
  `[Appearance]` 那四个键；`ThemeJson` / `ahk.ts` / `glass.css` 同步清理；外观页
  只剩「当前主题 + 说明」，没有保存按钮。（`npm run build` 通过；**真机目视未做**）
- **笔记状态栏**：底栏恢复「📅 日期 星期」「🏷 标签」，字数改成正文纯文本长度
  （`NoteSessionService.Meta/PushMeta` + `NoteHostMeta` + `NoteEditor.getTextLength`）。
  （探针：`meta={"date":"2026-10-23","weekday":"周四","tag":""}`，底栏文本含日期；
  同一篇 `chars=10`（Markdown）→ `textChars=7`（正文）；**带标签的笔记未验**）
- **字体入口恢复**：`Alt+Shift+T` 切正文字体、`Alt+=` / `Alt+-` 调字号 —— 迁移时这三条
  热键丢了，`FontService` 却一直在读写配置（用户只能改 ini）。切换后底栏会说一句
  「字体：华文行楷 16pt」（旧版 StatusBar 也这么反馈）。
  （真机：`FontIndex` 1→2→3→4、`FontSizeIndex` 3→4→3，配置已还原；
  切换时 `--sw-ed-font` 从「楷体」变「华文行楷」，底栏文本包含「字体：华文行楷 16pt」）
- **Pandoc 表格改输出 pipe table**：`PandocRunner` 加
  `-t markdown-grid_tables-multiline_tables-simple_tables`；合并单元格退回 `<table>` HTML 时
  `FileConvertService` 记 warning（`_HasHtmlTable`）。
  （自造 HTML 样本：简单表格 → `| A | B |`；合并表格 → HTML + warning；**真实 docx 未验**）
- **转换期间有提示**：`ConvertFeature.Run` 先 ToolTip「正在转换…」——
  `RunWait` 是同步的，大文件期间热键不响应，不给提示会被当成卡死。
- **保存失败会拦住退出**：锁住笔记文件（独占）→ 编辑后按退出 → `_error.log` 记录
  「笔记：笔记没能保存（无法写入 …）」，进程继续运行。
  （真机 + 文件独占锁，2026-10-23；副本隔离，真实笔记未参与）
- **回归**：`tools\run-tests.ps1` 71 条断言全绿；AHK 语法预检通过（含坏样本反向验证，
  退出码 2）；真机启动 6 秒 stderr 空、`_error.log` 无新增；`check-docs.ps1` 通过。

## 未完成 / 已知风险

| 项 | 状态 |
| --- | --- |
| **面板未保存设置的拦截** | `hasPending()` 在运行页面上可调用（探针返回 false）；「有改动 → true」这一支未真机点验 |
| **提示词「放弃」链路** | 依赖 `Hide()` 清基线；Esc / × / 保存三条路径只做了代码审查 |
| **笔记字体排版** | 字体 / 字号入口已恢复；行距、段距、标题层级的观感仍要按旧版参照验收 |
| **状态栏的标签显示** | 逻辑复用 `TagFromFileName`，但只验过空标签（当天笔记没标签） |
| **Pandoc 表格** | 普通表格已锁成 pipe table；**真实 docx 未验**，合并单元格在 Milkdown 里是否可见未验 |
| **保存失败路径无自动化用例** | 真机 + 文件锁已手工验过（退出被拦下）；自动化仍需要可注入的路径与锁 |
| **旧外观配置未清理** | `[Appearance]` 的 Material / Radius / Motion / Density 留在 ini 但不读 |
| 同日多文件只认第一个 | `日期.md` 与 `日期-标签.md` 并存时按日期只匹配第一个 |
| 实验前端仍在正式构建 | `GlassLab.vue` + `lab.css` 经 `?view=lab` 进包 |
| `BackdropService` 未接入 | 361 行，机制在，主题表里没有带图条目 |
| 分发未验收 | `web/dist` 入库可用，但运行时打包、跨机器首次运行都没试过 |
| 首次 `Alt+Z` 偶尔只出任务栏 | 历史问题，原因未定位 |

## 下一步（按顺序，一次做一件事）

1. 用一份**真实出问题的 docx** 跑 `Alt+M`：对照「原文 / 输出 md / 编辑器显示」，
   确认表格是否变成 `| … |`、合并单元格那条警告是否出现。
2. 笔记字体排版：拿旧版界面或一份样本文档当参照，逐项对齐后再动 CSS
   （入口 `Alt+Shift+T` / `Alt+=` / `Alt+-` 已恢复）。
3. 带标签的笔记真机看一眼状态栏「🏷 标签」（当前只验过空标签）。
4. 面板 `hasPending` 拦截已补验（改了文件夹槽位不保存 → 退出被拦下）。

## 维护规则

- 完成项**不要**留成「已做完」的清单越堆越长 —— 压成一句或直接删，历史在 Git。
- 只有**真的变了**才改这张卡；没变化就别为了「更新过」制造提交。
- 「建议」和「已决定」分开写；不要把自己的推测写进已完成。
