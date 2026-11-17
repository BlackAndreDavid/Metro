# 工程结构与调整指南

## 文件结构

```text
Metro/
├─ Demo/
│  ├─ project.godot
│  ├─ scenes/
│  │  ├─ ui/     main_menu.tscn、save_select.tscn、settings_panel.tscn
│  │  └─ game/   home.tscn、home_backdrop.tscn、exploration_setup.tscn、exploration.tscn、main.tscn
│  ├─ scripts/
│  │  ├─ home.gd                    游戏状态与页面调度
│  │  ├─ exploration.gd             地表场景和主控制器的连接
│  │  ├─ core/game_session.gd        三栏位存档选择
│  │  ├─ ui/                        菜单、设置、车厢视角、探索整备
│  │  ├─ cabin_state.gd             车厢经济、生存、物品与存档
│  │  ├─ cabin_map.gd               地铁线路与地图绘制
│  │  ├─ cabin_markets.gd           各站供需与报价
│  │  ├─ cargo_grid.gd              网格背包、拖放旋转
│  │  ├─ surface_block.gd           街区、建筑、移动、搜刮、车辆
│  │  ├─ surface_minimap.gd         地表小地图
│  │  ├─ auto_repair.gd             汽修课程及拆解零件
│  │  └─ main.gd / world.gd / player.gd / state.gd
│  │                                早期横版原型（state 也是车厢状态基类）
│  ├─ assets/
│  │  ├─ textures/                  Carriage.png、BG_Afternoon.png；旧 cabin.png 保留
│  │  ├─ source/                    Carriage.aseprite、BG_Afternoon.aseprite 等编辑源文件
│  │  ├─ shaders/                   地表照明着色器
│  │  └─ icons/
│  └─ addons/godot_ai/               第三方插件，保持内部布局
├─ tools/                           美术导出、原生 Aseprite 透明画布裁剪工具
└─ test/
   ├─ cases/                        状态、菜单、车厢冒烟和 Home 集成测试
   ├─ tools/run_tests.py             统一入口
   └─ results/                      每次运行的独立结果、日志和测试数据
```

## 主流程与设置

主菜单 → 三栏位存档（空栏位命名基地／已有栏位读取）→ `scenes/game/home.tscn`。

进入游戏后的场景原名 `cabin.tscn`，现改为 `home.tscn`；控制器也从 `cabin.gd` 更名为 `home.gd`。状态类仍叫 `cabin_state.gd`，存档格式和路径不变。旧 `main.tscn` 是独立保留的早期横版原型。

右上角“设置”打开共用的 `scenes/ui/settings_panel.tscn`：

```text
SettingsPanel (CanvasLayer，始终处理输入)
├─ Dimmer                      阻挡下方点击
└─ Center/Panel/Margin/Items
   ├─ Title
   ├─ VolumeLabel / Volume     主音量滑杆，0–1
   ├─ Fullscreen               全屏开关
   ├─ Error                    保存错误信息
   ├─ Return                   返回主菜单，进入游戏时显示
   └─ Close                    关闭设置
```

音量和全屏修改立即应用并写入 `user://settings.cfg`。主菜单也复用该面板，但隐藏返回按钮。游戏中打开设置会暂停移动、手电耗电及倒计时；关闭时补偿真实经过的时间。返回菜单会确认丢失未保存进度，取消确认仍留在设置。

## 点击“电脑”后的结构

该界面仍由 `scripts/home.gd` 动态生成，不是独立电脑 tscn。调用关系：

```text
use_hotspot("news")
└─ show_news()
   ├─ show_map()               先生成完整线路图页面
   ├─ 半透明遮罩
   └─ NewsCard                 当日新闻，覆盖在线路图上
      ├─ 标题、日期、天气
      ├─ 正文：state.news()
      └─ 关闭 / 关闭并查看线路图 → show_map()
```

关闭新闻后：

```text
Map
├─ 顶部：上海地铁线路图、当日新闻、返回车厢
├─ NetworkMapPanel             左侧线路图纸面
│  ├─ 图例
│  └─ RailMap                  cabin_map.gd 绘制线路与站点，点击回调 select_station
└─ StationDetails              右侧目的地详情
   ├─ 当前站、选中站、所属线路
   ├─ 站内设施 / 站外情报      outside_tab 控制
   │  ├─ 站内：供货、收购、价格和充电站余量
   │  └─ 站外：辐射和建筑遗址说明
   └─ 经过站点、行车耗电、前往按钮
```

调整入口（坐标均为 1280×720 的逻辑坐标，Rect2 为 x/y/宽/高）：

| 要调整的内容 | 位置 |
| --- | --- |
| 新闻卡片布局 | `home.gd → show_news()`，默认 `(318,173,644,372)` |
| 新闻文字与天气规则 | `cabin_state.gd → news()`、`weather()` |
| 电脑页面左右分栏 | `home.gd → show_map()`；左 `(40,89,865,585)`，右 `(923,89,317,585)` |
| 站内供需与报价 UI | `home.gd → show_map_market()`、`map_quote_column()` |
| 站点供需数据 | `cabin_markets.gd` |
| 线路、站点坐标和站外说明 | `cabin_map.gd` |
| 选择目的地、切换标签、出发 | `home.gd → select_station()`、`set_map_tab()`、`travel()` |

## 点击“出站探索”后的两个场景

### 1. 整备：exploration_setup.tscn

