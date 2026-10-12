extends Control

const MAP_SIZE = 24
const EDGE_BAND = 2
const BUILDINGS = [Rect2i(3, 14, 6, 6), Rect2i(14, 3, 7, 6), Rect2i(14, 14, 7, 7)]
const DOORS = [Vector2i(6, 19), Vector2i(14, 6), Vector2i(17, 14)]
var MAP: Array[String] = []
const AP_PER_TURN = 4
const MAX_AP = 8
const AIM_BONUS = 30
const MAP_VIEW_SIZE = Vector2(432, 360)
const SHOT_PROFILES = [
	{"name": "NORMAL", "damage": 35, "accuracy": 0, "ap": 1},
	{"name": "HEAD", "damage": 60, "accuracy": -20, "ap": 1},
	{"name": "BODY", "damage": 25, "accuracy": 15, "ap": 1},
	{"name": "BURST", "damage": 35, "accuracy": -15, "ap": 2}
]
const MAX_HEALTH = 100
const CRATE_HEALTH = 25
const LOW_COVER_PENALTY = 25
const RAID_LOOT_COUNT = 4
const OBJECTIVE_MIN_DISTANCE = 8
const RAID_ENEMY_COUNT = 6
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
var loot: Array[Dictionary] = []
var objective = Vector2i.ZERO
var objective_collected = false
var hp = MAX_HEALTH
var ap = AP_PER_TURN
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
var shot_mode = 0
var aiming = false
var shot_buttons: Array[Button] = []
var aim_button: Button
var shot_info: Label
var fire_button: Button
var reload_button: Button
var end_button: Button
var extract_button: Button
var search_button: Button
var objective_button: Button
var map_view: Control
var camera = Vector2.ZERO
var pointer_down = false
var pointer_start = Vector2.ZERO
var pointer_last = Vector2.ZERO
var pointer_dragged = false

func _ready():
	build_map()
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
	map_view = Control.new()
	map_view.set_script(load("res://map_view.gd"))
	map_view.game = self
	map_view.position = ORIGIN
	map_view.size = MAP_VIEW_SIZE
	map_view.clip_contents = true
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_view)
	title = make_label(Vector2(24, 20), Vector2(280, 32), 22, Color("e7efcf"))
	title.text = "TD / EXTRACTION"
	status = make_label(Vector2(24, 62), Vector2(432, 24), 17, Color("adc5af"))
	ammo_status = make_label(Vector2(24, 86), Vector2(432, 24), 16, Color("adc5af"))
	intel = make_label(Vector2(24, 116), Vector2(432, 42), 14, Color("e0b969"))
	feed = make_label(Vector2(24, 638), Vector2(432, 52), 14, Color("c8d7cd"))
	feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feed.size.y = 52
	for i in range(SHOT_PROFILES.size()):
		var button = make_button(SHOT_PROFILES[i].name, Vector2(24 + i * 111, 534), choose_shot.bind(i))
		button.size = Vector2(99, 44)
		button.toggle_mode = true
		shot_buttons.append(button)
	aim_button = make_button("AIM • 1 AP", Vector2(24, 588), aim_weapon)
	aim_button.size = Vector2(99, 44)
	aim_button.add_theme_font_size_override("font_size", 14)
	shot_info = make_label(Vector2(135, 588), Vector2(321, 48), 14, Color("e0b969"))
	fire_button = make_button("FIRE", Vector2(24, 700), shoot)
	reload_button = make_button("RELOAD", Vector2(135, 700), reload_weapon)
	end_button = make_button("END TURN", Vector2(246, 700), enemy_turn)
	extract_button = make_button("EXTRACT", Vector2(357, 700), extract)
	make_button("CENTER", Vector2(24, 756), center_player).size = Vector2(136, 40)
	search_button = make_button("SEARCH", Vector2(172, 756), search_nearby_body)
	search_button.size = Vector2(136, 40)
	objective_button = make_button("OBJECTIVE", Vector2(320, 756), center_objective)
	objective_button.size = Vector2(136, 40)
	make_button("NEW RAID", Vector2(320, 20), new_raid).size = Vector2(136, 36)

func tile_at(p: Vector2i) -> String:
	if p.x < 0 or p.y < 0 or p.y >= MAP.size() or p.x >= MAP[0].length():
		return "#"
	return MAP[p.y][p.x]

