# 森林沙盘渲染调研：Minecraft、Voxy 与开源算法

调研日期：2026-11-01。范围：原理与候选路线调查，不改动 P0.1 程序，不声明任何大场景性能已经验证。

## 结论

Chunk 是合适的共同基础，但仅分块不能解决当前逐像素 CPU 射线计算的成本。

- 保持纯仓颉渲染时，最直接的升级是分块占据数据、两级 DDA/空区跳过、相机参数预计算和批量像素写入；结合按屏幕尺度选取的森林显示 LOD。
- 若明确采用 GPU 网格绘制，则使用 Chunk 脏块更新、隐藏面剔除、可见性筛选、贪婪网格和批量提交；这是一条不同的绘制后端路线。
- 仿真精度和显示精度分开。远景显示聚合不能改变传播图、燃料、隔离带、保护目标及统计结果。
- 当前正交相机应主要依据屏幕占比选择 LOD，不照搬第一人称游戏仅基于距离的规则。

## 1. Minecraft 原版的 Chunk 与网格

以 Java 版经典区块地形管线说明：Chunk 是 16×16 水平范围的地形列，内部 section 通常为 16×16×16。section 组织几何与更新，地形表面生成为四边形/三角形网格后交给 GPU 绘制，不是每帧对所有方块各发一次绘制调用。

典型流程：

```text
区块 / section 数据
  → 方块模型与相邻面可见性
  → 按不透明、裁切透明、半透明等类别组织网格
  → 受改动影响的 section 更新
  → 可见区域筛选
  → GPU 绘制与深度测试
```

Chunk 是组织单位，不是某个神奇的加速算法。它让局部修改、可见区域筛选和有限加载成为可能。边界方块变化时，相关邻块的共享面也需要更新。

不要把传统原版等同于“已经使用所有贪婪网格与远景 LOD 优化”。这些是不同的可选技术。

版本限定：Minecraft Java 正在演进图形 API，不能笼统地称所有当前原版都只用 OpenGL。Mojang 2026-02-18 公告说明向 Vulkan 迁移；26.4 Snapshot 1 在 2026-09-22 将 Vulkan 作为默认偏好。这不改变“分块组织数据/网格”与“选用何种 GPU API”是两个不同层面。

资料：

