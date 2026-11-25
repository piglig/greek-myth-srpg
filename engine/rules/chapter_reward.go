package rules

// ChapterReward travels with the party between battles. Divinity is campaign
// progression, separate from the attacker's divine damage stat: it is the number of
// relics the protagonist has taken, never raised by using one in battle. It sets his
// tier (see divinity.go). Powers are the divine techniques he chose, one per tier.
type ChapterReward struct {
	Charms        map[string]string `json:"charms,omitempty"`
	EquippedRelic string            `json:"equipped_relic"`
	// Worn 是这一场带上的圣物，不超过 RelicSlots(Divinity) 件。没给时按老办法只看 EquippedRelic。
	Worn []string `json:"relics_worn,omitempty"`
	Boon          string            `json:"boon"`
	Divinity      int               `json:"divinity"`
	Powers        []string          `json:"powers,omitempty"`
}

// RelicSlots 是拿到 relics 件圣物时的圣物栏数：1 栏起，第 2、4、6 件各加 1 栏。
func RelicSlots(relics int) int {
	return min(4, 1+max(0, relics)/2)
}

// Wears 表示主角这一场带着这件圣物。
func (r *ChapterReward) Wears(relic string) bool {
	if r.Worn == nil {
		return r.EquippedRelic == relic
	}
	for _, id := range r.Worn {
		if id == relic {
			return true
		}
	}
	return false
}

// relicSkills 是每件圣物的主动招式（已经做进规则的那几件）。
var relicSkills = map[string]string{"lion_pelt": "impervious_hide", "hydra_blood": "hydra_venom"}

// ValidateRelics 检查带上的圣物：都是认识的、不重复、不超过栏数。
func ValidateRelics(reward ChapterReward) string {
	if len(reward.Worn) > RelicSlots(reward.Divinity) {
		return "more relics than slots"
	}
	seen := map[string]bool{}
	for _, id := range reward.Worn {
		if _, ok := relicSkills[id]; !ok {
			return "unknown relic: " + id
		}
		if seen[id] {
			return "relic worn twice: " + id
		}
		seen[id] = true
	}
	return ""
}

func (s *BattleState) IsMarked(id string) bool {
	return id != "" && (s.MarkedID == id || s.PreviousMark == id)
}

func (s *BattleState) removeMark(id string) {
	if s.MarkedID == id {
		s.MarkedID = s.PreviousMark
		s.PreviousMark = ""
	} else if s.PreviousMark == id {
		s.PreviousMark = ""
	}
}

func (s *BattleState) setMark(id string) {
	if s.Reward.Boon == "moon_hunt" && id != s.MarkedID {
		s.PreviousMark = s.MarkedID
	}
	s.MarkedID = id
}

func (s *BattleState) EquipReward(d *Data, reward ChapterReward) {
	s.Reward = reward
	if u := s.Unit(reward.Charms["stone"]); u != nil {
		u.Move++
		u.Defense -= 2
	}
	if u := s.Unit(reward.Charms["wrist"]); u != nil {
		u.Move--
	}
	if u := s.Unit(reward.Charms["brooch"]); u != nil {
		u.Will += 2
		u.Move--
	}
	if u := s.Unit(reward.Charms["anklet"]); u != nil {
		u.Jump++
		u.Strength -= 2
	}
	if hero := s.Unit("hero"); hero != nil {
		for _, relic := range [...]string{"lion_pelt", "hydra_blood"} {
			if reward.Wears(relic) {
				hero.AddSkill(d.Skill(relicSkills[relic]))
			}
		}
	}
	if reward.Boon == "swift_boots" {
		for _, u := range s.Units {
			if u.Team == TeamPlayer {
				u.Move += 2
			}
		}
	}
}
