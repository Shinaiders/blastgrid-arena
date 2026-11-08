extends TestCase
## Suíte de testes para os módulos das Fases 5 e 6:
## LoopbackTransport, WSTransport, NetSession, SettingsStore, SfxSynth e SteamBridge.


func run() -> void:
	_test_loopback_transport()
	_test_ws_transport()
	_test_net_session()
	_test_settings_store()
	_test_sfx_synth()
	_test_steam_bridge()


func _test_loopback_transport() -> void:
	var a := Transport.LoopbackTransport.new()
	var b := Transport.LoopbackTransport.new()
	Transport.LoopbackTransport.link(a, b)

	eq(a.connect_to_url("ws://loopback/a"), OK, "a conecta")
	eq(b.connect_to_url("ws://loopback/b"), OK, "b conecta")

	eq(a.send_text("hello_from_a"), OK, "a envia texto")
	var b_pkts := b.poll_packets()
	eq(b_pkts.size(), 1, "b recebe 1 pacote")
	if not b_pkts.is_empty():
		eq(b_pkts[0], "hello_from_a", "conteúdo recebido por b")

	eq(b.send_text("hello_from_b"), OK, "b envia texto")
	var a_pkts := a.poll_packets()
	eq(a_pkts.size(), 1, "a recebe 1 pacote")
	if not a_pkts.is_empty():
		eq(a_pkts[0], "hello_from_b", "conteúdo recebido por a")

	a.disconnect_transport(1001, "client close")
	b.disconnect_transport(1001, "server close")
	eq(a.get_state(), Transport.State.CLOSED, "a desconectado")
	eq(a.get_Close_code(), 1001, "código de fechamento verificado")


func _test_ws_transport() -> void:
	var ws := WSTransport.new()
	eq(ws.get_state(), WSTransport.STATE_CLOSED, "estado inicial STATE_CLOSED")
	eq(WSTransport.SUBPROTOCOL, "blastgrid.v1", "subprotocolo blastgrid.v1")
	var pkts := ws.poll_packets()
	eq(pkts.size(), 0, "poll_packets retorna vazio quando fechado")


func _test_net_session() -> void:
	var client_peer := Transport.LoopbackTransport.new()
	var server_peer := Transport.LoopbackTransport.new()
	Transport.LoopbackTransport.link(client_peer, server_peer)
	server_peer.connect_to_url("ws://server")

	var session := NetSession.new(client_peer)

	# 1. connect_session envia automaticamente hello com v: 1, type: "hello", seq: 1
	var conn_err := session.connect_session("wss://test/ws", "tok_123", "Sparky")
	eq(conn_err, OK, "connect_session OK")

	var server_rx := server_peer.poll_packets()
	check(server_rx.size() >= 1, "servidor recebeu pacote hello")
	if server_rx.size() >= 1:
		var hello_raw: String = server_rx[0]
		var hello_json: Variant = JSON.parse_string(hello_raw)
		check(hello_json is Dictionary, "envelope hello é JSON válido")
		if hello_json is Dictionary:
			eq(int(hello_json.get("v", 0)), 1, "v == 1")
			var msg_type := str(hello_json.get("type", hello_json.get("t", "")))
			eq(msg_type, "hello", "type == hello")
			eq(int(hello_json.get("seq", 0)), 1, "seq == 1")

	# 2. Servidor envia welcome
	var welcome_raw := Protocol.encode("welcome", 1, {
		"session_id": "s_1",
		"user_id": "u_1",
		"tick_rate": 20,
	})
	server_peer.send_text(welcome_raw)
	session.step(0.0)

	eq(session.is_authenticated, true, "session.is_authenticated == true")
	eq(session.session_id, "s_1", "session.session_id == s_1")

	# 3. Ping / Pong
	session.send_ping(1000)
	var ping_rx := server_peer.poll_packets()
	check(ping_rx.size() >= 1, "servidor recebeu ping")

	var pong_raw := Protocol.encode("pong", 2, {
		"client_time_ms": 1000,
		"server_time_ms": 1020,
		"t0": 1000,
		"ts": 1020,
		"tick": 20,
	})
	server_peer.send_text(pong_raw)
	session.step(0.0, 1040)
	check(session.last_rtt_ms >= 0, "last_rtt_ms >= 0")

	# 4. create_room -> room.state
	session.create_room("ffa", 4, true)
	var room_req_rx := server_peer.poll_packets()
	check(room_req_rx.size() >= 1, "servidor recebeu room.create")

	var room_state_raw := Protocol.encode("room.state", 3, {
		"room_id": "r_1",
		"code": "ABCD23",
		"status": "lobby",
		"resume_token": "res_tok_1",
	})
	server_peer.send_text(room_state_raw)
	session.step(0.0)

	eq(session.room_id, "r_1", "room_id == r_1")
	eq(session.room_code, "ABCD23", "room_code == ABCD23")
	eq(session.resume_token, "res_tok_1", "resume_token == res_tok_1")

	# 5. step_reconnect com backoff e envio de resume
	client_peer.close(1006, "abnormal")
	eq(client_peer.get_state(), Transport.State.CLOSED, "cliente fechado")

	eq(NetSession.BACKOFF_SCHEDULE_S, [0.5, 1.0, 2.0, 4.0, 8.0], "cronograma de backoff")

	session.step_reconnect(0.3, "wss://test/ws")
	eq(client_peer.get_state(), Transport.State.CLOSED, "ainda desconectado antes de 0.5s")

	session.step_reconnect(0.2, "wss://test/ws")
	eq(client_peer.get_state(), Transport.State.OPEN, "reconectou após 0.5s")

	var resume_rx := server_peer.poll_packets()
	check(resume_rx.size() >= 1, "servidor recebeu pacote de resume")
	if resume_rx.size() >= 1:
		var resume_json: Variant = JSON.parse_string(resume_rx[0])
		if resume_json is Dictionary:
			var t := str(resume_json.get("type", resume_json.get("t", "")))
			eq(t, "resume", "tipo de reconexão é resume")
			var d: Dictionary = resume_json.get("data", {})
			eq(str(d.get("resume_token", "")), "res_tok_1", "token de resume mantido")

	client_peer.disconnect_transport()
	server_peer.disconnect_transport()