func walkable(p: Vector2i) -> bool:
	return tile_at(p) == "."

func blocks_sight(p: Vector2i) -> bool:
	return tile_at(p) == "#"

func adjacent_low_cover(p: Vector2i) -> bool:
	for direction in DIRS:
		if tile_at(p + direction) == "=":
			return true
	return false

func occupied(p: Vector2i) -> bool:
	for e in enemies:
		if e.hp > 0 and e.pos == p:
			return true
	return false

func new_raid():
	var floor_tiles: Array[Vector2i] = []
	for y in range(MAP.size()):
		for x in range(MAP[0].length()):
			if walkable(Vector2i(x, y)):
				floor_tiles.append(Vector2i(x, y))
	# Local RNG: reproducible under a fixed seed in tests.
	for i in range(floor_tiles.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = floor_tiles[i]
		floor_tiles[i] = floor_tiles[j]
		floor_tiles[j] = temp
	var insertion_tiles: Array[Vector2i] = []
	for tile in floor_tiles:
		if is_outskirts(tile) and not is_indoors(tile):
			insertion_tiles.append(tile)
	assert(not insertion_tiles.is_empty())
	player = insertion_tiles[rng.randi_range(0, insertion_tiles.size() - 1)]
	floor_tiles.erase(player)
	var extraction_tiles: Array[Vector2i] = []
	for tile in floor_tiles:
		if is_outskirts(tile) and not is_indoors(tile) and distance(player, tile) >= 8:
			extraction_tiles.append(tile)
	assert(not extraction_tiles.is_empty())
	exfil = extraction_tiles[rng.randi_range(0, extraction_tiles.size() - 1)]
	floor_tiles.erase(exfil)
	var objective_tiles: Array[Vector2i] = []
	for tile in floor_tiles:
		if is_indoors(tile) and distance(player, tile) >= OBJECTIVE_MIN_DISTANCE:
			objective_tiles.append(tile)
	assert(not objective_tiles.is_empty(), "A distant indoor objective location is required")
	objective = objective_tiles[rng.randi_range(0, objective_tiles.size() - 1)]
	floor_tiles.erase(objective)
	objective_collected = false
	enemies.clear()
	for i in range(RAID_ENEMY_COUNT):
		var pos = floor_tiles.pop_back()
		while distance(pos, player) < 5:
			floor_tiles.push_front(pos)
			pos = floor_tiles.pop_back()
		enemies.append({"pos": pos, "hp": 60, "facing": DIRS[rng.randi_range(0, 3)], "alerted": false, "last_seen": pos})
	loot.clear()
	var indoor: Array[Vector2i] = []
	var outdoor: Array[Vector2i] = []
	for tile in floor_tiles:
		if is_indoors(tile):
			indoor.append(tile)
		else:
			outdoor.append(tile)
	for i in range(RAID_LOOT_COUNT):
		var pool = indoor if i < RAID_LOOT_COUNT - 1 else outdoor
		loot.append({"pos": pool.pop_back(), "kind": rng.randi_range(0, 2)})
	hp = MAX_HEALTH
	ap = AP_PER_TURN
	shot_mode = 0
	aiming = false
	ammo = MAGAZINE_CAPACITY
	reserve = 24
	cargo = 0
	ticks = 0
	combat = false
	finished = false
	selected = -1
	message = "Search buildings for the hidden objective, then extract. Search buildings for crates. Drag to explore the map; tap to move."
	center_player()
	refresh()

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var steps = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, steps):
		var p = Vector2(a).lerp(Vector2(b), float(i) / steps)
		if blocks_sight(Vector2i(roundi(p.x), roundi(p.y))):
			return false
	return true

func player_can_see(p: Vector2i) -> bool:
	return distance(player, p) <= 6 and line_of_sight(player, p)

func objective_visible() -> bool:
	return not objective_collected and player_can_see(objective)

func visible(e: Dictionary) -> bool:
	return e.hp > 0 and distance(player, e.pos) <= 6 and line_of_sight(player, e.pos)

