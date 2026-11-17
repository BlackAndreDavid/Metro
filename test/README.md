# 测试

测试用例、运行工具和结果统一存放于此目录，与 `Demo/` 游戏工程分离。

```text
test/
├─ cases/
│  ├─ test_state.gd          经济、许可证、存档：32 项断言
│  ├─ test_menu_flow.gd      菜单与三栏位：18 项检查，包含状态回归
│  ├─ test_cabin_smoke.gd    规则页 → Home UI 初始化
│  ├─ test_home_flow.gd      31 项检查：视角、真实电脑点击、设置与地表流程
│  ├─ test_build_flow.gd     家具、材料、扩建、耗电、存档迁移和多车厢回正
│  ├─ test_fixture_flow.gd   五类占格、边界、四挂点、前景层和统一高亮
│  ├─ test_item_map_flow.gd  电脑旋转与收纳、满格保护、地图往返 Home／建造
│  └─ test_construction_flow.gd  独立场景、状态共享、真实鼠标选择／按钮、2秒蓄力与真实拖放、无效落点、拆除、仓库及退出
├─ tools/
│  ├─ capture_home.gd       可选 OpenGL 图形截图验证
│  └─ run_tests.py           统一入口：资源导入 → 菜单与状态 → Home 冒烟 → Home 集成 → 家具与建造 → 独立设施 → 建造模块
├─ results/
│  ├─ <UTC时间-唯一编号>/   每次运行独立保存
│  │  ├─ summary.json       各步骤退出码、通过状态和日志路径
│  │  ├─ import.log
│  │  ├─ menu_flow.log
│  │  ├─ cabin_smoke.log
│  │  ├─ home_flow.log
│  │  ├─ build_flow.log
│  │  ├─ fixture_flow.log
│  │  ├─ construction_flow.log
│  │  ├─ item_map_flow.log
│  │  └─ 生成的存档、配置与缓存
│  ├─ legacy/              迁移前已有的测试存档（如存在）
│  └─ logs/                Windows 游戏、编辑器启动日志
└─ README.md
```

## 运行

需要 Python 3 和 Godot 4.7.2，无额外 Python 包。从仓库根目录运行：

```sh
python3 test/tools/run_tests.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
```

Windows 示例：

```powershell
python test/tools/run_tests.py --godot "C:\Godot\Godot_v4.7.2-stable_win64.exe"
```

支持 `GODOT_EXE` 环境变量；未指定时使用 PATH 中的 `godot`。运行工具也可以从其他工作目录调用，它自动定位 `Demo/`。所有步骤成功才返回退出码 0；失败或超时返回非零，检查对应结果目录中的日志。导入失败时不执行依赖该步骤的测试，汇总中仅记录已执行步骤，整体判为失败。

工具注入 `METRO_TEST_ROOT` 和 `METRO_TEST_RESULTS`，以绝对路径加载工程外的用例。独立运行 GDScript 用例时也必须提供这两个目录；推荐始终使用统一入口。测试隔离用户配置与游戏存档，结果目录不会提交到 Git。每次运行保留独立结果，便于对比；可在不需要时删除。

Godot AI 第三方插件内置的测试框架仍位于 `Demo/addons/godot_ai/testing/`，状态用例依赖其断言与结果统计；不移动或复制第三方实现。工程外用例不再由 MCP 默认的 `res://tests/` 自动发现。

验证范围为无界面的场景、状态和存档流程，不包含人工图形、音频体验。

## 可选图形验证

存在 X11 显示时，可用 `tools/capture_home.gd` 生成空槽、家具、描边、扩建、设置真实渲染截图（包括门、柜子、屏幕的独立描边、四个挂点、统一建造选择与仓库）。设置 `DISPLAY`、`METRO_TEST_RESULTS` 和独立的 `--save-file` 路径，随后执行：

```sh
Godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path Demo --script /absolute/path/to/test/tools/capture_home.gd -- --save-file=/path/to/test/results/visual/capture_save.json
```

此步骤需要图形驱动，不能加 `--headless`；目录须位于测试结果目录。`METRO_TEST_RESULTS` 指向截图输出目录。常规自动测试仍支持无界面运行。

按钮回归使用 `InputEventMouseButton` 注入视口，验证实际 GUI 命中与状态变化，防止 `pressed.emit()` 绕过输入遮挡。旧问题的复现记录可保存在 results 中；图形捕获包含无 Home UI 的独立建造场景。
