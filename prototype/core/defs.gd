class_name Defs
extends RefCounted
## 界面和规则引擎共用的枚举与方向常量。数值必须和 engine/rules/defs.go 一致。
## 规则用的调参常量都在 Go 引擎里，这里没有。

enum Team { PLAYER, ENEMY, NEUTRAL }
enum Terrain { PLAIN, FOREST, SHALLOW, DEEP, SWAMP, BURNING, STYX }
enum DamageType { PHYSICAL, DIVINE, TRUE }
enum Relation { FRONT, SIDE, BACK }
enum Phase { PLAYER, ENEMY }

const NORTH := Vector2i(0, -1)
const EAST := Vector2i(1, 0)
const SOUTH := Vector2i(0, 1)
const WEST := Vector2i(-1, 0)
const DIRS := [NORTH, EAST, SOUTH, WEST]

const NO_POS := Vector2i(-99999, -99999)  ## 表示“没有格子”
