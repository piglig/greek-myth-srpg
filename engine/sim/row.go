// Package sim 无界面地打完整场战斗（我方机器人 vs 敌方 AI），产出指标记录和回放，
// 并用 goroutine 并行地批量模拟（11-balance-testing §5.1）。
package sim

import (
	"bytes"
	"encoding/json"
	"math"
	"strconv"
	"strings"
)

// Row 是一场战斗的指标记录，序列化后就是导出文件里的一行 JSON。
// 字段按键名排序，和原版 JSON.stringify（按键排序）的输出逐字节一致。
//
// Result: "win" | "loss_hero"（主角倒下）| "loss_wipe"（全灭）| "timeout"。
// 伤害记在行动者头上。
type Row struct {
	Battle      string                 `json:"battle"`
	Bot         string                 `json:"bot"`
	BreakRounds []int                  `json:"break_rounds"` // 首领被破势的回合
	Counts      map[string]int         `json:"counts"`
	DmgCells    map[string]int         `json:"dmg_cells"` // "x,y" -> 我方单位站在那里时承受的伤害
	DmgToEnemy  map[string]int         `json:"dmg_to_enemy"`
	DmgToPlayer map[string]int         `json:"dmg_to_player"`
	Falls       []Fall                 `json:"falls"` // 每次敌人坠落
	Kills       []Kill                 `json:"kills"` // 每个敌人倒下时的最后一击
	MS          int64                  `json:"ms"`
	PartyHPLeft GDFloat                `json:"party_hp_left"`
	Phase2Round int                    `json:"phase2_round"` // 首领第一次退回洞穴的回合（0 = 从未）
	Picks       map[string][]string    `json:"picks"`
	Result      string                 `json:"result"`
	Rounds      int                    `json:"rounds"`
	Seed        int                    `json:"seed"`
	Units       map[string]*UnitRecord `json:"units"`
	Win         bool                   `json:"win"`
}

type Fall struct {
	Def    string `json:"def"`
	From   [2]int `json:"from"`
	Levels int    `json:"levels"`
	Round  int    `json:"round"`
	To     [2]int `json:"to"`
}

type Kill struct {
	By     string `json:"by"`
	Def    string `json:"def"`
	Pos    [2]int `json:"pos"`
	Round  int    `json:"round"`
	Source string `json:"source"`
}

type UnitRecord struct {
	Alive bool   `json:"alive"`
	Dealt int    `json:"dealt"`
	Def   string `json:"def"`
	HP    int    `json:"hp"`
	MaxHP int    `json:"max_hp"`
	Taken int    `json:"taken"`
	Team  string `json:"team"`
}

// JSON 返回这一行的 JSON（不带换行）。
func (r *Row) JSON() ([]byte, error) { return marshalGD(r) }

// marshalGD 按原版 JSON.stringify 的写法序列化：键排序、不转义 HTML 字符。
func marshalGD(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimRight(buf.Bytes(), "\n"), nil
}

// GDFloat 是按 Godot 的 JSON.stringify 规则写出的浮点数：
// 约 15 位有效数字，去掉末尾的 0，整数值写成 "1.0"。
// 写法以 Windows 版 Godot 4.7 为准（基准文件就是在它上面生成的）。
type GDFloat float64

func (f GDFloat) MarshalJSON() ([]byte, error) {
	return []byte(formatGDFloat(float64(f))), nil
}

func formatGDFloat(v float64) string {
	if v == 0 {
		return "0.0"
	}
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return "null"
	}
	// 先取 17 位有效数字（Windows 版 Godot 的 printf 只算这么多位，之后的位都当 0）
	sci := strconv.FormatFloat(math.Abs(v), 'e', 16, 64)
	mant, expText, _ := strings.Cut(sci, "e")
	exp, _ := strconv.Atoi(expText)
	digits := mant[:1] + mant[2:]
	// 小数位数 = 14 − floor(log10|v|)，至少 1 位
	precision := min(max(1, 14-exp), 32)
	// 再在这串十进制数字上四舍五入到 precision 位小数（两次舍入，与引擎的输出一致）
	n := digits
	if shift := exp - 16 + precision; shift >= 0 {
		n += strings.Repeat("0", shift)
	} else if cut := len(digits) + shift; cut < 0 {
		n = "0"
	} else {
		n = "0" + digits[:cut]
		if digits[cut] >= '5' {
			b := []byte(n)
			for i := len(b) - 1; i >= 0; i-- {
				if b[i] != '9' {
					b[i]++
					break
				}
				b[i] = '0'
			}
			n = string(b)
		}
	}
	n = strings.TrimLeft(n, "0")
	if len(n) <= precision {
		n = strings.Repeat("0", precision-len(n)+1) + n
	}
	out := n[:len(n)-precision] + "." + strings.TrimRight(n[len(n)-precision:], "0")
	if strings.HasSuffix(out, ".") {
		out += "0"
	}
	if v < 0 {
		out = "-" + out
	}
	return out
}
