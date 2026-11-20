# 打包编辑器与测试器

两个工具都提供独立程序窗口。内容编辑器复用 Qt WebEngine 中的完整编辑界面，启动器不会打开外部浏览器；测试器使用 Qt Widgets。

## Windows 一键生成 EXE

在 **Windows** 安装 Python 3.10+，双击 `打包Windows程序.cmd`，或在仓库根目录执行：

```powershell
py -3 -m venv .venv-editor
.\.venv-editor\Scripts\python.exe -m pip install -r tools/build/requirements.txt
.\.venv-editor\Scripts\python.exe tools/build/build_tools.py
```

产物：

- `tools/bin/MetroEditor/MetroEditor.exe`
- `tools/bin/MetroTester/MetroTester.exe`

必须保留各 EXE 同目录的 `_internal` 及其他依赖文件，不能只复制 EXE。不需要将 Python/Qt 安装到使用者机器上。Godot 两个插件和 CMD 启动器会优先使用仓库 `tools/bin` 下对应程序。若程序单独放在仓库之外，首次运行会让用户选择 `Game/project.godot`，后续记录双向路径。

也可在 GitHub 仓库的 Actions 页选择 **Build Windows desktop tools → Run workflow**，下载 `Metro-Windows-Tools` 产物。工作流在 Windows 上构建并实际启动两个 EXE，检查原生窗口、项目连接和退出；超时上限25分钟。产物包含程序目录及 `packaging-smoke.json` 检查结果，不上传本机路径缓存。

## 限制与检查

PyInstaller 必须在目标系统运行；Linux 上生成的是 Linux 程序，不能称为 Windows EXE。本次云端为 Linux，因此源程序与接入流程可以在云端验证，Windows EXE 以 Windows 构建和冒烟检查结果为准。

```sh
python tools/build/build_tools.py --tool tester   # 只打包测试器
python tools/build/build_tools.py --dry-run       # 检查构建指令，不打包
python test/tools/check_packaged_tools.py         # 检查本机已生成产物
```

构建脚本只打包编辑器静态资源白名单，不包含游戏素材、存档、令牌、`.projects.local.json` 或整份仓库。