func cover_at(p: Vector2i, attacker: Vector2i) -> bool:
	# Only the defender's adjacent low barrier facing the incoming shot matters.
	# Side/rear shots flank cover; shooting over the attacker's own cover is free.
	var delta = attacker - p
	for direction in DIRS:
		if tile_at(p + direction) != "=" or delta.x * direction.x + delta.y * direction.y <= 0:
			continue
		if direction.x != 0 and absi(delta.x) >= absi(delta.y):
			return true
		if direction.y != 0 and absi(delta.y) >= absi(delta.x):
			return true
	return false

func hit_chance(from: Vector2i, to: Vector2i) -> int:
	return clampi(95 - distance(from, to) * 8 - (LOW_COVER_PENALTY if cover_at(to, from) else 0), 15, 95)

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
	var bounds = Rect2(ORIGIN, MAP_VIEW_SIZE)
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and bounds.has_point(event.position):
			var amount = -CELL * 2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else CELL * 2
			camera += Vector2(amount, 0) if event.shift_pressed else Vector2(0, amount)
			clamp_camera()
			map_view.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and bounds.has_point(event.position):
				pointer_down = true
				pointer_start = event.position
				pointer_last = event.position
				pointer_dragged = false
			elif not event.pressed and pointer_down:
				pointer_down = false
				if not pointer_dragged and bounds.has_point(event.position) and not finished:
					select_tile(Vector2i((event.position - ORIGIN + camera) / CELL))
	elif event is InputEventMouseMotion and pointer_down:
		if event.position.distance_to(pointer_start) > 8:
			pointer_dragged = true
		if pointer_dragged:
			camera -= event.position - pointer_last
			clamp_camera()
			map_view.queue_redraw()
		pointer_last = event.position

func select_tile(target: Vector2i):
	for i in range(enemies.size()):
		if enemies[i].pos != target:
			continue
		if enemies[i].hp <= 0 and distance(player, target) <= 1:
			search_body(i)
			return
		if visible(enemies[i]):
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
		aiming = false
		ticks += 1
		if combat:
			ap -= 1
		if player == objective and not objective_collected:
			objective_collected = true
			message = "Objective secured. Reach the green extraction tile."
		for i in range(loot.size()):
			if loot[i].pos == player:
				var kind = loot[i].kind
				loot.remove_at(i)
				apply_loot(kind, "Crate")
				break
		if not combat:
			world_tick()
			if combat:
				break
	if not Rect2(camera, MAP_VIEW_SIZE).has_point(Vector2(player) * CELL + Vector2(18, 18)):
		center_player()
	refresh()

func facing_toward(delta: Vector2i) -> Vector2i:
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y)) if delta.y != 0 else Vector2i.LEFT

func enemy_can_see_player(e: Dictionary) -> bool:
	if not visible(e):
		return false
	var delta = player - Vector2i(e.pos)
	var facing = Vector2i(e.get("facing", Vector2i.LEFT))
	var forward = delta.x * facing.x + delta.y * facing.y
	var sideways = absi(delta.x * facing.y - delta.y * facing.x)
	return forward > 0 and forward >= sideways

func spot_player(e: Dictionary):
	e.alerted = true
	e.last_seen = player

func patrol_step(e: Dictionary):
	var options: Array[Vector2i] = []
	for direction in DIRS:
		var next = e.pos + direction
		if walkable(next) and not occupied(next) and next != player and next != exfil:
			options.append(direction)
	if not options.is_empty():
		var direction = options[rng.randi_range(0, options.size() - 1)]
		e.facing = direction
		e.pos += direction

func world_tick():
	var spotted = false
	for e in enemies:
		if enemy_can_see_player(e):
			spot_player(e)
			spotted = true
	for e in enemies:
		if e.hp > 0:
			patrol_step(e)
	for e in enemies:
		if enemy_can_see_player(e):
			spot_player(e)
			spotted = true
	if spotted:
		combat = true
		message = "Enemy patrol spotted you. Combat begins."

func choose_shot(mode: int):
	if mode < 0 or mode >= SHOT_PROFILES.size():
		return
	shot_mode = mode
	refresh()

func shot_chance(target: Vector2i) -> int:
	return clampi(hit_chance(player, target) + SHOT_PROFILES[shot_mode].accuracy + (AIM_BONUS if aiming else 0), 5, 95)

