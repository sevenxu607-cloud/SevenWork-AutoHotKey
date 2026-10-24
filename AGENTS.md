# Project Agent Guide

**Windows 本地工作台**：AutoHotkey v2 管窗口 / 热键 / 磁盘，WebView2 里的 Vue + Milkdown 管界面。
方向见 [`docs/INTENT.md`](docs/INTENT.md)，进度见 [`docs/STATE.md`](docs/STATE.md)。

## Repo Map

- `src/` —— AHK：`WorkBench/`（Kernel / Service / Capability / Coordinator）+ `modules/<模块>/`
- `web/src/` —— Vue + Milkdown；`web/dist` 入库，供 AHK 直接加载
- `tests/` —— AHK 断言（`RunTests.ahk`）；`web/tests/` 前端纯函数（`node:test`）
- `tools/` —— `run-tests.ps1` / `check-docs.ps1`
- `docs/` —— INTENT（去哪）/ STATE（停在哪）/ EXPERIENCE（怎么走）/ LAUNCHER-GUIDE（加外部窗口）
- `.clinerules/` —— 强制规则 01~05（语言 / 架构 / AHK 陷阱 / 验证 / 资料）

## Commands

```powershell
# 纯逻辑回归：AHK 109 条 + 前端 17 条
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-tests.ps1
# 文档体检：链接 / 编码 / 版本号 / 围栏 / 本文件行数
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-docs.ps1
# 前端构建：改 web/src 后必须重建，dist 入库
cd web; npm run build
```

改 `.ahk` 还要做语法预检 + 真机启动；做法见 `.clinerules/04-workflow.md`。

## Required Reading（按改动选，别全读）

| 要改什么 | 先读 |
| --- | --- |
| 结构 / 依赖方向 / 加模块 | `.clinerules/02-architecture.md` |
| 任何 `.ahk` | `.clinerules/03-ahk-v2.md` + `04-workflow.md` 的验证表 |
| `web/src` 或样式 | `docs/EXPERIENCE.md` 第 3、4 节 |
| 文档 / 收尾 | `.clinerules/05-records.md` |
| 加一个外部窗口呼出 | `docs/LAUNCHER-GUIDE.md` |

## Working Rules（细则在 `.clinerules`，这里只列硬约束）

1. **不动 Kernel**；跨模块只走 `EventBus`；Capability 不读业务、不发事件。
2. **先只读分析，再给计划**；diff 只做任务范围内的事。
3. **不引新依赖**；不碰真实笔记 / 配置 / secrets。
4. **没实测的数字不写进文档**；能写成测试的就别只写进文档。
5. 异步回调碰窗口前自己过闸；窗口定位在隐藏态完成（见 `03`）。
