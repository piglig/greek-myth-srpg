package rules

// ChapterReward travels with the party between battles. Divinity is campaign
// progression, separate from the attacker's divine damage stat: it is the number of
// relics the protagonist has taken, never raised by using one in battle. It sets his
// tier (see divinity.go). Powers are the divine techniques he chose, one per tier.
type ChapterReward struct {
	Charms        map[string]string `json:"charms,omitempty"`
	EquippedRelic string            `json:"equipped_relic"`
	Boon          string            `json:"boon"`
	Divinity      int               `json:"divinity"`
	Powers        []string          `json:"powers,omitempty"`
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
	if hero := s.Unit("hero"); hero != nil && reward.EquippedRelic == "lion_pelt" {
		hero.AddSkill(d.Skill("impervious_hide"))
	}
	if reward.Boon == "swift_boots" {
		for _, u := range s.Units {
			if u.Team == TeamPlayer {
				u.Move += 2
			}
		}
	}
}