func aim_weapon():
	if finished or not combat or ap < 1 or aiming:
		return
	ap -= 1
	aiming = true
	message = "Aiming: +30 accuracy for your next attack. Movement or a hit cancels it."
	refresh()

func can_fire() -> bool:
	return not finished and combat and ap >= SHOT_PROFILES[shot_mode].ap and ammo >= (2 if shot_mode == 3 else 1) and selected >= 0 and selected < enemies.size() and visible(enemies[selected])

func shoot():
	if not can_fire():
		return
	var enemy = enemies[selected]
	var profile = SHOT_PROFILES[shot_mode]
	var chance = shot_chance(enemy.pos)
	var rounds = mini(ammo, rng.randi_range(2, 3)) if shot_mode == 3 else 1
	spot_player(enemy)
	ap -= profile.ap
	ammo -= rounds
	aiming = false
	var hits = 0
	for round_index in range(rounds):
		if rng.randi_range(1, 100) <= chance:
			enemy.hp -= profile.damage
			hits += 1
	message = "%s: %d/%d hits, %d damage." % [profile.name, hits, rounds, hits * profile.damage]
	if enemy.hp <= 0:
		enemy.loot_kind = rng.randi_range(0, 2)
		enemy.searched = false
		selected = -1
		message += " Hostile down."
	refresh()

func take_damage(amount: int):
	if amount > 0:
		hp = maxi(0, hp - amount)
		aiming = false

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
			if enemy_can_see_player(e):
				spot_player(e)
				if rng.randi_range(1, 100) <= hit_chance(e.pos, player):
					take_damage(12)
					damage += 12
			elif e.get("alerted", false):
				var target = Vector2i(e.get("last_seen", e.pos))
				var best = e.pos
				for d in DIRS:
					var next = e.pos + d
					if walkable(next) and not occupied(next) and next != player and distance(next, target) < distance(best, target):
						best = next
				e.facing = facing_toward(best - Vector2i(e.pos)) if best != e.pos else facing_toward(target - Vector2i(e.pos))
				e.pos = best
			else:
				patrol_step(e)
	ap = mini(MAX_AP, ap + AP_PER_TURN)
	ticks += 1
	message = "Enemy turn: %d damage. Your turn." % damage
	if hp <= 0:
		hp = 0
		finished = true
		message = "Operator lost. Raid cargo lost. Your banked supplies are safe. Start a new raid."
	elif not enemies.any(func(e): return enemy_can_see_player(e)):
		combat = false
		selected = -1
		message = "Contact broken. Exploration resumes; patrols advance when you move."
	refresh()

func extract():
	if finished or player != exfil:
		return
	if not objective_collected:
		message = "Extraction locked. Collect the purple objective first."
		refresh()
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
	status.text = "HP %d • LOOT %d • BANK %d • OBJ %s" % [hp, cargo, stash, "OK" if objective_collected else "--"]
	ammo_status.text = "GUN %d/%d  •  RESERVE %d  •  TOTAL %d" % [ammo, MAGAZINE_CAPACITY, reserve, ammo + reserve]
	reload_button.tooltip_text = "Reload: 2 AP" if combat else "Reload: 1 world tick"
	intel.text = ("COMBAT • %d AP (max 8)" % ap) if combat else "EXPLORATION   •   TICK %d" % ticks
	if aiming:
		intel.text += " • AIMED"
	if adjacent_low_cover(player):
		intel.text += "   •   COVER"
	if selected >= 0 and visible(enemies[selected]):
		intel.text += "\nTARGET %d HP • HIT %d%%%s" % [enemies[selected].hp, shot_chance(enemies[selected].pos), " • COVER" if cover_at(enemies[selected].pos, player) else ""]
	else:
		intel.text += "\nPurple: objective • Green: exfil • Arrows: facing"
	feed.text = message
	var profile = SHOT_PROFILES[shot_mode]
	shot_info.text = "%s • %d AP • %d damage%s" % [profile.name, profile.ap, profile.damage, "/round" if shot_mode == 3 else ""]
	shot_info.text += "\nAim +30 • %s • %s" % ["2–3 ammo" if shot_mode == 3 else "1 ammo", "AIM READY" if aiming else "not aimed"]
	for i in range(shot_buttons.size()):
		shot_buttons[i].set_pressed_no_signal(i == shot_mode)
		shot_buttons[i].tooltip_text = "%d damage, %+d accuracy points, %d AP" % [SHOT_PROFILES[i].damage, SHOT_PROFILES[i].accuracy, SHOT_PROFILES[i].ap]
		shot_buttons[i].disabled = finished
	aim_button.disabled = finished or not combat or ap < 1 or aiming
	fire_button.disabled = not can_fire()
	reload_button.disabled = not can_reload()
	end_button.disabled = finished or not combat
	end_button.tooltip_text = "End turn: bank unused AP and gain four, up to eight. Enemies act first."
	objective_button.text = "EXFIL" if objective_collected else "OBJECTIVE"
	objective_button.disabled = not objective_collected and not objective_visible()
	search_button.disabled = finished or (combat and ap < 1) or nearby_body() < 0
	search_button.tooltip_text = "Search body: 1 AP" if combat else "Search body: 1 world tick"
	map_view.queue_redraw()
	extract_button.disabled = finished or player != exfil or not objective_collected
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color("101b1b"))

