# 工程结构与调整指南

## 文件结构

```text
Metro/
├─ Game/
│  ├─ project.godot
│  ├─ scenes/
│  │  ├─ ui/     main_menu.tscn、save_select.tscn、settings_panel.tscn
│  │  ├─ items/ highlightable_item.tscn、furniture.tscn
│  │  ├─ construction/construction_mode.tscn  独立装修界面
│  │  ├─ map/metro_map.tscn        独立线路图与新闻界面
│  │  └─ game/   home.tscn、home_backdrop.tscn、exploration_setup.tscn、exploration.tscn、main.tscn
│  ├─ resources/items/             可收纳物品定义（电脑）
│  ├─ resources/furniture/         床、电脑、门、柜子、屏幕的数据与裁剪偏移
│  ├─ scripts/
│  │  ├─ home.gd                    游戏状态与页面调度
│  │  ├─ exploration.gd             地表场景和主控制器的连接
│  │  ├─ items/furniture_catalog.gd  家具目录、占用空间、四个栏杆挂点
│  │  ├─ core/game_session.gd        三栏位存档选择
│  │  ├─ ui/                        菜单、设置、车厢视角、探索整备
│  │  ├─ items/                     通用 MetroFurniture 类、高亮与功能定义
│  │  ├─ construction/              ConstructionMode 类与统一装修操作
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

该界面由独立的 `scenes/map/metro_map.tscn` / `scripts/map/metro_map.gd` 管理，与 Home、装修场景同级。Home 注入同一个状态对象，地图不继承它们的 UI。进入后隐藏并停用来源场景，返回时恢复来源场景；装修不提供线路图入口。内部页面动态生成，公共样式工具位于 `scripts/ui/ui_builder.gd`。调用关系：

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
| 新闻卡片布局 | `map/metro_map.gd → show_news()`，默认 `(318,173,644,372)` |
| 新闻文字与天气规则 | `cabin_state.gd → news()`、`weather()` |
| 电脑页面左右分栏 | `map/metro_map.gd → show_map()`；左 `(40,89,865,585)`，右 `(923,89,317,585)` |
| 站内供需与报价 UI | `map/metro_map.gd → show_map_market()`、`map_quote_column()` |
| 站点供需数据 | `cabin_markets.gd` |
| 线路、站点坐标和站外说明 | `cabin_map.gd` |
| 选择目的地、切换标签、出发 | `map/metro_map.gd → select_station()`、`set_map_tab()`、`travel()` |

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
      ├─ FurnitureGrid             装修时的地面网格
      ├─ FurnitureSlots            床、电脑、门、柜子实例
      ├─ FloorPreview              地面放置预览
      └─ HangingFixtures           前景独立挂点网格、屏幕与放置预览
```

每节车厢使用 **35×12 地面格**，并有 **4 个独立 4×3 挂点**。挂点不占地面格，显示和鼠标命中都在地面家具前方。网格参数、默认位置和挂点原点集中在 `items/furniture_catalog.gd`，家具资源的 `grid_size` 定义占用：

| 家具 | 占格 | 平面 |
| --- | --- | --- |
| 电脑 | 3×2 | 地面 |
| 柜子 | 3×12 | 地面 |
| 门 | 8×12 | 地面 |
| 床 | 8×2 | 地面 |
| 屏幕 | 4×3 | 挂点（每点最大 4×3） |

`CELL_SIZE` 为 约 27.31×27.31 逻辑像素（固定正方形），网格从内壁 `(162,196)` 开始，宽956、高约327.77像素，覆盖天花板下沿至地板上沿的内部空间（底部不足0.25像素的余量）；除电脑保留比例并居中外，素材的显示尺寸与占用矩形一致，正式家具和拖动预览采用相同布局。已有素材已裁剪，描边的两像素边距单独补偿。网格替代旧槽位后，旧存档保留家具所在车厢、收纳状态和屏幕挂点，在对应车厢按新网格默认坐标重新安放。

新档自带收纳中的床与电脑，门、柜子、屏幕已安装。正常模式隐藏网格，点击素材执行功能；顶部重复的“柜子／探索”等按钮已移除。

### 独立装修场景与长按拖动

