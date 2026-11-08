class_name Grid
extends RefCounted
## Regras puras do grid 15x13 (GDD §3, ARCHITECTURE D-11/D-12/D-13, NETWORK_PROTOCOL §5.4).
## Sem dependência de nós da Godot; compartilhável com os cenários de conformidade em Go.

const DEFAULT_COLS: int = 15
const DEFAULT_ROWS: int = 13

enum Tile {
	EMPTY = 0,
	WALL = 1,
	BLOCK = 2,
}

## Spawns para até 8 jogadores (slots 0..3 = cantos; slots 4..7 = pontos médios das bordas).
const SPAWNS: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(13, 1),
	Vector2i(1, 11),
	Vector2i(13, 11),
	Vector2i(7, 1),
	Vector2i(7, 11),
	Vector2i(1, 6),
	Vector2i(13, 6),
]

## Zona segura em "L" (spawn + 2 células livres fora de pilares) por slot.
const SPAWN_SAFE_ZONES: Array = [
	[Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
	[Vector2i(13, 1), Vector2i(12, 1), Vector2i(13, 2)],
	[Vector2i(1, 11), Vector2i(2, 11), Vector2i(1, 10)],
	[Vector2i(13, 11), Vector2i(12, 11), Vector2i(13, 10)],
	[Vector2i(7, 1), Vector2i(6, 1), Vector2i(7, 2)],
	[Vector2i(7, 11), Vector2i(8, 11), Vector2i(7, 10)],
	[Vector2i(1, 6), Vector2i(1, 5), Vector2i(2, 5)],
	[Vector2i(13, 6), Vector2i(13, 7), Vector2i(12, 7)],
]

var cols: int = DEFAULT_COLS
var rows: int = DEFAULT_ROWS
var cells: PackedInt32Array = PackedInt32Array()


func _init(c: int = DEFAULT_COLS, r: int = DEFAULT_ROWS) -> void:
	cols = c
	rows = r
	cells.resize(cols * rows)
	cells.fill(Tile.EMPTY)


static func generate(seed_value: int, spawn_count: int = 4, c: int = DEFAULT_COLS, r: int = DEFAULT_ROWS) -> Grid:
	var g := Grid.new(c, r)
	var rng := PRNG.new(seed_value)
	var density_pct := 55 + rng.next_bound(16) # 55..70 inclusive

	var active_spawns := 4 if spawn_count <= 4 else 8
	var safe_map := {}
	for s in range( mini(active_spawns, SPAWN_SAFE_ZONES.size()) ):
		for pt: Vector2i in SPAWN_SAFE_ZONES[s]:
			safe_map[pt.y * c + pt.x] = true

	var candidates: Array[int] = []
	for cy in range(r):
		for cx in range(c):
			var idx := cy * c + cx
			if cx == 0 or cx == c - 1 or cy == 0 or cy == r - 1:
				g.cells[idx] = Tile.WALL
			elif cx % 2 == 0 and cy % 2 == 0:
				g.cells[idx] = Tile.WALL
			elif safe_map.has(idx):
				g.cells[idx] = Tile.EMPTY
			else:
				g.cells[idx] = Tile.EMPTY
				candidates.append(idx)

	# Embaralhamento Fisher-Yates determinístico
	var n := candidates.size()
	for i in range(n - 1, 0, -1):
		var j := rng.next_bound(i + 1)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	@warning_ignore("integer_division")
	var target_blocks: int = (n * density_pct) / 100
	for i in range(target_blocks):
		g.cells[candidates[i]] = Tile.BLOCK

	return g


static func from_ascii(ascii: String, c: int = DEFAULT_COLS, r: int = DEFAULT_ROWS) -> Grid:
	var g := Grid.new(c, r)
	var clean := ""
	for i in range(ascii.length()):
		var ch := ascii[i]
		if ch == "0" or ch == "1" or ch == "2" or ch == "." or ch == "#" or ch == "+":
			clean += ch
	assert(clean.length() == c * r, "from_ascii: tamanho inválido (%d != %d)" % [clean.length(), c * r])
	for idx in range(c * r):
		var ch := clean[idx]
		match ch:
			"0", ".":
				g.cells[idx] = Tile.EMPTY
			"1", "#":
				g.cells[idx] = Tile.WALL
			"2", "+":
				g.cells[idx] = Tile.BLOCK
	return g


func to_compact_string() -> String:
	var out := ""
	for idx in range(cells.size()):
		out += str(cells[idx])
	return out


func clone() -> Grid:
	var g := Grid.new(cols, rows)
	g.cells = cells.duplicate()
	return g


func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cx < cols and cy >= 0 and cy < rows


func get_tile(cx: int, cy: int) -> int:
	if not in_bounds(cx, cy):
		return Tile.WALL
	return cells[cy * cols + cx]


func set_tile(cx: int, cy: int, tile: int) -> void:
	if in_bounds(cx, cy):
		cells[cy * cols + cx] = tile


func is_solid_tile(cx: int, cy: int) -> bool:
	var t := get_tile(cx, cy)
	return t == Tile.WALL or t == Tile.BLOCK


func count_tiles(tile: int) -> int:
	var total := 0
	for v in cells:
		if v == tile:
			total += 1
	return total
