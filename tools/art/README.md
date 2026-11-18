# 临时美术素材工具

工具代码和风格预设全部位于根目录 `tools/`。运行需要 Python 3、Pillow（`python3 -m pip install -r tools/art/requirements.txt`）。凭据只从环境变量读取，不写入提示词或结果记录。

工作流：

0. `tools/art/style.json` 保存统一像素风提示词、低饱和紫灰／青绿／米黄配色；调整后复用同一个版本，避免逐件改变画风。
1. 根据物品及用途生成描述：

   ```sh
   python3 tools/art_asset_tool.py prepare "旧式电脑" --purpose "车厢家具，正面视角，底面朝下" --output test/results/art/computer_prompt.json
   ```

2. 文生图生成2或3个独立候选。支持 OpenAI 兼容 images/generations 接口；设置 `OPENAI_API_KEY`，可选 `OPENAI_BASE_URL` 和 `ART_IMAGE_MODEL`。以下执行整个流程：

   ```sh
   python3 tools/art_asset_tool.py run "穿工作服的维修工" --purpose "交易窗口客户，全身正面待机" --count 3 --name mechanic --width 48 --height 80 --output test/results/art/mechanic
   ```

   也可以把第1步提示词交给聊天中的文生图工具，再将2–3张候选交给第3步。当前客户就是通过聊天文生图生成3组候选后导入的，无需把任何密钥提交到工程。
3. 评估会记录透明度占比、居中程度、是否贴边和候选哈希。自动分数只评价技术可用性，不能判断角色含义、手部完整性或动作正确性；这些应人工查看后用 `--index` 指定0开始的候选编号。未指定时自动按技术分选择：

   ```sh
   python3 tools/art_asset_tool.py select a.png b.png c.png --index 1 --delete-unselected --name mechanic --width 48 --height 80 --block 1 --output test/results/art/selected
   ```

   `--delete-unselected` 仅删除传入的未选图片，最佳原图保留；生成模式使用临时目录，成功后只留下最佳原图、精简结果、提示词和评估记录。不会把未选方案复制进游戏素材目录。
4. 精简采用连通区域相似色检测，面积达到阈值后按通道中位数重上色；限制调色板；自动估算最小重复像素块（可用 `--block` 明确指定），每块使用**占比最大的颜色**，不取平均色。透明像素参与块投票，保留透明背景。输出使用最近邻缩放，不抗锯齿：

   ```sh
   python3 tools/art_asset_tool.py simplify best.png --name result --width 48 --height 80 --colors 18 --block 1 --output test/results/art/simplified
   ```

## 动画素材

`prepare/run/select/simplify` 都支持 `--frames N`：输入/生成横向等宽帧条，统一角色、相机、灯光、尺寸和落脚点。精简时按所有帧共有包围盒对齐，统一调色板和最小像素块，导出总帧条及逐帧 PNG。需要人工确认动作连续性；不会把生成结果误称为已验证的连续动画。

客户只出现在独立交易场景 `Game/scenes/commerce/trade.tscn` 内，Home 保持原窗户。当前客户使用 Godot 横向位移和颜色插值，从左入场、成交后向右退场；运行时只裁取上半身，不需要烘焙逐帧图。每位角色在 `Game/assets/textures/customers/` 下有独立 PNG；保留原图及候选评估记录在 `Game/assets/source/customers/`。角色注册在 `Game/scripts/commerce/customer_catalog.gd`，增加新角色只需添加独立图片和一条目录记录。

`tools/import_customer_candidates.py` 可将3行×4列的客户候选表拆为每位3张候选，选择一组，保存4张独立原图与4张48×80运行图；临时候选自动删除。当前选择第2组（`--row 1`），因为人物完整、职业轮廓清晰且比例统一。

```sh
python3 tools/import_customer_candidates.py candidates.png --row 1 --output Game/assets/textures/customers --source Game/assets/source/customers --reason "比例统一、全身完整、配色与车厢一致"
```
