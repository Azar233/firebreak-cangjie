# P0 验收记录

日期：2026-11-01。状态：P0 实现与逻辑检查完成，整体视觉效果待用户审查。

## 实际环境与依赖

- 仓颉编译器：`1.0.5 (cjnative)`，target `x86_64-w64-mingw32`。
- SDL：工作区现有 `../games/soft-cat/vendor/SDL` 封装，通过本地路径引用，未修改依赖实现。
- Minecraft：用户提供的本地资源，只筛选 P0 需要的贴图与位图字体页；实际复制清单见 `artifacts/resource-copy.json`。
- 三维：仓颉 CPU 体素射线遍历、正交相机、逐像素纹理与 alpha test，SDL 显示缓存结果。无需 GLSL，因此没有待确认的着色器语言依赖。
- 图集按钮保持像素边角，工具栏使用原版 hotbar 与选中框。ASCII 和中文使用原版位图；没有把 PNG 冒充成 TTF。

## 已执行并通过

```powershell
.\build.ps1 -Verify
.\tools\verify-magic.ps1
```

沙盘检查输出见 `artifacts/p0-checks.log`：

1. 72 组相机投影—地面拾取往返，涵盖多角度、俯视、缩放和平移。
2. 相机缩放/俯仰范围；平行域外射线、背向射线安全未命中。
3. 近处体素遮挡远处体素；删除近处体素后正确暴露后方。
4. 原版树叶同时存在透明与实体像素，透明孔洞正确显示后方物体。
5. 树冠不参与地面拾取；绿色着色保留透明度。
6. 1280×860、1100×780、1600×1000 三种尺寸的 16 个控件命中、最小尺寸、布局边界和画布/面板不重叠。
7. 工具栏鼠标切换、数字键、Shift+Tab、俯视、树冠显隐、相机复位。
8. 点击树冠下地面、右键旋转、中键平移、失焦清除拖动。
9. 原版 UI、工具、中文字体页可加载，SDL 可生成截图。
10. 相机不变时复用缓存纹理；场景纹理和贴图可重复安全关闭，并在窗口销毁前释放。

最初 P0 的固定 480px 小场景光栅化记录为 **26ms**。该实现已被下方 P0.1 修正替代，不能用旧读数代表当前清晰帧性能；不承诺稳定 60 FPS、多硬件或大场地性能。没有为视觉观感反复调参与重测。

还使用启动入口所调用的 Windows PowerShell 执行了 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1 -Verify`，构建与同一组检查通过。资源筛选显式按 UTF-8 读取源码，避免 Windows PowerShell 默认编码影响中文字体页选择。

检查生成一个代表性截图：`artifacts/p0-workbench.png`。只作资源和基础定位交付，不使用截图像素基线或自动美学评分。

## P0.1 — 全屏清晰度修正

用户已认可 P0 基本效果，并反馈全屏场景变粗。原因是旧实现始终只计算 480px 宽的场景，再放大到画布。

修正内容：

- 静止画面按 `画布逻辑尺寸 × window.scale × currentPixelDensity` 确定目标像素尺寸；向上取整，避免普通尺寸欠采样。
- 超大尺寸保留等比例内存边界：最多 16,777,216 像素、单边最多 8192。预算内匹配实际画布像素。
- 相机变化先给出最高 640px 宽预览；停止变化 150ms 且不再拖动后，按行补绘清晰帧。每次最多 32 行，每 4 行检查一次约 8ms 的计算预算，完成后整体替换。
- 补绘与输入同线程分时处理，未引入后台 SDL 对象、额外语言或绘制引擎。预算是计算目标，纹理上传、慢机器上的单批工作不承诺严格 8ms。
- 相机、选区、树冠、窗口尺寸或 DPI 变化会取消旧补绘；完整缓存、预览和未完成表面均被正确释放。
- 截图入口等待本次完整清晰帧，避免交付截图停留在预览阶段。

最终执行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./firebreak/build.ps1 -Verify`：构建与全部受影响的检查通过。

