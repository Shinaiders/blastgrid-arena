class_name MenuBackdrop
extends Control
## Fundo festivo de arcade ("Oficina de Fogos") e visualização viva de Sparky (Menu Overhaul).
## Desenha proceduralmente o gradiente noturno, grade de perspectiva retro, partículas flutuantes
## e o pedestal holográfico com Sparky gigante animado em tempo real.

var anim_time: float = 0.0
var show_character_showcase: bool = false
var showcase_pos: Vector2 = Vector2(290, 310)
var character_id: String = "sparky_a"

var _particles: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_particles()


func _process(delta: float) -> void:
	anim_time += delta
	queue_redraw()


func _init_particles() -> void:
	_particles.clear()
	var cols: Array[Color] = [
		Color(1.0, 0.82, 0.25, 0.75), # Gold
		Color(0.0, 0.85, 0.84, 0.70), # Cyan
		Color(1.0, 0.38, 0.35, 0.70), # Coral
	]
	for i in range(28):
		_particles.append({
			"x_ratio": randf(),
			"y_ratio": randf(),
			"speed": randf_range(20.0, 48.0),
			"size": randf_range(1.6, 3.4),
			"col": cols[i % cols.size()],
			"phase": randf_range(0.0, TAU),
		})


static func get_character_color(cid: String) -> Color:
	match cid:
		"sparky_a": return Color(1.00, 0.37, 0.35, 1.0) # Volt (Coral)
		"sparky_b": return Color(0.00, 0.85, 0.84, 1.0) # Ember (Ciano)
		"sparky_c": return Color(0.55, 0.91, 0.45, 1.0) # Moss (Lima)
		"sparky_d": return Color(1.00, 0.78, 0.15, 1.0) # Frost (Âmbar)
		_: return Color(1.00, 0.37, 0.35, 1.0)


static func get_character_name(cid: String) -> String:
	match cid:
		"sparky_a": return "Volt"
		"sparky_b": return "Ember"
		"sparky_c": return "Moss"
		"sparky_d": return "Frost"
		_: return "Sparky"


