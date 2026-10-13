extends Control

const MAP_SIZE = 24
const EDGE_BAND = 2
const BUILDINGS = [Rect2i(3, 14, 6, 6), Rect2i(14, 3, 7, 6), Rect2i(14, 14, 7, 7)]
const DOORS = [Vector2i(6, 19), Vector2i(14, 6), Vector2i(17, 14)]
var MAP: Array[String] = []
const AP_PER_TURN = 4
const AIM_BONUS = 30
const MAP_VIEW_SIZE = Vector2(432, 360)
const SHOT_PROFILES = [
	{"name": "BODY", "accuracy": 0},
	{"name": "HEAD", "accuracy": -20},
	{"name": "BURST", "accuracy": -15}
]
const WEAPONS = [
	{"name": "PISTOL", "ammo_type": "9mm", "magazine": 7, "damage": 35, "accuracy": 95, "falloff": 8, "range": 6, "ap": 1, "burst": true},
	{"name": "RIFLE", "ammo_type": "5.56", "magazine": 20, "damage": 40, "accuracy": 95, "falloff": 6, "range": 6, "ap": 1, "burst": true},
	{"name": "SHOTGUN", "ammo_type": "12GA", "magazine": 6, "damage": 55, "accuracy": 105, "falloff": 15, "range": 4, "ap": 2, "burst": false},
	{"name": "SNIPER", "ammo_type": "7.62", "magazine": 5, "damage": 65, "accuracy": 95, "falloff": 3, "range": 6, "ap": 2, "burst": false},
	{"name": "SMG", "ammo_type": ".45", "magazine": 25, "damage": 24, "accuracy": 100, "falloff": 10, "range": 6, "ap": 1, "burst": true}
]
const BLEED_CHANCE = 15
const BLEED_DAMAGE = 3
const MAX_HEALTH = 100
const CRATE_HEALTH = 25
const COVER_PENALTY = 25
const RAID_LOOT_COUNT = 4
const OBJECTIVE_MIN_DISTANCE = 8
const RAID_ENEMY_COUNT = 6
const CRATE_AMMO = 7
const COMBAT_RELOAD_AP = 2
const CELL = 36.0
const ORIGIN = Vector2(24, 164)
const DIRS = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
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
var pointer_down = false
var pointer_start = Vector2.ZERO
var pointer_last = Vector2.ZERO
var pointer_dragged = false

func _ready():
	build_map()
	rng.randomize()
	bleed_rng.randomize()
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
	title = make_label(Vector2(170, 20), Vector2(140, 32), 16, Color("e7efcf"))
	title.text = "TD / EXTRACT"
	gear_button = make_button("PISTOL", Vector2(24, 20), show_inventory)
	gear_button.size = Vector2(136, 36)
	gear_button.add_theme_font_size_override("font_size", 14)
	inventory_dialog = AcceptDialog.new()
	inventory_dialog.title = "Carried ammo"
	inventory_dialog.ok_button_text = "CLOSE"
	inventory_dialog.exclusive = true
	add_child(inventory_dialog)
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
		var pos = floor_tiles.pop_back()
		while distance(pos, player) < 5:
			floor_tiles.push_front(pos)
			pos = floor_tiles.pop_back()
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
		var pool = indoor if i < RAID_LOOT_COUNT - 1 else outdoor
		var gun = rng.randi_range(1, WEAPONS.size() - 1) if rng.randf() < 0.4 else -1
		loot.append({"pos": pool.pop_back(), "kind": rng.randi_range(0, 4), "ammo_type": rng.randi_range(0, WEAPONS.size() - 1), "weapon_id": gun, "ammo": rng.randi_range(0, WEAPONS[gun].magazine) if gun >= 0 else 0, "gun_available": gun >= 0, "searched": false})
	# Every raid has a hidden source of bandages, with randomized placement.
	loot[rng.randi_range(0, loot.size() - 1)].kind = rng.randi_range(3, 4)
	hp = MAX_HEALTH
	bleeding = false
	bandages = 1
	ap = AP_PER_TURN
	shot_mode = 0
	aiming = false
	cargo = 0
	ticks = 0
	combat = false
	finished = false
	selected = -1
	message = "Find guns and typed ammo in crates and bodies. Extract to keep your gear. Tap your weapon to view carried ammo."
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
	return distance(player, p) <= 6 and sight_with_peeking(player, p, false)

