# 平台能力（WorkBench/Capabilities）

> 平台能力是**跨模块复用、但不认识任何业务**的纯能力。
> 它不读 `Config` / `State`，不发 `EventBus` 事件，不调用 `LogError`，
> 也不 `#Include` 任何 `modules/*` 文件；失败时返回结构体，由调用方决定怎么处理。

---

## 1. 目录

```text
src/WorkBench/
├─ Kernel/                     骨架：生命周期 / 状态 / 事件 / 配置（冻结）
├─ Capabilities/               平台能力：纯能力，无业务、无时间、无理由
│  ├─ Placement/
│  │  ├─ RectMath.ahk          纯几何：堆叠方案、外框换算、角点、相交
│  │  ├─ WindowProbe.ahk       窗口 / 工作区事实查询
│  │  └─ PlacementExecutor.ahk 唯一搬窗口出口
│  ├─ Graphics/
│  │  ├─ BackdropService.ahk   背景图图层 + 位图合成
│  │  └─ UiPaint.ahk           Win32 染色原语：标题栏 / 窗口主题 / ListView / Edit / ComboBox
│  ├─ Shell/
│  │  └─ ExplorerProbe.ahk     按真实路径找资源管理器窗口 + 读选中项
│  └─ Document/
│     ├─ PandocRunner.ahk      单文件格式转换（pandoc 定位 + 调用）
│     └─ DocxHeadingFix.ahk    docx 预处理：标题样式名 → heading N + 编号固化入口
│        DocxNumberFix.ahk     把 Word 的自动标题编号（第 1 章 / 1.1 / 1））写成文字
├─ Services/                   平台服务：业务策略，**可读 Config / State**
│  └─ ThemeService.ahk         主题表（当前只留「琉璃 · 极光霜」）+ 语义色板 Palette()
├─ Coordinator/                跨模块协调：读业务上下文、发事件、算几何
│  └─ PeerCoordinator.ahk
├─ ModuleRegistry.ahk
├─ HotkeyRouter.ahk
├─ PanelHostBridge.ahk         工作台面板的宿主对象（数据聚合 + saveSettings + 主题 JSON）
├─ WebWindow.ahk               WebView2 窗口骨架（建窗 / 隐藏态定位 / 露面后挂载 / Esc / 换主题）
├─ WebPanelUI.ahk              工作台面板窗口（WebView2）：停哪一页 + 跨模块开页请求
└─ WorkBench.ahk               组合根：装配 5 个模块
```

`Coordinator/` **不并进** `Capabilities/`：协调器必须读 `Config`、订阅 / 发布事件，
按定义就不是纯能力。目录名保留 `Coordinator`，避免无收益的重命名。

---

## 2. 四条硬边界

1. **不反向依赖**
   `Capabilities` 只能调用 Win32 / AHK 内置函数与同层能力；不得 `#Include` 或引用
   `modules/*`、`EventBus`、业务 `Config` / `State`、`LogError`。
2. **只收数据，不收业务对象**
   需要窗口就收 `hwnd`，需要尺寸就收数字 / `Rect`；不要传 `Gui` 之外的业务类，
   也不要让能力去 `State.GetEd()` 找目标。
3. **失败返回结构体**
   统一返回 `{ok: true}` / `{ok: false, reason, error?}`；不弹框、不写业务日志、
   不抛未捕获异常。调用方负责回退与记录。
4. **单位写清楚**
   `RectMath` / `WindowProbe` / `PlacementExecutor` 的坐标与尺寸**一律物理像素**，
   与 `WinGetPos` / `WinMove` 同单位。
   `BackdropService.Render(x,y,w,h)` 是唯一例外：它直接喂 `GuiControl.Move`，
   入参沿用 AHK 的**逻辑单位**；内部再用 `GetWindowRect` 读回物理尺寸来合成位图。

---

## 3. 数据契约

### Rect

```ahk
{x: 0, y: 0, w: 0, h: 0}
```

左上角坐标 + 宽高，物理像素。`w` / `h` 必须大于 0 才能进入几何计算。

### Frame