static func _draw_rounded_box(canvas: CanvasItem, rect: Rect2, radius: float, bg_col: Color, border_col: Color = Color.TRANSPARENT, border_w: float = 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	if border_col.a > 0.0 and border_w > 0.0:
		sb.border_color = border_col
		sb.set_border_width_all(int(ceilf(border_w)))
	sb.draw(canvas.get_canvas_item(), rect)


static func draw_mini_sparky(canvas: CanvasItem, center: Vector2, scale_f: float, col: Color, t: float) -> void:
	draw_sparky_figure(canvas, center, scale_f, col, t, false)


static func draw_sparky_figure(canvas: CanvasItem, center: Vector2, scale_f: float, col: Color, t: float, draw_orbs: bool = false) -> void:
	# 1. Sombra elíptica dinâmica no chão
	var sh_w := 24.0 * scale_f
	var sh_h := 8.0 * scale_f
	var shadow_pts: PackedVector2Array = []
	for deg in range(16):
		var ang := float(deg) * TAU / 16.0
		shadow_pts.append(center + Vector2(cos(ang) * sh_w, 16.0 * scale_f + sin(ang) * sh_h))
	canvas.draw_colored_polygon(shadow_pts, Color(0.02, 0.03, 0.06, 0.48))

	# 2. Pezinhos batendo ritmo
	var step_l := maxf(0.0, sin(t * 5.0)) * 4.0 * scale_f
	var step_r := maxf(0.0, -sin(t * 5.0)) * 4.0 * scale_f
	var lf := center + Vector2(-9.0 * scale_f, 13.0 * scale_f - step_l)
	var rf := center + Vector2(9.0 * scale_f, 13.0 * scale_f - step_r)
	_draw_rounded_box(canvas, Rect2(lf.x - 5.0 * scale_f, lf.y - 3.5 * scale_f, 10.0 * scale_f, 7.0 * scale_f), 3.0 * scale_f, Color(0.12, 0.14, 0.22), Color(0.06, 0.07, 0.12), 1.0)
	canvas.draw_line(lf + Vector2(-3.5 * scale_f, 2.5 * scale_f), lf + Vector2(3.5 * scale_f, 2.5 * scale_f), col.lightened(0.2), 1.5 * scale_f)
	_draw_rounded_box(canvas, Rect2(rf.x - 5.0 * scale_f, rf.y - 3.5 * scale_f, 10.0 * scale_f, 7.0 * scale_f), 3.0 * scale_f, Color(0.12, 0.14, 0.22), Color(0.06, 0.07, 0.12), 1.0)
	canvas.draw_line(rf + Vector2(-3.5 * scale_f, 2.5 * scale_f), rf + Vector2(3.5 * scale_f, 2.5 * scale_f), col.lightened(0.2), 1.5 * scale_f)

	# 3. Tronco com cinto LED
	var torso_rect := Rect2(center.x - 10.0 * scale_f, center.y + 1.0 * scale_f, 20.0 * scale_f, 12.0 * scale_f)
	_draw_rounded_box(canvas, torso_rect, 4.0 * scale_f, Color(0.15, 0.18, 0.28), Color(0.08, 0.09, 0.15), 1.2 * scale_f)
	canvas.draw_line(center + Vector2(-9.0 * scale_f, 8.0 * scale_f), center + Vector2(9.0 * scale_f, 8.0 * scale_f), Color(0.25, 0.30, 0.42), 2.0 * scale_f)
	canvas.draw_circle(center + Vector2(0.0, 8.0 * scale_f), 2.5 * scale_f, col.lightened(0.3))

	# 4. Mãozinhas flutuando
	var lh := center + Vector2(-18.0 * scale_f, 5.0 * scale_f + sin(t * 3.5) * 2.5 * scale_f)
	var rh := center + Vector2(18.0 * scale_f, 5.0 * scale_f - sin(t * 3.5) * 2.5 * scale_f)
	canvas.draw_circle(lh, 4.5 * scale_f, Color(0.08, 0.09, 0.15))
	canvas.draw_circle(lh, 3.4 * scale_f, Color(0.92, 0.94, 0.98))
	canvas.draw_circle(lh + Vector2(-1.0, -1.0) * scale_f, 1.2 * scale_f, Color.WHITE)

	canvas.draw_circle(rh, 4.5 * scale_f, Color(0.08, 0.09, 0.15))
	canvas.draw_circle(rh, 3.4 * scale_f, Color(0.92, 0.94, 0.98))
	canvas.draw_circle(rh + Vector2(-1.0, -1.0) * scale_f, 1.2 * scale_f, Color.WHITE)

	# 5. Capacete arredondado 3D na cor do personagem
	var hw := 34.0 * scale_f
	var hh := 27.0 * scale_f
	var head_rect := Rect2(center.x - hw * 0.5, center.y - 20.0 * scale_f, hw, hh)

	# Fones laterais
	var ear_y := head_rect.position.y + hh * 0.52
	_draw_rounded_box(canvas, Rect2(head_rect.position.x - 4.5 * scale_f, ear_y - 5.5 * scale_f, 5.5 * scale_f, 11.0 * scale_f), 2.5 * scale_f, Color(0.14, 0.16, 0.25), Color(0.07, 0.08, 0.14), 1.0)
	_draw_rounded_box(canvas, Rect2(head_rect.position.x + hw - 1.0 * scale_f, ear_y - 5.5 * scale_f, 5.5 * scale_f, 11.0 * scale_f), 2.5 * scale_f, Color(0.14, 0.16, 0.25), Color(0.07, 0.08, 0.14), 1.0)
	canvas.draw_circle(Vector2(head_rect.position.x - 1.5 * scale_f, ear_y), 1.5 * scale_f, col.lightened(0.4))
	canvas.draw_circle(Vector2(head_rect.position.x + hw + 1.5 * scale_f, ear_y), 1.5 * scale_f, col.lightened(0.4))

	# Base e sombra de volume
	_draw_rounded_box(canvas, Rect2(head_rect.position.x, head_rect.position.y + 4.0 * scale_f, hw, hh - 4.0 * scale_f), 10.0 * scale_f, col.darkened(0.28), Color(0.07, 0.08, 0.14), 2.0 * scale_f)
	# Capacete principal
	_draw_rounded_box(canvas, head_rect, 10.0 * scale_f, col, Color(0.07, 0.08, 0.14), 2.2 * scale_f)
	# Brilho especular no topo
	_draw_rounded_box(canvas, Rect2(head_rect.position.x + 4.0 * scale_f, head_rect.position.y + 3.0 * scale_f, hw * 0.42, 4.5 * scale_f), 2.5 * scale_f, Color(1, 1, 1, 0.35))

	# 6. Antena com mola e esfera brilhante pulsante
	var ant_root := Vector2(center.x, head_rect.position.y + 1.0 * scale_f)
	var swing := sin(t * 3.5) * 3.0 * scale_f
	var mid_seg := ant_root + Vector2(swing * 0.4, -6.0 * scale_f)
	var tip_seg := ant_root + Vector2(swing, -16.0 * scale_f)
	canvas.draw_line(ant_root, mid_seg, Color(0.10, 0.12, 0.18), 3.2 * scale_f)
	canvas.draw_line(mid_seg, tip_seg, Color(0.10, 0.12, 0.18), 2.8 * scale_f)
	canvas.draw_line(ant_root, mid_seg, Color(0.85, 0.88, 0.95), 1.8 * scale_f)
	canvas.draw_line(mid_seg, tip_seg, Color(0.85, 0.88, 0.95), 1.6 * scale_f)

	var pulse := 0.75 + 0.25 * sin(t * 8.0)
	canvas.draw_circle(tip_seg, 6.5 * scale_f * pulse, Color(1.0, 0.85, 0.25, 0.35))
	canvas.draw_circle(tip_seg, 4.2 * scale_f, Color(1.0, 0.88, 0.32, 1.0))
	canvas.draw_circle(tip_seg + Vector2(-1.0, -1.0) * scale_f, 1.5 * scale_f, Color.WHITE)

	# 7. Visor com olhos LED piscando
	var vw := 24.0 * scale_f
	var vh := 13.0 * scale_f
	var visor_rect := Rect2(center.x - vw * 0.5, head_rect.position.y + 10.0 * scale_f, vw, vh)
	_draw_rounded_box(canvas, visor_rect, 5.5 * scale_f, Color(0.06, 0.08, 0.15), Color(0.03, 0.04, 0.08), 1.4 * scale_f)
	canvas.draw_line(visor_rect.position + Vector2(3.0 * scale_f, 10.0 * scale_f), visor_rect.position + Vector2(10.0 * scale_f, 3.0 * scale_f), Color(1, 1, 1, 0.22), 1.4 * scale_f)

	var is_blinking: bool = fmod(t + 0.3, 3.0) < 0.15
	if is_blinking:
		canvas.draw_line(visor_rect.position + Vector2(4.5 * scale_f, 6.5 * scale_f), visor_rect.position + Vector2(9.0 * scale_f, 6.5 * scale_f), Color(0.4, 0.95, 1.0, 0.9), 2.0 * scale_f)
		canvas.draw_line(visor_rect.position + Vector2(15.0 * scale_f, 6.5 * scale_f), visor_rect.position + Vector2(19.5 * scale_f, 6.5 * scale_f), Color(0.4, 0.95, 1.0, 0.9), 2.0 * scale_f)
	else:
		canvas.draw_circle(visor_rect.position + Vector2(6.5 * scale_f, 6.5 * scale_f), 2.4 * scale_f, Color(0.4, 0.98, 1.0, 1.0))
		canvas.draw_circle(visor_rect.position + Vector2(6.0 * scale_f, 5.8 * scale_f), 0.9 * scale_f, Color.WHITE)
		canvas.draw_circle(visor_rect.position + Vector2(17.5 * scale_f, 6.5 * scale_f), 2.4 * scale_f, Color(0.4, 0.98, 1.0, 1.0))
		canvas.draw_circle(visor_rect.position + Vector2(17.0 * scale_f, 5.8 * scale_f), 0.9 * scale_f, Color.WHITE)

	# 8. Três orbes de power-up orbitando
	if draw_orbs:
		var orb_colors: Array[Color] = [
			Color(1.0, 0.35, 0.25), # Bomba
			Color(0.20, 0.85, 1.0), # Patins (velocidade)
			Color(1.0, 0.85, 0.25), # Chama (raio)
		]
		var orbit_rx := 64.0 * scale_f
		var orbit_ry := 24.0 * scale_f
		for i in range(3):
			var ang := t * 2.0 + float(i) * TAU / 3.0
			var orb_pos := center + Vector2(cos(ang) * orbit_rx, sin(ang) * orbit_ry - 4.0 * scale_f)
			var orb_col: Color = orb_colors[i]
			canvas.draw_circle(orb_pos, 7.5 * scale_f, Color(orb_col.r, orb_col.g, orb_col.b, 0.35))
			canvas.draw_circle(orb_pos, 4.8 * scale_f, orb_col)
			canvas.draw_circle(orb_pos + Vector2(-1.2 * scale_f, -1.2 * scale_f), 1.6 * scale_f, Color.WHITE)


func _draw() -> void:
	var vp_sz := size if size.x > 10.0 and size.y > 10.0 else Vector2(1280, 720)

	# 1. Fundo escuro profundo com faixas de gradiente noturno
	draw_rect(Rect2(Vector2.ZERO, vp_sz), Color(0.06, 0.07, 0.13))
	var band_h := vp_sz.y / 10.0
	for b in range(10):
		var frac := float(b) / 10.0
		var band_col := Color(0.05, 0.06, 0.11).lerp(Color(0.08, 0.10, 0.18), frac)
		draw_rect(Rect2(0, b * band_h, vp_sz.x, band_h + 1.0), band_col)

	# 2. Grade de piso em perspectiva sutil na metade inferior
	var horizon_y := vp_sz.y * 0.48
	var grid_col := Color(0.11, 0.14, 0.24, 0.45)
	for i in range(1, 11):
		var t_ratio := float(i) / 10.0
		var line_y := horizon_y + (vp_sz.y - horizon_y) * (t_ratio * t_ratio)
		draw_line(Vector2(0, line_y), Vector2(vp_sz.x, line_y), grid_col, 1.2)

	var vp_persp := Vector2(vp_sz.x * 0.5, horizon_y - 50.0)
	for step in range(-14, 15):
		var bot_x := vp_sz.x * 0.5 + float(step) * (vp_sz.x / 16.0)
		var dir := (Vector2(bot_x, vp_sz.y) - vp_persp).normalized()
		var start_pt := vp_persp + dir * 65.0
		var end_pt := Vector2(bot_x, vp_sz.y)
		draw_line(start_pt, end_pt, grid_col, 1.0)

	# 3. 28 partículas flutuantes (faíscas douradas, ciano e coral)
	if _particles.is_empty():
		_init_particles()
	for p in _particles:
		var x: float = fmod(float(p["x_ratio"]) * vp_sz.x + sin(anim_time * 1.2 + float(p["phase"])) * 22.0, vp_sz.x)
		if x < 0.0:
			x += vp_sz.x
		var y: float = fmod(float(p["y_ratio"]) * vp_sz.y - anim_time * float(p["speed"]), vp_sz.y)
		if y < 0.0:
			y += vp_sz.y
		var sz: float = float(p["size"])
		var c: Color = p["col"]
		draw_circle(Vector2(x, y), sz * 2.0, Color(c.r, c.g, c.b, c.a * 0.35))
		draw_circle(Vector2(x, y), sz, c)
		draw_circle(Vector2(x, y), sz * 0.45, Color(1, 1, 1, 0.85))

	# 4. Preview Ao Vivo do Sparky
	if show_character_showcase:
		var ped_y := showcase_pos.y + 40.0

		# Raios holográficos verticais
		var beam_pts := PackedVector2Array([
			Vector2(showcase_pos.x - 65.0, ped_y),
			Vector2(showcase_pos.x + 65.0, ped_y),
			Vector2(showcase_pos.x + 46.0, showcase_pos.y - 85.0),
			Vector2(showcase_pos.x - 46.0, showcase_pos.y - 85.0)
		])
		draw_colored_polygon(beam_pts, Color(0.0, 0.85, 0.84, 0.06 + 0.02 * sin(anim_time * 4.0)))

		# Pedestal holográfico brilhante (anéis concêntricos animados)
		var pulse_a := 0.55 + 0.25 * sin(anim_time * 3.0)
		var pulse_b := 0.55 + 0.25 * cos(anim_time * 4.0)
		draw_arc(Vector2(showcase_pos.x, ped_y), 68.0, 0.0, TAU, 36, Color(0.0, 0.85, 0.84, 0.50 * pulse_a), 2.5)
		draw_arc(Vector2(showcase_pos.x, ped_y), 50.0, 0.0, TAU, 36, Color(1.0, 0.80, 0.22, 0.60 * pulse_b), 2.0)
		draw_arc(Vector2(showcase_pos.x, ped_y), 32.0, 0.0, TAU, 28, Color(0.2, 0.90, 1.0, 0.70 * pulse_a), 1.5)

		# Sparky gigante (~1.8x)
		var char_col := get_character_color(character_id)
		draw_sparky_figure(self, showcase_pos, 1.8, char_col, anim_time, true)
