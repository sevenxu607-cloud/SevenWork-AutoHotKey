# 03 · AutoHotkey v2 约定

## 版本与文件格式

- 每个脚本首行必须有 `#Requires AutoHotkey v2.0`。
- 本机解释器（64 位）：`D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe`（同值见 `.vscode/settings.json`）。
- 源码编码：**UTF-8 无 BOM**；换行：`*.ahk` **CRLF**、`*.md` **LF**（`.gitattributes`）。
- **必须 64 位**运行 / 编译：32 位会导致 RichEdit 字符格式异常。

## v2 语法要点（v1 写法一律不用）

- 赋值 `:=`；`=` 不区分大小写、`==` 区分。变量不加 `%`。函数调用带括号、字符串加引号。
- `#HotIf` 取代 v1 的 `#If`。`<` `>` 是数值比较，字符串比较用 `StrCompare`。
- **没有内置 `JSON`** —— `JSON.Stringify` 是 v2.1 alpha 才有的，v2.0.27 上会被当成未赋值变量。
- **没有 `Typeof()`** —— 用 `Type(x)`；写成 `Typeof` 抛出的错还会被外层 `try/catch` 染成看不懂的
  `Invalid callback function`。

## 命名：这些名字不能做变量名

| 类别 | 名单 | 报错 |
| --- | --- | --- |
| 内置函数 | `Clear` / `log` / `min` / `max` / `Indent` / `Edit` | `This Func cannot be used as an output variable. Specifically: edit` |
| 内置类 | `Gui` / `Object` / `Map` / `Array` / `Buffer` / `Func` / `File` / `Clipboard` | `This Class cannot be used as an output variable. Specifically: Gui` |

- 名字**不区分大小写**（`global LOG` 撞 `log`）。
- 报这个错时脚本**一句都不执行**、输出为空，很容易误判成「探针没跑」；没加 `/ErrorStdOut`
  还会弹模态框卡住不退（表现为平白多一个 `AutoHotkey64` 进程）。
- 对策：变量名写长 —— `guiHwnd` / `idxMap` / `logPath`。

## 本项目踩过的坑