```ahk
{l: 0, t: 0, r: 0, b: 0}
```

窗口外框比「可见边界」多出来的不可见调整边框（含 DWM 阴影）。
`l` / `t` 通常为负，`r` / `b` 通常为正。由 `WindowProbe.InvisibleFrame` 实测，
不在能力层写死。

### WorkArea

```ahk
{x: 0, y: 0, w: 1920, h: 1040}
```

显示器工作区（已扣掉任务栏），物理像素。

### MoveData

```ahk
{hwnd: 0, x: 0, y: 0, w: 0, h: 0}
```

`PeerCoordinator` 通过 `Launcher.Move` / `SevenNote.Move` 广播的载荷，
也是 `PlacementExecutor.Move` 认的形状。

### Result

```ahk
{ok: true}
{ok: false, reason: "no-fit"}
{ok: false, reason: "render-failed", error: "..."}
```

`reason` 是稳定、可供调用方分支的短字符串；`error` 只用于附带底层异常文本。

---

## 4. API

### 4.1 `RectMath`（纯几何）

```ahk
RectMath.PlanStack(peerRect, workArea, noteFrame, peerFrame, opts)
```

`opts = {gap, margin, minW, minH}`，全部物理像素。

返回：

```ahk
{ok: false, reason: "bad-peer-rect" | "bad-work-area" | "bad-opts" | "no-fit"}

{ok: true,
 note:     {x, y, w, h, frame},   ; 笔记窗口可见边界
 noteRect: {x, y, w, h},          ; WinMove 用的物理外框
 peer:     "",                    ; 伙伴不需要移动
 peerRect: {hwnd, x, y, w, h}}    ; 原样带回

{ok: true,
 note:     {x, y, w, h, frame},
 noteRect: {x, y, w, h},
 peer:     {hwnd, x, y},          ; 伙伴需要下移
 peerRect: {hwnd, x, y, w, h}}
```

语义与旧 `PeerCoordinator.PlanStack` 逐项一致：

1. 方案一：伙伴原地不动，笔记填伙伴上方；
2. 方案二：伙伴已贴顶、上方放不下，则伙伴下移到底边贴工作区底，笔记仍在上；
3. 都放不下 → `{ok:false, reason:"no-fit"}`。

其它纯函数：

| 方法 | 作用 |
| --- | --- |
| `RectMath.Physical(note)` | 可见边界 → `WinMove` 认的物理外框 |
| `RectMath.Overlaps(a, b)` | 两个矩形是否相交 |
| `RectMath.CornerRect(workArea, w, h, offsetRight := 0, offsetBottom := 0)` | 贴右下角的落点 |

> `RectMath` 不判断窗口在不在、可不可见、在哪个屏 —— 那些是 `WindowProbe` 的事。

### 4.2 `WindowProbe`（窗口事实）

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `IsPlaceable(hwnd)` | `bool` | 存在 + 可见 + 未最小化；隐藏 / 最小化一律 `false` |
| `RectOf(hwnd, allowHidden := true)` | `Rect` 或 `""` | 读物理外框；默认允许隐藏窗口 |
| `InvisibleFrame(hwnd)` | `Frame` | DWM 可见边界与外框的差；拿不到时全 0 |
| `WorkAreaFor(rect)` | `WorkArea` 或 `""` | 按矩形中心点找显示器，找不到回落主屏 |
| `PrimaryWorkArea(monIdx := 0)` | `WorkArea` | 指定显示器工作区；0 = 主屏 |
| `IsUsableRect(x, y, w, h)` | `bool` | 是否与任一显示器工作区相交；过滤最小化停放位 |

`RectOf` 内部自行开关 `DetectHiddenWindows` 并恢复原值，不把全局可见性语义留给调用方。

### 4.3 `PlacementExecutor`（唯一搬窗口出口）

```ahk
PlacementExecutor.Move(hwnd, rect, allowHidden := false)
```

- `allowHidden = false`：先过 `WindowProbe.IsPlaceable`，隐藏 / 最小化窗口直接返回
  `{ok:false, reason:"not-placeable"}`；
