package main

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/persistence/pgtest"
)

// TestRunWithDatabase: sobe com BG_MIGRATE_ON_START, confere /readyz com o
// check "database", o subcomando healthcheck e o ciclo migrate status/down/up.
func TestRunWithDatabase(t *testing.T) {
	dbURL := pgtest.URL(t)
	env := map[string]string{
		"BG_HTTP_ADDR":        "127.0.0.1:0",
		"BG_SHUTDOWN_TIMEOUT": "2s",
		"BG_DATABASE_URL":     dbURL,
		"BG_MIGRATE_ON_START": "true",
	}
	getenv := func(k string) string { return env[k] }
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	logs := &syncBuffer{}
	listening := make(chan string, 1)
	done := make(chan error, 1)
	go func() { done <- run(ctx, getenv, logs, listening) }()

	var addr string
	select {
	case addr = <-listening:
	case err := <-done:
		t.Fatalf("run terminou cedo: %v\n%s", err, logs.String())
	case <-time.After(10 * time.Second):
		t.Fatal("servidor não abriu o socket")
	}

	resp, err := (&http.Client{Timeout: 3 * time.Second}).Get("http://" + addr + "/readyz")
	if err != nil {
		t.Fatal(err)
	}
	var body struct {
		Status string `json:"status"`
		Checks []struct {
			Name string `json:"name"`
			OK   bool   `json:"ok"`
		} `json:"checks"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&body)
	resp.Body.Close()
	if resp.StatusCode != 200 || body.Status != "ready" || len(body.Checks) != 1 || body.Checks[0].Name != "database" || !body.Checks[0].OK {
		t.Fatalf("/readyz inesperado: %d %+v", resp.StatusCode, body)
	}

	_, port, _ := net.SplitHostPort(addr)
	hcEnv := map[string]string{"BG_HTTP_ADDR": ":" + port}
	if err := dispatch(ctx, []string{"healthcheck"}, func(k string) string { return hcEnv[k] }, &syncBuffer{}); err != nil {
		t.Fatalf("healthcheck: %v", err)
	}

	cancel()
	if err := <-done; err != nil {
		t.Fatalf("run: %v", err)
	}
	if !strings.Contains(logs.String(), `"msg":"migrate: aplicada"`) {
		t.Errorf("BG_MIGRATE_ON_START não aplicou migrations:\n%s", logs.String())
	}

	// ciclo do subcomando migrate (sem BG_MIGRATE_ON_START)
	delete(env, "BG_MIGRATE_ON_START")
	bg := context.Background()
	status := func() string {
		out := &syncBuffer{}
		if err := dispatch(bg, []string{"migrate", "status"}, getenv, out); err != nil {
			t.Fatalf("migrate status: %v", err)
		}
		return out.String()
	}
	if s := status(); !strings.Contains(s, "0001  init") || strings.Contains(s, "pendente") {
		t.Fatalf("status após up:\n%s", s)
	}
	if err := dispatch(bg, []string{"migrate", "down", "1"}, getenv, &syncBuffer{}); err != nil {
		t.Fatalf("migrate down: %v", err)
	}
	if s := status(); !strings.Contains(s, "pendente") {
		t.Fatalf("status após down deveria ter pendente:\n%s", s)
	}
	if err := dispatch(bg, []string{"migrate", "up"}, getenv, &syncBuffer{}); err != nil {
		t.Fatalf("migrate up: %v", err)
	}
	if s := status(); strings.Contains(s, "pendente") {
		t.Fatalf("status após up final:\n%s", s)
	}
}

func TestRunDatabaseUnreachable(t *testing.T) {
	env := map[string]string{
		"BG_HTTP_ADDR":          "127.0.0.1:0",
		"BG_DATABASE_URL":       "postgres://u:p@127.0.0.1:1/db",
		"BG_DB_CONNECT_TIMEOUT": "1s",
	}
	err := run(context.Background(), func(k string) string { return env[k] }, &syncBuffer{}, nil)
	if err == nil || !strings.Contains(err.Error(), "conectar ao banco") {
		t.Fatalf("esperava erro de conexão, veio %v", err)
	}
}

func TestDispatchErrors(t *testing.T) {
	none := func(string) string { return "" }
	for _, args := range [][]string{{"voar"}, {"migrate"}, {"migrate", "up"}} {
		if err := dispatch(context.Background(), args, none, &syncBuffer{}); err == nil {
			t.Errorf("dispatch %v: esperava erro", args)
		}
	}
	env := map[string]string{"BG_DATABASE_URL": "postgres://u:p@127.0.0.1:1/db", "BG_DB_CONNECT_TIMEOUT": "1s"}
	if err := dispatch(context.Background(), []string{"migrate", "down", "zero"}, func(k string) string { return env[k] }, &syncBuffer{}); err == nil {
		t.Error("migrate down zero: esperava erro")
	}
	// healthcheck sem servidor escutando deve falhar
	hc := map[string]string{"BG_HTTP_ADDR": "127.0.0.1:1"}
	if err := dispatch(context.Background(), []string{"healthcheck"}, func(k string) string { return hc[k] }, &syncBuffer{}); err == nil {
		t.Error("healthcheck sem servidor: esperava erro")
	}
}
