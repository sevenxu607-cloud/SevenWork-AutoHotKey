# 开发经验包

> 只收**验证过、能复用**的结论：下次遇到同类问题该怎么做、哪里不能碰、哪些方向已经算过账。
> 方向见 [`INTENT.md`](INTENT.md)，当前进度见 [`STATE.md`](STATE.md)，历史交给 Git。
> 原始对话在仓库外的私人档案，**不进 Git**。
>
> 可信度三级：**已实测** = 真机跑过并看过结果；**推断** = 没验过；**暂停** = 做过一半，别当现状。
> 结论都有前提：换宿主方式、换 Windows 版本、换样本，就要重新验。

---

## 目录（按需跳读）

| 节 | 讲什么 | 什么时候看 |
| --- | --- | --- |
| 1 架构与边界 | 依赖方向、模块可插拔、Capability 契约 | 加模块 / 挪代码 |
| 2 AHK v2 语言陷阱 | 会改变设计的那几条（完整检索表在 `.clinerules/03`） | 写 `.ahk` 报奇怪的错 |
| 3 窗口与 WebView2 | 隐藏态挂载、Show / WinMove、多窗口 | 碰窗口或 WebView2 |
| 4 材质与主题 | 玻璃为什么立不住、哪些参数不能碰 | 改样式 / 主题 |
| 5 数据安全 | 写盘、保存失败、改名同步 | 碰笔记 / 文件 |
| 6 验证方法 | 反向验证、探针、真机启动 | 要证明「真的好了」 |
| 7 资料怎么记 | 四份资料的分工 | 收尾 |
| 8 平台能力契约 | Capability 只收什么、失败怎么返回 | 新增能力 |
| 9 已经算过账的方向 | 别再重新论证的清单 | 想推翻某个设计之前 |
| 10 编译与分发 | Ahk2Exe、loader、dist、可选 Pandoc | 打包 / 编译 / 发布 |
| 11 演示与录屏 | 外部驱动、OBS 双显卡、分章文件 | 做验收视频 / 自动化演示 |

---

## 1. 架构与边界

- **依赖只能向下**：`Feature / Module → Service → Kernel → OS`，`Feature / Module → Capability → OS`。
  Capability 一旦引用 `modules/*`、`EventBus`、业务 `Config`，平台层就退化成业务层 —— 改一个模块
  要连带改平台。**已实测**：多轮重构都在收这个尾。
- **跨模块零调用，同模块可直接调**。事件用于「我不知道谁关心」，不用于「我要调它」。
  为后者绕事件只会多一层转发，还会把同步返回变成异步丢失。
- **Kernel 需要向上报告时用注入**：`EventBus.SetErrorSink(LogError)`，别在 Kernel 里直接调
  `LogError` —— 那一步就把 Kernel 和业务绑死了。
- **可插拔的检验方式是删掉它**：删任一 Feature，其余照常启动。做不到说明边界渗了。
- **`Init()` 不碰窗口，`Start()` 才对外可见**。顺序固定为 `InitAll → RegisterAll(热键) → StartAll`，
  否则窗口先露面、热键还没就位，表现为「按热键没反应」。
- **模块报上来的热键上下文才算数**：声明了 ctx 却没人提供实现，该模块热键**一条都不注册**并写日志。
  退回 `HotIf()` 更糟 —— 那会把 `Esc` / `Enter` 变成全系统热键。

## 2. AHK v2 语言陷阱

完整「报错原文 → 对策」检索表在 [`.clinerules/03-ahk-v2.md`](../.clinerules/03-ahk-v2.md)。这里只留
**会改变设计**的那几条：

- **属性里存的函数不能直接 `obj.prop(args)` 调用**：走的是方法查找，会抛
  `Too many parameters passed to function`，还会被外层 `try` 吞掉 → **先取局部变量再调**。
- **字段名不能与方法名同名**（v2 不区分大小写），字段也不能声明在类体里 —— 两种都是
  `Property is read-only`，表现成「按热键毫无反应、日志只有一行」。
- **`SetTimer` 收不了类静态方法**：用箭头函数包一层，并把闭包**存字段**，否则停不掉。
- **未捕获异常默认弹模态框并停摆**：组合根注册 `OnError` 写日志后继续。⚠ **兜底只保证不倒，
  不保证逻辑对** —— 异步回调碰窗口前仍要自己过闸。
- **`Send` 默认触发不了 `HotIf` 上下文热键**（键盘钩子忽略同脚本的 Send）。**外部驱动进程**
  设 `SendLevel(1)` + `SendMode("Input")` 后可以触发，已实测（`demo-sevenwork.ahk` 用它
  驱动 `Ctrl+G` / `Ctrl+N`）；同脚本内的探针仍不要指望。
- **`FileExist` 返回 `"A"` 不是 `true`**；比较数字前先 `IsNumber()` 守卫（空串会抛
  `Expected a Number`）。

## 3. 窗口与 WebView2

- **凡是装网页的窗口都走 `WebWindow`**，不要自己写生命周期。踩过的坑（隐藏态挂载白屏、
  先 `Show` 再 `WinMove` 会飘、Esc 收不到）都封在里面。
