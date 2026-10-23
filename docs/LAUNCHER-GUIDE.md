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

浏览器比终端多两件事要处理，`DeepSeekFeature` 是完整答案：

1. **认窗**：用 `--new-window <url>` 让 Edge 开出一扇**普通浏览器窗口**（标签栏、工具栏齐全，
   窗口内可以直接浏览网页；早先用 `--app` 求桌面应用观感，实测不划算 —— 理由见「关键坑点」表），
   再配 `--user-data-dir` 指向
   `Config.AppDataDir\_deepseek-profile`。**专用 profile** 换来两样东西 —— 不往用户自己的
   收藏夹 / 历史 / 扩展里掺东西，以及一条独立进程树（窗口可按 PID 唯一定位，不受用户日常
   浏览器里那些同标题窗口干扰）。PID 记在 `_deepseek.pid`，笔记程序重启后据此认回窗口。
   首次需要在它的 profile 里登录一次 DeepSeek，之后就记住了。

   ⚠ 这一步有两个本机实测踩到的坑（v2.1.1 修好，改这块代码前先读）：

   - **别只认「第一个」新进程**：用户自己的浏览器一直在跑，随时会冒出**没有应用窗口**的
     新渲染进程。启动后若只取第一个新 PID 去配窗口，一旦它排在真正那个前面就会**整段
     超时** —— 实测卡满 8 秒后弹「浏览器已启动，但未能找到它的窗口」，而窗口其实早开好了：
     只是没被摆位、PID 也没记下来，于是**下次再按又拉起一个新的，旧窗口永远隐藏不掉**。
     要遍历**全部**新 PID 逐个试（`_NewPidsSince`）。
   - **`_TopWindowOf` 不能要求窗口「可见」**：窗口被 `WinHide` 藏着时，那依然是我们自己
     那扇窗。要求可见的话，**重启程序后就认不回一个正被藏着的窗口**，又去拉一个新的。
     写法是优先取可见的，都没有则退回找到的第一个 —— 这就是 `relax` 参数，平时的「认回」
     调用传 `true`。

   顺便说清「认窗」的两级兜底：进程内 `_hwnd` 缓存 → `_deepseek.pid` → 都没有才重新拉起。
   所以**只在真正拉新窗口时**才走上面那段 PID 轮询。
   ⚠ 那段轮询自己还有一层兜底：Chromium 是**单实例**，`_deepseek.pid` 里的老进程若还活着
   （用户只关了窗口、没退进程 —— 普通窗口模式下这是常态），启动就**不会**产生新进程，
   只认「新 PID」会一路空等到超时弹框。故同时按老 PID 认窗（`_Launch` 里 `knownPid` 那段）。
