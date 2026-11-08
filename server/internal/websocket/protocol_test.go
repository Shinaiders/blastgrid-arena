package websocket_test

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/websocket"
)

func TestEnvelopeFixtures(t *testing.T) {
	path := filepath.Join("..", "..", "..", "tests", "protocol", "01_envelope.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ler fixture: %v", err)
	}
	var fx struct {
		ValidMessages []struct {
			Raw       string `json:"raw"`
			ExpectT   string `json:"expect_t"`
			ExpectSeq int64  `json:"expect_seq"`
			ExpectAck int64  `json:"expect_ack"`
		} `json:"valid_messages"`
		InvalidMessages []struct {
			Raw        string `json:"raw"`
			ExpectCode string `json:"expect_code"`
		} `json:"invalid_messages"`
	}
	if err := json.Unmarshal(raw, &fx); err != nil {
		t.Fatalf("unmarshal fixture: %v", err)
	}

	for _, m := range fx.ValidMessages {
		env, err := websocket.DecodeEnvelope([]byte(m.Raw))
		if err != nil {
			t.Fatalf("esperava válido para %s, erro: %v", m.Raw, err)
		}
		if env.T != m.ExpectT || env.Seq != m.ExpectSeq || env.Ack != m.ExpectAck {
			t.Fatalf("envelope inesperado: %+v", env)
		}
	}

	for _, m := range fx.InvalidMessages {
		_, err := websocket.DecodeEnvelope([]byte(m.Raw))
		if err == nil {
			t.Fatalf("esperava erro para %s", m.Raw)
		}
		var perr *websocket.ProtocolError
		if !errors.As(err, &perr) || perr.Code != m.ExpectCode {
			t.Fatalf("código esperado %q, obtido %v", m.ExpectCode, err)
		}
	}
}

func TestSeqTrackerReplayProtection(t *testing.T) {
	var st websocket.SeqTracker
	if !st.Accept(1) || !st.Accept(2) || !st.Accept(5) {
		t.Fatal("sequência crescente deveria ser aceita")
	}
	if st.Accept(5) || st.Accept(3) {
		t.Fatal("replay ou seq antigo deveria ser rejeitado")
	}
	if st.Replays() != 2 {
		t.Fatalf("esperava 2 replays contados, obteve %d", st.Replays())
	}
}

func TestRateLimiterTokenBucket(t *testing.T) {
	t0 := time.Now()
	rl := websocket.NewRateLimiter(40, 80, t0)
	for i := 0; i < 80; i++ {
		if !rl.Allow(t0) {
			t.Fatalf("mensagem %d dentro da rajada 80 foi bloqueada", i)
		}
	}
	if rl.Allow(t0) {
		t.Fatal("mensagem 81 no mesmo instante deveria sofrer rate limit")
	}
	// Após 50 ms a 40 msg/s recarrega 2 tokens
	t1 := t0.Add(50 * time.Millisecond)
	if !rl.Allow(t1) || !rl.Allow(t1) {
		t.Fatal("deveria permitir 2 mensagens após 50 ms")
	}
	if rl.Allow(t1) {
		t.Fatal("3ª mensagem após 50 ms deveria bloquear")
	}
}
