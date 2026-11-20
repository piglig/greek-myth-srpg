extends "res://tests/support/test_case.gd"
## 冒烟测试：经由 Go 规则引擎开一场战斗，移动、攻击、结束回合，检查快照跟着变。
## 规则本身的测试都在 engine/（go test ./...）；这里只确认 Godot 这一侧接得上。


func after() -> void:
	GoEngine.shutdown()


## 敌方阶段：和 battle_controller._end_turn 相同的流程，不带动画。
func _enemy_phase(s: BattleState) -> Array:
	var all: Array = []
	all.append_array(Rules.end_phase(s))
	for e in s.living(Defs.Team.ENEMY):
		var guard := 0
		while e.alive and not e.has_acted and guard < 4:
			guard += 1
			var p := EnemyAI.plan(s, e)
			if p.has("move_to"):
				all.append_array(Rules.perform(s, {"type": "move", "unit": e.id, "to": p["move_to"]})["events"])
			var o := Rules.perform(s, p["action"])
			if not o["ok"]:
				o = Rules.perform(s, {"type": "wait", "unit": e.id})
			all.append_array(o["events"])
			if not Rules.finish_activation(s, e):
				break
	all.append_array(Rules.end_phase(s))
	return all


func test_engine_starts_and_serves_the_tables() -> void:
	check(GoEngine.ensure(), "engine starts: " + GoEngine.error)
	check(Battles.ids().has("1-4") and Battles.ids().has("1-5"), "battle list")
	check(Battles.title("1-4").begins_with("1-4"), "battle title")
	eq(SkillCatalog.get_skill("spear")["name"], "矛刺", "skill names")
	check(SkillCatalog.get_skill("pounce").has("leap"), "leap skills are marked")
	eq(SkillTree.validate("hero", ["slam", "iron_arm", "shield_wall"]), "", "4 points ok")
	eq(SkillTree.validate("hero", ["slam", "iron_arm", "shield_wall", "intercept"]), "over budget", "6 points")
	eq(SkillTree.cost("hero", ["slam", "iron_arm"]), 3, "cost")
	check(SkillTree.trees().has("hero") and SkillTree.trees().has("atalanta"), "trees")
	eq(UnitCatalog.unit_def("lion")["name"], "涅墨亚狮子", "unit names")