- **每个窗口的 `dataDir` 必须不同**：同一 user data folder 建不出第二个
  `CoreWebView2Environment`，失败藏在 `await()` 里，**只表现为窗口一片纯底色**。
- **`WebHostService` 是多实例的**：调用一律显式传 hwnd。无参会落到「最近挂载的窗口」，
  面板一开、笔记窗就收不到尺寸。
- **hostObjects 的方法名不能撞 JS 内置**：`apply` / `call` / `bind` / `toString` / `constructor` …
  前端拿到的是 `Function.prototype` 上的原生函数，调用抛 `TypeError`，而调用点通常在 `try` 里 ——
  表现成「点保存没反应、日志一条不写」。
- **定位在隐藏态完成**：`Show("Hide")` → 量尺寸 / `WinMove` → 最后 `Show()`。反过来会先出现在
  默认落点、再跳到目标位置。
- **重新呼出 WebWindow 时，`WinActivate` 失败不能连带跳过 Resize / Esc**：实测
  `Alt+S` 关闭面板再打开，`WinActivate("ahk_id …")` 会抛 `Target window not found`；
  它和 `WebHostService.Resize`、`Hotkey("Esc", …)` 原来在同一个 `try` 里，失败后窗口
  虽然出来了，内容区仍是旧尺寸、Esc 也没重新注册。修法：只把 `Show()` 当硬失败，
  `WinActivate` 单独容错，Resize 与 Esc 重注册始终执行；最小化恢复用
  `ShowWindow(SW_RESTORE)`，不要用按标题匹配的 `WinRestore`。
  **已实测（2026-10-24，面板开→关→再开→Esc）**。
- **窗口 Close 里不要同步 Eval 页面脚本**：`WebHostService.Eval()` 内部是
  `ExecuteScriptAsync().await()`；页面卡住 / 正在销毁时会把 GUI Close 线程一起拖住，
  表现成「叉和 Alt+P 都关不掉」。先 `Hide()`，入场复位宁可不做。
- **外部程序槽位不能把「列表第一个窗口」当主窗**：Chromium / Electron / PyCharm
  一类程序会有隐藏合成窗或启动画面；`WinShow` 出来可能是一块没有正常关闭入口的
  巨大空白窗口。只选可见、未最小化、有标题、尺寸正常的主窗；**不要为了唤醒而
  `WinShow` 任意隐藏 / 最小化句柄**，没有可见窗就交给 `Run(cmd)`。
  **已按代码审查修复，待真机复验各槽位。**
- **`WinMove` 收物理像素，`Gui.Move` 收逻辑单位**：150% 缩放下混用会二次放大。
  位置记忆全程 `WinMove` + `WinGetPos`，尺寸别写死。
- **最小化窗口 `IsWindowVisible` 仍是 1**，而且 `WinGetPos` 返回屏幕外停放位（`-32000` 一类）。
  记位置前校验它落在某个 `MonitorGetWorkArea` 内。
  **已实测（2026-10-23）**：最小化后调 `Gui.Show()` **不会**还原窗口，只点亮任务栏按钮 ——
  必须先 `WinRestore` 再 `Show` + `WebHostService.Resize`（`WebWindow.Activate` 已按此改）。
- **三区域口径（已实测 2026-10-24）**：辅助区贴工作区右下（772×1020、离右 15）；
  记录区在辅助区正上方、同宽、顶留 10、缝 6；工作区是左侧剩余矩形。
  区域按**可见边界**算，摆放时用 `WindowProbe.InvisibleFrame + RectMath.Physical` 转外框。
  真机：记录区可见 `1773,10,772,564`，笔记外框 `1764,10,790,573`。
- **浮层也填满辅助区（2026-10-24 用户要求「严丝合缝」）**：提示词库走
  `WebWindow place:"zone"`，`_Place` 里把窗口 `WinMove` 到区域外框；日期框按区域
  **逻辑尺寸**（`w * 96 // A_ScreenDPI`）重排控件，再 `Place(fill:true)`。
  真机：两者外框 `1764,580,790,1029`、可见 `1773,580,772,1020`；提示词页面
  `innerWidth×innerHeight = 512×649`（CSS），`__swprompt` 存在、正文 105 字。
  ⚠ 不再「居中并夹到工作区」——那会让浮层比区域宽、压到工作区。
- **恢复布局只摆注册表里的窗口**：笔记在 `Init` 注册；终端 / 浏览器 / 文件 / 应用槽位在
  唤出时注册。同一区域多个窗口会重叠（终端与浏览器都在辅助区）—— 区域只保证「落到哪块」。
- **最大化窗口 `WinMove` 不生效**：`PlacementExecutor` 先 `IsZoomed → ShowWindow(SW_RESTORE)`。
  这条只做了代码补齐（2026-10-24），**未真机验过最大化窗口的落区**。
- **笔记不再置顶**：固定落记录区后去掉 `+AlwaysOnTop`，实测 `WS_EX_TOPMOST=0`；
  否则它会盖住工作区里正在用的窗口。
