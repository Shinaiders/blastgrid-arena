package rules

import "strings"

const (
	DefaultCols = 15
	DefaultRows = 13
)

// Tile representa o tipo de célula do grid (GDD §3).
type Tile int

const (
	TileEmpty Tile = 0
	TileWall  Tile = 1
	TileBlock Tile = 2
)

// CellCoord identifica uma célula (cx, cy).
type CellCoord struct {
	X int
	Y int
}

// Spawns para até 8 jogadores (slots 0..3 = cantos; slots 4..7 = bordas).
var Spawns = []CellCoord{
	{1, 1},
	{13, 1},
	{1, 11},
	{13, 11},
	{7, 1},
	{7, 11},
	{1, 6},
	{13, 6},
}

// SpawnSafeZones define a zona segura em "L" (3 células fora de pilares) por slot.
var SpawnSafeZones = [][]CellCoord{
	{{1, 1}, {2, 1}, {1, 2}},
	{{13, 1}, {12, 1}, {13, 2}},
	{{1, 11}, {2, 11}, {1, 10}},
	{{13, 11}, {12, 11}, {13, 10}},
	{{7, 1}, {6, 1}, {7, 2}},
	{{7, 11}, {8, 11}, {7, 10}},
	{{1, 6}, {1, 5}, {2, 5}},
	{{13, 6}, {13, 7}, {12, 7}},
}

// Grid armazena o mapa 2D da arena.
type Grid struct {
	Cols  int
	Rows  int
	Cells []Tile
}

// NewGrid cria um grid vazio (TileEmpty) de dimensões c×r.
func NewGrid(c, r int) *Grid {
	return &Grid{
		Cols:  c,
		Rows:  r,
		Cells: make([]Tile, c*r),
	}
}

// GenerateGrid gera um mapa determinístico a partir de seed e spawnCount (4 ou 8).
func GenerateGrid(seed uint32, spawnCount int) *Grid {
	g := NewGrid(DefaultCols, DefaultRows)
	rng := NewPRNG(seed)
	densityPct := 55 + int(rng.NextBound(16)) // 55..70 inclusive

	activeSpawns := 4
	if spawnCount > 4 {
		activeSpawns = 8
	}
	safeMap := make(map[int]bool, activeSpawns*3)
	for s := 0; s < activeSpawns && s < len(SpawnSafeZones); s++ {
		for _, pt := range SpawnSafeZones[s] {
			safeMap[pt.Y*g.Cols+pt.X] = true
		}
	}

	candidates := make([]int, 0, g.Cols*g.Rows)
	for cy := 0; cy < g.Rows; cy++ {
		for cx := 0; cx < g.Cols; cx++ {
			idx := cy*g.Cols + cx
			if cx == 0 || cx == g.Cols-1 || cy == 0 || cy == g.Rows-1 {
				g.Cells[idx] = TileWall
			} else if cx%2 == 0 && cy%2 == 0 {
				g.Cells[idx] = TileWall
			} else if safeMap[idx] {
				g.Cells[idx] = TileEmpty
			} else {
				g.Cells[idx] = TileEmpty
				candidates = append(candidates, idx)
			}
		}
	}

	// Embaralhamento Fisher-Yates idêntico ao GDScript
	for i := len(candidates) - 1; i > 0; i-- {
		j := int(rng.NextBound(uint32(i + 1)))
		candidates[i], candidates[j] = candidates[j], candidates[i]
	}

	targetBlocks := (len(candidates) * densityPct) / 100
	for i := 0; i < targetBlocks; i++ {
		g.Cells[candidates[i]] = TileBlock
	}
	return g
}

// CompactString serializa o grid em 195 dígitos ('0', '1', '2').
func (g *Grid) CompactString() string {
	var b strings.Builder
	b.Grow(len(g.Cells))
	for _, t := range g.Cells {
		b.WriteByte(byte('0' + t))
	}
	return b.String()
}

// InBounds verifica se (cx, cy) pertence ao grid.
func (g *Grid) InBounds(cx, cy int) bool {
	return cx >= 0 && cx < g.Cols && cy >= 0 && cy < g.Rows
}

// GetTile retorna o tile em (cx, cy) ou TileWall se fora dos limites.
func (g *Grid) GetTile(cx, cy int) Tile {
	if !g.InBounds(cx, cy) {
		return TileWall
	}
	return g.Cells[cy*g.Cols+cx]
}

// SetTile altera o tile em (cx, cy).
func (g *Grid) SetTile(cx, cy int, t Tile) {
	if g.InBounds(cx, cy) {
		g.Cells[cy*g.Cols+cx] = t
	}
}

// IsSolidTile retorna true para WALL ou BLOCK.
func (g *Grid) IsSolidTile(cx, cy int) bool {
	t := g.GetTile(cx, cy)
	return t == TileWall || t == TileBlock
}

// CountTiles conta quantas células possuem o tipo informado.
func (g *Grid) CountTiles(t Tile) int {
	n := 0
	for _, v := range g.Cells {
		if v == t {
			n++
		}
	}
	return n
}
