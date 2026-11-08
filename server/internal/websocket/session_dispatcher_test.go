package websocket_test

import (
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/auth"
	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rooms"
	"github.com/Shinaiders/blastgrid-arena/server/internal/websocket"
)

func TestServeHTTPHandshakeRFC6455(t *testing.T) {
	now := time.Now()
	authSvc := auth.NewService("test-secret", time.Hour)
	roomMgr := rooms.NewManager()
	disp := websocket.NewDispatcher(authSvc, roomMgr)

	// 1. Método HTTP != GET -> 405 Method Not Allowed
	reqPost := httptest.NewRequest(http.MethodPost, "/ws", nil)
	recPost := httptest.NewRecorder()
	disp.ServeHTTP(recPost, reqPost)
	if recPost.Code != http.StatusMethodNotAllowed {
		t.Fatalf("esperava 405 Method Not Allowed para POST, obteve %d", recPost.Code)
	}

	// 2. Sem subprotocolo blastgrid.v1 -> HTTP 400
	reqNoProto := httptest.NewRequest(http.MethodGet, "/ws", nil)
	reqNoProto.Header.Set("Upgrade", "websocket")
	reqNoProto.Header.Set("Connection", "Upgrade")
	reqNoProto.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	recNoProto := httptest.NewRecorder()
	disp.ServeHTTP(recNoProto, reqNoProto)
	if recNoProto.Code != http.StatusBadRequest {
		t.Fatalf("esperava 400 sem subprotocolo, obteve %d", recNoProto.Code)
	}

	// 3. Sem cabeçalhos Upgrade websocket -> HTTP 400
	reqNoUpgrade := httptest.NewRequest(http.MethodGet, "/ws", nil)
	reqNoUpgrade.Header.Set("Sec-WebSocket-Protocol", websocket.SubprotocolV1)
	reqNoUpgrade.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	recNoUpgrade := httptest.NewRecorder()
	disp.ServeHTTP(recNoUpgrade, reqNoUpgrade)
	if recNoUpgrade.Code != http.StatusBadRequest {
		t.Fatalf("esperava 400 sem Upgrade websocket, obteve %d", recNoUpgrade.Code)
	}

	// 4. Sec-WebSocket-Version incompatível -> HTTP 400
	reqBadVer := httptest.NewRequest(http.MethodGet, "/ws", nil)
	reqBadVer.Header.Set("Upgrade", "websocket")
	reqBadVer.Header.Set("Connection", "Upgrade")
	reqBadVer.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	reqBadVer.Header.Set("Sec-WebSocket-Protocol", websocket.SubprotocolV1)
	reqBadVer.Header.Set("Sec-WebSocket-Version", "12")
	recBadVer := httptest.NewRecorder()
	disp.ServeHTTP(recBadVer, reqBadVer)
	if recBadVer.Code != http.StatusBadRequest {
		t.Fatalf("esperava 400 para Sec-WebSocket-Version != 13, obteve %d", recBadVer.Code)
	}

	// 5. Cálculo de computeAcceptKey e handshake completo válido
	const sampleKey = "dGhlIHNhbXBsZSBub25jZQ=="
	wantAccept := "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
	if got := websocket.ComputeAcceptKey(sampleKey); got != wantAccept {
		t.Fatalf("computeAcceptKey esperado %q, obteve %q", wantAccept, got)
	}

	reqOK := httptest.NewRequest(http.MethodGet, "/ws", nil)
	reqOK.Header.Set("Upgrade", "websocket")
	reqOK.Header.Set("Connection", "Upgrade")
	reqOK.Header.Set("Sec-WebSocket-Key", sampleKey)
	reqOK.Header.Set("Sec-WebSocket-Version", "13")
	reqOK.Header.Set("Sec-WebSocket-Protocol", websocket.SubprotocolV1)
	recOK := httptest.NewRecorder()
	disp.ServeHTTP(recOK, reqOK)
	if recOK.Code != http.StatusSwitchingProtocols {
		t.Fatalf("esperava 101 Switching Protocols, obteve %d", recOK.Code)
	}
	if got := recOK.Header().Get("Sec-WebSocket-Accept"); got != wantAccept {
		t.Fatalf("Sec-WebSocket-Accept esperado %q, obtido %q", wantAccept, got)
	}
	if got := recOK.Header().Get("Sec-WebSocket-Protocol"); got != websocket.SubprotocolV1 {
		t.Fatalf("Sec-WebSocket-Protocol esperado %q, obtido %q", websocket.SubprotocolV1, got)
	}
	_ = now
}