新增检查覆盖：

1. 100/125/150/200% DPI 的像素尺寸换算，非法比例拒绝和极端画布分配上界。
2. 实际 SDL 大窗口产生 **2230×1142** 的场景纹理，而非固定 480px；大窗口地面拾取仍使用逻辑坐标。
3. 同尺寸的选区/相机更新也会使旧清晰帧失效，不能仅凭纹理尺寸相等复用旧内容。
4. 操作时预览、空闲时有限行数推进、相机改变取消旧表面。
5. 通过正常空闲调用完成补绘并替换预览，不依赖截图的强制完成路径。
6. 静止画面缓存复用，关闭时释放未完成补绘。

本次普通窗口 950×622 清晰帧计算累计记录为 95ms，不包含跨帧等待；不与旧 480px 的读数直接比较。实际 DPI 跨屏操作和整体清晰度、拖动手感由用户审查，未做美学打分。

代表性文件：`artifacts/p0-fullscreen.png`（大窗口）、`artifacts/p0-workbench.png`（普通窗口）；逻辑日志仍为 `artifacts/p0-checks.log`。未反复渲染进行观感微调，CangjieMagic 不受本次修改影响，未重跑其无关编译。

## CangjieMagic 的真实兼容结果

来源：`https://github.com/cangjiepl/CangjieMagic.git`，`dev` 分支固定提交：

```text
bc4624fac86ad8498b61d7e5f3b1168659bc72b5
```

最初官方配置引用 Windows stdx **1.0.0.1 / windows_x86_64_llvm**：源码及探针编译成功，但离线运行失败。依赖检查发现旧 OpenSSL FFI DLL 需要当前环境缺失的 `libssp-0.dll`；直接调整新旧 SDK DLL 搜索优先级仍不能运行，未把这些尝试记为通过。

最终采用与编译器匹配的官方 stdx **1.0.5.1 / windows_x86_64_cjnative**：

```text
https://gitcode.com/Cangjie/cangjie_stdx/releases/download/v1.0.5.1/cangjie-stdx-windows-x64-1.0.5.1.zip
SHA256 8CD08133C4F1152ACDCFF00C923D9ABE8184F081D6B92E924D2285F7E27F7162
```

其 package.json 声明 cjc_version = 1.0.5、version = 1.0.5.1。

对克隆的 CangjieMagic 仅修改 cjpm.toml 中两个 Windows bin-dependency 路径，改指向本地新 stdx；原框架源代码未改。`tools/prepare-magic.ps1` 固定提交、准备资源并复现这项路径适配，不重置已存在的不同提交。

最终探针：

- 真实导入 `magic.dsl` / `magic.prelude`。
- 编译实际 `@agent`、`@tool`。
- 创建 Researcher，读取其工具管理器。
- 从工具管理器找到 sceneSummary 并离线 invoke，校验返回摘要。
- 编译和执行成功，进程返回 0。
- 无模型请求、无密钥、无 shell/file 工具调用；不伪装成在线 Agent 验收。

探针编译有三条来自宏展开的 unused 警告；未通过修改第三方代码或关闭错误检查隐藏它们。编译与执行日志分别在 `artifacts/magic-probe-build.log`、`artifacts/magic-probe-run.log`。

## 未执行 / 未完成的范围

- Windows 操作系统层面的完整鼠标自动化、不同 DPI 和不同硬件的验收；当前交互检查是通过应用事件入口注入输入，使用实际 SDL 创建/绘制/释放。
- 大场地、动态火焰、完整编辑、保存、火势计算、方案评估与在线模型连接，均不属于本次 P0。
- 原版字体的所有字符覆盖、屏幕阅读器语义、三维实时阴影和复杂材质。
- 整体视觉观感、操作手感与材质微调：留给用户审查。
- 独立发布与商用资源分发核查在 P6，当前为用户提供资源下的本地开发样例。
