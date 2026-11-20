# 终末地铁

以末日上海地铁为背景的 Godot 游戏原型。玩家以车厢为据点，在各站之间交易、探索、收集物资并装修车厢。

## 启动游戏

使用 **Godot 4.7.2** 打开 [Game/project.godot](Game/project.godot)，按 **F5** 运行：主菜单 → 开始 → 三个存档栏位 → 命名基地或读取存档 → Home 车厢。

Windows 可使用 [启动Demo.cmd](Game/启动Demo.cmd) 直接试玩，或 [打开编辑器.cmd](Game/打开编辑器.cmd) 打开 Godot。启动脚本的引擎路径配置及游戏操作见 [游戏说明](Game/README.md)。

## 启动内容编辑器

在仓库根目录执行：

```sh
python -m pip install -r tools/editors/requirements-desktop.txt
python tools/editors/server.py
```

默认打开独立程序窗口，不启动浏览器。Godot 插件会自动登记双方路径；在“总设置 / Godot”可查看和测试连接。编辑客户、NPC 剧情和站点地图后，点击顶部“保存当前编辑”写入工程。

完整操作、跨日事件示例、地图预览和常见问题统一见 **[编辑器操作 README](tools/editors/README.md)**。

## 文件与说明索引

| 路径 | 内容 | 说明 |
| --- | --- | --- |
| `Game/scenes/` | 菜单、Home、装修、线路图、交易及探索场景 | [工程架构](Game/ARCHITECTURE.md) |
| `Game/scripts/` | 状态、交互、绘制、交易及剧情代码 | [探索架构](Game/EXPLORATION_ARCHITECTURE.md) |
| `Game/content/` | 客户、站点及关卡 JSON 数据 | [编辑器操作](tools/editors/README.md) |
| `Game/resources/` | 家具与物品 Resource 定义 | [家具与模块职责](Game/ARCHITECTURE.md) |
| `Game/assets/` | `source/` 编辑源文件、`textures/` 运行图、着色器与图标 | [美术工具](tools/art/README.md) |
| `Game/addons/` | Godot AI 第三方插件及其运行依赖 | 保留插件内部结构 |
| `Game/saves/legacy_demo/` | 迁移保留的旧调试存档 | [存档位置](Game/README.md#存档与设置) |
| `tools/` | 内容编辑器、美术生成、导出和裁剪工具 | [工具索引](tools/README.md) |
| `test/` | 测试用例、检查工具和独立运行结果 | [测试说明](test/README.md) |

目录中 `source` 与 `textures` 分别用于继续编辑和运行游戏，两者都保留。Godot 的 `.uid`、贴图 `.import` 和插件依赖属于工程文件；`.godot/`、Python 缓存及 `test/results/` 是可重新生成的本机结果，不提交到 Git。

## 验证

```sh
python -m pip install -r tools/art/requirements.txt
python test/tools/run_tests.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
```

完整依赖、浏览器交互检查与结果位置见 [test/README.md](test/README.md)。

中心城区线路参考申通地铁 D202501 版，设施、辐射和物价采用游戏设定：[上海轨道交通网络示意图](https://www.shanghai.gov.cn/shanghai/newshanghai/shgl2025.pdf)。

游戏测试器与数值调试见 [测试器说明](tools/tester/README.md)；编辑器和测试器的 Windows EXE 构建见 [打包说明](tools/build/README.md)。