func TestDispatcherFullFlowNetPipeHandleLoop(t *testing.T) {
	now := time.Now()
	authSvc := auth.NewService("test-secret-pipe", 2*time.Hour)
	roomMgr := rooms.NewManager()

	acc, tok, err := authSvc.CreateGuest("NetPipeHero", now)
	if err != nil {
		t.Fatalf("CreateGuest: %v", err)
	}

	disp := websocket.NewDispatcher(authSvc, roomMgr)

	clientConn, serverConn := net.Pipe()
	defer clientConn.Close()
	go func() {
		_ = disp.HandleLoop(serverConn)
	}()

	sendEnv := func(c net.Conn, env websocket.Envelope) {
		raw, err := websocket.EncodeEnvelope(env)
		if err != nil {
			t.Fatalf("EncodeEnvelope: %v", err)
		}
		if err := websocket.WriteWSFrame(c, raw, true); err != nil {
			t.Fatalf("WriteWSFrame: %v", err)
		}
	}

	recvEnv := func(c net.Conn) websocket.Envelope {
		raw, err := websocket.ReadWSFrame(c)
		if err != nil {
			t.Fatalf("ReadWSFrame: %v", err)
		}
		env, err := websocket.DecodeEnvelope(raw)
		if err != nil {
			t.Fatalf("DecodeEnvelope: %v", err)
		}
		return env
	}

	// 1. hello -> recebe welcome (session_id, user_id, tick_rate: 20)
	sendEnv(clientConn, websocket.Envelope{
		V: 1, T: "hello", Seq: 1, Data: map[string]any{
			"access_token": tok,
			"client": map[string]any{
				"platform": "web",
				"version":  "1.0.0",
			},
		},
	})
	welcomeEnv := recvEnv(clientConn)
	if welcomeEnv.T != "welcome" {
		t.Fatalf("esperava 'welcome', obteve %q (%+v)", welcomeEnv.T, welcomeEnv.Data)
	}
	if welcomeEnv.Data["session_id"] == "" || welcomeEnv.Data["session_id"] == nil {
		t.Fatalf("session_id vazio no welcome: %+v", welcomeEnv.Data)
	}
	if welcomeEnv.Data["user_id"] != acc.ID {
		t.Fatalf("user_id esperado %s, veio %v", acc.ID, welcomeEnv.Data["user_id"])
	}
	tickRate, ok := welcomeEnv.Data["tick_rate"].(float64)
	if !ok || int(tickRate) != 20 {
		t.Fatalf("tick_rate esperado 20, veio %v", welcomeEnv.Data["tick_rate"])
	}
	resumeToken, _ := welcomeEnv.Data["resume_token"].(string)
	if resumeToken == "" {
		t.Fatalf("resume_token ausente no welcome: %+v", welcomeEnv.Data)
	}

	// 2. ping -> recebe pong ecoando client_time_ms e server_time_ms
	const testClientTime = 42000.0
	sendEnv(clientConn, websocket.Envelope{
		V: 1, T: "ping", Seq: 2, Data: map[string]any{
			"client_time_ms": testClientTime,
		},
	})
	pongEnv := recvEnv(clientConn)
	if pongEnv.T != "pong" {
		t.Fatalf("esperava 'pong', obteve %q", pongEnv.T)
	}
	if pongEnv.Data["client_time_ms"] != testClientTime {
		t.Fatalf("client_time_ms esperado %v, veio %v", testClientTime, pongEnv.Data["client_time_ms"])
	}
	if pongEnv.Data["server_time_ms"] == nil {
		t.Fatal("server_time_ms ausente no pong")
	}

	// 3. room.create (max_players: 4) -> recebe room.state com code e status: "lobby"
	sendEnv(clientConn, websocket.Envelope{
		V: 1, T: "room.create", Seq: 3, Data: map[string]any{
			"max_players": float64(4),
			"mode":        "ffa",
		},
	})
	roomCreateEnv := recvEnv(clientConn)
	if roomCreateEnv.T != "room.state" {
		t.Fatalf("esperava 'room.state', obteve %q", roomCreateEnv.T)
	}
	roomID, _ := roomCreateEnv.Data["room_id"].(string)
	if roomID == "" {
		t.Fatalf("room_id vazio no room.state: %+v", roomCreateEnv.Data)
	}
	roomCode, _ := roomCreateEnv.Data["code"].(string)
	if roomCode == "" {
		t.Fatalf("code vazio no room.state: %+v", roomCreateEnv.Data)
	}
	roomStatus, _ := roomCreateEnv.Data["status"].(string)
	if roomStatus != "lobby" {
		t.Fatalf("status esperado 'lobby', obteve %q", roomStatus)
	}

	// 4. room.ready (ready: true) -> inicia a partida e envia match.start (seed, grid, players) + state inicial (full: true)
	sendEnv(clientConn, websocket.Envelope{
		V: 1, T: "room.ready", Seq: 4, Data: map[string]any{
			"ready":     true,
			"character": "sparky_a",
			"skin":      "sparky_a_default",
		},
	})
	// Primeiro envelope: room.state atualizado
	readyRoomState := recvEnv(clientConn)
	if readyRoomState.T != "room.state" {
		t.Fatalf("esperava 'room.state' após ready, obteve %q", readyRoomState.T)
	}

	// Segundo envelope: match.start
	matchStart := recvEnv(clientConn)
	if matchStart.T != "match.start" {
		t.Fatalf("esperava 'match.start', obteve %q", matchStart.T)
	}
	if matchStart.Data["seed"] == nil {
		t.Fatal("seed ausente em match.start")
	}
	gridStr, ok := matchStart.Data["grid"].(string)
	if !ok || len(gridStr) == 0 {
		t.Fatalf("grid ausente ou vazio em match.start: %v", matchStart.Data["grid"])
	}
	if matchStart.Data["players"] == nil {
		t.Fatal("players ausente em match.start")
	}

	// Terceiro envelope: state inicial (full: true)
	initState := recvEnv(clientConn)
	if initState.T != "state" {
		t.Fatalf("esperava 'state' inicial, obteve %q", initState.T)
	}
	if initState.Data["full"] != true {
		t.Fatalf("esperava full: true no state inicial, veio %v", initState.Data["full"])
	}

	// 5. input (dir_x: 1, dir_y: 0, bomb: true) + chamada a d.StepRoom(roomID, time.Now()) -> envia state com snapshot atualizado
	sendEnv(clientConn, websocket.Envelope{
		V: 1, T: "input", Seq: 5, Data: map[string]any{
			"dir_x": float64(1),
			"dir_y": float64(0),
			"bomb":  true,
		},
	})
	// Dá 1 tick no servidor, que despacha o envelope "state" via d.conn
	stepEnvs, err := disp.StepRoom(roomID, time.Now())
	if err != nil {
		t.Fatalf("StepRoom erro: %v", err)
	}
	if len(stepEnvs) == 0 || stepEnvs[0].T != "state" {
		t.Fatalf("StepRoom esperava envelope state, obteve %+v", stepEnvs)
	}

	updatedState := recvEnv(clientConn)
	if updatedState.T != "state" {
		t.Fatalf("esperava 'state' via net.Pipe após StepRoom, obteve %q", updatedState.T)
	}
	if updatedState.Data["tick"] == nil {
		t.Fatal("tick ausente no state atualizado")
	}

	// 6. resume com room_id e resume_token em nova conexão net.Pipe() -> recebe welcome + state (full: true)
	_ = clientConn.Close()

	client2, server2 := net.Pipe()
	defer client2.Close()
	disp2 := websocket.NewDispatcher(authSvc, roomMgr)
	go func() {
		_ = disp2.HandleLoop(server2)
	}()

	sendEnv(client2, websocket.Envelope{
		V: 1, T: "resume", Seq: 1, Data: map[string]any{
			"room_id":      roomID,
			"resume_token": resumeToken,
		},
	})

	resumeWelcome := recvEnv(client2)
	if resumeWelcome.T != "welcome" {
		t.Fatalf("esperava 'welcome' após resume, obteve %q", resumeWelcome.T)
	}
	resumeState := recvEnv(client2)
	if resumeState.T != "state" {
		t.Fatalf("esperava 'state' após resume, obteve %q", resumeState.T)
	}
	if resumeState.Data["full"] != true {
		t.Fatalf("esperava full: true no state do resume, obteve %v", resumeState.Data["full"])
	}

	// 7. Teste de anti-replay: seq repetido retorna error com code: "bad_seq"
	sendEnv(client2, websocket.Envelope{
		V: 1, T: "ping", Seq: 1, Data: map[string]any{
			"client_time_ms": float64(999),
		},
	})
	replayErr := recvEnv(client2)
	if replayErr.T != "error" {
		t.Fatalf("esperava envelope 'error' para replay de seq=1, obteve %q", replayErr.T)
	}
	if replayErr.Data["code"] != "bad_seq" {
		t.Fatalf("esperava code 'bad_seq', obteve %v", replayErr.Data["code"])
	}
}

