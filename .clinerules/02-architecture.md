# 02 · 架构约定（分层 + 组合根）

## 铁律

```
┌─────────────────────────────────────────────────────┐
│ FEATURE  功能层（21 项，按用户旅程排列）             │
│  · Feature 之间零调用，通过 EventBus 通信            │
│  · 可插拔：删除任一 Feature 不影响其他               │
├─────────────────────────────────────────────────────┤
│ SERVICE  服务层（业务策略，可读 Config / State）      │
│  · 被多个 Feature 共用                               │
├─────────────────────────────────────────────────────┤
│ CAPABILITY 平台能力（WorkBench/Capabilities/）        │
│  · 纯能力：不读 Config / State，不发 EventBus         │
│  · 只收 hwnd / 数字 / Rect，失败返回 {ok, reason}     │
│  · 不认识 modules/*，不调用 LogError                  │
├─────────────────────────────────────────────────────┤
│ KERNEL   骨架层（生命周期 / 状态 / 事件 / 配置）      │
│  · 冻结，只加不改                                    │
└─────────────────────────────────────────────────────┘

依赖方向：
  Feature / Module → Service → Kernel → OS
  Feature / Module → Capability → OS
  Coordinator → Capability + Config + EventBus
严禁反向：Capability 不得引用 modules/*、EventBus、业务 Config / State。

Kernel 唯一的「回头出口」是**注入**：`EventBus` 不认识 `LogError` / `Config`，订阅者出错时
调的是组合根塞进来的 `_sink`（`EventBus.SetErrorSink(LogError)`；没注入则退回 `OutputDebug`）。
将来 Kernel 里任何需要「向上报告」的场合都照此办理 —— **不要在 Kernel 里直接写 `LogError(...)`**。
⚠ 调用属性里存的函数**必须先取到局部变量**：`sink := this._sink` 再 `sink(msg)`；AHK v2 的
`obj.prop(args)` 走方法查找、不会调用属性里的 `Func`（实测抛 `Too many parameters passed to function`，
且会被包裹它的 `try` 吞掉），详见 `03-ahk-v2` 的踩坑表。
```

`Coordinator/` 是跨模块协调（读业务上下文、发事件、算几何），**不属于** Capability；
`PeerCoordinator` 保留在 `Coordinator/`，只把纯算式委托给 `RectMath` / `WindowProbe`。

## 源码目录

运行代码统一收在 **`src/`**：

- 根 `SevenWork.ahk` 只是启动器，`#Include src\SevenWork.ahk`；
- 组合根在 `src/SevenWork.ahk`，平台层在 `src/WorkBench/`，
  模块在 `src/modules/<模块名>/`；
- 平台能力在 `src/WorkBench/Capabilities/<领域>/`（当前 `Placement/` / `Graphics/` / `Shell/` / `Document/`）；
  跨模块协调在 `src/WorkBench/Coordinator/`；
- `src/SevenWork.ahk` 内部的 `#Include WorkBench\...` / `modules\...` 是相对路径，
  以**该文件所在目录**为基准，别改成从项目根起算。
- 配置与日志都恒落 `%AppData%\SevenWork\`（`_config.ini` + `_error.log`）—— v2.14 起取消
  「开发身份」，没有 `.logs\` 分支。**探针脚本读写的也是这份生产配置**，跑之前先备份
  `_config.ini`，见 `.clinerules/04`。

## 改动原则

1. **不动 Kernel；业务规则只加 Feature，纯平台能力只加 Capability。**
2. Feature 之间**零调用**，一律通过 `EventBus.Emit` 通信。
3. 可插拔：删除任一 Feature 不得影响其他 Feature。
4. 依赖方向**严禁反向**（Kernel 不许调 Service，Service 不许调 Feature，
   Capability 不许调 modules / EventBus / 业务 Config / State）。
5. **能力层只收数据**：hwnd、数字、`Rect`；失败返回 `{ok:false, reason}`，
   由 Feature / Module 决定回退与日志。详细契约见 `docs/CAPABILITIES.md`。

## 加新模块的标准步骤（两处）

模块 = 计算机能力面上的一个占位（有窗口 = 容器，无窗口 = 加速器）。
新建 `src/modules/<名字>/<名字>Module.ahk` 后，**改两处**：

```ahk
#Include modules\<名字>\<名字>Module.ahk   ; ① src\SevenWork.ahk 的 #Include 区
ModuleRegistry.Register(<名字>Module)      ; ② WorkBench.Init() 内
```

模块自己的 `Services/` / `Features/` 也要在**自己那一块** `#Include`（照 Text / Folders 的写法：
Service 行、Feature 行、Module 行，**模块类必须最后引入**）。除此之外组合根不动 ——
启动 / 热键 / 兜底全由 `ModuleRegistry` 与 `HotkeyRouter` 遍历。

