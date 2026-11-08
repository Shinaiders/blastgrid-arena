class_name NetSync
extends RefCounted
## Sincronização de relógio (NTP/Cristian), predição local e reconciliação (NETWORK_PROTOCOL.md §6–7).

const MAX_CLOCK_SAMPLES: int = 8
const SMOOTH_THRESHOLD_MT: int = 30

var clock_samples: Array[Dictionary] = []
var clock_offset_ms: int = 0
var median_rtt_ms: int = 0
var ref_server_tick: int = 0
var ref_server_ms: int = 0

## Buffer de inputs pendentes de confirmação (seq > last_acked_seq):
## Array de {"seq": int, "tick": int, "dir": String, "bomb": bool}
var pending_inputs: Array[Dictionary] = []
var last_acked_seq: int = 0


func add_pong_sample(t0_client_ms: int, ts_server_ms: int, t1_client_ms: int, server_tick: int) -> void:
	var rtt := maxi(t1_client_ms - t0_client_ms, 0)
	@warning_ignore("integer_division")
	var offset: int = ts_server_ms + (rtt / 2) - t1_client_ms
	clock_samples.append({"rtt": rtt, "offset": offset})
	if clock_samples.size() > MAX_CLOCK_SAMPLES:
		clock_samples.pop_front()

	# Usa o offset da amostra de menor RTT e a mediana do RTT para exibição (NETWORK_PROTOCOL §6)
	var best_rtt := 999999999
	var rtts: Array[int] = []
	for s in clock_samples:
		var r: int = int(s["rtt"])
		rtts.append(r)
		if r < best_rtt:
			best_rtt = r
			clock_offset_ms = int(s["offset"])

	rtts.sort()
	@warning_ignore("integer_division")
	median_rtt_ms = rtts[rtts.size() / 2]
	if server_tick > 0:
		ref_server_tick = server_tick
		ref_server_ms = ts_server_ms


@warning_ignore("integer_division")
func estimate_server_tick(now_client_ms: int) -> int:
	if ref_server_ms == 0:
		return ref_server_tick
	var est_server_ms := now_client_ms + clock_offset_ms
	return ref_server_tick + ((est_server_ms - ref_server_ms) / 50)


@warning_ignore("integer_division")
func target_input_tick(now_client_ms: int) -> int:
	var srv := estimate_server_tick(now_client_ms)
	var lead_ticks := ((median_rtt_ms / 2) + 50 + 49) / 50
	return srv + maxi(lead_ticks, 1)


func record_predicted_input(seq: int, tick: int, dir: String, bomb: bool, local_player: PlayerState, grid: Grid) -> void:
	pending_inputs.append({"seq": seq, "tick": tick, "dir": dir, "bomb": bomb})
	local_player.dir = dir
	MovementRules.step_player(local_player, grid)


## Reconcilia a posição do jogador local ao receber `state` com `ack` (NETWORK_PROTOCOL §7).
## Retorna o erro absoluto (em militiles) antes da correção.
func reconcile_local_player(auth_x: int, auth_y: int, ack_seq: int, local_player: PlayerState, grid: Grid) -> int:
	last_acked_seq = maxi(last_acked_seq, ack_seq)
	var remaining: Array[Dictionary] = []
	for inp in pending_inputs:
		if int(inp["seq"]) > last_acked_seq:
			remaining.append(inp)
	pending_inputs = remaining

	var prev_pred_x := local_player.x
	var prev_pred_y := local_player.y

	# Parte do estado autoritativo confirmado e re-simula os inputs ainda não confirmados
	local_player.x = auth_x
	local_player.y = auth_y
	for inp in pending_inputs:
		local_player.dir = str(inp["dir"])
		MovementRules.step_player(local_player, grid)

	return maxi(absi(local_player.x - prev_pred_x), absi(local_player.y - prev_pred_y))