2. **尺寸位置**：两个伙伴各有各的「谁来管」——
   - **浏览器**：尺寸由 `--window-size` 在启动时定下，位置它自己不记（每次都在 Chromium 的
     默认点），所以露面前由 `_PlaceLikeTerminal()` 摆到位。
   - **终端**：尺寸归 Windows Terminal 的 profile，位置由 WT 的 `initialPosition` 决定 ——
     而那份值可能早就过时。本机实测：任务栏改成自动隐藏后工作区变成 2560x1600，终端却仍落在
     `1803,540`（底边 1560，离工作区底 40px = 当年任务栏的高度），而 DeepSeek 按公式落在
     `1801,580`（贴底）—— 两个伙伴并排高矮不齐。`PowerShellFeature._PlaceLikeDeepSeek()`
     把终端的位置也按同一公式校正。

   两处落点公式相同：**右侧贴工作区右缘（离缘 `Config.PlaceRight`）、底边贴工作区底**，
   于是 `Alt+C` 与 `Alt+X` 两种堆叠观感一致。终端那一步**位置与宽度一起统一**（见下），
   高度仍归 Windows Terminal 的 profile —— 宽度不统一，左缘就会错开一大截。

   ⚠ **左缘对齐靠「宽度统一」，不是靠位置公式**：终端那一步原先「只挪位置、尺寸一个不动」，
   于是两个伙伴都按**右缘**贴屏幕摆、宽度却各是各的 —— 用户 WT profile 实测 **744x1020**、
   DeepSeek 目标 770：右缘齐（2545），**左缘差 26px**（终端可见 `1810..2536` vs DeepSeek
   `1784..2538`），堆叠处左边露出一条底色，看着就是「终端比别人窄一点、缺口在左边」。
   现在终端按**同一个目标宽**摆（只改宽，高度仍归 profile），三条边才全齐。

   ⚠ **目标宽 = Edge 自己会稳定停住的那个值（本机 772），别追着 `--window-size` 改**：
   `--window-size` 收的是**内容区**尺寸，Edge 套到外框上还会补一圈调整边框，而它重新套用的
   时机在窗口 show/restore **之后**，晚于摆位那一刻 —— 所以 `_PlaceLikeTerminal()` 摆完位置
   尺寸后，会在 350 / 950 / 1550 / 2150ms **各复核一次**实际外框，量到与目标不符就按目标重摆。
   ⚠ 复核必须**多轮**：Edge 只在露面后套用一次，`WinMove` 之后并不会被持续校正
   （实测稳定窗口上改过的尺寸能保持 2 秒以上不变）。
   实测（后台每 200ms 量一次的时间线）：60~80ms 窗口刚出现、1000ms 落到目标位，此后稳定。

   ⚠ **试过「把宽度请求砍小 2 去补那圈边框」，没用** —— 用临时 profile 开探针窗口实测：
   请求 506 / 512 逻辑像素（= 759 / 768 物理）**外框都落在 773**，宽度会被**吸附**；高度却准
   （680 → 1020）。所以别再跟它抢，**以它自己稳定停住的宽度为目标**：本机 SevenWork profile
   上是 **772**，写进 `_TargetW()` 默认值，终端也按 772 摆 —— `_CheckSize` 的复核才收敛
   （否则每轮都判「不符 → 重摆 → Edge 又套回去」来回弹）。

   实测终态（2026-10-16）：笔记窗口 / 终端 / DeepSeek 三者外框**同为 772 宽**、x 同为 `1773`，
   可见边界**左 `1782` / 右 `2536` / 底 `1591` 完全一致**；笔记窗口底边 `574` 到伙伴顶边
   `580` 正好 **6px**，即 `Config.DockGap`。

   ⚠ **窗口模式换代时，改了命令行不算数**：Chromium 单实例复用 —— profile 进程只要活着，
   后到的命令行就只被当成「在已有实例里开个地址」，窗口类型仍由**最先那次启动**决定。
   实测从 `--app` 升级到 `--new-window` 后，老进程（`--app` 启动的那个）一直活着，按
   `Alt+X` 照旧得到应用窗口；更麻烦的是 `Toggle()` 会先把老窗口认回来，**根本走不到
   `_Launch()`**。解法是落盘一个模式标记 `_deepseek.mode`：本版启动的实例写 `window`，
   `_FindBrowserHwnd()` 开头就校验它，不符就当「没有窗口」→ 转去 `_Launch()` →
   `_RetireLegacyInstance()` 先 `WM_CLOSE` 再强杀，清干净了再按新模式重开。
   ⚠ 老实例的识别**别只信 `_deepseek.pid`**（可能落后，也可能指向已退出的进程）—— 用 WMI
   按命令行里的 profile 路径全库筛才全（实测该 profile 下有 **9** 个同族进程：主进程 +
   crashpad / gpu / renderer…），WMI 拿不到时退回只认 pid 文件那一个。
   实测：退掉老实例后新起 `msedge.exe --new-window https://chat.deepseek.com/ ...`，一次
   到位；连按 3 次 `Alt+X` 隐藏 / 显示切换正常、PID 不变、不弹「找不到窗口」；程序重启后
   再按 `Alt+X` 认回同一扇窗口，不新开。

   > 同公式的两个实现（`_PlaceLikeTerminal` / `_PlaceLikeDeepSeek`）现在共用**一份**代码：
   > 落点算式与「可摆性闸」都在 `PeerLayoutService`（`CornerRect` / `TargetW` / `TargetH` /
   > `IsPlaceable` / `RectOf`）里，两个 Feature 各调一次 —— 不再需要「改一处同步另一处」。