模块类约定：`static Id` / `static Name` / `static Init()`（必填），
`GetHotkeys()` / `GetContexts()` / `GetMetadata()` / `GetSettingsSpec()`（可选）。

`GetMetadata()` 返回 `{name, desc, order, hotkeys}` —— `Alt+S` 面板左列的名字、排序、
以及该页的热键清单都从这来；不实现会退回「用 `Id` 当名字、`order = 100`」。

热键上下文**由模块自己声明**（`GetContexts()` 返回 `{名字: 表达式}`），不要再改 `HotkeyRouter` ——
v2.6 起它遍历各模块报上来的名字来注册。⚠ 声明了却没人提供实现的 ctx，它的热键**一条都不注册**
并写 `_error.log`；让它退回 `HotIf()` 更糟 —— 那就把 `Esc` / `Enter` 变成全系统热键了。

- `Init()` 只做「内部就绪」——订阅事件、准备 Feature，**不碰窗口**；
- `Start()`（可选）做「对外可见」——加载内容、恢复配置，**必须晚于热键注册**
  （否则窗口先露面、热键还没就位，按 `Alt+Z` 会「没反应」）。

组合根不再逐个手写模块名：`ModuleRegistry.InitAll()` → `HotkeyRouter.RegisterAll()` →
`ModuleRegistry.StartAll()`。某个模块 `Init` 抛错只记 `_error.log` 并在 `_failed` 里留名
（**它的热键不注册**），其余模块照常启动 —— 失败不带走别人。

### WebView2 窗口：一律走 `WebWindow`

v2.10 起平台界面是一张网页。凡是「装网页的窗口」，**不要自己写生命周期** —— 用
`src\WorkBench\WebWindow.ahk`，它把踩过的坑都封在里面（隐藏态挂载白屏、先 `Show` 再 `WinMove`
会飘、Esc 只能靠 `HotIfWinActive` 钩子）：

````ahk
static _win := ""
static _Window() {
    if !IsObject(this._win)
        this._win := WebWindow({title: Config.AppName . " · 提示词库"
            , w: 620, h: 520, view: "prompts", dataDir: "prompts"
            , handlers: PromptHostHandlers, place: "topright"})
    return this._win
}
````

- **`dataDir` 必须逐窗不同**：同一个 user data folder 建不出第二个 `CoreWebView2Environment`，
  而失败藏在 `await()` 里 —— 只表现为「窗口一片纯底色」；
- **`view`** 落到 `web/src/App.vue` 的 `?view=` 分发（`lab` / `panel`，其余走笔记编辑器）；
  加一个窗口 = 在 `App.vue` 加一个 `v-else-if` 分支 + 一个组件；
- **`handlers`** 传**函数**（不是方法表）：骨架在挂载时调它，每个窗口的 hostObjects 是独立一张表；
- **Esc 归骨架**，回调要写成**变参** `(*) => …` —— 零参闭包报 `Invalid callback function`；
- **字段名不能与类里的方法同名、也不能声明在类体里** —— 两者都报 `Property is read-only`
  （见 `03-ahk-v2` 踩坑表）。


### 面板布局：侧栏 / 内容区

