# 状态卡

> **覆盖式更新**：每次会话结束改这一份，不追加流水、不留历史版本（历史在 Git）。
> 新会话先读这里，再核对代码与 `git log` —— 这张卡是**起点，不是真理**。
>
> 更新于 `2026-10-23`　基线提交 `b5cb803` + 本轮未提交改动

---

## 当前焦点

用户给了真实 docx 与笔记窗口截图：Pandoc 表格已验收（普通表格全部 pipe table），
笔记的「首行突兀 / 标题发粗 / 打字频闪 / 空行格式不一致」已按样式层修掉。
下一步等用户看实际观感；字体字号仍是用户配置（楷体 16pt），可用 `Alt+-` 调回 14pt。

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
  只剩「当前主题 + 说明」，没有保存按钮。（`npm run build` 通过；真机面板 DOM：
  外观页 `inputs=0` / `selects=0` / 无 `sw-btn--primary`，说明文字正确）
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
- **首次呼出只出任务栏**（防御性修复）：`WindowFeature._MeasureStable` 补 200×120 下限 +
  60×10ms 重试，对齐 `WebWindow._Place`。此前它把隐藏态读到的 10px 中途值当终值，
  默认落点按 10px 宽度算 → 窗口被摆到屏幕右侧外。
  （三次新进程首次呼出：矩形均为 `1713,264 832×1046`，全在工作区 0,0,2560,1600 内；
  **偶发是否根治待观察**）
- **Pandoc 真实 docx 验收**：5.2MB LangChain 课件 → **1.4s**、86KB、无失败；
  普通表格 55 行全部是 pipe table，3 处合并单元格降级为 `<table>` 并产生 warning。
- **笔记排版修复**：首行标题压到与正文同字号、标题字重 600→500（楷体没有粗体，
  600 会触发合成加粗）、笔记页去掉 `backdrop-filter`（输入时不再重算模糊）、
  `.sw-editor` 加 `scrollbar-gutter: stable`（滚动条出现不再让正文重排）。
  （真机：首行 `21.33px` = 正文、第二个 H1 `23.89px`、`mainFilter=none`、`gutter=stable`）
- **空段落清理**：`toStoredMarkdown` 删掉独占一行的 `<br />` 并压缩连续空行，
  围栏代码块内不动。（真机：`para1 / <br /> / para2 / 3 个空行 / para3`
  → `para1、para2、para3`；代码块内空行原样保留）
- **Alt+M「按下没反应」排查与修复**：底层转换正常（资源管理器前台探针 → 128KB md / 1.4s）；
  没反应的原因是热键只在 `CabinetWClass` 生效，在桌面按**完全无声**。
  现在桌面（`Progman` / `WorkerW`）也纳入上下文，无选中项时给 5 秒提示并写日志。
  （真机：`explorer ctx=1` / `desktop ctx=1`；桌面调用 Run → 日志「前台类名 Progman」）
- **删除 Ctrl+H / Ctrl+Shift+H**（插分隔线 / 插「新分段」）：Markdown 里直接打
  `---` / `## ` 就会即时渲染，占位文字还得先选中改写。`Ctrl+T` 时间戳保留。
  （真机：派发 Ctrl+H / Ctrl+Shift+H 后 markdown 长度不变；Ctrl+T 仍会变长）
- **编辑区底色改成不透明的 `--sw-bg`**：此前 `.main.note` 叠了两层渐变 + 半透明底，
  背后 body 的光雾透上来 → 「打字区与空白区亮度不同」的割裂感。
  （真机：`backgroundColor = rgb(46, 46, 46)`；`backdrop-filter: none` 仍生效）
- **编辑区色差消除**：`.ProseMirror` 的 5% 黑底改为透明、`.main.note::before` 去掉
  46px 内雾（只留上下 1px）。
  （真机：`editorBg=rgba(0,0,0,0)`、`plateBg=rgb(46,46,46)`，整片同色）
- **保存反馈可感知**：`无改动 / 空笔记不落盘` 也带时间戳（`无改动 · 23:18`）——
  这台机器 `prefers-reduced-motion` 为 true，底栏的闪动动画不播放，只靠动画等于没反馈。
  （真机：连续保存两次 → `已保存 23:18` / `无改动 · 23:18`）
- **回归**：`tools\run-tests.ps1` 71 条断言全绿；AHK 语法预检通过（含坏样本反向验证，
  退出码 2）；真机启动 6 秒 stderr 空、`_error.log` 无新增；`check-docs.ps1` 通过。

## 未完成 / 已知风险

| 项 | 状态 |
| --- | --- |
| **面板未保存设置的拦截** | `hasPending()` 在运行页面上可调用（探针返回 false）；「有改动 → true」这一支未真机点验 |
| **提示词「放弃」链路** | 依赖 `Hide()` 清基线；Esc / × / 保存三条路径只做了代码审查 |
| **笔记字体排版** | 首行/标题字重/空行已修；字体观感与字号档位是否合意，仍需用户目视（楷体 16pt 是用户配置） |
| **打字频闪** | 已去掉编辑页的 `backdrop-filter` 并固定滚动条槽位；若仍闪，需要录屏或更具体的触发条件 |
| **桌面选中项读不到** | 桌面不是 `Shell.Application` 的窗口，Alt+M 在桌面只给提示；真正转换要在资源管理器里选中文件 |
| **Alt+M 的自动化验证不可靠** | 上下文热键由钩子实现，注入的 `SendKeys` 未必触发；只能手按或探针直接调 `Run()` |
| **状态栏的标签显示** | 逻辑复用 `TagFromFileName`，但只验过空标签（当天笔记没标签） |
| **Pandoc 表格** | 普通表格已锁成 pipe table；**真实 docx 未验**，合并单元格在 Milkdown 里是否可见未验 |
| **保存失败路径无自动化用例** | 真机 + 文件锁已手工验过（退出被拦下）；自动化仍需要可注入的路径与锁 |
| **旧外观配置未清理** | `[Appearance]` 的 Material / Radius / Motion / Density 留在 ini 但不读 |
| 同日多文件只认第一个 | `日期.md` 与 `日期-标签.md` 并存时按日期只匹配第一个 |
| 实验前端仍在正式构建 | `GlassLab.vue` + `lab.css` 经 `?view=lab` 进包 |
| `BackdropService` 未接入 | 361 行，机制在，主题表里没有带图条目 |
| 分发未验收 | `web/dist` 入库可用，但运行时打包、跨机器首次运行都没试过 |
| 首次 `Alt+Z` 偶尔只出任务栏 | 已补最小尺寸判据（见「已完成」）；三次首次呼出正常，**偶发是否根治待观察** |

## 下一步（按顺序，一次做一件事）

1. 用户目视新排版：首行是否还突兀、正文观感是否合意、打字是否还闪；
   字号可用 `Alt+-` / `Alt+=` 现场比较（当前是楷体 16pt）。
2. 若还有表格问题，拿**具体那一段**的原文 / 输出 md / 编辑器截图对照 ——
   已知边界：合并单元格只能退回 `<table>` HTML（Markdown 表达不了）。
3. 带标签的笔记真机看一眼状态栏「🏷 标签」（已用假路径验过显示，未验真实改名）。
4. 面板 `hasPending` 拦截已补验（改了文件夹槽位不保存 → 退出被拦下）。

## 维护规则

- 完成项**不要**留成「已做完」的清单越堆越长 —— 压成一句或直接删，历史在 Git。
- 只有**真的变了**才改这张卡；没变化就别为了「更新过」制造提交。
- 「建议」和「已决定」分开写；不要把自己的推测写进已完成。
