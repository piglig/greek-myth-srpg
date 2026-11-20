# 12 战棋工坊（Balance Studio）

> **2026-11-21 更新：全部工具已用 Go 重写，统一为 `engine/bin/srpg.exe`，战斗规则只有 Go 一份实现。命令和目录以 [engine/README.md](engine/README.md) 为准；下文里提到 Python、uv、pytest、GDScript 规则、gdUnit 的地方是当时的做法，保留作记录。**

关卡编辑、模拟、分析、回放、对比都在同一个本地网页里完成，不需要命令行，也不需要手改文件。人在界面上操作，AI 通过同一套接口操作，双方改的是同一份数据，互相能实时看到。

## 启动

```
cd balance
engine/bin/srpg.exe studio          # 打开 http://127.0.0.1:8765
```

首次使用或改了前端代码后，先构建一次网页：`cd balance/web && npm install && npm run build`。

## 一次完整的循环

1. **新建变体**。基线（`prototype/data/tables` 下的正式数据）只读；变体是一份可以随便改的副本，只保存和基线不同的文件。
2. **关卡**：地图是可旋转、可缩放的立体方块模型，高度就是方块的高度。画布底部的工具条里选工具：高度（左键抬高、右键或 Shift 降低、拖动抹平，也可以直接设为 0–5）、地形、放置单位、移除；选中单位后拖动移动、按 R 转向、Delete 移除。改动自动保存，可撤销。错误（重叠、出界、站在不可通行地形上、缺主角）会直接标在格子上。被悬崖挡住的地方可以转视角，或者点"压平"。可以一键用游戏引擎渲染实际画面。
3. **数值**：单位表和技能表，和基线不同的格子带底色。
4. **模拟分析**：选机器人和局数，点运行，界面显示进度。结果包括每个设计目标的达标情况（目标范围、实测值、95% 区间）、战斗结果、回合数与剩余生命分布、伤害占比、机制使用率；地图上可以叠加"敌人倒下 / 敌人坠落 / 我方受伤"的位置。设计目标也在这里改。
5. **回放**：点任意一局，在同一张地图上逐步重放，旁边是逐条记录。用来区分"设计有问题"和"机器人打得不对"。
6. **对比**：基线和所有变体在同一套目标下并排比较，带相对基线的变化。
7. **采用为基线**：把变体写回正式数据。与当前数据一致的模拟结果一并转为基线结果。

数据或规则代码改动后，旧的模拟结果会被标为"已过期"，不会被误当成当前结论。

## 人和 AI 协作

- 界面上的每个操作都对应一个接口（接口文档：`http://127.0.0.1:8765/docs`）。AI 调用时带请求头 `X-Actor: ai`。
- 底部状态栏显示最近一条操作，点开是完整的操作记录，列出谁做了什么；AI 的操作会在界面右下角弹出提示，地图和结果会自动刷新。
- 每个视图都有可以直接打开的链接，例如
  `/?mode=replay&battle=1-4&variant=某变体&bot=novice&seed=3`、`/?mode=sim&battle=1-4&heat=falls`。

常用接口：

| 用途 | 接口 |
|---|---|
| 读取某个版本的全部数据、检查结果、与基线的差异 | `GET /api/data?variant=` |
| 新建 / 删除 / 采用变体 | `POST /api/variants`、`DELETE /api/variants/{名称}`、`POST /api/variants/{名称}/adopt` |
| 保存关卡、保存数值表 | `PUT /api/variants/{名称}/battles/{关卡}`、`PUT /api/variants/{名称}/tables/{units\|skills}` |
| 运行、查看、取消模拟 | `POST /api/sims`、`GET /api/jobs`、`POST /api/jobs/{id}/cancel` |
| 结果与各版本对比 | `GET /api/results?battle=&variant=`、`GET /api/compare?battle=` |
| 回放一局 | `GET /api/replay?battle=&variant=&bot=&seed=` |
| 渲染游戏内画面 | `POST /api/preview?battle=&variant=` |

## 实现位置

| 部分 | 位置 |
|---|---|
| 后端（Go） | `engine/studio/`：变体、检查、差异、采用、指标与热力图、模拟任务、HTTP 接口和事件推送 |
| 前端（React + Mantine） | `balance/web/src/` |
| 变体与操作记录 | `balance/workspace/` |
| Godot 侧 | `Tables` 的 `--data-dir` 覆盖目录；`tools/replay.gd` 导出逐步回放；`BattleRunner` 记录倒下、坠落、受伤的位置 |
| 测试 | `engine/studio/*_test.go`（后端）；`balance/web/e2e/studio.e2e.mjs`（浏览器里跑完整循环） |

## 已知限制

- 3D 预览是一张截图，不能旋转；渲染时会短暂弹出游戏窗口。
- 模拟一次只跑一个，其余排队。
- 回放按需重算（约 10 秒一局），之后有缓存。
- 技能树、技能的非数值字段（形状、类型）目前只能看不能在界面里改。