车门／出站探索 → `show_gear()` → 实例化 `scenes/game/exploration_setup.tscn`，由 `scripts/ui/exploration_setup.gd` 的 `configure()` 绘制：

- 左列：普通／加强防护服。
- 中列：手电电池、撬棍、扳手。
- 右列：小／大背包。
- 底部：账户、提示、确认出发。

根节点 Inspector 的 `panel_bounds` 控制整备面板位置与尺寸（默认 150,106,980,510）；内部按钮、文字的相对布局在 `exploration_setup.gd`。其控件依然动态生成，编辑器中不会显示完整的运行时按钮树。

### 2. 街区探索：exploration.tscn

确认出发通过 `state.depart()` 后进入 `scenes/game/exploration.tscn`。这是 Home 加载的独立子场景，使用同一个游戏状态，避免切场景丢失背包、租金与倒计时。

```text
Exploration (Control，exploration.gd)
├─ Background                    全页背景
├─ Location                      街区名 / 建筑与楼层
├─ Departure                     出发站与车电
├─ Timer                         探索剩余秒数
├─ StreetFrame                   裁切地表视窗，默认 777×524
│  └─ SurfaceBlock               surface_block.gd：绘制与交互
├─ Minimap                       surface_minimap.gd
├─ InteractionPrompt             E 互动 / 手电提示
├─ PackAnchor                    背包、装备、电池槽的布局锚点
└─ Status                        底部操作结果与错误提示
```

`exploration.gd.configure(home)` 连接拾取、撤离、拆车和移动信号。背包与装备内容由 Home 生成在 `PackAnchor` 下，修改背包不会重建街区，因而人物位置会保留。

调整页面布局：直接打开 `exploration.tscn`，调整上述 Control 的位置和尺寸。背包内部的格子尺寸与按钮位置在 `home.gd → update_surface_pack()`；区域、建筑、巷口、物品点、移动速度在 `surface_block.gd` 的 `BUILDINGS / JUNCTIONS / LOOT / SPEED` 等常量中；小地图布局在 `surface_minimap.gd`。该场景由 Home 注入真实状态，完整试玩请从主菜单或 Home 运行。

邮电新村、四平路、同济大学使用此街区场景；其余站点继续使用原有简化搜刮页面，未将其伪装为完整街区。

## 分层车厢与视角拖拽

```text
Home 动态页面
└─ HomeBackdrop (home_backdrop.tscn / home_backdrop.gd)
   ├─ Background                BG_Afternoon.png，位于后层
   └─ Carriage                  前层，整体跟随拖拽
      ├─ Texture                Carriage.png
      └─ Hotspots               柜子、车门、交易、电脑、床的点击区与标签
```

新的 `Carriage.aseprite` 已将完全透明边缘裁掉，从 256×256 变为 **243×108**，保留所有图层与像素。裁剪移除了左 7、上 106、右 6、下 42 像素。游戏中车厢按 4 倍显示（972×432），默认位于 `(154,144)`，可见内容中心为 `(640,360)`。背景保持原始 256×256。

按住鼠标左键拖拽空白场景或车厢热点，移动超过 6 个逻辑像素后进入拖拽；轻点仍执行原交互，拖拽结束不会误开柜子或电脑。HUD 的按钮与设置不跟随场景移动。

`home_backdrop.tscn` 根节点可调：

- `drag_sensitivity`：默认 0.35，控制拖拽幅度。
- `max_offset_ratio`：默认 0.2，硬上限 0.2；车厢中心在横、纵方向均不超过视口对应尺寸的 20%。1280×720 下为左右 256、上下 144 像素。
- `background_parallax`：默认 0.25，背景只移动车厢偏移的四分之一。

车厢、家具点击区和标签共享同一父节点。`home.gd` 的 `HOTSPOTS` 仍使用原 256×256 源图的家具坐标，构建时用 `原坐标×4 + (126,-280)` 对齐裁剪后的图；源图裁剪偏移已计入纹理位置，因此不需要手工重画热点。不同页面重建时视角回中。

## 美术修改与导出

源文件在 `assets/source/`，使用 `.gdignore` 避免自动导入 Blender、Aseprite 等编辑文件。运行时使用 `assets/textures/` 的 PNG。

```sh
# 需要 Python 3 + Pillow；导出这两张素材的第一个帧，保留透明度。
python3 tools/export_home_art.py
# 如将来又添加了透明边缘，可对单帧 RGBA 文件原生裁剪；像素验证通过才覆盖。
python3 tools/trim_aseprite.py Demo/assets/source/Carriage.aseprite
```

工具保留当前素材的普通图层叠加。遇到动画、分组、非普通混合、切片等不支持的结构会明确失败；复杂素材请使用 Aseprite 的官方导出／裁剪功能。

## 存档与验证

- 三栏位：`user://saves/slot_1.json` 至 `slot_3.json`，创建时命名基地，已有栏位不会被创建操作覆盖。
- 原单存档存在时保留兼容读取入口；缺少名字时显示“未命名基地”。
- 床铺结算并保存，返回菜单不额外推进日期，也不自动保存。
- 设置独立位于 `user://settings.cfg`。

```sh
python3 test/tools/run_tests.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
```

该入口执行导入、菜单与状态回归、Home 冒烟及集成检查；结果保存在根目录 `test/results/`。详见 [测试说明](../test/README.md)。
