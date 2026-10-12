extends Control

const MAP = [
	"############",
	"#..........#",
	"#..##......#",
	"#..##..##..#",
	"#......##..#",
	"#..........#",
	"#..##......#",
	"#..##..##..#",
	"#......##..#",
	"#..........#",
	"#..........#",
	"############"
]
const MAGAZINE_CAPACITY = 7
const CRATE_AMMO = 7
const COMBAT_RELOAD_AP = 2
const CELL = 36.0
const ORIGIN = Vector2(24, 164)
const DIRS = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
var rng = RandomNumberGenerator.new()
var player = Vector2i.ZERO
var exfil = Vector2i.ZERO
var enemies: Array[Dictionary] = []
var loot: Array[Vector2i] = []
var hp = 100
var ap = 2
var ammo = MAGAZINE_CAPACITY
var reserve = 24
var cargo = 0
var stash = 0
var ticks = 0
var combat = false
var finished = false
var selected = -1
var message = ""
var title: Label
var status: Label
var ammo_status: Label
var intel: Label
var feed: Label
var fire_button: Button
var reload_button: Button
var end_button: Button
var extract_button: Button

func _ready():
	rng.randomize()
	stash = int(load_stash())
	make_ui()
	new_raid()

func load_stash():
	if FileAccess.file_exists("user://stash.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://stash.json"))
		if data is Dictionary:
			return data.get("supplies", 0)
	return 0