| 坑 | 症状 → 对策 |
| --- | --- |
| **反引号在 AHK 字符串里是转义符** | 三连反引号写不出来（正则匹配 markdown 围栏时报 `Missing """`）→ 用 `Chr(96)` 拼出围栏再交给 `RegExReplace`（见 `PromptStoreService.Summary`） |
| **`<=` / `>=` 遇空字符串抛错** | `Expected a Number but got an empty string` → 数值比较前先 `IsNumber()` 守卫（`State` 未初始化的记忆值就是 `""`） |
| **`FileExist` 返回 `"A"` 不是 `true`** | 断言 / 布尔判断需 `!!` 转换，否则 `= true` 判假 |
| **`EM_SETSEL` / `EM_GETSEL` 要用 DllCall** | 内置 `SendMessage` 对 INT 参数有歧义 |
| **`FINDTEXTEXW` 读偏移 16/20**（chrgText） | 误读 0/4 会导致搜索只找到 1 个 |
| **`FileInstall` 必须写在一行** | 折行会打包出 0KB 空文件 |
| **最小化窗口的 `IsWindowVisible` 仍是 `1`** | 判断「窗口在显示」必须 `IsWindowVisible && !IsIconic`；最小化窗口的 `WinGetPos` 返回 `-32000` 一类屏幕外停放位（150% 下 `-21333`），记下来再 `WinMove` 会把窗口搬到看不见的地方 → 记位置前校验它落在某个 `MonitorGetWorkArea` 内，并给 `WinRestore` 兜底 |
| **`WinMove` 收物理像素，`Gui.Move` / `Gui.Show("w…")` 收逻辑单位** | 150% 缩放下混用会**二次放大**（实测 `g.Move(1629,238)` 落到 `(2444,357)`）；`Show("w450 h550")` 也压不住尺寸（被控件撑到 697×881）。对策：**位置记忆全程 `WinMove` + `WinGetPos`**（同一单位），尺寸别写死、交给 AHK（`WinMove` 的 `Width/Height` 留空即不变）。⚠ `Config.WinW/WinH` 已作为死字段删除，别再引回 |
| **`Gui.Show("Hide")` 过的窗口 `WinGetPos` 读不到** | `WS_VISIBLE` 为 `0` 时 `WinGetPos` / `WinMove` 默认忽略隐藏窗口（抛错）→ 先 `DetectHiddenWindows(true)`，用完恢复 `A_DetectHiddenWindows` |
| **先 `Show` 再 `WinMove` 会让窗口「飘一下」** | 实测 `+31ms` 出现在默认落点、`+219ms` 才跳到目标位置 → **定位在隐藏态完成**：`Show("Hide")` → 量尺寸 / `WinMove` → 最后 `Show()` |
| **异步回调里碰窗口，窗口可能已经藏了** | `SetTimer` 排的复核跑起来时用户可能已按热键收窗 → `WinMove` 抛 `Target window not found` → 弹**模态框**、整个脚本卡死。**规则**：异步回调碰窗口前过闸 —— `DetectHiddenWindows(false)` + `WinExist` + `!DllCall("IsIconic", "ptr", hwnd, "int")`，不满足即 `return`；判断「用户已收起」时**顺手停掉后续复核**（不再排下一轮） |
| **未捕获异常默认弹模态框卡死** | 默认动作是 `MsgBox` + 停摆，而 `SetTimer` 回调没有外层 `try`。v2.4.2 起组合根注册 `OnError`（写 `_error.log` 后 `return 1`）、`#Warn VarUnset` 改 `OutputDebug`。⚠ **兜底只保证不倒，不保证逻辑对** —— 异步回调碰窗口 / 控件前仍须自己过闸 |
| **`obj.prop(args)` 调不动属性里存的函数** | 走**方法查找**、属性值是 `Func` 时抛 `Too many parameters passed to function`，还会被外层 `try` 吞掉（表现为「日志一条都不写」）→ **先取局部变量**：`fn := obj.prop` → `fn(args)` |
| **`SetTimer(this.StaticMethod, -1000)` 报 `Invalid callback function`** | 类静态方法的函数对象看着干净（`Type(...)` = `Func`）但 `SetTimer` 不收 → 用箭头函数包一层 `SetTimer(() => T.StaticReset(), -300)`，并把闭包**存字段**（每次新建的箭头函数是新对象，`SetTimer(fn,0)` 认不出、停不掉）；从字段取出先放局部变量再传 |
| **`ComboBox.Value := x` 抛 `Invalid value`** | 实测下拉已含该值照样抛 → 可编辑下拉**读写都别用 `.Value`**：对 `Hwnd` 发 `WM_SETTEXT(0x0C)` / `WM_GETTEXT(0x0D)` / `WM_GETTEXTLENGTH(0x0E)`。⚠ 内置 `SendMessage()` 第 4 参数是 **Control** 不是 WinTitle（传错位报 `Target window not found`） |
| **`Gui.Control` 没有 `Destroy()` 方法** | `Destroy()` 是 `Gui` 对象的方法；写 `ctrl.Destroy()` 抛「方法不存在」并被外层 `try` 静默吞掉（实测面板切页后 3 个输入框仍挂着）→ 单个控件只能 `DllCall("DestroyWindow", "ptr", ctrl.Hwnd)`。**排查手段**：在这类 `try` 里数「成功几次」再记日志（`rows=3 destroyedCtrl=0` 一眼定位） |
| **`Ord()` 在 v2 只收一个字符** | 照 v1 的习惯写 `Ord(s, i)` 抛 `Too many parameters passed to function. Specifically: Ord` → 先 `SubStr(s, i, 1)` 再 `Ord(ch)`。⚠ 逐字符遍历时 `SubStr` 按 UTF-16 单元取，emoji 会被拆成代理对的两个单元；只要判定后**原样追加**（不重新 `Chr` 组合），拼回去仍是原字 |
| **WebView2 在窗口隐藏期挂载 → 编辑区一片纯底色** | 父窗口 `Show("Hide")` 时 `Mount`，Chromium 子窗口会停在 `SW_HIDE`（实测子窗口 `vis=False`、坐标 `-32000,-32000`），父窗口随后 `Show()` 也不回来 —— 表现是「窗口出来了、编辑区一片纯底色」，`stderr` 与 `_error.log` 都空。两个补丁都要：`ComCall(4, ctrl, "int", 1)`（见下一行）+ **父窗口可见后**再 `Fill()` 一次（隐藏时那次给的是 0×0） |
| **`WebHostService` 的 `IsVisible` 只有 getter** | 库里 `IsVisible { get => ComCall(3, …) }`，没有 `put_IsVisible`。`ICoreWebView2Controller` 的 vtable 4 就是 putter，直接 `ComCall(4, this._ctrl, "int", 1)`；写成 `this._ctrl.IsVisible := 1` 抛「属性是只读的」，同样会被外层 `try` 吞掉 |
| **hostObjects 的方法键名撞上 JS 内置** | `AddHostObjectToScript("ahk", {apply: Fn})` 之后，前端 `b['apply']` 拿到的是 `Function.prototype.apply`（宿主对象是 Proxy，先查函数原型）→ 调用抛 `TypeError: Function.prototype.apply was called on ...`，而调用点大多在 `try` 里，表现成「点保存没反应、日志一条不写」→ 键名避开 `apply` / `call` / `bind` / `toString` / `constructor` / `name` / `length` / `prototype`；本项目改用 `saveSettings` |
| **`WebHostService` 单例挂不住第二个窗口** | 老实现挂第二个窗口时先 `Destroy()` 掉第一个 → 面板一开、笔记窗一片纯底色。改成 `hwnd → {ctrl, core, host}` 槽位表后 **无参调用会落到「最近挂载的窗口」**，所以调用一律显式传 hwnd；两个窗口的 `dataDir` 还必须分开（同一 user data folder 建不出第二个 `CoreWebView2Environment`，失败藏在 `await()` 里、只表现为白屏） |
| **`Property is read-only`（实例字段赋值）** | 两个同源原因：① **字段名与方法名撞车** —— AHK v2 的属性名**不区分大小写**、且与方法共用命名空间，`this._place := x` 撞上私有方法 `_Place()` 就被解析成「给方法赋值」（方法只有 getter，无 setter）；② 字段声明在类体里（类体变量是**静态**的），`this.x := v` 等于写静态变量。两种表现都是「按热键没反应，`_error.log` 只有一行 `Return Property is read-only.`」→ **字段一律在 `__New` 里赋初值，且名字与方法错开**（`_placeMode` vs `_Place()`）。本项目此前全是全静态类，`WebWindow.ahk` 是第一个实例类 |
| **`DwmSetWindowAttribute(38, SYSTEMBACKDROP)` 返回 0 却什么都没做** | 传 `3`（Acrylic / TRANSIENTWINDOW）拿到 `S_OK`，窗口照样把后方内容**清晰**透出来 —— 没有模糊、也没有报错。返回码不可信 → **只能看截图**。⚠ 2026-10-23 补正：纯 `Gui` 上材质**是生效的**（宿主红底被亮材质提亮成浅粉），前提是同时调 `DwmExtendFrameIntoClientArea(hwnd, {-1,-1,-1,-1})`；**一旦挂上 WebView2 子窗口材质就不再出现**，设在 `Show()` 前 / 后 / 延迟 1.5s 重设都一样 → 阻断者是 WebView2 的合成表面，不是缺那一步调用 |
| **`SetWindowCompositionAttribute(ACCENT_ENABLE_ACRYLICBLURBEHIND)` 让整个窗口消失** | 调用返回 `1`（成功）、进程还在，但窗口**连标题栏都不见了**，屏幕上只剩后方内容 → 它把窗口 layered 化，而 layered 父窗口的 Chromium 子窗口直接被裁掉。同理 `WS_EX_LAYERED` 也不能加。⚠ `GlassPaint` 里那段 `_Accent` 是**从未跑过**的第三级兜底（第一级就 return 了），别以为它在生产里验过 |
| **拦 `WM_ERASEBKGND` 后必须由 DWM backdrop 托底** | 想让板外「露桌面」就得 `OnMessage(0x14, (*) => 1)` 掐掉背景刷，但**关掉所有 backdrop 后窗口整个不可见**（`MainWindowHandle = 0`、`IsWindow` 仍在）——未绘制的区域变成一片虚无。而且同一组合（拦背景 + `SYSTEMBACKDROP(3)`）实测**时好时坏**（一次板可见、下一次只剩一角）→ 这条路不稳定，**不要进生产**。WebView2 客户区本来就透不到桌面（它是独立合成表面，自己算完像素交给父窗口），板外那圈只能靠 CSS 画 |
| **`{"edge-a": "0.55"}` → `Invalid property name in object literal.`** | v2 的对象字面量**只收标识符作键**，带连字符 / 引号的键一律解析失败。这类错误在类体里时方案 A 的 `ExitApp()` 预检**抓不到**（auto-execute 早退了），表现成「程序一启动就消失、`_error.log` 一行都没有」→ 含非标识符键的对象改用 `Map("key", value, ...)`；读的时候 `for k, v in` 对对象与 Map 都认，**但写回必须是 Map** |
| **`ConfigService.Read(section, key, default)` → `Too many parameters passed to function.`** | 它只有 **两个**参数（默认值走 `SetDefault` 或就地判空），三个参数的是 `ReadInt`。多传一个编写时不报错，只在调用路径上抛 —— 面板建窗时调它，表现就是「按 `Alt+S` 打不开」，日志里一行 `Too many parameters` |



