class_name RankedSystem
extends RefCounted
## Sistema de ligas ranqueadas de Bronze até Diamante (GDD & SPEC).
## Gerencia faixas de MMR, deltas por colocação/eliminações, dificuldades de bot e metadados visuais.

const COLOR_BRONZE: Color = Color(0.82, 0.52, 0.26)
const COLOR_PRATA: Color = Color(0.78, 0.84, 0.92)
const COLOR_OURO: Color = Color(1.00, 0.82, 0.20)
const COLOR_PLATINA: Color = Color(0.00, 0.88, 0.85)
const COLOR_DIAMANTE: Color = Color(0.42, 0.72, 1.00)

const ICON_BRONZE: String = "🥉"
const ICON_PRATA: String = "🥈"
const ICON_OURO: String = "🥇"
const ICON_PLATINA: String = "💠"
const ICON_DIAMANTE: String = "💎"


static func get_tier_info(mmr: int) -> Dictionary:
	var league: String = "Bronze"
	var division: String = "Bronze III"
	var icon: String = ICON_BRONZE
	var color: Color = COLOR_BRONZE
	var min_mmr: int = 0
	var next_mmr: int = 900

	if mmr < 900:
		league = "Bronze"
		division = "Bronze III"
		icon = ICON_BRONZE
		color = COLOR_BRONZE
		min_mmr = 0
		next_mmr = 900
	elif mmr < 1000:
		league = "Bronze"
		division = "Bronze II"
		icon = ICON_BRONZE
		color = COLOR_BRONZE
		min_mmr = 900
		next_mmr = 1000
	elif mmr < 1100:
		league = "Bronze"
		division = "Bronze I"
		icon = ICON_BRONZE
		color = COLOR_BRONZE
		min_mmr = 1000
		next_mmr = 1100
	elif mmr < 1166:
		league = "Prata"
		division = "Prata III"
		icon = ICON_PRATA
		color = COLOR_PRATA
		min_mmr = 1100
		next_mmr = 1166
	elif mmr < 1233:
		league = "Prata"
		division = "Prata II"
		icon = ICON_PRATA
		color = COLOR_PRATA
		min_mmr = 1166
		next_mmr = 1233
	elif mmr < 1300:
		league = "Prata"
		division = "Prata I"
		icon = ICON_PRATA
		color = COLOR_PRATA
		min_mmr = 1233
		next_mmr = 1300
	elif mmr < 1366:
		league = "Ouro"
		division = "Ouro III"
		icon = ICON_OURO
		color = COLOR_OURO
		min_mmr = 1300
		next_mmr = 1366
	elif mmr < 1433:
		league = "Ouro"
		division = "Ouro II"
		icon = ICON_OURO
		color = COLOR_OURO
		min_mmr = 1366
		next_mmr = 1433
	elif mmr < 1500:
		league = "Ouro"
		division = "Ouro I"
		icon = ICON_OURO
		color = COLOR_OURO
		min_mmr = 1433
		next_mmr = 1500
	elif mmr < 1583:
		league = "Platina"
		division = "Platina III"
		icon = ICON_PLATINA
		color = COLOR_PLATINA
		min_mmr = 1500
		next_mmr = 1583
	elif mmr < 1666:
		league = "Platina"
		division = "Platina II"
		icon = ICON_PLATINA
		color = COLOR_PLATINA
		min_mmr = 1583
		next_mmr = 1666
	elif mmr < 1750:
		league = "Platina"
		division = "Platina I"
		icon = ICON_PLATINA
		color = COLOR_PLATINA
		min_mmr = 1666
		next_mmr = 1750
	elif mmr < 1850:
		league = "Diamante"
		division = "Diamante III"
		icon = ICON_DIAMANTE
		color = COLOR_DIAMANTE
		min_mmr = 1750
		next_mmr = 1850
	elif mmr < 1950:
		league = "Diamante"
		division = "Diamante II"
		icon = ICON_DIAMANTE
		color = COLOR_DIAMANTE
		min_mmr = 1850
		next_mmr = 1950
	else:
		league = "Diamante"
		division = "Diamante I"
		icon = ICON_DIAMANTE
		color = COLOR_DIAMANTE
		min_mmr = 1950
		next_mmr = 2000

	var progress_pct: int = 100
	if mmr < next_mmr:
		if next_mmr > min_mmr:
			var ratio: float = float(mmr - min_mmr) / float(next_mmr - min_mmr)
			progress_pct = clampi(int(floor(ratio * 100.0)), 0, 100)
		else:
			progress_pct = 100
	else:
		progress_pct = 100

	return {
		"league": league,
		"division": division,
		"icon": icon,
		"color": color,
		"min_mmr": min_mmr,
		"next_mmr": next_mmr,
		"progress_pct": progress_pct,
		"mmr": mmr,
	}


static func format_badge(mmr: int) -> String:
	var info := get_tier_info(mmr)
	return "%s %s (%d MMR)" % [info["icon"], info["division"], mmr]


static func calculate_mmr_delta(current_mmr: int, placement: int, total_players: int, kills: int) -> int:
	var base: int = 0
	if total_players <= 4:
		match placement:
			1: base = 36
			2: base = 16
			3: base = -10
			4: base = -20
			_: base = -20
	else:
		match placement:
			1: base = 48
			2: base = 32
			3: base = 20
			4: base = 10
			5: base = -4
			6: base = -10
			7: base = -16
			8: base = -22
			_: base = -22

	var delta: int = base + (kills * 4)
	if current_mmr < 1100 and delta < 0:
		@warning_ignore("integer_division")
		delta = delta / 2
	return delta


static func bot_difficulty_for_mmr(mmr: int) -> String:
	if mmr < 1100:
		return "easy"
	elif mmr < 1500:
		return "medium"
	return "hard"


static func all_leagues_summary() -> Array[Dictionary]:
	return [
		{
			"league": "Bronze",
			"name": "Bronze",
			"icon": ICON_BRONZE,
			"range": "0 - 1099",
			"min_mmr": 0,
			"max_mmr": 1099,
			"color": COLOR_BRONZE,
			"divisions": ["Bronze III", "Bronze II", "Bronze I"],
		},
		{
			"league": "Prata",
			"name": "Prata",
			"icon": ICON_PRATA,
			"range": "1100 - 1299",
			"min_mmr": 1100,
			"max_mmr": 1299,
			"color": COLOR_PRATA,
			"divisions": ["Prata III", "Prata II", "Prata I"],
		},
		{
			"league": "Ouro",
			"name": "Ouro",
			"icon": ICON_OURO,
			"range": "1300 - 1499",
			"min_mmr": 1300,
			"max_mmr": 1499,
			"color": COLOR_OURO,
			"divisions": ["Ouro III", "Ouro II", "Ouro I"],
		},
		{
			"league": "Platina",
			"name": "Platina",
			"icon": ICON_PLATINA,
			"range": "1500 - 1749",
			"min_mmr": 1500,
			"max_mmr": 1749,
			"color": COLOR_PLATINA,
			"divisions": ["Platina III", "Platina II", "Platina I"],
		},
		{
			"league": "Diamante",
			"name": "Diamante",
			"icon": ICON_DIAMANTE,
			"range": "1750+",
			"min_mmr": 1750,
			"max_mmr": 9999,
			"color": COLOR_DIAMANTE,
			"divisions": ["Diamante III", "Diamante II", "Diamante I"],
		},
	]
