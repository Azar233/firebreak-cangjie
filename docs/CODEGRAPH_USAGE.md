# 可选 CodeGraph 开发辅助

已选择性接入仓颉 CodeGraph `1.5.0-cangjie-1.0.5.3`，只用于导航、调用链和候选影响范围查询。不是应用运行依赖，不参与 `build.ps1`、`run.ps1` 或正式交付。未安装全局命令，未修改 Codex 配置，也未启用常驻 MCP。

## 入口

在 `E:\CangJie\firebreak` 下运行：

```powershell
# 新环境首次准备；当前工作区已经准备好
.\tools\prepare-codegraph.ps1

# 状态与显式刷新；其余查询也会先自动同步真实源码
.\tools\codegraph.ps1 -Action Status
.\tools\codegraph.ps1 -Action Refresh

# 使用限定名称区分同名方法
.\tools\codegraph.ps1 -Action Query -Names FireRun -Json
.\tools\codegraph.ps1 -Action Callers -Names App.refreshExperimentView -Json
.\tools\codegraph.ps1 -Action Callees -Names VoxelView.rows -Json
.\tools\codegraph.ps1 -Action Impact -Names fireDisplayMaterial -Depth 4 -Json

# 只提供受影响验证文件的候选清单，不执行或裁剪测试
.\tools\codegraph.ps1 -Action Affected -Names src/scene.cj -Json

# 单独查看共享库的定义与调用，避免把无关项目混入主图
.\tools\codegraph.ps1 -Scope SDL -Action Callees -Names Surface.writePixel -Json
.\tools\codegraph.ps1 -Scope Magic -Action Query -Names ToolRequest -Json
```

`Status/Refresh` 使用文本输出，其余动作可选 JSON。`Affected` 仅支持 Project 范围，自动使用 `src/verify*.cj` 过滤，路径必须在项目内。可以用 `-Names @('src/scene.cj','src/renderer.cj')` 提供多个文件；符号查询每次一个名称。

## 已接入的边界

- 工具保存在工作区 `.tools/codegraph`。首次准备需要 Node/npm；版本固定，不自动追随 latest，不执行 npm 生命周期脚本。
- Project、SDL、Magic 三个范围各自在自身根目录创建 `.codegraph/`。索引已加入忽略，未修改 SDL/Magic 的源码或依赖配置。
- 每次查询前执行 init/sync，处理新增、修改和删除。这里使用真实源码，不再查询调研时的冻结副本。
- 各范围是**独立导航图**，不承诺跨图完整调用分析。SDK 定义按需用 `-Scope SDL` 查；Magic 仅在本地依赖已经存在时可用。
- 仅在子进程期间关闭遥测、自动更新检查、下载回退和常驻 daemon，结束后恢复调用者的环境变量。工具不会运行 `codegraph install` 或改写全局 AGENTS。
- 不可用时继续使用 rg 与源码阅读，不阻塞仓颉构建或应用验证。索引可删除后重建，不是项目数据或保存文件。

## 查询结果怎样使用

1. 按原有流程用 rg 定位；跨文件追踪时可用图谱补充候选调用链。
2. 回到输出文件和行号核实实际数据流，特别是可选类型、`??`、动态分派和 FFI。已实测该版本漏掉 `simulationAction` 中部分 `r.advance/play/seek` 调用。
3. 不把空结果当作无调用、不把影响图当作实际回归范围、不把 Affected 清单作为跳过验证的依据。现有 `build.ps1 -Verify` 仍是应用检查入口。

## 接入验证（2026-11-02）

已检查：固定版本复用；项目调用/影响查询；自动 verify*.cj 过滤；SDL Surface.writePixel 导航；Magic ToolRequest 查询；Windows PowerShell 的 JSON 输出；新增、改名和删除源文件后的自动同步；拒绝越出项目的 Affected 路径；调用者原有/未设置的环境变量恢复。

同步检查使用 tools 下临时仓颉文件，不进入应用 src，已删除并同步清理索引。实现过程中修正了 PowerShell 将未设置变量恢复成空值的差异。没有改动应用算法或渲染，因此没有重复运行无关的 142 项应用回归。

初始调研及已知限制见 [CODEGRAPH_ASSESSMENT.md](CODEGRAPH_ASSESSMENT.md)。正式接入后，试用安装已复用迁移到 `.tools/codegraph`，旧研究副本仅作为历史证据保留。
