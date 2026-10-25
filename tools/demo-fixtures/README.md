# demo-fixtures

`demo-sevenwork.ps1` 使用的纯虚构样本：Vault、提示词库、文件槽位目录和
Obsidian 演示库。全部内容不含真实工作资料，可以随仓库提交。

脚本会在 `%TEMP%\SevenWorkDemo-*` 复制这些文件，用当天日期替换 `{{DATE}}` /
`{{PREV}}`，结束时删除临时目录；仓库里的样本不会被修改。
