# 开发工具索引

所有命令从仓库根目录执行。测试工具和输出统一位于 [test/](../test/README.md)。

| 文件或目录 | 用途 | 操作说明 |
| --- | --- | --- |
| `editors/` | 客户/NPC、剧情事件线和站点关卡网页编辑器，连接 Godot | [编辑器 README](editors/README.md) |
| `art_asset_tool.py`、`art/` | 统一画风、生成候选、筛选与像素精简 | [美术 README](art/README.md) |
| `import_customer_candidates.py` | 从客户候选表拆分独立角色素材，保留原图与评估 | [美术 README](art/README.md) |
| `export_home_art.py` | 将七张 Home Aseprite 源图的首帧导出为透明 PNG | 下方命令 |
| `trim_aseprite.py` | 原生裁剪支持的 Aseprite 透明画布，并验证像素 | 下方命令 |

## Home 素材导出与裁剪

先安装 Pillow：`python -m pip install -r tools/art/requirements.txt`。

```sh
python tools/export_home_art.py
python tools/trim_aseprite.py Game/assets/source/Carriage.aseprite
```

源文件位于 `Game/assets/source/`，运行图位于 `Game/assets/textures/`。导出与裁剪保留普通图层叠加；不支持的动画、分组、非普通混合或切片结构会明确报错，复杂文件请使用 Aseprite 官方工具。

裁剪改变源画布原点时，同步检查 `Game/resources/furniture/*.tres` 中的 `source_origin`；家具位置与显示大小仍由网格资源决定。操作完成后按需重新导出 PNG，并在 Godot 检查显示与高亮。家具布局参数见 [工程架构](../Game/ARCHITECTURE.md)。
