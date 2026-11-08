class_name PlayerState
extends RefCounted
## Estado puro de um jogador na simulação determinística em militiles (1 tile = 1000).
## Sem dependência de nós da Godot (ARCHITECTURE D-11, D-13).

const TILE_SIZE: int = 1000
const HALF_TILE: int = 500

const BASE_SPEED: int = 200
const SPEED_STEP: int = 25
const MAX_SPEED: int = 350

const BASE_BOMBS: int = 1
const MAX_BOMBS: int = 8

const BASE_RANGE: int = 2
const MAX_RANGE: int = 8

var id: String = ""
var slot: int = 0
var character_id: String = "sparky_a"
var skin_id: String = "sparky_a_default"

var x: int = 1500
var y: int = 1500
var dir: String = "none"
var facing: String = "down"
var alive: bool = true
var disconnected: bool = false

var speed: int = BASE_SPEED
var max_bombs: int = BASE_BOMBS
var bomb_range: int = BASE_RANGE
var shield_ticks: int = 0
var invulnerable_ticks: int = 0

var score: int = 0
var kills: int = 0
var deaths: int = 0
var blocks_destroyed: int = 0
var powerups_collected: int = 0


func _init(p_id: String = "p0", p_slot: int = 0, spawn_cell: Vector2i = Vector2i(1, 1)) -> void:
	id = p_id
	slot = p_slot
	x = spawn_cell.x * TILE_SIZE + HALF_TILE
	y = spawn_cell.y * TILE_SIZE + HALF_TILE


@warning_ignore("integer_division")
func cell_x() -> int:
	return x / TILE_SIZE


@warning_ignore("integer_division")
func cell_y() -> int:
	return y / TILE_SIZE


func cell() -> Vector2i:
	return Vector2i(cell_x(), cell_y())


## Verdadeiro enquanto o corpo de 1 tile do jogador ainda sobrepõe o interior da célula (cx, cy).
func overlaps_cell(cx: int, cy: int) -> bool:
	var center_x := cx * TILE_SIZE + HALF_TILE
	var center_y := cy * TILE_SIZE + HALF_TILE
	return absi(x - center_x) < TILE_SIZE and absi(y - center_y) < TILE_SIZE


func to_dict() -> Dictionary:
	return {
		"id": id,
		"slot": slot,
		"x": x,
		"y": y,
		"dir": dir,
		"alive": alive,
		"speed": speed,
		"bombs": max_bombs,
		"range": bomb_range,
		"shield": shield_ticks,
	}
