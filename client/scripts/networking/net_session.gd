class_name NetSession
extends RefCounted
## Gerenciador de sessão do protocolo v1 sobre Transport (NETWORK_PROTOCOL.md §4–§8).
## Cuida de hello/welcome, ping/pong, salas, partida e reconexão com backoff exponencial.

signal welcomed(data: Dictionary)
signal room_state_received(data: Dictionary)
signal match_started(data: Dictionary)
signal state_received(data: Dictionary, ack: int)
signal match_ended(data: Dictionary)
signal protocol_error(code: String, msg: String)

const BACKOFF_SCHEDULE_S: Array[float] = [0.5, 1.0, 2.0, 4.0, 8.0]
const DEFAULT_RESUME_WINDOW_S: float = 30.0
const PING_INTERVAL_S: float = 2.0
const PONG_TIMEOUT_S: float = 10.0

var transport: Transport
var sync: NetSync = NetSync.new()

var url: String = "ws://localhost:8080/ws"
var auth_token: String = ""
var display_name: String = ""
var client_version: String = "0.1.0"
var client_build: String = "dev"

var seq: int = 0
var last_server_seq: int = 0
var session_id: String = ""
var player_id: String = ""
var user_id: String = ""
var tick_rate: int = 20
var resume_token: String = ""
var resume_window_s: float = DEFAULT_RESUME_WINDOW_S
var room_id: String = ""
var room_code: String = ""
var last_rtt_ms: int = -1

var handshake_sent: bool = false
var authenticated: bool = false
var is_authenticated: bool:
	get:
		return authenticated
	set(val):
		authenticated = val

var reconnect_attempt: int = 0
var disconnected_elapsed_s: float = 0.0
var retry_timer_s: float = 0.0

var last_room_state: Dictionary = {}
var last_match_start: Dictionary = {}
var last_state: Dictionary = {}
var last_match_end: Dictionary = {}
var last_error: Dictionary = {}


func _init(p_transport: Transport = null) -> void:
	transport = p_transport if p_transport != null else WSTransport.new()


func start(p_url: String, p_token: String) -> int:
	url = p_url
	auth_token = p_token
	handshake_sent = false
	authenticated = false
	reconnect_attempt = 0
	disconnected_elapsed_s = 0.0
	retry_timer_s = 0.0
	return transport.connect_to_url(url)


func connect_session(p_url: String, p_token: String, p_display_name: String = "") -> int:
	display_name = p_display_name
	var err := start(p_url, p_token)
	if err == OK and transport.get_state() == Transport.State.OPEN and not handshake_sent:
		handshake_sent = true
		if not resume_token.is_empty():
			send_resume()
		else:
			send_hello()
	return err


func next_seq() -> int:
	seq += 1
	return seq


func send_message(msg_type: String, data: Dictionary = {}) -> int:
	var raw := Protocol.encode(msg_type, next_seq(), data, last_server_seq)
	return transport.send_text(raw)


func send_hello() -> int:
	var client_meta := {
		"platform": PlatformInfo.platform_name().to_lower(),
		"version": client_version,
		"build": client_build,
	}
	var data := {
		"token": auth_token,
		"client": client_meta,
	}
	if not display_name.is_empty():
		data["name"] = display_name
	return send_message("hello", data)


func send_resume() -> int:
	return send_message("resume", {
		"resume_token": resume_token,
		"last_server_seq": last_server_seq,
	})


func send_ping(now_client_ms: int) -> int:
	return send_message("ping", {"t0": now_client_ms, "client_time_ms": now_client_ms})


func send_input(tick: int, dir: String, bomb: bool) -> int:
	return send_message("input", {"tick": tick, "dir": dir, "bomb": bomb})


func send_room_create(mode: String = "ffa", max_players: int = 4, is_private: bool = false) -> int:
	return send_message("room.create", {"mode": mode, "max_players": max_players, "private": is_private})


func create_room(mode: String = "ffa", max_players: int = 4, is_private: bool = false) -> int:
	return send_room_create(mode, max_players, is_private)


func send_room_join(p_room_id: String = "", code: String = "") -> int:
	if not code.is_empty():
		return send_message("room.join", {"code": code})
	return send_message("room.join", {"room_id": p_room_id})


