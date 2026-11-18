# Godot 内容接口与数据约定

启动 `python tools/editors/server.py`，在“总设置 / Godot”填写可执行文件路径并测试连接。支持直接打开 Game 工程、运行游戏、启动选定站点的 Godot 预览。预览使用独立的 `user://content_preview/session_<timestamp>.json`，不会读取或写入玩家存档。地图网页预览无需安装 Godot。

网页和 Godot 使用同一份 `Game/content/` JSON。GET `/api/project` 返回目录及本次服务的 token；写入请求携带 `X-Editor-Token`。服务只监听回环地址。POST `/api/customer` 保存角色；POST `/api/level` 保存地图并生成注册场景；POST `/api/settings` 保存本机 Godot 路径；POST `/api/godot` 的 action 支持 probe/editor/game/preview（preview 另带 station）。本机设置文件已加入 gitignore。

## NPC、关系与事件

角色稳定 ID 保留，新增角色追加，不改变已有存档的索引。`faction` 为 red/yellow/blue/none；`trade_enabled:false` 可创建仅在探索出现的 NPC。地图 NPC 引用这些角色的 ID，贴图、名称及对话均来自客户/NPC编辑区。

每位顾客每日最多进入交易窗口一次，跨站共享此限制；实际到访人数为站点上限和当日可用角色数的较小值。送客仍消耗此次到访。睡觉进入下一天后重置到访记录，关系与事件不重置。探索中同一个 NPC 可以再次交谈，但同一故事在同次会面内完成后不会重复执行。

每段剧情是一场见面中的节点图；折线实箭头连接节点。上方跨日事件线以故事为单位，用太阳/月亮、虚线箭头和 ♥/◆ 标识持续影响；选择事件框可进入该次对话。通过“前置 NPC / 前置事件 / 间隔天数”关联跨日故事，0天允许当天后续，1天表示至少下一天。剧情可选择交易、探索或两者均可。默认只完成一次，取消后可在后续会面重复。

```json
{
  "id":"followup", "contexts":["exploration"], "once":true,
  "after":[{"npc":"scavenger","story":"first_meeting","days":1}],
  "conditions":{"affection_min":10,"trust_min":5},
  "start":"greeting",
  "nodes":{"greeting":{"text":"又见面了。","effects":{"affection":2,"trust":1}}}
}
```

好感度属于 NPC，信任度属于其阵营，取值 -100～100，初始0；无阵营不累加信任。节点和分支均可设置变化值。条件支持 affection_min/max、trust_min/max（当前角色）、events_all:["npc/story"]，并兼容原有资金、日期、物品及标记条件。分支条件 JSON 与节点图独立保留。

存档15版记录关系、事件完成日期、当前对话、当日来访角色及效果执行凭据。重复进入节点、保存再读档不会重复累加效果。兼容旧版存档；14版及以前未保留已离场顾客身份，迁移时可恢复仍在订单中的角色，后续新到访完整记录。

## 地图

支持1～8条街道，每条1～8格；增加列扩展横向街道，增加行自动添加连接巷口。每格内可放置建筑、入口、巷口、物资、汽车和室外 NPC。建筑保留1～2层规则。开关“栅格吸附”控制拖动时是否按设置的世界像素步长对齐，建筑可横向及跨街道拖动，其内部物资随之移动。

NPC 位置格式：`{"npc":"scavenger","row":2,"x":330}`。NPC 对话在角色编辑器中编排，地图仅决定出现位置；同一关卡不能重复放置相同NPC。地图预览、游戏大地图和小地图读取相同拓扑。

## 目录核对

本次工作开始时 `Demo/` 已不存在，完整游戏工程已在 `Game/`。旧原型场景、源码、家具及顾客素材均已保存在 Game 中，没有额外删除可用内容。工具位于 tools，测试及运行结果位于独立的 test。