- **应用 / 文件必须填满 + 持续看管（已实测 2026-10-24）**：保留尺寸会被 Everything / Explorer
  恢复，表现为越区或向上漂移。`fill:true` + 8 秒内每 500ms 复核后：
  Obsidian 外框 `10,10,1757,1590`（2/5/9 秒三次一致）；Everything 在辅助区时
  `1772,580,774,1021`。终端 / 浏览器例外：高度归 WT profile、宽度被 Edge 吸附，仍用锚定。
- **应用槽位找主窗口（2026-10-26 修正）**：按 exe 文件名分三级取 ——
  ① 可见 + 未最小化 + 有标题 + 尺寸正常；② 最小化 + 有标题 + 还原尺寸正常；
  ③ 收起（隐藏）+ 有标题 + 非辅助窗类。Everything 的搜索窗 / Obsidian 的弹窗 /
  Chromium 辅助窗都可能排在主窗口前面，所以按面积取最大，并排除
  `Chrome_WidgetWin_0` / `Base_PowerMessageWindow` / `IME` 这类辅助窗。
  **已实测（本机 Obsidian 1.13.7）**：最小化时主窗 `Chrome_WidgetWin_1` 的
  `IsIconic=1`、`WinGetPos` 是 `-21333,-21333,158x26`（停放位 + 退化尺寸），
  旧逻辑（只认可见 + 未最小化）因此认不到窗口 → `Run` → 单实例程序**新开一扇窗**，
  表现就是「不是呼出，而是又多一个进程」。⚠ 最小化 / 隐藏的窗口量不到当前尺寸，
  要读 `GetWindowPlacement` 的 `rcNormalPosition` 判断「是不是正常大小」。
- **恢复最小化要 `ShowWindow(SW_RESTORE)` 并等它真的退出最小化**：`ShowWindow` 是异步的
  （本机 300ms 后才 `IsIconic=0`）。这期间 `PlacementExecutor` 判 `minimized` 直接放弃、
  `ZoneService.Watch` 的第一轮复核也会因此停掉 → 窗口回来了但停在它自己记住的位置。
  写法：`WinShow` → 若 `IsIconic` 则 `ShowWindow(9)` → 轮询到「可见且未最小化」再 `Place`。
  冷启动等待放宽到 15 秒（Obsidian 比 Everything 慢）。
- **改 `%AppData%\SevenWork\_config.ini` 必须保留 UTF-16 LE + BOM**：该文件是 `FF FE` 开头的
  UTF-16；用「UTF-8 无 BOM」重写后 `IniRead` 读出的中文 `Vault` 路径变乱码 →
  启动走「首次运行选目录」分支、`DirCreate` 报 `(123) 文件名、目录名或卷标语法不正确`，
  而且**热键注册根本没执行到**（表现成「热键全没反应」）。要改就用
  `[Text.UnicodeEncoding]::new($false, $true)` 写回，或只改字节、整文件保留。
- **原生 Button 在深色窗口上是白底**：标签对话框改用 `Text + SS_NOTIFY`（`+0x300`
  含垂直居中），继承窗口底色；点击「取消」实测窗口关闭（`after=0`）。
  Enter / NumpadEnter 另用 `HotIfWinActive + Hotkey`（Text 不是默认按钮）。
  位置用 `ZoneService.CenterIn(hwnd, "record")`，窗口中心与记录区中心一致。
- **按键模块要有反馈**：CapsLock 层 Toggle 现在闪 ToolTip（开启时说明 H/J/K/L = 方向键），
  不再只是静默改配置；`CapsLock.Toggled` 事件保留给订阅者。

## 4. 材质与主题

- **WebView2 客户区透不到桌面**（**已实测**：Win11 25H2 + 本项目「`Gui` + WebView2」宿主）：
  `DwmSetWindowAttribute(38, …)` 在纯 `Gui` 上有效（配合 `DwmExtendFrameIntoClientArea(-1)`），
  一旦挂上 WebView2 就再也不出现；`SetWindowCompositionAttribute(ACRYLIC)` 会把窗口 layered 化、
  连标题栏一起消失。→ **本项目要玻璃只能由 CSS 画**。结论绑定在这个宿主组合上 ——
  换纯原生窗、换 Windows 版本，都要重新验。
- **拦 `WM_ERASEBKGND` 必须有 backdrop 托底**，否则窗口整个不可见；而且同一组合实测时好时坏。
  **不要进生产。**
- **材质在 `glass.css`、结构在组件里**：scoped 样式的 specificity 输给全局材质选择器，
  圆角这类变量统一落在 token（`--sw-radius-*`）上。
- **外观不给逐项参数**（2026-10-23 定）：材质浓度 / 圆角 / 动效 / 密度四项滑杆撤掉 ——
  实际观感差几乎看不出，却要维护「保存 → 广播 → 前端改写变量」整条链路。观感由每套主题
  给全，参数试验留在 `?view=lab`。验证范围见 `STATE.md`（入口消失 + 默认值一致，
  未做逐项目视对比）。
