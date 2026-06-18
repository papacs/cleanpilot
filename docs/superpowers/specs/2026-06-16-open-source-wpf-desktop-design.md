# 开源 WPF 桌面版重新设计

## 目标

将 SafeDiskCleanup 从脚本优先的 Windows 清理工具，升级为可信赖的开源 Windows 10/11 桌面工具，提供精致的 WPF 界面、可见进度、可审计的清理详情和清晰的发布打包方式。

## 产品定位

SafeDiskCleanup 应定位为面向开发者和高级用户的安全 Windows C 盘清理助手：

- 先扫描，再清理。
- 删除前展示每个清理类别。
- 使用明确的允许清单，而不是宽泛删除目录。
- 避免处理个人文件、驱动存储、还原点删除和捆绑的专有分析器。
- 保留 PowerShell 引擎的自动化能力，同时让桌面应用成为主要用户体验。

## 选定方案

Windows 桌面客户端使用 `.NET 8 + WPF`，并继续保留 PowerShell 作为清理引擎。

当清理需要管理员权限时，桌面应用以提升权限的子进程启动 PowerShell 引擎。引擎除普通文本日志外，还输出结构化 JSON Lines 事件，使 UI 能够在不解析自由文本的情况下渲染进度、类别表、警告和最终汇总。

相比 Electron、Tauri 或 WinUI 3，该方案更适合本项目：WPF 体积更小，更贴近 Windows 管理工具，成熟稳定，易于打包为自包含应用，并且适合进程控制和系统工具界面。

## 首个桌面版本的非目标

- 不提供基于浏览器的 UI。
- 不支持跨平台。
- 不提供后台计划清理。
- 不在启动时自动清理。
- 不捆绑 WizTree 二进制文件或其他专有分析器。
- 不删除明确允许清单之外的内容。
- 不清理注册表、驱动存储或还原点。

## 仓库结构调整

推荐结构：

```text
SafeDiskCleanup.ps1
Run-SafeDiskCleanup-AsAdmin.cmd
src/
  SafeDiskCleanup.App/
    SafeDiskCleanup.App.csproj
    App.xaml
    MainWindow.xaml
    MainWindow.xaml.cs
    Models/
    Services/
    ViewModels/
tests/
  Test-SafeDiskCleanup.ps1
docs/
  screenshots/
  superpowers/
.github/
  workflows/
README.md
LICENSE
CHANGELOG.md
SECURITY.md
.gitignore
```

现有 `tools/WizTree` 文件夹应从公开仓库移除。脚本仍可支持 `-WizTreePath`，但文档必须要求用户在需要该辅助流程时自行下载 WizTree。

## 桌面用户体验

首屏就是实际清理工作区，而不是营销页面。

顶部区域：

- 应用名称、当前磁盘、已用/可用容量和管理员状态。
- 主要操作：`Scan`、`Clean Selected`、`Open Log`、`Settings`。
- 模式选择器：`Safe` 和 `Deep Scan`。

主工作区：

- 清理类别表格，列包括：类别、路径、风险等级、符合条件的文件数、预估大小、选中状态和状态。
- 风险标签：`Safe`、`Developer Cache`、`Windows Maintenance`、`Review`。
- 详情面板展示所选类别包含的内容，以及它为什么安全或为什么需要复核。

底部区域：

- 总体进度条。
- 当前操作文本。
- 事件日志流，并突出显示警告。
- 最终汇总，包括释放空间、跳过文件和日志路径。

视觉风格应专业、实用：表格密集但可读，颜色克制，状态徽标清晰，采用原生 Windows 间距，不使用装饰性英雄区布局。

## 清理流程

1. 用户打开应用。
2. 应用检查自身是否以提升权限运行。
3. 用户点击 `Scan`。
4. 应用以 dry-run 模式和 JSONL 输出启动引擎。
5. 引擎报告每个清理目标的预估可释放空间和风险元数据。
6. UI 展示候选项，并允许用户选择允许的目标。
7. 用户点击 `Clean Selected`。
8. 如果需要管理员权限但当前缺失，应用会以管理员权限重新启动自身或引擎。
9. 引擎清理选定目标，并流式输出进度事件。
10. UI 更新进度、记录警告，并显示最终汇总。

## 引擎契约

