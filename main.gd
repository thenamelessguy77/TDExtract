extends Control

const MAP_SIZE = 48
const DISTRICT_SIZE = 24
const DISTRICT_OFFSETS = [Vector2i(0, 0), Vector2i(24, 0), Vector2i(0, 24), Vector2i(24, 24)]
const EDGE_BAND = 2
const BASE_BUILDINGS = [Rect2i(3, 14, 6, 6), Rect2i(14, 3, 7, 6), Rect2i(14, 14, 7, 7)]
const BASE_DOORS = [Vector2i(6, 19), Vector2i(14, 6), Vector2i(17, 14)]
var BUILDINGS: Array[Rect2i] = []
var DOORS: Array[Vector2i] = []
var MAP: Array[String] = []
const AP_PER_TURN = 4
const AIM_BONUS = 30
const TIMING_BONUS = 20
const TIMING_PENALTY = -25
const SIGHT_RANGE = 10
const HEARING_RANGE = 12
const INVESTIGATION_ACTIONS = 32
const SEARCH_ACTIONS = 4
const MIN_ZOOM = 0.5
const MAX_ZOOM = 1.5
const ZOOM_STEP = 0.125
const MAP_VIEW_SIZE = Vector2(432, 360)
const SHOT_PROFILES = [
	{"name": "BODY", "accuracy": 0},
	{"name": "HEAD", "accuracy": -20},
	{"name": "BURST", "accuracy": -15}
]
const WEAPONS = [
	{"name": "PISTOL", "ammo_type": "9mm", "magazine": 7, "damage": 35, "accuracy": 95, "falloff": 5, "range": 10, "ap": 1, "burst": true},
	{"name": "RIFLE", "ammo_type": "5.56", "magazine": 20, "damage": 40, "accuracy": 95, "falloff": 4, "range": 10, "ap": 1, "burst": true},
	{"name": "SHOTGUN", "ammo_type": "12GA", "magazine": 6, "damage": 55, "accuracy": 105, "falloff": 10, "range": 6, "ap": 2, "burst": false},
	{"name": "SNIPER", "ammo_type": "7.62", "magazine": 5, "damage": 65, "accuracy": 95, "falloff": 2, "range": 10, "ap": 2, "burst": false},
	{"name": "SMG", "ammo_type": ".45", "magazine": 25, "damage": 24, "accuracy": 100, "falloff": 6, "range": 10, "ap": 1, "burst": true}
]
const BLEED_CHANCE = 15
const BLEED_DAMAGE = 3
const MAX_HEALTH = 100
const CRATE_HEALTH = 25
const COVER_PENALTY = 25
const RAID_LOOT_COUNT = 16
const OBJECTIVE_MIN_DISTANCE = 16
const RAID_ENEMY_COUNT = 24
const CRATE_AMMO = 7
const COMBAT_RELOAD_AP = 2
const MOVE_SECONDS = 0.09
const CELL = 36.0
const ORIGIN = Vector2(24, 164)
const DIRS = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
var animations_enabled = true
var movement_active = false
var animation_running = false
var motion_epoch = 0
var motion_tween: Tween
var player_draw_pos = Vector2.ZERO
var player_motion: Array[Vector2] = []
var meter_rng = RandomNumberGenerator.new()
var meter_active = false
var meter_direction = 1.0
var meter_position = 0.0
var meter_speed = 1.5
var meter_center = 0.5
var meter_width = 0.12
var pending_shot: Dictionary = {}
var meter_overlay: Control
var last_shot_modifier = 0
var last_shot_chance = 0
var rng = RandomNumberGenerator.new()
var bleed_rng = RandomNumberGenerator.new()
var weapon_id = 0
var carried_ammo: Array[int] = [24, 0, 0, 0, 0]
var saved_gear: Dictionary = {}
var pending_gun: Dictionary = {}
var gun_dialog: ConfirmationDialog
var inventory_dialog: AcceptDialog
var gear_button: Button
var bleeding = false
var bandages = 1
var health_kits = 0
var inventory_heal_button: Button
var inventory_bandage_button: Button
var bandage_button: Button
var player = Vector2i.ZERO
var exfil = Vector2i.ZERO
var enemies: Array[Dictionary] = []
var loot: Array[Dictionary] = []
var objective = Vector2i.ZERO
var objective_collected = false
var hp = MAX_HEALTH
var ap = AP_PER_TURN
var ammo = 7
var reserve: int:
	get:
		return carried_ammo[weapon_id]
	set(value):
		carried_ammo[weapon_id] = maxi(0, value)
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
var map_zoom = 1.0
var takedown_button: Button
var zoom_label: Label
var zoom_in_button: Button
var zoom_out_button: Button
var pointer_down = false
var pointer_start = Vector2.ZERO
var pointer_last = Vector2.ZERO
var pointer_dragged = false

func _ready():
	build_map()
	rng.randomize()
	bleed_rng.randomize()
	meter_rng.randomize()
	load_stash()
	make_ui()
	new_raid()

func default_gear() -> Dictionary:
	return {"weapon_id": 0, "ammo": 7, "carried_ammo": [24, 0, 0, 0, 0]}

func sanitize_gear(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return default_gear()
	var weapon = clampi(int(data.get("weapon_id", 0)), 0, WEAPONS.size() - 1)
	var rounds = data.get("carried_ammo", [24, 0, 0, 0, 0])
	if not rounds is Array or rounds.size() != WEAPONS.size():
		rounds = [24, 0, 0, 0, 0]
	var safe_rounds: Array[int] = []
	for count in rounds:
		safe_rounds.append(clampi(int(count), 0, 9999))
	return {"weapon_id": weapon, "ammo": clampi(int(data.get("ammo", WEAPONS[weapon].magazine)), 0, WEAPONS[weapon].magazine), "carried_ammo": safe_rounds}

func load_stash():
	saved_gear = default_gear()
	if FileAccess.file_exists("user://stash.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://stash.json"))
		if data is Dictionary:
			stash = maxi(0, int(data.get("supplies", 0)))
			saved_gear = sanitize_gear(data.get("gear", default_gear()))