```text
Root
├─ Home                         装修期间隐藏并停用
├─ ConstructionMode
│  ├─ World/HomeBackdrop        独立创建车厢视图
│  ├─ Toolbar                   选择信息、仓库、拆除、扩建、退出
│  ├─ Warehouse                 统一家具列表
│  ├─ Expansion                 材料、耗电和扩建确认
│  └─ HoldProgress              鼠标右上方蓄力圈（不拦截输入）
└─ MetroMap                     从 Home进入的同级地图场景
```

点击家具只选中，可用统一“拆除”按钮收纳。**按住左键 1 秒后拖动**，松开在有效目标格提交；不足 1 秒移动超过 8 像素会取消蓄力。拖动显示绿／红占格预览，越界、重叠或类型不匹配时保留原位置。Esc 可取消。已删除“移动”和“取消选中”按钮；未摆放的家具从仓库取出后点击有效格放置。

`ConstructionMode` 统一处理所有家具的注册、选择、手势、预览和提交，`MetroFurniture` 只把装修输入转交它。`cabin_state.gd → furniture_placement_problem()` 校验网格、类型、车厢、占格与重叠，预览和提交共用此方法。Home 与装修只共享状态和车厢焦点，装修时不显示或处理 Home UI。

### 可收纳物品与电脑朝向

`MetroItem`（`scripts/items/item_definition.gd`）是可复用 Resource 类，定义 ID、名称、储物尺寸、贴图与对应家具 ID；`resources/items/computer.tres` 将电脑注册为 2×2 物品。储物条目的 `rotated` 独立保存，使用现有 R 键／滚轮旋转及网格拖放，图标同步旋转。

电脑摆放时从柜子或背包消耗一个物品条目，生成底面朝下的家具，不继承储物旋转。移动现有电脑不消耗物品。拆除电脑时归还一个未旋转的电脑物品；柜子和背包都放不下时拒绝拆除并保留原家具。仓库只显示实际持有的电脑，不会凭空复制。其余家具仍使用家具仓库收纳。

### 高亮、素材与视角

通用 `highlightable_item.tscn` / `highlightable_item.gd` 提供透明像素命中、白色描边和唯一功能提示。`item_outline.gdshader` 对周围八方向做 alpha 膨胀，纹理增加两像素边距避免裁断；`tooltip_text` 留空，避免重复说明框。

裁剪源文件在 `assets/source/`，运行图在 `assets/textures/`：车厢243×108、床62×10、电脑23×18、门63×78、柜子25×76、屏幕28×20。资源 `source_origin` 记录旧画布裁剪偏移，新布局由网格决定位置。

普通模式按住左键轻拖视角，短按执行家具功能。拖动偏移硬上限为视口的 **10%**，松开以 **320 逻辑像素／秒**匀速回正；多车厢返回松手时最接近视口中心的车厢。多车厢视图缩放，让 10% 范围可越过相邻车厢中点。装修蓄力和家具拖动期间锁定视角，避免手势冲突。

### 扩建与存档

装修扩建最多至3节；每次消耗钢板×2、螺丝×4、工具×1，每节新增35×12地面格和4个挂点。行车基础30度／站，每新增一节+10；每日基础2度，每新增一节+2。材料不足、外出或游戏结束时不可扩建，失败不扣料。

存档版本 **14** 保存家具 `{car,x,y}`（挂点另有 `mount`）、独立储物物品与朝向。兼容版本1–13；旧槽位迁移到新格位，保留原车厢及收纳状态。读取前完整校验位置、尺寸、重叠、挂点和电脑数量，非法布局不部分覆盖当前状态。旧档收纳中的电脑补入储物格，空间全满则恢复默认摆放以保留物品。布置、扩建通过床铺休息保存，返回菜单不自动保存。

## 美术修改与导出

源文件在 `assets/source/`，使用 `.gdignore` 避免自动导入 Blender、Aseprite 等编辑文件。运行时使用 `assets/textures/` 的 PNG。