可配置项（`_config.ini`，都可留空走默认）：

```ini
[Paths]
BrowserPath=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
DeepSeekW=772
DeepSeekH=1020
```

- `BrowserPath` 留空时按 Edge → Chrome 顺序自动探测，换 Chromium 系浏览器不用改代码。
- `DeepSeekW` / `DeepSeekH` 是**物理像素**目标尺寸，默认 `772x1020`。772 不是「照 WT profile
  推算」的，而是**实测 Edge 自己会稳定停住的外框宽**（本机 150% 缩放下请求 `513x680` 逻辑
  像素落到 772）—— 终端也按这个宽摆，三者左 / 右 / 底三条边才全齐。
  ⚠ 历史三步：写 `744` 时比终端实测窄 26px（左缘错开一大截）；改 `770` 后与终端齐，却比
  Edge 实际稳定停留的 772 窄 2px，复核每轮都判「不符」重摆。**以 Edge 实测值为准。**
  换机器 / 换缩放要重定：先 `WinGetPos` 量一次外框，再改这两个值。
- ⚠ `--window-size` 收的是**逻辑像素**，而 `WinMove` / `WinGetPos` 认**物理像素**。
  本机 150% 缩放（`A_ScreenDPI = 144`）下传 `513x680` 得到 `772x1020`，所以代码里按
  `目标物理值 × 96 ÷ A_ScreenDPI` 反算，别写死。⚠ 这只对**高度**可靠：宽度实测会被 Edge
  **吸附**到它自己的值（探针：请求 506 / 512 都落 773），宽度以 772 这个实测值为准。

### 设计思考：为什么「呼出 + 窗口自适应」这么贵

> 这一节不是操作指南，是一份**成本账** —— 给将来想再挂一个外挂窗口的人（包括我自己）一个判断依据。
> 数据取自 2026-10-17 单体版 `SevenWork.ahk` 的实测统计（拆分后代码位置变了，成本量级不变）。

**先把两件事分开**：

| | 代码量 | 与 AHK 的关系 |
| --- | --- | --- |
| **呼出 / 收起 / 认回**（`Run` + 认窗 + `WinActivate` + 置顶） | ~30 行 | ✅ 天生贴合：AHK 就是干这个的 |
| **窗口匹配 + 笔记自适应**（上文整套契约） | **~960 行** | ⚠️ 硬凑：在脚本层手写窗口管理 |

**这 960 行的去处**：

| 模块 | 约行数 |
| --- | --- |
| `PeerLayoutService`（落点公式 + 可摆性闸） | 68 |
| `WindowFeature` 伴生段（让位 / 状态机 / 堆叠算法） | 441 |
| `PowerShellFeature`（认窗 + 摆位） | 221 |
| `DeepSeekFeature` 摆位 / 复核段 | 231 |
| **合计** | **961（代码 543 / 注释 333，注释占 35%）** |

—— 占全文 4313 行的 **22%**。两个快捷键背后，是这个项目最重的一处。

**真正的算法只有一处**：`_StackWithPeer`（约 199 行；把笔记摆到伙伴正上方、同宽、按可见边界对齐）。其余 ~760 行都不是算法：

