package rules_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rules"
)

func loadScenarioFile(t *testing.T, name string, dst any) {
	t.Helper()
	path := filepath.Join("..", "..", "..", "..", "tests", "scenarios", name)
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ler %s: %v", path, err)
	}
	if err := json.Unmarshal(raw, dst); err != nil {
		t.Fatalf("decodificar %s: %v", path, err)
	}
}

func TestConformance01GridGeneration(t *testing.T) {
	var scen struct {
		PRNGCases []struct {
			Seed     uint32   `json:"seed"`
			Sequence []uint32 `json:"sequence"`
		} `json:"prng_cases"`
		GridCases []struct {
			Seed           uint32 `json:"seed"`
			SpawnCount     int    `json:"spawn_count"`
			ExpectedGrid   string `json:"expected_grid"`
			ExpectedBlocks int    `json:"expected_blocks"`
		} `json:"grid_cases"`
	}
	loadScenarioFile(t, "01_grid_generation.json", &scen)

	for _, c := range scen.PRNGCases {
		rng := rules.NewPRNG(c.Seed)
		for i, want := range c.Sequence {
			if got := rng.NextU32(); got != want {
				t.Fatalf("PRNG seed=%d passo %d: got %d, want %d", c.Seed, i, got, want)
			}
		}
	}

	for _, c := range scen.GridCases {
		g := rules.GenerateGrid(c.Seed, c.SpawnCount)
		if got := g.CompactString(); got != c.ExpectedGrid {
			t.Fatalf("Grid seed=%d spawns=%d diverge do cenário compartilhado", c.Seed, c.SpawnCount)
		}
		if got := g.CountTiles(rules.TileBlock); got != c.ExpectedBlocks {
			t.Fatalf("Grid blocks seed=%d: got %d, want %d", c.Seed, got, c.ExpectedBlocks)
		}
	}
}

func TestConformance02Movement(t *testing.T) {
	var scen struct {
		Cases []struct {
			Name       string   `json:"name"`
			Seed       uint32   `json:"seed"`
			ClearCells [][2]int `json:"clear_cells"`
			BlockCells [][2]int `json:"block_cells"`
			StartX     int      `json:"start_x"`
			StartY     int      `json:"start_y"`
			Speed      int      `json:"speed"`
			Steps      []struct {
				Dir     string `json:"dir"`
				Ticks   int    `json:"ticks"`
				ExpectX int    `json:"expect_x"`
				ExpectY int    `json:"expect_y"`
			} `json:"steps"`
		} `json:"cases"`
	}
	loadScenarioFile(t, "02_movement.json", &scen)

	for _, c := range scen.Cases {
		g := rules.GenerateGrid(c.Seed, 4)
		for _, cell := range c.ClearCells {
			g.SetTile(cell[0], cell[1], rules.TileEmpty)
		}
		for _, cell := range c.BlockCells {
			g.SetTile(cell[0], cell[1], rules.TileBlock)
		}
		p := rules.NewPlayerState("p1", 0, rules.CellCoord{X: 1, Y: 1})
		p.X = c.StartX
		p.Y = c.StartY
		p.Speed = c.Speed

		for _, st := range c.Steps {
			p.Dir = st.Dir
			for i := 0; i < st.Ticks; i++ {
				rules.StepPlayer(p, g, nil)
			}
			if p.X != st.ExpectX || p.Y != st.ExpectY {
				t.Fatalf("%s: got (%d,%d), want (%d,%d)", c.Name, p.X, p.Y, st.ExpectX, st.ExpectY)
			}
		}
	}
}

