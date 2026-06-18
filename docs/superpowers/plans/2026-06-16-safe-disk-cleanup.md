# 安全磁盘清理与 WizTree 辅助功能实施计划

> **面向代理式执行者：** 必需子技能：使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施本计划。步骤使用复选框（`- [ ]`）语法进行跟踪。

**目标：** 修复交互式删除确认问题，并在不捆绑第三方二进制文件的前提下，增加可选的 WizTree 辅助启动支持。

**架构：** 保持单个自包含的 PowerShell 清理脚本，并采用保守删除规则。清理空目录前会先确认目录确实为空，并传入 `-Confirm:$false` 以抑制递归删除确认提示。WizTree 支持为可选能力：脚本会在自身旁边查找 `tools\WizTree\WizTree64.exe`，也可接受 `-WizTreePath`，并且只用于启动可视化检查。

**技术栈：** 兼容 PowerShell 5.1+ 的语法、Windows 内置 cmdlet、DISM，以及可选的本地 WizTree Portable 可执行文件。

---

### 任务 1：确认提示回归测试

**文件：**
- 修改：`tests/Test-SafeDiskCleanup.ps1`
- 被测目标：`SafeDiskCleanup.ps1`

- [x] **步骤 1：编写失败测试**

添加断言：`Remove-EmptyDirectories` 应保留过期但非空的目录，且不把它们计为跳过的删除失败；应删除过期空目录；目录 `Remove-Item` 调用应包含 `-Confirm:$false`。

- [x] **步骤 2：运行测试并确认失败**

运行：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1`

预期：失败，因为当前目录清理会尝试删除非空目录，并且未传入 `-Confirm:$false`。

### 任务 2：目录清理修复

**文件：**
- 修改：`SafeDiskCleanup.ps1`
- 测试：`tests/Test-SafeDiskCleanup.ps1`

- [x] **步骤 1：实施最小修复**

修改 `Remove-EmptyDirectories`：先检查子项；非空目录直接跳过，且不增加跳过的删除失败计数；只删除空目录，并传入 `-Confirm:$false`。

### 任务 3：WizTree 可选辅助功能

**文件：**
- 修改：`SafeDiskCleanup.ps1`
- 修改：`tests/Test-SafeDiskCleanup.ps1`

- [x] **步骤 1：编写失败测试**

断言顶层参数包含 `OpenWizTree`、`WizTreePath` 和 `ScanPath`；函数包含 `Resolve-WizTreeExecutable` 和 `Start-WizTreeScan`；脚本内容引用 `tools\WizTree\WizTree64.exe` 和 `/admin=1`。

- [x] **步骤 2：运行测试并确认失败**

运行：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1`

预期：失败，因为 WizTree 参数和辅助函数尚不存在。

- [x] **步骤 3：实施最小支持**

添加可选的 WizTree 路径解析和启动逻辑。如果找不到可执行文件，记录预期放置路径并继续执行。如果使用 `-OpenWizTree` 且可执行文件存在，则调用 `Start-Process`，传入扫描路径，并在当前进程已提升权限时传入 `/admin=1`。

### 任务 4：验证

**文件：**
- 使用：`SafeDiskCleanup.ps1`
- 使用：`tests/Test-SafeDiskCleanup.ps1`

- [x] **步骤 1：运行测试**

运行：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1`

预期：通过。

- [x] **步骤 2：运行 dry-run**

运行：`powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1 -DryRun -MinAgeDays 30`

预期：脚本打印 dry-run 汇总，且不删除文件。

- [x] **步骤 3：检查不安全命令**

搜索脚本中的宽泛删除模式、个人文件夹、计划任务命令、`ResetBase`、卷影副本删除和驱动存储删除。

预期：不存在不安全模式。

## 自检

- 本计划覆盖确认提示修复、可选 WizTree 辅助启动、验证测试、dry-run 验证和最终安全检查。
- 测试期间不会运行破坏性命令。
- 本计划使用明确文件路径和具体验证命令。
- 此工作区当前是 git 仓库；本次执行只更新文档状态，不自动提交。