```sh
# 需要 Python 3 + Pillow；导出七张素材的第一个帧，保留透明度。
python3 tools/export_home_art.py
# 如将来又添加了透明边缘，可对单帧 RGBA 文件原生裁剪；像素验证通过才覆盖。
python3 tools/trim_aseprite.py Game/assets/source/Carriage.aseprite
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

## 建造按钮失效的原因与修复

原来的建造节点是 Home 的早期子节点，通过 `z_index=200` 画在后创建的 Home 页面之上。但 Godot 的 GUI 命中顺序由控件树／输入过滤决定，绘制用的 z_index 并不会让它优先接收鼠标。实际复现中，点“家具仓库”按钮的两次鼠标事件都进入了后创建的 HomeBackdrop，按钮没有收到事件，仓库仍然关闭。

修复后 Home 隐藏且停止处理输入；独立装修场景中 World 始终在控件树前面，Toolbar、Warehouse、Expansion 在它后面，刷新只重建 World 的内容。因此背景不会再盖住按钮的 GUI 命中，也不再靠 z_index 掩盖输入层级问题。回归测试使用视口的真实鼠标按下／松开操作验证移动、拆除、仓库、放置、扩建、返回和退出，而非只直接发射 `pressed` 信号。

版本6、7、8的旧网格存档按原像素底边与横坐标迁移到新网格。门、柜子优先安放，高度固定占12格；受扩大的占格影响产生冲突时，其他家具在原车厢就近寻找空位，收纳状态与挂点保持不变。

屏幕始终显示站名、日期、天气三行。此前代码在素材控件高度小于72像素时只显示站名，导致2×2屏幕隐藏日期与天气；现已移除该条件，4×3屏幕固定显示完整内容。挂点扩大时按新宽度的一半重新对齐，保持屏幕挂在栏杆挂钩下方正中。

设置按钮是 `scenes/game/home.tscn` 的直接子节点 `SettingsButton`，信号连接 Home 的 `show_settings()`。此前它先创建，后创建的全屏页面抢走鼠标事件，较高的 z_index 只改变绘制顺序。现在 `begin_page()` 把动态页面插在设置按钮之前，使绘制和 GUI 命中顺序一致；不再依赖 z_index。回归使用真实鼠标点击检查车厢、储物、页面刷新与探索中的打开和关闭。

## 本次界面与美术工具

- 电脑的**家具占格3×2**，储物物品仍为2×2，两个用途独立。`fill_grid=false` 配合 `FurnitureCatalog.visual_rect()` 保持电脑原图比例，在占格中央显示；装修预览复用相同算法。
- “装修”移除了线路图按钮及控制器入口。屏幕的 `action=none`，仅提供当天信息悬浮提示和常驻站名/日期/天气，不再用点击或键盘打开线路图；正常模式仍可经过屏幕轻拖视角。电脑是线路图入口。
- 交易页面为独立 `scenes/commerce/trade.tscn`，其 `Panel/CustomerWindow` 实例化 `customer_window.tscn`；顾客和新增窗口仅存在于交易页面。HomeBackdrop 保持原车厢窗口素材和原交易热点，Home 不显示顾客。`customer_window.gd` 从左入场，在中央等待订单完成，再向右退场；不再定时循环换客。窗口只显示独立全身素材的上半身。
- 四位客户分别保存在 `assets/textures/customers/{scavenger,mechanic,commuter,medic}.png`。`customer_catalog.gd` 注册目录；增加角色只添加独立 PNG 和目录记录。原图与生成筛选记录在 `assets/source/customers/`，不会把未选候选提交进仓库。
- 美术工具为根目录 `tools/art_asset_tool.py`，预设与说明位于 [tools/art/README.md](../tools/art/README.md)。支持描述、2–3候选、选择、区域中位数、像素块多数色及动画帧条；当前四位客户通过聊天文生图生成，再经工具精简为48×80、18种可见颜色以内的透明图片。
- 详细探索结构、事件流、数据与修改入口见 [探索模块详细架构](EXPLORATION_ARCHITECTURE.md)。

版本10的电脑占格由2×2迁移到3×2，保留原车厢、储物状态和挂点，冲突时同车厢就近安放。

## 交易场景与 Home 的边界

`Home.show_trade()` 只负责加载 `scenes/commerce/trade.tscn` 并转发地图查询和关闭操作。`scripts/commerce/trade.gd` 管理商品拖拽、待确认清单和结果文本，`customer_orders.gd` 管理订单、预算、名额与原子结算。交易窗口、客户形象与进退动画属于该交易场景，不挂在 HomeBackdrop 上。

```text
Home
├─ SettingsButton
└─ Trade（交易时加载；返回 Home 后销毁）
   ├─ Background
   └─ Panel
      ├─ CustomerWindow        顾客进退动画
      ├─ Bag / Stock           玩家背包与顾客商品拖拽卡片
      ├─ Basket / Confirm       待确认清单及确认交易按钮
      ├─ Order / Quote          类别需求、预算、每日人数和报价
      ├─ Account / Status      余额与操作结果
      └─ Map / Close           查报价、返回 Home