`WebPanelUI`（AHK 侧）+ `web/src/components/PanelView.vue` 是**唯一的平台界面**，
结构照通用控制面板（VS Code 设置 / Windows 设置）来。v2.9 起它是一张网页 ——
原生 `Gui` 做不出 `backdrop-filter`，面板要与笔记窗穿同一套玻璃材质，只能搬进 WebView2。

面板 940x700，两块**独立玻璃板**（各占一栏，中间留缝、四周留边 —— 板外留边才有玻璃感，
满窗均匀柔光又变回一块深色主题，S1 踩过这个坑）：

```
┌ 导航 216 ────────┐  ┌ 内容 ──────────────────────────────────┐
│ ● SevenWork  v2.9│  │ 全部热键                               │  ← 页眉 24px/600
│ ≡ 全部热键    24 │  │ 所有模块的热键汇总 · 按分组排列         │  ← 副标题 12px 灰
│   笔记         7 │  │ 【分组】                                │
│   键位         1 │  │  Alt+S      工作台面板（帮助 + 设置）  │  ← 键名定宽 100px
│   外部程序     2 │  │  Alt+T      循环切换界面主题           │
│   文件夹       4 │  │ ─────────────────────────────────────│
│   文本         7 │  │ 文件夹槽位 / 说明                       │
│ 5 个模块·共24 条 │  │ Alt+1 → [____________] [浏览…]         │
└──────────────────┘  │ 状态行      D:\…\Vault   [保存][关闭] │  ← 底栏
                      └────────────────────────────────────────┘
```

- **材质在 `glass.css`，结构在 `PanelView.vue`**：玻璃板的背景 / 模糊写成全局的
  `html[data-style='glass'] .pnav`（specificity `0,2,1`），组件 scoped 里只留一层
  `--sw-bg-alt` 兜底（编成 `.pnav[data-v-x]` = `0,2,0`）—— 刚好盖得住。
- **两块板各有 `::before`（1px 环边）/ `::after`（specular）**，别再往 `.pnav` / `.pmain`
  身上加伪元素（同 `.side` / `.card` 的坑）。
- **标题分两级**：页眉（模块名 / 「全部热键」）+ 副标题（模块 `desc`）。别挤回一行 ——
  一行里两种字号层级就没了。正文里**不重复**模块名与描述。
- **`≡ 全部热键` 是视图，其余是模块** —— 靠 `≡` 前缀 + 右侧「本页热键条数」区分。
  视图的条数含**平台级**热键（`Alt+S` / `Alt+T` 等），所以比各模块之和多；页脚用同一口径，
  别一处写 40、另一处写 42。
- **数据一次取完**（`ahk.getPanel()` → `PanelData.Json()`；实测 24 条热键 = 3450 字符）：
  切页是纯前端行为，来回过 hostObjects 每趟都是一次跨进程 COM 调用。只有「保存 / 浏览」
  回 AHK，保存成功后前端再拉一次全量（模块可能在 `apply` 里把值规整过）。
- **顺序 = `order` 升序，同 `order` 按 `Id` 字典序**（`PanelData._ItemBefore`）——
  别让它取决于 `Map` 的遍历顺序，那会在加模块时悄悄变。
- 模块 `Init` 失败**仍占一行并标 `(失败)`**，点进去写明「热键未注册、修复后重启」。
  让失败的模块从列表里消失，等于让用户以为模块没了。「全部热键」视图**不列**它的热键
  （一条都没注册，列出来等于骗人）。
- **切页只有一条路径 `goto(id)`**：鼠标点 / 上下键 / AHK 的 `__swpanel.goto(id)` 全走它。
  首次打开走 `getPanel` 返回的 `focus` 字段（`ShowHelp(moduleId)` 记下的目标页）——
  比「导航完再 `Eval(goto)`」稳，那次可能落在页面脚本就绪之前、静默丢掉。
- **换主题不重建窗口**：原生版 30+ 控件逐块上色只能关掉重开、还会退回第一页；
  现在窗口底色 + 标题栏 + `--sw-*` 一趟推给页面，**停在哪页保持不变**。