- **主题分两层**：主题本身（色板 / 派生 / 广播）在平台 Service，调节入口在模块。
  删掉模块，所有窗口照样上色 —— 这才叫可插拔。

## 5. 数据安全

- **保存要有返回值，不能「发了就算」**：返回 `{ok, reason, recoverable}`，调用方据此决定
  切日期 / 收窗口 / 退出。`recoverable` 专指「本来就没有可丢的内容」（冷启动、页面没起来）。
- **退出要逐条问，不看单一「保存成功」标志**：`WorkBench.RequestExit()` 调各模块在 `Init()` 里
  `Emit("Exit.Guard", {id, check})` 登记的检查；守卫抛错按「不通过」处理，宁可拒绝退出。
  平台不认识模块业务、模块也不反向调平台。**已实测**（2026-10-23）：探针 `guards=2`、
  `dirty=1` 时 `RequestExit()` 返回后进程仍活着；面板里有未保存设置时同样拦下。
- **字数按正文算，不能拿 Markdown 文本长度代替**：`noteMd.length` 把 `# `、`**`、链接 URL
  都算进去（实测同一篇 `chars=10` / `textChars=7`）。取 ProseMirror 的
  `doc.textBetween(0, doc.content.size, '\n', '\n').length`，与旧版 RichEdit 的纯文本字数同源。
  **已实测**（2026-10-23，探针读 `__swnote.getState()` 与底栏文本）。
- **「能力还在」不等于「用户能用」**：迁移后 `FontService` 仍读写配置、`Font.Changed` 也有
  订阅者，但热键表里的三条入口丢了 —— 用户只能改 ini（表现成「字体和以前割裂」）。
  判断某个能力是否可用要看**入口**（热键 / 面板字段），不能只看 Service 与事件链。
  **已实测**（2026-10-23：恢复 `Alt+Shift+T` / `Alt+=` / `Alt+-` 后，`FontIndex` 真的会变，
  `--sw-ed-font` 也跟着从「楷体」变「华文行楷」）。
- **Markdown 表格必须锁成 pipe table**：pandoc 的 markdown writer 会按内容挑
  grid / multiline / simple 三种表格，而 GFM（Obsidian / Milkdown）只认 pipe table。
  **已实测**（pandoc 3.8，2026-10-23，同一份 HTML）：默认输出 multiline
  （`  A   B` + `  --- ---`），加 `-t markdown-grid_tables-multiline_tables-simple_tables`
  才变成 `| A | B |`。合并单元格在 GFM 里表达不了，pandoc 会退回 `<table>` HTML
  —— 内容保留、编辑器未必渲染，所以转换侧必须给警告，不能静默降级。
- **楷体没有粗体，字重 600 会「合成加粗」**：浏览器把 600 映射到 bold 并伪造笔画，
  结果是标题发粗、发虚（用户报「字体有异常」的一半）。要层次就调字号，
  字重停在 500（100–500 → normal）。**已实测**（2026-10-23，笔记窗标题）。
- **编辑区不能挂 `backdrop-filter`**：Chromium 每次输入 / 滚动都要重算整片模糊，
  实际表现就是「打字时闪、画面轻轻抖」。笔记页 `html[data-style] .main.note` 已改成
  `backdrop-filter: none` —— 它背后就是 body 自己的底色，模糊收益≈0。
  **已实测**（2026-10-23，真机读 `mainFilter=none`）。
- **滚动条会让正文横向重排**：`.sw-editor` 内容一旦超过一屏，滚动条出现会吃掉约 17px，
  整页文字重排（看起来像「窗口抖了一下」）。固定用 `scrollbar-gutter: stable`。
  **已实测**（2026-10-23，真机读 `gutter=stable`）。
- **文字层的底色必须不透明**：`.main.note` 原来叠了两层渐变（0.075/0.02）+ 半透明，
  背后 body 的光雾透上来，内容一滚动就出现「这段亮、那段暗」的割裂
  （用户原话：「像有一层黑色遮罩，打字区有晕染」）。文字区用 `var(--sw-bg)` 实心底，
  玻璃感只放在板外那圈光。**已实测**（2026-10-23，`backgroundColor = rgb(46,46,46)`）。
- **旧笔记里的行尾 `\` 与 `&#x20;` 必须归一**：前者是 Markdown 的「硬换行」标记，
  Milkdown 既不把它当换行、也不隐藏它 —— 编辑器里**直接显示反斜杠**，保存时又写回文件；
  后者是行首空格被转义的样子，同样会原样显示。`toDisplayMarkdown` / `toStoredMarkdown`
  现在统一走 `normalizeLegacyMarkdown`：行尾 `\` → 段落分隔（空行）、`&#x20;` → 空格，
  只处理围栏代码块之外。**已实测**（2026-10-23：`line1\ / line2\ / &#x20;line3`
  → 3 个独立段落，DOM 与落盘均无 `\` / `&#x20;`）。
- **首行不要加粗**：`# 📅 2026-10-23 速记` 被整行加粗后会存成 `# **# 📅 … 速记**`，
  渲染出来就是两个 `#`（第二个在加粗里）。首行保留原始格式即可。
