class_name EventText
extends RefCounted
## Turns rule events into Chinese lines for the preview panel and battle log.

const STATUS_NAMES := {
	"impervious_hide":"不坏之皮","guard": "防御姿态", "dodge": "闪避", "stunned": "眩晕", "staggered": "破势",
	"rooted": "束缚", "burning": "灼烧", "poisoned": "中毒",
	"petrified": "石化", "control_immune": "控制免疫",
}
const SOURCE_NAMES := {
	"fall": "坠落", "choke": "窒息", "collision": "撞击", "edge": "坠出边缘",
	"assist": "援护", "burning": "灼烧", "poisoned": "中毒", "styx": "冥河",
}
const NOTE_NAMES := {
	"kindling":"助燃",
	"charge":"冲锋","block": "格挡", "high_ground": "高处", "cover": "掩体", "marked": "标记",
	"flanked": "包夹", "guard": "防御姿态", "broken": "破势中", "grappled": "被擒抱",
	"physical_immune": "物理免疫", "patience": "猎人耐心", "iron_arm": "铁臂", "shield_wall": "盾墙",
}
const RELATION_NAMES := ["正面", "侧面", "背面"]
const ENTRANCE_NAMES := {"west": "西侧", "east": "东侧", "north": "北侧", "south": "南侧"}
const ERRORS := {
	"need healable ally":"请选择可治疗的同伴","unhurt ally":"同伴无需救治",
	"wounded ally":"负伤的喀戎会自行射击","no such unit": "没有这个单位", "not this unit's phase": "不是它的回合", "already acted": "已经行动过",
	"grappled": "正被擒抱", "grappling": "正在擒抱", "cannot move now": "现在不能移动",
	"unreachable": "到不了", "nothing to undo": "没有可撤销的移动", "unknown skill": "没有这个技能",
	"on cooldown": "冷却中", "no enemy there": "那里没有敌人",
	"grappled: can only strike the grappler": "被擒抱时只能攻击擒抱者", "out of range": "超出射程",
	"not in line": "不在直线上", "no line of sight": "视线被挡住", "cannot grapple": "不会擒抱",
	"not adjacent": "不相邻", "cannot grapple that": "不能擒抱这个目标", "already grappled": "已被擒抱",
	"not grappling": "没有在擒抱", "not grappled": "没有被擒抱", "facing locked": "朝向被锁定",
	"bad facing": "朝向无效", "cannot mark": "不能标记", "need landing": "先选择落点",
	"bad landing": "不能落在那里", "no boulder there": "那里没有巨石", "already sealed": "这个入口已经封住",
	"cannot seal the last entrance": "不能封住最后一个入口", "no one in range": "范围内没有目标", "cannot slam": "没有可摔投的目标", "bad slam direction": "只能摔向目标相邻的格子",
}


static func error_text(err: String) -> String:
	return ERRORS.get(err, err)
const END_REASONS := {
	"escaped": "挣脱", "released": "松开", "displaced": "被击退", "ko": "倒下", "controlled": "受控",
	"slam": "摔投",
}


static func name_of(state: BattleState, id: String) -> String:
	var u := state.unit(id)
	return u.display_name if u != null else id


static func skill_name(skill_id: String) -> String:
	return SkillCatalog.get_skill(skill_id)["name"] if SkillCatalog.has_skill(skill_id) else skill_id


static func describe(state: BattleState, events: Array) -> Array[String]:
	var lines: Array[String] = []
	for e in events:
		var line := _line(state, e)
		if line != "":
			lines.append(line)
	return lines