| 类别 | 约 | 为什么省不掉 |
| --- | --- | --- |
| **认窗** | 250 行 | Chromium / Windows Terminal 都是**单实例复用**（窗口可能属于老进程）；同一 profile 可能开着几扇窗；WT 的标题要等 PowerShell 进程 ~0.7s 才设好；换窗口模式还得先退老实例 |
| **守闸** | 120 行 | AHK v2 对隐藏 / 最小化窗口的 `WinMove` / `WinGetPos` **直接抛错**，默认动作是弹模态框 → 整个程序停摆（v2.4.1 的连打卡死即此类） |
| **尺寸复核** | 80 行 | Edge 在 show/restore **之后**才重新套用 `--window-size`，且不通知任何人 → 只能 350 / 950 / 1550 / 2150ms 四轮事后核对 |
| **摆位** | 90 行 | DWM 的 9px 不可见边框、按可见边界对齐、屏幕塞不下的兜底 |
| **状态机** | 220 行 | `_docked` / `_stacked` / `_preStackRect` +「只适配一次」+ 堆叠态隐藏不覆盖记忆 |

**根因不在 AHK 的「能力」，在它的「模型」**：

1. **窗口 API 是「无状态的一次性动词」** —— `WinMove(x, y, w, h, "ahk_id " . hwnd)` 是一个动作、不返回任何对象；外部程序开的窗口在 AHK 眼里**永远只是一个 hwnd 数字**（只有自己 `Gui()` 建的窗口才有对象）。所以「记住它是我的伙伴 / 它现在在哪 / 它变了我得知道」三件事全靠手搭：持久句柄 + 观察者 + 状态机。
2. **没有窗口事件，只能用定时器轮询** —— 实测 `SetWinEventHook` / `RegisterShellHookWindow` / `WM_WINDOWPOSCHANGED` / `OnMessage` **0 处**，`SetTimer` **8 处**。Windows 本身**是**会通知「某窗口被移动 / 缩放 / 销毁」的（`SetWinEventHook` 的 `EVENT_OBJECT_LOCATIONCHANGE` 等），但接它要 `DllCall` 处理 Win32 回调（回调里不能做重活、要防重入、生命周期难管）—— **成本 ≥ 轮询**，于是自然滑向「多量几次」：`_WatchSize` 四轮猜时机、`_docked` 自己记状态。

> **一句话**：AHK 是很好的**遥控器**，这里却让它兼任了**舞台监督** —— 遥控器按一下就够；舞台监督得记住每个演员此刻站在哪、什么时候自己挪了位置、谁先上台谁后上台。上文「只适配一次」的取舍正长在这块土壤上：没有事件通知、又只认第一次，第二个上台的伙伴就没人看了。

**所以本质上，这一块写的是一个「只服务三个窗口的专用平铺窗口管理器」**。FancyZones / Komorebi / GlazeWM 做的是同一件事（C++ / Rust，独立产品，几千行起），这里砍到 543 行、只做「一列堆叠」。定位清楚以后成本就合理了：**贵不是因为写错了，而是「让三个窗口看起来像一个应用」本来就是窗口管理器的活。**

**三条路（按「贴合 AHK 哲学」排序）**：

| 路 | 形态 | 代码量 | 代价 |
| --- | --- | --- | --- |
| **约定式**（最贴 AHK） | 笔记与伙伴各占一个**固定矩形**，`WinMove` 到常量、不记状态 | ~100–150 行 | 失去「笔记随便摆都能拼上」 |
| **现状**（通用自适应） | 认窗 + 追变化 + 按冲突算位置 | 543 行 | 已在付；并需容忍 `_docked` 那类状态机取舍 |
| **交给现成窗管器** | 装 FancyZones / Komorebi，三窗固定到 zone，本程序只管呼出 | ~30 行 | 要装额外软件；「呼出即就位」要另配；笔记窗口（AHK Gui）也得纳入 zone |

**能复用到什么程度**：