- **关面板是 `Hide` 不是 `Destroy`**：WebView2 重建要 300ms 上下，而 `Alt+S` 是随手按的键。
  ⚠ 重新 `Show()` 后要补一次 `Resize()` —— 子窗口在父窗口隐藏期间尺寸停滞，
  回来会留一条旧尺寸的底色。
- **`Esc` 靠 `HotIfWinActive` 钩子**，不靠 `Gui` 的 `Escape` 事件：键盘焦点在 WebView2
  子窗口里，`Gui` 收不到那个事件。
- **底栏**：状态（绿 = 成 / 红 = 败 / 琥珀 = 提醒）+ 笔记目录 + 保存 + 关闭。
  没有它，按钮就「浮在空气里」，尤其没有设置字段的页、页尾一大片空白收不住。
- ⚠ **`WebHostService` 是多实例的**（v2.9 起）：面板与笔记窗各挂一份，`dataDir` 必须分开
  （同一 user data folder 建不出第二个 `CoreWebView2Environment`），
  **调用一律显式传 hwnd** —— 无参会落到「最近挂载的窗口」上，面板一开笔记窗就收不到尺寸。

### 模块设置：`GetSettingsSpec()`

模块想让用户在 `Alt+S` 面板里调参数，就实现它并返回**数据描述**，而不是控件：

```ahk
static GetSettingsSpec() {
    return {
        title:  "文件夹槽位",
        hint:   "热键固定，指向哪个目录可以随时换；留空表示该槽位未启用。",
        fields: [{key: "Slot1", label: "Alt+1 →", kind: "folder"
            , value: FolderSlotService.Get(1)}],
        apply:  (values) => FolderSlotService.SaveAll(values)
    }
}
```

- 平台只认 `{label, kind, value}` 三个字段，**不认识任何业务名词**（「槽位」是 Folders 自己的词）；
  `kind` 目前支持 `"folder"`（输入框 + 「浏览…」按钮 → 回调 AHK 的 `DirSelect`，
  `BIF_NEWDIALOGSTYLE` 带地址栏）与 `"text"`（缺省）；
- 字段还可以给**可选的 `placeholder`** —— 空输入框里的灰字提示（原生 `placeholder`）。
  只显示、**不进值**：不填直接保存写进去的仍是空串；
- `apply` 收到**按声明顺序排好的值数组**，由模块自己落盘并返回 `true` / `false`；
- 保存成功后平台会**重新拉一次全量数据** —— 模块可以在 `apply` 里把值规整成最终形态
  （去尾斜杠 / 空串归一），不回读的话输入框里还是用户刚敲的原始样子；
- 模块**不用管控件生命周期**：切页是前端换数据，页面只渲染当前 `row.spec`；
- 保存按钮自带三段反馈（`保存设置` → `保存中…` → `✓ 已保存` / `✗ 失败`），模块不用自己造；
- ⚠ 平台调用 `apply` 时先取局部变量再调（`fn := spec.apply` → `fn(values)`）：
  AHK v2 的 `obj.prop(args)` 走方法查找，属性里存的 `Func` 不会被调用（见 `03-ahk-v2`）。
- ⚠ **值固定走 8 个参数槽位**（`PanelHostApply(moduleId, v1 … v8)`）：hostObjects 走 IDispatch，
  变参（`args*`）在这种调用方式下不可靠，前端也拿不到「AHK 想要几个」。前端永远补满 8 个，
  AHK 侧只取前 `fields.Length` 个；超过 8 个字段要同步加长两边（目前最多的是文件夹的 3 个）。
- ⚠ **hostObjects 的方法键名不能叫 `apply`** —— JS 侧是 Proxy，`b['apply']` 先命中
  `Function.prototype.apply`，拿到的是原生函数、调用抛 `TypeError`，而调用点在 `try` 里，
  表现成「点保存没反应」。同类禁用名：`call` / `bind` / `toString` / `constructor` /
  `name` / `length` / `prototype`。实际用的是 `saveSettings`。
