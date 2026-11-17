# 工程架构

## 场景流程

```text
project.godot
└─ scenes/ui/main_menu.tscn         主菜单：开始 / 设置 / 退出
   ├─ 设置对话框                   音量、全屏，保存在 user://settings.cfg
   └─ scenes/ui/save_select.tscn    三个独立栏位
      ├─ 空栏位 → 输入基地名 → 创建初始存档
      ├─ 已有栏位 → 验证并读取（损坏时保留文件、禁止进入）
      └─ scenes/game/cabin.tscn    车厢经营主游戏
         ├─ 规则页 → 车厢 → 交易 / 背包 / 新闻 / 线路图 / 出站探索
         └─ 返回主菜单（确认未保存进度丢失）

scenes/game/main.tscn              独立保留的早期横版原型，编辑器 F6 运行
```

## 文件分类

```text
Metro/
├─ README.md
├─ test/
│  ├─ cases/                    状态、菜单流程与车厢冒烟用例
│  ├─ tools/run_tests.py        统一测试入口
│  └─ results/                 每次运行的日志、汇总及测试存档
└─ Demo/
   ├─ project.godot               默认主菜单，GameSession 自动加载
   ├─ export_presets.cfg          原 Windows 导出配置
   ├─ scenes/
   │  ├─ ui/                     main_menu.tscn、save_select.tscn
   │  └─ game/                   cabin.tscn、main.tscn
   ├─ assets/
   │  ├─ textures/               cabin.png 与导入配置
   │  ├─ icons/                  icon.svg 与导入配置
   │  ├─ shaders/                surface_light.gdshader
   │  └─ source/                 SCENE.aseprite、CITY.aseprite、CITY.png、ExploreScene.blend
   ├─ scripts/
   │  ├─ core/game_session.gd    三栏位路径、创建、读取验证、当前选中存档
   │  ├─ ui/                     main_menu.gd、save_select.gd
   │  ├─ cabin.gd                车厢玩法与动态 UI 的主控制器
   │  ├─ cabin_state.gd          车厢状态、经济、生存、物品、存档
   │  ├─ cabin_map.gd            线路、站点信息与地图绘制
   │  ├─ cabin_markets.gd        站点供需、报价、生活补给
   │  ├─ cargo_grid.gd           背包网格与拖放旋转交互
   │  ├─ auto_repair.gd          汽修课程、车辆与可拆零件
   │  ├─ surface_block.gd        地表街区、建筑、搜刮与移动
   │  ├─ surface_minimap.gd      地表小地图
   │  └─ main.gd / world.gd / player.gd / state.gd
   │                             早期横版原型；state.gd 也被车厢状态继承
   ├─ addons/godot_ai/            第三方编辑器与测试插件，保留其内部目录
   ├─ README.md / ARCHITECTURE.md
   └─ 启动Demo.cmd / 打开编辑器.cmd
```

美术源文件使用 `.gdignore`，避免 Godot 自动导入 Blender 等编辑源文件及要求额外工具；运行素材独立位于 textures。第三方插件内部资源保持原布局，以免破坏升级与插件约定。`.godot/` 是本地生成缓存，不属于源码架构。

## 已完成的游戏内容与依赖

`cabin.gd` 负责界面和流程调度：车厢热点、交易、床铺结算、新闻、路线选择、出站整备和地表页面。大多数页面由代码生成，而非独立 tscn；本次没有将现有玩法拆成多个场景。

`cabin_state.gd` 继承 `state.gd`，处理账户与车电、按站库存、背包与储物柜、饮食与欠费、停电、电池充电、旅行和接应、探险倒计时、汽修进度以及 JSON 存档校验。地图、市场和汽修数据分别来自 `cabin_map.gd`、`cabin_markets.gd`、`auto_repair.gd`；显示层读取状态并调用状态方法。

`surface_block.gd` 生成邮电新村、四平路、同济大学的横版街区和建筑交互，结合小地图、照明着色器、背包与装备实现移动、室内照明、搜刮、车辆拆解和撤离。

早期原型的 `main.gd` 调度地下站与地表循环，`world.gd` 生成场景，`player.gd` 处理移动、跳跃和爬梯，`state.gd` 提供经济、检查、许可证、升级及政府回收委托。它保留为独立入口，不与新的三栏位菜单混用。

## 存档约定

- 新栏位：`user://saves/slot_1.json` 至 `slot_3.json`，基地名写入状态中的 `base_name`，每日保存会保留名称。
- 创建仅允许空栏位；不提供删除或覆盖入口。名称去除首尾空格，长度 1–24 字。
- 游戏仍通过床铺结算保存，返回菜单不会额外推进日期或自动保存。失败后重新开始沿用该栏位与基地名。
- 旧 `Demo/saves/cabin_slot.json` 或导出程序旁 `saves/cabin_slot.json` 存在时显示兼容读取入口，不自动迁移、不覆盖。
- 旧存档缺少基地名时显示“未命名基地”。正常保存沿用原有临时文件写入与重命名机制。

## 验证

使用 Godot 4.7.2：

```sh
python3 test/tools/run_tests.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
```

菜单流程测试包含 18 项检查，并运行原 `game_state` 测试（33 项断言）。新测试使用 `test/results/<运行编号>/` 独立目录验证三个栏位、命名、覆盖保护、读取、日期推进隔离、损坏文件处理和场景初始化。图形与音频效果需在桌面上人工体验。

测试代码与工具均位于工程外的根目录 `test/`，运行时仍以 `Demo/` 为 Godot 项目以解析游戏资源。第三方插件内置测试框架保持原位，由工具加载；插件默认 MCP 用例扫描不再适用于工程外用例。详见 [test/README.md](../test/README.md)。
