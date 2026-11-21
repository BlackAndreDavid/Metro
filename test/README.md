# 测试与结果

用例、检查工具和结果统一在本目录，与 Game 工程分离。以下命令从仓库根目录执行。

## 依赖与统一入口

需要 **Python 3.10+、Pillow、PySide6、Godot 4.7.2**。独立窗口接入测试需先安装 `tools/editors/requirements-desktop.txt`。美术工具和编辑器共用 Pillow，但各自保留 requirements 文件，便于独立安装。

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

统一入口目前包含24组：导入、16组 Godot 流程、临时素材、美术工具、内容编辑器、Godot 独立编辑器启动接入和原生测试器接入。内容编辑器组还会在隔离 Game 副本中进行资源导入、Godot 关卡预览和剧情运行检查。

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

`cases/test_network_runtime.gd` 验证 JSON 地图读取、原有路线、修改连接、折点与环线及贴图加载。`cases/test_content_editors.py` 另验证地图接口校验、过期写入保护及隔离工程中的 Godot 数据契约。

```sh
python test/tools/check_network_editor_browser.py
```

该工具在临时工程中验证真实鼠标拖动/新增/删除结点、线路增删与撤销、贴图导入/缩放/旋转/排序、保存重读、多窗口冲突和 Godot 连接清单。截图保存在 `test/results/network-editor/`。

`python test/tools/check_godot_editor_bridge.py` 在隔离 Godot 工程中测试真实启动按钮、自动启动偏好、独立 Qt 窗口、浏览器先启动与 Godot 先启动的双向路径关联、项目环境自动查找与路径栏自动填充、失效覆盖路径恢复和缓存保存、非法服务地址拦截、重复唤起、禁用插件时保留程序，以及窗口关闭后的清理。测试驱动为 `tools/desktop_plugin_driver.gd`。该检查也纳入统一入口。

独立窗口内部的编辑/保存可额外验证：

```sh
python -m pip install -r tools/editors/requirements-desktop.txt websockets
python test/tools/check_desktop_editor.py
```

该测试直接连接程序内置的 Qt WebEngine 页面，验证地图、物品、客户保存、双向路径、单实例与关闭，不启动浏览器程序。仍保留原三套浏览器回归测试，以核对共享界面全部功能。Qt 桌面依赖安装在另一解释器时，可设 `METRO_EDITOR_PYTHON=/path/to/python`；测试记录和截图保存在 `results/desktop-editor/` 与每轮结果的 `desktop-bridge/`。


`cases/test_geometry_contract.gd` 验证不规则占位的空洞利用、旋转镜像、存档重叠检查、手动贴图绑定、楼层高度，以及直线/弧线随机生成与同日稳定性，已纳入统一入口。目录浏览器测试包含框选增删格子、贴图拖动缩放旋转、楼层增减、物理/贴图层切换和弧线控制点拖动，截图保存在 `results/catalog-ui/`。

存档维护检查 `test_save_management.gd` 验证确认/取消、修复备份、无损重排、缺失定义/空间不足/核心数据异常时停止，以及删除隔离。

`tools/check_tester.py` 启动真实原生 Qt 窗口和隔离 Godot 游戏，验证双向登记、插件启动、数值/向量修改、物品生成、正式存档不变、鉴权和单实例退出。`check_packaged_tools.py` 由目标平台打包工作流运行，验证实际生成的程序。

## 编辑项保存检查

```sh
python test/tools/check_save_sessions_browser.py
python test/tools/check_desktop_editor.py
```

前者需要 Playwright 与 Chromium，在隔离副本中覆盖按物品/建筑/关卡/顾客/线路图保存、连续修改不写盘、保存/放弃/取消、保存失败留在原项和子建筑归入关卡。后者还验证真实 Qt 窗口关闭时取消退出、保存后退出。结果位于 `test/results/save-sessions/` 和 `test/results/desktop-editor/`，不修改正常工程内容。

家具专项：`cases/test_furniture_system.gd` 覆盖双平面占位、支撑、距离、移动、收纳、可调储物、动画、迁移及退出检查；`python test/tools/check_furniture_editor_browser.py` 检查真实家具编辑、GIF转换、物品关联与保存。截图位于 `test/results/furniture-editor/`。

## 装修与建造回归

`cases/test_renovation_workflow.gd` 使用真实家具目录，覆盖初始冲突恢复、每车门窗、临时收纳清空、地面边界吸附、分解确认与原子回滚、技术保存、建造条件亮暗及排序，以及真实鼠标操作临时仓库和单家具储物格。已纳入统一入口。

部分既有家具规则用例使用 `cases/support/furniture_fixtures.gd` 的进程内窗户墙面基准，隔离美术占位变化；不修改工程定义。新增装修用例保留实际窗户地面格，负责当前内容布局和迁移兼容检查。

`python test/tools/check_preview_layers_browser.py` 检查物品/家具占位和建筑碰撞箱实际像素叠放、隐藏开关与数据不变；截图在 `results/preview-layers/`。`python test/tools/check_furniture_editor_browser.py` 同时验证家具贴图绑定、动画、双平面占位和保存。