func TestSessionDispatcherResumeAndMatchEnd(t *testing.T) {
	now := time.Now()
	authSvc := auth.NewService("test-secret", time.Hour)
	roomMgr := rooms.NewManager()

	acc1, tok1, _ := authSvc.CreateGuest("Alpha", now)
	acc2, tok2, _ := authSvc.CreateGuest("Bravo", now)

	room := roomMgr.CreateRoom(acc1.ID, acc1.DisplayName, "web", "ffa", 2, false)
	_, part2, _ := roomMgr.JoinRoom(room.ID, acc2.ID, acc2.DisplayName, "linux")
	_, _, _ = roomMgr.SetReady(room.ID, acc1.ID, true, "sparky_a", "sparky_a_default", 77)
	_, _, _ = roomMgr.SetReady(room.ID, acc2.ID, true, "sparky_b", "sparky_b_default", 77)

	// Reconecta part2 via resume em nova sessão
	s2 := websocket.NewDispatcher(authSvc, roomMgr)
	resOut := s2.Dispatch(websocket.Envelope{
		V: 1, T: "resume", Seq: 10, Data: map[string]any{"resume_token": part2.ResumeToken},
	}, now)
	if len(resOut) != 2 || resOut[0].T != "welcome" || resOut[1].T != "state" || resOut[1].Data["full"] != true {
		t.Fatalf("resume durante partida deve retornar welcome + state(full=true), obteve %+v", resOut)
	}

	// Força fim de partida eliminando adversário
	st2 := room.World.GetPlayer(acc2.ID)
	st2.Alive = false

	endOut, err := s2.StepRoom(room.ID, time.Now())
	if err != nil || len(endOut) != 2 || endOut[0].T != "state" || endOut[1].T != "match.end" {
		t.Fatalf("esperava state + match.end ao terminar partida, obteve %+v err=%v", endOut, err)
	}
	if endOut[1].Data["winner"] != acc1.ID {
		t.Fatalf("esperava winner=%s, obteve %v", acc1.ID, endOut[1].Data["winner"])
	}
	_ = tok1
	_ = tok2
}