func TestConformance03BombsAndExplosions(t *testing.T) {
	var scen struct {
		Cases []struct {
			Name       string   `json:"name"`
			Seed       uint32   `json:"seed"`
			ClearCells [][2]int `json:"clear_cells"`
			BlockCells [][2]int `json:"block_cells"`
			BombA      struct {
				Owner string `json:"owner"`
				CX    int    `json:"cx"`
				CY    int    `json:"cy"`
				Fuse  int    `json:"fuse"`
				Range int    `json:"range"`
			} `json:"bomb_a"`
			BombB struct {
				Owner string `json:"owner"`
				CX    int    `json:"cx"`
				CY    int    `json:"cy"`
				Fuse  int    `json:"fuse"`
				Range int    `json:"range"`
			} `json:"bomb_b"`
			TicksToRun         int   `json:"ticks_to_run"`
			ExpectDetonatedOrd []int `json:"expect_detonated_order"`
			ExpectCell51Tile   int   `json:"expect_cell_5_1_tile"`
		} `json:"cases"`
	}
	loadScenarioFile(t, "03_bombs_and_explosions.json", &scen)

	for _, c := range scen.Cases {
		sim := rules.NewWorldSim(c.Seed, []string{"p0", "p1"})
		sim.GetPlayer("p0").X, sim.GetPlayer("p0").Y = 13500, 11500
		sim.GetPlayer("p1").X, sim.GetPlayer("p1").Y = 1500, 11500
		for _, cell := range c.ClearCells {
			sim.Grid.SetTile(cell[0], cell[1], rules.TileEmpty)
		}
		for _, cell := range c.BlockCells {
			sim.Grid.SetTile(cell[0], cell[1], rules.TileBlock)
		}
		sim.Bombs = append(sim.Bombs,
			&rules.BombState{ID: 1, OwnerID: c.BombA.Owner, CX: c.BombA.CX, CY: c.BombA.CY, Fuse: c.BombA.Fuse, Range: c.BombA.Range, PassThroughIDs: map[string]bool{}},
			&rules.BombState{ID: 2, OwnerID: c.BombB.Owner, CX: c.BombB.CX, CY: c.BombB.CY, Fuse: c.BombB.Fuse, Range: c.BombB.Range, PassThroughIDs: map[string]bool{}},
		)

		var order []int
		for i := 0; i < c.TicksToRun; i++ {
			evs := sim.StepTick()
			for _, e := range evs {
				if e["k"] == "explosion" {
					order = append(order, e["bomb_id"].(int))
				}
			}
		}
		if !reflect.DeepEqual(order, c.ExpectDetonatedOrd) {
			t.Fatalf("%s: got order %v, want %v", c.Name, order, c.ExpectDetonatedOrd)
		}
		if got := int(sim.Grid.GetTile(5, 1)); got != c.ExpectCell51Tile {
			t.Fatalf("%s: tile (5,1) got %d, want %d", c.Name, got, c.ExpectCell51Tile)
		}
	}
}

func TestConformance04PowerUps(t *testing.T) {
	var scen struct {
		Cases []struct {
			Name                string `json:"name"`
			Seed                uint32 `json:"seed"`
			PlayerCell          [2]int `json:"player_cell"`
			ShieldKind          string `json:"shield_kind"`
			BombFuse            int    `json:"bomb_fuse"`
			TicksAfterExplosion int    `json:"ticks_after_explosion"`
			ExpectAlive         bool   `json:"expect_alive"`
			ExpectShieldTicks   int    `json:"expect_shield_ticks"`
		} `json:"cases"`
	}
	loadScenarioFile(t, "04_powerups.json", &scen)

	for _, c := range scen.Cases {
		sim := rules.NewWorldSim(c.Seed, []string{"p0", "p1"})
		p0 := sim.GetPlayer("p0")
		sim.PlacePowerUp(c.PlayerCell[0], c.PlayerCell[1], c.ShieldKind)
		sim.StepTick()
		sim.Bombs = append(sim.Bombs, &rules.BombState{
			ID: 1, OwnerID: "p1", CX: c.PlayerCell[0], CY: c.PlayerCell[1],
			Fuse: c.BombFuse, Range: 2, PassThroughIDs: map[string]bool{},
		})
		for i := 0; i < c.BombFuse+c.TicksAfterExplosion; i++ {
			sim.StepTick()
		}
		if p0.Alive != c.ExpectAlive {
			t.Fatalf("%s: Alive=%v, want %v", c.Name, p0.Alive, c.ExpectAlive)
		}
		if p0.ShieldTicks != c.ExpectShieldTicks {
			t.Fatalf("%s: ShieldTicks=%d, want %d", c.Name, p0.ShieldTicks, c.ExpectShieldTicks)
		}
	}
}
