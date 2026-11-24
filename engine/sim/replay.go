package sim

import (
	"srpg/bots"
	"srpg/rules"
)

// ReplayData 是一场带种子的战斗的逐步回放（工坊的回放视图读它）。
// Frames[0] 是开局；之后每一帧是一批事件发生后的局面。
type ReplayData struct {
	Battle string  `json:"battle"`
	Bot    string  `json:"bot"`
	Frames []Frame `json:"frames"`
	Result string  `json:"result"`
	Rounds int     `json:"rounds"`
	Seed   int     `json:"seed"`
}

type Frame struct {
	Actor string              `json:"actor"`
	Cave  CaveSnap            `json:"cave"`
	Lines []string            `json:"lines"`
	Round int                 `json:"round"`
	Units map[string]UnitSnap `json:"units"`
}

// CaveSnap 是洞穴的快照；没有洞穴的战斗写成 {}。
type CaveSnap struct {
	Boulders  []BoulderSnap  `json:"boulders"`
	Entrances []EntranceSnap `json:"entrances"`
}

func (c CaveSnap) MarshalJSON() ([]byte, error) {
	if c.Boulders == nil && c.Entrances == nil {
		return []byte("{}"), nil
	}
	type plain CaveSnap
	return marshalGD(plain(c))
}

type BoulderSnap struct {
	ID       string `json:"id"`
	Placed   bool   `json:"placed"`
	Pos      [2]int `json:"pos"`
	Progress int    `json:"progress"`
}

type EntranceSnap struct {
	Anchor [2]int `json:"anchor"`
	ID     string `json:"id"`
	Sealed bool   `json:"sealed"`
}

type UnitSnap struct {
	Alive      bool     `json:"alive"`
	Def        string   `json:"def"`
	Facing     string   `json:"facing"`
	Hidden     bool     `json:"hidden"`
	HP         int      `json:"hp"`
	MaxHP      int      `json:"max_hp"`
	Name       string   `json:"name"`
	Pos        [2]int   `json:"pos"`
	Size       int      `json:"size"`
	Stagger    int      `json:"stagger"`
	StaggerMax int      `json:"stagger_max"`
	Statuses   []string `json:"statuses"`
	Team       string   `json:"team"`
}

// JSON 返回回放的 JSON，与原版 replay.gd 写出的文件一致。
func (r *ReplayData) JSON() ([]byte, error) { return marshalGD(r) }

// ReplayOptions 是 ReplayWith 的完整选项。
type ReplayOptions struct {
	Battle, Bot string
	Seed        int
	DataDir     string
	TablesDir   string
	Sets        []string
	Picks       map[string][]string
	MaxRounds   int
}

// Replay 重放一场战斗，记录每一步。
func Replay(battle, bot string, seed int, dataDir string) (*ReplayData, error) {
	return ReplayWith(ReplayOptions{Battle: battle, Bot: bot, Seed: seed, DataDir: dataDir})
}

func ReplayWith(o ReplayOptions) (*ReplayData, error) {
	data, err := rules.LoadData(rules.DataOptions{Root: o.TablesDir, Overlay: o.DataDir, Sets: o.Sets})
	if err != nil {
		return nil, err
	}
	prof, err := bots.ProfileByName(o.Bot)
	if err != nil {
		return nil, err
	}
	picks := o.Picks
	if picks == nil {
		picks = data.DefaultPicks()
	}
	start, err := data.Build(o.Battle, picks)
	if err != nil {
		return nil, err
	}
	out := &ReplayData{Battle: o.Battle, Bot: o.Bot, Seed: o.Seed}
	out.Frames = append(out.Frames, Frame{Round: 1, Lines: []string{}, Units: snapshot(start), Cave: caveSnap(start)})
	hook := func(s *rules.BattleState, events []rules.Event, actor string) {
		if len(events) == 0 {
			return
		}
		lines := rules.Describe(s, events)
		if len(lines) == 0 {
			return
		}
		out.Frames = append(out.Frames, Frame{Round: s.Round, Actor: actor, Lines: lines, Units: snapshot(s), Cave: caveSnap(s)})
	}
	rec, err := RunBattle(data, o.Battle, picks, prof, o.Seed, o.MaxRounds, hook)
	if err != nil {
		return nil, err
	}
	out.Result, out.Rounds = rec.Result, rec.Rounds
	return out, nil
}

func snapshot(s *rules.BattleState) map[string]UnitSnap {
	out := make(map[string]UnitSnap, len(s.Units))
	for _, u := range s.Units {
		team := "neutral"
		switch u.Team {
		case rules.TeamPlayer:
			team = "player"
		case rules.TeamEnemy:
			team = "enemy"
		}
		out[u.ID] = UnitSnap{Def: u.DefID, Name: u.Name, Team: team, Pos: xy(u.Pos), Size: u.Size,
			HP: max(u.HP, 0), MaxHP: u.MaxHP, Facing: facingLetter(u.Facing), Alive: u.Alive, Hidden: u.Hidden,
			Statuses: u.StatusNames(), Stagger: u.Stagger,
			StaggerMax: u.StaggerMax}
	}
	return out
}

func caveSnap(s *rules.BattleState) CaveSnap {
	if s.Cave == nil {
		return CaveSnap{}
	}
	c := CaveSnap{Boulders: []BoulderSnap{}, Entrances: []EntranceSnap{}}
	for _, e := range s.Cave.Entrances {
		c.Entrances = append(c.Entrances, EntranceSnap{ID: e.ID, Anchor: xy(e.Anchor), Sealed: e.Sealed})
	}
	for _, b := range s.Cave.Boulders {
		c.Boulders = append(c.Boulders, BoulderSnap{ID: b.ID, Pos: xy(b.Pos), Placed: b.Placed, Progress: b.Progress})
	}
	return c
}

func facingLetter(v rules.Cell) string {
	switch v {
	case rules.North:
		return "N"
	case rules.East:
		return "E"
	case rules.West:
		return "W"
	}
	return "S"
}
