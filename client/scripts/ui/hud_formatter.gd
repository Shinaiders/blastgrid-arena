class_name HudFormatter
extends RefCounted
## Formatação pura de dados do HUD e tabela de resultados (Dia 13 — GDD §8, §11).


static func format_clock(remaining_ticks: int, tick_rate: int = 20) -> String:
	var clamped := maxi(remaining_ticks, 0)
	@warning_ignore("integer_division")
	var total_sec: int = (clamped + tick_rate - 1) / maxi(tick_rate, 1)
	@warning_ignore("integer_division")
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]


static func count_alive(players: Array[PlayerState]) -> int:
	var c := 0
	for p in players:
		if p.alive and not p.disconnected:
			c += 1
	return c


static func format_powerups_summary(p: PlayerState) -> String:
	if p == null:
		return "Bombas: 1 | Alcance: 2 | Vel: 4.0 | Escudo: Não"
	var tiles_per_sec := float(p.speed) * 20.0 / 1000.0
	var shield_txt := "Não"
	if p.shield_ticks > 0:
		shield_txt = "%.1fs" % (float(p.shield_ticks) / 20.0)
	return "Bombas: %d | Alcance: %d | Vel: %.1f | Escudo: %s" % [
		p.max_bombs,
		p.bomb_range,
		tiles_per_sec,
		shield_txt,
	]


static func format_connection_badge(is_online: bool, rtt_ms: int = 0, status: String = "connected") -> String:
	if not is_online:
		return "LOCAL · 20 Hz (Offline)"
	if status != "connected":
		return "ONLINE · %s" % status.to_upper()
	return "ONLINE · %d ms" % maxi(rtt_ms, 1)


## Ordena os participantes para a tela de resultado: vivos primeiro, depois maior score, mais kills, menor slot.
static func build_standings(world: WorldSim) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for p in world.players:
		rows.append({
			"id": p.id,
			"slot": p.slot,
			"name": ArenaRenderer.PLAYER_NAMES[p.slot % ArenaRenderer.PLAYER_NAMES.size()],
			"alive": p.alive,
			"score": p.score,
			"kills": p.kills,
			"deaths": p.deaths,
			"blocks": p.blocks_destroyed,
			"powerups": p.powerups_collected,
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["alive"]) != bool(b["alive"]):
			return bool(a["alive"])
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		if int(a["kills"]) != int(b["kills"]):
			return int(a["kills"]) > int(b["kills"])
		return int(a["slot"]) < int(b["slot"])
	)

	for i in range(rows.size()):
		rows[i]["place"] = i + 1
	return rows

