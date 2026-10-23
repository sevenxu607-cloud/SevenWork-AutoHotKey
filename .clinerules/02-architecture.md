# 02 · 架构与边界

## 分层

| 层 | 位置 | 干什么 | 硬约束 |
| --- | --- | --- | --- |
| FEATURE | `src/modules/<模块>/Features/` | 一个用户旅程一个类 | 可插拔：删掉不影响其他 Feature |
| SERVICE | `src/modules/<模块>/Services/`、`src/WorkBench/Services/` | 业务策略，可读 Config / State | 不认识 Feature |
| CAPABILITY | `src/WorkBench/Capabilities/<领域>/` | 纯能力（摆放 / 图形 / Shell / 文档） | 只收 hwnd / 数字 / Rect，不读业务 |
| KERNEL | `src/WorkBench/Kernel/` | 配置 / 事件 / 状态 / 生命周期 | 冻结，只加不改 |
| 界面 | `web/src/`（Vue + Milkdown） | 编辑与面板 | 只经 hostObjects 与 AHK 通信 |

依赖方向：`Feature / Module → Service → Kernel → OS`，`Feature / Module → Capability → OS`。
**严禁反向**：Capability 不得引用 `modules/*`、`EventBus`、业务 Config / State、`LogError`。

`Coordinator/` 是跨模块协调（读业务上下文、发事件、算几何），**不属于** Capability。

## 组合根与启动顺序

- 根 `SevenWork.ahk` 只是启动器（保持 `A_ScriptDir` 指向项目根），组合根是 `src/SevenWork.ahk`；
- `src/` 内的 `#Include WorkBench\...` / `modules\...` 是**相对路径**，以该文件所在目录为基准，
  别改成从项目根起算；
- 顺序固定：`ModuleRegistry.InitAll()` → `HotkeyRouter.RegisterAll()` → `ModuleRegistry.StartAll()`；
- 某模块 `Init` 抛错只记日志、它的热键不注册，其余照常启动 —— **失败不带走别人**。

## 加新模块（改两处 + 自己的 include）

```ahk
#Include modules\<名字>\<名字>Module.ahk   ; ① src\SevenWork.ahk 的 #Include 区
ModuleRegistry.Register(<名字>Module)      ; ② WorkBench.Init() 内
```

模块自己的 `Services/` / `Features/` 在**自己那一块** include（Service 行、Feature 行、Module 行，
**模块类必须最后引入**）。

模块类约定：`static Id` / `static Name` / `static Init()` 必填；
`GetHotkeys()` / `GetContexts()` / `GetMetadata()` / `GetSettingsSpec()` / `Start()` 可选。
`GetMetadata()` 返回 `{name, desc, order, hotkeys}` —— 面板左列的名字、排序与热键清单都从这来；
不实现会退回「用 `Id` 当名字、`order = 100`」。

- `Init()` 只做内部就绪（订阅事件、准备 Feature），**不碰窗口**；
- `Start()` 做对外可见（加载内容、恢复配置），**必须晚于热键注册**（否则窗口先露面、热键还没就位）。

## 加新功能（三步）

1. 在所属模块的 FEATURE 层加一个类；
2. 在模块的 `GetHotkeys()` 加一行 `{ctx, key, group, line, fn}`（平台级热键归
   `WorkBench.GetHotkeys()`；注册与 `Alt+S` 面板共用这份数据）；
3. 用 `EventBus.Emit` 通知结果。

**跨模块零调用**；**同模块内**的兄弟 Feature 可以直接调 —— 它们共享模块生命周期，
绕事件只会多一层转发。

## 热键上下文由模块声明

`GetContexts()` 返回 `{名字: 表达式}`，`HotkeyRouter` 遍历各模块报上来的名字注册 —— 不要再改 Router。
⚠ 声明了 ctx 却没人实现，该模块热键**一条都不注册**并写日志；退回 `HotIf()` 更糟
（`Esc` / `Enter` 会变成全系统热键）。

## WebView2 窗口一律走 `WebWindow`

它封住了踩过的坑（隐藏态挂载白屏、先 `Show` 再 `WinMove` 会飘、Esc 收不到）：

```ahk
static _Window() {
    if !IsObject(this._win)
        this._win := WebWindow({title: ..., w: 620, h: 520, view: "prompts"
            , dataDir: "prompts", handlers: PromptHostHandlers, place: "topright"})
    return this._win
}
```

- **`dataDir` 逐窗不同**：同一 user data folder 建不出第二个 `CoreWebView2Environment`，
  失败藏在 `await()` 里、只表现为「窗口一片纯底色」；
- **`view`** 落到 `web/src/App.vue` 的 `?view=` 分发；加一个窗口 = 加一个 `v-else-if` + 一个组件；
- **`handlers` 传函数**（不是方法表）；**Esc 回调要写变参** `(*) => …`；
- **字段名不能与方法同名、也不能声明在类体里**（两类都是 `Property is read-only`）。

## 面板与模块设置

- `PanelData` 一次取完全量数据交给前端（`ahk.getPanel()`），切页是纯前端行为；
- 模块实现 `GetSettingsSpec()` 就能在面板里多一块设置区：
  `{title, hint, fields: [{key, label, kind, value}], apply: (values) => ...}` ——
  平台只认 `kind`（`text` / `folder` / `select` / `range`），不认识任何业务名词；
- **hostObjects 方法名不能撞 JS 内置**（`apply` / `call` / `bind` / `toString` / `constructor` …），
  本项目用 `saveSettings`；
- 值固定走 8 个参数槽位（前端补满 8 个），字段超过 8 个要两边同步加长；
- 保存成功后平台会重新拉一次全量数据 —— 模块可以在 `apply` 里把值规整成最终形态。

## 外观参数归谁

| 层面 | 归属 | 管什么 |
| --- | --- | --- |
| 主题本身 | `WorkBench\Services\ThemeService` | 色板、材质、`Palette()` 派生、持久化、`Theme.Changed` |
| 调节入口 | `modules\Theme\ThemeModule` | `[Appearance]` 四个全局参数 |

删掉模块，所有窗口照样上色 —— 反过来让 Service 调 Module 才是反向依赖。
写入后复用 `Theme.Changed` 广播（**重刷不是重建**：停在哪页、输入框里的字都不能动）。
圆角只能落在 `--sw-radius-lg`，**别在 `glass.css` 里写死 px**，否则滑杆就是个摆设。

## 改代码的五条判据

1. 不动 Kernel；业务规则加 Feature，纯平台能力加 Capability；
2. 跨模块走 `EventBus`，同模块可直接调；
3. 可插拔的检验方式是**删掉它**；
4. 依赖方向严禁反向；
5. 能力层只收数据，失败返回 `{ok:false, reason}`。