func save_stash(gear: Dictionary):
	var file = FileAccess.open("user://stash.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"supplies": stash, "gear": gear}))

func current_gear() -> Dictionary:
	return {"weapon_id": weapon_id, "ammo": ammo, "carried_ammo": carried_ammo.duplicate()}

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
	takedown_button = make_button("TAKEDOWN", Vector2(30, 476), takedown_nearby)
	takedown_button.size = Vector2(136, 40)
	takedown_button.add_theme_font_size_override("font_size", 14)
	zoom_out_button = make_button("−", Vector2(354, 476), zoom_map.bind(-1))
	zoom_out_button.size = Vector2(44, 40)
	zoom_in_button = make_button("+", Vector2(406, 476), zoom_map.bind(1))
	zoom_in_button.size = Vector2(44, 40)
	zoom_label = make_label(Vector2(302, 480), Vector2(48, 30), 13, Color("eef4df"))
	title = make_label(Vector2(170, 20), Vector2(140, 32), 16, Color("e7efcf"))
	title.text = "TD / EXTRACT"
	gear_button = make_button("INVENTORY", Vector2(24, 20), show_inventory)
	gear_button.size = Vector2(136, 36)
	gear_button.add_theme_font_size_override("font_size", 14)
	inventory_dialog = AcceptDialog.new()
	inventory_dialog.title = "Inventory"
	inventory_dialog.ok_button_text = "CLOSE"
	inventory_dialog.exclusive = true
	add_child(inventory_dialog)
	inventory_heal_button = inventory_dialog.add_button("USE KIT", false, "heal")
	inventory_bandage_button = inventory_dialog.add_button("BANDAGE", false, "bandage")
	inventory_dialog.custom_action.connect(inventory_action)
	gun_dialog = ConfirmationDialog.new()
	gun_dialog.title = "Weapon found"
	gun_dialog.exclusive = true
	gun_dialog.ok_button_text = "TAKE GUN"
	gun_dialog.cancel_button_text = "KEEP CURRENT"
	gun_dialog.confirmed.connect(take_found_gun)
	gun_dialog.canceled.connect(decline_gun)
	add_child(gun_dialog)
	status = make_label(Vector2(24, 62), Vector2(432, 24), 17, Color("adc5af"))
	ammo_status = make_label(Vector2(24, 86), Vector2(432, 24), 16, Color("adc5af"))
	intel = make_label(Vector2(24, 116), Vector2(432, 42), 14, Color("e0b969"))
	feed = make_label(Vector2(24, 638), Vector2(432, 52), 14, Color("c8d7cd"))
	feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feed.size.y = 52
	for i in range(SHOT_PROFILES.size()):
		var button = make_button(SHOT_PROFILES[i].name, Vector2(24 + i * 148, 534), choose_shot.bind(i))
		button.size = Vector2(136, 44)
		button.toggle_mode = true
		shot_buttons.append(button)
	aim_button = make_button("AIM • 1 AP", Vector2(24, 588), aim_weapon)
	aim_button.size = Vector2(99, 44)
	aim_button.add_theme_font_size_override("font_size", 14)
	bandage_button = make_button("BANDAGE (1)", Vector2(135, 588), use_bandage)
	bandage_button.size = Vector2(99, 44)
	bandage_button.add_theme_font_size_override("font_size", 12)
	shot_info = make_label(Vector2(246, 588), Vector2(210, 48), 12, Color("e0b969"))
	fire_button = make_button("FIRE", Vector2(24, 700), begin_shot)
	reload_button = make_button("RELOAD", Vector2(135, 700), reload_weapon)
	end_button = make_button("END TURN", Vector2(246, 700), enemy_turn)
	extract_button = make_button("EXTRACT", Vector2(357, 700), extract)
	make_button("CENTER", Vector2(24, 756), center_player).size = Vector2(136, 40)
	search_button = make_button("SEARCH", Vector2(172, 756), search_nearby_body)
	search_button.size = Vector2(136, 40)
	objective_button = make_button("OBJECTIVE", Vector2(320, 756), center_objective)
	objective_button.size = Vector2(136, 40)
	make_button("NEW RAID", Vector2(320, 20), new_raid).size = Vector2(136, 36)
	meter_overlay = Control.new()
	meter_overlay.set_script(load("res://shot_meter.gd"))
	meter_overlay.game = self
	meter_overlay.size = Vector2(480, 800)
	meter_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	meter_overlay.focus_mode = Control.FOCUS_ALL
	meter_overlay.gui_input.connect(meter_input)
	meter_overlay.hide()
	add_child(meter_overlay)

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
	meter_active = false
	pending_shot = {}
	if is_instance_valid(meter_overlay):
		meter_overlay.hide()
	motion_epoch += 1
	if is_instance_valid(motion_tween):
		motion_tween.kill()
	movement_active = false
	animation_running = false
	# Only extracted gear is secured; unextracted pickups are discarded on restart.
	var gear = sanitize_gear(saved_gear)
	weapon_id = gear.weapon_id
	ammo = gear.ammo
	carried_ammo.assign(gear.carried_ammo)
	pending_gun = {}
	if is_instance_valid(gun_dialog):
		gun_dialog.hide()
		inventory_dialog.hide()
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
		var pos = Vector2i.ZERO
		for index in range(floor_tiles.size() - 1, -1, -1):
			var candidate = floor_tiles[index]
			if district_at(candidate) == i % DISTRICT_OFFSETS.size() and distance(candidate, player) >= 5:
				pos = candidate
				floor_tiles.remove_at(index)
				break
		assert(pos != Vector2i.ZERO, "Every district must have safe patrol spawn locations")
		var gun = rng.randi_range(0, WEAPONS.size() - 1)
		enemies.append({"pos": pos, "hp": 60, "facing": DIRS[rng.randi_range(0, 3)], "alerted": false, "last_seen": pos, "weapon_id": gun, "ammo_type": gun, "ammo": WEAPONS[gun].magazine, "reserve": rng.randi_range(0, WEAPONS[gun].magazine), "gun_available": true})
	loot.clear()
	var indoor: Array[Vector2i] = []
	var outdoor: Array[Vector2i] = []
	for tile in floor_tiles:
		if is_indoors(tile):
			indoor.append(tile)
		else:
			outdoor.append(tile)
	for i in range(RAID_LOOT_COUNT):
		var pool = indoor if i < RAID_LOOT_COUNT * 3 / 4 else outdoor
		var pos = Vector2i.ZERO
		for index in range(pool.size() - 1, -1, -1):
			if district_at(pool[index]) == i % DISTRICT_OFFSETS.size():
				pos = pool[index]
				pool.remove_at(index)
				break
		assert(pos != Vector2i.ZERO, "Each district needs indoor and outdoor loot positions")
		var kind = rng.randi_range(0, 3)
		var gun = rng.randi_range(1, WEAPONS.size() - 1) if kind == 2 else -1
		loot.append({"pos": pos, "kind": kind, "ammo_type": rng.randi_range(0, WEAPONS.size() - 1) if kind == 0 else -1, "weapon_id": gun, "ammo": rng.randi_range(0, WEAPONS[gun].magazine) if gun >= 0 else 0, "gun_available": kind == 2, "searched": false})
	hp = MAX_HEALTH
	bleeding = false
	bandages = 1
	health_kits = 0
	ap = AP_PER_TURN
	shot_mode = 0
	aiming = false
	cargo = 0
	ticks = 0
	combat = false
	finished = false
	selected = -1
	message = "Search crates and bodies for gear. Open Inventory to view ammo and use medical items."
	player_draw_pos = Vector2(player)
	set_map_zoom(1.0)
	center_player()
	refresh()

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func clear_ray(a: Vector2i, b: Vector2i) -> bool:
	if blocks_sight(a) or blocks_sight(b):
		return false
	var steps = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, steps):
		var p = Vector2(a).lerp(Vector2(b), float(i) / steps)
		if blocks_sight(Vector2i(roundi(p.x), roundi(p.y))):
			return false
	return true