## 全局异常兜底（v2.4.2 起，注册点在组合根）

- `OnError(OnScriptError)` → 写 `Config.LogPath` 后 `return 1` 继续跑，不再弹模态框。
  日志位置：**恒为 `%AppData%\SevenWork\_error.log`**（v2.14 起取消开发身份，不再有
  `<工作树根>\.logs\` / `src\.logs\` 分支）。含消息 / 文件 / 行 / 调用栈，超 512KB 轮转。
- `#Warn VarUnset, OutputDebug` —— 未赋值变量警告不再拦路。
- **订阅者的异常也进同一份日志**（v2.4.5 起）：`EventBus.Emit` 对每个订阅者 `try`/`catch`
  且**互相隔离**，循环后汇聚成一条（`事件名 + 订阅者第 N 个 + 消息 + 文件/行`）。
  出口是组合根注入的 `_sink`（`EventBus.SetErrorSink(LogError)`）；没注入则只写 `OutputDebug`。
  ⚠ 「第 N 个」= 注册顺序，改顺序序号就变；没加名字标签（要改 30 处 `On`，不值）。

⚠ **别把兜底当挡箭牌**：`OnError` 只保证「程序不倒」，出错那句会被跳过、后续可能拿到半成品状态；
新增 `SetTimer` / `OnMessage` 回调时照 `AutoSaveFeature.Tick` 的写法自己守卫；
用户报「按了没反应」时**先看 `_error.log`**，再枚举 `#32770` 读正文
（`DetectHiddenWindows(true)` + `WinGetText`，标题是脚本名）。

