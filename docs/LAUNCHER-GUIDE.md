# 接入一个外部窗口（落到区域）

> 2026-10-24 起：窗口不再「适配伙伴」，只认三块固定区域。
> 旧的 `Launcher.Preparing` / `Launcher.Opened` / `Launcher.Failed`、`PeerCoordinator`、
> `PeerLayoutService` 已删除；**不要照旧文档重写那套**。

## 三块区域

| 区域 | 谁在这 | 默认策略 |
| --- | --- | --- |
| 记录区 | 笔记 | 填满（`{fill: true}`） |
| 辅助区 | 终端、浏览器、提示词库、日期检索 | 应用锚定；浮层居中 |
| 工作区 | 文件槽位、应用槽位、其他程序 | 锚定（保留窗口尺寸） |

几何在 `WorkBench/Services/ZoneService`（`[Vision]` 配置）；纯计算在
`WorkBench/Capabilities/Placement/ZoneMath`。区域顺序：辅助区贴工作区右下，
记录区在它正上方、同宽，工作区是左侧剩余矩形。

## 接入步骤

1. 启动程序，轮询到 hwnd（认窗方式见下表）。
2. 显示窗口：`WinShow` → 若最小化再 `WinRestore` → `WinActivate`。
3. 落区：`ZoneService.Place(hwnd, "aux", {fill: false})`。
4. 登记：`ZoneService.Register(hwnd, "app", "aux", false)` —— `Alt+Shift+V` 靠它恢复布局。
5. 失败：写日志 / ToolTip，**不弹模态框**（模态框会挡住热键）。

示例（`PowerShellFeature._ShowAndFocus` 的骨架）：

```ahk
static _ShowAndFocus(hwnd) {
    try WinShow("ahk_id " . hwnd)
    ; Chromium 可能把自己标成最小化；WinShow 不解除最小化
    if DllCall("user32\IsIconic", "ptr", hwnd, "int")
        try WinRestore("ahk_id " . hwnd)
    try WinActivate("ahk_id " . hwnd)

    res := ZoneService.Place(hwnd, "aux", {fill: false, allowHidden: false})
    if !res.ok && res.reason != "not-placeable"
        && res.reason != "minimized" && res.reason != "no-zone"
        LogError("落辅助区失败：" . res.reason)

    ZoneService.Register(hwnd, "app", "aux", false)
}
```

浮层（提示词库 / 日期检索）不要 `Place` 锚定，用 `ZoneService.Center(hwnd, "aux")`：
它保留窗口自身尺寸；比辅助区宽时向左溢出，再夹到工作区右缘。

- WebView2 窗口：`WebWindow({place: "zone", zone: "aux"})`，由 `WebWindow._Place()` 居中。
- 原生 `Gui`：`Show("… Hide")` → `ZoneService.Center(hwnd, "aux")` → `Show()`。

## 认窗方式

| 方式 | 适用 | 注意 |
| --- | --- | --- |
| 窗口标题 | PowerShell 终端 | 标题必须唯一（`SevenWork PowerShell`） |
| 专用 profile + PID | DeepSeek 浏览器 | 独立进程树；详见 `DeepSeekFeature` |
| Shell 路径 | 资源管理器 | `ExplorerProbe.FindFor(path)`，不靠标题 |
| exe 文件名 | 应用槽位（任意 exe） | `CommandLine.ExeOf` 取第一段；多实例只取第一个 |

## 必须守住的点

| 点 | 为什么 |
| --- | --- |
| 隐藏 / 最小化守卫 | 对隐藏窗口 `WinMove` 会抛；最小化窗口的坐标是停放位 |
| 「可见 && 前台」才能隐藏 | `WinHide` 后 `GetForegroundWindow` 仍指向隐藏窗口，只判 `WinActive` 会再也呼不出来 |
| `WinShow` 后补 `WinRestore` | Chromium 实测必现：窗口回来了但仍是最小化 |
| 别给 `Run` 传 `"Hide"` | 会换掉宿主（Windows Terminal → conhost，配色 / 尺寸全变） |
| 物理像素 | `WinMove` / `WinGetPos` 同一单位；`Gui.Move` / `Gui.Show` 收逻辑单位 |
| 最大化窗口 | `PlacementExecutor` 会先 `IsZoomed → ShowWindow(SW_RESTORE)`；**未真机验** |
| 区域只保证落区 | 同区多窗口会重叠（终端与浏览器都在辅助区），不做堆叠 |
| UWP / 提权窗口 | 不支持：`ahk_exe` 认不到 UWP；提权窗口搬不动，返回失败 |

## 想改区域尺寸

第一版写死在 `_config.ini`：

```ini
[Vision]
AuxW=772
AuxH=1020
Right=15
Gap=6
Margin=10
```

改完重启程序（`ConfigService` 有进程内缓存）。面板暂不暴露这些参数 ——
先确认现有几何在用户屏幕上合意，再决定要不要做滑杆。
