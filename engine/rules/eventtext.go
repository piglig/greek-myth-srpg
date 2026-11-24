package rules

import (
	"fmt"
	"strings"
)

// 把规则事件写成中文，用于预览面板、战斗日志和回放。

var statusNames = map[string]string{
	"guard": "防御姿态", "dodge": "闪避", "stunned": "眩晕", "staggered": "破势",
	"rooted": "束缚", "burning": "灼烧", "poisoned": "中毒",
	"petrified": "石化", "control_immune": "控制免疫",
}

var sourceNames = map[string]string{
	"fall": "坠落", "collision": "撞击", "edge": "坠出边缘",
	"assist": "援护", "burning": "灼烧", "poisoned": "中毒", "styx": "冥河", "thunder_body": "雷躯",
}

var noteTexts = map[string]string{
	"kindling": "助燃", "charge": "冲锋", "block": "格挡", "high_ground": "高处", "cover": "掩体", "marked": "标记",
	"flanked": "包夹", "guard": "防御姿态", "broken": "破势中",
	"physical_immune": "物理免疫", "patience": "猎人耐心", "shield_wall": "盾墙",
}

var relationNames = [...]string{"正面", "侧面", "背面"}

var entranceNames = map[string]string{"west": "西侧", "east": "东侧", "north": "北侧", "south": "南侧"}

var errorTexts = map[string]string{
	"wounded ally": "负伤的喀戎会自行射击", "no such unit": "没有这个单位", "not this unit's phase": "不是它的回合", "already acted": "已经行动过",
	"cannot move now": "现在不能移动",
	"unreachable":     "到不了", "nothing to undo": "没有可撤销的移动", "unknown skill": "没有这个技能",
	"need healable ally": "请选择可治疗的同伴", "unhurt ally": "同伴无需救治", "on cooldown": "冷却中", "no enemy there": "那里没有敌人",
	"out of range": "超出射程",
	"not in line":  "不在直线上", "no line of sight": "视线被挡住",
	"not adjacent": "不相邻", "cannot throw that": "摔不动这个目标", "cannot be healed": "他已经不是凡人的药能治的了",
	"bad facing": "朝向无效", "cannot mark": "不能标记", "need landing": "先选择落点",
	"bad landing": "不能落在那里", "no boulder there": "那里没有巨石", "already sealed": "这个入口已经封住",
	"cannot seal the last entrance": "不能封住最后一个入口", "no one in range": "范围内没有目标",
}

func lookup(m map[string]string, k string) string {
	if v, ok := m[k]; ok {
		return v
	}
	return k
}

// ErrorText 把校验的出错原因翻成中文。
func ErrorText(err string) string { return lookup(errorTexts, err) }

func nameOf(s *BattleState, id string) string {
	if u := s.Unit(id); u != nil {
		return u.Name
	}
	return id
}

// 技能的显示名：在场上任何单位的技能里找，找不到就用 id。
func skillName(s *BattleState, id string) string {
	for _, u := range s.Units {
		if sk := u.Skill(id); sk != nil {
			return sk.Name
		}
	}
	return id
}