- **原生 Markdown 输入规则要保留**：`# ` 变标题、`- ` 变列表、`**x**` 变加粗、`---` 变分隔线
  —— 这是 Obsidian 一类软件的默认体验，不能因为换成浏览器渲染就丢掉（用户 2026-10-23 明确要求）。
  真正让「字体像换了一种」的是**合成粗体**：楷体没有 bold，600+ 会让浏览器伪造笔画。
  解法是压字重（标题与 `strong` 都用 500），层级靠字号 / 亮度表达。
  **已实测**（2026-10-23：`# test` → `h1count=1`；`strong` 计算字重 = 500）。
- **WebView2 的虚拟主机有 HTTP 缓存**：`app.local` 的 `index.html` / `index.css` 会被缓存，
  构建后 URL 不变就可能一直加载旧文件 —— 表现是「改了前端、重启也没变」。
  `WebWindow._Mount` 现在给 URL 加 `_=<tick>`。**推断**（按 WebView2 行为判断，
  本次预防性加上；出现「改了没生效」时先怀疑它）。
- **状态行靠右用 `margin-left: auto`**：底栏只有「日期 + 状态」两格时，
  `justify-content: space-between` 会把状态**顶在中间**（看着像居中，而不是右对齐）；
  `margin-left: auto` 才能把它推到行尾。**已实测**（2026-10-23：
  `stRight=500` / 底栏 `footRight=522`）。
- **`ToolTip` 没有「右对齐」**（备查）：坐标是文字块左上角，要贴屏幕角得先显示、
  `WinGetPos` 量尺寸再 `WinMove`。本项目试过「保存提示放屏幕右下角」，用户改回
  **底栏右侧**（2026-10-23），这段留作以后要贴角时的做法。
- **状态提示要有寿命**：旧版 StatusBar 2 秒后清空，常驻的提示会变成「死板的装饰」。
  `setStatus` 2.2 秒后清空（**错误不清**）；切日期另行推一条
  「已切换到 2026-10-24 周六」（不带箭头 —— 用户 2026-10-23 要求去掉）。
  **已实测**（2026-10-23）。
- **同一片区域里别再叠第二层 scrim**：板面已是不透明底色时，`.ProseMirror` 再压
  `rgba(0,0,0,.05)` 会让「编辑区 / 滚动条槽位 / 内边距」差一档灰；
  `::before` 的 `inset 0 0 46px` 内雾则会让边缘比中间亮。两处都已去掉
  （v2.16）。**已实测**：`editorBg = rgba(0,0,0,0)`、`plateBg = rgb(46,46,46)`。
- **「减少动态效果」开着时，动画不能当反馈**：这台机器
  `prefers-reduced-motion: reduce` 实测为 **true**，CSS 动画一律不播放；
  状态行若只靠闪动，用户会觉得「按了没反应」。保存状态直接报 `已保存 HH:mm`
  （不区分有没有改动）才是可靠证据。**已实测**（2026-10-23）。
- **「旧版补出来的快捷键」要跟着媒介一起退役**：`Ctrl+H`（插 `---` 文本）与
  `Ctrl+Shift+H`（插「新分段」文本）在纯文本 RichEdit 里是必要的，在 Markdown 里
  直接打 `---` / `## ` 就会渲染 —— 快捷键反而多一步，还要求先选中占位文字。
  v2.16 删除（2026-10-23 用户反馈）。**已实测**：派发这两个键后 markdown 不再变化，
  `Ctrl+T` 仍会插入时间戳。
- **Milkdown 的空段落会落成 `<br />`**：同一篇笔记里于是「有的空行是空行、有的是
  HTML 换行」，观感不一致。`toStoredMarkdown` 现在删掉独占一行的 `<br />`、把连续空行
  压成一个，**并且只对围栏代码块之外生效**（代码块里的空行是内容）。
  **已实测**（2026-10-23：`para1 / <br /> / para2 / 3 空行 / para3` → 三行正文；
  `~~~` 代码块内空行原样保留）。
- **保存失败会拦住退出**：锁住目标文件（`FileShare.None`）后触发退出，`WriteFile` 走
  「临时文件 → 替换」，替换失败返回 false → `ExitCheck` 拒绝放行，`_error.log` 写明
  「笔记没能保存（无法写入 …）」。**已实测**（2026-10-23，真机 + 独占锁，操作的是副本）。
- **上下文热键条件不满足时完全无声**：用户按了没反应，第一反应是「功能坏了」。
  排查顺序：① 程序是否在跑；② 前台窗口类名是否落在 ctx 里；③ 再看 `_error.log`。
  **已实测**（2026-10-23：`Alt+M` 只在 `CabinetWClass` 生效，在桌面 `Progman` 上按毫无反应；
  把桌面加进 ctx 后至少能给出「请去资源管理器选中文件」的说明）。
  推论：**凡是 ctx 热键，条件不满足时必须能被解释** —— 要么扩 ctx（如桌面），
  要么在文档/面板里写清「在哪用」；别让它静默放行。