func objective_visible() -> bool:
	return not objective_collected and player_can_see(objective)

func visible(e: Dictionary) -> bool:
	return e.hp > 0 and distance(player, e.pos) <= 6 and line_of_sight(player, e.pos)

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
	return clampi(95 - distance(from, to) * 8 - (COVER_PENALTY if cover_at(to, from) else 0), 15, 95)

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
	if finished or gun_dialog.visible:
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
			enter_combat()
			message = "Target acquired. Fire to engage, or reposition behind cover."
			refresh()
			return
	move_to(target)

func move_to(target: Vector2i):
	if finished or gun_dialog.visible:
		return
	var path = path_to(target)
	if path.is_empty():
		message = "Choose a reachable, unoccupied tile."
	for step in path:
		if finished:
			break
		if combat and ap <= 0:
			message = "No action points. End your turn."
			break
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
					apply_loot(crate.kind, "Crate", int(crate.get("ammo_type", 0)))
				break
		if not combat:
			world_tick()
		if not found_crate.is_empty():
			if not finished and found_crate.get("gun_available", false):
				offer_gun(found_crate)
			elif not found_crate.get("gun_available", false):
				loot.erase(found_crate)
		if (not was_combat and combat) or gun_dialog.visible or finished:
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
	camera = (Vector2(player) + Vector2(e.pos)) * CELL / 2 + Vector2(18, 18) - MAP_VIEW_SIZE / 2
	clamp_camera()
	map_view.queue_redraw()

func choose_shot(mode: int):
	if mode < 0 or mode >= SHOT_PROFILES.size() or (mode == 2 and not weapon_profile().burst):
		return
	shot_mode = mode
	refresh()

func shot_chance(target: Vector2i) -> int:
	var weapon = weapon_profile()
	var base = clampi(weapon.accuracy - distance(player, target) * weapon.falloff - (COVER_PENALTY if cover_at(target, player) else 0), 15, 95)
	return clampi(base + SHOT_PROFILES[shot_mode].accuracy + (AIM_BONUS if aiming else 0), 5, 95)

func aim_weapon():
	if finished or not combat or ap < 1 or aiming:
		return
	ap -= 1
	aiming = true
	message = "Aiming: +30 accuracy on every attack until you move or take damage."
	refresh()

func can_fire() -> bool:
	return not gun_dialog.visible and not finished and combat and ap >= attack_ap() and (shot_mode != 2 or weapon_profile().burst) and ammo >= (2 if shot_mode == 2 else 1) and selected >= 0 and selected < enemies.size() and visible(enemies[selected]) and distance(player, enemies[selected].pos) <= weapon_profile().range

func shoot():
	if not can_fire():
		return
	var enemy = enemies[selected]
	var profile = SHOT_PROFILES[shot_mode]
	var chance = shot_chance(enemy.pos)
	var rounds = mini(ammo, rng.randi_range(2, 3)) if shot_mode == 2 else 1
	spot_player(enemy)
	ap -= attack_ap()
	ammo -= rounds
	var hits = 0
	for round_index in range(rounds):
		if rng.randi_range(1, 100) <= chance:
			enemy.hp -= attack_damage()
			hits += 1
	message = "%s: %d/%d hits, %d damage." % [profile.name, hits, rounds, hits * attack_damage()]
	if enemy.hp <= 0:
		enemy.loot_kind = rng.randi_range(0, 4)
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

func show_inventory():
	var lines = ["%s: %d/%d loaded" % [weapon_profile().name, ammo, weapon_profile().magazine]]
	for i in range(WEAPONS.size()):
		lines.append("%s (%s): %d spare" % [WEAPONS[i].ammo_type, WEAPONS[i].name, carried_ammo[i]])
	inventory_dialog.dialog_text = "\n".join(lines)
	inventory_dialog.popup_centered(Vector2i(360, 270))

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
	return not gun_dialog.visible and not finished and bleeding and bandages > 0 and (not combat or ap >= 1)