| 层 | 复用度 | 说明 |
| --- | --- | --- |
| **契约层** | **100%，零改动** | 三个生命周期事件 + 两个 Move 事件；让位 / 记忆 / 兜底全在 `WindowFeature`，新伙伴照上文骨架抄 |
| **机制层** | 复用 | `PeerLayoutService` 的落点公式与可摆性闸、`_CheckSize` 多轮复核（**只在「每次新建窗口」的伙伴上需要**） |
| **伙伴个性层** | **不能复用，必须逐个实测** | 认窗方式、尺寸谁管、会不会吸附、几何记在哪 —— 每换一个伙伴就是一次实验 |

**边际成本判据**：接新伙伴 ≈ 「实测一次脾气」+ 30~80 行适配，不是重写 300 行。
**但**：`_peerRect`（`WindowFeature` 1834 行）是**单值**、`_docked`（1851 行）一旦置位就冻结，所以「**一次只呼出一个伙伴**」的用法现在就能接第 3、4 个；要「三窗同屏」则必须先重构（`_peerRect` → 伙伴集合、`_StackWithPeer` → 能排三格的布局器、`_docked` → 按伙伴身份记忆）。**一句话：加伙伴是「填参数」，加布局是「改引擎」。**

**已经用上的「降维打击」：把不确定性移出运行期**

两个伙伴各有各的脾气（浏览器不记位置、Edge 吸附宽度、WT 的 `initialPosition` 可能过时），摆位代码只是在**事后纠正**它们。换个思路 —— **把配置提前对齐，让纠正无事可做**：

```
Windows Terminal 的 settings.json
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json

    "initialPosition": "1814,540",   ← 改成 "1773,580"
    "initialCols": 48,               ← 改成 50
    "initialRows": 33,               ← 不动：33 行 = 1020 物理 = TargetH
```

- 三个数字都是**物理像素**（2026-10-17 实读；现值 `1814,540` 与终端落点逐字一致，底边 `540+1020=1560` 正是「任务栏还显示」时代的工作区底 `1600−40`）。⚠ 上文别处写的 `1803` 是更早的记录，以这次实读的 `1814` 为准。
- `1773 / 580` = `CornerRect(772,1020)` 的结果；`50 列`由「48 列 → 744 物理」与「每列 15 物理」（WT 默认 Cascadia Mono 12pt，字格 10×20 逻辑 = 15×30 物理 @150%）反算：`(772 − 24) ÷ 15 = 49.87 → 50`（外框 ≈774，与 Edge 自己那 2px 取整误差同级）。
- ⚠ 改完**新开**终端才生效；任务栏改回「一直显示」或换缩放后要重算。

效果：终端从「先按 profile 露一脸（左缘差 28px）→ 约 1 秒后归位」变成**诞生即在位**，`_PlaceLikeDeepSeek` 退化为「移到相同坐标」= 零可见移动。**这是本仓库第一个「用配置换掉算法」的例子。**

**一条方法论（顺手记下，比上面所有数字都值钱）**

**「这个判断每次运行都会得到同一个答案吗？」** 是 → 挪出运行期；否 → 留运行期但**必须有兜底**。

| 形态 | 例 |
| --- | --- |
| **烘焙进资源** | 图片的裁剪与色调烘进 PNG → 运行期只铺图，零判断 |
| **固化进配置** | `Config.PlaceRight` / `DockGap`、`Themes` 静态数组、WT profile 的 `initialPosition` |
| **改成手动** | v2.4 砍掉「自动补时间戳」（删 `FindLastTimestamp` / `Config.TimestampInterval`）→ `Ctrl+T` 手动 |

反向判据：答案取决于**人的审美或机器环境**（`-CropW` 主体大小、配色、屏幕缩放）→ 只能由人在准备期定，**别让运行期去猜** —— 「为配深字把暗图整体提亮」那次翻车，本质就是把准备期的判断塞给了运行期思维。

**后续可做（todolist，都不急、按需触发）**

