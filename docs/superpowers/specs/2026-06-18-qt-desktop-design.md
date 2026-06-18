# CleanPilot Qt 桌面端设计

## 目标

在不影响现有 `SafeDiskCleanup.ps1` 命令行使用方式的前提下，为 CleanPilot 增加一款专业、漂亮、实用、易用的 Windows CS 桌面端程序。桌面端负责提供可视化操作体验，清理能力仍由现有 PowerShell 引擎提供，避免重复实现危险的文件删除逻辑。

## 选定方案

使用 `Python 3.10 + PySide6 + PyInstaller` 构建 Qt 桌面端。

选择该方案的原因：

- 当前工作机已有 Python 3.10，不依赖本机 Qt C++ 工具链。
- PySide6 提供官方 Qt for Python 绑定，适合快速构建原生桌面体验。
- PyInstaller 可把 Python、Qt DLL、应用代码和脚本一起打包成发布目录，用户不需要安装 Python、Qt 或其他开发工具。
- 依赖可以提前下载为 wheel，存放在本地缓存目录，后续构建可尽量离线、可重复。
- 现有 CLI 不需要改名、不需要变更入口、不需要删除参数。

## 非目标

- 不替换 `SafeDiskCleanup.ps1`。
- 不改变现有命令行默认行为。
- 不做后台常驻服务。
- 不做开机自动清理。
- 不做计划任务管理。
- 不捆绑 WizTree 或其他专有分析器。
- 不直接在 Qt 代码中执行宽泛文件删除；Qt 端只调用受控的 PowerShell 引擎。

## 推荐仓库结构

```text
SafeDiskCleanup.ps1
Run-SafeDiskCleanup-AsAdmin.cmd
src/
  cleanpilot_qt/
    app.py
    main_window.py
    engine.py
    models.py
    resources/
      app.qss
      cleanpilot.ico
scripts/
  build_qt_app.ps1
  download_qt_wheels.ps1
tools/
  wheels/
tests/
  Test-SafeDiskCleanup.ps1
  test_qt_engine.py
docs/
  superpowers/
README.md
```

`tools/wheels/` 作为本地依赖缓存目录，保存固定版本的 `PySide6`、`shiboken6`、`PyInstaller` 等 wheel 文件。该目录默认可被 `.gitignore` 忽略，发布构建时可通过下载脚本重新生成，或在内部发布包中预置。

## 桌面体验

首屏就是清理工作台，不做营销页。

顶部区域：

- 产品名 `CleanPilot`。
- 当前系统盘容量、已用空间、可用空间。
- 管理员状态徽标：`管理员` 或 `普通权限`。
- 主操作按钮：`扫描`、`清理选中项`、`打开日志`、`打开脚本目录`。
- 模式控件：`安全模式` / `深度扫描` 分段选择。

主区域：

- 左侧为清理类别表格，列包括：选择、类别、路径、风险、预估大小、状态。
- 右侧为详情面板，显示当前类别说明、安全原因、权限需求和实际路径。
- 表格默认只展示安全扫描结果，深度扫描项用更醒目的风险标签标识。

底部区域：

- 总进度条。
- 当前操作文本。
- 实时日志窗口，警告和错误使用不同颜色。
- 推荐信息栏，根据扫描结果给出下一步建议，例如“建议先清理安全项”“建议以管理员身份重新扫描”“深度扫描项请先复核路径”。
- 最终摘要：预计可释放空间、已处理类别、跳过项、日志路径。

视觉风格：

- 专业工具风格，信息密度高但不过载。
- 使用浅色 Windows 工具配色，搭配克制的蓝色主操作色、绿色安全标签、琥珀色复核标签、红色错误标签。
- 按钮、表格、状态徽标保持一致尺寸和间距。
- 不使用装饰性大图、营销式 hero、夸张渐变或复杂动效。

## 交互流程