- ⚠ **前端失败要回写 AHK 日志**（`ahk.log(msg)` → `PanelHostLog`）：JS 侧错误只活在页面里，
  用户在真机上只会看到状态栏一行看不懂的字，而排错第一步是看 `_error.log`。
- ⚠ **`GetMetadata()` 必须给 `name`**：拿不到就退回用 `Id`（英文），面板左列会冒出
  `Text` 这种与其它中文条目格格不入的名字。`desc` 统一成「一句话功能 · 主热键」。

## 加新功能的标准步骤

0. 先判断是不是**跨模块复用的纯平台能力**：是 → 放 `WorkBench/Capabilities/<领域>/`，
   返回结构化结果；不是 → 继续下面。
1. 在 FEATURE 层新增一个 class
2. 在所属模块的 `GetHotkeys()` 里加热键（平台级热键归 `WorkBench.GetHotkeys()`；
   `HotkeyRouter` 注册与 `Alt+S` 帮助共用这份数据）
3. 通过 `EventBus.Emit` 通知结果

参考实现（README「开发指南」原文）：

```ahk
class ExportFeature {
    static ExportHtml() {
        hwnd := State.GetEd()
        rtfPath := NoteStoreService.RtfPath(State.GetDate())
        htmlPath := NoteStoreService.TempDir() . "\export.html"
        cmd := '"' . Config.PandocPath . '" "' . rtfPath . '" -o "' . htmlPath . '"'
        RunWait(A_ComSpec . ' /c "' . cmd . '"', , "Hide")
        Run(htmlPath)
    }
}
```

在模块的 `GetHotkeys()` 里加一行即可（`{ctx, key, group, line, fn}`）—— 不需要改任何其他
Feature，也不需要改组合根或帮助函数。

## 外观参数归谁

主题分**两层**，别混在一起：

| 层面 | 归属 | 管什么 |
| --- | --- | --- |
| **主题本身** | `WorkBench\Services\ThemeService`（平台服务） | 色板、材质风格、`Themes` 表、`Palette()` 派生、配置持久化、`Theme.Changed` 广播 |
| **调节入口** | `modules\Theme\ThemeModule`（模块） | 在 `Alt+S` 里让用户改**全局外观参数**：材质浓度 / 圆角 / 动效 / 密度 |

- 模块**不持有主题**、不建窗口、没有热键：只读写 `[Appearance]` 四个键；
- `Palette()` 读色板时把这些覆盖合并进去 —— **删掉模块，所有窗口照样上色**，只是没了调节入口；
- 反过来让 `ThemeService` 调模块，就是 Service → Module 的反向依赖，禁止。

写入后 `ThemeModule._Apply` **复用 `Theme.Changed`** 广播（不新开事件）：订阅者要做的事完全一样 ——
「按当前 `Palette()` 重刷一遍」，而且是**重刷不是重建**（窗口停在哪页、输入框里的字都不能动）。

⚠ 覆盖是**跨主题**的：调的是「同一个材质浓不浓 / 圆角多大 / 动多快」，不是「换成什么颜色」，换主题时保留。
将来做窗口类型差异（笔记正文更安静、提示词库更紧凑）要落在**类型默认值**那一层，别往这个全局页塞逐窗开关。

⚠ 圆角唯一能落地的地方是 `--sw-radius-lg`（`tokens.css` 定义、`applyTheme()` 覆盖）。
**别在 `glass.css` 里写死 px** —— 写死就等于把那个滑杆变成摆设（三窗那三处已改成 `var(--sw-radius-lg)`）。

## 加新主题

`src\WorkBench\Services\ThemeService.ahk` 的 `Themes` 数组加一行（**追加到末尾**）：

```ahk
{name: "暗夜黑", win: "1E1E1E", edBg: "252526", text: "D4D4D4", dim: "808080"},
```