| # | 事项 | 成本 | 触发条件 |
| --- | --- | --- | --- |
| 1 | 验证 Obsidian 是否记住窗口几何（`WinMove` → 关 → 重开 → `WinGetPos` 比对） | 5 分钟、零代码 | 下次开 Obsidian |
| 2 | 接 Obsidian 窗口：发三事件 + `obsidian://` 认窗 + `Alt+O`（常驻单实例、**没有漂移问题**，估算 ~30 行） | ~30 行 | 想要 |
| 3 | 修 `_docked` 顺序敏感（第二个伙伴不触发重排）+ `_CheckSize` 重摆后补 `_BroadcastRect` | ~30 行 | 想要两个伙伴都自动重排 |
| 4 | `_BroadcastRect` / `_CheckSize` 在两处 Feature 各有一份（2487 / 3026），照 v2.4.3 先例上收到 Service | ~0（纯搬运） | 接第 3 个伙伴之前 |
| 5 | 三窗同屏：`_peerRect` → 伙伴集合 + 通用布局器 + `_docked` 按伙伴记忆 | 150~250 行 | **仅当**要同屏三窗 |
| 6 | 主题流水线补 `-Report`：自动验收（亮部 p95 / 饱和 p95 / 12×12 网格 p90）并推荐 `-Knee`/`-HiMax`，输出**带逗号可粘贴**的 `Themes` 条目 | ~1 小时 | 下一张主题图之前 |

> 提醒：`tools\pick-theme-colors.ps1` 与 `tools\rebake-backdrop.ps1` 是**独立 CLI**，脱离本程序也能单跑 —— 主题这条线的可复用性来自「重活全部外包成外部工具、AHK 只编排」，与窗口那条线（能力长在 `WindowFeature` 里、只能靠契约复用）是两种形态。**想让某个能力被复用，先把它隔成一个可单跑的工具。**


## 附：两条业务坑（原「关键坑点」）

| **`--app` 应用窗口不值得用，改开普通窗口** | 早先用 `--app=<url>` 让 Edge 开「应用窗口」图的是桌面应用观感，实测两头不占：Edge 155 起 app 窗口**照样自带地址栏**（UIA 查到 `view_1017`「地址和搜索栏」，换全新 `--user-data-dir` 亦然，是产品行为），却**没有标签栏** —— 既不像应用，也不算好用的浏览器。改用 `--new-window <url>` 开**普通窗口**：标签栏与完整工具栏都在，窗口内能直接浏览网页（实测窗口标题带「和另外 1 个页面」= 多标签、以及「Microsoft Edge」后缀，app 窗口两者皆无）。认窗逻辑一行不用改（普通窗口 class 同为 `Chrome_WidgetWin_1`，仍按专用 profile 的 PID 认）。⚠ 外框尺寸别指望 `--window-size`：实测宽度请求会被 Edge **吸附**到它自己的值（探针：请求 506 / 512 逻辑都落 773），高度却准（680 → 1020）；本机 SevenWork profile 上稳定在 **772**，目标宽就以这个实测值为准 —— 见上文「目标宽」一节 |
| **换了窗口模式必须退掉老实例** | Chromium 单实例复用会让「最先那次启动」的窗口类型沿用到该进程结束 —— 老实例还活着，改了命令行也白改（实测从 `--app` 升级后按 `Alt+X` 仍开应用窗口）。更隐蔽的是 `Toggle()` 会**先把老窗口认回来**，于是根本走不到 `_Launch()`。故落盘模式标记 `_deepseek.mode` 做升级清理：`_FindBrowserHwnd()` 开头就校验它，不符即当「没有窗口」，再由 `_RetireLegacyInstance()` 先 `WM_CLOSE` 后强杀。⚠ 老实例的识别别只信 `_deepseek.pid`（可能落后或指向已退出进程），用 WMI 按命令行里的 profile 路径筛才全（实测该 profile 下有 9 个同族进程：主进程 + crashpad / gpu / renderer…） |