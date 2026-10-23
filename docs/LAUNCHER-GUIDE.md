# 添加呼出外部窗口的功能（窗口自动适配）

> 从 `README.md` 拆出（2026-10-21）：伴生窗口适配契约的**机制、调参与实测账**。

`Alt+C` 呼出终端时，笔记窗口会自动退场、让出上半屏、与终端上下拼成一列 —— 这**不是为终端写死的**。
凡是「呼出一个外部窗口」的功能（资源管理器、Obsidian、浏览器、另一个编辑器…），都走同一份
**伴生窗口适配契约**（peer docking）：发布方只管广播三个生命周期事件，
`WindowFeature` 负责笔记窗口的让位 / 记忆 / 失败兜底；真正搬窗口由平台协调器
广播的 `SevenNote.Move` / `Launcher.Move` 执行，各模块只搬自己的窗口。

### 机制：三个生命周期事件 + 两个 Move 事件

```
发布方（你的 Feature）                    订阅方（WindowFeature）
  ── Launcher.Preparing ───────────────▶  笔记窗口退场（只在显示着时才收；仅首次）
  ── 启动外部程序 / 轮询等它露面 ──────▶
  ── Launcher.Opened {hwnd,x,y,w,h} ───▶  相撞才摆位、否则原地还回来（仅首次）
  ── Launcher.Failed ──────────────────▶  把刚才退场的笔记窗口还回来

平台 PeerCoordinator（只算几何）          执行方
  ── SevenNote.Move {hwnd,x,y,w,h} ────▶  WindowFeature._OnNoteMove()
  ── Launcher.Move  {hwnd,x,y,w,h} ────▶  LauncherModule._OnMove()
```

| 事件 | 何时发 | 带什么 | 反应 |
| --- | --- | --- | --- |
| `Launcher.Preparing` | 确定要启动了，**在外部窗口露面之前** | 无 | `_CollapseForLauncher()` 收起自己 —— **仅首次**，已适配过就什么都不做 |
| `Launcher.Opened` | 外部窗口已落位 | `{hwnd, x, y, w, h}` —— **真实**窗口矩形 | `_OnLauncherOpened()` → `_AdaptToPeer()`：与笔记原来待的地方**相撞才**摆位，否则原样还回来 —— 随后**冻结**，此后不再联动 |
| `Launcher.Failed` | 最终没起来 | 无 | `_RestoreAfterFailedLauncher()` 把自己还回来 |
| `SevenNote.Move` | 平台算出堆叠落点 | 物理外框 `{hwnd, x, y, w, h}` | `WindowFeature._OnNoteMove()` 搬笔记窗口 |
| `Launcher.Move` | 平台算出伙伴下移 | 物理外框 `{hwnd, x, y, w, h}` | `LauncherModule._OnMove()` 搬终端 / 浏览器窗口 |

> **Phase 5b**：旧的 `Peer.*` 桥接已移除。生命周期归 `Launcher.*`，执行路径归两个
> Move 事件；`PeerCoordinator` 只算几何，不跨模块 `WinMove`。

> **为什么"先收再摆"**：把「搬窗口」和「露面」拆成两件事。`Show()` 本来就支持**隐藏态下算好位置、
> 最后一次性露面**（见 `_PlaceWindow`）；若窗口已显示着去搬，平移会连着控件重排一起被看见 ——
> 观感就是「飘一下」。
>
> **⚠ 只在第一次**：这一整套（退场 → 摆位 → 露面）只在笔记窗口**还没有自己的格局**时跑一次。
> 跑完就置位 `WindowFeature._docked`，此后伙伴怎么呼出隐藏，笔记都一个坐标都不改 —— 位置尺寸
> 归用户自己管。而"要不要适配"看的是**相不相撞**：笔记原来待的地方与伙伴窗口有重叠才摆，
> 不重叠就原样还回来。于是「笔记放左边、终端在右下」这种各占一角的用法，从第一次起就互不打扰。
> 退出程序重开才会重置这一次（`_docked` 与位置记忆一样是纯内存的，不落盘）。

### 接入步骤

仓库里有两个现成的参考实现，都带完整注释，可直接对照：

