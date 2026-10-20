# 04 · 验证与工作流

## 改完必须验证

**不要只靠"读代码觉得没问题"就宣称改好了。** 改完 `.ahk` 必须用真实解释器跑一次语法检查。

### 先验编码与换行（编辑器可能整文件改写）

`.gitattributes` 规定 `*.ahk` 用 **CRLF**、`*.md` 用 **LF**，源码 **UTF-8 无 BOM**。
但有些编辑器 / 工具在整文件写回时会**把 CRLF 统一成 LF** —— 实测一次改动就把
`src\SevenWork.ahk` 全转成裸 LF（4352 行），`git diff` 整文件变色、`CRLF=0`。

```powershell
$src='d:\03-PersonalFiles\02-GitHubFiles\SevenNote-AutoHotKey\src\SevenWork.ahk'
$b=[System.IO.File]::ReadAllBytes($src)
'BOM=' + (($b[0] -eq 0xEF) -and ($b[1] -eq 0xBB))
$t=[System.IO.File]::ReadAllText($src,[System.Text.Encoding]::UTF8)
'CRLF=' + ([regex]::Matches($t,"`r`n").Count) + '  bareLF=' + ([regex]::Matches($t,"(?<!`r)`n").Count)
```

期望 `BOM=False`、`bareLF=0`。根启动器 `SevenWork.ahk` 也要同样过一遍。
若 `CRLF=0`（全裸 LF），这样转回来（保持无 BOM）：

```powershell
$t = $t -replace "`r`n","`n"; $t = $t -replace "`n","`r`n"
[System.IO.File]::WriteAllText($src, $t, [System.Text.UTF8Encoding]::new($false))
```

> ⚠ **正则必须写在双引号里。** 写成单引号 `'(?<!`r)`n'` 时 PowerShell **不做反引号转义** ——
> 它变成「匹配字面 `` `n ``（反引号 + n）」的正则，后果是双向的：① 检测把源码里的 AHK
> 换行转义当成裸 LF 报出来（实测 `src\SevenWork.ahk` 报 `bareLF=9`，字节级统计其实是 **0**）；
> ② 照它去「修」会把 9 处 `` `n `` **替换成真换行**，`OnScriptError` 里的多行字符串当场
> 报 `Missing """`、脚本起不来，只有 `git checkout` 能救回（2026-10-20 实测踩到）。
> **判换行只认字节**：`0x0D 0x0A` = CRLF、单独 `0x0A` = 裸 LF、单独 `0x0D` = 裸 CR。
> ```powershell
> $b=[System.IO.File]::ReadAllBytes($f); $crlf=0;$cr=0;$lf=0
> for($i=0;$i -lt $b.Length;$i++){
>     if($b[$i] -eq 13 -and $i+1 -lt $b.Length -and $b[$i+1] -eq 10){ $crlf++;$i++ }
>     elseif($b[$i] -eq 13){ $cr++ } elseif($b[$i] -eq 10){ $lf++ }
> }
> ```

### 语法检查

⚠️ **`/validate` 不可用** —— 本机 AHK v2.0.27 不识别该参数。别用。

实测症状：AHK 会把 `/validate` 当成脚本路径去找，找不到就**弹出模态错误框**
（标题是脚本名，正文形如 `Error: Invalid assignment.`），进程**卡住不退出**，
窗口一直挡在屏幕上，只能手动杀进程收拾。

#### 方案 A（预检，有盲区）：注入 `ExitApp()`

```powershell
$exe = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$src = 'd:\03-PersonalFiles\02-GitHubFiles\SevenWork-AutoHotKey\src\SevenWork.ahk'
$dir = 'd:\03-PersonalFiles\02-GitHubFiles\SevenWork-AutoHotKey\src'   # 预检脚本必须与主脚本同目录，否则相对 #Include 找不到
$L   = [System.IO.File]::ReadAllLines($src)
$tmp = "$dir\_syn_check.ahk"
$out = @('#Requires AutoHotkey v2.0','ExitApp()') + $L[1..($L.Count-1)]
[System.IO.File]::WriteAllText($tmp, (($out -join "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))
$se  = "$env:TEMP\SevenWorkDev\_syn_err.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $se) | Out-Null
$r   = Start-Process -FilePath $exe -ArgumentList @('/ErrorStdOut', "`"$tmp`"") `
         -RedirectStandardError $se -Wait -PassThru
