# Metro 游戏测试器

测试器是 **Qt Widgets 原生独立程序**，不打开浏览器，也不使用 WebEngine。它与内容编辑器分别运行，项目中默认启用“Metro 游戏测试器”插件。

## 启动与双向路径

- Godot：右侧“Metro测试器 → 打开独立测试器”，也可用“项目 → 工具 → Metro 游戏测试器”。自动查找项目虚拟环境，登记实际 Godot 可执行文件。
- Windows 文件管理器：双击本目录 `启动测试器.cmd`。
- macOS/Linux：运行 `./tools/tester/启动测试器.sh`。
- 命令行：`python tools/tester/desktop.py --project /path/to/Game`。

与编辑器共用 `.venv-editor` 时无需重复安装 Qt。单独安装可运行：

```sh
python -m pip install -r tools/tester/requirements.txt
```

同一项目只保留一个测试窗口，再次启动激活已有窗口。先打开 Godot 或先打开测试器均可自动关联。本机记录分别保存在 `Game/content/tester-settings.local.json`、`tools/tester/.projects.local.json` 和 `Game/.godot/metro_tester_connection.json`，不提交版本库。打包后反向记录存入用户本地数据目录 `MetroTester/projects.json`。

## 使用

1. 点击“启动测试游戏”，在游戏内创建/读取测试基地；也可以先运行现有游戏，再启动测试器自动连接。
2. 在运行实例下拉框选择游戏；程序列出状态、探索、怪物和 Home 脚本中的数值/布尔属性，支持名称筛选。双击值，输入数字或 `true/false`，回车提交。
3. 可用“指定路径”修改未列出的深层数值，例如 `state.account`、`state.health`、`exploration.player_x`、`monsters.0.x`、`home.pointer_position.x`。仅修改已存在的数值/布尔属性，不执行表达式或脚本。
4. 选择物品、数量及 `bag`（背包）/`locker`（柜子），点“生成物品”。按当前不规则占位寻找空间，整批放不下则全部撤销；电脑继续遵守唯一实例规则。
5. “保存到测试存档”只写入当前隔离测试档。实际路径在执行结果中显示；探索中不能保存时按游戏原有规则返回错误。

## 存档与连接边界

“启动测试游戏”使用 `.godot/metro-tester/saves/<运行实例>/` 目录。若连接的是已加载正式存档的游戏，首次修改前先复制当前状态到该测试目录，再切换后续保存路径，正式原文件不改动。修改可能打破游戏数值规则，因此不会自动写回正式存档。

运行桥仅在 Godot **debug 构建**启用；普通启动且无测试器时不执行命令。通信仅限 `127.0.0.1`，校验当前项目及本机会话令牌。指令按运行实例隔离，在 Godot 主线程执行，并对重复投递的成功指令去重；多个游戏同时启动时不会串改。

窗口启动日志：`.godot/metro-tester/desktop-error.log`；从测试器启动游戏的日志：`.godot/metro-tester/game.log`。没有连接时先确认插件启用、游戏已运行、项目路径一致；修改具体值后若游戏逻辑立即重设该值，界面会显示游戏的最新值。

Windows EXE 构建方式见 [打包说明](../build/README.md)。
