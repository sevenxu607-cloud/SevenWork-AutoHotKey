# 04 · 验证与提交

## 改完必须验证

**不要只靠「读代码觉得没问题」就说改好了。** 改 `.ahk` 必须用真实解释器跑一次。

只改文档时（`.md` / `.clinerules` / `tools\*.ps1`）不用起 AHK，但必须跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-docs.ps1
```

输出 `=== RESULT: all checks passed ===` 且**退出码 0** 才算过 —— 它抓的是结构性腐化
（相对链接断、编码跑偏、代码围栏没配平），**抓不到「内容说错了」**。

## 编码与换行

`.ahk` = **CRLF**、`.md` = **LF**、一律 **UTF-8 无 BOM**（`.gitattributes` 已规定）。
编辑器整文件写回可能把 CRLF 统一成 LF，`git diff` 会整文件变色 —— **判换行只认字节**：

```powershell
$b=[IO.File]::ReadAllBytes($f); $crlf=0;$cr=0;$lf=0
for($i=0;$i -lt $b.Length;$i++){
    if($b[$i] -eq 13 -and $i+1 -lt $b.Length -and $b[$i+1] -eq 10){ $crlf++;$i++ }
    elseif($b[$i] -eq 13){ $cr++ } elseif($b[$i] -eq 10){ $lf++ }
}
```

期望 `crlf>0, cr=0, lf=0`。转回 CRLF 且无 BOM：

```powershell
$t = $t -replace "`r`n","`n"; $t = $t -replace "`n","`r`n"
[IO.File]::WriteAllText($src, $t, [Text.UTF8Encoding]::new($false))
```

> ⚠ 正则里的反引号必须写在**双引号**字符串里。单引号 `'(?<!`r)`n'` 不做转义，
> 匹配的是字面「反引号 + n」，会误报 `bareLF=9`；照它去「修」会破坏 AHK 的 `` `n ``，
> 多行字符串当场报 `Missing """`，脚本起不来。

## 语法预检（快，但有盲区）

`/validate` 不可用 —— v2.0.27 不识别，会把它当脚本路径去找，找不到就弹模态错误框、进程卡住。

```powershell
$exe='D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$src="$tree\src\SevenWork.ahk"; $dir="$tree\src"    # 预检脚本必须与 #Include 同目录
$L=[IO.File]::ReadAllLines($src); $tmp="$dir\_syn_check.ahk"
$out=@('#Requires AutoHotkey v2.0','ExitApp()')+$L[1..($L.Count-1)]
[IO.File]::WriteAllText($tmp,(($out -join "`r`n")+"`r`n"),[Text.UTF8Encoding]::new($false))
$se="$env:TEMP\SevenWorkDev\_syn_err.txt"
$r=Start-Process -FilePath $exe -ArgumentList @('/ErrorStdOut','"'+$tmp+'"') `
     -RedirectStandardError $se -Wait -PassThru
$r.ExitCode                     # 0 = 通过；非 0 读 $se
Remove-Item $tmp -Force
```

⚠ **盲区：抓不到 class 体内的错误。** `ExitApp()` 在第 2 行，auto-execute 跑到就退出，
后面的 class 定义根本没被解析 —— 数组漏个逗号照样退出码 0、真机启动才报
`Unexpected "{"`。**每次都要反向验证一次**（故意造个坏样本，确认退出码非 0）。

⚠ **别用 `& $exe ...` 判退出码**：AHK 是 GUI 子系统程序，调用运算符不等它，
`$LASTEXITCODE` 保留旧值（通常 0），看起来「一切通过」。必须 `Start-Process -Wait -PassThru`。

## 真机启动（必做）

```powershell
Start-Process -FilePath $exe `
    -ArgumentList @('/ErrorStdOut','"<仓库根>\SevenWork.ahk"') -RedirectStandardError $se
Start-Sleep -Seconds 6
Get-Content $se                                      # 空 = 没有语法 / 运行时错误
Get-Process AutoHotkey64 | Stop-Process -Force        # 收工，别留实例
```

| 现象 | 含义 | 怎么办 |
| --- | --- | --- |
| stderr 有内容 | 语法 / 运行时错误，AHK 已退出 | 直接读 stderr，有行号 |
| stderr 空 + 多一个标题是脚本名的窗口 | 弹了模态错误框，进程卡着不退 | 见下 |
| **窗口没出来** | **正常** —— 主窗口默认不显示 | 要看见得按 `Alt+Z` |

错误框类名 `#32770`、标题是脚本名，正文跨进程 `GetWindowText` 读不到 →
`WinGetText("ahk_id " . hwnd)` 读出来写文件。

## 探针：单测一个 Service / Feature

不必起真窗口：把主脚本读进内存，在 **auto-execute 段内**插驱动（直接调 `SomeService.Method()`，
结果写文件），最后 `ExitApp()`。

- 驱动插在 `ShowStartupTip()` **之后**，别追加到文件末尾（历史上曾整段不执行）；
- 探针必须放 `src\`（与相对 `#Include` 同目录）；
- **跑前备份 `%AppData%\SevenWork\_config.ini`** —— 没有开发身份隔离，探针读写的就是生产配置；
- 先 `Stop-Process` 掉已在运行的实例（两个实例抢热键，后起的注册失败）；
- 第一行别用裸 `FileDelete`（路径不存在会抛，`OnError` 之后后续语句不再执行）——
  用 `if FileExist(...)` 守卫，或每步 `FileAppend` 打点，卡在哪一步一眼看到；
- **验证完立刻删探针**，并确认没有残留进程。

## 上下文热键不能用 Send 验证

`HotIf` / `#HotIf` 由**键盘钩子**实现，而钩子**忽略同一脚本 `Send` 的事件**（`SendLevel(1)` 也无效）：

| 热键类型 | 实现方式 | `Send` 能否触发 |
| --- | --- | --- |
| 无上下文的 `Hotkey()`（`Alt+Z` / `Alt+S`） | 系统 `RegisterHotKey` | **能** |
| 有 `HotIf` 上下文 / `$` 前缀 | 键盘钩子 | **不能** |

所以上下文热键只能**手按**。**别据此判定「热键坏了」。**

## 临时文件与提交

- 调试脚本 / 截图 / 中间产物放 `%TEMP%\SevenWorkDev\`，别丢 `%TEMP%` 根目录
  （会污染 VS Code 的「问题」面板），**更别写进仓库**（会进 `git status`）；
- 清理：`Remove-Item "$env:TEMP\SevenWorkDev" -Recurse -Force`；
- 提交信息用**简体中文短句**，说清「做了什么」，不加 `feat:` / `fix:` 前缀。

## PowerShell 两个坑

- `powershell.exe` 5.1 按系统 ANSI 读**无 BOM** 的 `.ps1`：脚本内容**全用 ASCII**；
  必须含中文就存成 **UTF-8 带 BOM**；
- 同一个持久会话里 `Add-Type` 定义同名类型会**静默沿用旧编译** —— 改了 C# 逻辑就
  **递增类名**（`X` → `X2`），否则脚本输出看起来完全正常、跑的却是旧代码。
