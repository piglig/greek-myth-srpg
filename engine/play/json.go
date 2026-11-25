package play

import (
	"srpg/rules"
)

// 把引擎里的局面、事件、计划和数据表写成客户端用的 JSON 形状。
// 坐标一律是 [x, y]；有顺序要求的小表（状态、冷却、特性）写成 [[键, 值], ...]。

func xy(c rules.Cell) [2]int { return [2]int{c.X, c.Y} }

func cellsJSON(cells []rules.Cell) [][2]int {
	out := make([][2]int, len(cells))
	for i, c := range cells {
		out[i] = xy(c)
	}
	return out
}

func kvJSON(list []rules.KV) [][2]any {
	out := make([][2]any, len(list))
	for i, kv := range list {
		out[i] = [2]any{kv.Key, kv.Val}
	}
	return out
}

func stateJSON(s *rules.BattleState, withGrid bool) obj {
	units := make([]obj, len(s.Units))
	for i, u := range s.Units {
		skills := make([]string, len(u.Skills))
		for j, sk := range u.Skills {
			skills[j] = sk.ID
		}
		traits := [][2]any{}
		for _, name := range u.Traits.Names() {
			traits = append(traits, [2]any{name, true})
		}
		units[i] = obj{
			"id": u.ID, "def": u.DefID, "tree": u.TreeKey(), "name": u.Name, "team": int(u.Team), "pos": xy(u.Pos), "size": u.Size,
			"facing": xy(u.Facing), "max_hp": u.MaxHP, "hp": u.HP, "str": u.Strength, "div": u.Divinity,
			"defense": u.Defense, "wil": u.Will, "move": u.Move, "jump": u.Jump, "skills": skills, "traits": traits,
			"statuses": kvJSON(u.Statuses), "cooldowns": kvJSON(u.Cooldowns), "items": kvJSON(u.Charges), "shield": u.Shield,
			"stagger": u.Stagger, "stagger_max": u.StaggerMax, "boss": u.IsBoss(),
			"actions_per_turn": u.ActionsPerTurn, "actions_left": u.ActionsLeft,
			"has_moved": u.HasMoved, "has_acted": u.HasActed, "assist_used": u.AssistUsed, "mark_used": u.MarkUsed,
			"intercept_used": u.InterceptUsed, "post_move": u.PostMove,
			"alive": u.Alive, "hidden": u.Hidden,
			"regrow": u.Regrow, "regrown": u.Regrown, "sealed": u.Sealed,
			"can_undo": u.CanUndoMove(), "height": s.UnitHeight(u),
		}
	}
	out := obj{"round": s.Round, "phase": int(s.Phase), "marked": s.MarkedID, "previous_mark": s.PreviousMark, "reward": s.Reward, "units": units, "cave": nil}
	if c := s.Cave; c != nil {
		entrances := make([]obj, len(c.Entrances))
		for i, e := range c.Entrances {
			entrances[i] = obj{"id": e.ID, "anchor": xy(e.Anchor), "sealed": e.Sealed}
		}
		boulders := make([]obj, len(c.Boulders))
		for i, b := range c.Boulders {
			boulders[i] = obj{"id": b.ID, "pos": xy(b.Pos), "seals": b.Seals, "progress": b.Progress, "placed": b.Placed}
		}
		out["cave"] = obj{"boss": c.Boss, "trigger_hp": c.TriggerHP, "emerge_actions": c.EmergeActions, "last": c.Last,
			"entrances": entrances, "boulders": boulders}
	}
	if len(s.EscortExits) > 0 {
		out["escort_exits"] = cellsJSON(s.EscortExits)
		out["escort_result"] = s.Outcome()
	}
	if len(s.ReachExits) > 0 {
		out["reach_exits"] = cellsJSON(s.ReachExits)
		out["reach_result"] = s.Outcome()
		out["swamp_rests"] = s.SwampRests
	}
	if s.Drowned > 0 {
		out["drowned"] = s.Drowned
	}
	out["outcome"] = s.Outcome()
	out["most_regrown"] = s.MostRegrown()
	if s.FireEver {
		fires := make([][]int, 0, len(s.Fires))
		for _, f := range s.Fires {
			fires = append(fires, []int{f.Cell.X, f.Cell.Y, f.Left})
		}
		out["fires"], out["fire_next"] = fires, cellsJSON(s.FireNext())
	}
	if len(s.Targets) > 0 {
		out["targets"], out["targets_left"], out["targets_scorched"] = s.Targets, s.TargetsLeft(), s.TargetsScorched()
		out["target_result"] = s.Outcome()
	}
	if len(s.RescueExits) > 0 {
		out["rescue_result"] = s.Outcome()
		out["rescue_exits"] = cellsJSON(s.RescueExits)
	}
	if s.Village != nil {
		exits := make([][]int, 0, len(s.Village.Exits))
		for _, c := range s.Village.Exits {
			exits = append(exits, []int{c.X, c.Y})
		}
		out["village"] = obj{"exits": exits, "result": s.Outcome()}
	}
	if withGrid || s.Village != nil || s.FireEver {
		g := s.Grid
		heights := make([]int, 0, g.Width*g.Depth)
		terrain := make([]int, 0, g.Width*g.Depth)
		for y := 0; y < g.Depth; y++ {
			for x := 0; x < g.Width; x++ {
				heights = append(heights, g.HeightAt(rules.Cell{X: x, Y: y}))
				terrain = append(terrain, int(g.TerrainAt(rules.Cell{X: x, Y: y})))
			}
		}
		out["grid"] = obj{"w": g.Width, "d": g.Depth, "heights": heights, "terrain": terrain}
	}
	return out
}

