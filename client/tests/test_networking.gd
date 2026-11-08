extends TestCase
## Testes das Fases 3 e 4 no cliente: codec do protocolo v1 (fixtures compartilhadas),
## sincronização de relógio NTP/Cristian e predição/reconciliação.


func run() -> void:
	_test_protocol_fixtures()
	_test_clock_sync()
	_test_prediction_and_reconciliation()


func _test_protocol_fixtures() -> void:
	var file_path := ProjectSettings.globalize_path("res://../tests/protocol/01_envelope.json")
	check(FileAccess.file_exists(file_path), "fixture 01_envelope.json existe")
	if not FileAccess.file_exists(file_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	check(data is Dictionary, "JSON válido")
	if not (data is Dictionary):
		return

	for m: Dictionary in data.get("valid_messages", []):
		var res := Protocol.decode(str(m["raw"]))
		check(bool(res["ok"]), "mensagem válida aceita: %s" % str(m["raw"]))
		eq(str(res["t"]), str(m["expect_t"]), "tipo decodificado")
		eq(int(res["seq"]), int(m["expect_seq"]), "seq decodificado")
		eq(int(res["ack"]), int(m["expect_ack"]), "ack decodificado")

	for m: Dictionary in data.get("invalid_messages", []):
		var res := Protocol.decode(str(m["raw"]))
		eq(bool(res["ok"]), false, "mensagem inválida rejeitada: %s" % str(m["raw"]))
		eq(str(res["code"]), str(m["expect_code"]), "código de erro esperado")


func _test_clock_sync() -> void:
	var ns := NetSync.new()
	# RTT = 40 ms, servidor está 1000 ms à frente
	ns.add_pong_sample(100, 1120, 140, 200)
	eq(ns.median_rtt_ms, 40, "mediana RTT = 40 ms")
	eq(ns.clock_offset_ms, 1000, "offset = 1000 ms")
	# 100 ms depois (t=220 no cliente -> 1220 no servidor, +2 ticks sobre ts=1120)
	eq(ns.estimate_server_tick(220), 202, "estimativa de tick do servidor")


func _test_prediction_and_reconciliation() -> void:
	var g := Grid.generate(1, 4)
	g.set_tile(2, 1, Grid.Tile.EMPTY)
	g.set_tile(3, 1, Grid.Tile.EMPTY)

	var p := PlayerState.new("p0", 0, Vector2i(1, 1))
	var ns := NetSync.new()

	# Jogador prediz 3 passos para a direita (seqs 1, 2, 3 -> x = 1500 + 600 = 2100)
	ns.record_predicted_input(1, 10, "right", false, p, g)
	ns.record_predicted_input(2, 11, "right", false, p, g)
	ns.record_predicted_input(3, 12, "right", false, p, g)
	eq(p.x, 2100, "posição predita após 3 inputs")

	# Servidor confirma até seq=2 na posição exata (x=1900); re-simula seq=3 -> continua 2100 (erro 0)
	var err := ns.reconcile_local_player(1900, 1500, 2, p, g)
	eq(err, 0, "sem divergência entre predição e servidor")
	eq(p.x, 2100, "posição reconciliada mantém seq=3 pendente")
	eq(ns.pending_inputs.size(), 1, "resta apenas seq=3 pendente")

	# Servidor corrige seq=3 para x=1900 (ex.: pacote perdido) -> reconcilia para 1900
	var err2 := ns.reconcile_local_player(1900, 1500, 3, p, g)
	eq(err2, 200, "detectou divergência de 200 mt")
	eq(p.x, 1900, "corrigiu para a posição autoritativa")

