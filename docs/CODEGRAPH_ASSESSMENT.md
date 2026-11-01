# CodeGraph 对《断火线》的适用性调研

日期：2026-11-02。结论：适合作为可选的代码导航和影响范围候选查询工具；目前不适合成为唯一依赖分析或测试选择依据。不需要作为应用依赖或正式交付前置条件。

## 版本与来源

- 用户提供的包：`@cangjie-lang/codegraph`。
- npm registry 查询到的 latest：`1.5.0-cangjie-1.0.5.3`。仓颉扩展发行版，不能用当前上游 main 的功能和宣传成绩替代该版本的验证。
- 包仓库：[SunriseSummer/codegraph-cangjie](https://github.com/SunriseSummer/codegraph-cangjie)，对应说明分支 [cangjie-1.0.5](https://github.com/SunriseSummer/codegraph-cangjie/tree/cangjie-1.0.5)。npm metadata 声明 MIT。
- Windows x64 原生平台包与运行时可用，平台包解包大小 262953668 字节，约 263 MB，索引另计。本机 Node v24.14.0 / npm 11.11.0 下 CLI 启动成功。
- 实际包带仓颉 Tree-sitter grammar、仓颉符号提取器，能识别 `.cj`，不是只靠文本搜索。

## 隔离试用范围

只在 `.tools/codegraph-research` 安装了固定版本开发工具；没有执行 `npm install -g`、`codegraph install` 或修改 Codex 配置/全局 AGENTS，也没有在真实 firebreak 目录写入索引。

使用 `.reference/codegraph-research/fixture` 中的代码副本建图，不改变项目源码或依赖配置。试用时设置 `CODEGRAPH_TELEMETRY=0`、`DO_NOT_TRACK=1`、`CODEGRAPH_NO_UPDATE_CHECK=1`、`CODEGRAPH_NO_DOWNLOAD=1`、`CODEGRAPH_NO_DAEMON=1`。没有验证 MCP 自动接入本会话或 watcher 长期运行。

## 实测结果

| 输入 | 索引结果 | 观测 |
|---|---|---|
| 断火线 15 个仓颉文件，约 2050 非空行 | 412 节点、2297 边，DB 约 2.7 MiB | 完整 CLI 冷启动约 9.2 秒；工具内部索引统计 1.1 秒 |
| 业务 + CangjieMagic，默认排除 vendor | 289 文件、6123 节点、13816 边 | SDL 没有进入图，不能把“索引成功”视为依赖覆盖完整 |
| 业务 + SDL + Magic，显式纳入 vendor | 520 文件（518 CJ + 2 Python）、10832 节点、27661 边，DB 约 30.42 MiB | 完整 CLI 重建约 21.4 秒；工具内部索引统计 1.1 秒 |

仅单机单次观测，包含进程/模块/worker 启动开销，不是严谨性能基准，也未测驻留内存。没有做 AI 端到端 token、费用或代码正确率的 A/B 实验，不能承诺宣传中的节省比例。

### 已证实有用

- `callers setFireState` 找到 `refreshExperimentView`。
- `callers refreshExperimentView` 找到 `updateExperiment`、`simulationAction`、`syncScene` 与对应验证入口。
- `impact fireDisplayMaterial --depth 4` 给出 17 个候选影响节点，包含射线、颜色、行绘制、缓存准备、UI、地面选格和测试代码。
- 依赖纳入后，`callees VoxelView.rows` 可以连接到 SDL 的 `Surface.writePixel`，返回真实文件和行号。
- 这些查询对跨文件理解、后续批量评估/异步取消以及图形后端调整有实际导航价值。它辅助 AI 找上下文，不负责生成或验证正确算法。

### 已观察到的限制

1. **明确漏边**：`callers FireRun.advance` 返回 tick 和数个验证函数，但漏掉真实的 `App.simulationAction`。后者使用 `let r=experiment.run ?? experiment.create(...)` 后调用 `r.advance()`；其 `r.play()` 和 `r.seek()` 也未出现在该方法的 callees 中。加入 SDL/Magic 后仍漏掉 `advance` 的这条调用。尚未调试解析器，不能断言内部根因，但不能把空结果当成无调用。
2. **同名消歧**：仅查 `advance` 会聚合 `FireRun.advance` 和 `PixelFont.advance`；应使用 `FireRun.advance` 等限定名称。
3. **测试命名需配置**：默认 `affected src/scene.cj` 返回空测试列表；加入 `--filter 'src/verify*.cj'` 后找到 5 个验证文件。不能直接使用默认结果裁剪现有验证入口。
4. **依赖默认遗漏**：`vendor` 默认不索引。本次仅在隔离副本的 `.gitignore` 加 `!**/vendor/` 后纳入 SDL。真实工作区的 `.reference`、无关原型等也需要明确范围；尚未设计或应用正式索引配置。
5. **图谱不判断分支语义**：燃尽过滤的影响图列出了地面选格，但源码中 `groundOnly` 跳过该过滤。结果适合作为检查清单，需要人工/AI 读实现判定实际回归范围。
6. **更大图未必更准确**：纳入依赖后的 rows 查询中还出现了与同名 color 相关的 SDL 字段，需要源码复核。没有验证宏展开、C FFI 或所有动态/可选类型调用的完整覆盖。

## 接入建议

- 当前业务规模小，继续保留 rg、源码阅读和现有 142 项逻辑/资源检查；不为工具改应用架构或语言栈。
- 建议先以固定版本 CLI 按需辅助，优先查跨文件调用、SDK 定义和改动候选范围；后续 P3/P5 代码增多后再评估持续 MCP 集成的收益。
- 安装 CLI、建立项目索引、AI 主动调用是不同步骤；只有全局 npm 安装不会自动让当前 AI 使用图谱。
- 正式接入时评估索引范围、verify*.cj 过滤和限定名称查询。不要把整个 E:\CangJie 的无关原型、Minecraft 资源或构建产物混入业务图。
- 当前发行包的 Codex 安装器代码会写入用户级 config.toml 和 AGENTS.md；若后续接入，应保留既有协作规则，不直接接受未经核对的全局指令改写。
- 该工具仅用于开发，Node/Rust 运行时不进入断火线程序或用户交付包，应用业务仍为仓颉 + SDL。
- [发行分支遥测说明](https://github.com/SunriseSummer/codegraph-cangjie/blob/cangjie-1.0.5/TELEMETRY.md) 声明源码留在本地，但默认存在匿名使用统计，可关闭。本次已通过环境变量关闭；没有声称对全部网络行为做抓包审计。

## 复核证据

完整输出保留在 `E:\CangJie\.reference\codegraph-research`，包括 npm README/包信息、索引日志、限定名称调用查询、simulationAction 的 callees、默认/自定义测试过滤结果、依赖覆盖与状态输出。试用索引只针对副本，后续代码变化不会自动更新这些研究快照。

未修改应用源码，没有运行与工具调研无关的应用回归。是否采用全局 CLI / MCP 尚未执行；当前建议是保留可选辅助，而不引入强制流程。

## 选择性接入更新（2026-11-02）

用户授权后已采用项目内可选 CLI 方式：工具复用迁移至 `.tools/codegraph`；入口 `tools/codegraph.ps1`，新环境准备 `tools/prepare-codegraph.ps1`。查询前同步真实源码，提供独立 Project/SDL/Magic 范围与项目 verify*.cj 过滤。新增项目级 AGENTS 说明，保留源码核对和现有验证入口；没有全局安装或自动修改 Codex MCP 配置。

验证了实际调用/影响查询、SDL/Magic 符号导航、增改删同步、PowerShell 5 JSON、路径边界、环境设置恢复，以及依赖 Git 仓库内生成索引的忽略。当前 Project 范围包含业务 src 和兼容性探针，共 16 个仓颉文件，不等同于早期只复制 src 的 15 文件研究快照。具体用法、边界和接入验证见 `CODEGRAPH_USAGE.md`。
