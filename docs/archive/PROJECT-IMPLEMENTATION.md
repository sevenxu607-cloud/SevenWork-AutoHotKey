# SevenWork 技术实现清单（历史快照 · RichEdit 时代）

> ⚠ **已归档（2026-10-23）**：本文写于 v2.8，记录的是 **RichEdit + 双 RTF** 那一代的技术实现。
> 编辑区迁到 WebView2 + Milkdown、保存链路改为纯 Markdown 之后，第 1–5 节的**技术载体已不存在**。
> **当前架构看** [`../PROJECT-OVERVIEW.md`](../PROJECT-OVERVIEW.md)，能力契约看
> [`../CAPABILITIES.md`](../CAPABILITIES.md)。原文不改写 —— 里面的**判断**仍有价值（例如
> 「为什么不自研 Markdown 解析器」「为什么不让剪贴板当进程内通道」），只是不再描述现状。

> **用途**：回答「到底用了什么技术、实现了什么」—— 每条都是「技术手段 → 实现效果」。
> 功能怎么用看 `../README.md`；项目全景看 `PROJECT-OVERVIEW.md`；人的决策看 `DEVLOG.md`。
> 口径：`v2.8` / `2026-10-21`。**技术事实以 `src/SevenWork.ahk` 为准**，本文只是索引。

---

## 总览

> 用 AHK v2 作宿主，把 RichEdit 当作可编程富文本引擎，用 Win32 消息 + Dwm/Uxtheme + GDI
> 补齐 RichEdit 不提供的滚动、主题、背景图能力；用 Pandoc 做格式出口；用 EventBus + 四层架构
> 把 21 个功能拆成互不依赖的插件；最后用「源码替换 + 拼接驱动」的脚本化演示验证整条用户旅程。

| # | 技术块 | 一句话 |
| --- | --- | --- |
| 1 | 窗口与控件 | AHK `Gui` 里嵌 Win32 `RichEdit50W` |
| 2 | RTF 读写 | `EM_STREAMOUT/IN` 回调直读直写 |
| 3 | 字符与行操作 | `EM_SETCHARFORMAT` / `EM_LINEFROMCHAR` / `EM_LINEINDEX` |
| 4 | 文内搜索 | `EM_FINDTEXTEXW` + 独立搜索栏 Gui |
| 5 | 滚动同步 | `GetScrollInfo` + `EM_GET/SETSCROLLPOS` |
| 6 | 主题染色 | Dwm `SetWindowAttribute` + Uxtheme `SetWindowTheme` |
| 7 | 背景图 | GDI 双 DC + `StretchBlt`(HALFTONE) |
| 8 | 外部程序呼出 | `Run` + WT profile / Edge 命令行 |
| 9 | 窗口自动让位 | `Launcher.*` 生命周期 + `SevenNote.Move` / `Launcher.Move` + `DwmGetWindowAttribute` |
| 10 | 热键系统 | 平台 / 模块 `GetHotkeys()` 聚合 + `HotIf` |
| 11 | 配置 / 状态 / 解耦 | Ini + 进程内缓存 + `EventBus` |
| 12 | 格式出口 | 内嵌 Pandoc `RunWait` |
| 13 | 稳定性 | `OnError` + 旋转日志 |
| 14 | 端到端测试 | 源码内存替换 + 拼接驱动 |
| 15 | 图片烘焙工具 | PowerShell + C# + GDI |

---

## 1. 用 AHK v2 `Gui` + RichEdit，实现了一个富文本编辑窗口

| 手段 | 实现 |
| --- | --- |
| `DllCall("LoadLibrary", "msftedit.dll", "ptr")` | 加载 RichEdit 4.1+ 控件库 |
| `g.AddCustom("ClassRichEdit50W x8 y32 ...")` | 把 Win32 `RichEdit50W` 直接嵌进 AHK 的 Gui |
| `+E0x02000000`（`WS_EX_COMPOSITED`） | 主窗口离屏双缓冲 —— 修掉「滚动时先擦客户区再画字」的一帧频闪 |
| `+0x201004` | 多行编辑区样式组合 |