func peek_positions(p: Vector2i) -> Array[Vector2i]:
	var positions: Array[Vector2i] = [p]
	if not walkable(p):
		return positions
	for direction in DIRS:
		if tile_at(p + direction) != "#":
			continue
		var tangent = Vector2i(-direction.y, direction.x)
		for side in [tangent, -tangent]:
			if walkable(p + side) and walkable(p + direction + side) and not positions.has(p + side):
				positions.append(p + side)
	return positions

func sight_with_peeking(a: Vector2i, b: Vector2i, target_peeks: bool) -> bool:
	var targets: Array[Vector2i] = []
	if target_peeks:
		targets = peek_positions(b)
	else:
		targets.append(b)
	for origin in peek_positions(a):
		for target in targets:
			if clear_ray(origin, target):
				return true
	return false

func line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	# Actors may lean at either end, so exposed peeking positions can be fired on.
	return sight_with_peeking(a, b, true)

func player_can_see(p: Vector2i) -> bool:
	# Stationary loot/objectives cannot lean out from behind their own walls.
	return distance(player, p) <= SIGHT_RANGE and sight_with_peeking(player, p, false)

func objective_visible() -> bool:
	return not objective_collected and player_can_see(objective)

func visible(e: Dictionary) -> bool:
	return e.hp > 0 and distance(player, e.pos) <= SIGHT_RANGE and line_of_sight(player, e.pos)

func cover_at(p: Vector2i, attacker: Vector2i) -> bool:
	# Only defensive cover affects aim; the shooter can peek over or around it.
	# Low barriers protect their facing side; full walls protect exposed corners.
	var delta = attacker - p
	for direction in DIRS:
		if tile_at(p + direction) != "=" or delta.x * direction.x + delta.y * direction.y <= 0:
			continue
		if direction.x != 0 and absi(delta.x) >= absi(delta.y):
			return true
		if direction.y != 0 and absi(delta.y) >= absi(delta.x):
			return true
	return corner_cover_at(p, attacker)

func hit_chance(from: Vector2i, to: Vector2i) -> int:
	return weapon_hit_chance(from, to, WEAPONS[0])

func weapon_hit_chance(from: Vector2i, to: Vector2i, weapon: Dictionary) -> int:
	return clampi(weapon.accuracy - distance(from, to) * weapon.falloff - (COVER_PENALTY if cover_at(to, from) else 0), 15, 95)

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
	if gun_dialog.visible or inventory_dialog.visible:
		return
	var bounds = Rect2(ORIGIN, MAP_VIEW_SIZE)
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and bounds.has_point(event.position):
			set_map_zoom(map_zoom + (ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else -ZOOM_STEP), event.position - ORIGIN)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and bounds.has_point(event.position):
				pointer_down = true
				pointer_start = event.position
				pointer_last = event.position
				pointer_dragged = false
			elif not event.pressed and pointer_down:
				pointer_down = false
				if not pointer_dragged and bounds.has_point(event.position) and not finished:
					select_tile(Vector2i(((event.position - ORIGIN) / map_zoom + camera) / CELL))
	elif event is InputEventMouseMotion and pointer_down:
		if event.position.distance_to(pointer_start) > 8:
			pointer_dragged = true
		if pointer_dragged:
			camera -= (event.position - pointer_last) / map_zoom
			clamp_camera()
			map_view.queue_redraw()
		pointer_last = event.position

func select_tile(target: Vector2i):
	if busy() or finished or gun_dialog.visible:
		return
	for crate in loot:
		if crate.pos == target and crate.get("searched", false) and crate.get("gun_available", false) and distance(player, target) <= 1:
			offer_gun(crate)
			return
	for i in range(enemies.size()):
		if enemies[i].pos != target:
			continue
		if enemies[i].hp <= 0 and distance(player, target) <= 1:
			search_body(i)
			return
		if visible(enemies[i]):
			selected = i
			if can_takedown(i):
				message = "Unaware guard: TAKEDOWN costs 1 tick; FIRE starts combat."
				refresh()
				return
			enter_combat()
			message = "Target acquired. Fire to engage, or reposition behind cover."
			refresh()
			return
	move_to(target)

func move_to(target: Vector2i):
	if busy() or finished or gun_dialog.visible:
		return
	var path = path_to(target)
	var epoch = motion_epoch
	movement_active = not path.is_empty()
	if path.is_empty():
		message = "Choose a reachable, unoccupied tile."
	while not path.is_empty():
		var step = path.pop_front()
		if occupied(step):
			path = path_to(target)
			if path.is_empty():
				message = "Route blocked. Choose another tile."
				break
			continue
		if finished:
			break
		if combat and ap <= 0:
			message = "No action points. End your turn."
			break
		begin_motion()
		var was_combat = combat
		player = step
		aiming = false
		ticks += 1
		if combat:
			ap -= 1
		if player == objective and not objective_collected:
			objective_collected = true
			message = "Objective secured. Reach the green extraction tile."
		var found_crate: Dictionary = {}
		for crate in loot:
			if crate.pos == player:
				found_crate = crate
				if not crate.get("searched", false):
					crate.searched = true
					apply_loot(crate.kind, "Crate", maxi(0, int(crate.get("ammo_type", 0))))
				break
		if not combat:
			world_tick()
		if not Rect2(camera, map_visible_size()).has_point(Vector2(player) * CELL + Vector2(18, 18)):
			center_player()
		if not await animate_motion() or epoch != motion_epoch:
			return
		if not found_crate.is_empty():
			if not finished and found_crate.get("gun_available", false):
				offer_gun(found_crate)
			elif not found_crate.get("gun_available", false):
				loot.erase(found_crate)
		if (not was_combat and combat) or gun_dialog.visible or finished:
			break
	movement_active = false
	if not Rect2(camera, map_visible_size()).has_point(Vector2(player) * CELL + Vector2(18, 18)):
		center_player()
	refresh()

func busy() -> bool:
	return movement_active or animation_running or meter_active

func begin_motion():
	player_draw_pos = Vector2(player)
	player_motion = [player_draw_pos]
	for e in enemies:
		e.draw_pos = Vector2(e.pos)
		e.draw_facing = e.get("facing", Vector2i.LEFT)
		e.motion_visible = visible(e)
		e.motion_path = [Vector2(e.pos)]

func record_enemy_motion(e: Dictionary):
	if e.has("motion_path") and e.motion_path.back() != Vector2(e.pos):
		e.motion_path.append(Vector2(e.pos))

func motion_position(points: Array, elapsed_steps: float) -> Vector2:
	var index = mini(floori(elapsed_steps), points.size() - 1)
	if index >= points.size() - 1:
		return Vector2(points.back())
	return Vector2(points[index]).lerp(Vector2(points[index + 1]), elapsed_steps - index)

