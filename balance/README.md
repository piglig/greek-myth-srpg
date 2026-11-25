# 平衡数据（balance）

这里只放数据和网页前端。程序在 [`../engine/`](../engine/README.md)（Go），方案见 [../11-balance-testing.md](../11-balance-testing.md)，战棋工坊见 [../12-balance-studio.md](../12-balance-studio.md)。

| 路径 | 内容 |
|---|---|
| `schemas/` | 数据表的 JSON Schema（未知字段、拼写错误、越界数值都会被拒绝） |
| `specs/*.yaml` | 静态规格：设计文档里的数值要求，每条都注明出处 |
| `difficulty.yaml` | 难度目标：每类关卡对每种"配置 × 水平"的胜率区间。`srpg difficulty` 和工坊的"难度"页按它判定 |
| `kits.yaml` | 出战配置：节俭、一般、富裕三种玩家打到每一关时带着什么。模拟默认用"一般" |
| `targets/*.yaml` | 个别关卡的玩法目标（回合数、要教的招式有没有用上）。胜率不在这里 |
| `workspace/` | 战棋工坊的变体和动态日志 |
| `out/` | 生成物：模拟结果、报告 |
| `web/` | 战棋工坊的网页前端（Vite + React）；`npm run build` 后由 `srpg studio` 提供 |

数据表本身在 `../prototype/data/tables/`。

## 改数值的流程

1. `srpg studio`，在工坊里新建变体、改数值、跑模拟、看结论，满意后采用。
2. 或者直接改 `prototype/data/tables/` 下的 JSON，然后 `srpg check`，再 `srpg difficulty <关卡>` 看难度有没有跑出区间。

想知道换一位支援英雄会怎样，用 `srpg supports <关卡>`，或者在工坊的"支援"页里看。

机器人有三种：`casual`（普通玩家，主要验收对象）、`skilled`（熟练）、`novice`（几乎随机，只作参考，不进难度目标）。
