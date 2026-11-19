# 测试与结果

用例、检查工具和结果统一在本目录，与 Game 工程分离。以下命令从仓库根目录执行。

## 依赖与统一入口

需要 **Python 3.10+、Pillow、Godot 4.7.2**。美术工具和编辑器共用 Pillow，但各自保留 requirements 文件，便于独立安装。

```sh
python -m pip install -r tools/art/requirements.txt
python test/tools/run_tests.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
```

Windows 示例：

```powershell
python test/tools/run_tests.py --godot "C:\Godot\Godot_v4.7.2-stable_win64.exe"
```

也可设置 `GODOT_EXE`；未指定时查找 PATH 中的 godot。运行工具可从其他工作目录调用，会自动定位工程。成功退出0，失败或超时返回非零。导入失败时跳过依赖步骤，汇总仍判失败。

## 用例与工具

统一入口目前包含16组：导入、12组 Godot 流程、临时素材、美术工具、内容编辑器。内容编辑器组还会在隔离 Game 副本中进行资源导入、Godot 关卡预览和剧情运行检查。

| 用例 | 覆盖内容 |
| --- | --- |
| `cases/test_state.gd`、`test_menu_flow.gd` | 经济、许可证、存档、主菜单与三栏位；状态检查由菜单用例加载 |
| `cases/test_cabin_smoke.gd`、`test_home_flow.gd` | 规则页、Home 初始化、视角、电脑、设置与地表流程 |
| `cases/test_build_flow.gd`、`test_fixture_flow.gd` | 家具布局、边界、挂点、高亮、扩建耗电和迁移 |
| `cases/test_construction_flow.gd` | 独立装修场景、1秒蓄力、真实拖放、仓库、拆除、退出 |
| `cases/test_item_map_flow.gd`、`test_settings_input.gd` | 电脑收纳/旋转、地图往返、真实鼠标点击设置 |
| `cases/test_customer_orders.gd`、`test_commerce_flow.gd` | 类别订单、预算、原子结算、拖放、送客、去重和日结 |
| `cases/test_art_tools.py` | 区域中位数、像素块多数色、动画帧对齐、筛选和文生图离线契约 |
| `cases/test_content_editors.py` | 编辑 API、输入/引用校验、稳定 ID、Godot 接口及场景导出 |
| `cases/test_content_runtime.gd` | 由上述 Python 用例调用：新增头像、剧情恢复、关系去重、跨日事件、地图和 NPC |
| `cases/test_exploration_systems.gd` | 真实Shift输入、体力/减速、噪声与警觉、扑击、柜子、共用高亮及偏移街道 |
| `cases/test_temp_art.py` | 51份Aseprite的全部帧与运行PNG逐像素一致 |
| `tools/check_content_catalogs_browser.py` | 新目录增删/恢复、素材选择、加权柜子、偏移起点、怪物拖放与实例编辑 |
| `tools/capture_exploration.gd` | 可选角色/老鼠/体力、柜子描边及内容窗口渲染截图 |
| `tools/run_tests.py` | 统一运行、隔离环境、超时控制及结果汇总 |
| `tools/check_editors_browser.py` | 可选真实浏览器的卡片/地图/对话编辑流程 |
| `tools/capture_home.gd`、`capture_content_story.gd` | 可选 Home/装修与剧情渲染截图 |

按钮回归通过视口注入鼠标事件，验证真实 GUI 命中。原生商品拖放也使用真实输入路径。Godot AI 插件测试框架位于 `Game/addons/godot_ai/testing/`，状态用例依赖它；不移动第三方实现。

## 结果位置

每次运行创建独立的 `results/<UTC时间-唯一编号>/`，包含：

- `summary.json`：步骤、退出码、通过状态与日志路径。
- 各组 `.log`，例如 import.log、commerce_flow.log、content_editors.log。
- 隔离内容检查日志：editor_content_import.log、editor_level_preview.log、editor_content_runtime.log。
- 测试生成的存档、配置和缓存。

运行器注入 `METRO_TEST_ROOT` 与 `METRO_TEST_RESULTS`，隔离配置、用户数据和存档。直接运行 GDScript 用例需自行提供这些变量，推荐使用统一入口。结果目录不提交 Git，不需要时可以删除；Windows 启动日志另在 `results/logs/`。

## 浏览器交互检查

需要额外安装 Playwright 和 Chromium。当前检查脚本使用 `/usr/bin/chromium`，其他系统先调整脚本的 executable_path。

```sh
python -m pip install playwright
python test/tools/check_editors_browser.py
```

工具启动临时项目与本地服务，验证头像卡选择、客户保存、多轮对话与拖拽连线、事件选择、线路图选站、不等长街道增减/撤销、原生建筑及 NPC 拖入、素材复用和 Godot 连接。当前脚本使用云环境的 Godot 绝对路径，迁移机器时一并调整。截图在 `results/editor-ui/`，不修改正在编辑的工程。

## 可选图形捕获

需要 X11 和图形驱动，不能使用 headless。设置 DISPLAY、METRO_TEST_RESULTS，以及独立的测试存档路径，再运行：

```sh
Godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path Game --script /absolute/path/to/test/tools/capture_home.gd -- --save-file=/path/to/test/results/visual/capture_save.json
```

`capture_content_story.gd` 使用相同环境与参数方式，输出剧情优先级、分支和结束截图。截图需要人工检查，自动检查不覆盖主观画面和音频体验。

新增目录的真实鼠标检查：`python test/tools/check_content_catalogs_browser.py`。同样使用隔离项目，截图输出至 `results/catalog-ui/`。

`exploration_hud` 覆盖全屏/背包键及鼠标按钮、主动位换装与容量失败、16版存档及15版迁移、空格使用、暗处/室外拾取、自动关灯、敌人绘制顺序和循环脚步声。界面截图位于 `results/exploration-hud/`。