func _test_settings_store() -> void:
	var path := "user://test_input_phase6.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var store1 := SettingsStore.new(path)
	store1.set_volume("sfx", 1.5)
	eq(store1.get_volume("sfx"), 1.0, "volume sfx clamp 1.0")

	store1.set_volume("music", -0.5)
	eq(store1.get_volume("music"), 0.0, "volume music clamp 0.0")

	store1.mute = true
	store1.fullscreen = true
	store1.rebind_key("bomb", KEY_B)

	eq(store1.save_settings(), OK, "save_settings gravado com sucesso")

	var store2 := SettingsStore.new(path)
	eq(store2.load_settings(), OK, "load_settings carregado com sucesso")

	eq(store2.get_volume("sfx"), 1.0, "volume sfx persistido")
	eq(store2.get_volume("music"), 0.0, "volume music persistido")
	eq(store2.mute, true, "mute persistido")
	eq(store2.fullscreen, true, "fullscreen persistido")
	eq(store2.get_key_binding("bomb"), int(KEY_B), "rebind bomb persistido")

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _test_sfx_synth() -> void:
	var synth := SfxSynth.new()

	var sounds: Array[AudioStreamWAV] = [
		SfxSynth.make_bomb_place(),
		SfxSynth.make_explosion(),
		SfxSynth.make_powerup(),
		SfxSynth.make_victory(),
		SfxSynth.make_ui_click(),
	]
	var sound_names: Array[String] = [
		"bomb_place",
		"explosion",
		"powerup",
		"victory",
		"ui_click",
	]

	for i in range(sounds.size()):
		var s: AudioStreamWAV = sounds[i]
		var name: String = sound_names[i]
		eq(s.format, AudioStreamWAV.FORMAT_16_BITS, "%s FORMAT_16_BITS" % name)
		eq(s.mix_rate, 22050, "%s mix_rate 22050" % name)
		check(s.data.size() > 1000, "%s data.size() > 1000 (%d bytes)" % [name, s.data.size()])

	# Determinismo: segunda geração deve produzir bytes idênticos
	var s_bomb_2 := SfxSynth.make_bomb_place()
	eq(sounds[0].data, s_bomb_2.data, "make_bomb_place é determinístico")

	var s_exp_2 := SfxSynth.make_explosion()
	eq(sounds[1].data, s_exp_2.data, "make_explosion é determinístico")

	var s_pow_2 := SfxSynth.make_powerup()
	eq(sounds[2].data, s_pow_2.data, "make_powerup é determinístico")

	var s_vic_2 := SfxSynth.make_victory()
	eq(sounds[3].data, s_vic_2.data, "make_victory é determinístico")

	var s_click_2 := SfxSynth.make_ui_click()
	eq(sounds[4].data, s_click_2.data, "make_ui_click é determinístico")

	eq(synth.audio_unlocked, false, "áudio inicialmente bloqueado")
	synth.unlock_on_gesture()
	eq(synth.audio_unlocked, true, "áudio desbloqueado por unlock_on_gesture")


func _test_steam_bridge() -> void:
	var bridge := SteamBridge.new()

	# 1. Sem tag steam / ambiente headless / force_disallow
	var init_res := bridge.init_steam(true)
	eq(init_res, false, "init_steam retorna false em ambiente desautorizado")
	eq(bridge.is_initialized, false, "is_initialized mantido false")

	# 2. Modo mock
	bridge.enable_mock_steam(true, 76561198000000001)
	var mock_init := bridge.init_steam()
	eq(mock_init, true, "init_steam retorna true no modo mock")
	eq(bridge.is_initialized, true, "is_initialized == true")

	var ticket := bridge.get_auth_session_ticket_hex(480)
	eq(ticket.length(), 32, "ticket tem 32 caracteres hexadecimais")

	# evaluate_match_achievements desbloqueia sem duplicatas
	var achs1 := bridge.evaluate_match_achievements(true, 3, 50)
	eq(achs1, ["FIRST_WIN", "CHAIN_MASTER_3", "COLLECTOR_50"], "desbloqueia 3 conquistas na primeira avaliação")

	var achs2 := bridge.evaluate_match_achievements(true, 3, 50)
	eq(achs2.size(), 0, "sem duplicatas em avaliações subsequentes")