- `allowHidden = true`：用于 `Show("Hide")` 之后的笔记窗口，但仍拒绝最小化窗口；
- 成功返回 `{ok:true}`。

失败 `reason`：`bad-input` / `bad-rect` / `not-placeable` / `not-found` /
`minimized` / `move-failed`。

`Launcher.Move` / `SevenNote.Move` 这两条**事件驱动的搬窗口**都从这里走，模块层不再各写一套
`DetectHiddenWindows` + `WinMove`。Feature 自己的首次落点（终端 / DeepSeek / 笔记窗口）
仍由各自 Feature 负责，因为它们各自带生命周期判断。

### 4.4 `BackdropService`（背景图）

```ahk
BackdropService.Attach(g, targetHwnd)
```

在 `g` 上创建承载背景图的 `Static`，并压到 `targetHwnd` 之下。
`targetHwnd` 由 Feature 传入（通常是编辑区），能力层不查 `State`。
返回 `{ok:true}` / `{ok:false, reason:"bad-target" | "attach-failed"}`。

```ahk
BackdropService.SetImage(path)
BackdropService.SetFit("cover" | "contain")
BackdropService.SetMask(hexRGB, alphaPercent)
BackdropService.SetVisible(on)
BackdropService.HasImage()
```

```ahk
BackdropService.Render(x, y, w, h)
```

`x/y/w/h` 是 `GuiControl.Move` 的逻辑单位；内部从 `GetWindowRect` 读回物理像素再合成。
返回 `{ok:true}` / `{ok:false, reason}`。`reason` 包括：

`not-attached` / `bad-size` / `no-image` / `load-failed` /
`ctrl-size-failed` / `compose-failed` / `render-failed`

> **Feature 的失败责任**：`BackdropFeature._Apply` 只有在 `Render().ok` 为真时才把编辑区
> 设为 `WS_EX_TRANSPARENT`；失败时恢复不透明、隐藏图层、清掉尺寸记忆，退回主题纯色。
> 绝不能留下「编辑区透明 + 没有图」的组合。

### 4.5 `ExplorerProbe`（资源管理器窗口）

```ahk
ExplorerProbe.ListWindows()          ; → [{hwnd, path}, ...]
ExplorerProbe.FindFor(path)          ; → hwnd；找不到为 0
ExplorerProbe.SelectedPaths(hwnd)    ; → [路径, ...]；没有选中项为 []
ExplorerProbe.IsExplorerWindow(hwnd) ; → bool
ExplorerProbe.SamePath(a, b)         ; → bool
ExplorerProbe.NormalizePath(path)    ; → 归一化后的路径串
```

