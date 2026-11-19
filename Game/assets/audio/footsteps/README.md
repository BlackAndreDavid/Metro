# 探索脚步声

`walk_loop.wav`：柔和噪声与低通摩擦的沙沙声，每步0.40秒；`run_loop.wav`：短促噪声瞬态叠加低频落脚声，每步0.24秒。均为22050Hz、单声道、16位，四步一循环。移动停止或碰到边界时立即停止，走跑切换时更换音轨。

生成工具：仓库根目录运行 `python tools/generate_footsteps.py`，无需第三方依赖。固定种子生成三套候选，以目标响度差最小且无削波、接缝为零为筛选依据；只写入选中的第三套两条音轨，其他候选不保留。指标见 `evaluation.json`。这种筛选只代表客观音频检查，最终听感可在游戏中试听后调整。

参考音频来自 [Kenney Starter Kit 3D Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer)，提交 `3fa8a04b1c01ab23db43123d4ce814a34c3fc7f0` 的 `sounds/walking.ogg`；该项目 README 标明音效素材为 CC0。参考其短落脚声及尾部结构，并用原游戏走/跑步间隔区分节奏；这里保留的音频全部为函数合成，不含参考录音采样。使用 `--reference /path/to/decoded-walking.wav` 可重新计算参考指标；普通重新生成无需下载素材。
