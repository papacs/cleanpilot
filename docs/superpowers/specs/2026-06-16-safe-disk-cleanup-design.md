# 安全磁盘清理设计

## 目标

构建一个 Win10/Win11 PowerShell 清理脚本，用户可以手动运行它，以安全且快速地释放 C 盘空间。

## 选定方案

使用单个专业 PowerShell 脚本，默认策略保守，并提供可选的激进清理。相比宽泛删除目录，脚本优先使用 Windows 支持的清理机制和明确白名单中的缓存路径。

## 默认行为

- 正常使用无需配置。
- 以管理员身份运行时效果更好，同时仍支持有限的非管理员清理。
- 支持 `-DryRun`，用于只报告候选项而不删除。
- 当 WizTree Portable 放在脚本旁的 `tools\WizTree\WizTree64.exe` 时，支持可选的 `-OpenWizTree` 检查。
- 默认使用 `-MinAgeDays 7`，避免删除最近生成的缓存文件。
- 记录所有操作、释放大小、跳过文件和错误。
- 清理用户和系统临时文件、Windows Update 下载缓存、传递优化缓存、Windows 错误报告缓存、旧 CBS/DISM 日志归档、浏览器缓存和回收站。
- 默认跳过 Windows 组件存储清理；只有显式传入 `-IncludeDism` 时，才运行 `DISM /Online /Cleanup-Image /StartComponentCleanup`。
- 包含一个双击启动器，用于请求管理员权限，并在完成后保留 PowerShell 窗口。

## 安全边界

- 永不处理 Downloads、Desktop、Documents、Pictures、Music 或 Videos 等个人库。
- 永不处理 Program Files 下的应用安装目录。
- 永不删除驱动存储内容。
- 不删除所有还原点。
- 默认不使用 `DISM /ResetBase`。
- 删除前使用明确路径允许清单和存在性检查。
- 将锁定文件作为跳过处理，而不是作为硬失败。
- 仅在确认目录为空后才删除目录，并显式抑制 PowerShell 的递归删除确认提示。
- 将 DISM 组件清理视为可选 Windows 维护步骤，因为即使普通缓存清理成功，它也可能因系统级访问或服务堆栈错误而失败。

## 可选 WizTree 辅助工具

本项目不捆绑或下载 WizTree。内部使用时，可将 portable 可执行文件放在 `SafeDiskCleanup.ps1` 旁边的 `tools\WizTree\WizTree64.exe`，或显式传入 `-WizTreePath`。使用 `-OpenWizTree` 时，脚本会针对 `-ScanPath`（默认：系统盘）启动 WizTree，让用户在决定清理前可视化检查大目录。清理脚本永远不会根据 WizTree 输出删除文件；WizTree 只是检查辅助工具，脚本删除仍限制在安全目标允许清单内。

## 可选激进行为

`-Aggressive` 开关可在存在时包含较旧的 Windows 升级残留，例如 `Windows.old` 和 `$WINDOWS.~BT`，并启用更深入的浏览器和包管理器缓存清理。它仍然避免个人数据，以及删除所有还原点这类不利于回滚的操作。

## 可选 DISM 行为

`-IncludeDism` 开关通过 DISM 运行 Windows 组件存储清理。当系统服务堆栈允许时，这很有用；但它不是默认内部清理路径的一部分，因为 DISM 可能返回访问或 CBS 服务错误，而这些错误不影响普通缓存清理。

## 交付物

- `SafeDiskCleanup.ps1`：面向用户的清理脚本。
- `Run-SafeDiskCleanup-AsAdmin.cmd`：用于手动清理的双击启动器。
- `tests/Test-SafeDiskCleanup.ps1`：轻量级验证测试。
- 可选内部目录：`tools\WizTree\WizTree64.exe`，由用户或组织自行提供，不存储在本仓库中。

## 验证

- 使用 PowerShell 解析脚本，以捕获语法错误。
- 运行测试，断言参数、安全排除项、dry-run 支持、计划任务支持、DISM 行为，以及不存在不安全默认行为。
- 运行测试，验证空目录清理不会尝试删除非空目录。
- 运行 dry-run 调用，验证脚本只报告而不删除。

## 备注

此工作区当前不是 git 仓库，因此无法在这里提交设计文档。