按**真实路径**找资源管理器窗口：读 `Shell.Application.Windows` 的
`Document.Folder.Self.Path`，再与目标路径做归一化比对（去两端空白与末尾反斜杠、统一大小写；
盘根 `D:\` 保留反斜杠）。

窗口标题是**文件夹名**（`Documents`、`本地磁盘 (C:)`），重名与本地化都靠不住，所以不用它。

- 失败（COM 不可用 / 遍历中途出错）返回 `0` 或已收集到的部分数组，**不抛错**；
- 没有文件夹路径的壳窗口（「此电脑」/「快速访问」/ 桌面）会被跳过；
- ⚠ 被 `WinHide` 藏起来的窗口**仍然在集合里**（实测：隐藏后 `FindFor` 照常返回原 `hwnd`），
  而 `WinExist` 在 `DetectHiddenWindows(false)` 下会返回 `0` —— 判断「这个文件夹有没有开着的窗口」
  只能走本能力，不能靠 `WinExist`；
- 本能力**只查不动**：显示 / 隐藏 / 激活都由调用方负责（`FolderWindowFeature`）。

`SelectedPaths(hwnd)` 读 `Document.SelectedItems`，**文件与文件夹都返回** ——
`item.Path` 对两者都适用，「该转目录还是跳过」属于调用方的策略（`FileConvertService.Plan`
判 `is-folder`）。壳窗口的 `Document` 是 `Null`（for-in 会抛错），由内层 `try` 兜住、
已收上来的部分照常返回；`hwnd` 统一 `Integer()` 后再与 `w.HWND` 比，接受字符串形式的句柄。

---

### 4.6 `PandocRunner`（单文件格式转换）

```ahk
PandocRunner.ResolveCmd(preferredPath)          ; → 带引号的绝对路径；不可用则退回 "pandoc.exe"
PandocRunner.IsUsableExe(path)                  ; → bool（存在且 ≥ 1MB）
PandocRunner.Convert(cmd, src, dst, mediaDir)   ; → {ok:true, size} / {ok:false, reason, code?}
```

`preferredPath` 由调用方传入（通常是 `Config.PandocPath`）—— **本能力不读 Config**。
`mediaDir` 传 `""` 表示不抽图。

转换时不传 `-f`：pandoc 3.11 认得 50 余种输入格式（`docx` / `odt` / `rtf` / `epub` / `html` /
`latex` / `pptx` / `xlsx` / `csv` / `ipynb` …）且随版本增长，写死 `-f` 就得跟着维护一张表。
它认不得的（`pdf` / `doc`）由调用方提前判掉、给用户一句人话。

`reason` 包括：`no-cmd` / `bad-arg` / `src-missing` / `run-failed` / `pandoc-exit` / `no-output`。

- ⚠ **不经 `cmd /c`**：`RunWait` 直接拉起 exe。实测（2026-10-21，AHK v2.0.27 + pandoc 3.11）
  `cmd /c ""<exe>" <args>"` 与 `cmd /s /c ""<exe>" <args>"` 都让 pandoc 以退出码 1 结束、
  目标文件不生成，只有直接 `<exe> <args>` 能成。代价是**拿不到 stderr 原文**
  （重定向只有 shell 支持）—— 失败只带回退出码，由调用方记日志；
- 失败时若目标文件已被 pandoc 建出来（0 字节），本能力负责删掉它 ——
  留着会让下一次被「已存在」判断永久跳过（调用方已保证 `dst` 原本不存在）；
- 退出码 0 但目标文件不存在时返回 `no-output`（磁盘满 / 目标被占），不谎报成功。

> 与 `modules/SevenNote/Services/PandocService.ahk` 是**两份实现**，不是漏改：那份是笔记保存
> 链路专用（RTF 输入 + 图片搬 `_assets` + 可用性缓存 + 后处理），改它要动「每次 `Alt+Z` 都跑」
> 的路径，风险与收益不成比例。本能力只做通用单文件转换。

转换永远带 `--markdown-headings=atx`：pandoc 的 `markdown` writer 默认 **setext**，
H1/H2 会写成「标题 + `====` 下划线」，多数编辑器的大纲面板只认 `#` 开头（ATX）；
`gfm` / `commonmark` writer 的默认值本来也是 `atx`，所以这条对谁都不算意外。

---

### 4.7 `DocxHeadingFix` / `DocxNumberFix`（docx 预处理）

```ahk
DocxHeadingFix.Prepare(src, workDir)      ; → {ok:true, path, changed, numbered, warnings, cleanup} / {ok:false, reason, detail}
DocxHeadingFix.FixStyles(xml)             ; → {xml, count}（纯函数，改 styles.xml 文本）
DocxHeadingFix.LevelOf(styleName)         ; → 1..9 / 0（0 = 不是标题样式，或已是 heading N）

DocxNumberFix.FixDocument(docXml, stylesXml, numXml)  ; → {ok, xml, numbered, skipped, warnings}
DocxNumberFix.StripStyleNumbering(stylesXml)          ; → {xml, stripped}
```

`Prepare` 一次做两件事：**把自动标题编号固化成文字** + **把自定义样式名规范化成 `heading N`**。

**为什么需要它**：pandoc 的 docx reader 只把 `w:name` 为 `heading 1`..`heading 9` 的样式
当标题。国内课件爱自定义「二级标题」「三级标题」「半括号标题（五级）」「圆括号标题（六级标题）」
这类样式名 —— Word 里层级、编号、导航窗格一切正常，pandoc 却**一个标题都不输出**，
整篇塌成嵌套有序列表，Markdown 编辑器里大纲是空的。

