# CleanPilot

CleanPilot 是一款安全的 Windows 10/11 磁盘清理助手。

它会先扫描并报告可清理内容，只会删除明确列入允许清单的缓存和维护目录中的文件。当前版本保留 PowerShell 命令行入口，并新增 Qt 桌面端，用于展示进度、推荐信息、日志和清理候选项。

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

## Qt 桌面端

Qt 桌面端是现有 PowerShell 引擎的可视化外壳，不改变原有 CLI 用法。它提供：

- `扫描` 和 `清理选中项` 按钮。
- 安全模式和深度扫描模式。
- 最小文件年龄设置。
- 清理候选项表格。
- 实时进度条。
- 推荐信息栏，例如建议先清理安全项或以管理员身份重新扫描。
- 实时日志查看，并可打开日志目录。

从源码运行桌面端：

```powershell
python -m pip install PySide6
python -m src.cleanpilot_qt.app
```

提前下载可打包依赖到本地 wheel 缓存：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\download_qt_wheels.ps1
```

构建自包含 Windows 发布目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_qt_app.ps1
```

构建完成后，发布目录位于：

```text
dist\CleanPilot\CleanPilot.exe
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
- Qt 桌面端支持进度条、推荐信息和日志查看。
- 提供轻量级验证测试。

## 路线图

- 为 UI 集成提供 JSON Lines 引擎输出。
- 提供稳定的清理目标 ID，并支持按目标选择清理。
- 完善 Qt 桌面端的结构化进度、风险标签和最终清理报告。
- 发布自包含的 Windows x64 安装包。

## 测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1
python -m unittest tests.test_qt_engine tests.test_qt_ui_contract -v
```

## 许可证

MIT。参见 [LICENSE](LICENSE)。