"退出码 = $($r.ExitCode)"     # 0 = 通过
Get-Content $se               # 空 = 没有语法错误
Remove-Item $tmp -Force
```

> ⚠ **别用 `& $exe ...` 判断退出码 —— 它是 GUI 子系统程序，PowerShell 的调用运算符不等它。**
> `$LASTEXITCODE` 会保持上一次的值（通常是 `0`），看起来「一切通过」，实际脚本可能压根没跑。
> 实测：最小脚本（`FileAppend` + `ExitApp`）用 `&` 跑，连输出文件都没生成，退出码照样 `0`；
> 换成 `Start-Process -Wait -PassThru` 才拿到真实的 `ExitCode`。
> **每次都要用坏样本反向验证一次**（见下），否则无法区分「真通过」和「根本没跑」。

**实测基准**：`src\SevenWork.ahk` 退出码 `0`、stderr 空；
坏样本用**未闭合字符串**（`x := "abc`）→ 退出码 `2`、stderr 打 `(2) : ==> Missing """`。

> ⚠ **坏样本别用行尾 `x :=`** —— AHK v2 支持行尾运算符续行，`x :=` 与下一行会被拼成
> `x := ExitApp()`，语法完全合法、退出码 `0`，白白浪费一轮排查（2026-10-21 实测踩到）。

> ⚠ **但它有盲区，别只靠它。** 实测踩到：往 `ThemeService.Themes` 数组追加主题时漏了元素间
> 的逗号，这个预检**退出码照样是 `0`**，而真机启动立刻报
> `src\SevenWork.ahk (946) : ==> Unexpected "{"`。
>
> 原因：`ExitApp()` 在第 2 行，AHK v2 **并非**「加载时完整解析整个文件」——
> auto-execute 段跑到 `ExitApp()` 就退出了，**后面那些 class 定义根本没被解析**。
> 所以这个预检能抓「auto-execute 段及其之前」的错误，**抓不到 class 体内的**。

#### 方案 B（真机验证，必做）：直接启动 + 抓 stderr

改完必须用这个兜底 —— 它就是方案 A 漏掉的那一半：

```powershell
$exe = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$script = 'd:\03-PersonalFiles\02-GitHubFiles\SevenWork-AutoHotKey\SevenWork.ahk'   # 根启动器；会 #Include src\SevenWork.ahk
$se = "$env:TEMP\SevenWorkDev\_run_err.txt"
Remove-Item $se -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $exe -ArgumentList @('/ErrorStdOut', "`"$script`"") `
    -RedirectStandardError $se | Out-Null
Start-Sleep -Seconds 6
Get-Content $se          # 空 = 没有运行时/语法错误
Get-Process -Name AutoHotkey64 | Stop-Process -Force   # 收工，别留实例
```

⚠️ **两种错误形态要分清**：

| 现象 | 含义 | 怎么查 |
| --- | --- | --- |
| stderr **有内容** | 有语法/运行时错误，AHK 已退出 | 直接读 stderr，给出行号 |
| stderr **为空**、但多出一个标题是**脚本名**（`SevenWork.ahk`）的窗口 | 弹了模态错误框，进程**卡着不退**，`ExitApp` 也没用 | 见下方「错误框抓法」 |

⚠️ **窗口没出来 ≠ 出错**。`SevenWork` 的窗口**启动时不显示**——
`g.Show()` 只在 `WindowFeature.Show()`（`!z` 热键）路径里由 `_PlaceWindow` 调用。
所以启动后枚举窗口会看到 `AutoHotkeyGUI / title=SevenWork / vis=False / 0x0 at 0,0`，
那是**正常**的。要看到窗口得先发一次 `Alt+Z`：

```powershell
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('%z')
```

**错误框抓法**（stderr 为空却卡着时）：

```powershell
# AHK 报错框的类名是 #32770、标题是脚本名；正文在 Static 子控件里，
# 跨进程 GetWindowText 读不到 —— 用本机 AHK 的 WinGetText 最省事
DetectHiddenWindows true
Loop {
    hwnd := WinExist("ahk_class #32770")
    if !hwnd
        break
    MsgBox WinGetText("ahk_id " . hwnd)   ; 或写文件后读
}
```

> 更快的路子：**改完直接按方案 B 跑一遍**。它同时覆盖 auto-execute 段和全部 class 定义，
> 是唯一能证明「程序真能起来」的检查。方案 A 只当写代码中途的快速预检。

> 端到端演示测试已移除（2026-10-19，为工作台化重构让路）；重构后按新模块结构重建。

### 单测一个 Service / Feature 的方法（探针脚本）

不必起真窗口：把主脚本读进内存、在 **auto-execute 段内**插一段驱动，驱动里直接调
`SomeService.Method()`、把结果写文件，最后 `ExitApp()`。实测用它一次跑完 `PeerLayoutService`
的四项对拍 —— `CornerRect` 与工作区算术比对、`IsPlaceable` 对「可见 / 隐藏 / 不存在」三态、
`RectOf` 读隐藏窗口的外框。

⚠ **驱动别直接追加到文件末尾，插在 `ShowStartupTip()` 调用行之后。**

实测（AHK v2.0.27）：**函数定义、类定义、运行时 `Hotkey()` 调用都不结束 auto-execute** ——
下面这种脚本 A–E 五步全执行：

```ahk
FileAppend("A`n", logPath)
F() { x := 1 }
FileAppend("B`n", logPath)
class C { static X := 1 }
FileAppend("C`n", logPath)
Hotkey("!q", (*) => 0, "On")
FileAppend("D`n", logPath)
ExitApp()
```

真正结束 auto-execute 的是**热键 / 热字符串 / `#HotIf` 指令**。
但主脚本末尾是 `ShowStartupTip()` / `DestroyTipWindow()` 这类函数定义，历史上追加在它之后的驱动曾整段不执行
（`exit=0`、stderr 为空、日志两边都没有）；原因未完全定位，**别拿它赌**。
用正则插在 `ShowStartupTip()` 调用行之后，是实测可靠的做法。

具体写法（那行顶格独占一行，且在 auto-execute 段内）：

```powershell
# $src 指向 src\SevenWork.ahk，$dir 指向 src\ —— 探针必须与 #Include 同目录
$t   = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
$drv = 'ShowStartupTip()' + "`r`n" + 'LogError("PROBE ...")' + "`r`n" + 'ExitApp()'
$t2  = [regex]::Replace($t, '(?m)^ShowStartupTip\(\)\r?$', $drv, 1)   # 恰好 1 处
if ($t2 -eq $t) { throw 'anchor not found' }
[System.IO.File]::WriteAllText("$dir\_probe.ahk", $t2, [System.Text.UTF8Encoding]::new($false))
```

⚠ 探针文件此时**放在 `src\`**（不是项目根，也不是 `%TEMP%`）：它要和
`src\SevenWork.ahk` 的相对 `#Include` 同目录。直接跑 `src\SevenWork.ahk` / 探针时
`A_ScriptDir` 是 `src\`，开发版日志落 **`src\.logs\`**（正常用根启动器时仍落项目根 `.logs\`）。
**验证完立刻删掉** `src\_probe.ahk` 与 `src\.logs\`，别留在仓库里（会进 `git status`，
也会被 AHK++ 扫到）。

⚠ **跑之前先 `Stop-Process` 掉已在运行的实例** —— 否则两个实例抢同一批热键，
后起的那个注册失败、可能弹出模态框把结论搅浑。

### 探针第一行别用裸 `FileDelete`

`FileDelete(不存在的路径)` 会抛 `OSError`。它写在探针第一行时，`OnError`（`return 1`）
之后**后续语句不再执行** —— 表现是「日志文件根本没生成、进程 `exit=0`、stderr 为空」，
极易误判成「脚本没启动」或「驱动没拼进去」。实测为此白查了三轮。

- 先 `if FileExist(logp)` 守卫，或干脆**只 `FileAppend`**（会自己创建）；
- 探针里每步都 `FileAppend(步骤名, logp)`，卡在哪一步一眼就看得到。

### ⚠ 上下文热键无法用 `Send` 验证（只能手按）

`HotIf(...)` / `#HotIf` 的上下文热键由**键盘钩子**实现，而 AHK 的钩子会**忽略同一脚本
`Send` 产生的事件** —— 实测 `SendLevel(1)` 也无效，`Hotkey("$F9")`（强制钩子）与
`Hotkey("F8")`（有 `HotIf` 上下文）**都抓不到**，脚本正常跑完、`_error.log` 干净。

| 热键类型 | 实现方式 | `Send` 能否触发 |
| --- | --- | --- |
| 无上下文的 `Hotkey()`（如 `Alt+Z` / `Alt+S`） | 系统 `RegisterHotKey` | **能** ✓ 用它验全局热键 |
| 有 `HotIf` 上下文 / `$` 前缀 | 键盘钩子 | **不能** ✗ |

**别据此判定「热键坏了」。** 上下文热键只有两条验证途径：

1. `Hotkey()` 全部未抛错 → `_error.log` 为空（本项目 30 条全过即证明注册成功）；
2. **人工按键**（只能由用户按）。

⚠️ 连带的一个假象：`Send("^f")` 若命中了某个上下文热键，`Send` 会**等热键线程跑完**，
探针看起来「卡住」、后续步骤全不执行 —— 判断「是不是真卡」要直调那个 action
（实测 `SearchFeature.Show()` **16ms** 返回、`IsVisible()` 立刻为 1，与卡死无关）。

**断「改造前后是否等价」的硬办法**：把新注册的上下文表达式与旧 `#HotIf` 行**逐字比对** ——
本项目 `HotIf((*) => WinActive("ahk_id " . State.GetGuiHwnd()) && !SearchFeature.IsVisible())`
与 HEAD 的 `#HotIf` 行一字不差。

## 看主题效果时的窗口截图坑

验证背景图主题**别只看成品图**，要**在真窗口里看文字压上去的效果**。实测三个坑：

| 坑 | 现象 | 绕法 |
| --- | --- | --- |
| `PrintWindow` 抓不全 | 窗口一大（实测 1361x1084），右半边全是空白，**文字和背景同时断在同一列** —— 那是截图边界，**不是应用 bug**（474 宽的小窗口抓得完整） | 用 **900 宽以内**的窗口抓，或改用 `CopyFromScreen`（截屏前先确认窗口没被别的窗口压住） |
| **最小化窗口的 `IsWindowVisible` 仍是 `1`** | 以为窗口显示着，`GetWindowRect` 却返回 `-21333,-21333`（150% DPI 下的最小化停放位），抓出来只有 158x26 | 先 `IsIconic()` 判断、再 `ShowWindow(hwnd, 9)` 恢复；`GetWindowRect` 拿到负数坐标就一律当没显示 |
| 一条 PowerShell 里塞「`SendKeys` + 截屏 + 杀进程」会被**防病毒拦** | 整条命令一行都不执行，报 `ScriptContainedMaliciousContent` | **拆成多条**：类型定义 / 发热键 / 截屏各自一条 |

**回写、重铺这类改动的验收公式**：连打 N 次 `SetWindowPos` + 前后各截一张图逐字节比对。

```powershell
# 0x0004 = SWP_NOZORDER；打一串不同尺寸，测总耗时
for ($i = 1; $i -le 40; $i++) {
    [PW7]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, ($w + ($i % 9) * 7), ($hgt + ($i % 11) * 9), 0x0004)
}
```

- 每次 **几毫秒**（实测 40 次共 392ms）说明合成被合并了；秒级说明还在逐帧重铺。
- 打完把尺寸**调回原值**再截第二张 —— 两张 PNG **字节数完全相同**（1302123 = 1302123）
  就是逐像素一致，即「文字没丢、图没错位」。

> **判构图和明暗请直接读成品 PNG。** 成品图就是铺进编辑区的内容（`bgAlpha = 0` 时无遮罩、
> 无裁切），比隔着截图猜准得多；截图只用来看「文字压在图上读不读得清」。

## 临时脚本放哪（别污染「问题」面板）

调试验证用的脚本、截图、中间产物**不要直接丢在 `%TEMP%` 根目录** —— VS Code
（AHK++ / PowerShell 扩展）会把那里的文件纳入诊断，「问题」面板会被一堆一次性脚本的
告警刷屏（实测：`_grab.ahk`、`_sstest.ahk`、`_gdicmp.ps1` 三个临时文件的 5 条告警把
真问题全盖住了）。而且文件删掉后诊断仍是**陈旧缓存**，必须 `Developer: Reload Window`
才消失。

- 统一放 `%TEMP%\SevenWorkDev\`，**用完立刻整目录删掉**：

  ```powershell
  Remove-Item "$env:TEMP\SevenWorkDev" -Recurse -Force -ErrorAction SilentlyContinue
  ```

- 同理别把中间产物（截图、diff 图、日志）留在 `%TEMP%` 根部。
- 更别写进仓库目录 —— `.ahk` / `.ps1` 会进 `git status`，也会被 AHK++ 语法检查扫到。

**怎么清陈旧诊断**：文件删了、「问题」面板还挂着它的告警时 ——

1. 先关掉那个文件的标签页（若 VS Code 里还开着）；
2. `Ctrl+Shift+P` → 输入 `Developer: Reload Window` 回车。

诊断只存在于扩展宿主进程的内存里，磁盘上**没有**缓存文件可删，所以别去翻
`%APPDATA%\Code\` 找 —— 重载窗口是刷新它的方式（实测：`%TEMP%\_gdicmp.ps1`
早已删除，面板里那 3 条告警仍旧挂着，与磁盘状态无关）。

## 给 PowerShell 写脚本时的编码坑

⚠ **`git show` 之类外部命令的输出别再经 PowerShell 管道**：`git show HEAD:x.ahk | Set-Content out.ahk`
看着正常，实际 `powershell.exe`（5.1）会按系统 ANSI（本机 GBK）解码子进程吐出的 UTF-8 字节 ——
中文变乱码，而且 **GBK 的双字节解码还会吃掉紧跟其后的 ASCII 字符**（引号 / 括号），把类体边界
一起破坏。实测导出 HEAD 版 `src\SevenWork.ahk` 后启动，AHK 报
`(278) : ==> Not a valid method, class or property definition. Specifically: SendMessage(0x00B1, 0, 0,hwnd)`
—— 看着像源码坏了，其实是被**解码**坏的。要字节级搬运就走 cmd 重定向：

```powershell
cmd /c "git -C <repo> show HEAD:src/SevenWork.ahk > <temp>\_old.ahk"
```

`powershell.exe`（5.1）**按系统 ANSI（本机 GBK）读取无 BOM 的 `.ps1`**。用 UTF-8 无 BOM
写含中文的脚本，中文会变乱码；GBK 双字节解码还会**吃掉紧跟其后的 ASCII 字符** ——
实测引号被吞，报 `字符串缺少终止符`，让人以为是语法写错。

- 脚本内容**全用 ASCII**（注释、输出消息、字符串一律英文）；
- 必须含中文时存成 **UTF-8 带 BOM**；
- 中文路径别硬写在脚本里，用通配符取：

  ```powershell
  # 路径的目录名本身是中文也没关系，通配符里不含中文即可
  $src = (Get-ChildItem -Path 'D:\00-SevenFiles\Pictures\*\*\*\2026-10-14_*.png' | Select-Object -First 1).FullName
  ```

## PowerShell 持久会话的坑（Add-Type 会沿用旧编译类型）

命令是在**同一个持久 `powershell.exe` 会话**里跑的。用 `Add-Type` 定义 C# 辅助类时，
第二次运行会抛「类型名称 `X` 已存在」，并且**静默沿用第一次编译的那个类型** ——
你改了 C# 逻辑，脚本还在跑旧代码，**而输出看起来完全正常**。

实测（给主题烘图那个脚本）：改完提亮曲线后重跑，输出与旧公式**逐像素完全一致**；
只有拿源图某个点手算「预期值 vs 实际值」比对才暴露 —— 实际值精确等于**旧公式**的结果。

对策：

- `Add-Type` 外面套 `if (-not ("Name" -as [type])) { ... }`，让重复运行不再报错；
- **改了 C# 逻辑就递增类名**（`X` → `X2`），强制重新编译；
- 验收别只看图、只看统计 —— **取一个已知输入算预期输出，再读实际输出比对**。

⚠️ 同一次响应里「编辑文件 + 运行脚本」**不保证先编辑后运行**（实测编辑器调用与命令
并行执行，脚本跑到的是**编辑前**的版本）。要跑改过的脚本，**先发编辑，下一轮再运行**。

## 提交信息

简体中文短句，说清"做了什么"，**不加** `feat:` / `fix:` 等英文前缀。
参考既有提交：`添加了终端快捷呼出隐藏功能`、`autohotkey位置配置修改`。