- **探针失败路径必须自己收掉进程**：探针里排了「等标记 → 执行 RequestExit → 保存」这种
  时序动作时，外部脚本一旦中途抛错、没 `Stop-Process`，探针会在超时后**照常执行**，
  把测试内容写进真实笔记（实测：2026-10-23 往当天笔记追加了一个 `probe-lock` 段落，
  已按字节恢复 39 → 27）。要碰真实数据目录的探针，要么只对临时副本动手，要么保证
  失败路径也杀进程。**已实测**。
- **写入走「同目录临时文件 → 写完替换」**，不要 `FileOpen(path, "w")` —— 它先把原文件
  截断成 0 字节再写，中途失败就是空文件。
- **读失败不能静默回退成空笔记**：那等于 40 行笔记换一行标题。区分「没文件」/「读不出」/「读到」。
- **「没改动就不写盘」要大小写敏感比较**（`==`），否则只改英文大小写会被判成没改。
- **空笔记不落盘**，但「编辑器返回空串」必须与「页面还没就绪」分开 —— 分不开时**宁可拒绝保存**，
  也不能把未就绪的空内容当「用户清空」去删文件。
- **改名会让磁盘路径变掉**：会话里的路径必须同步，否则下次保存按旧路径另写一份。

## 6. 验证方法

- **单测 include 了，生产没 include**：`CommandLine` 只进了 `tests\RunTests.ahk`，主脚本漏了；
  13 条测试全绿，真机按 `Alt+Shift+1` 却报「局部变量未赋值」。→ 新增能力 / 服务后，
  除了 tests include，必须检查 `src\SevenWork.ahk` 的 include 闭包；真机启动 + **实际热键**仍是最后一道。

- **语法预检有盲区**：注入 `ExitApp()` 跑一遍只能查出 auto-execute 段的错，**class 体内的错抓不到**
  （漏个逗号照样退出码 0）。所以**必须再真机启动一次**。
- **判退出码要用 `Start-Process -Wait -PassThru`**：AHK 是 GUI 子系统程序，`&` 调用不等它，
  `$LASTEXITCODE` 保留旧值，看起来「全部通过」。
- **窗口没出来 ≠ 出错**：主窗口默认不显示，`vis=False / 0x0` 是正常的。
- **探针要放 `src\`**（相对 `#Include` 要找得到），驱动插在 `ShowStartupTip()` 之后，
  别追加到文件末尾。**跑前备份 `_config.ini`** —— 没有开发身份隔离，探针读写的就是生产配置。
- **验证完立刻删探针**，并确认没有残留进程。
- **改前端行为要验往返**（`roundtrip-same`）：写出去再读回来不变形，比看截图可靠。

## 7. 资料怎么记

- **四份东西各管一件事**：意图书（往哪走）、状态卡（下次从哪接）、经验包（别再踩）、
  README（对外解释）。历史交给 `git log`，原始对话在仓库外。
- **状态卡只覆盖、不追加**：写下的进度一旦停更就开始说谎，所以宁可短。
- **最严重的文档问题不是「太长」，而是「不是同一代」**：代码已经换成 A，文档还在讲 B，
  这种文档比没有更危险 —— 它会被当成事实。
- **数字必须带口径**（哪天的、怎么算的）；易变数字（行数）宁可不写。
- **结论分散在多处 = 必然不一致**：同一个问题只留一个归属，其余位置只放指针。

## 8. 平台能力的接口契约

- **只收数据**：需要窗口就收 `hwnd`，需要尺寸就收数字或 `Rect`；不要传业务类，
  也不让能力自己去找目标窗口。
- **失败返回结构体**：`{ok: true}` / `{ok: false, reason, error?}` —— 不弹框、不写业务日志、
  不抛未捕获异常，由调用方决定回退与记录。
- **坐标与尺寸一律物理像素**（与 `WinGetPos` / `WinMove` 同单位），只有直接喂
  `GuiControl.Move` 的渲染入口沿用逻辑单位，且必须在文档里写明。
- **`Rect` = `{x, y, w, h}`**，四个都是数字，缺字段视为调用方错误。
- **`Coordinator/` 不是 Capability**：它要读 `Config`、发事件、算业务几何，按定义就不是纯能力。

## 9. 已经算过账的方向（别再重新论证）

这些不是「不能做」，而是**做之前得先推翻下列理由**：