| 参考 | 起什么 | 特殊在哪 |
| --- | --- | --- |
| `PowerShellFeature`（`Alt+C`） | 本机 PowerShell 终端 | 靠窗口标题认窗；**位置与宽度**由 `_PlaceLikeDeepSeek()` 对齐到与 DeepSeek / 笔记窗口同一处（只改宽，**高度仍归 Windows Terminal profile**） |
| `DeepSeekFeature`（`Alt+X`） | DeepSeek 网页（普通 Edge 窗口 + 专用 profile） | 得「自己认窗 + 自己定尺寸位置」，多出来的两处坑见下表与实例二 |

骨架长这样（`PowerShellFeature` 的简化版）：

```ahk
class MyWindowFeature {
    static Open() {
        ; ① 确定能起来之后才发 —— 早退分支不能白收一次笔记窗口
        EventBus.Emit("Launcher.Preparing")

        try {
            Run('"D:\我的程序\app.exe"')     ; ⚠ 第三个参数别传 "Hide"，见下表
        } catch {
            EventBus.Emit("Launcher.Failed")      ; ④ 起不来就还回去
            return
        }

        ; ② 等它的窗口出现（轮询要密：每档间隔都会叠进「按了没反应」的那段空白）
        deadline := A_TickCount + 15000
        while (A_TickCount < deadline) {
            if (hwnd := this._FindIt()) {
                WinShow("ahk_id " . hwnd)
                WinActivate("ahk_id " . hwnd)
                EventBus.Emit("Launcher.Opened", this._Rect(hwnd))   ; ③ 广播真实矩形
                WinActivate("ahk_id " . hwnd)                        ; 广播是同步的，还回前台
                return
            }
            Sleep(20)
        }
        EventBus.Emit("Launcher.Failed")          ; ④ 等满超时也算失败
    }
}
```

**完成。** `WindowFeature` / `LauncherModule` 的订阅都无需改 —— 生命周期事件负责让位、
堆叠、失败兜底与位置记忆，`SevenNote.Move` / `Launcher.Move` 负责真正搬窗口，
且第一次之后就不再打扰用户摆好的格局（见上文「⚠ 只在第一次」）。

### 必须守住的点

| 点 | 为什么 |
| --- | --- |
| **`Launcher.Opened` 必须带真实矩形** | 内部要按「可见边界」换算（`_InvisibleFrame` 用 `DwmGetWindowAttribute` 量），自己拼坐标拼不准 —— 窗口矩形比肉眼看到的多一圈不可见边框（本机实测左 −9 / 右 9 / 下 9） |
| **读矩形前开 `DetectHiddenWindows`** | 刚 `WinShow` 出来的窗口 `WS_VISIBLE` 可能仍是 `0`，此时 `WinGetPos` / `WinMove` **直接抛错**（默认忽略隐藏窗口）。用完恢复原值 `A_DetectHiddenWindows` |
| **`Launcher.Failed` 一定要有** | 少了它就是「按一下热键，屏幕上什么都不剩」—— 笔记窗口被收走却没还回来。`Run` 抛错和等满超时**两条**路径都要发 |
| **别给 `Run` 传第三参数 `"Hide"`** | 隐藏启动会绕过系统把程序委派给现代宿主的机制，程序退回默认宿主（实测：Windows Terminal 变 conhost，`120x50` + `#012456` 经典蓝）。**要藏就由笔记窗口让位，别去动对方的窗口** |
| **发布方别自己去摆笔记窗口** | 几何算法在 `PeerCoordinator.PlanStack()`，状态与位置记忆（`_StackWithPeer` / `_RememberPosition` / `_preStackRect`）在 `WindowFeature`。发布方越界改坐标会和记忆打架 |
| **`EventBus.Emit` 是同步的** | 广播那一行返回时笔记窗口已经露面了，而 `Show()` 末尾会激活自己、抢走前台。以你的窗口为主角的话，广播后要 `WinActivate` 还给它 |
| **`Launcher.Opened` 的 `hwnd` 不用你清理** | 每次呼出都重记一份；伙伴被关掉后 `_StackWithPeer` 开头有 `WinExist` 存活性检查，会自行退回记忆位置 |
| **`SevenNote.Move` / `Launcher.Move` 载荷必须是物理外框** | 这两个事件直接喂给 `WinMove`；`PlanStack` 已把「可见边界」补上不可见边框换算好了，订阅方不要再自行换算 |
| **一套机制同时只服务一个伙伴** | `_peerRect` 是单值。将来若要「同时呼出 A 和 B 各占一边」，得先把它升级成列表 —— 那是重构，不是加一行 |
| **窗口认不出来？给它的进程做个记号** | 终端能靠标题认（`SevenWork PowerShell`），浏览器**不能** —— 页面标题归网页管、还会随会话变，用户的日常浏览器里也常开着同一个站点，标题一模一样。`DeepSeekFeature` 的做法是 `--user-data-dir` 指一个**专用 profile**，让 Chromium 起一条独立进程树，之后按 PID 认窗 |
| **切换判定不能只看 `WinActive`** | `WinHide` 之后 `GetForegroundWindow` **仍指着那个隐藏窗口**（本机实测 1.2s 后依然如此），于是判定成「在前台 → 再藏一次」，**再也呼不出来**。要写成 `可见 && 在前台`（两个参考实现里都有 `_IsVisible`） |
| **`WinShow` 之后补一句 `WinRestore`** | 窗口被 `WinHide` 藏起来后，宿主可能把自己标记成「最小化」—— Chromium 实测必现：再呼出时 `iconic=1`、`rect` 停在 `-32000,-32000 237x39` 的停放位。而 `WinShow` **不解除最小化**，用户看到的就是「窗口没回来」 |

