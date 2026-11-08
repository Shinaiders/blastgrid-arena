package platform_test

import (
	"testing"

	"github.com/Shinaiders/blastgrid-arena/server/internal/platform"
)

func TestSteamValidateTicket(t *testing.T) {
	const validSteamID uint64 = 76561198000000001
	const appID uint32 = platform.DefaultSteamAppID

	// 1. Ticket válido
	ticket := platform.BuildMockTicket(validSteamID, appID)
	gotID, err := platform.ValidateTicket(ticket, appID)
	if err != nil {
		t.Fatalf("ValidateTicket válido falhou: %v", err)
	}
	if gotID != validSteamID {
		t.Fatalf("esperava steamID %d, obteve %d", validSteamID, gotID)
	}

	// 2. Ticket vazio
	if _, err := platform.ValidateTicket("", appID); err != platform.ErrEmptyTicket {
		t.Fatalf("esperava ErrEmptyTicket, obteve %v", err)
	}
	if _, err := platform.ValidateTicket("   ", appID); err != platform.ErrEmptyTicket {
		t.Fatalf("esperava ErrEmptyTicket para espaços, obteve %v", err)
	}

	// 3. Ticket malformado (hex inválido ou tamanho insuficiente)
	if _, err := platform.ValidateTicket("not_hex", appID); err != platform.ErrMalformedTicket {
		t.Fatalf("esperava ErrMalformedTicket para texto não-hex, obteve %v", err)
	}
	if _, err := platform.ValidateTicket("aabbcc", appID); err != platform.ErrMalformedTicket {
		t.Fatalf("esperava ErrMalformedTicket para tamanho < 16 bytes, obteve %v", err)
	}

	// SteamID == 0
	zeroIDTicket := platform.BuildMockTicket(0, appID)
	if _, err := platform.ValidateTicket(zeroIDTicket, appID); err != platform.ErrMalformedTicket {
		t.Fatalf("esperava ErrMalformedTicket para steamID zero, obteve %v", err)
	}

	// 4. AppID divergente
	diffAppTicket := platform.BuildMockTicket(validSteamID, 12345)
	if _, err := platform.ValidateTicket(diffAppTicket, appID); err != platform.ErrAppIDMismatch {
		t.Fatalf("esperava ErrAppIDMismatch, obteve %v", err)
	}

	// AppID esperado 0 aceita qualquer appID
	gotAnyApp, err := platform.ValidateTicket(diffAppTicket, 0)
	if err != nil || gotAnyApp != validSteamID {
		t.Fatalf("esperava sucesso com expectedAppID=0, obteve id=%d err=%v", gotAnyApp, err)
	}
}

func TestEvaluateAchievements(t *testing.T) {
	// Nenhuma conquista
	a0 := platform.EvaluateAchievements(false, 1, 10)
	if len(a0) != 0 {
		t.Fatalf("esperava 0 conquistas, obteve %v", a0)
	}

	// FIRST_WIN apenas
	a1 := platform.EvaluateAchievements(true, 2, 20)
	if len(a1) != 1 || a1[0] != "FIRST_WIN" {
		t.Fatalf("esperava [FIRST_WIN], obteve %v", a1)
	}

	// CHAIN_MASTER_3 apenas
	a2 := platform.EvaluateAchievements(false, 3, 20)
	if len(a2) != 1 || a2[0] != "CHAIN_MASTER_3" {
		t.Fatalf("esperava [CHAIN_MASTER_3], obteve %v", a2)
	}

	// COLLECTOR_50 apenas
	a3 := platform.EvaluateAchievements(false, 2, 50)
	if len(a3) != 1 || a3[0] != "COLLECTOR_50" {
		t.Fatalf("esperava [COLLECTOR_50], obteve %v", a3)
	}

	// Todas as conquistas juntas
	aAll := platform.EvaluateAchievements(true, 5, 99)
	if len(aAll) != 3 {
		t.Fatalf("esperava 3 conquistas, obteve %v", aAll)
	}
	expected := map[string]bool{"FIRST_WIN": true, "CHAIN_MASTER_3": true, "COLLECTOR_50": true}
	for _, a := range aAll {
		if !expected[a] {
			t.Fatalf("conquista inesperada: %s", a)
		}
	}
}
