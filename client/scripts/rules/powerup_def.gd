class_name PowerUpDef
extends Resource
## Definição expansível de power-up via Resource (GDD §7, ARCHITECTURE §3).

const KIND_RANGE_UP := "range_up"
const KIND_BOMB_UP := "bomb_up"
const KIND_SPEED_UP := "speed_up"
const KIND_SHIELD := "shield"

const DROP_CHANCE_PCT: int = 30
const SHIELD_DURATION_TICKS: int = 120 # 6 s a 20 Hz

@export var id: String = KIND_RANGE_UP
@export var display_name: String = "Faísca"
@export var description: String = "+1 alcance de explosão"
@export var drop_weight: int = 35
@export var add_range: int = 0
@export var add_bombs: int = 0
@export var add_speed: int = 0
@export var shield_ticks: int = 0
@export var color: Color = Color(1.0, 0.55, 0.2, 1.0)


func apply(player: PlayerState) -> void:
	if add_range != 0:
		player.bomb_range = clampi(player.bomb_range + add_range, 1, PlayerState.MAX_RANGE)
	if add_bombs != 0:
		player.max_bombs = clampi(player.max_bombs + add_bombs, 1, PlayerState.MAX_BOMBS)
	if add_speed != 0:
		player.speed = clampi(player.speed + add_speed, PlayerState.BASE_SPEED, PlayerState.MAX_SPEED)
	if shield_ticks > 0:
		player.shield_ticks = shield_ticks


## Aplica pelo id estável do protocolo (usado também quando não se carrega o .tres).
static func apply_kind(player: PlayerState, kind: String) -> void:
	match kind:
		KIND_RANGE_UP:
			player.bomb_range = mini(player.bomb_range + 1, PlayerState.MAX_RANGE)
		KIND_BOMB_UP:
			player.max_bombs = mini(player.max_bombs + 1, PlayerState.MAX_BOMBS)
		KIND_SPEED_UP:
			player.speed = mini(player.speed + PlayerState.SPEED_STEP, PlayerState.MAX_SPEED)
		KIND_SHIELD:
			player.shield_ticks = SHIELD_DURATION_TICKS


## Sorteia se um bloco destruído gera drop (30%) e qual o tipo (pesos 35/35/20/10 — GDD §7).
## Retorna "" se não houver drop.
static func roll_drop(rng: PRNG) -> String:
	if rng.next_bound(100) >= DROP_CHANCE_PCT:
		return ""
	var w := rng.next_bound(100)
	if w < 35:
		return KIND_RANGE_UP
	if w < 70:
		return KIND_BOMB_UP
	if w < 90:
		return KIND_SPEED_UP
	return KIND_SHIELD