func make_label(pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label = Label.new()
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

func make_button(text_value: String, pos: Vector2, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text_value
	button.position = pos
	button.size = Vector2(99, 52)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	add_child(button)
	return button

func make_ui():
	title = make_label(Vector2(24, 20), Vector2(280, 32), 22, Color("e7efcf"))
	title.text = "TD / EXTRACTION"
	status = make_label(Vector2(24, 62), Vector2(432, 24), 17, Color("adc5af"))
	ammo_status = make_label(Vector2(24, 86), Vector2(432, 24), 16, Color("adc5af"))
	intel = make_label(Vector2(24, 116), Vector2(432, 42), 14, Color("e0b969"))
	feed = make_label(Vector2(24, 606), Vector2(432, 82), 16, Color("c8d7cd"))
	feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_button = make_button("FIRE", Vector2(24, 700), shoot)
	reload_button = make_button("RELOAD", Vector2(135, 700), reload_weapon)
	end_button = make_button("END TURN", Vector2(246, 700), enemy_turn)
	extract_button = make_button("EXTRACT", Vector2(357, 700), extract)
	make_button("NEW RAID", Vector2(320, 20), new_raid).size = Vector2(136, 36)

func walkable(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.y < MAP.size() and p.x < MAP[0].length() and MAP[p.y][p.x] != "#"

func occupied(p: Vector2i) -> bool:
	for e in enemies:
		if e.hp > 0 and e.pos == p:
			return true
	return false

func new_raid():
	var floor_tiles: Array[Vector2i] = []
	for y in range(12):
		for x in range(12):
			if walkable(Vector2i(x, y)):
				floor_tiles.append(Vector2i(x, y))
	# Local RNG: reproducible under a fixed seed in tests.
	for i in range(floor_tiles.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = floor_tiles[i]
		floor_tiles[i] = floor_tiles[j]
		floor_tiles[j] = temp
	player = floor_tiles.pop_back()
	exfil = floor_tiles.pop_back()
	while distance(player, exfil) < 8:
		floor_tiles.push_front(exfil)
		exfil = floor_tiles.pop_back()
	enemies.clear()
	for i in range(5):
		var pos = floor_tiles.pop_back()
		while distance(pos, player) < 5:
			floor_tiles.push_front(pos)
			pos = floor_tiles.pop_back()
		enemies.append({"pos": pos, "hp": 60})
	loot.clear()
	for i in range(7):
		loot.append(floor_tiles.pop_back())
	hp = 100
	ap = 2
	ammo = MAGAZINE_CAPACITY
	reserve = 24
	cargo = 0
	ticks = 0
	combat = false
	finished = false
	selected = -1
	message = "Tap a tile to travel. Gold crates hold supplies and ammo. Reach the green extraction tile to bank your haul."
	refresh()

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var steps = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, steps):
		var p = Vector2(a).lerp(Vector2(b), float(i) / steps)
		if not walkable(Vector2i(roundi(p.x), roundi(p.y))):
			return false
	return true

func visible(e: Dictionary) -> bool:
	return e.hp > 0 and distance(player, e.pos) <= 6 and line_of_sight(player, e.pos)

func cover_at(p: Vector2i, attacker: Vector2i) -> bool:
	var delta = attacker - p
	var direction = Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
	return not walkable(p + direction)

func hit_chance(from: Vector2i, to: Vector2i) -> int:
	return clampi(95 - distance(from, to) * 8 - (25 if cover_at(to, from) else 0), 15, 95)

func path_to(target: Vector2i) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = [player]
	var parents = {player: player}
	while not frontier.is_empty():
		var p = frontier.pop_front()
		if p == target:
			break
		for d in DIRS:
			var next = p + d
			if walkable(next) and not occupied(next) and not parents.has(next):
				parents[next] = p
				frontier.append(next)
	var path: Array[Vector2i] = []
	if not parents.has(target):
		return path
	var cursor = target
	while cursor != player:
		path.push_front(cursor)
		cursor = parents[cursor]
	return path

func _gui_input(event):
	if finished:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local = event.position - ORIGIN
		if local.x < 0 or local.y < 0 or local.x >= 432 or local.y >= 432:
			return
		var target = Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		for i in range(enemies.size()):
			if enemies[i].pos == target and visible(enemies[i]):
				selected = i
				combat = true
				message = "Target acquired. Fire to engage, or reposition behind cover."
				refresh()
				return
		move_to(target)

func move_to(target: Vector2i):
	var path = path_to(target)
	if path.is_empty():
		message = "Choose a reachable, unoccupied tile."
	for step in path:
		if combat and ap <= 0:
			message = "No action points. End your turn."
			break
		player = step
		ticks += 1
		if combat:
			ap -= 1
		if loot.has(player):
			loot.erase(player)
			cargo += 1
			reserve += CRATE_AMMO
			message = "Recovered supplies and %d reserve rounds. Extract to keep your supplies." % CRATE_AMMO
		if not combat:
			world_tick()
			if combat:
				break
	refresh()

func world_tick():
	# Each exploration action tick advances every enemy once; no real-time timer.
	var spotted = enemies.any(func(e): return visible(e))
	for e in enemies:
		if e.hp <= 0:
			continue
		var next = e.pos + DIRS[rng.randi_range(0, 3)]
		if walkable(next) and not occupied(next) and next != player and next != exfil:
			e.pos = next
	for e in enemies:
		if spotted or visible(e):
			combat = true
			message = "Enemy patrol spotted you. Combat begins."
			break

func shoot():
	if finished or not combat or ap <= 0 or ammo <= 0:
		return
	if selected < 0 or not visible(enemies[selected]):
		message = "Tap a visible enemy first."
		refresh()
		return
	var enemy = enemies[selected]
	ap -= 1
	ammo -= 1
	if rng.randi_range(1, 100) <= hit_chance(player, enemy.pos):
		enemy.hp -= 35
		message = "Hit for 35 damage." if enemy.hp > 0 else "Hostile neutralized."
	else:
		message = "Shot missed. Reposition to improve your odds."
	if enemy.hp <= 0:
		selected = -1
	refresh()

func can_reload() -> bool:
	return not finished and reserve > 0 and ammo < MAGAZINE_CAPACITY and (not combat or ap >= COMBAT_RELOAD_AP)

func reload_weapon():
	if not can_reload():
		return
	var rounds = mini(MAGAZINE_CAPACITY - ammo, reserve)
	ammo += rounds
	reserve -= rounds
	if combat:
		ap -= COMBAT_RELOAD_AP
		message = "Reloaded %d rounds for 2 AP." % rounds
	else:
		ticks += 1
		message = "Reloaded %d rounds. One world tick elapsed." % rounds
		world_tick()
	refresh()

func enemy_turn():
	if finished or not combat:
		return
	var damage = 0
	for e in enemies:
		if e.hp <= 0:
			continue
		# Each enemy has two actions: move one cell or fire once per action.
		for action in range(2):
			if visible(e):
				if rng.randi_range(1, 100) <= hit_chance(e.pos, player):
					hp -= 12
					damage += 12
			else:
				var best = e.pos
				for d in DIRS:
					var next = e.pos + d
					if walkable(next) and not occupied(next) and next != player and distance(next, player) < distance(best, player):
						best = next
				e.pos = best
	ap = 2
	ticks += 1
	message = "Enemy turn: %d damage. Your turn." % damage
	if hp <= 0:
		hp = 0
		finished = true
		message = "Operator lost. Raid cargo lost. Your banked supplies are safe. Start a new raid."
	elif not enemies.any(func(e): return visible(e)):
		combat = false
		selected = -1
		message = "Contact broken. Exploration resumes; patrols advance when you move."
	refresh()

func extract():
	if finished or player != exfil:
		return
	stash += cargo
	var file = FileAccess.open("user://stash.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"supplies": stash}))
	finished = true
	message = "Extraction successful. %d supplies banked. Start a new raid." % cargo
	refresh()

func refresh():
	if not is_instance_valid(status):
		return
	status.text = "HP %d  •  LOOT %d  •  BANK %d" % [hp, cargo, stash]
	ammo_status.text = "GUN %d/%d  •  RESERVE %d  •  TOTAL %d" % [ammo, MAGAZINE_CAPACITY, reserve, ammo + reserve]
	reload_button.tooltip_text = "Reload: 2 AP" if combat else "Reload: 1 world tick"
	intel.text = ("COMBAT   •   %d / 2 AP" % ap) if combat else "EXPLORATION   •   TICK %d" % ticks
	if selected >= 0 and visible(enemies[selected]):
		intel.text += "\nTARGET %d HP   •   HIT %d%%" % [enemies[selected].hp, hit_chance(player, enemies[selected].pos)]
	else:
		intel.text += "\nBlue: operator   Gold: loot   Green: exfil"
	feed.text = message
	fire_button.disabled = finished or not combat or selected < 0 or ap <= 0 or ammo <= 0
	reload_button.disabled = not can_reload()
	end_button.disabled = finished or not combat
	extract_button.disabled = finished or player != exfil
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color("101b1b"))
	for y in range(12):
		for x in range(12):
			var p = Vector2i(x, y)
			var rect = Rect2(ORIGIN + Vector2(p) * CELL, Vector2.ONE * (CELL - 2))
			draw_rect(rect, Color("4a5551") if not walkable(p) else Color("23332f"))
			if walkable(p) and cover_at(p, player):
				draw_rect(Rect2(rect.position + Vector2(2, 28), Vector2(30, 3)), Color("6c7c63"))
	var extract_rect = Rect2(ORIGIN + Vector2(exfil) * CELL + Vector2(3, 3), Vector2(28, 28))
	draw_rect(extract_rect, Color("62b58d"), false, 3)
	for p in loot:
		draw_rect(Rect2(ORIGIN + Vector2(p) * CELL + Vector2(11, 11), Vector2(12, 12)), Color("d6ad58"))
	for i in range(enemies.size()):
		var e = enemies[i]
		if not visible(e):
			continue
		var center = ORIGIN + Vector2(e.pos) * CELL + Vector2(17, 17)
		draw_circle(center, 11, Color("c97061"))
		if selected == i:
			draw_arc(center, 15, 0, TAU, 24, Color("f4df9c"), 2)
		draw_rect(Rect2(center + Vector2(-12, -16), Vector2(24 * maxf(e.hp, 0) / 60.0, 3)), Color("da8d79"))
	draw_circle(ORIGIN + Vector2(player) * CELL + Vector2(17, 17), 11, Color("87c6e3"))
	draw_circle(ORIGIN + Vector2(player) * CELL + Vector2(17, 17), 4, Color("eef4df"))