func update_motion(elapsed_steps: float):
	player_draw_pos = motion_position(player_motion, elapsed_steps)
	for e in enemies:
		if e.has("motion_path"):
			e.draw_pos = motion_position(e.motion_path, elapsed_steps)
			var segment = floori(elapsed_steps)
			e.draw_facing = facing_toward(Vector2i(e.motion_path[segment + 1] - e.motion_path[segment])) if segment < e.motion_path.size() - 1 else e.get("facing", Vector2i.LEFT)
	map_view.queue_redraw()

func animate_motion() -> bool:
	if player_motion.back() != Vector2(player):
		player_motion.append(Vector2(player))
	var steps = player_motion.size() - 1
	for e in enemies:
		steps = maxi(steps, e.get("motion_path", [e.pos]).size() - 1)
	if not animations_enabled or steps == 0:
		update_motion(float(steps))
		return true
	var epoch = motion_epoch
	animation_running = true
	refresh()
	motion_tween = create_tween()
	motion_tween.tween_method(update_motion, 0.0, float(steps), steps * MOVE_SECONDS)
	await get_tree().create_timer(steps * MOVE_SECONDS).timeout
	if epoch != motion_epoch:
		return false
	if is_instance_valid(motion_tween):
		motion_tween.kill()
	update_motion(float(steps))
	animation_running = false
	refresh()
	return true

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
	e.investigating = false
	e.last_seen = player

func patrol_step(e: Dictionary):
	var options: Array[Vector2i] = []
	for direction in DIRS:
		var next = e.pos + direction
		if walkable(next) and not occupied(next) and next != player and next != exfil:
			options.append(direction)
	if options.is_empty():
		return
	var heading = Vector2i(e.get("facing", Vector2i.LEFT))
	var remaining = int(e.get("patrol_remaining", 0))
	if remaining <= 0 and e.get("patrol_started", false) and not e.get("patrol_pause", false):
		e.patrol_pause = true
		return
	var direction = heading
	if not options.has(heading) or remaining <= 0:
		var choices: Array[Vector2i] = []
		for option in options:
			if option != -heading:
				choices.append(option)
		if choices.is_empty():
			choices = options
		# Favor continuing straight when choosing the next short patrol leg.
		direction = heading if choices.has(heading) and rng.randf() < 0.65 else choices[rng.randi_range(0, choices.size() - 1)]
		remaining = rng.randi_range(3, 6)
	e.patrol_remaining = remaining - 1
	e.patrol_started = true
	e.patrol_pause = false
	e.facing = direction
	e.pos += direction
	record_enemy_motion(e)

func hear_gunshot(origin: Vector2i, shooter: Dictionary = {}):
	for e in enemies:
		if e.hp <= 0 or e == shooter or e.get("alerted", false) or distance(e.pos, origin) > HEARING_RANGE:
			continue
		begin_investigation(e, origin)

func begin_investigation(e: Dictionary, origin: Vector2i):
	e.investigating = true
	e.investigate_pos = origin
	e.investigate_remaining = INVESTIGATION_ACTIONS
	e.search_remaining = SEARCH_ACTIONS
	e.patrol_remaining = 0
	e.patrol_started = false
	e.patrol_pause = false

func guard_route_step(e: Dictionary, target: Vector2i) -> Vector2i:
	var frontier: Array[Vector2i] = [e.pos]
	var parents = {e.pos: e.pos}
	var endpoint = Vector2i(-1, -1)
	while not frontier.is_empty():
		var p = frontier.pop_front()
		if distance(p, target) <= 1:
			endpoint = p
			break
		var directions = DIRS.duplicate()
		# Prefer the current heading on equally short routes.
		var heading = Vector2i(e.get("facing", Vector2i.LEFT))
		directions.erase(heading)
		directions.push_front(heading)
		for direction in directions:
			var next = p + direction
			if walkable(next) and not parents.has(next) and not occupied(next) and next != player:
				parents[next] = p
				frontier.append(next)
	if endpoint == Vector2i(-1, -1) or endpoint == e.pos:
		return e.pos
	var cursor = endpoint
	while parents[cursor] != e.pos:
		cursor = parents[cursor]
	return cursor

func investigation_step(e: Dictionary):
	var target = Vector2i(e.get("investigate_pos", e.pos))
	e.investigate_remaining = int(e.get("investigate_remaining", INVESTIGATION_ACTIONS)) - 1
	if distance(e.pos, target) <= 1:
		var remaining = int(e.get("search_remaining", SEARCH_ACTIONS))
		e.facing = facing_toward(target - Vector2i(e.pos)) if remaining == SEARCH_ACTIONS else Vector2i(-e.facing.y, e.facing.x)
		e.search_remaining = remaining - 1
	else:
		var next = guard_route_step(e, target)
		if next != e.pos:
			e.facing = facing_toward(next - Vector2i(e.pos))
			e.pos = next
			record_enemy_motion(e)
	if int(e.investigate_remaining) <= 0 or int(e.get("search_remaining", SEARCH_ACTIONS)) <= 0:
		e.investigating = false
		e.alerted = false
		e.patrol_remaining = 0
		e.patrol_started = false
		e.patrol_pause = false

func can_takedown(index: int) -> bool:
	if busy() or finished or combat or gun_dialog.visible or index < 0 or index >= enemies.size():
		return false
	var e = enemies[index]
	return e.hp > 0 and not e.get("alerted", false) and player == Vector2i(e.pos) - Vector2i(e.get("facing", Vector2i.LEFT)) and not enemies.any(func(guard): return enemy_can_see_player(guard))

func nearby_takedown() -> int:
	if can_takedown(selected):
		return selected
	for i in range(enemies.size()):
		if can_takedown(i):
			return i
	return -1

func takedown_nearby():
	silent_takedown(nearby_takedown())

func silent_takedown(index: int):
	if not can_takedown(index):
		return
	begin_motion()
	var e = enemies[index]
	e.hp = 0
	e.alerted = false
	e.investigating = false
	e.loot_kind = rng.randi_range(0, 3)
	e.searched = false
	selected = -1
	aiming = false
	ticks += 1
	message = "Silent takedown. One world tick elapsed. Search the body for gear."
	world_tick()
	if not await animate_motion():
		return
	refresh()

func world_tick():
	advance_bleeding()
	if finished:
		return
	var spotted_guards: Array[Dictionary] = []
	for e in enemies:
		if enemy_can_see_player(e):
			spot_player(e)
			spotted_guards.append(e)
	for e in enemies:
		# A guard that sees the operator reacts in place instead of wandering away.
		if e.hp > 0 and not spotted_guards.has(e):
			if e.get("investigating", false):
				investigation_step(e)
			else:
				patrol_step(e)
	for e in enemies:
		if enemy_can_see_player(e):
			spot_player(e)
			if not spotted_guards.has(e):
				spotted_guards.append(e)
	if not spotted_guards.is_empty():
		enter_combat()
		focus_contact(spotted_guards[0])
		message = "Enemy patrol spotted you. Highlighted the guard; choose an attack."