func test_move_attack_and_end_turn() -> void:
	var s := Battles.build("test", SkillTree.default_picks())
	check(s != null, "battle builds: " + GoEngine.error)
	Rules.start_battle(s)
	eq(s.round_number, 1, "round 1")
	eq(s.phase, Defs.Phase.PLAYER, "player phase")
	eq(s.grid.width, 12, "grid width")
	var hero := s.unit("hero")
	eq(hero.pos, Vector2i(1, 8), "hero start")
	check(hero.has_trait("slam") and hero.has_trait("grapple"), "default picks and base traits arrive")

	# 移动：目的地来自引擎，走完后同一个 UnitState 对象原地更新
	var dests := Movement.destinations(s, hero)
	check(dests.has(Vector2i(1, 6)) and not dests.has(Vector2i(9, 2)), "destinations")
	eq(Rules.validate(s, {"type": "move", "unit": "hero", "to": Vector2i(9, 2)}), "unreachable", "validate")
	var mv := Rules.perform(s, {"type": "move", "unit": "hero", "to": Vector2i(1, 6)})
	check(mv["ok"], mv["error"])
	eq(mv["events"][0]["type"], "move", "move event")
	eq(mv["events"][0]["path"], [Vector2i(1, 7), Vector2i(1, 6)] as Array[Vector2i], "path as cells")
	eq(hero.pos, Vector2i(1, 6), "snapshot follows the move")
	check(s.move_undo.has("hero"), "move can be undone")
	check(Rules.perform(s, {"type": "undo_move", "unit": "hero"})["ok"], "undo")
	eq(hero.pos, Vector2i(1, 8), "undo restores the position")

	# 一直打到有人能出手：每回合让每个我方单位找一个能打的目标，没有就待机
	var attacked := false
	var rounds := 0
	while not attacked and rounds < 8 and hero.alive:
		rounds += 1
		for u in s.living(Defs.Team.PLAYER):
			if attacked or u.has_acted:
				continue
			for sk in u.skills:
				var t := Rules.targeting(s, {"type": "skill", "unit": u.id, "skill": sk})
				var valid: Array[Vector2i] = t["valid"]
				if valid.is_empty():
					continue
				var target := s.unit_at(valid[0])
				var hp_before := target.hp
				var act := {"type": "skill", "unit": u.id, "skill": sk, "target": target.pos}
				var p := Rules.preview(s, act)
				check(p["ok"], "preview: " + str(p["error"]))
				eq(target.hp, hp_before, "preview does not change the snapshot")
				var o := Rules.perform(s, act)
				check(o["ok"], o["error"])
				check(has_event(o["events"], "attack"), "attack event")
				eq(sum_events(o["events"], "damage", "amount"), sum_events(p["events"], "damage", "amount"), "preview == perform")
				check(target.hp < hp_before, "target lost hp (%d -> %d)" % [hp_before, target.hp])
				check(u.has_acted, "attacker spent its action")
				check(not EventText.describe(s, o["events"]).is_empty(), "events can be described")
				attacked = true
				break
		if attacked:
			break
		for u in s.living(Defs.Team.PLAYER):
			if not u.has_acted:
				Rules.perform(s, {"type": "wait", "unit": u.id})
		var round_before := s.round_number
		var before := {}
		for e in s.living(Defs.Team.ENEMY):
			before[e.id] = e.pos
		_enemy_phase(s)
		eq(s.round_number, round_before + 1, "a new round after both phases")
		eq(s.phase, Defs.Phase.PLAYER, "back to the player phase")
		if rounds == 1:
			var moved := false
			for e in s.living(Defs.Team.ENEMY):
				moved = moved or e.pos != before[e.id]
			check(moved, "enemies advanced during their phase")
			check(not hero.has_acted, "player units are refreshed")
	check(attacked, "someone got to attack within %d rounds" % rounds)


func test_cave_battle_snapshot_and_previews() -> void:
	var s := Battles.build("1-5", SkillTree.default_picks())
	check(s != null, "battle builds: " + GoEngine.error)
	Rules.start_battle(s)
	check(not s.cave.is_empty(), "cave arrives")
	eq(s.cave["entrances"]["west"]["anchor"], Vector2i(2, 3), "entrance anchor")
	eq(s.cave["boulders"]["boulder_e"]["pos"], Vector2i(12, 5), "boulder position")
	var lion := s.unit("lion")
	check(lion.is_boss() and lion.size == 2, "lion is a 2x2 boss")
	eq(s.unit_at(Vector2i(7, 4)), lion, "footprint lookup")
	check(EnemyAI.threat_cells(s, lion).size() > 20, "threat cells")
	var sim := EnemyAI.simulate(s, lion)
	check(sim["plan"].has("action") and not (sim["events"] as Array).is_empty(), "intent preview")
	eq(lion.pos, Vector2i(6, 3), "intent preview does not move the real lion")
	eq(s.phase, Defs.Phase.PLAYER, "nor change the phase")
	var land := Rules.targeting(s, {"type": "skill", "unit": "lion", "skill": "pounce"})
	check(not (land["landings"] as Array).is_empty(), "leap landings in one request")
	var shoot := Rules.targeting(s, {"type": "skill", "unit": "atalanta", "skill": "shoot"})
	check((shoot["in_range"] as Array).size() > 20 and (shoot["valid"] as Array).is_empty(), "range band without targets")
	eq(Rules.validate(s, {"type": "push_boulder", "unit": "hero", "target": Vector2i(12, 5)}), "not adjacent", "boulder rules")
	# 整个敌方阶段走一遍，局面照常推进
	for u in s.living(Defs.Team.PLAYER):
		Rules.perform(s, {"type": "wait", "unit": u.id})
	_enemy_phase(s)
	eq(s.round_number, 2, "round 2")
	check(lion.pos != Vector2i(6, 3), "the lion moved")
