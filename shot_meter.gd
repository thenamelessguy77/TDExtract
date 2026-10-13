extends Control

var game: Control

func _draw():
	if not is_instance_valid(game) or not game.meter_active:
		return
	var font = get_theme_default_font()
	draw_rect(Rect2(24, 530, 432, 160), Color(0.035, 0.065, 0.065, 0.96))
	draw_string(font, Vector2(24, 554), "TIME YOUR SHOT", HORIZONTAL_ALIGNMENT_CENTER, 432, 19, Color("e7efcf"))
	var bar = Rect2(36, 578, 408, 36)
	draw_rect(bar, Color("964d46"))
	var green_left = game.meter_center - game.meter_width / 2
	draw_rect(Rect2(36 + (green_left - 0.10) * 408, 578, (game.meter_width + 0.20) * 408, 36), Color("c2a04f"))
	draw_rect(Rect2(36 + green_left * 408, 578, game.meter_width * 408, 36), Color("63b877"))
	draw_rect(bar, Color("e7efcf"), false, 2)
	var cursor_x = 36 + game.meter_position * 408
	draw_line(Vector2(cursor_x, 574), Vector2(cursor_x, 618), Color("ffffff"), 4)
	draw_colored_polygon(PackedVector2Array([Vector2(cursor_x, 572), Vector2(cursor_x - 6, 562), Vector2(cursor_x + 6, 562)]), Color("ffffff"))
	draw_string(font, Vector2(24, 639), "GREEN +20 • YELLOW 0 • RED −25", HORIZONTAL_ALIGNMENT_CENTER, 432, 16, Color("eef4df"))
	draw_string(font, Vector2(24, 662), "Tap anywhere • Timeout fires at −25", HORIZONTAL_ALIGNMENT_CENTER, 432, 16, Color("e0b969"))