func send_room_ready(ready: bool, character: String = "sparky_a", skin: String = "default") -> int:
	return send_message("room.ready", {"ready": ready, "character": character, "skin": skin})


func send_room_leave() -> int:
	return send_message("room.leave", {})


static func get_backoff_delay(attempt_index: int) -> float:
	var idx := clampi(attempt_index, 0, BACKOFF_SCHEDULE_S.size() - 1)
	return BACKOFF_SCHEDULE_S[idx]


func can_attempt_resume(elapsed_s: float) -> bool:
	return not resume_token.is_empty() and elapsed_s < resume_window_s


func step_reconnect(dt: float, target_url: String = "") -> void:
	if not target_url.is_empty():
		url = target_url
	step(dt)


func step(delta: float, now_client_ms: int = -1) -> void:
	var clock_ms := now_client_ms if now_client_ms >= 0 else int(Time.get_ticks_msec())
	transport.poll()
	var st := transport.get_state()

	if st == Transport.State.OPEN:
		disconnected_elapsed_s = 0.0
		if not handshake_sent:
			handshake_sent = true
			if not resume_token.is_empty():
				send_resume()
			else:
				send_hello()
		for raw in transport.receive_text():
			_handle_raw_frame(raw, clock_ms)
	elif st == Transport.State.CLOSED:
		authenticated = false
		handshake_sent = false
		if can_attempt_resume(disconnected_elapsed_s):
			disconnected_elapsed_s += delta
			retry_timer_s += delta
			var wait_s := get_backoff_delay(reconnect_attempt)
			if retry_timer_s >= wait_s and can_attempt_resume(disconnected_elapsed_s):
				retry_timer_s = 0.0
				reconnect_attempt += 1
				transport.connect_to_url(url)
				if transport.get_state() == Transport.State.OPEN:
					if not handshake_sent:
						handshake_sent = true
						if not resume_token.is_empty():
							send_resume()
						else:
							send_hello()


func _handle_raw_frame(raw: String, now_client_ms: int) -> void:
	var msg := Protocol.decode(raw)
	if not bool(msg.get("ok", false)):
		return
	var srv_seq := int(msg["seq"])
	if srv_seq <= last_server_seq:
		return # proteção contra replay (NETWORK_PROTOCOL §2, §9)
	last_server_seq = srv_seq

	var t := str(msg["t"])
	var ack := int(msg["ack"])
	var data: Dictionary = msg["data"]

	match t:
		"welcome":
			authenticated = true
			reconnect_attempt = 0
			session_id = str(data.get("session_id", ""))
			player_id = str(data.get("player_id", data.get("user_id", "")))
			user_id = player_id
			tick_rate = int(data.get("tick_rate", tick_rate))
			resume_token = str(data.get("resume_token", resume_token))
			resume_window_s = float(data.get("resume_window_s", DEFAULT_RESUME_WINDOW_S))
			welcomed.emit(data)
		"pong":
			var t0 := int(data.get("t0", data.get("client_time_ms", now_client_ms)))
			var ts := int(data.get("ts", data.get("server_time_ms", now_client_ms)))
			var srv_tick := int(data.get("tick", 0))
			last_rtt_ms = maxi(0, now_client_ms - t0)
			sync.add_pong_sample(t0, ts, now_client_ms, srv_tick)
			if last_rtt_ms < 0:
				last_rtt_ms = sync.median_rtt_ms
		"room.state":
			last_room_state = data
			room_id = str(data.get("room_id", room_id))
			room_code = str(data.get("code", data.get("room_code", room_code)))
			if data.has("resume_token"):
				resume_token = str(data["resume_token"])
			room_state_received.emit(data)
		"match.start":
			last_match_start = data
			match_started.emit(data)
		"state":
			last_state = data
			state_received.emit(data, ack)
		"match.end":
			last_match_end = data
			match_ended.emit(data)
		"error":
			var code := str(data.get("code", "unknown"))
			var err_msg := str(data.get("msg", ""))
			last_error = data
			if code == "resume_failed":
				# Falha no resume -> limpa token e faz hello novo (NETWORK_PROTOCOL §5.1)
				resume_token = ""
				send_hello()
			protocol_error.emit(code, err_msg)
