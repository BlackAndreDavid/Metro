# 工程结构与调整指南

## 文件结构

```text
Metro/
├─ Demo/
│  ├─ project.godot
│  ├─ scenes/
│  │  ├─ ui/     main_menu.tscn、save_select.tscn、settings_panel.tscn
│  │  ├─ items/ highlightable_item.tscn、furniture.tscn
│  │  ├─ construction/construction_mode.tscn  独立建造界面
│  │  └─ game/   home.tscn、home_backdrop.tscn、exploration_setup.tscn、exploration.tscn、main.tscn
│  ├─ resources/furniture/         床、电脑、门、柜子、屏幕的数据与裁剪偏移
│  ├─ scripts/
│  │  ├─ home.gd                    游戏状态与页面调度
│  │  ├─ exploration.gd             地表场景和主控制器的连接
│  │  ├─ items/furniture_catalog.gd  家具目录、占用空间、四个栏杆挂点
│  │  ├─ core/game_session.gd        三栏位存档选择
│  │  ├─ ui/                        菜单、设置、车厢视角、探索整备
│  │  ├─ items/                     通用 MetroFurniture 类、高亮与功能定义
│  │  ├─ construction/              ConstructionMode 类与统一建造操作
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
│  │  ├─ textures/                  Carriage.png、BG_Afternoon.png、Bed.png、LapTop.png、Door.png、Locker.png、Screen.png
│  │  ├─ source/                    Carriage.aseprite、BG_Afternoon.aseprite 等编辑源文件
│  │  ├─ shaders/                   地表照明着色器
│  │  └─ icons/
│  └─ addons/godot_ai/               第三方插件，保持内部布局
├─ tools/                           美术导出、原生 Aseprite 透明画布裁剪工具
└─ test/
   ├─ cases/                        状态、菜单、车厢冒烟、Home 与建造集成测试
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

## 分层车厢、家具和视角拖拽

```text
Home 动态页面
├─ 固定顶部工具栏（按钮底边 ≤ 144，不遮挡居中车厢）
└─ HomeBackdrop (home_backdrop.tscn / home_backdrop.gd)
   ├─ Background                BG_Afternoon.png，后层视差
   └─ Carriage                  整列车的变换父节点
      ├─ Texture                第一节空车厢
      ├─ Fixtures               固定交易窗，也使用共用高亮组件
      ├─ Carriage2 / Carriage3   扩建时复用同一空车厢贴图
      └─ FurnitureSlots
         ├─ SlotN               建造模式中的地面槽位／挂点
         ├─ Bed                 独立床素材 + 睡觉行为
         ├─ Computer            独立电脑素材 + 使用电脑行为
         ├─ Door                独立门素材 + 出站探索行为
         ├─ Locker              独立柜子素材 + 整理物品行为
         └─ Screen              独立屏幕素材 + 站点信息／线路图
```

每节车厢包含 **6 个地面槽位、4 个专用栏杆挂点**。新档自带收纳中的床与电脑，门、柜子、屏幕则已按原位置安装。

顶部原有“柜子／交易／出站探索”重复按钮已删除，直接点击对应素材执行功能。顶部只保留“建造模式”入口。进入后直接点击家具选中，再用共用工具栏移动、拆除、取用仓库或扩建；没有逐件家具的摆放按钮，也没有第二层“家具布置”开关。正常模式不显示目标槽位。

建造模式的统一操作：

1. 点击车厢中的家具选中；此时只选中，不触发原功能，也不立即收纳。
2. 点击“移动”显示兼容目标位置，再点击目标提交。移动前保留原布局；“取消选择”或退出不会改变尚未提交的位置。
3. 点击“拆除”后家具进入统一仓库，可从仓库列表重新取出。拆除不是永久销毁，也不返还扩建材料。
4. 对原本未安装的床、电脑，打开“家具仓库”，在单个 ItemList 中选中条目，再用共用的“放置选中”操作放置；不生成每件家具单独的按钮。
5. 工具栏有明确的“退出建造模式”按钮，退出后家具恢复正常交互。Esc 优先关闭仓库、取消选择，随后退出。

门仍占两个连续地面槽位，不能跨车厢；柜子占一格。屏幕只能选择四个栏杆挂点，其他家具不能占挂点。移动目标直接复用状态层校验，只显示类型、空间、占用都合法的位置。被移动家具以半透明预览并穿透点击，选中的家具保持白色轮廓。挂点控制位于家具前面，避免门拦截点击。

### 独立模块与家具类

```text
Home
├─ ConstructionMode (持久子场景，独立控制器)
│  ├─ Toolbar：选择信息 / 家具仓库 / 移动 / 拆除 / 取消 / 扩建 / 退出
│  └─ Warehouse：统一家具列表 / 放置选中 / 返回建造
└─ 动态 HomeBackdrop
   └─ MetroFurniture 实例：床、电脑、门、柜子、屏幕
