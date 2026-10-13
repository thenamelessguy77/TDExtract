extends Control

var game: Control

func _draw():
	if not is_instance_valid(game) or not game.meter_active:
		return
	var font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.065, 0.065, 0.96))
	draw_string(font, Vector2(24, 214), "TIME YOUR SHOT", HORIZONTAL_ALIGNMENT_CENTER, 432, 26, Color("e7efcf"))
	var enemy = game.pending_shot.target
	var base = game.shot_chance(enemy.pos)
	draw_string(font, Vector2(24, 250), "%s • %s • BASE %d%%" % [game.weapon_profile().name, game.SHOT_PROFILES[game.shot_mode].name, base], HORIZONTAL_ALIGNMENT_CENTER, 432, 17, Color("adc5af"))
	draw_string(font, Vector2(24, 287), "Tap anywhere to take the shot", HORIZONTAL_ALIGNMENT_CENTER, 432, 20, Color("eef4df"))
	var bar = Rect2(24, 330, 432, 64)
	draw_rect(bar, Color("964d46"))
	var green_left = game.meter_center - game.meter_width / 2
	draw_rect(Rect2(24 + (green_left - 0.10) * 432, 330, (game.meter_width + 0.20) * 432, 64), Color("c2a04f"))
	draw_rect(Rect2(24 + green_left * 432, 330, game.meter_width * 432, 64), Color("63b877"))
	draw_rect(bar, Color("e7efcf"), false, 2)
	var cursor_x = 24 + game.meter_position * 432
	draw_line(Vector2(cursor_x, 325), Vector2(cursor_x, 399), Color("ffffff"), 4)
	draw_colored_polygon(PackedVector2Array([Vector2(cursor_x, 323), Vector2(cursor_x - 8, 309), Vector2(cursor_x + 8, 309)]), Color("ffffff"))
	draw_string(font, Vector2(24, 442), "GREEN +20 • YELLOW 0 • RED −25", HORIZONTAL_ALIGNMENT_CENTER, 432, 18, Color("eef4df"))
	draw_string(font, Vector2(24, 478), "Green %d%% • Yellow %d%% • Red %d%%" % [clampi(base + game.TIMING_BONUS, 5, 95), base, clampi(base + game.TIMING_PENALTY, 5, 95)], HORIZONTAL_ALIGNMENT_CENTER, 432, 17, Color("adc5af"))
	draw_string(font, Vector2(24, 518), "New speed and green zone every shot", HORIZONTAL_ALIGNMENT_CENTER, 432, 16, Color("e0b969"))
