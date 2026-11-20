package rules

import "fmt"

// Grid 保存每格的高度和地形。格子是玩法的真相；画面只是叠在上面的表现。
type Grid struct {
	Width, Depth int
	heights      []int8
	terrain      []Terrain
	version      int // 每次改动加一，让移动缓存失效
}

var terrainChars = map[byte]Terrain{
	'.': Plain, 'f': Forest, 'w': Shallow, 'D': Deep, 's': Swamp, 'b': Burning, 'x': Styx,
}

func NewGrid(w, d, defaultHeight int) *Grid {
	g := &Grid{Width: w, Depth: d, heights: make([]int8, w*d), terrain: make([]Terrain, w*d)}
	for i := range g.heights {
		g.heights[i] = int8(clamp(defaultHeight, 0, MaxHeight))
	}
	return g
}

// GridFromRows 用高度数字行建图，例如 ["0012", "0012"]；地形行可选，字符见 terrainChars。
func GridFromRows(heightRows, terrainRows []string) (*Grid, error) {
	if len(heightRows) == 0 || len(heightRows[0]) == 0 {
		return nil, fmt.Errorf("地图没有高度行")
	}
	d, w := len(heightRows), len(heightRows[0])
	g := NewGrid(w, d, 0)
	for y, row := range heightRows {
		if len(row) != w {
			return nil, fmt.Errorf("第 %d 行高度长度不一致", y)
		}
		for x := 0; x < w; x++ {
			h := 0
			if row[x] >= '0' && row[x] <= '9' {
				h = int(row[x] - '0')
			}
			g.SetHeight(Cell{x, y}, h)
		}
	}
	for y, row := range terrainRows {
		for x := 0; x < len(row); x++ {
			c := Cell{x, y}
			if !g.InBounds(c) {
				return nil, fmt.Errorf("地形行超出地图范围 (%d, %d)", x, y)
			}
			g.SetTerrain(c, terrainChars[row[x]])
		}
	}
	return g, nil
}

func (g *Grid) InBounds(c Cell) bool {
	return c.X >= 0 && c.Y >= 0 && c.X < g.Width && c.Y < g.Depth
}

func (g *Grid) index(c Cell) int { return c.Y*g.Width + c.X }

func (g *Grid) HeightAt(c Cell) int { return int(g.heights[c.Y*g.Width+c.X]) }

func (g *Grid) SetHeight(c Cell, h int) {
	g.heights[g.index(c)] = int8(clamp(h, 0, MaxHeight))
	g.version++
}

func (g *Grid) TerrainAt(c Cell) Terrain { return g.terrain[c.Y*g.Width+c.X] }

func (g *Grid) SetTerrain(c Cell, t Terrain) {
	g.terrain[g.index(c)] = t
	g.version++
}

func (g *Grid) Copy() *Grid {
	n := &Grid{Width: g.Width, Depth: g.Depth}
	n.heights = append([]int8(nil), g.heights...)
	n.terrain = append([]Terrain(nil), g.terrain...)
	return n
}