**这是整个项目的地基**：后面所有能力（格式化、搜索、滚动、图片、背景图）都建立在
「能直接对 RichEdit 发 Win32 消息」上。

---

## 2. 用 `EM_STREAMOUT` / `EM_STREAMIN` 回调，实现了 RTF 的直接读写

```
EM_STREAMOUT (0x0453)  → 自定义 EditStreamCallback → 拿回 RTF 字节流
EM_STREAMIN  (0x0454)  → 同一回调                  → 把 RTF 灌回编辑区
```

- **不碰剪贴板** —— 剪贴板是进程间共享资源，拿它当私有通道会引发并发竞争；
- **同一次保存输出两份 RTF**：936（GBK，给 WPS/Word）+ 65001（UTF-8，给 Pandoc）——
  因为三方对编码口径的要求互相冲突，只能各喂一份。

**效果**：`.rtf` 是保真母版，`.md` 是便携译本，两者永远同源。

---

## 3. 用 `EM_SETCHARFORMAT` / `EM_LINEFROMCHAR` / `EM_LINEINDEX`，实现了字符格式与行的精确操作

| 消息 | 用途 |
| --- | --- |
| `0x00C2` `EM_SETCHARFORMAT` | 改选中区 / 插入点的字体、字号、颜色、加粗 |
| `0x00C9` `EM_LINEFROMCHAR` | 字符索引 → 行号 |
| `0x00BB` `EM_LINEINDEX` | 行号 → 字符索引 |
| `0x00B1` `EM_SETSEL` | 定位 / 选中 |
| `0x044B` `EM_GETTEXTEX` | 按字符范围取文本 |

**效果**：`Ctrl+Y` 删整行、`Ctrl+D` 复制到下一行、`Ctrl+Shift+↑↓` 移行、`Tab` 缩进
**不丢字符格式** —— 这些不是「拼字符串」，而是「按字符区间做精细编辑」。

---

## 4. 用 `EM_FINDTEXTEXW` + 独立搜索栏 Gui，实现了文内搜索与跳转

```
EM_FINDTEXTEXW (0x044A) + FINDTEXTEXW 结构
  ⚠ 匹配范围要读结构偏移 16/20（chrgText）
    读 0/4 会导致「只找得到第一个匹配」
```

- 搜索栏是**独立的小 Gui**，浮在主窗口上方；
- 打开时用 `HotIf` 把 `Enter / Shift+Enter / Esc` 临时重定向给它；
- 匹配结果用 `EM_SETSEL` 选中并滚动到位。

**另一条线**：`Ctrl+G` 的日期 / 标签跳转不查正文，而是**扫 Vault 文件名**
（标签就写在文件名里），所以它能跨日期找。

---

## 5. 用 `GetScrollInfo` + `EM_GETSCROLLPOS` / `EM_SETSCROLLPOS`，实现了「删末尾空行后视口跟随」

这是项目里最硬的一处逆向：

```
现象：内容删短后，SCROLLINFO 已算对新值，但行布局和画面停在旧内容上
实测：只有 WM_VSCROLL 能修；WM_SIZE / 重绘 / EM_SCROLLCARET 都不行

做法：
  ① GetScrollInfo 读 nPos / nMax / nPage
  ② EM_GETSCROLLPOS (0x04DD) 读内部像素位置 py，与 nPos 一比 —— 差 >2px 即「脱节」
  ③ EM_SETSCROLLPOS (0x04DE) 写回 nPos，RichEdit 据此重算行布局并重绘
```

**关键守卫**：差值 ≤2px 直接返回 —— 无条件写回会在用户拖滚动条时把它弹回去，
表现就是「滑条拖不动」。

**边缘处理**：删除后 `nPos` 可能比 `nMax - nPage` 多 1（实测 502 对 501），
钳到上界后的结果与「拖一下滚动条」逐像素一致。

---

