# CleanPilot

CleanPilot 是一款安全的 Windows 10/11 磁盘清理助手。

它会先扫描并报告可清理内容，只会删除明确列入允许清单的缓存和维护目录中的文件。当前版本以脚本为主，后续计划提供 .NET 8 WPF 桌面应用，用于展示进度、选择清理类别，并提供更完善的 Windows 工具体验。

## 安全模型

CleanPilot 默认采用保守策略：

- 支持先执行 `DryRun` 扫描，再决定是否删除。
- 清理目标使用明确的允许清单。
- 排除个人库目录。
- 排除程序安装目录。
- 排除驱动存储清理。
- 排除还原点删除。
- 排除 `DISM /ResetBase`。
- 遇到锁定文件时跳过，而不是强制删除。

本项目不会捆绑 WizTree 或其他专有磁盘分析工具。如果你想把 WizTree 作为可视化辅助工具，请自行下载，并通过 `-WizTreePath` 传入路径。

## 快速开始

预览清理候选项，不删除文件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1 -DryRun
```

预览更深入的开发者缓存和 Windows 升级残留清理：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1 -DryRun -Aggressive -MinAgeDays 14
```

执行保守清理：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1
```

使用启动器以管理员身份运行：

```text
Run-SafeDiskCleanup-AsAdmin.cmd
```

## 当前功能

- 清理用户和 Windows 临时文件。
- 清理 Windows Update 下载缓存。
- 清理传递优化缓存。
- 清理 Windows 错误报告缓存。
- 清理 CBS 和 DISM 归档日志。
- 清理 Chrome、Edge 和 Firefox 缓存。
- 在激进模式下可选清理开发者缓存。
- 在激进模式下可选清理 Windows 升级残留。
- 通过 `-IncludeDism` 可选执行 DISM 组件清理。
- 生成日志文件。
- 提供轻量级验证测试。

## 路线图

- 为 UI 集成提供 JSON Lines 引擎输出。
- 提供稳定的清理目标 ID，并支持按目标选择清理。
- 提供 .NET 8 WPF 桌面应用。
- 提供进度条、事件日志、风险标签和最终清理报告。
- 发布自包含的 Windows x64 安装包。

## 测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1
```

## 许可证

MIT。参见 [LICENSE](LICENSE)。
