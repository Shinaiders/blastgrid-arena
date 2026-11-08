package websocket

import (
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/auth"
	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rooms"
	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rules"
)

const (
	rfc6455GUID        = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	DefaultRatePerSec  = 40.0
	DefaultBurstTokens = 80.0
)

// SessionDispatcher processa mensagens do protocolo v1 para uma sessão de cliente,
// aplicando anti-replay (SeqTracker), rate limiting (40 msg/s, rajada 80),
// exigência de autenticação via hello/resume e roteamento para auth.Service e rooms.Manager.
// Também implementa http.Handler para o handshake RFC 6455 em GET /ws.
type SessionDispatcher struct {
	mu            sync.Mutex
	auth          *auth.Service
	rooms         *rooms.Manager
	seq           SeqTracker
	limiter       *RateLimiter
	serverSeq     int64
	bootTime      time.Time
	authenticated bool
	sessionID     string
	playerID      string
	displayName   string
	platform      string
	roomID        string
	resumeToken   string
	conn          net.Conn
}

// Dispatcher é um alias para SessionDispatcher para facilitar o uso no servidor HTTP.
type Dispatcher = SessionDispatcher

// NewDispatcher cria um SessionDispatcher inicializado para o servidor HTTP.
func NewDispatcher(authSvc *auth.Service, roomMgr *rooms.Manager) *Dispatcher {
	return NewSessionDispatcher(authSvc, roomMgr, time.Now())
}

// NewSessionDispatcher cria um novo dispatcher de sessão com rate limiter padrão (40 msg/s, burst 80).
func NewSessionDispatcher(authSvc *auth.Service, roomMgr *rooms.Manager, now time.Time) *SessionDispatcher {
	if now.IsZero() {
		now = time.Now()
	}
	return &SessionDispatcher{
		auth:     authSvc,
		rooms:    roomMgr,
		limiter:  NewRateLimiter(DefaultRatePerSec, DefaultBurstTokens, now),
		bootTime: now,
		platform: "web",
	}
}

// ComputeAcceptKey calcula o valor de Sec-WebSocket-Accept conforme RFC 6455 §4.2.2.
func ComputeAcceptKey(secWebSocketKey string) string {
	sum := sha1.Sum([]byte(strings.TrimSpace(secWebSocketKey) + rfc6455GUID))
	return base64.StdEncoding.EncodeToString(sum[:])
}

func computeAcceptKey(secWebSocketKey string) string {
	return ComputeAcceptKey(secWebSocketKey)
}

func hasSubprotocol(r *http.Request, target string) bool {
	for _, line := range r.Header.Values("Sec-WebSocket-Protocol") {
		for _, part := range strings.Split(line, ",") {
			if strings.TrimSpace(part) == target {
				return true
			}
		}
	}
	return false
}

