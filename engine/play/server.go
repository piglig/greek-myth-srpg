// Package play 让 Godot 原型把 Go 引擎当作唯一的规则实现来用。
//
// 服务端持有战斗（会话），客户端只拿到局面快照和事件；每个规则判定都在这里做。
//
// 传输：127.0.0.1 上的 TCP 连接，一问一答。每条消息 = 4 字节小端长度 + UTF-8 JSON。
// 请求是 {"op": "...", ...}；应答是一个 JSON 对象，协议层出错时为 {"fail": "原因"}。
// 一个服务进程只服务一个连接：连接断开（游戏退出）进程就结束，不会留下孤儿进程。
package play

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"time"

	"srpg/rules"
)

// Protocol 是协议版本；客户端在 hello 里核对。
const Protocol = 1

// 同时保留的战斗数上限（重开一局会新建会话，旧的按先后淘汰）。
const maxSessions = 8

// Server 持有数据表和进行中的战斗。只在一个 goroutine 里用。
type Server struct {
	data     *rules.Data
	sessions map[int]*rules.BattleState
	order    []int
	nextID   int
}

func NewServer(data *rules.Data) *Server {
	return &Server{data: data, sessions: map[int]*rules.BattleState{}}
}

// ListenAndServe 在 127.0.0.1:port 上监听（port 为 0 则由系统挑），把实际端口交给 ready，
// 然后等一个客户端连上来并服务到它断开。waitFor 内没人连接就返回错误。
func (s *Server) ListenAndServe(port int, waitFor time.Duration, ready func(port int)) error {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return err
	}
	defer ln.Close()
	if ready != nil {
		ready(ln.Addr().(*net.TCPAddr).Port)
	}
	if waitFor > 0 {
		ln.(*net.TCPListener).SetDeadline(time.Now().Add(waitFor))
	}
	conn, err := ln.Accept()
	if err != nil {
		return fmt.Errorf("没有客户端连接: %w", err)
	}
	defer conn.Close()
	if tc, ok := conn.(*net.TCPConn); ok {
		tc.SetNoDelay(true)
	}
	return s.Serve(conn)
}

// Serve 在一条连接上一问一答，直到对方断开。
func (s *Server) Serve(conn io.ReadWriter) error {
	r := bufio.NewReader(conn)
	var head [4]byte
	for {
		if _, err := io.ReadFull(r, head[:]); err != nil {
			if err == io.EOF || err == io.ErrUnexpectedEOF {
				return nil
			}
			return nil // 连接被对方重置也算正常结束
		}
		n := binary.LittleEndian.Uint32(head[:])
		if n > 16<<20 {
			return fmt.Errorf("请求过大: %d 字节", n)
		}
		body := make([]byte, n)
		if _, err := io.ReadFull(r, body); err != nil {
			return nil
		}
		reply := s.Handle(body)
		out := make([]byte, 4, 4+len(reply))
		binary.LittleEndian.PutUint32(out, uint32(len(reply)))
		if _, err := conn.Write(append(out, reply...)); err != nil {
			return nil
		}
	}
}

type cell = [2]int

type actionJSON struct {
	Type     string `json:"type"`
	Unit     string `json:"unit"`
	Skill    string `json:"skill"`
	Target   *cell  `json:"target"`
	To       *cell  `json:"to"`
	Facing   *cell  `json:"facing"`
	Entrance string `json:"entrance"`
}

// partyMember 是营地里选中出战、但关卡文件里没有写的我方单位（剧情加入的同伴或招募来的人）。
type request struct {
	// Party 不为 nil 时由它决定额外出战的人，ChironJoined 不再起作用。
	Party        []rules.PartyMember `json:"party"`
	Reward       rules.ChapterReward `json:"reward"`
	ChironJoined bool                `json:"chiron_joined"`
	// Bench 是关卡文件里写了、但这一场留在营地的我方单位。主角不能留守。
	Bench []string `json:"bench"`
	// Support 是来支援的英雄（recruits.json 里的名字）；空着就是没带。
	Support string              `json:"support"`
	Op      string              `json:"op"`
	SID     int                 `json:"sid"`
	Battle  string              `json:"battle"`
	Picks   map[string][]string `json:"picks"`
	// Loadout 按单位 id 给出带进战斗的招式（最多 rules.LoadoutSlots 个）。没列出的单位带上全部招式。
	Loadout map[string][]string `json:"loadout"`
	// Mods 按单位 id 给出装备带来的属性增减（hp/str/def/wil/div/move/jump）。
	Mods map[string]map[string]int `json:"mods"`
	// Items 按单位 id 给出随身物品（每件一个 id，最多 rules.KitSlots 件）。
	Items   map[string][]string `json:"items"`
	Action  *actionJSON         `json:"action"`
	Unit    string              `json:"unit"`
	Budget  *int                `json:"budget"`
	Cell    *cell               `json:"cell"`
	Skill   string              `json:"skill"`
	Def     string              `json:"def"`
	Nodes   []string            `json:"nodes"`
	Actions []*actionJSON       `json:"actions"`
}

