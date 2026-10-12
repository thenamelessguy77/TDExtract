extends Control

var game: Control

func _draw():
	if is_instance_valid(game):
		game.draw_map(self)
