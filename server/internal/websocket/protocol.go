// Package websocket implementa o codec do protocolo v1 (docs/NETWORK_PROTOCOL.md),
// proteção contra replay de seq e rate limiting por conexão.
package websocket

import (
	"encoding/json"
	"errors"
	"regexp"
	"sync"
	"time"
)

const (
	ProtocolVersion = 1
	SubprotocolV1   = "blastgrid.v1"
	MaxFrameBytes   = 4096

	CloseUnsupportedVersion = 4003
	CloseRateLimited        = 4004
)

var msgTypePattern = regexp.MustCompile(`^[a-z_.]{1,32}$`)

// Envelope é a estrutura de todas as mensagens do protocolo v1.
type Envelope struct {
	V    int            `json:"v"`
	T    string         `json:"t"`
	Seq  int64          `json:"seq"`
	Ack  int64          `json:"ack,omitempty"`
	Data map[string]any `json:"data"`
}

// ProtocolError classifica falhas de validação do envelope.
type ProtocolError struct {
	Code string
	Msg  string
}

func (e *ProtocolError) Error() string { return e.Code + ": " + e.Msg }

// DecodeEnvelope valida um frame de texto JSON segundo NETWORK_PROTOCOL.md §2.
func DecodeEnvelope(raw []byte) (Envelope, error) {
	if len(raw) == 0 || len(raw) > MaxFrameBytes {
		return Envelope{}, &ProtocolError{Code: "bad_message", Msg: "tamanho de frame inválido"}
	}
	var env Envelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return Envelope{}, &ProtocolError{Code: "bad_message", Msg: "JSON inválido"}
	}
	if env.V != ProtocolVersion {
		return Envelope{}, &ProtocolError{Code: "unsupported_version", Msg: "versão de protocolo não suportada"}
	}
	if !msgTypePattern.MatchString(env.T) {
		return Envelope{}, &ProtocolError{Code: "bad_message", Msg: "tipo de mensagem inválido"}
	}
	if env.Seq < 1 || env.Ack < 0 {
		return Envelope{}, &ProtocolError{Code: "bad_message", Msg: "seq/ack inválido"}
	}
	if env.Data == nil {
		return Envelope{}, &ProtocolError{Code: "bad_message", Msg: "campo data obrigatório"}
	}
	return env, nil
}

// EncodeEnvelope serializa um Envelope para JSON.
func EncodeEnvelope(env Envelope) ([]byte, error) {
	if env.V == 0 {
		env.V = ProtocolVersion
	}
	if env.Data == nil {
		env.Data = map[string]any{}
	}
	return json.Marshal(env)
}

// SeqTracker impõe que seq seja estritamente crescente (anti-replay, §9).
type SeqTracker struct {
	lastSeq int64
	replays int
}

// Accept retorna true se seq > lastSeq; caso contrário conta como replay.
func (s *SeqTracker) Accept(seq int64) bool {
	if seq <= s.lastSeq {
		s.replays++
		return false
	}
	s.lastSeq = seq
	return true
}

func (s *SeqTracker) LastSeq() int64 { return s.lastSeq }
func (s *SeqTracker) Replays() int   { return s.replays }

// RateLimiter implementa um token bucket (padrão: 40 msg/s, rajada 80 — §9).
type RateLimiter struct {
	mu     sync.Mutex
	rate   float64
	burst  float64
	tokens float64
	last   time.Time
}

func NewRateLimiter(ratePerSec, burst float64, now time.Time) *RateLimiter {
	return &RateLimiter{
		rate:   ratePerSec,
		burst:  burst,
		tokens: burst,
		last:   now,
	}
}

func (rl *RateLimiter) Allow(now time.Time) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	if elapsed := now.Sub(rl.last).Seconds(); elapsed > 0 {
		rl.tokens += elapsed * rl.rate
		if rl.tokens > rl.burst {
			rl.tokens = rl.burst
		}
		rl.last = now
	}
	if rl.tokens < 1.0 {
		return false
	}
	rl.tokens -= 1.0
	return true
}

func toIntVal(v any) (int, bool) {
	switch n := v.(type) {
	case int:
		return n, true
	case int64:
		return int(n), true
	case float64:
		return int(n), true
	default:
		return 0, false
	}
}

// ValidateInputData valida o payload de uma mensagem "input" (§5.4, §9).
func ValidateInputData(data map[string]any, serverTick int) (dir string, bomb bool, targetTick int, err error) {
	if rawDir, ok := data["dir"].(string); ok {
		switch rawDir {
		case "none", "up", "down", "left", "right":
			dir = rawDir
		default:
			return "", false, 0, errors.New("dir inválido")
		}
	} else {
		dx, okX := toIntVal(data["dir_x"])
		dy, okY := toIntVal(data["dir_y"])
		if okX || okY {
			if dx > 0 {
				dir = "right"
			} else if dx < 0 {
				dir = "left"
			} else if dy > 0 {
				dir = "down"
			} else if dy < 0 {
				dir = "up"
			} else {
				dir = "none"
			}
		} else {
			return "", false, 0, errors.New("dir ausente")
		}
	}

	rawBomb, ok := data["bomb"].(bool)
	if !ok {
		return "", false, 0, errors.New("bomb deve ser bool")
	}
	bomb = rawBomb

	t := serverTick
	if tickVal, ok := toIntVal(data["tick"]); ok {
		t = tickVal
	}
	// Janela: mais de 40 ticks no futuro é descartado (bad_tick); mais de 20 no passado aplica no atual.
	if t > serverTick+40 {
		return "", false, 0, &ProtocolError{Code: "bad_tick", Msg: "tick muito no futuro"}
	}
	if t < serverTick {
		t = serverTick
	}
	return dir, bomb, t, nil
}