## 6. 用 `DwmSetWindowAttribute` + `uxtheme\SetWindowTheme`，实现了窗口全要素跟主题染色

| 手段 | 效果 |
| --- | --- |
| `dwmapi\DwmSetWindowAttribute` 属性 **20** | immersive dark mode 开 / 关（按主题底色加权亮度 <128 判断） |
| 属性 **35 / 36 / 34**（Win11 22000+） | 标题栏底色 / 标题文字 / 外框，染成主题的 `win` / `text` / `win` |
| `uxtheme\SetWindowTheme(ed, "DarkMode_Explorer", 0)` | 编辑区滚动条转深色（实测该区域均亮度 40、亮像素 0 个） |

**配套**：`GetWindowLongPtr` / `SetWindowLongPtr` 读写窗口样式（32 位回退到非 `Ptr` 版本）。

**不需要版本判断**：Win10 上后三个 DWM 属性不存在，`DllCall` 静默失败、自然退回系统配色；
深浅本身由属性 20 兜住。

---

## 7. 用 GDI 双 DC + `StretchBlt`（HALFTONE），实现了背景图铺满编辑区

```
CreateCompatibleDC / CreateCompatibleBitmap / CreateDIBSection  → 离屏画布
StretchBlt + SetStretchBltMode(HALFTONE)                        → 高质量缩放
SetBrushOrgEx                                                   → 消除平铺错位
FillRect + CreateSolidBrush                                     → contain 模式铺底色
SelectObject / DeleteObject / DeleteDC                          → 句柄生命周期管理
```

**贴图结构**：背景图是编辑区的**兄弟 Static 控件**（`SS_BITMAP`），编辑区加
`WS_EX_TRANSPARENT` 让它绘制时跳过自身背景 —— 文字于是直接浮在图上。

> 实测结论：子类化 `WM_ERASEBKGND` 自绘**无效**，图会被 RichEdit 在 `WM_PAINT` 里
> 重填背景盖掉；「兄弟控件 + 透明编辑区」是唯一走通的路。

**性能处理**：
- `_ScheduleRender()` 用 `SetTimer -80` 合并 resize 抖动；
- `_RenderNow()` 同矩形直接跳过，只有真重铺过才 `RedrawWindow(ed, INVALIDATE|ERASE)`；
- 实测 1361×1084 连打 40 次 resize 共 **392ms**，前后截图逐像素一致。

---

## 8. 用 `Run` + WT profile / Edge 命令行，实现了外部程序的快捷呼出

**`Alt+C` → PowerShell**

- 启动 `powershell.exe`，但**不传 `Run` 的 `Hide`** —— 隐藏启动会绕过 Windows Terminal
  委派，退回 conhost 默认（120×50、`#012456` 蓝底），拿不到用户的 WT profile 背景。

**`Alt+X` → DeepSeek 网页**

```
msedge.exe --new-window https://chat.deepseek.com/
           --user-data-dir=<独立 profile>
           --window-size=...
```

- 用**独立 profile 的普通 Edge 窗口**（不是 `--app`）：有完整标签栏，能当轻量浏览器；
- `_deepseek.mode` 落盘模式标记识别「老实例」（`--app` 时代遗留），必要时
  `WM_CLOSE` + `ProcessClose` 退掉；
- 用 **WMI**（`ComObjGet("winmgmts:")` + 按命令行筛选）找齐该 profile 下所有进程
  （主进程 + crashpad / gpu / renderer…，实测 9 个）。

**`Alt+Shift+C` → CapsLock 映射**

- `HotkeyRouter.Add("CapsLock", (*) => 0)` 吞掉原功能 + `CapsLock & h/j/k/l` 映射方向键；
  Phase 4 起由 `src/modules/KeysInput/Features/CapsLockFeature.ahk` 在开关时动态加 / 卸，
  Feature 内不再直接调 `Hotkey()`。

---

## 9. 用「事件契约 + `DwmGetWindowAttribute` 读外框」，实现了窗口自动让位对齐