static func _line(s: BattleState, e: Dictionary) -> String:
	match e["type"]:
		"rescued":
			return "村民已从西侧山道撤离"
		"arrival":
			return s.unit(e["unit"]).display_name + " 进入战场"
		"attack":
			var notes: Array[String] = []
			for n in e["notes"]:
				notes.append(NOTE_NAMES.get(n, n))
			var extra := "" if notes.is_empty() else "，" + "、".join(notes)
			return "%s 对 %s 使用「%s」（%s%s）" % [name_of(s, e["unit"]), name_of(s, e["target"]),
				skill_name(e["skill"]), RELATION_NAMES[e["relation"]], extra]
		"heal":
			return "%s 的净化箭为 %s 恢复 %d 点生命（现有 %d）"%[name_of(s,e.unit),name_of(s,e.target),e.amount,e.hp]
		"damage":
			var src: String = SOURCE_NAMES.get(e["source"], "")
			var label := "" if src == "" else src + " "
			return "  %s受到 %s%d 点伤害（剩余 %d）" % [name_of(s, e["target"]), label, e["amount"], maxi(e["hp"], 0)]
		"assist":
			return "%s 援护攻击（%s）" % [name_of(s, e["unit"]), RELATION_NAMES[e["relation"]]]
		"knockback":
			return "  %s 被击退到 %s" % [name_of(s, e["target"]), _cell(e["to"])]
		"fall":
			return "  %s 坠落 %d 层" % [name_of(s, e["target"]), e["levels"]]
		"collision":
			var other: String = "墙壁" if e["with"] == "wall" else name_of(s, e["with"])
			return "  %s 撞上 %s" % [name_of(s, e["target"]), other]
		"edge":
			return "  %s 被推出边缘" % name_of(s, e["target"])
		"stagger":
			var u := s.unit(e["target"])
			return "  %s 破势 +%d（%d/%d）" % [name_of(s, e["target"]), e["amount"], e["total"], u.stagger_max if u else 0]
		"broken":
			return "★ %s 破势！跳过行动并失去免疫" % name_of(s, e["target"])
		"ko":
			return "✖ %s 倒下" % name_of(s, e["target"])
		"grapple_start":
			return "%s 擒抱 %s（挣脱值 %d）" % [name_of(s, e["grappler"]), name_of(s, e["target"]), e["escape"]]
		"grapple_end":
			return "  %s 的擒抱结束（%s）" % [name_of(s, e["grappler"]), END_REASONS.get(e["why"], e["why"])]
		"struggle":
			return "%s 挣扎（挣脱值 %d）" % [name_of(s, e["unit"]), e["escape"]]
		"reinforce":
			return "%s 加固擒抱（挣脱值 %d）" % [name_of(s, e["unit"]), e["escape"]]
		"escape_tick":
			return "  %s 的挣脱值降到 %d" % [name_of(s, e["target"]), e["escape"]]
		"status":
			return "  %s 获得%s" % [name_of(s, e["target"]), STATUS_NAMES.get(e["status"], e["status"])]
		"status_end":
			return "  %s 的%s结束" % [name_of(s, e["target"]), STATUS_NAMES.get(e["status"], e["status"])]
		"resist":
			return "  %s 抵抗了%s" % [name_of(s, e["target"]), STATUS_NAMES.get(e["status"], e["status"])]
		"dodge":
			return "  %s 闪避了攻击" % name_of(s, e["target"])
		"shield":
			return "  %s 的护盾吸收 %d" % [name_of(s, e["target"]), e["absorbed"]]
		"stun_skip":
			return "%s 眩晕中，跳过行动" % name_of(s, e["unit"])
		"mark":
			return "%s 标记了 %s" % [name_of(s, e["unit"]), name_of(s, e["target"])]
		"move":
			return "%s 移动到 %s" % [name_of(s, e["unit"]), _cell(e["to"])]
		"leap":
			return "%s 跃到 %s" % [name_of(s, e["unit"]), _cell(e["to"])]
		"area":
			return "%s 使用「%s」" % [name_of(s, e["unit"]), skill_name(e["skill"])]
		"push":
			return "%s 推动巨石（%d/2）" % [name_of(s, e["unit"]), mini(int(e["progress"]), 2)]
		"sealed":
			return "  巨石封住了%s入口" % ENTRANCE_NAMES.get(e["entrance"], e["entrance"])
		"flee":
			return s.unit(e.unit).display_name + " 撤出宴地"
		"retreat":
			return "%s 退回洞内" % name_of(s, e["unit"])
		"emerge":
			return "%s 从%s入口冲出，落在 %s" % [name_of(s, e["unit"]), ENTRANCE_NAMES.get(e["entrance"], e["entrance"]), _cell(e["to"])]
		"intercept":
			return "%s 截击，替 %s 挡下攻击" % [name_of(s, e["unit"]), name_of(s, e["protected"])]
		"slam":
			return "%s 把 %s 摔了出去" % [name_of(s, e["unit"]), name_of(s, e["target"])]
	return ""


static func _cell(c: Vector2i) -> String:
	return "(%d, %d)" % [c.x, c.y]
