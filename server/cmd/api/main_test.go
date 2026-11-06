package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

type syncBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

// TestRunEndToEnd sobe o processo completo numa porta efêmera, consulta
// /healthz e /readyz por HTTP real e encerra via cancelamento de contexto
// (equivalente ao SIGTERM).
func TestRunEndToEnd(t *testing.T) {
	env := map[string]string{"BG_HTTP_ADDR": "127.0.0.1:0", "BG_SHUTDOWN_TIMEOUT": "2s"}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	logs := &syncBuffer{}
	listening := make(chan string, 1)
	done := make(chan error, 1)
	go func() { done <- run(ctx, func(k string) string { return env[k] }, logs, listening) }()

	var addr string
	select {
	case addr = <-listening:
	case err := <-done:
		t.Fatalf("run terminou cedo: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("servidor não abriu o socket")
	}

	client := &http.Client{Timeout: 2 * time.Second}
	for _, path := range []string{"/healthz", "/readyz"} {
		resp, err := client.Get("http://" + addr + path)
		if err != nil {
			t.Fatalf("GET %s: %v", path, err)
		}
		var body map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Errorf("GET %s: status %d %v", path, resp.StatusCode, body)
		}
		if resp.Header.Get("X-Request-ID") == "" {
			t.Errorf("GET %s: sem X-Request-ID", path)
		}
	}

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("graceful shutdown não terminou")
	}
	out := logs.String()
	for _, want := range []string{`"msg":"api: iniciando"`, `"msg":"api: encerrado"`} {
		if !strings.Contains(out, want) {
			t.Errorf("log sem %s:\n%s", want, out)
		}
	}
}

func TestRunInvalidConfig(t *testing.T) {
	env := map[string]string{"BG_LOG_LEVEL": "barulhento"}
	err := run(context.Background(), func(k string) string { return env[k] }, &syncBuffer{}, nil)
	if err == nil || !strings.Contains(err.Error(), "BG_LOG_LEVEL") {
		t.Fatalf("esperava erro de configuração, veio %v", err)
	}
}