```
发布方（PowerShellFeature / DeepSeekFeature）
  只广播三个生命周期事件：Launcher.Preparing / Launcher.Opened / Launcher.Failed
  ⚠ 不碰笔记窗口 —— Feature 之间零调用

平台（PeerCoordinator）
  · 读伙伴外框：DwmGetWindowAttribute(hwnd, 9, ...)   ← DWMWA_EXTENDED_FRAME_BOUNDS
  · 摆位算法：PlanStack() 算「笔记在上、伙伴在下」的物理外框
  · 广播执行事件：SevenNote.Move → WindowFeature._OnNoteMove()
                  Launcher.Move  → LauncherModule._OnMove()

执行方（各自订阅、只搬自己的窗口）
  · WindowFeature 搬笔记窗口；LauncherModule 搬终端 / 浏览器窗口
  · 落点公式与可摆性闸仍在 PeerLayoutService：
      IsPlaceable / TargetW / TargetH / CornerRect / RectOf
```

**只在第一次适配**：笔记窗口被撞到才让位，随后冻结，归用户自己管（v2.1 起）。

**护栏**：凡在异步 `SetTimer` 回调里碰窗口，先过
`DetectHiddenWindows(false)` + `WinExist` + `!IsIconic` —— 否则对一个已被收起的窗口
`WinMove` 会抛错并弹模态框，整个脚本停摆（v2.4.1 连按 `Alt+C` 卡死即此类）。

---

## 10. 用「数据驱动的热键表」，实现了注册与帮助文档同源

```ahk
class SevenNoteModule {
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!z", group: "窗口", line: "   Alt+Z   呼出 / 隐藏"
                , fn: (*) => WindowFeature.Toggle()},
            ...
        ]
    }
}
```

- **一份数据，两处使用**：`HotkeyRouter.RegisterAll()` 聚合平台 `WorkBench.GetHotkeys()`
  与各模块 `GetHotkeys()` 注册；`WorkBenchUI.BuildHotkeyHelpText()` 遍历同一份数据生成文本；
- 改热键只改所属模块（平台级改 `WorkBench.GetHotkeys()`）—— 这是 `86e76f8`「热键改为表驱动」
  之后、Phase 5 完成「按模块归属」之后才有的性质；
- `ctx` 字段决定用哪套 `HotIf` 上下文：`global` / 窗口激活 / 搜索栏可见；
  表达式由各模块 `GetContexts()` 提供，Router 只负责 `HotIf`。

---

## 11. 用 Ini + 进程内缓存 + `EventBus`，实现了配置、状态与完全解耦

| 组件 | 实现 |
| --- | --- |
| `ConfigService` | `IniRead` / `IniWrite` 包一层，**读一次就缓存**（`GetVault()` 单次保存要调 6 次以上） |
| `State` | 进程内状态：Gui 句柄 / 编辑区句柄 / 当前日期 / 标签 |
| `EventBus` | `Map` + `On(event, fn)` / `Emit(event, ...)` —— 25 个 Feature 之间**零直接调用** |
| `StatusBar` | 三个 Static 控件：日期+星期 / 标签 / 字数+提示 |

**已用的事件**（部分）：`Window.BeforeHide`、`Window.Shown`、`Save.Requested`、
`Date.Changed`、`Date.JumpRequested`、`Launcher.Preparing` / `Launcher.Opened` /
`Launcher.Failed`、`SevenNote.Move` / `Launcher.Move`。