func use_bandage():
	if not can_bandage():
		return
	bandages -= 1
	bleeding = false
	message = "Bandaged. Bleeding stopped; no health restored."
	if combat:
		ap -= 1
	else:
		ticks += 1
		world_tick()
	refresh()

func can_reload() -> bool:
	return not gun_dialog.visible and not finished and reserve > 0 and ammo < weapon_profile().magazine and (not combat or ap >= COMBAT_RELOAD_AP)

func reload_weapon():
	if not can_reload():
		return
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
	refresh()

func enemy_turn():
	if finished or not combat or gun_dialog.visible:
		return
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
				var chance = clampi(enemy_weapon.accuracy - distance(e.pos, player) * enemy_weapon.falloff - (COVER_PENALTY if cover_at(player, e.pos) else 0), 15, 95)
				if rng.randi_range(1, 100) <= chance:
					var dealt = roundi(enemy_weapon.damage / 3.0)
					take_damage(dealt)
					damage += dealt
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
			e.alerted = false
		message = "Contact broken. Exploration resumes; patrols advance when you move."
	if combat and not finished:
		for e in enemies:
			if enemy_can_see_player(e):
				focus_contact(e)
				break
	refresh()

func extract():
	if gun_dialog.visible:
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
	feed.text = message
	var profile = SHOT_PROFILES[shot_mode]
	shot_info.text = "%s • %d AP • %d dmg%s" % [profile.name, attack_ap(), attack_damage(), "/round" if shot_mode == 2 else ""]
	shot_info.text += "\nRange %d • %s • Aim +30" % [weapon_profile().range, "2–3 ammo" if shot_mode == 2 else "1 ammo"]
	for i in range(shot_buttons.size()):
		shot_buttons[i].set_pressed_no_signal(i == shot_mode)
		shot_buttons[i].tooltip_text = "%d damage, %+d accuracy points, %d AP" % [roundi(weapon_profile().damage * 60.0 / 35.0) if i == 1 else weapon_profile().damage, SHOT_PROFILES[i].accuracy, 2 if i == 2 else weapon_profile().ap]
		shot_buttons[i].disabled = finished or (i == 2 and not weapon_profile().burst)
	gear_button.text = "%s • %s" % [weapon_profile().name, weapon_profile().ammo_type]
	gear_button.tooltip_text = "View all carried ammo types. Guns are found in crates and bodies."
	bandage_button.text = "BANDAGE (%d)" % bandages
	bandage_button.disabled = not can_bandage()
	bandage_button.tooltip_text = "Stop bleeding: 1 AP, no healing" if combat else "Stop bleeding: 1 world tick, no healing"
	aim_button.disabled = finished or not combat or ap < 1 or aiming
	fire_button.disabled = not can_fire()
	reload_button.disabled = not can_reload()
	end_button.disabled = finished or not combat
	end_button.tooltip_text = "End turn: enemies act, then start your next turn with four AP. Unused AP is lost."
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
		if tile_at(p + direction) == "=" or is_corner_edge(p, direction):
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

func apply_loot(kind: int, source: String, ammo_type: int = 0, ammo_amount: int = -1):
	cargo += 1
	var rounds = ammo_amount if ammo_amount >= 0 else (CRATE_AMMO if kind in [0, 2, 4] else 0)
	var healed = mini(CRATE_HEALTH, MAX_HEALTH - hp) if kind in [1, 2, 4] else 0
	carried_ammo[ammo_type] += rounds
	hp += healed
	var dressings = 1 if kind in [3, 4] else 0
	bandages += dressings
	message = "%s: +%d %s, +%d HP, +%d bandage, +1 supply." % [source, rounds, WEAPONS[ammo_type].ammo_type, healed, dressings]

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
	if gun_dialog.visible:
		return
	if finished or index < 0 or index >= enemies.size() or (combat and ap < 1):
		return
	var body = enemies[index]
	if body.hp > 0 or distance(player, body.pos) > 1:
		return
	if body.get("searched", false):
		offer_gun(body)
		return
	body.searched = true
	apply_loot(int(body.get("loot_kind", 0)), "Body", int(body.get("weapon_id", 0)), int(body.get("reserve", CRATE_AMMO)))
	body.reserve = 0
	ticks += 1
	if combat:
		ap -= 1
	else:
		world_tick()
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
