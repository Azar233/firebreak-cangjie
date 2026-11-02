# GPU 体素渲染 v0.4.3

2026-11-02。默认场景渲染已从 CPU 射线计算切换为 GPU Compute；业务、仿真、项目管理和主机端图形代码仍为仓颉，GPU 内核为 HLSL。未引入 Java、C++ 桥接库或其他游戏引擎，P5 仍暂缓。

## 使用

- `./run.ps1` 启动工作台。Esc → 显示选项 → 场景渲染，在 GPU / Auto 和 CPU 间切换，选择保存在本地设置。旧设置默认自动启用 GPU。
- 页脚显示实际后端。Auto 不表示一定成功：设备/着色器不可用时显示 CPU fallback 与原因，并使用原 CPU 路径。窗口、二维地图和基线/方案比较复用同一视图实现。
- `./forest-stress.cmd` 默认以 GPU 查看约 10.9 万树的局部三维森林，Home 总览、F 局部、Tab 俯视。
- `./forest-stress.ps1 -Benchmark -Gpu` 生成 GPU 数据；不加 `-Gpu` 为 CPU 路径。测试会覆盖各自的当前结果文件，已经完成的 CSV 行在取消后保留。
- `./build.ps1 -Verify` 编译并运行全部 CPU/GPU 原生验证，含实际硬件、像素读回与完整菜单流程。原生 GPU 验证要求 D3D11 可用，不把回退当作 GPU 通过。

当前后端限定 Windows、SDL direct3d11、系统 d3dcompiler_47.dll，HLSL 运行时编译为 cs_5_0。没有宣称已经支持 Vulkan/Metal。资源有所有线程与设备代际检查；硬件设备丢失会拒绝旧资源，本轮未实现窗口/驱动重建。

## 数据流与算法实践

```text
仓颉 Scene / 显示状态
 → 单字节体素 + 8³ 区块占据 + 每格一个压缩状态字 + MC 材质图集
 → D3D11 原始只读缓冲区
 → 8×8 线程组：视口像素射线 → 世界包围盒 → 区块跳空 → 细体素 DDA
 → alpha 树叶、方向光照、燃尽、连通高亮、选中格
 → RGBA GPU 存储纹理 → GPU 内部复制到 SDL 纹理 → 原有 UI 与火焰精灵 → Present
```