func focus_contact(e: Dictionary):
	selected = enemies.find(e)
	var span = Vector2((Vector2i(e.pos) - player).abs()) * CELL + Vector2.ONE * CELL * 3
	set_map_zoom(minf(map_zoom, minf(MAP_VIEW_SIZE.x / span.x, MAP_VIEW_SIZE.y / span.y)))
	camera = (Vector2(player) + Vector2(e.pos)) * CELL / 2 + Vector2(18, 18) - map_visible_size() / 2
	clamp_camera()
	map_view.queue_redraw()

func choose_shot(mode: int):
	if meter_active:
		return
	if mode < 0 or mode >= SHOT_PROFILES.size() or (mode == 2 and not weapon_profile().burst):
		return
	shot_mode = mode
	refresh()

func shot_chance(target: Vector2i) -> int:
	var weapon = weapon_profile()
	var base = weapon_hit_chance(player, target, weapon)
	return clampi(base + SHOT_PROFILES[shot_mode].accuracy + (AIM_BONUS if aiming else 0), 5, 95)

func aim_weapon():
	if busy() or finished or not combat or ap < 1 or aiming:
		return
	ap -= 1
	aiming = true
	message = "Aiming: +30 accuracy on every attack until you move or take damage."
	refresh()

func can_fire() -> bool:
	return not busy() and not gun_dialog.visible and not finished and (ap if combat else AP_PER_TURN) >= attack_ap() and (shot_mode != 2 or weapon_profile().burst) and ammo >= (2 if shot_mode == 2 else 1) and selected >= 0 and selected < enemies.size() and visible(enemies[selected]) and distance(player, enemies[selected].pos) <= weapon_profile().range

func begin_shot():
	if not can_fire() or inventory_dialog.visible:
		return
	pending_shot = {"target": enemies[selected], "index": selected, "mode": shot_mode, "weapon": weapon_id, "epoch": motion_epoch}
	meter_speed = meter_rng.randf_range(1.3, 2.0)
	meter_center = meter_rng.randf_range(0.24, 0.76)
	meter_width = meter_rng.randf_range(0.10, 0.14)
	meter_position = meter_rng.randf_range(0.0, 0.10)
	meter_direction = 1.0 if meter_rng.randi_range(0, 1) == 0 else -1.0
	if meter_direction < 0:
		meter_position = 1.0 - meter_position
	meter_active = true
	pointer_down = false
	refresh()
	meter_overlay.show()
	meter_overlay.grab_focus()
	meter_overlay.queue_redraw()

func _process(delta: float):
	if not meter_active:
		return
	meter_position += delta * meter_speed * meter_direction
	if meter_position >= 1.0 or meter_position <= 0.0:
		meter_position = clampf(meter_position, 0.0, 1.0)
		resolve_shot_meter(true)
		return
	meter_overlay.queue_redraw()

func meter_input(event: InputEvent):
	if not meter_active:
		return
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER]):
		meter_overlay.accept_event()
		resolve_shot_meter()

func timing_modifier_at(position_value: float) -> int:
	var error = absf(position_value - meter_center)
	if error <= meter_width / 2:
		return TIMING_BONUS
	if error <= meter_width / 2 + 0.10:
		return 0
	return TIMING_PENALTY

func resolve_shot_meter(timed_out: bool = false):
	if not meter_active:
		return
	var request = pending_shot
	var modifier = TIMING_PENALTY if timed_out else timing_modifier_at(meter_position)
	meter_active = false
	pending_shot = {}
	meter_overlay.hide()
	if request.is_empty() or request.epoch != motion_epoch or selected != request.index or shot_mode != request.mode or weapon_id != request.weapon or not can_fire() or enemies[selected] != request.target:
		message = "Shot canceled: target or weapon no longer valid."
		refresh()
		return
	shoot(modifier)
	message = "%s timing (%+d): %d%% hit chance. " % ["TIMEOUT" if timed_out else ("GREEN" if modifier > 0 else ("RED" if modifier < 0 else "YELLOW")), modifier, last_shot_chance] + message
	refresh()

func shoot(timing_modifier: int = 0):
	if not can_fire():
		return
	if not combat:
		enter_combat()
	var enemy = enemies[selected]
	var profile = SHOT_PROFILES[shot_mode]
	var chance = clampi(shot_chance(enemy.pos) + timing_modifier, 5, 95)
	last_shot_modifier = timing_modifier
	last_shot_chance = chance
	var rounds = mini(ammo, rng.randi_range(2, 3)) if shot_mode == 2 else 1
	spot_player(enemy)
	hear_gunshot(player)
	ap -= attack_ap()
	ammo -= rounds
	var hits = 0
	for round_index in range(rounds):
		if rng.randi_range(1, 100) <= chance:
			enemy.hp -= attack_damage()
			hits += 1
	message = "%s: %d/%d hits, %d damage." % [profile.name, hits, rounds, hits * attack_damage()]
	if enemy.hp <= 0:
		enemy.loot_kind = rng.randi_range(0, 3)
		enemy.searched = false
		selected = -1
		message += " Hostile down."
		finish_cleared_engagement()
	refresh()

func take_damage(amount: int):
	if amount > 0 and not finished:
		hp = maxi(0, hp - amount)
		aiming = false
		if hp > 0 and not bleeding and bleed_rng.randi_range(1, 100) <= BLEED_CHANCE:
			bleeding = true
		check_death()

func weapon_profile() -> Dictionary:
	return WEAPONS[weapon_id]

func attack_ap() -> int:
	return 2 if shot_mode == 2 else int(weapon_profile().ap)

func attack_damage() -> int:
	return roundi(weapon_profile().damage * 60.0 / 35.0) if shot_mode == 1 else int(weapon_profile().damage)

func refresh_inventory():
	var lines = ["GUN: %s (%s)" % [weapon_profile().name, weapon_profile().ammo_type], "Loaded: %d/%d" % [ammo, weapon_profile().magazine], "", "CARRIED AMMO"]
	for i in range(WEAPONS.size()):
		lines.append("%s (%s): %d spare" % [WEAPONS[i].ammo_type, WEAPONS[i].name, carried_ammo[i]])
	lines.append("")
	lines.append("Health kits: %d • Bandages: %d" % [health_kits, bandages])
	lines.append("HP: %d/%d • Bleeding: %s" % [hp, MAX_HEALTH, "YES" if bleeding else "no"])
	lines.append("Use costs 1 AP" if combat else "Use costs 1 world tick")
	inventory_dialog.dialog_text = "\n".join(lines)
	inventory_heal_button.disabled = not can_use_health_kit()
	inventory_bandage_button.disabled = not can_bandage()

func show_inventory():
	if busy():
		return
	refresh_inventory()
	inventory_dialog.popup_centered(Vector2i(390, 430))

func inventory_action(action: StringName):
	if action == "heal":
		use_health_kit()
	elif action == "bandage":
		use_bandage()

func can_use_health_kit() -> bool:
	return not busy() and not finished and not gun_dialog.visible and hp < MAX_HEALTH and health_kits > 0 and (not combat or ap >= 1)

