# 玩法原型（Godot 4.7）

实现计划见 [../10-prototype-plan.md](../10-prototype-plan.md)，规则依据见 [../07-combat-rules.md](../07-combat-rules.md)。

## 当前进度

- [x] M0 工程骨架
- [x] M1 规则内核（无画面）
- [x] M2 灰盒表现层
- [x] M3 1-4 涅墨亚山谷（待人工通关验证）
- [ ] M4 1-5 双口洞穴
- [ ] M5 试玩与调参

## 运行游戏

规则只有一份实现：Go 引擎（`../engine/`）。游戏启动时会自己拉起 `../engine/bin/srpg.exe play`，通过本机 TCP 一问一答，退出时引擎跟着结束。**第一次运行或改过引擎后先构建它：**

```sh
cd ../engine && ./build.sh      # Windows 也可以双击 build.bat
```

找不到引擎程序时游戏会直接显示原因。环境变量 `SRPG_BIN` 可以指定引擎程序的位置；命令行 `--` 之后的 `--data-dir=<目录>`、`--set=<表>:<键>=<值>` 会原样交给引擎。

用 Godot 4.7 打开 `prototype/` 运行。启动后进入《潘多拉之裔》首页。选择「开始征程」进入**战前编成**：选择战斗（包括 1-5 双口洞穴），并在 4 个技能点内为主角和阿塔兰忒挑选技能。也可以用命令行跳过编成：

```sh
"$GODOT" --path . --resolution 1920x1080 -- --battle=1-4
```

| 操作 | 按键 |
|---|---|
| 选择单位 / 移动 / 确认目标 | 左键 |
| 取消 | 右键、Esc |
| 旋转镜头 | Q / E |
| 缩放 | 滚轮、+ / − |
| 平移 | WASD、方向键、中键拖动 |
| 威胁范围 | T |
| 战术视图（高度数字、去掉装饰） | Tab |
| 像素化后处理开关 | P |
| 撤销移动 | Z |
| 结束回合 | 空格、回车 |
| 重开 | R |
| 全屏 | F11 |

悬停敌人会显示它"如果现在轮到它"的行动意图和威胁范围；瞄准时悬停目标会显示完整预览（伤害、援护、击退落点、坠落、破势）。

### 自动截图

```sh
"$GODOT" --path . --resolution 1920x1080 -- --capture=<输出.png> --demo=<build|move|target|threat|leap|rotate|enemy>
```

## PC 美术切片 · 1-1 焚村撤离

战前编成默认选中 1-1。主角从燃烧的村中出发，火势逐回合向外扩展。第三回合阿塔兰忒从高地入场。让两人各占一个村门出口格，或消灭三波狼群，即可获胜。运行 `-- --battle=1-1 --demo=escape --capture=escape.png` 可观看四回合撤离演示。默认镜头全程保留操作界面。将演示名换为 `escape_far` 可在最远缩放下重放相同的战斗，镜头在第二、第三回合各旋转一次。

建筑、树木和岩石使用 `art/landmarks/` 下的三维模型。运行仓库中的 `python3 art/tools/model_landmarks.py` 可重新生成。

## PC 美术切片 · 1-5 双口洞穴

在战前编成选择 **1-4 涅墨亚山谷** 或 **1-5 双口洞穴**，或以 `-- --battle=1-5` 直接进入。战场按桌面窗口原生分辨率显示。可行走台面、高差、双方占地和封洞均取自规则引擎，绘制地形的笔触固定在世界坐标。Q/E 旋转，滚轮缩放，Tab 查看战术地图。

九类单位的正式图集位于 `art/original/actors/`。在仓库根目录运行 `python3 art/tools/pack_originals.py` 从原创透明原稿重新排版人物、野兽、火焰及地表。该命令需要 Pillow。前后两组各含待机、走格和攻击。主角与狮子另有蓄力和收势关键帧。

在焚村使用 `--demo=material --capture=material.png` 可重放走格、矛刺与敌方阶段。`material_side` 旋转 90°，`material_close` 和 `material_far` 分别切换最近与最远缩放档。

## 运行测试

```sh
./run_tests.sh
```

测试框架是 gdUnit4（`addons/gdUnit4/`，6.2.3）。`tests/` 里只剩一个冒烟测试（`test_engine_smoke.gd`）：经由 Go 引擎开战、移动、攻击、结束回合，确认 Godot 这一侧接得上。报告写到 `reports/`。默认使用 `../../cloudbound-isles/.tools/godot/` 里的 Godot 4.7.2，可以用环境变量 `GODOT` 指定其他路径。

规则本身的测试、与原 GDScript 引擎的对拍、批量模拟和数值检查都在 `../engine/`：`go test ./...`，以及 `srpg simulate / replay / bench / export-metrics / check` 等命令。

无头自检（不需要显示器，走完整个敌方阶段后退出）：

```sh
"$GODOT" --headless --path . -- --battle=1-5 --demo=enemy --capture=x.png
```

## 目录

| 目录 | 内容 |
|---|---|
| `core/` | Go 规则引擎的客户端：`go_engine.gd` 拉起并连接引擎，其余文件是局面快照（`BattleState`、`UnitState`、`BattleGrid`）和转发调用的薄封装（`Rules`、`Movement`、`EnemyAI`）。不含规则 |
| `data/` | `tables/*.json` 是全部数值（单位、技能、技能树、战斗），由 Go 引擎读取；同目录的 GDScript 只把引擎给的定义转交给界面 |
| `view/` | 低分辨率 3D 世界：灰盒地图、单位精灵、高亮、相机、像素化后处理；`battle_controller.gd` 是入口 |
| `ui/` | 原生分辨率 HUD：面板、覆盖层（血条、破势条、浮动数字、意图箭头）、事件文本 |
| `tests/` | gdUnit4 冒烟测试；`tests/support/` 是断言辅助 |
| `addons/gdUnit4/` | gdUnit4 测试框架（6.2.3），随仓库保存 |
| `addons/godot_ai/` | godot-ai 编辑器插件（4.4.1），随仓库保存 |
| `tools/inspect_godot.py` | godot-ai 的项目内客户端 |

## 规则调用要点

- `Rules.perform(state, action)` 让引擎校验并执行一个行动，返回事件列表，并原地刷新 `state` 快照。
- `Rules.preview(state, action)` 由引擎在副本上执行同一段代码，所以预览结果与实际执行完全一致。
- `Rules.targeting(state, pending)` 一次返回瞄准时要画的全部格子（射程、可选目标、跳跃落点）。
- `Rules.end_phase(state)` 推进阶段：我方 → 敌方 → 回合结算 → 下一回合我方。
- 不改变局面的查询按局面缓存，悬停时反复问同一件事不会重复请求。

## 编辑器自动化（godot-ai）

插件已经在 `project.godot` 里启用，同时注册了运行时 autoload `_mcp_game_helper`。用编辑器打开本工程后：

```sh
uv run --with mcp python tools/inspect_godot.py editor_state '{}'
uv run --with mcp python tools/inspect_godot.py logs_read '{"source":"editor","count":20}'
```

独立服务固定为 `godot-ai==4.4.1`，启动时禁用遥测；需要安装 `uv`。