`SafeDiskCleanup.ps1` 应增加机器可读输出，同时不破坏当前命令行用法。

新增参数：

- `-JsonLines`：为 UI 消费输出每行一个 JSON 对象。
- `-IncludeTargets <string[]>`：只清理由 UI 选中的具名目标 ID。
- `-NoRecycleBin`：允许 UI 把回收站清理作为明确可选项处理。

每个清理目标应具备稳定 ID 和元数据：

- `id`
- `name`
- `path`
- `risk`
- `requiresAdmin`
- `aggressiveOnly`
- `minimumAgeDays`
- `description`

核心事件类型：

- `started`
- `target_discovered`
- `target_estimated`
- `target_started`
- `file_removed`
- `target_completed`
- `warning`
- `error`
- `summary`

UI 必须依赖这些事件，而不是自由格式日志字符串。

## 开源准备

公开推广前：

- 移除捆绑的 WizTree 二进制文件和语言文件。
- 在 `.gitignore` 中加入本地工具、日志、构建输出和临时包。
- 补充 `README.md`，包含截图、安全模型、快速开始、CLI 用法、桌面用法和示例。
- 添加开源许可证；除非有理由选择更严格的许可证，否则优先使用 MIT。
- 添加 `SECURITY.md`，说明如何报告不安全清理行为。
- 添加从 `0.1.0` 开始的 `CHANGELOG.md`。
- 添加 GitHub Actions，用于 PowerShell 解析器验证、脚本测试和 .NET 构建。
- 添加自包含 Windows x64 构建的发布打包说明。

## 安全规则

现有安全姿态仍然是强制要求：

- 永不处理 Downloads、Desktop、Documents、Pictures、Music 或 Videos。
- 永不处理 `Program Files` 安装目录。
- 永不手动删除 `WinSxS`、`Windows\Installer`、驱动存储内容或还原点。
- 永不使用 `DISM /ResetBase`。
- 永不使用 `vssadmin delete shadows`。
- 锁定文件视为跳过。
- 在可用时优先使用 Windows 支持的清理命令。
- 默认先执行 dry-run 扫描，再执行清理。

桌面应用必须用简洁的用户可见文案展示这些规则，尤其是在 `Clean Selected` 之前。

## 测试策略

PowerShell 测试：

- 解析器验证。
- 参数和函数契约验证。
- 不安全模式检查。
- JSONL 架构检查。
- 包含目标过滤行为。
- dry-run 不删除文件。

.NET 测试：

- JSONL 解析器能将引擎事件映射到视图模型。
- 进度聚合能处理缺失事件或警告事件。
- 目标选择能生成预期的 `-IncludeTargets` 参数。
- 管理员检测和重新启动命令构造正确。

手动验证：

- 在无管理员权限下运行扫描。
- 在管理员权限下运行扫描。
- 针对临时夹具路径运行清理。
- 验证长时间扫描期间进度和日志仍保持响应。
- 验证最终发布构建可在 Windows 10/11 上启动。

## 发布里程碑

### 里程碑 1：可信赖的开源基线

移除专有二进制文件，补充 README、许可证、安全策略、变更日志、gitignore，以及当前脚本的 CI。

### 里程碑 2：结构化引擎

添加稳定清理目标 ID、JSONL 事件、目标过滤和测试，同时保持现有 CLI 行为。

### 里程碑 3：WPF 桌面 MVP

创建 .NET 8 WPF 应用，提供扫描、可选目标、进度条、日志流、管理员状态和清理选中项流程。

### 里程碑 4：完善发布

添加截图、发布打包、签名或校验和产物、完善文档，并发布首个公开 `0.1.0` 版本。

## 验收标准

- 仓库可以在不捆绑专有可执行文件的情况下公开发布。
- 新用户能从 README 理解工具会删除什么、不会删除什么。
- CLI 仍支持安全 dry-run 和清理。
- WPF 应用可以扫描、展示预估清理类别、清理选定目标、显示进度并展示最终报告。
- 自动化测试覆盖脚本安全契约和 UI 事件解析器。
- 项目具备足够的 GitHub 推广信任材料：许可证、CI、截图、安全策略、变更日志和发布说明。

## 备注

此工作区当前不是 git 仓库，因此在初始化仓库之前无法提交此设计文档。