func draw_map(canvas: Control):
	for y in range(MAP.size()):
		for x in range(MAP[0].length()):
			var p = Vector2i(x, y)
			var rect = Rect2(map_point(p), Vector2.ONE * (CELL - 2))
			canvas.draw_rect(rect, Color("4a5551") if blocks_sight(p) else (Color("354039") if is_indoors(p) else Color("23332f")))
			if tile_at(p) == "=":
				canvas.draw_rect(Rect2(rect.position + Vector2(3, 9), Vector2(28, 16)), Color("85936d"))
				for stripe in range(4):
					canvas.draw_line(rect.position + Vector2(5 + stripe * 7, 10), rect.position + Vector2(5 + stripe * 7, 23), Color("c0cca1"), 2)
	if objective_collected:
		var extract_rect = Rect2(map_point(exfil) + Vector2(3, 3), Vector2(28, 28))
		canvas.draw_rect(extract_rect, Color("62b58d"), false, 3)
	if objective_visible():
		var center = map_point(objective) + Vector2(17, 17)
		canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -12), center + Vector2(12, 0), center + Vector2(0, 12), center + Vector2(-12, 0)]), Color("c89bdf"))
	for crate in loot:
		if not player_can_see(crate.pos):
			continue
		var center = map_point(crate.pos) + Vector2(17, 17)
		canvas.draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), Color("d6ad58"))
	for i in range(enemies.size()):
		var e = enemies[i]
		if e.hp <= 0:
			if distance(player, e.pos) <= 6 and line_of_sight(player, e.pos):
				var body_center = map_point(e.pos) + Vector2(17, 17)
				var body_color = Color("778078") if e.get("searched", false) else Color("e0c090")
				canvas.draw_line(body_center - Vector2(8, 5), body_center + Vector2(8, 5), body_color, 4)
				canvas.draw_line(body_center + Vector2(-8, 5), body_center + Vector2(8, -5), body_color, 4)
			continue
		if not visible(e):
			continue
		var center = map_point(e.pos) + Vector2(17, 17)
		canvas.draw_circle(center, 11, Color("c97061"))
		var forward = Vector2(e.get("facing", Vector2i.LEFT))
		var side = Vector2(-forward.y, forward.x)
		canvas.draw_colored_polygon(PackedVector2Array([center + forward * 14, center + forward * 4 + side * 5, center + forward * 4 - side * 5]), Color("fff0c0"))
		draw_cover_edges(canvas, e.pos, Color("e6be91"))
		if selected == i:
			canvas.draw_arc(center, 15, 0, TAU, 24, Color("f4df9c"), 2)
		canvas.draw_rect(Rect2(center + Vector2(-12, -16), Vector2(24 * maxf(e.hp, 0) / 60.0, 3)), Color("da8d79"))
	canvas.draw_circle(map_point(player) + Vector2(17, 17), 11, Color("87c6e3"))
	canvas.draw_circle(map_point(player) + Vector2(17, 17), 4, Color("eef4df"))

	draw_cover_edges(canvas, player, Color("a0dcd6"))