```

- `scripts/construction/construction_mode.gd` 定义 `ConstructionMode` 类，配套 `scenes/construction/construction_mode.tscn`。负责进入退出、选择、移动预览、提交、拆除、仓库和 Esc 操作。
- `scripts/items/furniture.gd` 定义 `MetroFurniture` 类，继承通用高亮物品类。正常模式执行资源定义的功能；建造模式发出 `selection_requested(id)`，不再把点击等同于拆除。
- 所有家具由模块的 `register_furniture()` 注册，不按具体家具生成按钮或分支控制。
- `home.gd` 只负责模块生命周期、页面刷新和扩建请求连接；旧的 `build_mode / placement_mode / selected_furniture` 状态和逐件摆放函数已移除。
- `cabin_state.gd → furniture_placement_problem()` 是可复用的无副作用校验，预览与最终 `place_furniture()` 共用它。门的两格、屏幕挂点、跨车厢限制和占用检查保持一致。
- 模块用 ID 保留选择，场景刷新时重新注册家具实例，避免引用已经释放的节点。切到正常游戏页面会自动退出建造；扩建页面返回则保留建造模式。

屏幕的第一个挂点保持原位置。另三个挂点依据原栏杆像素校准：四个挂钩横坐标分别是源图的 `42 / 101 / 144 / 218`，末端纵坐标是 `22 / 22 / 20 / 21`；屏幕在挂钩下居中。可在 `items/furniture_catalog.gd → HANGING_ORIGINS` 修改位置。每增加一节车厢，获得独立的四个挂点。

**可复用高亮与家具封装：**

- `scenes/items/highlightable_item.tscn` + `scripts/items/highlightable_item.gd` 提供统一纹理透明度命中检测、悬停功能文字与描边材质。透明画布不会成为点击区。
- `assets/shaders/item_outline.gdshader` 使用周围 8 个方向的 alpha 膨胀生成白色轮廓，纹理自动加两像素透明边距，防止外轮廓被截掉。每个物品独享材质，悬停不会同时点亮其他物品。
- 后续物品可直接实例化通用场景，调用 `set_item(texture, 功能文案, home_backdrop)`，连接 `activated` 信号；无须复制描边算法。非车厢物品可省略第三个参数，不会绑定视角拖拽。
- `furniture.tscn` 继承该通用场景，`MetroFurniture` 根据当前模式决定请求选中还是调用家具功能。移动和拆除由统一建造控制器处理。
- `resources/furniture/*.tres` 定义名称、素材路径、功能文案、动作、占用格数、摆放类型和裁剪偏移；`furniture_definition.gd.perform(home)` 分别连接休息、电脑、出站整备、柜子、站点地图流程。屏幕上常驻的站点／日期／天气属于内容展示，不是悬停提示。
- 素材使用延迟加载，保存与布局校验无需提前读取 PNG，首次导入项目也不依赖纹理缓存。
- `highlightable_item.gd` 的 `Function` 是唯一悬停功能说明。旧版同一节点另设了 `tooltip_text`，造成 Godot 默认提示框和功能文字同时出现；该字段已清空。原来叠在车厢上的隐形柜子、门、交易 Tooltip 热点已移除，交易窗也复用同一组件。背包、价格按钮等没有高亮说明的 UI 仍可保留各自的明细提示。

**裁剪与对齐：**

- `Carriage.aseprite` 仍为 243×108，新版已移除床、电脑、门、柜子和屏幕，不会与独立家具重复绘制。
- `Bed.aseprite` 从 243×108 裁为 **62×10**，移除的原点为 `(175,79)`。
- `LapTop.aseprite` 从 243×108 裁为 **23×18**，移除的原点为 `(151,70)`。
- `Door.aseprite` 从 243×108 裁为 **63×78**，原点 `(59,17)`；柜子 `Locker.aseprite` 为 **25×76**，原点 `(2,22)`；屏幕 `Screen.aseprite` 为 **28×20**，原点 `(28,22)`。
- 裁剪偏移保存在家具 `.tres` 的 `source_origin`，槽位位置由 `slot_rect()` 使用该偏移建立。描边的透明边距也计入位置补偿。初始槽位内的素材仍对齐原来的车厢位置；裁剪不改变有效像素与图层。

**拖拽与多车厢回正：**

按住左键拖拽场景或家具，超过 6 个逻辑像素才进入拖拽；短按仍执行交互，拖拽不会误开家具功能。松开后以 `return_speed`（默认 160 逻辑像素/秒）匀速回正，而不是逐渐减速的插值。

只有一节时回到该节中心；多节时在松开的一刻，比较每节车厢中心到视口中心的距离，选择最近的一节为目标。距离相等时保持原车厢，避免来回跳动。回正过程中重新按住可立即接管视角；刷新家具或打开页面返回时保留当前节数，重新载入游戏则从第一节开始。刚扩建或将家具移入其他车厢时会聚焦目标车厢。

`home_backdrop.tscn` 根节点可调参数：

- `drag_sensitivity`：默认 0.35。
- `return_speed`：默认 160，控制匀速回正速度。
- `max_offset_ratio`：默认 0.2，硬上限 0.2，限制相对当前车厢焦点的手动拖拽范围。
- `background_parallax`：默认 0.25。

多车厢会缩小显示比例，让相邻车厢中心间的中点位于允许拖拽范围内，从而能通过轻拖切换焦点；车厢、家具、空槽和热点共享缩放与位置变换。

## 扩建、耗电与存档

“建造模式 → 扩建车厢”显示完整材料需求、当前持有量和扩建前后耗电，确认后才扣料。

| 项目 | 默认规则 |
| --- | --- |
| 每次扩建材料 | 钢板×2、螺丝×4、工具×1，柜子与背包合并计算 |
| 车厢数量 | 初始 1 节，最多 3 节 |
| 空间 | 每新增一节增加 6 个地面槽位、4 个栏杆挂点 |
| 行车与跨站接应 | 初始 30 度/站，每新增一节 +10 度/站 |
| 每日结算 | 基础 2 度，每新增一节 +2 度 |

这些默认值集中在 `cabin_state.gd` 的 `MAX_CARRIAGES / EXPANSION_COST / EXTRA_TRAVEL_COST / EXTRA_DAILY_COST`，方便调整。每日基础耗电保留原规则，不随电脑是否收纳而免除。所有路线报价、实际行车、找充电站、跨站接应及休息结算统一调用状态方法，避免显示和实际扣电不一致。

材料不足、超过数量上限、外出中或游戏结束时均不能扩建；先验证整份配方再扣料，失败不会部分扣除。

存档升级为版本 5，保存 `carriage_count`、五类家具的 `furniture_layout`，仍兼容版本 1–4。版本 4 的床、电脑按旧的每节两槽编号迁移到新的每节十位编号，保留原车厢和原摆放位置；新增门、柜子和屏幕恢复在第一节原位置，屏幕挂在第一个挂点。更早存档恢复原始床和电脑布局。读取时校验家具种类、车厢数量、格位类型、门的两格占用、边界与重叠，非法布局不会部分污染当前状态。布置与扩建仍通过床铺睡觉保存，返回菜单不会自动保存。

## 美术修改与导出

源文件在 `assets/source/`，使用 `.gdignore` 避免自动导入 Blender、Aseprite 等编辑文件。运行时使用 `assets/textures/` 的 PNG。

```sh
# 需要 Python 3 + Pillow；导出七张素材的第一个帧，保留透明度。
python3 tools/export_home_art.py
# 如将来又添加了透明边缘，可对单帧 RGBA 文件原生裁剪；像素验证通过才覆盖。
python3 tools/trim_aseprite.py Demo/assets/source/Carriage.aseprite
```

可同样用裁剪工具处理 Bed、LapTop、Door、Locker、Screen 等 Aseprite 文件。源图裁剪偏移变化时，需要同步 `.tres` 的 source_origin。

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