实测（2026-10-21，尚硅谷 NLP 课件 23MB，pandoc 3.11）：

| 状态 | `Header` 数 | md 里的标题 |
| --- | --- | --- |
| 原文档 | **0**（20088 行 AST 里一个都没有） | 无，全是 `1.` / `2.` 列表 |
| 改过 `styles.xml` 后 | 215 + 8 | `#` 8 / `##` 32 / `###` 55 / `####` 34 / `#####` 53 / `######` 41 |

`##`..`######` 的数量与 `styles.xml` 里 `a0`..`a4` 的使用次数**逐项相等** —— 一一对应，
不是猜的。

**做法**：不改源文件。`tar.exe -xf` 解到 `workDir` → 改 `word/styles.xml` 里那几个
`<w:name w:val="…"/>` → `tar.exe -a -cf` 打回 `.zip` 再改名 `.docx` → 交给 `PandocRunner`。

- `changed = 0 && numbered = 0` 表示这份文档既没有要改的样式名、也没有可固化的编号 →
  `path` 返回 `src` 本身，`cleanup = false`（省掉一次打包）；
- `reason`：`bad-arg` / `no-tar` / `no-workdir` / `no-extract` / `no-styles` / `no-pack`
  （`no-styles` 现在带 `detail`，否则一句 reason 看不出是读文件、编号固化还是改样式名出的问题）。
  调用方任何一种失败都**直接转原件**，转换照常进行；
- `LevelOf` 的规则：`^heading [1-9]$` → 0（不动）；`N级标题` → N；`（N级` → N；
  `^标题 [1-9]$` → N。字符样式（`w:type="character"`）一律不动。

- ⚠ **必须用 `tar … -C dir *`，不能用 `.`**：`.` 打出来的条目名带 `./` 前缀
  （`./word/media/image1.png`），而 OPC 包内路径是 `word/media/...`。pandoc 照样读得到
  `document.xml`，却找不到图片 —— `--extract-media` 时**静默丢图**（实测 145 张一张不剩，
  md 里连 `![]` 都没有，退出码仍是 0）。换 `*` 后 144 张图正常抽出；
- 输出 zip 必须在**被打包目录之外**，否则会把自己也打进去；
- 依赖 Windows 10 1803+ 自带的 `bsdtar`（`C:\Windows\System32\tar.exe`）。AHK v2 没有 zip
  能力，这是最少依赖的一条路。实测 23MB 课件：解压 148ms + 打包 760ms。

**编号固化（`DocxNumberFix`）**：Word 的「第 1 章 / 1.1 / 1）」不是正文文字，而是
「样式 → `numPr` → `numbering.xml` 的多级模板」渲染出来的；pandoc 只取段落文字，
模板编号整体消失 —— 标题层级还在（`##`），编号全没了。

`Prepare` 里的顺序是**固化编号 → 删样式编号 → 改样式名**，三步不能换：

1. `FixDocument` 按 `lvlText`（`第 %1 章`、`%1.%2`、`（%6）`…）逐级算编号，写进标题段落
   第一个 `w:t`，同时把该段落 `numPr` 改成 `numId=0`；
2. `StripStyleNumbering` 删掉标题样式上的 `numPr`；
3. `FixStyles` 才把样式名改成 `heading N`。

- ⚠ **必须靠样式名判断标题，所以要放在改名之前**：「半括号标题（五级）」一旦变成
  `heading 5`，`LevelOf()` 返回 0，这些标题的编号会静默漏掉；
- ⚠ **只固化编号不够，还得清 numPr**：实测只做第 1 步时 pandoc 仍把标题当 `OrderedList`，
  整篇输出成「1. NLP导论 / 1. 定义」，一个标题都没有；
- ⚠ `numId=0` 是「显式取消编号」：遇到它**不补号、也不推进计数**，否则本无编号的标题
  会冒出序号、后面的编号整体错位（实测样本里的「完整案例如下：」）；