type obj = map[string]any

func fail(format string, args ...any) obj { return obj{"fail": fmt.Sprintf(format, args...)} }

// Handle 处理一条请求，返回应答的 JSON。引擎内部出错（panic）也变成 {"fail": ...}，不会把服务拖垮。
func (s *Server) Handle(body []byte) (reply []byte) {
	defer func() {
		if r := recover(); r != nil {
			reply, _ = json.Marshal(fail("引擎内部错误: %v", r))
		}
	}()
	var req request
	if err := json.Unmarshal(body, &req); err != nil {
		reply, _ = json.Marshal(fail("请求不是合法的 JSON: %v", err))
		return
	}
	reply, err := json.Marshal(s.dispatch(&req))
	if err != nil {
		reply, _ = json.Marshal(fail("应答无法序列化: %v", err))
	}
	return
}

func toCell(c *cell) rules.Cell {
	if c == nil {
		return rules.NoPos
	}
	return rules.Cell{X: c[0], Y: c[1]}
}

func toAction(a *actionJSON) rules.Action {
	if a == nil {
		return rules.Action{}
	}
	act := rules.Action{Type: rules.ActionTypeByName(a.Type), Unit: a.Unit, Skill: a.Skill, Entrance: a.Entrance}
	if a.Target != nil {
		act.Target = toCell(a.Target)
	} else {
		act.Target = rules.NoPos
	}
	if a.To != nil {
		act.To, act.HasTo = toCell(a.To), true
	}
	if a.Facing != nil {
		act.Facing = toCell(a.Facing)
	}
	return act
}

