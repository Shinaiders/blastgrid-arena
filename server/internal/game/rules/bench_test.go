package rules_test

import (
	"testing"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rules"
)

func BenchmarkWorldSim8PlayersTick(b *testing.B) {
	ids := []string{"p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8"}
	dirs := []string{"up", "right", "down", "left", "none"}
	sim := rules.NewWorldSim(0xCAFEBABE, ids)
	sim.DurationTicks = 2400

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j, id := range ids {
			sim.SetInput(id, dirs[(i+j)%len(dirs)], (i+j)%7 == 0)
		}
		sim.StepTick()
		if sim.MatchOver {
			sim = rules.NewWorldSim(0xCAFEBABE+uint32(i), ids)
			sim.DurationTicks = 2400
		}
	}
}

func TestWorldSim8PlayersTickBudget(t *testing.T) {
	ids := []string{"p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8"}
	dirs := []string{"up", "right", "down", "left", "none"}
	sim := rules.NewWorldSim(0xCAFEBABE, ids)
	sim.DurationTicks = 2400

	const totalTicks = 2400
	start := time.Now()
	for tick := 0; tick < totalTicks; tick++ {
		for j, id := range ids {
			sim.SetInput(id, dirs[(tick+j)%len(dirs)], (tick+j)%8 == 0)
		}
		sim.StepTick()
	}
	elapsed := time.Since(start)
	avgTick := elapsed / totalTicks

	t.Logf("2400 ticks com 8 jogadores concluídos em %v (médio: %v por tick)", elapsed, avgTick)
	if avgTick >= 1*time.Millisecond {
		t.Fatalf("orçamento de CPU estourado: média de %v por tick (máximo 1ms)", avgTick)
	}
}