| 方向 | 当初否掉的理由 |
| --- | --- |
| 恢复 RTF 双写（`.rtf` 母版 + `.md` 副本） | 双份必然不同步，维护成本翻倍；且生产库 36 篇已 1:1 配对、`rtf-only = 0`，双写没有换来任何可读回的东西 |
| 恢复「开发身份」/ 双工作树 / `dev` 分支 | 两条分支指向同一个提交、源码零差异，却带出两份配置、两处日志、每次的搬运成本。隔离收益改成「跑探针前备份 `_config.ini`」 |
| 编辑区换回原生 RichEdit | 做不出现代排版，也留不住多窗口观感一致；已经为它付过一次迁移成本 |
| 系统级真玻璃（DWM / Acrylic） | 见第 4 节，被 WebView2 合成表面挡住 |
| 背景图主题（`BackdropService` 贴图 + `bg` / `bgAlpha`） | 同一块合成表面：`Static` + `SS_BITMAP` 贴在父窗口上，WebView2 客户区整片盖住，配了也看不见。「保主体 / 保明暗 / 保饱和」那套烘焙配方随之作废，别照旧文档重试；要装饰就改 `glass.css` |
| 在 AHK 侧重做编辑器自带的编辑热键 | 撤销 / 重做 / 删行 / 复制行 / 上下移行 / 回车全重复；只保留编辑器做不到的（v2.16 起仅剩时间戳 —— 分隔线与分段标题已删，Markdown 直接打 `---` / `## `） |
| 编辑器里的 Tab / Shift+Tab 缩进 | 普通段落里 `indent` 是空操作（四个空格在 Markdown 里就是代码块），`Shift+Tab` 只能删用户手打的空格 —— 两条都不达预期，却把 Tab 吞掉了。列表层级靠 `Ctrl+Alt+7/8` 建列表 + 回车自动续项，再往上是 Markdown 语法本身的事 |
| 笔记模块的热键走 `global` | 字体 / 字号 / 切日期改的都是「当前这篇」，`global` 会在**任何程序里静默截键**：Excel 里按 `Alt+↑` 会先存盘再切到前一天，用户不知道笔记被切走了。v2.17 收窄成 `editor` 上下文，只有 `Alt+Z` 保持 `global`（窗口藏着也得能叫出来） |
| 让窗口回到原生控件 + 染色 | 原生控件只能染色、没有材质；新窗口一律走 `WebWindow` |
| 伙伴窗口适配（`Launcher.Preparing/Opened/Failed` + `PeerCoordinator` + `PeerLayoutService`） | 已由三区域取代（2026-10-24）：让位 / 堆叠 / 冻结那套要维护「谁动谁适配」，而笔记一旦固定落记录区就不再需要联动。新窗口只调 `ZoneService.Place` |
| 所有窗口强制填满区域 | **例外已收窄（2026-10-24）**：终端高度归 Windows Terminal profile、浏览器会被 Edge 的 `--window-size` 吸附 —— 这两类保持锚定；**文件 / 应用槽位反过来必须填满 + 300/900/1600ms 复核**，否则它们会恢复上次尺寸、越区或向上漂移（Everything / Explorer 已实测稳定） |
| 一键启动（暂缓，不是否掉） | 串行启动会占住热键线程（终端 15s、浏览器 15s）；先要解决异步模型，否则一按 Alt+V 十几秒没反应 |

## 10. 编译与分发

- **Ahk2Exe 编译根启动器可行**：先编译仓库根 `SevenWork.ahk`（它 `#Include src\SevenWork.ahk`），
  而不是只编译 `src` 入口；产物 `SevenWork.exe` 约 1.5MB。
- **编译版显式找 loader**：`WebHostService.Mount` 先找 `A_ScriptDir\WebView2Loader.dll`，
  找不到才回退库的 `src\lib\WebView2\64bit` 路径；发布 staging 必须把 loader 放在 exe 同级。
- **`web/dist` 放 exe 同级 `web\dist`**：`WebHostService.DistDir()` 已支持；不要把整棵
  `web/dist` 塞进 `FileInstall`。
- **Pandoc 不要 FileInstall**：150~230MB、构建机路径、GPL 分发义务都不划算；
  它只服务 `Alt+M`，按需探测 Path / sidecar 即可，缺失时明确降级。
- **WebView2 Runtime 是硬依赖**：检查 `EdgeUpdate\Clients\{F3017226-...}` 的 `pv`；
  loader 不是 runtime，二者别混。Win11 通常自带，Win10 需要用户安装。
- **编译版 smoke 必测**：启动 compiled exe → `Alt+S` 面板 → `Alt+Shift+S` 退出；
  验证 `web/dist`、loader、运行时探测都真的在 exe 环境生效。**已实测（2026-10-25）**。
- **`Ahk2Exe /compress 1|2` 对 v2 x64 base 无效**：2026-10-28 实测三种写法（不传 / 1 / 2），
  产物都是 **1,523,200 字节**，差异只来自脚本内容。别再指望「去掉压缩壳能降误报」。
- **未签名的 exe 即使没有 MOTW 也会被拦**：本机编译、`Zone.Identifier` 不存在的
  `SevenWork.exe`，照样弹「打开文件 - 安全警告：无法验证发布者」或 SmartScreen 蓝色拦截。
  判定依据是**签名 + 声誉**，与文件损坏、压缩壳、编译方式无关 → **重编译不解决**；
  而且每次重编哈希都变，用户点过的「运行」记录随之失效、提示重来。
  根治只有代码签名；日常自用直接双击源码 `SevenWork.ahk`，编译版留给没装 AHK 的机器。
- **`Start-Process` 启动未签名 exe 会被安全警告卡住**：它走 ShellExecute，弹框时调用不返回
  （命令看起来像卡死）。自动化验收改用
  `New-Object System.Diagnostics.ProcessStartInfo` + `UseShellExecute = $false` 直接 CreateProcess。**已实测（2026-10-28）**。