func (s *Server) dispatch(req *request) obj {
	switch req.Op {
	case "hello":
		return obj{"protocol": Protocol}
	case "data":
		return s.dataJSON()
	case "picks_check":
		budget := s.data.Points
		if req.Budget != nil && *req.Budget > 0 {
			budget = *req.Budget
		}
		return obj{"cost": s.data.PicksCost(req.Def, req.Nodes), "error": s.data.ValidateTraining(req.Def, req.Nodes, budget)}
	case "build":
		party := req.Party
		if party == nil && req.ChironJoined && (req.Battle == "1-4" || req.Battle == "1-5" || req.Battle == "2-1") {
			party = []rules.PartyMember{{ID: "chiron", Def: "chiron"}}
		}
		st, err := s.data.Muster(req.Battle, rules.Muster{Party: party, Bench: req.Bench, Picks: req.Picks,
			Loadout: req.Loadout, Mods: req.Mods, Items: req.Items, Reward: req.Reward, Support: req.Support})
		if err != nil {
			return fail("%v", err)
		}
		s.nextID++
		s.sessions[s.nextID] = st
		s.order = append(s.order, s.nextID)
		for len(s.order) > maxSessions {
			delete(s.sessions, s.order[0])
			s.order = s.order[1:]
		}
		return obj{"sid": s.nextID, "state": stateJSON(st, true)}
	case "drop":
		delete(s.sessions, req.SID)
		return obj{}
	}

	st := s.sessions[req.SID]
	if st == nil {
		return fail("没有这场战斗（会话 %d）", req.SID)
	}
	unit := func() *rules.UnitState { return st.Unit(req.Unit) }
	switch req.Op {
	case "start":
		rules.StartBattle(st)
		return obj{"state": stateJSON(st, false)}
	case "validate":
		return obj{"error": rules.Validate(st, toAction(req.Action))}
	case "validate_many":
		errs := make([]string, len(req.Actions))
		for i, a := range req.Actions {
			errs[i] = rules.Validate(st, toAction(a))
		}
		return obj{"errors": errs}
	case "perform":
		o := rules.Perform(st, toAction(req.Action))
		return obj{"ok": o.OK, "error": o.Error, "events": eventsJSON(o.Events), "state": stateJSON(st, false)}
	case "preview":
		o := rules.Preview(st, toAction(req.Action))
		return obj{"ok": o.OK, "error": o.Error, "events": eventsJSON(o.Events)}
	case "end_phase":
		return obj{"events": eventsJSON(rules.EndPhase(st)), "state": stateJSON(st, false)}
	case "finish":
		u := unit()
		if u == nil {
			return fail("没有这个单位: %s", req.Unit)
		}
		again := rules.FinishActivation(st, u)
		return obj{"again": again, "state": stateJSON(st, false)}
	case "plan":
		u := unit()
		if u == nil {
			return fail("没有这个单位: %s", req.Unit)
		}
		return obj{"plan": planJSON(rules.PlanFor(st, u))}
	case "simulate":
		u := unit()
		if u == nil {
			return fail("没有这个单位: %s", req.Unit)
		}
		p, events := rules.Simulate(st, u)
		return obj{"plan": planJSON(p), "events": eventsJSON(events), "threat": cellsJSON(rules.ThreatCells(st, u))}
	case "rescue_preview":
		u := unit()
		if u == nil || u.DefID != "refugee" || !u.Alive || u.Hidden || st.Phase != rules.PhasePlayer {
			return fail("invalid rescue preview")
		}
		path, threats, escapes := rules.RescuePreview(st, u)
		return obj{"path": cellsJSON(path), "threats": threats, "escapes": escapes}
	case "threat":
		u := unit()
		if u == nil {
			return fail("没有这个单位: %s", req.Unit)
		}
		return obj{"cells": cellsJSON(rules.ThreatCells(st, u))}
	case "threat_all":
		// 一方全部在场单位的威胁范围的并集（按 T 显示的那一层）
		seen := map[rules.Cell]bool{}
		cells := []rules.Cell{}
		for _, e := range st.Living(rules.TeamEnemy) {
			for _, c := range rules.ThreatCells(st, e) {
				if !seen[c] {
					seen[c] = true
					cells = append(cells, c)
				}
			}
		}
		return obj{"cells": cellsJSON(cells)}
	case "cave_entrance":
		u := unit()
		if u == nil || st.Cave == nil {
			return obj{"entrance": ""}
		}
		return obj{"entrance": rules.CaveEntrance(st, u)}
	case "destinations":
		u := unit()
		if u == nil {
			return fail("没有这个单位: %s", req.Unit)
		}
		budget := -1
		if req.Budget != nil {
			budget = *req.Budget
		}
		reach := rules.Reachable(st, u, budget)
		out := [][3]int{}
		for _, c := range reach.Dests() {
			out = append(out, [3]int{c.X, c.Y, reach.Cost(c)})
		}
		return obj{"cells": out}
	case "leap_error":
		u := unit()
		if u == nil {
			return fail("没有这个单位: %s", req.Unit)
		}
		sk := u.Skill(req.Skill)
		if sk == nil {
			sk = s.data.Skill(req.Skill)
		}
		if sk != nil && sk.Carry > 0 {
			var to rules.Cell
			if req.Cell != nil {
				to = toCell(req.Cell)
			}
			return obj{"error": rules.CarryLandingError(st, u, to, sk)}
		}
		if sk == nil || !sk.HasLeap {
			return obj{"error": "bad landing"}
		}
		return obj{"error": rules.LeapLandingError(st, u, toCell(req.Cell), sk)}
	case "targeting":
		return targeting(st, req.Action)
	}
	return fail("不认识的请求: %s", req.Op)
}