1. 用户打开 `CleanPilot.exe`。
2. 应用检查当前进程权限和系统盘信息。
3. 用户点击 `扫描`。
4. Qt 端启动 PowerShell 子进程执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1 -DryRun
```

5. Qt 端实时读取标准输出，把日志展示在界面中，并从 dry-run 文本中提取类别、路径、文件数和预估大小。
6. Qt 端根据扫描结果生成推荐信息，默认推荐安全项，深度扫描和需要复核的项不自动勾选。
7. 用户查看推荐信息、日志和候选项后，勾选要清理的类别。
8. 用户点击 `清理选中项`。
9. 如果当前不是管理员权限，界面提示需要提升权限，并提供以管理员身份重新运行清理的操作。
10. Qt 端调用 PowerShell 引擎执行清理，并实时展示进度和日志。
11. 清理完成后展示最终摘要和日志路径。

第一版会尽量复用当前脚本能力。若后续需要精确“按目标清理”，再在 PowerShell 引擎中增加 `-JsonLines` 和 `-IncludeTargets`，并保持旧 CLI 参数兼容。

## 架构

### Qt 应用层

`app.py` 创建 `QApplication`，加载样式，创建主窗口。

`main_window.py` 负责界面布局、按钮状态、表格渲染、日志渲染和用户确认流程。

### 引擎适配层

`engine.py` 封装 PowerShell 子进程调用：

- 构造参数。
- 设置工作目录。
- 流式读取 stdout/stderr。
- 解析 dry-run 输出。
- 发送进度、推荐信息、日志、完成、错误信号给 UI。

Qt 端不直接删除文件，只执行仓库内的 `SafeDiskCleanup.ps1`。

### 数据模型

`models.py` 定义清理候选项：

- `name`
- `path`
- `risk`
- `estimated_size`
- `file_count`
- `requires_admin`
- `selected`
- `status`
- `recommendation`

第一版数据来源是当前 dry-run 文本。后续结构化引擎完成后，数据来源切换为 JSON Lines。

## 权限策略

- 扫描默认可在普通权限下运行。
- 清理系统缓存时建议管理员权限。
- Qt 应用启动时显示权限状态。
- 用户点击清理时，如果普通权限可能影响结果，先展示明确提示。
- 需要提升权限时，通过 Windows `runas` 重新启动 PowerShell 清理命令，而不是静默失败。

## 依赖与打包

固定使用 Python 3.10。

依赖清单：

- `PySide6`
- `shiboken6`
- `PyInstaller`

构建脚本：

- `scripts/download_qt_wheels.ps1`：下载固定版本 wheel 到 `tools/wheels/`。
- `scripts/build_qt_app.ps1`：创建本地虚拟环境，优先从 `tools/wheels/` 安装依赖，然后调用 PyInstaller 打包。

发布产物：

```text
dist/
  CleanPilot/
    CleanPilot.exe
    SafeDiskCleanup.ps1
    Run-SafeDiskCleanup-AsAdmin.cmd
    _internal/
```

发布目录应能在未安装 Python 和 Qt 的 Windows 10/11 机器上运行。

## 错误处理

- PowerShell 不存在：提示当前系统不支持运行清理引擎。
- 脚本缺失：提示发布包损坏，并显示预期路径。
- 扫描失败：保留日志，允许用户重试。
- 清理失败：显示失败类别和日志路径，不继续隐藏错误。
- 权限不足：提示以管理员身份运行。
- 解析失败：仍展示原始日志，不阻塞用户查看结果。

## 测试策略

PowerShell 现有测试继续保留，确保命令行行为不回退。

新增 Python 测试：

- PowerShell 命令参数构造正确。
- dry-run 文本解析能识别类别、文件数、预估大小和路径。
- 缺失脚本时返回明确错误。
- 清理命令不会绕过 `SafeDiskCleanup.ps1` 直接删除文件。

手动验证：

- 普通权限启动并扫描。
- 管理员权限启动并扫描。
- 点击 `打开日志` 能打开正确目录。
- 打包后的 `CleanPilot.exe` 能在发布目录中启动。
- 现有 CLI 命令仍可直接运行。

## 验收标准

- `SafeDiskCleanup.ps1` 原有命令行用法保持可用。
- Qt 桌面端可扫描、展示候选项、展示日志和显示最终摘要。
- UI 有清晰按钮、表格、状态徽标、进度条、推荐信息和权限提示。
- 用户可在界面中查看实时日志，并可打开日志所在目录。
- 清理动作必须经过用户明确点击和确认。
- 构建脚本能提前下载依赖并生成可分发发布目录。
- 自动化测试覆盖脚本安全契约和 Qt 引擎适配层。