func use_health_kit():
	if not can_use_health_kit():
		return
	begin_motion()
	health_kits -= 1
	var healed = mini(CRATE_HEALTH, MAX_HEALTH - hp)
	hp += healed
	message = "Used health kit: +%d HP. Bleeding requires a bandage." % healed
	if combat:
		ap -= 1
	else:
		ticks += 1
		world_tick()
	if not await animate_motion():
		return
	refresh()

func offer_gun(source: Dictionary):
	if finished or not source.get("gun_available", false):
		return
	pending_gun = source
	var gun = WEAPONS[int(source.weapon_id)]
	gun_dialog.dialog_text = "Found %s • %s ammo\n%d/%d loaded • %d damage • %d AP\nSpare %s carried: %d\n\nCurrent: %s (%d/%d loaded)\nSwap guns? Your old gun stays here." % [gun.name, gun.ammo_type, int(source.get("ammo", 0)), gun.magazine, gun.damage, gun.ap, gun.ammo_type, carried_ammo[int(source.weapon_id)], weapon_profile().name, ammo, weapon_profile().magazine]
	gun_dialog.popup_centered(Vector2i(390, 260))

func decline_gun():
	pending_gun = {}
	gun_dialog.hide()
	refresh()

func take_found_gun():
	if finished or pending_gun.is_empty() or not pending_gun.get("gun_available", false) or distance(player, pending_gun.pos) > 1:
		decline_gun()
		return
	var previous_weapon = weapon_id
	var previous_ammo = ammo
	weapon_id = int(pending_gun.weapon_id)
	ammo = clampi(int(pending_gun.get("ammo", 0)), 0, weapon_profile().magazine)
	pending_gun.weapon_id = previous_weapon
	pending_gun.ammo_type = previous_weapon
	pending_gun.ammo = previous_ammo
	shot_mode = 0
	aiming = false
	message = "Equipped %s (%s). Left %s behind. Matching spare ammo: %d." % [weapon_profile().name, weapon_profile().ammo_type, WEAPONS[previous_weapon].name, reserve]
	pending_gun = {}
	gun_dialog.hide()
	refresh()

func check_death():
	if hp <= 0:
		hp = 0
		finished = true
		saved_gear = default_gear()
		save_stash(saved_gear)
		if is_instance_valid(gun_dialog):
			gun_dialog.hide()
		pending_gun = {}
		message = "Operator lost. Raid cargo lost. Your banked supplies are safe. Start a new raid."

func advance_bleeding():
	if finished or not bleeding:
		return
	hp = maxi(0, hp - BLEED_DAMAGE)
	aiming = false
	message += " Bleeding: -%d HP." % BLEED_DAMAGE
	check_death()

func can_bandage() -> bool:
	return not busy() and not gun_dialog.visible and not finished and bleeding and bandages > 0 and (not combat or ap >= 1)

func use_bandage():
	if not can_bandage():
		return
	begin_motion()
	bandages -= 1
	bleeding = false
	message = "Bandaged. Bleeding stopped; no health restored."
	if combat:
		ap -= 1
	else:
		ticks += 1
		world_tick()
	if not await animate_motion():
		return
	refresh()

func can_reload() -> bool:
	return not busy() and not gun_dialog.visible and not finished and reserve > 0 and ammo < weapon_profile().magazine and (not combat or ap >= COMBAT_RELOAD_AP)

func reload_weapon():
	if not can_reload():
		return
	begin_motion()
	var rounds = mini(weapon_profile().magazine - ammo, reserve)
	ammo += rounds
	reserve -= rounds
	if combat:
		ap -= COMBAT_RELOAD_AP
		message = "Reloaded %d rounds for 2 AP." % rounds
	else:
		ticks += 1
		message = "Reloaded %d rounds. One world tick elapsed." % rounds
		world_tick()
	if not await animate_motion():
		return
	refresh()

func enemy_turn():
	if busy() or finished or not combat or gun_dialog.visible:
		return
	begin_motion()
	var damage = 0
	for e in enemies:
		if finished:
			break
		if e.hp <= 0:
			continue
		var enemy_weapon = WEAPONS[int(e.get("weapon_id", 0))]
		if not e.has("ammo"):
			e.ammo = enemy_weapon.magazine
			e.reserve = 24
		var actions = 2
		while actions > 0:
			actions -= 1
			if finished:
				break
			var sees_player = enemy_can_see_player(e)
			if sees_player:
				spot_player(e)
			if sees_player and distance(e.pos, player) <= enemy_weapon.range:
				if int(e.ammo) <= 0:
					if actions >= 1 and int(e.get("reserve", 0)) > 0:
						var loaded = mini(enemy_weapon.magazine, int(e.reserve))
						e.ammo = loaded
						e.reserve -= loaded
						actions -= 1
					continue
				if enemy_weapon.ap > actions + 1:
					continue
				actions -= enemy_weapon.ap - 1
				e.ammo -= 1
				hear_gunshot(e.pos, e)
				var chance = weapon_hit_chance(e.pos, player, enemy_weapon)
				if rng.randi_range(1, 100) <= chance:
					var dealt = roundi(enemy_weapon.damage / 3.0)
					take_damage(dealt)
					damage += dealt
			elif e.get("alerted", false):
				var target = Vector2i(e.get("last_seen", e.pos))
				var next = guard_route_step(e, target)
				e.facing = facing_toward(next - Vector2i(e.pos)) if next != e.pos else facing_toward(target - Vector2i(e.pos))
				e.pos = next
				record_enemy_motion(e)
			elif e.get("investigating", false):
				investigation_step(e)
			else:
				patrol_step(e)

	ap = AP_PER_TURN
	ticks += 1
	message = "Enemy turn: %d damage. Your turn." % damage
	advance_bleeding()
	if hp <= 0:
		check_death()
	elif not enemies.any(func(e): return enemy_can_see_player(e)):
		combat = false
		selected = -1
		for e in enemies:
			if e.hp > 0 and e.get("alerted", false):
				begin_investigation(e, Vector2i(e.get("last_seen", e.pos)))
				e.alerted = false
		message = "Contact broken. Exploration resumes; patrols advance when you move."
	if combat and not finished:
		for e in enemies:
			if enemy_can_see_player(e):
				focus_contact(e)
				break
	if not await animate_motion():
		return
	refresh()

func extract():
	if busy() or gun_dialog.visible:
		return
	if finished or player != exfil:
		return
	if not objective_collected:
		message = "Extraction locked. Collect the purple objective first."
		refresh()
		return
	stash += cargo
	saved_gear = current_gear()
	save_stash(saved_gear)
	finished = true
	message = "Extraction successful. %d supplies banked. %s and ammo saved for your next raid." % [cargo, weapon_profile().name]
	refresh()

func total_ammo() -> int:
	var total = ammo
	for rounds in carried_ammo:
		total += rounds
	return total

