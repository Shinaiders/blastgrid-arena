package rooms_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rooms"
	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rules"
)

func TestRoom4PlayersMatchAndReconnect(t *testing.T) {
	mgr := rooms.NewManager()
	now := time.Now()

	// Cross-platform: web, windows, linux e macos na mesma sala
	platforms := []string{"web", "windows", "linux", "macos"}
	var room *rooms.Room
	var p0 *rooms.Participant
	for i := 0; i < 4; i++ {
		pid := fmt.Sprintf("u_%d", i+1)
		r, p, err := mgr.Matchmake(pid, "Player"+pid, platforms[i], "ffa", 4)
		if err != nil {
			t.Fatalf("Matchmake jogador %d: %v", i, err)
		}
		room = r
		if i == 0 {
			p0 = p
		}
	}
	if len(room.Players) != 4 {
		t.Fatalf("esperava 4 jogadores na sala, obteve %d", len(room.Players))
	}

	// Todos ficam ready -> inicia partida
	for i := 0; i < 4; i++ {
		pid := fmt.Sprintf("u_%d", i+1)
		_, started, err := mgr.SetReady(room.ID, pid, true, "sparky_a", "sparky_a_default", 42)
		if err != nil {
			t.Fatalf("SetReady %s: %v", pid, err)
		}
		if i == 3 && !started {
			t.Fatal("partida deveria iniciar quando o 4º jogador ficou ready")
		}
	}

	// Desconexão e reconexão dentro da janela de 30s
	if err := mgr.Disconnect(room.ID, p0.ID, now); err != nil {
		t.Fatalf("Disconnect: %v", err)
	}
	if _, _, err := mgr.Resume(p0.ResumeToken, now.Add(10*time.Second)); err != nil {
		t.Fatalf("Resume dentro da janela deveria funcionar: %v", err)
	}

	// Reconexão fora da janela (>30s) deve falhar
	_ = mgr.Disconnect(room.ID, p0.ID, now)
	if _, _, err := mgr.Resume(p0.ResumeToken, now.Add(35*time.Second)); err != rooms.ErrResumeFailed {
		t.Fatalf("Resume fora da janela deveria falhar, obteve: %v", err)
	}
	// Reconecta de volta dentro da janela para concluir a partida
	_ = mgr.Disconnect(room.ID, p0.ID, now)
	_, _, _ = mgr.Resume(p0.ResumeToken, now.Add(1*time.Second))

	// Simula inputs e eliminações para encerrar a partida e validar ranking
	if err := mgr.ApplyInput(room.ID, "u_1", 1, "right", true); err != nil {
		t.Fatalf("ApplyInput: %v", err)
	}
	// Elimina u_2, u_3 e u_4 na simulação para verificar o cálculo autoritativo de resultado/Elo
	for _, id := range []string{"u_2", "u_3", "u_4"} {
		st := room.World.GetPlayer(id)
		st.X, st.Y = 1500, 1500
	}
	room.World.GetPlayer("u_1").X, room.World.GetPlayer("u_1").Y = 13500, 11500
	room.World.Bombs = append(room.World.Bombs, &rules.BombState{
		ID: 99, OwnerID: "u_1", CX: 1, CY: 1, Fuse: 1, Range: 2, PassThroughIDs: map[string]bool{},
	})

	_, over, err := mgr.StepRoom(room.ID)
	if err != nil || !over {
		t.Fatalf("esperava fim de partida após explosão, over=%v err=%v", over, err)
	}
	if len(room.Results) != 4 {
		t.Fatalf("esperava 4 resultados, obteve %d", len(room.Results))
	}
	if room.Results[0].Player != "u_1" || room.Results[0].Place != 1 || room.Results[0].RatingAfter <= room.Results[0].RatingBefore {
		t.Fatalf("vencedor u_1 deveria ficar em 1º e ganhar rating: %+v", room.Results[0])
	}
}

func TestRoom8PlayersCapacity(t *testing.T) {
	mgr := rooms.NewManager()
	r := mgr.CreateRoom("u_1", "Host", "windows", "ffa", 8, true)
	if r.Code == "" {
		t.Fatal("sala privada deve ter código de convite")
	}
	for i := 2; i <= 8; i++ {
		pid := fmt.Sprintf("u_%d", i)
		if _, _, err := mgr.JoinRoom(r.Code, pid, "P"+pid, "web"); err != nil {
			t.Fatalf("JoinRoom jogador %d por código: %v", i, err)
		}
	}
	if _, _, err := mgr.JoinRoom(r.Code, "u_9", "Extra", "linux"); err != rooms.ErrRoomFull {
		t.Fatalf("9º jogador deveria receber ErrRoomFull, obteve %v", err)
	}
	for i := 1; i <= 8; i++ {
		pid := fmt.Sprintf("u_%d", i)
		_, _, _ = mgr.SetReady(r.ID, pid, true, "sparky_b", "sparky_b_default", 99)
	}
	if r.Status != rooms.StatusInMatch || len(r.World.Players) != 8 {
		t.Fatalf("sala de 8 jogadores deveria estar em partida com 8 spawns, status=%s", r.Status)
	}
}