// Describe 把一批事件写成若干行中文。
func Describe(s *BattleState, events []Event) []string {
	lines := []string{}
	for i := range events {
		if line := describeOne(s, &events[i]); line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

func cellText(c Cell) string { return fmt.Sprintf("(%d, %d)", c.X, c.Y) }

func describeOne(s *BattleState, e *Event) string {
	switch e.Type {
	case EvFlee:
		return s.Unit(e.Unit).Name + " 撤出了宴地"
	case EvRescued:
		return "村民已从西侧山道撤离"
	case EvArrival:
		return s.Unit(e.Unit).Name + " 进入战场"
	case EvAttack:
		extra := ""
		if names := e.Notes.Names(); len(names) > 0 {
			for i, n := range names {
				names[i] = lookup(noteTexts, n)
			}
			extra = "，" + strings.Join(names, "、")
		}
		return fmt.Sprintf("%s 对 %s 使用「%s」（%s%s）", nameOf(s, e.Unit), nameOf(s, e.Target),
			skillName(s, e.Skill), relationNames[e.Relation], extra)
	case EvHeal:
		return fmt.Sprintf("%s 的净化箭为 %s 恢复 %d 点生命（现有 %d）", nameOf(s, e.Unit), nameOf(s, e.Target), e.Amount, e.HP)
	case EvDamage:
		label := ""
		if src, ok := sourceNames[e.Source]; ok && src != "" {
			label = src + " "
		}
		return fmt.Sprintf("  %s受到 %s%d 点伤害（剩余 %d）", nameOf(s, e.Target), label, e.Amount, max(e.HP, 0))
	case EvAssist:
		return fmt.Sprintf("%s 援护攻击（%s）", nameOf(s, e.Unit), relationNames[e.Relation])
	case EvKnockback:
		return fmt.Sprintf("  %s 被击退到 %s", nameOf(s, e.Target), cellText(e.To))
	case EvFall:
		return fmt.Sprintf("  %s 坠落 %d 层", nameOf(s, e.Target), e.Levels)
	case EvCollision:
		other := "墙壁"
		if e.With != "wall" {
			other = nameOf(s, e.With)
		}
		return fmt.Sprintf("  %s 撞上 %s", nameOf(s, e.Target), other)
	case EvEdge:
		return fmt.Sprintf("  %s 被推出边缘", nameOf(s, e.Target))
	case EvStagger:
		staggerMax := 0
		if u := s.Unit(e.Target); u != nil {
			staggerMax = u.StaggerMax
		}
		return fmt.Sprintf("  %s 破势 +%d（%d/%d）", nameOf(s, e.Target), e.Amount, e.Total, staggerMax)
	case EvBroken:
		return fmt.Sprintf("★ %s 破势！跳过行动并失去免疫", nameOf(s, e.Target))
	case EvKO:
		return fmt.Sprintf("✖ %s 倒下", nameOf(s, e.Target))
	case EvStatus:
		return fmt.Sprintf("  %s 获得%s", nameOf(s, e.Target), lookup(statusNames, e.Status))
	case EvStatusEnd:
		return fmt.Sprintf("  %s 的%s结束", nameOf(s, e.Target), lookup(statusNames, e.Status))
	case EvResist:
		return fmt.Sprintf("  %s 抵抗了%s", nameOf(s, e.Target), lookup(statusNames, e.Status))
	case EvDodge:
		return fmt.Sprintf("  %s 闪避了攻击", nameOf(s, e.Target))
	case EvShield:
		return fmt.Sprintf("  %s 的护盾吸收 %d", nameOf(s, e.Target), e.Absorbed)
	case EvStunSkip:
		return fmt.Sprintf("%s 眩晕中，跳过行动", nameOf(s, e.Unit))
	case EvMark:
		return fmt.Sprintf("%s 标记了 %s", nameOf(s, e.Unit), nameOf(s, e.Target))
	case EvMove:
		return fmt.Sprintf("%s 移动到 %s", nameOf(s, e.Unit), cellText(e.To))
	case EvLeap:
		return fmt.Sprintf("%s 跃到 %s", nameOf(s, e.Unit), cellText(e.To))
	case EvArea:
		return fmt.Sprintf("%s 使用「%s」", nameOf(s, e.Unit), skillName(s, e.Skill))
	case EvPush:
		return fmt.Sprintf("%s 推动巨石（%d/2）", nameOf(s, e.Unit), min(e.Progress, 2))
	case EvSealed:
		return fmt.Sprintf("  巨石封住了%s入口", lookup(entranceNames, e.Entrance))
	case EvRetreat:
		return fmt.Sprintf("%s 退回洞内", nameOf(s, e.Unit))
	case EvEmerge:
		return fmt.Sprintf("%s 从%s入口冲出，落在 %s", nameOf(s, e.Unit), lookup(entranceNames, e.Entrance), cellText(e.To))
	case EvIntercept:
		return fmt.Sprintf("%s 截击，替 %s 挡下攻击", nameOf(s, e.Unit), nameOf(s, e.Protected))
	case EvWard:
		return fmt.Sprintf("  %s 获得 %d 点护盾", nameOf(s, e.Target), e.Amount)
	case EvThrow:
		return fmt.Sprintf("%s 把 %s 摔了出去", nameOf(s, e.Unit), nameOf(s, e.Target))
	}
	return ""
}