func refresh():
	if not animations_enabled:
		player_draw_pos = Vector2(player)
	if not is_instance_valid(status):
		return
	if selected >= 0 and (selected >= enemies.size() or not visible(enemies[selected])):
		selected = -1
	status.text = "HP %d • LOOT %d • BANK %d • OBJ %s" % [hp, cargo, stash, "OK" if objective_collected else "--"]
	ammo_status.text = "GUN %d/%d • AMMO %d %s • TOTAL %d" % [ammo, weapon_profile().magazine, reserve, weapon_profile().ammo_type, total_ammo()]
	reload_button.tooltip_text = "Reload: 2 AP" if combat else "Reload: 1 world tick"
	intel.add_theme_color_override("font_color", Color("ef9585") if bleeding else Color("e0b969"))
	intel.text = ("COMBAT • %d/4 AP" % ap) if combat else "EXPLORATION   •   TICK %d" % ticks
	if bleeding:
		intel.text += " • BLEED -%d" % BLEED_DAMAGE
	if aiming:
		intel.text += " • AIMED"
	if adjacent_cover(player):
		intel.text += "   •   COVER"
	if selected >= 0 and visible(enemies[selected]):
		intel.text += "\n%s %d HP • HIT %d%%%s" % [WEAPONS[int(enemies[selected].get("weapon_id", 0))].name, enemies[selected].hp, shot_chance(enemies[selected].pos), " • OUT OF RANGE" if distance(player, enemies[selected].pos) > weapon_profile().range else (" • COVER" if cover_at(enemies[selected].pos, player) else "")]
	else:
		intel.text += "\nPurple: objective • Green: exfil • Arrows: facing"
	takedown_button.disabled = nearby_takedown() < 0
	takedown_button.tooltip_text = "Silent takedown: directly behind an unaware guard, 1 tick outside combat."
	if not takedown_button.disabled:
		intel.text = intel.text.get_slice("\n", 0) + "\nTAKEDOWN READY • 1 tick • Tap button"
	feed.text = message
	var profile = SHOT_PROFILES[shot_mode]
	shot_info.text = "%s • %d AP • %d dmg%s" % [profile.name, attack_ap(), attack_damage(), "/round" if shot_mode == 2 else ""]
	shot_info.text += "\nRange %d • %s • Aim +30" % [weapon_profile().range, "2–3 ammo" if shot_mode == 2 else "1 ammo"]
	for i in range(shot_buttons.size()):
		shot_buttons[i].set_pressed_no_signal(i == shot_mode)
		shot_buttons[i].tooltip_text = "%d damage, %+d accuracy points, %d AP" % [roundi(weapon_profile().damage * 60.0 / 35.0) if i == 1 else weapon_profile().damage, SHOT_PROFILES[i].accuracy, 2 if i == 2 else weapon_profile().ap]
		shot_buttons[i].disabled = finished or (i == 2 and not weapon_profile().burst)
	gear_button.text = "INVENTORY"
	gear_button.disabled = busy()
	title.text = weapon_profile().name
	gear_button.tooltip_text = "View your gun, ammo, health kits and bandages."
	refresh_inventory()
	bandage_button.text = "BANDAGE (%d)" % bandages
	bandage_button.disabled = not can_bandage()
	bandage_button.tooltip_text = "Stop bleeding: 1 AP, no healing" if combat else "Stop bleeding: 1 world tick, no healing"
	aim_button.disabled = busy() or finished or not combat or ap < 1 or aiming
	fire_button.disabled = not can_fire()
	reload_button.disabled = not can_reload()
	end_button.disabled = busy() or finished or not combat
	end_button.tooltip_text = "End turn: enemies act, then start your next turn with four AP. Unused AP is lost."
	objective_button.text = "EXFIL" if objective_collected else "OBJECTIVE"
	objective_button.disabled = not objective_collected and not objective_visible()
	search_button.disabled = busy() or finished or (combat and ap < 1) or nearby_body() < 0
	search_button.tooltip_text = "Search body: 1 AP" if combat else "Search body: 1 world tick"
	map_view.queue_redraw()
	extract_button.disabled = busy() or finished or player != exfil or not objective_collected
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color("101b1b"))

func draw_map(canvas: Control):
	var first = Vector2i(camera / CELL)
	var last = Vector2i((camera + map_visible_size()) / CELL) + Vector2i.ONE
	for y in range(maxi(0, first.y), mini(MAP.size(), last.y)):
		for x in range(maxi(0, first.x), mini(MAP[0].length(), last.x)):
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
		canvas.draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), Color("a99665") if crate.get("searched", false) else Color("d6ad58"))
	for i in range(enemies.size()):
		var e = enemies[i]
		if e.hp <= 0:
			if player_can_see(e.pos):
				var body_center = map_point(e.pos) + Vector2(17, 17)
				var body_color = Color("778078") if e.get("searched", false) else Color("e0c090")
				canvas.draw_line(body_center - Vector2(8, 5), body_center + Vector2(8, 5), body_color, 4)
				canvas.draw_line(body_center + Vector2(-8, 5), body_center + Vector2(8, -5), body_color, 4)
			continue
		if not visible(e) and not (animation_running and e.get("motion_visible", false)):
			continue
		var center = Vector2(e.get("draw_pos", Vector2(e.pos))) * CELL - camera + Vector2(17, 17)
		canvas.draw_circle(center, 11, Color("d6ad58") if e.get("investigating", false) else Color("c97061"))
		var forward = Vector2(e.get("draw_facing", e.get("facing", Vector2i.LEFT)))
		var side = Vector2(-forward.y, forward.x)
		canvas.draw_colored_polygon(PackedVector2Array([center + forward * 14, center + forward * 4 + side * 5, center + forward * 4 - side * 5]), Color("fff0c0"))
		draw_cover_edges(canvas, e.pos, Color("e6be91"), Vector2(e.get("draw_pos", Vector2(e.pos))))
		if selected == i:
			canvas.draw_arc(center, 15, 0, TAU, 24, Color("f4df9c"), 2)
		canvas.draw_rect(Rect2(center + Vector2(-12, -16), Vector2(24 * maxf(e.hp, 0) / 60.0, 3)), Color("da8d79"))
	canvas.draw_circle(player_draw_pos * CELL - camera + Vector2(17, 17), 11, Color("87c6e3"))
	canvas.draw_circle(player_draw_pos * CELL - camera + Vector2(17, 17), 4, Color("eef4df"))

	draw_cover_edges(canvas, player, Color("a0dcd6"), player_draw_pos)

func draw_cover_edges(canvas: Control, p: Vector2i, color: Color, display: Vector2):
	var center = display * CELL - camera + Vector2(17, 17)
	for direction in DIRS:
		if tile_at(p + direction) == "=" or is_corner_edge(p, direction):
			var normal = Vector2(direction)
			var tangent = Vector2(-normal.y, normal.x)
			canvas.draw_line(center + normal * 15 - tangent * 9, center + normal * 15 + tangent * 9, color, 3)

func district_at(p: Vector2i) -> int:
	return floori(float(p.x) / DISTRICT_SIZE) + floori(float(p.y) / DISTRICT_SIZE) * 2