- **目录带 Low 完整性标签会把编译版进程降权 → 一切「静默」**（2026-10-28 实测）。
  仓库原在 `D:\...\02-GitHubFiles\` 下，该层被显式设成 `Mandatory Label\Low Mandatory Level`
  （`icacls` 可见；没有 `(I)` 表示在本层设置，其余子项全是继承）。exe 继承该标签后
  `CreateProcess` 以 **Low IL** 启动（实测 4096；同一份代码用解释器跑是 8192/Medium）→
  **写 `%AppData%` / `%LocalAppData%` 全被拒**，于是同时出现三个「查不到原因」的症状：
  · `_error.log` 一条不写（`LogError` 自己被拒，静默失败）→ 表现为「无日志、无报错」；
  · WebView2 创建返回 `0x800700AA 请求的资源在使用中`（真实原因是 profile 写不进去）→
    表现为「进程在、0 个 WebView2 子进程、窗口空白」；
  · 源码版**完全正常**（进程 IL 由 `AutoHotkey64.exe` 决定，与脚本文件标签无关）。
  **判断**：`icacls <目录>` 看 `Mandatory Label`；`Get-Process` 读不到 IL，要用
  `OpenProcessToken` + `GetTokenInformation(TokenIntegrityLevel=25)` 取 RID
  （4096=Low / 8192=Medium / 12288=High）。
  **修复**：管理员执行 `icacls <目录> /setintegritylevel (OI)(CI)Medium /T`
  —— 普通用户会报「拒绝访问」（需要 `SeRelabelPrivilege`）。
  ⚠ **只改单个 exe 不够**：父目录标签还在，下次构建的新 exe 会重新继承。
  ⚠ **只改项目紧邻的那层也不够**：`02-GitHubFiles` 这种「容器目录」自己带标签时，
  在它下面**直接新建**的项目会重新继承 —— 把容器层一起改掉才算收口（2026-10-28 实测）。
  ⚠ 这解释了「换个目录放项目后编译版就废了」：问题不在路径本身，而在新目录的完整性标签。

## 11. 演示与录屏

- **双显卡笔记本上，OBS 跑在独显会录出黑屏**：本机 RTX 4060 + Intel UHD，
  `monitor_capture` 选到 2560×1600 显示器仍 `sourceWidth=0`，截图纯白 / 视频纯黑。
  在 Windows「图形设置」把 `obs64.exe` 设为**省电 / 集显**并重启 OBS 后，
  同一源立刻出画面。**已实测（2026-10-24，OBS 32.2.2 / Win11 25H2）**。
- **OBS `StopRecord` 的响应早于文件落盘**：紧接着 `rename` / `copy` 会得到 0KB，
  源文件仍在后台继续写。`demo-obs.mjs` 在 stop 里等大小非零且连续稳定 500ms 再搬；
  下一段 start 也先等 `outputActive=false`。**已实测**。
- **外部 AHK 驱动要用 `SendLevel(1)`**：`HotIf` 上下文热键走键盘钩子，默认会忽略同脚本
  / 低级别注入事件；独立进程 + `SendLevel(1)` + `SendMode("Input")` 可触发，
  已用 `Ctrl+G` / `Ctrl+N` / `Esc` 验证。
- **别让录屏拍进真实工作内容**：驱动启动前用 `Shell.Application.ToggleDesktop()`
  收起其它窗口，结束后再 toggle 恢复；否则左侧的 VS Code / 真实笔记会进画面。
- **Obsidian 不认 `Obsidian.exe <vault>`**：它按 `%AppData%\obsidian\obsidian.json`
  里 `open=true` 的 vault 启动。演示脚本先备份该 json，注册临时 Vault 为唯一 open，
  结束后还原；真实 Obsidian 必须先关。**已实测**（标题 `工作台演示 - ObsidianVault`）。
- **窗口标题匹配要带 class**：OBS 标题含 profile 名 `SevenNoteJourneyCapture`，
  `WinWait("SevenNote")` 会先抓到 OBS。演示驱动用
  `SevenNote ahk_class AutoHotkeyGUI`，并在录制前最小化 OBS。
- **本地录制偏暗先查 OBS Color Range，不是先调显示器亮度**：本机 profile 原为
  `ColorRange=Partial`，同一段 05 素材抽帧平均亮度约 **76**、`yuv420p(tv)`；
  改成 `Full` 后约 **114**、`yuvj420p(pc)`。这是色彩范围不一致，不是壁纸或背光。
  录制本地 mp4 用 Full；要发平台再换回 Partial。**已实测（2026-10-25）**。
- **浅色壁纸不能只改 `HKCU\\Control Panel\\Desktop\\WallPaper`**：Windows 的
  自定义主题会把实际壁纸拉回 OEM 文件；直接改注册表截图仍是旧壁纸。演示环境
  要么改主题 / 壁纸文件并完整恢复，要么不要拿壁纸当提亮手段。