- [Sodium 作者 douira 的原始研究：section、quad 和半透明排序](https://douira.dev/assets/document/douira-master-thesis.pdf)，2024，描述研究所基于的版本，不声称涵盖所有新版本细节。
- [Mojang：Another step towards Vibrant Visuals](https://www.minecraft.net/sv-se/article/another-step-towards-vibrant-visuals-for-java-edition)
- [官方 26.4 Snapshot 1 说明](https://feedback.minecraft.net/hc/en-us/articles/49076034811533-Minecraft-Java-Edition-26-4-Snapshot-1)

## 2. Voxy：借鉴层级思想，不照搬模组

核对的仓库：`https://github.com/MCRcortex/voxy`。

核对提交：`5bf33350a1cc7bb7e2b5d947b236c56d878b8a7d`，2026-10-19。源码副本在工作区 `.reference/rendering/voxy`，没有加入应用依赖。

从该提交可确认：

- `WorldSection.java`：自己的世界 section 具有细节层级，数据单元为 32³。
- `WorldVoxilizedSectionMipper.java`：逐级从细粒度生成更粗的体素表示。
- `HierarchicalOcclusionTraverser.java` / `traversal_dev.comp`：GPU 层级遍历，包含视锥、屏幕空间尺度与遮挡相关数据。
- `HiZBuffer.java`：分层深度表示。
- `MDICSectionRenderer.java`：计算着色器与间接批量绘制的路径。
- `RenderDataFactory.java`：生成绘制数据；不能把整个 Voxy 概括成 CPU DDA 搬到 GPU。

对本项目的可借鉴点：

1. 显示数据有多层表示，不要求远处逐树逐叶。
2. 可见性和细节选择以区域为单位，避免主线程逐对象提交。
3. 细节重建、显存/数据驻留、当前视图展示分开调度。
4. 只更新受变化影响的显示区域，并向上使相应显示 LOD 失效。

不需要复制它面向超远距离 MC 世界的完整导入、存储和 GPU 管线。我们的任务是有边界的场地编辑与传播比较。

许可实际核对：此提交的 [LICENSE.md](https://github.com/MCRcortex/voxy/blob/5bf33350a1cc7bb7e2b5d947b236c56d878b8a7d/LICENSE.md) 写明 All rights reserved、Do not redistribute。它属于公开源码的架构研究对象，不列为 MIT 等宽松许可的代码候选。

原始实现链接：

- [层级遍历着色器](https://github.com/MCRcortex/voxy/blob/5bf33350a1cc7bb7e2b5d947b236c56d878b8a7d/src/main/resources/assets/voxy/shaders/lod/hierarchical/traversal_dev.comp)
- [体素多层表示生成](https://github.com/MCRcortex/voxy/blob/5bf33350a1cc7bb7e2b5d947b236c56d878b8a7d/src/main/java/me/cortex/voxy/common/voxelization/WorldVoxilizedSectionMipper.java)
- [间接绘制实现](https://github.com/MCRcortex/voxy/blob/5bf33350a1cc7bb7e2b5d947b236c56d878b8a7d/src/main/java/me/cortex/voxy/client/core/rendering/section/backend/mdic/MDICSectionRenderer.java)

## 3. 截图中的优化项

| 方法 | 作用 | 本项目判断 |
|---|---|---|
| 逐面可见性剔除 | 相邻不透明块之间的内部面不生成；背面剔除另外处理朝向 | 网格后端第一优先。裁切透明树叶不能简单视作完整遮挡块 |
| 素材图集 | 减少 GPU 纹理切换与提交次数 | 网格批量绘制时重要；当前 CPU 已将纹理放入内存，打图集不会自动解决射线成本 |
| 视锥剔除 | 剔除与可见体不相交的 Chunk 包围盒 | 低复杂度，优先；正交相机使用正交可见体，不假定透视锥体 |
| 遮挡剔除 | 跳过被前方不透明物完整遮挡的区域 | 后置优化。山地/建筑可能有收益；俯视平坦林地的收益需测量，树叶孔洞不能作为实心遮挡 |
| Unity Mesh 顶点开销 | 减少顶点、重建、上传和不必要缓冲 | Unity API 本身不使用；缓冲复用、局部更新和后台生成的原则可借鉴 |
| C# 运行时优化 | 减少分配、GC、主线程开销 | 不移植 C# 技巧；仓颉中检查每射线临时数组、相机重复三角函数和跨 FFI 单像素写入 |
| LOD | 缩小视图时减少几何/体素细节 | 森林重点。当前预览/高清补绘是图像分辨率切换，尚未实现几何或世界数据 LOD |
| Greedy Meshing | 合并同平面、兼容材质/属性的相邻面 | 网格路径可用，地表/道路/墙面通常更适合；不直接加速现有 DDA |

贪婪合并示例：16×16 的同材质平顶原有 256 个小四边形，可以合为 1 个。合并必须保持贴图重复，不将单张纹理拉伸到整片；方向、材质、透明类别、着色/AO 等约束也要匹配。树叶孔洞、树冠轮廓和非完整方块应单独处理。

## 4. 开源算法候选

许可为调研时仓库声明，不推断所有依赖与文件都具有相同许可。这里只调查，不直接接入其他语言的库。

| 项目 | 算法/能力 | 对本项目用途 | 仓库声明 |
|---|---|---|---|
| [cgerikj/binary-greedy-meshing](https://github.com/cgerikj/binary-greedy-meshing) | 占据位掩码、位运算面剔除、贪婪合并、紧凑 quad | 仓颉 UInt64 算法实现的重点参考，面向候选网格后端 | MIT |
| [bonsairobo/block-mesh-rs](https://github.com/bonsairobo/block-mesh-rs) | visible_block_faces、greedy_quads、边界 padding | 小而清楚，适合先写正确性基线，再比较面数/构建成本 | MIT OR Apache-2.0 |
| [dubiousconst282/VoxelRT](https://github.com/dubiousconst282/VoxelRT) | PlainDDA、MultiDDA、BrickMap、稀疏树、BVH 对照 | 与当前射线法最接近；先研究 MultiDDA 与空区跳过 | MIT |
| [GameTechDev/MaskedOcclusionCulling](https://github.com/GameTechDev/MaskedOcclusionCulling) | 层级深度、覆盖掩码、CPU 遮挡测试 | 后续确有遮挡瓶颈再参考，不作为第一项优化 | Apache-2.0 |
| [zeux/meshoptimizer](https://github.com/zeux/meshoptimizer) | 网格缓存/访问优化、简化、meshlet | 后续网格与 LOD 的进阶资料，不等同于体素贪婪建网格 | MIT |
| [Zylann/godot_voxel](https://github.com/Zylann/godot_voxel) | 体素地形模块与工程组织 | 查分块/重建/地形组织，不接入 Godot 改变技术栈 | MIT，依赖另列 |

特别相关的原作者说明：

- [0fps：Meshing in a Minecraft Game](https://0fps.net/2012/06/30/meshing-in-a-minecraft-game/)
- [0fps：Texture atlases, wrapping and mip mapping](https://0fps.net/2013/07/09/texture-atlases-wrapping-and-mip-mapping/)
- [VoxelRT 加速结构比较](https://github.com/dubiousconst282/VoxelRT/blob/alt-renderers/README.md)

项目自报的网格生成微秒数、Mrays/s 或 FPS 不作为我们仓颉程序的承诺：硬件、输入、语言、后端和是否包含上传均不同。

Sodium 也是有价值的可见性、调度和透明排序参考，但当前 [许可证声明](https://github.com/CaffeineMC/sodium#-license) 为 Polyform Shield 1.0.0，不把它列成宽松许可算法库。

## 5. 推荐的两条路线

### 路线 A：保留纯仓颉 CPU 后端，先做可测量升级

1. 显示世界按小 Chunk/brick 存储，记录空区域与非空计数。尺寸以 16³ 或较扁的森林区域为候选，通过测试决定，不强求照搬 MC。
2. 相机基向量和像素步进预计算，减少每条射线临时数组、重复 sin/cos 和资源调用。
3. 两级 DDA：先遍历较大单元，空单元整体跳过，只在非空区域进入细格。
4. 同步保持精确的地面拾取，采样和光线步进有确定性参考测试。
5. 根据屏幕投影尺度增加林冠显示 LOD，重要道路/隔离带/目标另作清晰覆盖，精细仿真完全不变。
6. 局部变化只让相关区域缓存失效；不能仅凭 Chunk 脏标记就认定像素区域一定局部，旋转/遮挡变化仍可能要求重绘。

路线 A 能直接复用现有代码与语言边界，但并不保证大规模动态森林达到高帧率。

### 路线 B：GPU Chunk 网格后端

仓颉生成表面网格 → Chunk 脏块重建 → 视锥筛选 → 材质分组/批量绘制 → 分级林冠 → 按测量需要再加遮挡剔除。

静态地形、树木几何和火焰/烟雾动态表示分开，变化颜色或燃烧状态不自动要求每步重建所有树叶。CPU 精确射线可保留给选取。

该路线涉及图形接口和通常所需的 GPU 着色器，与当前无 GLSL 的路线不同；不能未经决定就把所有业务迁往外部引擎，或把 shader 依赖隐藏成“纯仓颉全部完成”。

## 6. 下一步应测什么

先选固定种子的不同密度场地与几个地面规模，如 64²、128²、256²；这些是测试候选，不是容量承诺。

记录：可燃地块数、显示树木/体素数、分辨率、预览和完整重绘时间、平均/尾部交互延迟、分配与内存、射线平均遍历格数或网格面数、局部变化重建开销。

正确性检查包括 Chunk 边界共享面、透明树叶、LOD 切换不改变仿真结果、地面拾取、取消和旧结果失效。依照用户约定，自动检查限逻辑与基础定位；视觉效果、LOD 可接受程度由用户审查。

## 7. P1 实践记录（2026-11-01）

保留路线 A：`VoxelView.rows` 每批预计算相机基向量、方向和光线原点基准，替代逐像素调用相机三角函数。框选预览只绘覆盖线，提交编辑后才重建 24×20 的显示场景；场地变化通过同一个 dirty/取消路径使旧补绘失效。处理带不留邻树越界树冠。投影/选格和旧帧取消回归见 `artifacts/p1-checks.log`。

这还不是 Chunk 实现，没有拿重绘耗时宣称加速比。后续扩大输入时先测试不同密度和尺寸，再落实分块存储、粗级空区遍历与林冠 LOD；未启用 GPU 网格或引入 Voxy/Sodium 实现代码。