// 事件写成原版事件字典的形状（键名不变），界面的动画和文字代码照旧可用。
func eventsJSON(events []rules.Event) []obj {
	out := make([]obj, len(events))
	for i := range events {
		e := &events[i]
		m := obj{"type": e.Type.String()}
		switch e.Type {
		case rules.EvDodge:
			m["target"], m["source"] = e.Target, e.Source
		case rules.EvShield:
			m["target"], m["absorbed"] = e.Target, e.Absorbed
		case rules.EvHeal:
			m["unit"], m["target"], m["skill"], m["amount"], m["hp"] = e.Unit, e.Target, e.Skill, e.Amount, e.HP
		case rules.EvDamage:
			m["target"], m["amount"], m["dmg_type"], m["source"], m["hp"] = e.Target, e.Amount, int(e.DmgType), e.Source, e.HP
		case rules.EvArrival, rules.EvRescued, rules.EvFlee:
			m["unit"] = e.Unit
		case rules.EvKO, rules.EvBroken, rules.EvEdge, rules.EvCauterize, rules.EvRegrow:
			m["target"] = e.Target
		case rules.EvResist:
			m["target"], m["status"], m["why"] = e.Target, e.Status, e.Why
		case rules.EvStatus:
			m["target"], m["status"], m["rounds"] = e.Target, e.Status, e.Rounds
		case rules.EvStatusEnd:
			m["target"], m["status"] = e.Target, e.Status
		case rules.EvStagger:
			m["target"], m["amount"], m["total"] = e.Target, e.Amount, e.Total
		case rules.EvCollision:
			m["target"], m["with"] = e.Target, e.With
		case rules.EvKnockback:
			m["target"], m["from"], m["to"] = e.Target, xy(e.From), xy(e.To)
		case rules.EvFall:
			m["target"], m["levels"] = e.Target, e.Levels
		case rules.EvFace:
			m["unit"], m["facing"] = e.Unit, xy(e.Facing)
		case rules.EvMark, rules.EvThrow:
			m["unit"], m["target"] = e.Unit, e.Target
		case rules.EvMove:
			m["unit"], m["from"], m["to"], m["path"] = e.Unit, xy(e.From), xy(e.To), cellsJSON(e.Path)
		case rules.EvUndoMove, rules.EvLeap:
			m["unit"], m["from"], m["to"] = e.Unit, xy(e.From), xy(e.To)
		case rules.EvWard:
			m["target"], m["amount"] = e.Target, e.Amount
		case rules.EvIgnite, rules.EvBurnOut:
			m["to"] = xy(e.To)
		case rules.EvSupport:
			m["unit"], m["skill"], m["to"], m["source"] = e.Unit, e.Skill, xy(e.To), e.Source
		case rules.EvArea:
			m["unit"], m["skill"], m["to"] = e.Unit, e.Skill, xy(e.To)
		case rules.EvAttack:
			notes := e.Notes.Names()
			if notes == nil {
				notes = []string{}
			}
			m["unit"], m["target"], m["skill"], m["relation"], m["notes"] = e.Unit, e.Target, e.Skill, int(e.Relation), notes
		case rules.EvAssist:
			m["unit"], m["target"], m["relation"] = e.Unit, e.Target, int(e.Relation)
		case rules.EvPush:
			m["unit"], m["boulder"], m["progress"] = e.Unit, e.Boulder, e.Progress
		case rules.EvSealed:
			m["entrance"], m["boulder"] = e.Entrance, e.Boulder
		case rules.EvRetreat, rules.EvStunSkip:
			m["unit"] = e.Unit
		case rules.EvEmerge:
			m["unit"], m["entrance"], m["to"] = e.Unit, e.Entrance, xy(e.To)
		case rules.EvIntercept:
			m["unit"], m["protected"] = e.Unit, e.Protected
		}
		out[i] = m
	}
	return out
}

