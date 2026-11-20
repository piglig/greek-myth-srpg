# 平衡数据（balance）

这里只放数据和网页前端。程序在 [`../engine/`](../engine/README.md)（Go），方案见 [../11-balance-testing.md](../11-balance-testing.md)，战棋工坊见 [../12-balance-studio.md](../12-balance-studio.md)。

| 路径 | 内容 |
|---|---|
| `schemas/` | 数据表的 JSON Schema（未知字段、拼写错误、越界数值都会被拒绝） |
| `specs/*.yaml` | 静态规格：设计文档里的数值要求，每条都注明出处 |
| `targets/*.yaml` | 每场战斗的设计目标 |
| `workspace/` | 战棋工坊的变体和动态日志 |
| `out/` | 生成物：模拟结果、报告 |
| `web/` | 战棋工坊的网页前端（Vite + React）；`npm run build` 后由 `srpg studio` 提供 |

数据表本身在 `../prototype/data/tables/`。

## 改数值的流程

1. `srpg studio`，在工坊里新建变体、改数值、跑模拟、看结论，满意后采用。
2. 或者直接改 `prototype/data/tables/` 下的 JSON，然后 `srpg check`，再 `srpg run <战斗>`。
