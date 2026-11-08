class_name PRNG
extends RefCounted
## Gerador pseudoaleatório determinístico xorshift32 (ARCHITECTURE D-12 e §5).
## Garante a mesma sequência em GDScript e em Go para qualquer seed u32.

const MASK32: int = 0xFFFFFFFF

var state: int = 1


func _init(seed_value: int = 1) -> void:
	var s := seed_value & MASK32
	state = s if s != 0 else 1


func next_u32() -> int:
	var x := state & MASK32
	x = (x ^ ((x << 13) & MASK32)) & MASK32
	x = (x ^ ((x >> 17) & MASK32)) & MASK32
	x = (x ^ ((x << 5) & MASK32)) & MASK32
	state = x
	return x


func next_bound(bound: int) -> int:
	assert(bound > 0, "bound deve ser > 0")
	return next_u32() % bound