func actionOut(a rules.Action) obj {
	m := obj{"type": a.Type.String(), "unit": a.Unit}
	switch a.Type {
	case rules.ActMove:
		m["to"] = xy(a.To)
	case rules.ActSkill:
		m["skill"], m["target"] = a.Skill, xy(a.Target)
		if a.HasTo {
			m["to"] = xy(a.To)
		}
	case rules.ActMark, rules.ActPushBoulder:
		m["target"] = xy(a.Target)
	case rules.ActFace:
		m["facing"] = xy(a.Facing)
	case rules.ActEmerge:
		m["entrance"] = a.Entrance
	}
	return m
}

func planJSON(p rules.Plan) obj {
	m := obj{"action": actionOut(p.Action)}
	if p.HasMove {
		m["move_to"] = xy(p.MoveTo)
	}
	return m
}

var typeNames = [...]string{rules.Physical: "physical", rules.Divine: "divine", rules.True: "true"}

// 数据表里界面要用到的部分：技能、单位、技能树、战斗列表。
func (s *Server) dataJSON() obj {
	d := s.data
	skills := [][2]any{}
	for _, id := range d.SkillIDs {
		sk := d.Skill(id)
		m := obj{"name": sk.Name}
		if sk.HasMult {
			m["mult"], m["type"] = sk.Mult, int(sk.Type)
			m["type_name"] = typeNames[sk.Type]
		}
		if sk.HasMinRange {
			m["min_range"] = sk.MinRange
		}
		if sk.HasMaxRange {
			m["max_range"] = sk.MaxRange
		}
		if sk.Line {
			m["shape"] = "line"
		}
		if sk.Ranged {
			m["ranged"] = true
		}
		for k, v := range map[string]int{"knockback": sk.Knockback, "cooldown": sk.Cooldown,
			"stagger_bonus": sk.StaggerBonus, "marked_flank_stagger": sk.MarkedFlankStagger} {
			if v != 0 {
				m[k] = v
			}
		}
		if sk.HasLeap {
			m["leap"], m["leap_rise"] = sk.Leap, sk.LeapRise
		}
		if sk.Item {
			m["item"] = true
		}
		if sk.Support != "" {
			m["support"], m["power"] = sk.Support, sk.Power
		}
		for k, v := range map[string]int{"heal": sk.Heal, "cleanse": sk.Cleanse} {
			if v != 0 {
				m[k] = v
			}
		}
		if sk.Status != "" {
			m["status"], m["rounds"] = sk.Status, sk.Rounds
		}
		if sk.SelfStatus != "" {
			m["self_status"], m["rounds"] = sk.SelfStatus, sk.Rounds
		}
		if sk.IsArea() {
			m["area_status"], m["radius"], m["rounds"] = sk.AreaStatus, sk.Radius, sk.Rounds
		}
		skills = append(skills, [2]any{id, m})
	}
	units := [][2]any{}
	for _, id := range d.UnitIDs {
		u := d.UnitDef(id)
		traits := obj{}
		for _, t := range u.Traits {
			traits[t.Key] = t.Value
		}
		units = append(units, [2]any{id, obj{"name": u.Name, "hp": u.HP, "max_hp": u.MaxHP, "str": u.Str, "div": u.Div,
			"def": u.Def, "wil": u.Wil, "move": u.Move, "jump": u.Jump, "size": u.Size, "actions": u.Actions,
			"stagger_max": u.StaggerMax, "skills": u.Skills, "traits": traits}})
	}
	trees := [][2]any{}
	for _, def := range d.TreeDefs {
		branches := []obj{}
		for _, br := range d.Trees(def) {
			nodes := []obj{}
			for _, n := range br.Nodes {
				node := obj{"id": n.ID, "name": n.Name, "cost": n.Cost, "desc": n.Desc, "parent": n.Parent}
				if n.Trait != "" {
					node["trait"] = n.Trait
				}
				if n.Skill != "" {
					node["skill"] = n.Skill
				}
				if len(n.Support) > 0 {
					mods := obj{}
					for _, kv := range n.Support {
						mods[kv.Key] = kv.Val
					}
					node["support"] = mods
				}
				nodes = append(nodes, node)
			}
			branches = append(branches, obj{"branch": br.Name, "nodes": nodes})
		}
		trees = append(trees, [2]any{def, branches})
	}
	battles := []obj{}
	if ids, err := d.BattleIDs(); err == nil {
		for _, id := range ids {
			battles = append(battles, obj{"id": id, "title": d.BattleTitle(id)})
		}
	} else {
		return fail("%v", err)
	}
	return obj{"protocol": Protocol, "points": d.Points, "skills": skills, "units": units, "trees": trees,
		"default_picks": d.DefaultPicks(), "battles": battles}
}