- 只处理标题样式，`bullet` 级别跳过 —— 那是真列表，交给 pandoc；
- 不认识的编号格式（罗马数字等）按十进制写入，并在 `warnings` 里留一条；
- ⚠ 切段落时 `last` 必须按**原始长度**推进：`_ClearNumbering` 会改长段落，用改后的长度
  让后续切片错位，产出的 docx 结构损坏 —— pandoc 只给一句 `couldn't parse docx file: DocxError`。

实测（2026-10-23，同一份 23MB NLP 课件）：223 个标题、编号逐级对上
（`# 第 1 章 NLP导论` / `## 1.1 定义` / `### 1.2.1 文本分类` / `##### 1）安装pytorch`），
`完整案例如下：` 保持无编号，155 张图与相对路径不变。

---

### 4.8 `UiPaint`（Win32 染色原语）

```ahk
UiPaint.TitleBar(hwnd, winHex, textHex)   ; → true / false（无 hwnd 时 false）
UiPaint.WindowTheme(hwnd, dark)           ; → true / false
UiPaint.ListView(hwnd, bgHex, fgHex)      ; → true / false
UiPaint.EditColors(hwnd, bgHex, fgHex)    ; → true / false（Edit / ComboBox）
UiPaint.ReleaseColors(hwnd)               ; → true / false（可选，不调也有 Sweep 兜）
UiPaint.Sweep()                           ; → 清掉的失效条目数
UiPaint.GdiCount()                        ; → 本进程 GDI 对象数（探针用）
UiPaint.Bgr(hexRGB)                       ; → COLORREF（0x00BBGGRR）
UiPaint.IsDark(hexRGB)                    ; → bool
```

**只收 hwnd + `RRGGBB` 字符串 + 布尔**，不认主题对象、不读 `Config` / `State`、不发事件。
配色由调用方（`ThemeService.Palette()`）算好再传进来 —— 能力层只管「把这个颜色刷上去」。

| 方法 | 干了什么 | 失败时 |
| --- | --- | --- |
| `TitleBar` | `DWMWA_USE_IMMERSIVE_DARK_MODE`（20，退 19）+ Win11 的 `35/36/34` 染标题栏 / 标题文字 / 外框 | 静默退回系统配色（Win10 无后三个属性） |
| `WindowTheme` | `SetWindowTheme` 设 `DarkMode_Explorer` / `Explorer` | 静默退回系统主题（老系统没有前者） |
| `ListView` | `LVM_SETBKCOLOR` / `SETTEXTCOLOR` / `SETTEXTBKCOLOR` + 双缓冲 + `InvalidateRect` | `SendMessageW` 失败不报错（控件已销毁） |
| `EditColors` | 登记 hwnd → `{bg, fg, brush}`，挂 `WM_CTLCOLOREDIT / LISTBOX / STATIC` 按 hwnd 分发；ComboBox 顺带登记**内部 Edit** | 返回 `false`（hwnd 无效），不抛 |

全都不返回值给业务判断「要不要回退」：染色失败只影响观感、不影响功能，让调用方写分支
反而会诱使它在失败时做危险动作（比如把窗口藏起来）。

⚠ **GDI 必须成对管理**：`EditColors` 每个控件建一个 `CreateSolidBrush`，同一 hwnd 同色重复登记
直接跳过；换色时先 `DeleteObject` 旧 brush 再建新的；控件销毁后靠 `Sweep()` 清（每次
`EditColors` 都会顺手调一次）。实测连切 16 次主题、反复开关编辑窗，GDI 对象数稳定不涨。

⚠ **可编辑 ComboBox 是两层窗口**：`WM_CTLCOLOREDIT` 的 `lParam` 是它**内部的 Edit 子窗口**
（`parent = ComboBox`），不是 ComboBox 自己的 hwnd。只登记 ComboBox 会让编辑区继续是系统白
（深色主题下一块刺眼的白板）。`EditColors` 内部用 `FindWindowExW(cb, 0, "Edit", 0)` 顺手登记 ——
别改用 `GetComboBoxInfo`（本机实测一直返回 0）。