沿用 [VoxelRT](https://github.com/dubiousconst282/VoxelRT) 的 MultiDDA 两级空间遍历思想，以 HLSL 独立实现；没有复制其 shader。区块没有基础体素时跳到区块边界，非空块细查。只发视口像素射线，用世界 AABB 排除不能命中地形的像素。区块索引使用移位，材质按字节读取，图集和压缩显示状态减少资源访问。保留近景局部与总览，未将全世界强制缩进窗口。

相机变化只更新 256 字节参数，不重复上传森林。场景 revision 变化更新几何、占据和列状态；火势/连通状态变化只更新每格一个 UInt32 的列状态，包含高度、燃烧阶段、烧过/正在燃烧和颜色索引。选中格、树冠开关及投影使用参数。**几何变化当前仍上传完整几何缓冲，不是脏区块局部传输或流式加载。**

主机业务与仿真数据不被 GPU 修改，地面拾取继续由 CPU 精确射线处理。常规帧不读回像素、不在 CPU 计算整张图。运动中直接生成实际画布分辨率，GPU 路径不使用 640px 模糊预览或等待 CPU 补绘。

SDL 的公共 [renderer 属性](https://wiki.libsdl.org/SDL3/SDL_GetRendererProperties) 和 [texture 属性](https://wiki.libsdl.org/SDL3/SDL_GetTextureProperties) 提供原生 D3D11 对象。仓颉调用 [D3D11 Compute/CopyResource](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nn-d3d11-id3d11devicecontext)，先 Flush SDL 命令，计算后解除 CS 资源、UAV、常量和 shader 绑定，再做 GPU 内部复制，不依赖 SDL 私有结构。不改 SDL 的图形绘制状态。

## 真实硬件与计时

通过 SDL 暴露的实际 D3D11 device → IDXGIDevice → IDXGIAdapter 查询，确认使用 **NVIDIA GeForce RTX 4060 Laptop GPU**，不是根据系统显卡列表推测。CPU/RAM 与 v0.4.2 相同，i7-13700H、15.64GiB。SDL direct3d11、vsync=1，所有测试保留每帧 12ms 等待，因此约 70FPS 不代表 GPU 吞吐上限。

循环预热 3 帧、采样 24 帧。GPU 的提交时延和完成时延分开：`completed_gpu_ms` 使用 [D3D11 timestamp/disjoint 查询](https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d11-graphics-reference-overviews-query) 的三个样本中位数，覆盖计算和 GPU 纹理复制；时钟失效会报错，不把异常样本记作加速。查询仅用于测试，普通帧不等待时间戳。显式像素 readback 只用于验证。

GPU CSV 中保留的 `raster_median_ms` 是同轮运行的 **CPU 完整图参考**，不是 GPU 时间；`completed_gpu_ms` 才是 GPU 已完成时间，普通 `lastRenderMs` 是 CPU 提交耗时。`settle_ms` 包含首次 shader 编译、上传与首次 Present 提交，不称为 GPU 完成延迟。实际旋转、平移和火焰 FPS 包含呈现与固定等待，不能用提交时间的倒数替代。

## 最终结果

同一份 1536×1536、seed=42、109,253 个树模型。小窗口 1280×860，三维原生画布 950×578；大窗口 2560×1380、画布 2230×1098。下表 CPU 为 v0.4.2 已保留数据，GPU 为本轮最终源码运行结果。

| 用户操作 | CPU | GPU |
|---|---:|---:|
| 十万树局部旋转，小窗口 | 27.1 FPS | 73.7 FPS |
| 十万树局部旋转，大窗口 | 31.5 FPS | 62.7 FPS |
| 十万树总览旋转，小窗口 | 30.1 FPS | 74.3 FPS |
| 十万树总览旋转，大窗口 | 36.7 FPS | 72.4 FPS |
| 真实小场景火焰回放，小窗口 | 37.9 FPS | 69.2 FPS |
| 真实小场景火焰回放，大窗口 | 44.9 FPS | 69.3 FPS |

GPU 局部平移为 73.3/73.7 FPS。大窗口局部 GPU 已完成计算+复制时间中位数 11.67ms，总览为 3.86ms，俯视 1.44ms；小窗口对应 0.28/6.71/0.08ms。GPU 时钟、缓存和首次采样历史会影响短时间查询，不能把小窗口单项比大窗口慢解释为分辨率更高反而更便宜。本轮保留全部数据，没有挑选试跑中的最好数值，也没有进行长时间稳定性测试。

相机连续变化后，十万树每个 GPU 案例仍只有 4 次输入上传（材质、体素、占据、状态），分别完成 31 次 dispatch；带平移的局部案例为 58 次 dispatch，同样只有 4 次上传。这验证了相机变化没有重新传整个森林。

GPU 运动中使用上述完整原生画布，CPU 基线运动中使用 640px 宽预览。因此 FPS 比较反映实际交互体验，并不是同一像素数的纯内核吞吐比。260 项检查和画面均由真实 SDL/D3D11 生成，未使用示意图代替实测。

## 验证与边界

260 项原生检查通过，保留原有 247 项。新增真实 GPU 读回地形/天空；262,144 个俯视像素逐通道与 CPU 对照，允许 FP32 颜色计算的一档舍入差，覆盖树叶 alpha、隐藏树冠、燃尽、灰烬、残桩、连通区域调色和选中格。还检查相机不重传、火势只传状态、revision 更新、非 8 整倍数目标、原生时间戳、资源释放、CPU/GPU 来回切换、明确回退、本地偏好兼容及菜单切换不改变场地和评估版本。

现有菜单多尺寸命中检查覆盖新增按钮。CPU 原有 41,472 条参考射线与边角回归继续通过。GPU 的 FP32 与 CPU Float64 在三维边界采样上不承诺位级一致；三维整体观感仍由用户审查。截图仅检查真实资源、基本位置与地形实际呈现。

十万树案例仍是独立渲染诊断；规划和真实传播保持 24×20。火焰回放用真实小场景和每帧历史更新，不代表十万树同时燃烧、烟雾或大规模传播已验证。当前是 GPU 两级 DDA，并非 MC 的区块表面网格，也没有贪婪网格、世界 LOD、遮挡层次或磁盘流式驻留。后续在更大/更高地形、烟雾和动态负载暴露瓶颈后再比较这些路线。

进程工作集和峰值不等同于显存，本轮没有记录专用 GPU 显存用量。GPU 与 CPU 使用相同数据和相机，但 GPU 运动中画面分辨率更高；性能对照应连同这一差异阅读。

- [GPU 数据](../artifacts/gpu-benchmark.csv)、[真实工作台](../artifacts/gpu-workbench.csv)、[260 项检查](../artifacts/gpu-checks.log)
- [v0.4.2 CPU 数据](../artifacts/forest-benchmark.csv)、[v0.4.2 工作台](../artifacts/forest-workbench.csv)
- [GPU 局部森林](../artifacts/gpu-forest-local.png)、[总览](../artifacts/gpu-forest-overview.png)、[菜单](../artifacts/gpu-menu.png)