func build_map():
	BUILDINGS.clear()
	DOORS.clear()
	for offset in DISTRICT_OFFSETS:
		for i in range(BASE_BUILDINGS.size()):
			BUILDINGS.append(Rect2i(BASE_BUILDINGS[i].position + offset, BASE_BUILDINGS[i].size))
			DOORS.append(BASE_DOORS[i] + offset)
	var rows: Array[String] = []
	for y in range(MAP_SIZE):
		var row = ""
		for x in range(MAP_SIZE):
			row += "#" if x == 0 or y == 0 or x == MAP_SIZE - 1 or y == MAP_SIZE - 1 else "."
		rows.append(row)
	MAP = rows
	for offset in DISTRICT_OFFSETS:
		for block in [Rect2i(3, 2, 2, 2), Rect2i(7, 3, 2, 2), Rect2i(3, 6, 2, 2), Rect2i(7, 7, 2, 2)]:
			for y in range(block.position.y, block.end.y):
				for x in range(block.position.x, block.end.x):
					set_tile(Vector2i(x, y) + offset, "#")
	for i in range(BUILDINGS.size()):
		var room = BUILDINGS[i]
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				if x == room.position.x or x == room.end.x - 1 or y == room.position.y or y == room.end.y - 1:
					set_tile(Vector2i(x, y), "#")
		set_tile(DOORS[i], ".")
	for offset in DISTRICT_OFFSETS:
		for local_tile in [Vector2i(3, 9), Vector2i(4, 9), Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 10), Vector2i(11, 10), Vector2i(4, 12), Vector2i(5, 12), Vector2i(5, 16), Vector2i(6, 17), Vector2i(17, 5), Vector2i(17, 6), Vector2i(17, 17), Vector2i(18, 17)]:
			var p = local_tile + offset
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

func map_visible_size() -> Vector2:
	return MAP_VIEW_SIZE / map_zoom

func zoom_map(direction: int):
	set_map_zoom(map_zoom + direction * ZOOM_STEP)

func set_map_zoom(value: float, anchor: Vector2 = Vector2(-1, -1)):
	if anchor.x < 0:
		anchor = MAP_VIEW_SIZE / 2
	var world_anchor = camera + anchor / map_zoom
	map_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	map_view.scale = Vector2.ONE * map_zoom
	map_view.size = map_visible_size()
	camera = world_anchor - anchor / map_zoom
	clamp_camera()
	zoom_label.text = "%d%%" % roundi(map_zoom * 100)
	zoom_in_button.disabled = map_zoom >= MAX_ZOOM
	zoom_out_button.disabled = map_zoom <= MIN_ZOOM
	map_view.queue_redraw()

func clamp_camera():
	camera.x = clampf(camera.x, 0, maxf(0, MAP[0].length() * CELL - map_visible_size().x))
	camera.y = clampf(camera.y, 0, maxf(0, MAP.size() * CELL - map_visible_size().y))

func center_player():
	camera = Vector2(player) * CELL + Vector2(18, 18) - map_visible_size() / 2
	clamp_camera()
	if is_instance_valid(map_view):
		map_view.queue_redraw()

func center_objective():
	if not objective_collected and not objective_visible():
		return
	camera = Vector2(exfil if objective_collected else objective) * CELL + Vector2(18, 18) - map_visible_size() / 2
	clamp_camera()
	map_view.queue_redraw()

func map_point(p: Vector2i) -> Vector2:
	return Vector2(p) * CELL - camera

func apply_loot(kind: int, source: String, ammo_type: int = 0, ammo_amount: int = -1):
	cargo += 1
	var rounds = ammo_amount if ammo_amount >= 0 else (CRATE_AMMO if kind == 0 else 0)
	carried_ammo[ammo_type] += rounds
	if kind == 1:
		health_kits += 1
	if kind == 3:
		bandages += 1
	var contents: Array[String] = []
	if rounds > 0:
		contents.append("+%d %s ammo" % [rounds, WEAPONS[ammo_type].ammo_type])
	if kind == 1:
		contents.append("+1 health kit")
	if kind == 3:
		contents.append("+1 bandage")
	if kind == 2:
		contents.append("gun discovered")
	message = "%s: %s. +1 supply." % [source, ", ".join(contents)]

func nearby_body() -> int:
	# Prefer fresh bodies over already-searched bodies holding a swapped gun.
	for searched in [false, true]:
		for i in range(enemies.size()):
			var body = enemies[i]
			if body.hp <= 0 and body.get("searched", false) == searched and (not searched or body.get("gun_available", false)) and distance(player, body.pos) <= 1:
				return i
	return -1

func search_nearby_body():
	search_body(nearby_body())

func search_body(index: int):
	if busy() or gun_dialog.visible:
		return
	if finished or index < 0 or index >= enemies.size() or (combat and ap < 1):
		return
	var body = enemies[index]
	if body.hp > 0 or distance(player, body.pos) > 1:
		return
	if body.get("searched", false):
		offer_gun(body)
		return
	begin_motion()
	body.searched = true
	apply_loot(int(body.get("loot_kind", 0)), "Body", int(body.get("weapon_id", 0)), int(body.get("reserve", CRATE_AMMO)))
	body.reserve = 0
	ticks += 1
	if combat:
		ap -= 1
	else:
		world_tick()
	if not await animate_motion():
		return
	if not finished and body.get("gun_available", false):
		offer_gun(body)
	refresh()

func is_outskirts(p: Vector2i) -> bool:
	return walkable(p) and mini(mini(p.x, p.y), mini(MAP[0].length() - 1 - p.x, MAP.size() - 1 - p.y)) <= EDGE_BAND

func is_corner_edge(p: Vector2i, direction: Vector2i) -> bool:
	if not walkable(p) or tile_at(p + direction) != "#":
		return false
	var tangent = Vector2i(-direction.y, direction.x)
	for side in [tangent, -tangent]:
		if walkable(p + side) and walkable(p + direction + side):
			return true
	return false

func adjacent_cover(p: Vector2i) -> bool:
	if adjacent_low_cover(p):
		return true
	for direction in DIRS:
		if is_corner_edge(p, direction):
			return true
	return false

func corner_cover_at(p: Vector2i, attacker: Vector2i) -> bool:
	if not walkable(attacker) or not line_of_sight(p, attacker):
		return false
	var delta = attacker - p
	for direction in DIRS:
		if not is_corner_edge(p, direction) or delta.x * direction.x + delta.y * direction.y <= 0:
			continue
		var tangent = Vector2i(-direction.y, direction.x)
		for side in [tangent, -tangent]:
			if walkable(p + side) and walkable(p + direction + side) and delta.x * side.x + delta.y * side.y >= 0:
				for target in peek_positions(attacker):
					if clear_ray(p + side, target):
						return true
	return false

func enter_combat():
	if not combat:
		ap = AP_PER_TURN
	combat = true

func finish_cleared_engagement():
	if not combat or finished:
		return
	for e in enemies:
		if e.hp > 0 and (e.get("alerted", false) or enemy_can_see_player(e)):
			return
	combat = false
	selected = -1
	for e in enemies:
		e.alerted = false
	message += " Engagement cleared. Exploration resumes."