// targeting 一次算出瞄准时界面要画的全部格子，省得客户端逐格来问：
//
//	landings —— 跳跃技能还没选落点时，可以落脚的锚点
//	in_range —— 技能的射程范围（只看距离和直线，画底色用）
//	valid    —— 现在真能指定的目标格（敌人的占地）
func targeting(st *rules.BattleState, pending *actionJSON) obj {
	out := obj{"landings": [][2]int{}, "in_range": [][2]int{}, "valid": [][2]int{}}
	if pending == nil {
		return out
	}
	u := st.Unit(pending.Unit)
	if u == nil {
		return out
	}
	g := st.Grid
	act := toAction(pending)
	var landings, inRange, valid []rules.Cell
	sk := u.Skill(pending.Skill)
	switch {
	case act.Type == rules.ActSkill && sk != nil && (sk.Blink > 0 || sk.Blast > 0 || sk.Support == "charge"):
		// 指定格子的招式：射程底色照常，可选的是每一个校验得过的格子。
		for y := 0; y < g.Depth; y++ {
			for x := 0; x < g.Width; x++ {
				c := rules.Cell{X: x, Y: y}
				dist := gap(u.Pos.X, u.Size, x) + gap(u.Pos.Y, u.Size, y)
				reach, near := sk.MaxRange, max(sk.MinRange, 1)
				if sk.Blink > 0 {
					reach, near = sk.Blink, 1
				}
				if sk.Support == "charge" {
					// 冲锋选的是方向：主角身边的四格。底色标出整条冲过去的路。
					reach, near = sk.MaxRange, 1
					if x != u.Pos.X && y != u.Pos.Y {
						dist = reach + 1
					}
				}
				if dist >= near && dist <= reach {
					inRange = append(inRange, c)
				}
				act.Target = c
				if rules.Validate(st, act) == "" {
					valid = append(valid, c)
				}
			}
		}
	case act.Type == rules.ActSkill && sk != nil && sk.Carry > 0 && !act.HasTo:
		for y := 0; y < g.Depth; y++ {
			for x := 0; x < g.Width; x++ {
				if c := (rules.Cell{X: x, Y: y}); rules.CarryLandingError(st, u, c, sk) == "" {
					landings = append(landings, c)
				}
			}
		}
	case act.Type == rules.ActSkill && sk != nil && sk.HasLeap && !act.HasTo:
		for y := 0; y < g.Depth; y++ {
			for x := 0; x < g.Width; x++ {
				if c := (rules.Cell{X: x, Y: y}); rules.LeapLandingError(st, u, c, sk) == "" {
					landings = append(landings, c)
				}
			}
		}
	default:
		origin := u.Pos
		if act.HasTo && (sk == nil || sk.Carry == 0) {
			origin = act.To // 驮行的落点是同伴去的地方，够不够得着仍然从主角算
		}
		if act.Type == rules.ActSkill && sk != nil && sk.HasMaxRange {
			minR := max(sk.MinRange, 1)
			if u.Traits.CannotAttackAdjacent && sk.Ranged {
				minR = max(sk.MinRange, 2)
			}
			for y := 0; y < g.Depth; y++ {
				for x := 0; x < g.Width; x++ {
					dx := gap(origin.X, u.Size, x)
					dy := gap(origin.Y, u.Size, y)
					dist := dx + dy
					if dist >= minR && dist <= sk.MaxRange && (!sk.Line || dx == 0 || dy == 0) {
						inRange = append(inRange, rules.Cell{X: x, Y: y})
					}
				}
			}
		}
		for _, e := range st.Units {
			if !e.Alive || e.Hidden {
				continue
			}
			act.Target = e.Pos
			if rules.Validate(st, act) == "" {
				valid = append(valid, e.Footprint(e.Pos)...)
			}
		}
		if act.Type == rules.ActSkill && sk != nil && rules.Kindles(sk) && !sk.HasLeap {
			// 带火的招式还能打空着的林地格。
			for y := 0; y < g.Depth; y++ {
				for x := 0; x < g.Width; x++ {
					c := rules.Cell{X: x, Y: y}
					if g.TerrainAt(c) != rules.Forest || st.UnitAt(c) != nil {
						continue
					}
					act.Target = c
					if rules.Validate(st, act) == "" {
						valid = append(valid, c)
					}
				}
			}
		}
	}
	out["landings"], out["in_range"], out["valid"] = cellsJSON(landings), cellsJSON(inRange), cellsJSON(valid)
	return out
}

// 占地 [a0, a0+size) 到坐标 b 在一条轴上的距离。
func gap(a0, size, b int) int {
	if b < a0 {
		return a0 - b
	}
	if b > a0+size-1 {
		return b - (a0 + size - 1)
	}
	return 0
}
