# 临时素材分类

原始图保持在上一级 `atlas_temp.png`、`heroine_temp.png`。本目录保存可继续编辑的 RGBA Aseprite 文件；运行图在 `../../textures/temp/`（即 `Game/assets/textures/temp/`）。

| 子目录 | 数量 | 内容 |
| --- | --- | --- |
| `characters/` | 10 | 防护服四向行走、普通主角四向行走、穿/脱防护服 |
| `monsters/` | 5 | 变异老鼠、兜帽拾荒者、真菌炮台、变异爬行兽、锈蚀机器人 |
| `items/` | 36 | 补给、药品、电池、设备、材料、容器、家具和图标 |

每个动画单独保存为多帧 `.aseprite`，静物为单帧；统一底部居中、共同画布与两像素留白，不逐帧拉伸。穿防护服动画由原脱下序列逆序得到。文件帧时长120ms，游戏播放帧率由内容定义控制。

`manifest.json` 记录原图哈希、每帧裁剪框、分类、帧数、尺寸和导出路径。仅裁剪与清理低透明背景（alpha < 96），不重新绘画或改色；原图保留供后续调整。默认接入探索的是 `suit_walk_left/right` 与 `mutant_rat`。

从仓库根目录重建：

```sh
python tools/split_temp_art.py
```

此命令从原图重建分类文件，会覆盖工具生成的同名文件。手工修改前请另存副本。验证命令见 [测试 README](../../../../test/README.md)。