```

拖入或移除商品时只刷新卡片和清单，保留当前客户。确认交易成功才进入退场动画，退场结束才创建下一张订单。关闭交易后整个 Trade 子场景释放，Home 恢复原窗口，不残留顾客节点。新增窗口及顾客视觉不更换 Home 的车厢窗户贴图。

## 每日顾客订单与预算

- 交易窗口从280×320增至448×360逻辑像素，`CustomerWindow/Customer` 使用 AtlasTexture 从48×80独立原图裁取上方48×44区域，不修改源素材。入场由左侧移到中央，订单未完成时一直等待，完成后向右离开。
- 每位顾客一张订单，以顾客为方向：`buy`＝顾客从玩家购买，`sell`＝顾客向玩家出售。订单只指定生活补给、电力用品、工业材料或文书旧物类别，允许同类不同商品组合，至少选择一件。
- 用原生鼠标拖放把 Bag/Stock 卡片放入 Basket；不会立即扣款或移动库存。“移除”可撤回选择，“确认交易”再次校验类别、唯一物品ID、顾客库存、背包空间与预算，全部成功后一次性结算。
- 顾客购买时预算减少、玩家收入先还欠费；总价超过顾客预算显示“买不起”，确认按钮禁用，库存和余额不变。顾客出售时预算增加，玩家按原账户/欠费规则付款；若需赊购，确认前明确提示。
- 顾客出售的每种同类商品初始2件。当地已有报价沿用，新增同类商品用 BASE_PRICES、行情倍率及买入折扣定价；电池回收还考虑电量。旧的逐件即时购买/出售按钮已从交易界面移除。
- 初始顾客预算取 content/customers.json 的 base_budget，出现按权重及世界种子、日期、站点与到访序号确定；不会因关闭窗口重抽。站点每日上限：邮电新村4、四平路6、同济大学5；其他站按设施继承3–8位。配置位于 `customer_orders.gd → STATION_LIMITS/GROUP_LIMITS`。
- 到访即占用一个当日名额，未完成订单不会自动跳过。关闭交易或切站后回来，保留同一站点的订单、预算和人数；日结清空各站当日记录。达到上限后窗口空置，显示明日再来。
- 存档版本12保存 `customer_visits`，每站含 arrived/completed/active；读取先校验预算、类别、计数和库存，非法数据不部分覆盖游戏状态。版本1–11读取时建立空的顾客记录。

“送客”将当前未完成订单标记为 dismissed，不结算商品或预算，清空选择并向右离场；单独记录 dismissed 人数，不增加 completed，仍占 arrived 名额。版本13为各站记录增加 dismissed，版本12记录迁移时补零。

## 内容编辑拓展

游戏工程目录由 Demo 更名为 Game，`res://` 内部路径不变。可视化工具代码在 `tools/editors/`，编辑的数据在 `Game/content/`；用法与条件字段见 [编辑工具说明](../tools/editors/README.md)。

- `content/customers.json`：角色名称、独立贴图、基础预算、权重、买卖类别、条件剧情与分支节点。目录追加保存，旧角色以停用代替删除，维持存档索引稳定。
- `scripts/commerce/customer_catalog.gd`：读取客户配置，支持新 PNG 在未导入时直接加载；`customer_orders.gd` 按有效候选权重选择顾客，用定义中的基础预算和类别生成订单。
- `scripts/commerce/customer_dialogue.gd`：条件、优先级、节点、分支和标记；交易层先展示符合条件的对话，规则层也阻止剧情未完成时确认交易。版本14增加 content_flags/dialogue_progress，兼容旧存档。
- `content/registry.json`：站点到地图配置及 tscn 的映射。`content/levels/postal.json` 保存现有邮电街区作为模板，默认三站共用。
- `scripts/content/content_registry.gd`：读取登记和场景路径；Home 按站点加载具体探索场景。SurfaceBlock 的建筑、物资、汽车、站口和街道名称改为实例数据，保留原默认值作兼容；小地图使用当前实例的数据。
- 编辑站点时生成 `scenes/exploration/stations/station_<hash>.tscn`，继承已有探索场景；配置写入 content/levels，注册后即可从对应站点出站。导出预设显式包含 content JSON，避免打包后找不到定义。

“打开编辑器.cmd”仅负责启动 Godot 工程编辑器并记录日志；`tools/editors/启动内容编辑器.cmd` 负责启动专用内容编辑工具，两者不互相替代。