// ServeHTTP realiza a validação e o handshake HTTP -> WebSocket (RFC 6455) exigindo o subprotocolo blastgrid.v1.
func (d *SessionDispatcher) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if ver := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Version")); ver != "" && ver != "13" {
		w.Header().Set("Sec-WebSocket-Version", "13")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"unsupported_websocket_version","expected":"13"}`))
		return
	}
	if !hasSubprotocol(r, SubprotocolV1) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"missing_subprotocol","expected":"blastgrid.v1"}`))
		return
	}
	key := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Key"))
	upgrade := strings.ToLower(strings.TrimSpace(r.Header.Get("Upgrade")))
	if key == "" || upgrade != "websocket" {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"invalid_websocket_upgrade"}`))
		return
	}

	accept := ComputeAcceptKey(key)
	w.Header().Set("Upgrade", "websocket")
	w.Header().Set("Connection", "Upgrade")
	w.Header().Set("Sec-WebSocket-Accept", accept)
	w.Header().Set("Sec-WebSocket-Protocol", SubprotocolV1)
	w.WriteHeader(http.StatusSwitchingProtocols)
}

// DispatchRaw decodifica um frame JSON bruto e o despacha para a sessão.
func (d *SessionDispatcher) DispatchRaw(raw []byte, now time.Time) []Envelope {
	d.mu.Lock()
	defer d.mu.Unlock()

	if !d.limiter.Allow(now) {
		return []Envelope{d.newError("rate_limited", "limite de mensagens excedido", 0)}
	}

	env, err := DecodeEnvelope(raw)
	if err != nil {
		code := "bad_message"
		msg := err.Error()
		if perr, ok := err.(*ProtocolError); ok {
			code = perr.Code
			msg = perr.Msg
		}
		return []Envelope{d.newError(code, msg, 0)}
	}
	return d.dispatchLocked(env, now)
}

// Dispatch processa um Envelope já decodificado aplicando rate limit e proteção anti-replay.
func (d *SessionDispatcher) Dispatch(env Envelope, now time.Time) []Envelope {
	d.mu.Lock()
	defer d.mu.Unlock()

	if !d.limiter.Allow(now) {
		return []Envelope{d.newError("rate_limited", "limite de mensagens excedido", env.Seq)}
	}
	return d.dispatchLocked(env, now)
}

func (d *SessionDispatcher) dispatchLocked(env Envelope, now time.Time) []Envelope {
	if !d.seq.Accept(env.Seq) {
		return []Envelope{d.newError("bad_seq", "número de sequência repetido ou fora de ordem", env.Seq)}
	}

	switch env.T {
	case "ping":
		return []Envelope{d.handlePing(env, now)}
	case "hello":
		return []Envelope{d.handleHello(env, now)}
	case "resume":
		return d.handleResume(env, now)
	}

	if !d.authenticated {
		return []Envelope{d.newError("unauthorized", "hello obrigatório antes de outras mensagens", env.Seq)}
	}

	switch env.T {
	case "room.create":
		return []Envelope{d.handleRoomCreate(env)}
	case "room.join":
		return []Envelope{d.handleRoomJoin(env)}
	case "room.leave":
		return []Envelope{d.handleRoomLeave(env, now)}
	case "room.ready":
		return d.handleRoomReady(env)
	case "input":
		return d.handleInput(env)
	default:
		return []Envelope{d.newError("unknown_type", "tipo de mensagem desconhecido", env.Seq)}
	}
}

func (d *SessionDispatcher) handlePing(env Envelope, now time.Time) Envelope {
	var clientTime any
	if ct, ok := env.Data["client_time_ms"]; ok {
		clientTime = ct
	} else if t0, ok := env.Data["t0"]; ok {
		clientTime = t0
	}
	serverTime := now.Sub(d.bootTime).Milliseconds()
	tick := d.currentRoomTick()
	return d.nextEnvelope("pong", env.Seq, map[string]any{
		"t0":             clientTime,
		"client_time_ms": clientTime,
		"ts":             serverTime,
		"server_time_ms": serverTime,
		"tick":           tick,
	})
}

func (d *SessionDispatcher) handleHello(env Envelope, now time.Time) Envelope {
	tok, _ := env.Data["token"].(string)
	if tok == "" {
		tok, _ = env.Data["access_token"].(string)
	}
	if strings.TrimSpace(tok) == "" {
		return d.newError("unauthorized", "token ausente", env.Seq)
	}
	claims, err := d.auth.VerifyToken(tok, now)
	if err != nil {
		return d.newError("unauthorized", "token inválido ou expirado", env.Seq)
	}

	platform := "web"
	if clientMap, ok := env.Data["client"].(map[string]any); ok {
		if p, ok := clientMap["platform"].(string); ok && p != "" {
			platform = p
		}
		if ver, ok := clientMap["version"].(string); ok && strings.HasPrefix(ver, "0.0.") {
			return d.newError("client_outdated", "versão do cliente abaixo do mínimo suportado", env.Seq)
		}
	}

	d.authenticated = true
	d.playerID = claims.UserID
	d.displayName = claims.DisplayName
	d.platform = platform
	d.sessionID = "s_" + claims.UserID
	if d.resumeToken == "" {
		d.resumeToken = "rt_" + claims.UserID
	}

	return d.nextEnvelope("welcome", env.Seq, map[string]any{
		"session_id":      d.sessionID,
		"user_id":         d.playerID,
		"player_id":       d.playerID,
		"tick_rate":       rules.DefaultTickRate,
		"server_time_ms":  now.Sub(d.bootTime).Milliseconds(),
		"resume_token":    d.resumeToken,
		"resume_window_s": int(rooms.DefaultResumeWindow.Seconds()),
	})
}

func (d *SessionDispatcher) handleResume(env Envelope, now time.Time) []Envelope {
	rt, _ := env.Data["resume_token"].(string)
	targetRoomID, _ := env.Data["room_id"].(string)
	if strings.TrimSpace(rt) == "" {
		return []Envelope{d.newError("resume_failed", "resume_token ausente", env.Seq)}
	}
	room, part, err := d.rooms.Resume(rt, now)
	if err != nil && targetRoomID != "" {
		room, part, err = d.rooms.ResumeRoom(targetRoomID, rt, now)
	}
	if err != nil {
		return []Envelope{d.newError("resume_failed", err.Error(), env.Seq)}
	}

	d.authenticated = true
	d.playerID = part.ID
	d.displayName = part.Name
	d.platform = part.Platform
	d.roomID = room.ID
	d.resumeToken = part.ResumeToken
	d.sessionID = "s_" + part.ID

	out := []Envelope{
		d.nextEnvelope("welcome", env.Seq, map[string]any{
			"session_id":      d.sessionID,
			"user_id":         d.playerID,
			"player_id":       d.playerID,
			"tick_rate":       rules.DefaultTickRate,
			"server_time_ms":  now.Sub(d.bootTime).Milliseconds(),
			"resume_token":    d.resumeToken,
			"resume_window_s": int(rooms.DefaultResumeWindow.Seconds()),
		}),
	}
	if room.World != nil {
		out = append(out, d.buildStateEnvelope(room, nil, true))
	}
	return out
}

func (d *SessionDispatcher) handleRoomCreate(env Envelope) Envelope {
	mode, _ := env.Data["mode"].(string)
	maxPlayers := 4
	if mp, ok := env.Data["max_players"].(float64); ok {
		maxPlayers = int(mp)
	} else if mp, ok := env.Data["max_players"].(int); ok {
		maxPlayers = mp
	}
	priv, _ := env.Data["private"].(bool)

	room := d.rooms.CreateRoom(d.playerID, d.displayName, d.platform, mode, maxPlayers, priv)
	d.roomID = room.ID
	if len(room.Players) > 0 {
		room.Players[0].ResumeToken = d.resumeToken
		d.rooms.RegisterToken(d.resumeToken, room.ID)
	}
	return d.buildRoomStateEnvelope(room, env.Seq)
}

func (d *SessionDispatcher) handleRoomJoin(env Envelope) Envelope {
	target, _ := env.Data["room_id"].(string)
	if target == "" {
		target, _ = env.Data["code"].(string)
	}
	if strings.TrimSpace(target) == "" {
		return d.newError("bad_message", "room_id ou code obrigatório", env.Seq)
	}
	room, part, err := d.rooms.JoinRoom(target, d.playerID, d.displayName, d.platform)
	if err != nil {
		code := "room_not_found"
		if err == rooms.ErrRoomFull {
			code = "room_full"
		}
		return d.newError(code, err.Error(), env.Seq)
	}
	d.roomID = room.ID
	d.resumeToken = part.ResumeToken
	return d.buildRoomStateEnvelope(room, env.Seq)
}

func (d *SessionDispatcher) handleRoomLeave(env Envelope, now time.Time) Envelope {
	if d.roomID == "" {
		return d.newError("not_in_room", "jogador não está em nenhuma sala", env.Seq)
	}
	_ = d.rooms.Disconnect(d.roomID, d.playerID, now)
	leftRoomID := d.roomID
	d.roomID = ""
	return d.nextEnvelope("room.state", env.Seq, map[string]any{
		"room_id": leftRoomID,
		"status":  "left",
	})
}

func (d *SessionDispatcher) handleRoomReady(env Envelope) []Envelope {
	if d.roomID == "" {
		return []Envelope{d.newError("not_in_room", "jogador não está em nenhuma sala", env.Seq)}
	}
	ready, _ := env.Data["ready"].(bool)
	character, _ := env.Data["character"].(string)
	skin, _ := env.Data["skin"].(string)

	room, started, err := d.rooms.SetReady(d.roomID, d.playerID, ready, character, skin, 0)
	if err != nil {
		return []Envelope{d.newError("room_not_found", err.Error(), env.Seq)}
	}
	out := []Envelope{d.buildRoomStateEnvelope(room, env.Seq)}
	if started && room.World != nil {
		out = append(out, d.buildMatchStartEnvelope(room))
		out = append(out, d.buildStateEnvelope(room, nil, true))
	}
	return out
}

func (d *SessionDispatcher) handleInput(env Envelope) []Envelope {
	if d.roomID == "" {
		return []Envelope{d.newError("not_in_room", "jogador não está em nenhuma sala", env.Seq)}
	}
	serverTick := d.currentRoomTick()
	dir, bomb, _, err := ValidateInputData(env.Data, serverTick)
	if err != nil {
		code := "bad_message"
		msg := err.Error()
		if perr, ok := err.(*ProtocolError); ok {
			code = perr.Code
			msg = perr.Msg
		}
		return []Envelope{d.newError(code, msg, env.Seq)}
	}
	if err := d.rooms.ApplyInput(d.roomID, d.playerID, env.Seq, dir, bomb); err != nil {
		return []Envelope{d.newError("not_in_room", err.Error(), env.Seq)}
	}
	return nil
}

// StepRoom avança 1 tick na sala atual (ou roomID informado) e retorna os envelopes
// de "state" e, caso a partida tenha encerrado, "match.end".
func (d *SessionDispatcher) StepRoom(roomID string, nowArgs ...time.Time) ([]Envelope, error) {
	d.mu.Lock()
	defer d.mu.Unlock()

	if roomID == "" {
		roomID = d.roomID
	}
	evs, over, err := d.rooms.StepRoom(roomID)
	if err != nil {
		return nil, err
	}
	room := d.findRoom(roomID)
	if room == nil || room.World == nil {
		return nil, rooms.ErrRoomNotFound
	}
	full := room.World.Tick%200 == 0
	out := []Envelope{d.buildStateEnvelope(room, evs, full)}
	if over {
		out = append(out, d.buildMatchEndEnvelope(room))
	}
	if d.conn != nil {
		targetConn := d.conn
		for _, env := range out {
			if b, err := EncodeEnvelope(env); err == nil {
				go func(c net.Conn, data []byte) {
					_ = WriteWSFrame(c, data, false)
				}(targetConn, b)
			}
		}
	}
	return out, nil
}

func (d *SessionDispatcher) currentRoomTick() int {
	if d.roomID == "" {
		return 0
	}
	if r := d.findRoom(d.roomID); r != nil && r.World != nil {
		return r.World.Tick
	}
	return 0
}

func (d *SessionDispatcher) findRoom(roomID string) *rooms.Room {
	return d.rooms.GetRoom(roomID)
}

func (d *SessionDispatcher) buildRoomStateEnvelope(room *rooms.Room, ack int64) Envelope {
	players := make([]map[string]any, 0, len(room.Players))
	for _, p := range room.Players {
		players = append(players, map[string]any{
			"id":       p.ID,
			"name":     p.Name,
			"ready":    p.Ready,
			"slot":     p.Slot,
			"platform": p.Platform,
		})
	}
	data := map[string]any{
		"room_id":      room.ID,
		"mode":         room.Mode,
		"max_players":  room.MaxPlayers,
		"host":         room.HostID,
		"players":      players,
		"status":       room.Status,
		"resume_token": d.resumeToken,
	}
	if room.Code != "" {
		data["code"] = room.Code
	}
	return d.nextEnvelope("room.state", ack, data)
}

func (d *SessionDispatcher) buildMatchStartEnvelope(room *rooms.Room) Envelope {
	spawns := make([]map[string]any, 0, len(room.Players))
	for i, p := range room.Players {
		sp := rules.Spawns[i%len(rules.Spawns)]
		spawns = append(spawns, map[string]any{
			"id":    p.ID,
			"slot":  p.Slot,
			"spawn": []int{sp.X, sp.Y},
		})
	}
	return d.nextEnvelope("match.start", d.seq.LastSeq(), map[string]any{
		"match_id":       fmt.Sprintf("m_%s", room.ID),
		"seed":           room.World.Seed,
		"grid":           room.World.Grid.CompactString(),
		"cols":           room.World.Grid.Cols,
		"rows":           room.World.Grid.Rows,
		"start_tick":     60,
		"tick_rate":      room.World.TickRate,
		"duration_ticks": room.World.DurationTicks,
		"rules": map[string]any{
			"fuse":       room.World.FuseTicks,
			"flame":      room.World.FlameTicks,
			"base_range": rules.BaseRange,
			"base_bombs": rules.BaseBombs,
			"base_speed": rules.BaseSpeed,
		},
		"players": spawns,
	})
}

func (d *SessionDispatcher) buildStateEnvelope(room *rooms.Room, evs []rules.Event, full bool) Envelope {
	var ack int64
	for _, p := range room.Players {
		if p.ID == d.playerID {
			ack = p.LastInputSeq
			break
		}
	}
	if evs == nil {
		evs = []rules.Event{}
	}
	data := map[string]any{
		"tick":    room.World.Tick,
		"full":    full,
		"players": room.World.Players,
		"bombs":   room.World.Bombs,
		"events":  evs,
	}
	if full {
		data["grid"] = room.World.Grid.CompactString()
	}
	return d.nextEnvelope("state", ack, data)
}

func (d *SessionDispatcher) buildMatchEndEnvelope(room *rooms.Room) Envelope {
	var winner any
	if room.World.WinnerID != "" {
		winner = room.World.WinnerID
	}
	return d.nextEnvelope("match.end", d.seq.LastSeq(), map[string]any{
		"match_id": fmt.Sprintf("m_%s", room.ID),
		"tick":     room.World.Tick,
		"reason":   room.World.EndReason,
		"winner":   winner,
		"results":  room.Results,
	})
}

func (d *SessionDispatcher) nextEnvelope(msgType string, ack int64, data map[string]any) Envelope {
	d.serverSeq++
	return Envelope{
		V:    ProtocolVersion,
		T:    msgType,
		Seq:  d.serverSeq,
		Ack:  ack,
		Data: data,
	}
}

func (d *SessionDispatcher) newError(code, msg string, ref int64) Envelope {
	return d.nextEnvelope("error", ref, map[string]any{
		"code": code,
		"msg":  msg,
		"ref":  ref,
	})
}

// WriteWSFrame serializa e escreve um frame de texto RFC 6455.
func WriteWSFrame(w io.Writer, payload []byte, masked bool) error {
	length := len(payload)
	var frame []byte
	byte0 := byte(0x81) // FIN=1, Opcode=1 (Text)
	var byte1 byte
	if masked {
		byte1 = 0x80
	}

	if length <= 125 {
		byte1 |= byte(length)
		frame = append(frame, byte0, byte1)
	} else if length <= 65535 {
		byte1 |= 126
		frame = append(frame, byte0, byte1, byte(length>>8), byte(length))
	} else {
		byte1 |= 127
		lenBytes := make([]byte, 8)
		binary.BigEndian.PutUint64(lenBytes, uint64(length))
		frame = append(frame, byte0, byte1)
		frame = append(frame, lenBytes...)
	}

	if masked {
		maskKey := []byte{0x12, 0x34, 0x56, 0x78}
		frame = append(frame, maskKey...)
		for i := 0; i < length; i++ {
			frame = append(frame, payload[i]^maskKey[i%4])
		}
	} else {
		frame = append(frame, payload...)
	}

	_, err := w.Write(frame)
	return err
}

// ReadWSFrame lê e decodifica um frame RFC 6455.
func ReadWSFrame(r io.Reader) ([]byte, error) {
	var hdr [2]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return nil, err
	}

	masked := (hdr[1] & 0x80) != 0
	payloadLen := int(hdr[1] & 0x7F)

	if payloadLen == 126 {
		var ext [2]byte
		if _, err := io.ReadFull(r, ext[:]); err != nil {
			return nil, err
		}
		payloadLen = int(binary.BigEndian.Uint16(ext[:]))
	} else if payloadLen == 127 {
		var ext [8]byte
		if _, err := io.ReadFull(r, ext[:]); err != nil {
			return nil, err
		}
		payloadLen = int(binary.BigEndian.Uint64(ext[:]))
	}

	var maskKey [4]byte
	if masked {
		if _, err := io.ReadFull(r, maskKey[:]); err != nil {
			return nil, err
		}
	}

	payload := make([]byte, payloadLen)
	if _, err := io.ReadFull(r, payload); err != nil {
		return nil, err
	}

	if masked {
		for i := 0; i < payloadLen; i++ {
			payload[i] ^= maskKey[i%4]
		}
	}

	return payload, nil
}

// readWSFrame é um helper não exportado compatível com os testes.
func readWSFrame(r io.Reader) ([]byte, error) {
	return ReadWSFrame(r)
}

// writeWSFrame é um helper não exportado compatível com os testes.
func writeWSFrame(w io.Writer, payload []byte, masked bool) error {
	return WriteWSFrame(w, payload, masked)
}

// HandleLoop atende uma conexão WebSocket executando o loop de recepção e despacho.
func (d *SessionDispatcher) HandleLoop(conn net.Conn) error {
	d.mu.Lock()
	d.conn = conn
	d.mu.Unlock()

	defer func() {
		d.mu.Lock()
		if d.conn == conn {
			d.conn = nil
		}
		d.mu.Unlock()
		_ = conn.Close()
	}()

	for {
		raw, err := ReadWSFrame(conn)
		if err != nil {
			return err
		}
		responses := d.DispatchRaw(raw, time.Now())
		for _, resp := range responses {
			data, err := EncodeEnvelope(resp)
			if err != nil {
				return err
			}
			if err := WriteWSFrame(conn, data, false); err != nil {
				return err
			}
		}
	}
}

// handleLoop é um helper com minúscula para flexibilidade nos testes.
func (d *SessionDispatcher) handleLoop(conn net.Conn) error {
	return d.HandleLoop(conn)
}
