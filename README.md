# 终末地铁

一款以末日上海地铁为背景的 Godot 游戏原型。玩家以车厢为据点，用电力支付车费、采购物资和租用防护服，在各站之间跑商，也可以出站探索。

## 运行

用 Godot 4.7.2 打开 [Demo/project.godot](Demo/project.godot)，按 **F5** 进入主菜单，再选择存档或创建基地。新游戏从邮电新村开始。

- 点击车厢里的窗、床、柜子和电脑，可交易、存档、整理物品、查看新闻及线路图。
- 各站有不同的供货、收购范围和当日报价，出发前可在线路图上查询。
- 选中或拖拽物品时，用鼠标滚轮或 **R** 旋转。

车厢的 Aseprite 源图在 [Demo/assets/source/Carriage.aseprite](Demo/assets/source/Carriage.aseprite)。更多玩法和编辑说明见 [Demo/README.md](Demo/README.md)。

中心城区线路示意参考申通地铁 D202501 版，设施、辐射和物价采用游戏设定。[上海轨道交通网络示意图](https://www.shanghai.gov.cn/shanghai/newshanghai/shgl2025.pdf)

工程目录、场景流转和模块职责见 [架构说明](Demo/ARCHITECTURE.md)。

测试独立位于根目录 [test/](test/README.md)，统一运行命令：`python3 test/tools/run_tests.py --godot <Godot可执行文件>`。

车厢主场景为 `Demo/scenes/game/home.tscn`；背景与车厢独立分层。电脑与探索界面的调整位置见 [结构与调整指南](Demo/ARCHITECTURE.md)。

床与电脑已拆为独立家具，可在空槽摆放和收纳，悬停显示白色轮廓与功能。扩建车厢会增加行车及每日耗电；松开拖拽后，视角匀速回到最近的车厢中心。规则与可调整参数见 [家具与车厢指南](Demo/ARCHITECTURE.md)。

门、柜子和屏幕也已独立，顶部入口统一为“建造模式”。门占两格，屏幕使用四个栏杆挂点；悬停只显示共用高亮组件的一份说明。

建造模式已独立封装：点击家具选中后使用共用移动、拆除操作，仓库统一取放，并提供明确的退出按钮。

建造场景与 Home UI 已分离，鼠标按钮交互按真实输入验证；拖拽范围为视口的 10%，回中速度提高到 320 逻辑像素/秒。