**配置落点**：`_config.ini` 与 `_error.log` 恒在 `%AppData%\SevenWork\`（v2.14 起取消「开发身份」，不再有 `SevenWork-Dev` 与 `.logs\`）；`pandoc.exe` 同目录（100+MB 不重复释放）。
⚠ 缓存带来的代价：运行期手改 `_config.ini` 不生效，改完要重启。

---

## 12. 用 `RunWait` + 内嵌 `pandoc.exe`，实现了 RTF → Markdown 转换

```
"<AppData>\SevenWork\pandoc.exe" "<tmp>\in.rtf" -o "<vault>\2026-09-20.md" --extract-media=...
```

- Pandoc 由 `FileInstall` 打包，首选释放到 `%AppData%\SevenWork\pandoc.exe`；
- **软依赖**：探测不到就降级为纯文本 MD（笔记不丢）；
- **可用性缓存**：探测到「可用」就永久记住 —— 否则每次 `Alt+Z` 隐藏都要 `RunWait`
  起一个 200MB 进程；
- **有效性校验**：`FileGetSize > 1MB`（防打包出 0KB 坏文件）。

---

## 13. 用 `OnError` + 旋转日志，实现了「程序不倒」

- `OnError(OnScriptError)`：未捕获异常 → 写日志（消息 / 文件 / 行 / 调用栈）→ `return 1` **继续跑**；
- 落点：恒为 `%AppData%\SevenWork\_error.log`（v2.14 起取消开发身份，不再落工作树 `.logs\`）；
- 超 **512KB** 自动轮转；
- `#Warn VarUnset, OutputDebug`：未赋值变量警告不再弹模态框。

**为什么必须有**：AHK v2 对未捕获异常的默认动作是**弹模态框并停摆** —— 本项目在迁移期
连踩三次（`JSON.Stringify` 不存在 / `Gui` 当变量名 / 空字符串比较）。

⚠ 兜底只保证「程序不倒」，**不保证「逻辑做对了」**：异步回调里碰窗口 / 控件前仍须自己过闸。

---

## 14. 端到端自动化测试（已移除，待重建）

原 `tests\run_user_journey_demo.ps1` 用「源码内存替换 + 拼接驱动」跑沙箱用户旅程。
2026-10-19 为工作台化重构删除：单文件锚点在拆模块后必然失配，且临时脚本放在 `%TEMP%`
时无法解析相对 `#Include`。重构完成后按 `src/modules/` 的模块接口重建端到端测试。

---

## 15. 用 PowerShell + C#（`Add-Type`）+ GDI 类，实现了背景图烘焙工具链

`tools\rebake-backdrop.ps1`：按编辑区比例裁（0.917）→ 缩到 2400 宽 → **V 空间等比缩放**
调明暗 → 在成品尺寸上 unsharp。

**为什么做成离线工具而不是运行时**：运行时遮罩按色混合会掉饱和度；离线在 V 空间等比缩放，
`S = 1 - min/max` 不变，饱和度一丝不掉（实测 42.2% → 44.1%）。

`tools\pick-theme-colors.ps1`：从图里取均色 / luma 分位，产出可粘贴的 `Themes` 条目。

---

## 一句话总括

> **用 AHK v2 作宿主，把 RichEdit 当作可编程富文本引擎，用 Win32 消息 + Dwm/Uxtheme + GDI
> 补齐 RichEdit 不提供的滚动、主题、背景图能力；用 Pandoc 做格式出口；用 EventBus + 四层架构
> 把 21 个功能拆成互不依赖的插件；最后按模块接口重建端到端验证。**

---

## 维护说明

- 本文**只做索引**，技术事实以 `src/SevenWork.ahk` 为准；消息号与 API 名随版本可能漂移；
- 改动下列任一模块时顺手更新对应条目：

| 改了什么 | 更新哪条 |
| --- | --- |
| 换编辑器控件 / 窗口样式 | 1 |
| RTF 读写、双编码策略 | 2 |
| 字符格式、行操作 | 3 |
| 搜索实现 | 4 |
| 滚动同步 / 视口跟随 | 5 |
| 主题、标题栏、滚动条染色 | 6 |
| 背景图铺贴 | 7 |
| `Alt+C` / `Alt+X` / CapsLock | 8 |
| 伙伴窗口让位契约 | 9 |
| 热键表 | 10 |
| 配置、事件、状态栏 | 11 |
| Pandoc 链路 | 12 |
| 异常兜底、日志 | 13 |
| 演示测试 | 14 |
| 烘图 / 取色工具 | 15 |