### 摆放策略在哪改

当前算法是**上下堆叠**（笔记在上、伙伴在下，同宽左对齐），分两层：

- **几何**：`PeerCoordinator.PlanStack()` 算落点，并由 `_PublishMoves()` 广播
  `SevenNote.Move` / `Launcher.Move`；
- **状态与底稿**：`WindowFeature._StackWithPeer()` 判断 `_docked` / `_preStackRect`，
  真正 `WinMove` 由两个 Move 事件的订阅方执行。

1. 伙伴已在屏幕下半区 → 它**原地不动**，笔记窗口填它上方的空间
2. 伙伴贴着屏幕顶部 → 把它**下移**到底边贴工作区底（只挪位置、尺寸一字不动），腾出上半屏
3. 两条都不成立（屏幕太矮、两窗叠不下）→ 返回 `false`，笔记窗口退回记忆位置 / 默认落点

要改成**左右并排**（比如浏览器更适合放右边），改 `PlanStack()` 的算式与 Move 事件载荷即可 ——
发布方那三个生命周期事件的代码一行不用动。
间距与边距调 `Config.DockGap` / `Config.DockMargin` 即可，不必碰算法。

**⚠ 它只在首次适配时被叫到** —— 而且只在 `_AdaptToPeer` 判定「笔记原来待的地方与伙伴相撞」时才会走。
所以想调整**要不要动、什么时候动**，改的是 `_AdaptToPeer` 里的 `_RectsOverlap` 判断与
`_FreezeDocked` 的冻结时机（`_docked` / `_CurrentRect` / `_RectsOverlap` 三个工具方法就在它旁边）。

### 实例二：`Alt+X` 唤 DeepSeek（浏览器）

浏览器比终端多两件事，`DeepSeekFeature` 是完整答案（细节在代码注释里）：

1. **认窗**：`--new-window <url>` + `--user-data-dir` 指向专用 profile → 独立进程树，按 PID 认窗。
   不能靠标题（页面标题归网页管，用户日常浏览器里也常开着同一个站点）。
   ⚠ 别用 `--app`：Edge 155 起 app 窗口照样带地址栏、却没有标签栏，两头不占。
2. **模式标记**：`_deepseek.mode` 落盘。老实例（`--app` 启动的那个）不校验就会一直顶替新窗口；
   标记不符就当「没有窗口」→ 重开。老实例用 WMI 按 profile 路径全库筛，别只信 pid 文件。
3. **尺寸**：`[Paths] DeepSeekW/DeepSeekH` 默认 `772x1020`（**物理像素**）。772 是实测 Edge
   自己会稳定停住的外框宽（请求 513 逻辑像素落到 772）；`--window-size` 收逻辑像素，代码里按
   `目标物理值 × 96 ÷ A_ScreenDPI` 反算。换机器 / 换缩放先 `WinGetPos` 量一次外框再改这两个值。
   ⚠ 宽度请求会被 Edge **吸附**（请求 506 / 512 都落 773），高度却准（680 → 1020）。
   `BrowserPath` 留空时按 Edge → Chrome 顺序自动探测。