⚠ **`ListView` 的 `SendMessage` 必须直发 hwnd**：内置 `SendMessage(msg, wParam, lParam, Control)`
的第 4 个参数是 **Control 不是 WinTitle**，传 `hwnd` 会被当成窗口标题去找、静默失败（列表全白）。
用 `DllCall("SendMessageW", "ptr", hwnd, ...)`，改完再 `InvalidateRect + UpdateWindow` 立刻重画
（只发消息不重画，要等窗口自己去 repaint）。

## 5. 不该放进 `Capabilities` 的东西

| 东西 | 原因 | 留在哪 |
| --- | --- | --- |
| `PeerCoordinator` | 读 `Config`、订阅 / 发布事件、保存最近落位 | `WorkBench/Coordinator/` |
| `PeerLayoutService` | 带 Launcher 策略（`TargetW/H`、`Config.PlaceRight`） | `modules/Launcher/Services/` |
| `BackdropFeature` | 决策该不该铺、失败怎么回退 | `modules/SevenNote/Features/` |
| 主题 / 字体 / 保存 | 业务规则、配置、用户旅程 | 对应 Feature / Service |
| `HotkeyRouter` | 应用级热键注册（上下文名由各模块 `GetContexts()` 提供） | `WorkBench/` |

`PeerLayoutService` 只把通用的 `IsPlaceable` / `RectOf` / `CornerRect` 内部委托给能力层；
`TargetW` / `TargetH` 与 `Config.PlaceRight` 仍由它自己解释。

---

## 6. 调用方向

```text
Feature / Module
      │
      ├──► Capability（RectMath / WindowProbe / PlacementExecutor / BackdropService
      │               / ExplorerProbe / PandocRunner / DocxHeadingFix）
      │         │
      │         └──► Win32 / AHK 内置
      │
      ├──► Service（业务策略）
      └──► Kernel（State / EventBus / Config）

Coordinator
      ├──► Capability
      ├──► Config
      └──► EventBus
```

- `Capability` **不反向**调用 `Feature` / `Service` / `Coordinator`；
- `Feature` 之间仍然零调用，跨模块通过 `EventBus`；
- `Capability` 层内部也不互相发事件；需要组合时由调用方按顺序调用。

---

## 7. 验证清单

改完能力层至少跑三条：

1. **纯几何对拍**：`RectMath.PlanStack` 覆盖
   伙伴在下 / 伙伴贴顶下移 / 放不下 / 副屏 / 100% 与 150% DPI 的最小尺寸；
2. **能力独立性**：`Capabilities` 目录内不得出现 `State.` / `Config.` /
   `EventBus.` / `LogError(` 的**调用**（注释里的说明不算）；
3. **真机启动**：根启动器 `SevenWork.ahk` 用 `/ErrorStdOut` 起来，
   `stderr` 为空、`_error.log` 无新增，再按 `Alt+Z` / `Alt+T` 看窗口与主题。

语法预检的 `ExitApp()` 注入**抓不到 class 体内错误**，必须再做真机启动；
具体命令见 `.clinerules/04-workflow.md`。

---

## 8. 当前边界说明

- `WorkBench.ahk` 仍硬编码模块清单（SevenNote / Launcher / KeysInput / Text / Folders），
  本轮不改成 `WorkBench.Init(modules)`；
- `HotkeyRouter` 的上下文**已改为表驱动**（加 Text 模块时一并做的）：注册哪些 ctx
  由各模块 `GetContexts()` 决定，Router 里不再有 `global` / `editor` / `search` 字面量。
  改之前新模块加上下文必须回来改 Router，漏改的后果是它的 `Esc` / `Enter` 一条都不注册；
  现在 `_ApplyContext` 按表查、`RegisterAll` 遍历 contexts 的键，新 ctx 自动生效。
  它仍属于应用级机制，不在能力层；
- `PeerCoordinator.GetLastNote/GetLastPeer` 暂无调用方，保留给探针与后续协调；
  若确认不需要，可单独删除，不影响能力层。