func draw_cover_edges(canvas: Control, p: Vector2i, color: Color):
	var center = map_point(p) + Vector2(17, 17)
	for direction in DIRS:
		if tile_at(p + direction) == "=":
			var normal = Vector2(direction)
			var tangent = Vector2(-normal.y, normal.x)
			canvas.draw_line(center + normal * 15 - tangent * 9, center + normal * 15 + tangent * 9, color, 3)

func build_map():
	var rows: Array[String] = []
	for y in range(MAP_SIZE):
		var row = ""
		for x in range(MAP_SIZE):
			row += "#" if x == 0 or y == 0 or x == MAP_SIZE - 1 or y == MAP_SIZE - 1 else "."
		rows.append(row)
	MAP = rows
	for block in [Rect2i(3, 2, 2, 2), Rect2i(7, 3, 2, 2), Rect2i(3, 6, 2, 2), Rect2i(7, 7, 2, 2)]:
		for y in range(block.position.y, block.end.y):
			for x in range(block.position.x, block.end.x):
				set_tile(Vector2i(x, y), "#")
	for i in range(BUILDINGS.size()):
		var room = BUILDINGS[i]
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				if x == room.position.x or x == room.end.x - 1 or y == room.position.y or y == room.end.y - 1:
					set_tile(Vector2i(x, y), "#")
		set_tile(DOORS[i], ".")
	for p in [Vector2i(3, 9), Vector2i(4, 9), Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 10), Vector2i(11, 10), Vector2i(4, 12), Vector2i(5, 12), Vector2i(5, 16), Vector2i(6, 17), Vector2i(17, 5), Vector2i(17, 6), Vector2i(17, 17), Vector2i(18, 17)]:
		assert(walkable(p))
		for y in range(-1, 2):
			for x in range(-1, 2):
				assert(not blocks_sight(p + Vector2i(x, y)), "Low cover must have a floor-tile gap from full walls, including diagonals")
		set_tile(p, "=")

func set_tile(p: Vector2i, value: String):
	MAP[p.y] = MAP[p.y].substr(0, p.x) + value + MAP[p.y].substr(p.x + 1)

func is_indoors(p: Vector2i) -> bool:
	for room in BUILDINGS:
		if Rect2i(room.position + Vector2i.ONE, room.size - Vector2i(2, 2)).has_point(p):
			return true
	return false

func clamp_camera():
	camera.x = clampf(camera.x, 0, MAP[0].length() * CELL - 432)
	camera.y = clampf(camera.y, 0, MAP.size() * CELL - MAP_VIEW_SIZE.y)

func center_player():
	camera = Vector2(player) * CELL + Vector2(18, 18) - MAP_VIEW_SIZE / 2
	clamp_camera()
	if is_instance_valid(map_view):
		map_view.queue_redraw()

func center_objective():
	if not objective_collected and not objective_visible():
		return
	camera = Vector2(exfil if objective_collected else objective) * CELL + Vector2(18, 18) - MAP_VIEW_SIZE / 2
	clamp_camera()
	map_view.queue_redraw()

func map_point(p: Vector2i) -> Vector2:
	return Vector2(p) * CELL - camera

func apply_loot(kind: int, source: String):
	cargo += 1
	var rounds = CRATE_AMMO if kind != 1 else 0
	var healed = mini(CRATE_HEALTH, MAX_HEALTH - hp) if kind != 0 else 0
	reserve += rounds
	hp += healed
	message = "%s: +%d ammo, +%d HP, +1 supply." % [source, rounds, healed]

func nearby_body() -> int:
	for i in range(enemies.size()):
		if enemies[i].hp <= 0 and not enemies[i].get("searched", false) and distance(player, enemies[i].pos) <= 1:
			return i
	return -1

func search_nearby_body():
	search_body(nearby_body())

func search_body(index: int):
	if finished or index < 0 or index >= enemies.size() or (combat and ap < 1):
		return
	var body = enemies[index]
	if body.hp > 0 or body.get("searched", false) or distance(player, body.pos) > 1:
		return
	body.searched = true
	apply_loot(int(body.get("loot_kind", 0)), "Body")
	ticks += 1
	if combat:
		ap -= 1
	else:
		world_tick()
	refresh()

func is_outskirts(p: Vector2i) -> bool:
	return walkable(p) and mini(mini(p.x, p.y), mini(MAP[0].length() - 1 - p.x, MAP.size() - 1 - p.y)) <= EDGE_BAND