加完 `Alt+T` 自动循环到新主题，无需改别处。**只给 4 个基色**（`win` / `edBg` / `text` /
`dim`）就够 —— `accent` / `border` / `panel` / `codeBg` 由 `Palette()` 按明暗派生；
要覆盖就在条目里自带同名字段。派生只写一处，前端 `--sw-*` 与 AHK 窗口拿的是同一份结果。

⚠ **主题表目前只有「哑光灰」一套**（护眼绿 / 纸白 / 星空 / 金克斯暂时下线）。只有一套时
`ThemeService.Next()` 是**空操作**：不写配置、不发 `Theme.Changed`；表里有第二套就自动恢复。
老配置的下标由 `_MigrateIndex()` 一次性归 1 并写回（`[Appearance] ThemeSchema=3`）。

### 带背景图的主题

> ⚠ **当前暂缓**：主题表里没有带 `bg` 的条目（星空 / 金克斯已下线），铺图机制
> （`BackdropService` / `BackdropFeature`）代码仍在。要接回来就按本节加一条 —— 别只在表里
> 塞 `bg` 而不管前端：`bg` / `bgAlpha` / `bgFit` 已推到前端，前端消费仍在打磨。

多一组可选字段：`bg`（图片绝对路径）、`bgAlpha`（压暗遮罩 0–100）、`bgFit`（可选，缺省 `cover`）。

```ahk
{name: "金克斯", win: "0B1624", edBg: "0B1624", text: "EAF2FF", dim: "93AACB"
    , bg: "D:\Pictures\jinx.png", bgAlpha: 0, bgFit: "cover"}
```

**必须守住的几点**（完整配方与实测账见 [`docs/THEME-IMAGES.md`](../docs/THEME-IMAGES.md)，
最短路线见 [`05-theme-image.md`](05-theme-image.md)）：

- **`bg` / `bgAlpha` 成对**：`BackdropFeature._Sync()` 见 `bg` 就读 `t.bgAlpha`，缺了抛「属性不存在」；
  `bgFit` 可选（`HasProp` 守卫），只有 `cover` / `contain` 两个值。
- **竖版 / 人物图先裁再铺，别用 `contain`**：按编辑区比例 0.917 裁好再 cover；`contain` 会缩进中间、两侧留底色。
- **`contain` 必须铺底色**：留边否则露出 GDI 未初始化位图（花屏）；`_Compose` 的 `FillRect` 只在 contain 分支执行。
- **`edBg` 兼两用**（遮罩色 + contain 留边色），必须与图的明暗同档。
- **配色从图取**（`tools\pick-theme-colors.ps1`，`win` = 均色 × 0.55）：暗图配近白字、亮图配深字。
  判据 WCAG 4.5:1 —— **亮字要背景 ≤ 118，深字要 ≥ 128**。
- **绝不为配深字整体提亮暗图**（那是把原图洗白）；动明暗只在 V 空间等比缩放 —— 混白会砍掉近一半饱和度。
- **烘图三步一步别省**：按 0.917 裁 → 缩到 2400 宽 + V 空间色调 → 成品尺寸 unsharp（`rebake-backdrop.ps1` 全包）。
  改脚本里的 C# 逻辑记得递增类名（见 `04-workflow`）。
- **只能追加到数组末尾**（`ThemeIndex` 存下标）；前一条结尾补 `},` —— 漏逗号报 `Unexpected "{"`，方案 A 预检查不出。
- **标题栏自动跟主题色**：`UiPaint.TitleBar` 按 `win` 亮度 < 128 决定 dark mode，Win11 用
  `DWMWA_CAPTION_COLOR` 染色（Win10 上 DllCall 静默失败、退回系统配色，不必判断版本）。
- **拉伸时文字「时隐时无」= 铺图时机**：`_ScheduleRender()`（`SetTimer -80` 合并抖动）+ `_RenderNow()`
  （同矩形跳过，真重铺才 `RedrawWindow`）；`_Apply` 走 `_RenderNow(true)` 绕防抖。
- **图与浓淡写在主题自己的 `bg` / `bgAlpha` 上**（v2.4.3 起删掉了全局覆盖键 `[Appearance] BackdropImage`）。
