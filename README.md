# SevenWork

> 🤖 给 AI / 新会话的入口是 [`AGENTS.md`](AGENTS.md) —— 本文只讲「是什么、怎么跑」。

**一个面向个人 Windows 工作流的本地工作台。** 用统一的热键和面板，把速记、提示词、文件操作、
外部程序和输入辅助收在一处 —— 不用先找窗口、找软件。

后台是 AutoHotkey v2（管窗口、热键、磁盘、进程），前台是 WebView2 里的 Vue + Milkdown。
**记下来的东西都是普通文件**：笔记就是 `.md`，直接落在你自己的 Obsidian 库里。

![version](https://img.shields.io/badge/version-2.19-blue)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-lightgrey)
![language](https://img.shields.io/badge/language-AutoHotkey%20v2-green)
![license](https://img.shields.io/badge/license-MIT-orange)

> ⚠ **开发期项目，不是稳定发行版。** portable 编译版已经可以构建；
> 安装器、代码签名和**干净机器首次运行**还没验收。
> 日常自用可以，给别人装机之前先读「已知限制」。

## 它解决什么问题

| 痛点 | 做法 |
| --- | --- |
| 打开笔记软件要几秒，灵感等不起 | `Alt+Z` 呼出即写，收起自动存 |
| 常用动作散在好几个软件里 | 一个面板 + 一套热键：提示词、文件、终端、网页、转换 |
| 记下来的东西被某个软件锁死 | 落盘就是标准 Markdown，任何编辑器都能开 |
| 并排用时窗口手动摆两次 | 记录区 / 辅助区 / 工作区固定分区，呼出即落位 |

> 窗口分区由「视界」统一管理：笔记固定落记录区，终端 / 浏览器落辅助区，
> 其余窗口按槽位设置落区；`Alt+Shift+V` 把已开窗口摆回各区域。

## 现在有什么

| 核心应用 | 干什么 | 入口 |
| --- | --- | --- |
| 笔记 | 每日 `.md`，标签写在文件名里，图片收进 `_assets/日期/` | `Alt+Z` |
| 文本 | `<Vault>\_prompts\` 下的普通 Markdown（提示词库） | `Alt+P` |
| 文件 | 三个常用目录随叫随到 | `Alt+1/2/3` |
| 应用 | PowerShell 终端、DeepSeek 网页（辅助区）；槽位可配任意 exe | `Alt+C` / `Alt+X` / `Alt+Shift+1/2/3` |
| 视界 | 记录区 / 辅助区 / 工作区固定分区，恢复布局 | `Alt+Shift+V` |
| 按键 | CapsLock → `H/J/K/L` 方向键 | `Alt+Shift+C` |
| 主题 | 当前主题（整套观感由主题自己定义） | `Alt+S` 里的面板 |

退出程序用 `Alt+Shift+S`：笔记 / 提示词 / 面板里还有没保存的内容时会先拦下，不会直接丢。
笔记正文的字体与字号：`Alt+Shift+T` 换字体、`Alt+=` / `Alt+-` 调大小（笔记窗口在前台时才生效，避免抢别的程序的键）。

**完整热键表不用查文档**：按 `Alt+S` 打开工作台面板，「全部热键」一页列全、按模块分组。

## 跑起来

1. 装 **AutoHotkey v2**（64 位）
2. 确认有 **WebView2 Runtime**（Win11 自带；Win10 多数随 Edge 装好）
3. 双击仓库根目录的 `SevenWork.ahk` —— 它只是启动器，实际入口在 `src\SevenWork.ahk`
4. 首次运行选择笔记目录
5. 按 `Alt+Z`

`Alt+M` 的文档转换是**可选功能**：需要机器上已有 Pandoc（放在
`%AppData%\SevenWork\pandoc.exe` 或在 PATH 里）。没有 Pandoc 时只有这个功能不可用，
启动、笔记、提示词、文件和三区域不受影响；发布包**不打包 Pandoc**。

改前端（`web\src\`）之后要在 `web\` 下 `npm run build`，产物 `web\dist\` 已入库、AHK 从这里加载。

### 构建 portable 版

```powershell
# 需要 Node.js + Ahk2Exe（默认从本机 AutoHotkey 安装目录找）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1
```

产物在 `dist\SevenWork\`，并生成 `dist\SevenWork-<版本>-portable.zip`：

```text
SevenWork.exe
WebView2Loader.dll
assets\icon\SevenWork.ico
web\dist\...
LICENSE / README / THIRD-PARTY-NOTICES.txt
BUILD.txt
```

已发布：[SevenWork v2.19-portable](https://github.com/sevenxu607-cloud/SevenWork-AutoHotKey/releases/tag/v2.19-portable)

### 第一次运行被拦下（SmartScreen）

发布包**没有代码签名**，所以换一台机器首次运行 `SevenWork.exe` 时，Windows 可能弹出
「Windows 已保护你的电脑 —— Microsoft Defender SmartScreen 阻止了无法识别的应用启动」。
拦截依据是**无签名 + 无下载声誉**，与文件是否损坏、是否用压缩壳无关；
**重新编译不会让它消失**（2026-10-28 实测：本机未打包、无下载标记的产物同样会被拦）。

- 单次放行：点「更多信息」→「仍要运行」；
- 整包放行：先对下载到的 **zip** 右键 →「属性」→ 勾「解除锁定」→ 确定，再解压；
  已经解压过的，对 `SevenWork.exe` 做同样操作即可，也可在 PowerShell 里
  `Get-ChildItem . -Recurse | Unblock-File`；
- 校验完整性：`Get-FileHash SevenWork.exe -Algorithm SHA256`，与包内 `BUILD.txt`
  的 `sha256=` 一行比对，一致说明文件没被动过；
- 根治只能靠代码签名（EV 证书），见 [`docs/INTENT.md`](docs/INTENT.md) 的「还没定」。

构建脚本**不加任何压缩参数**：本机实测 `Ahk2Exe` 的 `/compress 1` / `/compress 2`
与不传一样，产物都是 1,523,200 字节，对 SmartScreen 也没有影响 —— 拦截只看签名与声誉，
**重编译不会改变结果**。

### 程序起来了，但里面什么都没有

如果双击后**进程确实在跑**（任务管理器里能看到 `SevenWork.exe`），却没有窗口内容、
`%AppData%\SevenWork\_error.log` 也一条都不写 —— 先查项目目录的**完整性标签**。
放在 Low 完整性目录里的 exe 会以低权限启动，写不了 `%AppData%`，于是日志与 WebView2
全部**静默失败**（WebView2 会报 `0x800700AA 请求的资源在使用中`）。

```powershell
# 出现 "Low Mandatory Level" 就是它
icacls <项目目录> | Select-String 'Mandatory Label'

# 修复（需要管理员；普通用户会「拒绝访问」）
icacls <项目目录> /setintegritylevel (OI)(CI)Medium /T
```

判断依据不是「重新编译」也不是「换路径」，而是**目录本身的标签**：同样的 exe 复制到
普通目录就正常。详见 [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) 第 10 节。

### 自动演示 / 验收录屏

`tools\demo-sevenwork.ps1` 会拉起临时 Vault、OBS 和独立 AHK 驱动，逐段演示
工作台、笔记、提示词、文件、Obsidian、视界和退出；不读真实笔记。

```powershell
# 只跑 UI 断言，不录制
powershell -NoProfile -ExecutionPolicy Bypass -File tools\demo-sevenwork.ps1 -Mode Test

# 每段单独录制成 mp4，并保存 cover.png / driver.log
powershell -NoProfile -ExecutionPolicy Bypass -File tools\demo-sevenwork.ps1 -Mode Demo -Record
```

输出在桌面 `SevenWork-Demo\<时间戳>\`，按章节分子目录。录制前请关掉真实的
Obsidian；脚本会临时备份并还原 `%AppData%\SevenWork\_config.ini` 与
`%AppData%\obsidian\obsidian.json`。OBS 需要在 Windows「图形设置」里指定为
**省电 / 集显**（双显卡笔记本上独显会截出黑屏），并开启 WebSocket 4456。
素材目录、配置备份与还原都在脚本退出时清理。

本机实测：OBS profile 的 **Color Range = Partial** 会让本地 mp4 暗暗的；
在 `设置 → 高级 → 视频` 改成 **Full** 后，视频从 `yuv420p(tv)` 变为
`yuvj420p(pc)`，抽帧平均亮度约 **76 → 114**。录制本地素材建议 Full；
要发给别人或上传平台再改回 Partial。

## 数据与安全

```text
<你选的笔记目录>\             ← 只需备份这个
├─ 2026-09-20.md              每天的笔记
├─ 2026-09-20-机器学习.md      带标签的版本
├─ _assets\2026-09-20\        当天粘贴的图片
└─ _prompts\                  提示词库

%AppData%\SevenWork\           _config.ini、_error.log
```

实际做到的是这些（**不要当成更强的承诺**）：

- 写入走「同目录临时文件 → 写完替换」，避免直接截断原文件；
- 内容没变不写盘；空笔记不落盘；
- 收起窗口、保存退出前都会先确认保存成功，存不住就留在原地并给出提示。

**没做到**：断电 / 崩溃瞬间的强一致保证，外部修改检测，多端同步。

## 已知限制

| 限制 | 说明 |
| --- | --- |
| **外部修改可能被覆盖** | 没有文件监听。在 Obsidian 里改完再回来保存，以编辑器内容为准 |
| 同日多文件只认第一个 | `日期.md` 与 `日期-标签.md` 并存时，按日期只匹配第一个 |
| 标签单字段 | 每个日期一个标签 |
| 仅 Windows | AHK v2 的平台限制 |
| 改配置要重启 | `_config.ini` 在进程内被缓存 |
| **同一区域多窗口会重叠** | 区域只保证「落到哪块」，不负责同区堆叠；恢复布局会把终端 / 浏览器同时摆回辅助区 |
| **一键启动 / 自定义布局暂缓** | 视界页目前只有说明与 `Alt+Shift+V` 恢复布局，没有「一键启动默认程序」 |
| **应用槽位按 exe 文件名认窗** | 多实例只取第一个；不支持 UWP、`cmd /c start` 与提权窗口 |
| DOCX 编号只验过样本 | 标题编号固化只对一份 23MB 课件验证过，`lvlOverride` / 罗马数字未处理 |

## 开发

```powershell
# 纯逻辑回归（不建窗口、不读配置、不碰真实笔记）：AHK 109 条 + 前端 17 条
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-tests.ps1

# 文档与编码体检：链接 / LF / CRLF / 版本号 / 代码围栏
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-docs.ps1
```

AHK 用例在 `tests\Cases\`，入口 `tests\RunTests.ahk`；前端纯函数用例在 `web\tests\`
（`node:test`，如 Markdown 清洁与代码区保护）。新增用例后要**故意改坏一次**，确认它会红。
语法预检、真机启动、探针的完整做法见 [`.clinerules/04-workflow.md`](.clinerules/04-workflow.md)。

| 想了解 | 看 |
| --- | --- |
| 这个项目要成为什么、不做什么 | [`docs/INTENT.md`](docs/INTENT.md) |
| 现在停在哪、下一步做什么 | [`docs/STATE.md`](docs/STATE.md) |
| 下次怎么少踩坑、哪些方向算过账 | [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) |
| 改代码的硬约束 | [`.clinerules/`](.clinerules/) |
| 接一个新的外部窗口 | [`docs/LAUNCHER-GUIDE.md`](docs/LAUNCHER-GUIDE.md) |

历史看 `git log`；原始对话在仓库外的私人档案，不进 Git。

## License

MIT — 见 [LICENSE](LICENSE)。
