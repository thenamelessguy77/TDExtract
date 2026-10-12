extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.rng.seed = 77
	game.new_raid()
	assert(game.distance(game.player, game.exfil) >= 8)
	assert(game.enemies.size() == 6 and game.loot.size() == 4)
	var cells = [game.player, game.exfil, game.objective]
	for e in game.enemies:
		assert(game.walkable(e.pos) and not cells.has(e.pos))
		cells.append(e.pos)
	for crate in game.loot:
		assert(game.walkable(crate.pos) and not cells.has(crate.pos))
		cells.append(crate.pos)
	var before = game.ticks
	await process_frame
	await process_frame
	assert(game.ticks == before, "Idle world must not advance")
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.loot.clear()
	game.loot.append({"pos": Vector2i(2, 1), "kind": 2})
	game.move_to(Vector2i(5, 1))
	assert(game.ticks == before + 4)
	assert(game.cargo == 1)
	assert(game.player == Vector2i(5, 1))
	game.enemies.append({"pos": Vector2i(7, 1), "hp": 60})
	game.combat = false
	game.player = Vector2i(1, 1)
	game.move_to(Vector2i(5, 1))
	assert(game.combat and game.player == Vector2i(2, 1), "Contact must interrupt travel")
	game.ap = 2
	game.move_to(Vector2i(4, 1))
	assert(game.ap == 0)
	game.move_to(Vector2i(5, 1))
	assert(game.player == Vector2i(4, 1))
	game.enemy_turn()
	assert(game.ap == 4)
	game.ap = 2
	assert(game.hit_chance(Vector2i(2, 1), Vector2i(4, 1)) > game.hit_chance(Vector2i(1, 1), Vector2i(7, 1)))
	assert(not game.line_of_sight(Vector2i(2, 3), Vector2i(5, 3)))
	assert(not game.cover_at(Vector2i(2, 3), Vector2i(5, 3)), "Full walls block shots rather than apply low cover")
	game.selected = 0
	game.enemies[0].pos = Vector2i(5, 1)
	game.shoot()
	assert(game.ap == 1 and game.ammo == 6)
	game.reload_weapon()
	assert(game.ap == 1 and game.ammo == 6, "Combat reload must require two available AP")
	game.ap = 2
	game.reload_weapon()
	assert(game.ap == 0 and game.ammo == 7 and game.reserve == 30)
	game.player = game.exfil
	game.objective_collected = true
	var bank = game.stash
	game.extract()
	assert(game.finished and game.stash == bank + 1)
	# Restore bank so running smoke checks never awards persistent supplies.
	var file = FileAccess.open("user://stash.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"supplies": bank}))
	file.close()
	game.stash = bank
	game.new_raid()
	game.combat = true
	game.hp = 1
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 60})
	game.rng.seed = 1
	game.enemy_turn()
	assert(game.finished and game.hp == 0 and game.stash == bank)
	for seed_value in range(100):
		game.rng.seed = seed_value
		game.new_raid()
		assert(game.distance(game.player, game.exfil) >= 8)
		game.enemies.clear()
		assert(not game.path_to(game.exfil).is_empty(), "Extraction must be connected to insertion")
	assert(test_full_wall_corners(game), "Corner-cover checks must complete")
	assert(test_combat_options(game), "Expanded combat tests must complete")
	assert(test_objective_visibility(game), "Objective visibility checks must complete")
	assert(test_map_and_bodies(game), "Expanded map checks must complete")
	assert(test_objective_facing_loot(game), "New raid mechanics must complete")
	assert(test_health_and_cover(game), "Health and cover checks must all complete")
	assert(test_ammo(game), "Ammo checks must all complete")
	print("PASS: randomized placements, idle freeze, movement ticks, loot, contact interruption, AP, enemy turn, LOS, cover, range, shooting, reloading, extraction, death, 100 raid seeds")
	game.queue_free()
	quit(0)

func test_ammo(game) -> bool:
	game.new_raid()
	assert(game.ammo == 7 and game.reserve == 24)
	assert(game.ammo_status.text == "GUN 7/7  •  RESERVE 24  •  TOTAL 31")
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.exfil = Vector2i(10, 10)
	game.ammo = 2
	game.reserve = 3
	game.refresh()
	assert(not game.reload_button.disabled, "Exploration reload must be enabled")
	game.enemies.append({"pos": Vector2i(5, 5), "hp": 60})
	game.reload_weapon()
	assert(game.ammo == 5 and game.reserve == 0, "Partial reload must use only available rounds")
	assert(game.ticks == 1 and game.ap == 4)
	assert(game.distance(game.enemies[0].pos, Vector2i(5, 5)) == 1, "Reload must advance the enemy patrol once")
	assert(game.reload_button.disabled)
	game.reload_weapon()
	assert(game.ticks == 1, "No reserve ammo must not spend a tick")
	game.reserve = 10
	game.reload_weapon()
	assert(game.ammo == 7 and game.reserve == 8 and game.ticks == 2)
	game.reload_weapon()
	assert(game.ticks == 2 and game.reserve == 8, "Full magazine must not reload")
	game.enemies.clear()
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 60})
	game.combat = false
	game.ammo = 0
	game.reload_weapon()
	assert(game.combat and game.ap == 4 and game.ticks == 3, "Contact during exploration reload must not charge combat AP")
	game.ammo = 0
	game.ap = 1
	game.refresh()
	assert(game.reload_button.disabled)
	game.reload_weapon()
	assert(game.ammo == 0 and game.ap == 1 and game.ticks == 3)
	game.ap = 2
	game.reload_weapon()
	assert(game.ammo == 1 and game.reserve == 0 and game.ap == 0 and game.ticks == 3)
	game.enemies.clear()
	game.combat = false
	game.loot.clear()
	game.loot.append({"pos": Vector2i(2, 1), "kind": 2})
	game.move_to(Vector2i(2, 1))
	assert(game.reserve == 7 and game.ammo == 1, "Crates add reserve ammo without loading the gun")
	game.move_to(Vector2i(1, 1))
	game.move_to(Vector2i(2, 1))
	assert(game.reserve == 7, "A collected crate must not grant ammo again")
	game.combat = true
	game.ap = 2
	game.enemies.append({"pos": Vector2i(3, 1), "hp": 60})
	game.selected = 0
	game.shoot()
	assert(game.ammo == 0 and game.reserve == 7 and game.ap == 1)
	assert(game.ammo_status.text == "GUN 0/7  •  RESERVE 7  •  TOTAL 7")
	game.shoot()
	assert(game.ap == 1, "An empty gun cannot fire reserve rounds")
	game.finished = true
	game.ap = 2
	game.reload_weapon()
	assert(game.ammo == 0 and game.reserve == 7 and game.ap == 2)
	print("PASS: ammo HUD, seven-round capacity, partial/full/empty reloads, patrol tick, detection during reload, two-AP combat reload, crate ammo, single pickup, empty gun, finished raid")
	return true

func test_health_and_cover(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	game.hp = 50
	game.loot.append({"pos": Vector2i(2, 1), "kind": 2})
	game.move_to(Vector2i(2, 1))
	assert(game.hp == 75 and game.ticks == 1, "Crates heal without an extra action")
	game.move_to(Vector2i(1, 1))
	game.move_to(Vector2i(2, 1))
	assert(game.hp == 75, "A looted crate cannot heal twice")
	game.hp = 90
	game.loot.append({"pos": Vector2i(3, 1), "kind": 2})
	game.move_to(Vector2i(3, 1))
	assert(game.hp == 100, "Healing must cap at maximum health")
	game.loot.append({"pos": Vector2i(4, 1), "kind": 2})
	game.move_to(Vector2i(4, 1))
	assert(game.hp == 100 and game.cargo == 3, "Full health still allows looting")
	game.hp = 70
	game.combat = true
	game.ap = 2
	game.loot.append({"pos": Vector2i(5, 1), "kind": 2})
	game.move_to(Vector2i(5, 1))
	assert(game.hp == 95 and game.ap == 1, "Combat crate healing only costs the movement AP")
	var north = Vector2i(3, 8)
	var south = Vector2i(3, 10)
	assert(not game.walkable(Vector2i(3, 9)) and not game.blocks_sight(Vector2i(3, 9)))
	assert(game.line_of_sight(north, south) and game.line_of_sight(south, north), "Low cover must allow reciprocal sight and fire")
	assert(game.adjacent_low_cover(north) and game.adjacent_low_cover(south))
	assert(game.cover_at(north, south) and game.cover_at(south, north), "Both sides of a barrier receive cover")
	assert(not game.cover_at(north, Vector2i(3, 6)), "Rear attacks flank cover")
	assert(not game.cover_at(north, Vector2i(1, 8)), "Side attacks flank cover")
	assert(not game.cover_at(Vector2i(2, 8), south), "A distant barrier does not protect the target")
	assert(game.hit_chance(north, south) == 54 and game.hit_chance(south, north) == 54)
	assert(game.hit_chance(south, Vector2i(2, 8)) == 71, "Firing over your own cover has no accuracy penalty")
	assert(game.hit_chance(Vector2i(2, 8), south) == 46, "Only the defender's cover reduces incoming aim")
	game.player = north
	var route = game.path_to(south)
	assert(not route.is_empty() and route.size() > 2, "Movement must route around waist-high barriers")
	for step in route:
		assert(game.walkable(step))
	game.player = south
	game.enemies.append({"pos": north, "hp": 60})
	assert(game.visible(game.enemies[0]), "Patrol detection sees over low cover")
	game.selected = 0
	game.ap = 2
	game.ammo = 7
	game.refresh()
	assert("COVER" in game.intel.text and "54%" in game.intel.text)
	game.shoot()
	assert(game.ammo == 6 and game.ap == 1, "Player can fire across low cover")
	# An enemy firing over its own cover at an uncovered flank keeps 71% aim.
	game.player = Vector2i(2, 8)
	game.enemies[0].pos = south
	game.enemies[0].facing = Vector2i.UP
	game.hp = 100
	var rolls = RandomNumberGenerator.new()
	var firing_seed = -1
	for candidate in range(1000):
		rolls.seed = candidate
		var first = rolls.randi_range(1, 100)
		var second = rolls.randi_range(1, 100)
		if first > 46 and first <= 71 and second > 46 and second <= 71:
			firing_seed = candidate
			break
	assert(firing_seed >= 0)
	game.rng.seed = firing_seed
	game.enemy_turn()
	assert(game.hp == 76, "Enemy can fire twice over its own cover without an aim penalty")
	assert(not game.walkable(Vector2i(3, 3)) and game.blocks_sight(Vector2i(3, 3)))
	assert(not game.line_of_sight(Vector2i(2, 3), Vector2i(5, 3)), "Full walls still block visibility")
	print("PASS: crate healing and health cap, no extra heal action, low-cover movement/LOS, automatic directional cover, flanking, reciprocal shots, own-cover accuracy, cover HUD")
	return true

func test_objective_facing_loot(game) -> bool:
	var objective_locations = {}
	var loot_kinds = {}
	for seed_value in range(100):
		game.rng.seed = seed_value
		game.new_raid()
		assert(game.distance(game.player, game.objective) >= 8)
		assert(game.is_outskirts(game.player) and not game.is_indoors(game.player))
		assert(game.is_outskirts(game.exfil) and not game.is_indoors(game.exfil))
		assert(game.enemies.size() == 6)
		assert(game.objective != game.exfil and game.walkable(game.objective) and game.is_indoors(game.objective))
		assert(game.loot.size() == 4 and not game.objective_collected)
		objective_locations[game.objective] = true
		for e in game.enemies:
			assert(game.DIRS.has(e.facing) and e.pos != game.objective)
		for crate in game.loot:
			assert(crate.pos != game.objective and crate.kind >= 0 and crate.kind <= 2)
			loot_kinds[crate.kind] = true
		game.enemies.clear()
		assert(not game.path_to(game.objective).is_empty())
	assert(objective_locations.size() > 1 and loot_kinds.size() == 3)
	game.player = game.exfil
	var bank = game.stash
	game.extract()
	assert(not game.finished and game.stash == bank and game.extract_button.disabled)
	game.player = Vector2i(1, 1)
	game.objective = Vector2i(2, 1)
	game.move_to(game.objective)
	assert(game.objective_collected)
	for kind in range(3):
		game.loot.clear()
		game.loot.append({"pos": Vector2i(3, 1), "kind": kind})
		game.player = Vector2i(2, 1)
		game.hp = 50
		game.reserve = 0
		game.move_to(Vector2i(3, 1))
		assert(game.reserve == (0 if kind == 1 else 7))
		assert(game.hp == (50 if kind == 0 else 75))
	game.player = Vector2i(2, 1)
	var guard = {"pos": Vector2i(4, 1), "hp": 60, "facing": Vector2i.RIGHT}
	assert(game.visible(guard) and not game.enemy_can_see_player(guard), "Player can see a guard facing away without being detected")
	guard.facing = Vector2i.LEFT
	assert(game.enemy_can_see_player(guard))
	guard.facing = Vector2i.UP
	assert(not game.enemy_can_see_player(guard), "Side and rear are outside the forward cone")
	game.enemies.clear()
	game.enemies.append(guard)
	var previous = guard.pos
	game.patrol_step(guard)
	assert(guard.pos != previous and guard.facing == guard.pos - previous)
	game.enemies.clear()
	game.player = Vector2i(3, 10)
	guard = {"pos": Vector2i(3, 8), "hp": 60, "facing": Vector2i.DOWN}
	assert(game.enemy_can_see_player(guard), "Forward sight passes over low cover")
	game.player = Vector2i(5, 3)
	guard = {"pos": Vector2i(2, 3), "hp": 60, "facing": Vector2i.RIGHT}
	assert(not game.enemy_can_see_player(guard), "Full walls still block facing-based detection")
	print("PASS: distant randomized objective, locked extraction, objective pickup, four varied crates, directional sight, player visibility, patrol facing, low/full cover detection")
	return true

func test_map_and_bodies(game) -> bool:
	game.new_raid()
	assert(game.MAP.size() == 24 and game.MAP[0].length() == 24)
	for y in range(24):
		for x in range(24):
			var p = Vector2i(x, y)
			if game.tile_at(p) == "=":
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						assert(not game.blocks_sight(p + Vector2i(dx, dy)))
	game.enemies.clear()
	for i in range(game.BUILDINGS.size()):
		var room = game.BUILDINGS[i]
		var openings = 0
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				if x == room.position.x or x == room.end.x - 1 or y == room.position.y or y == room.end.y - 1:
					if game.walkable(Vector2i(x, y)):
						openings += 1
		assert(openings == 1 and game.walkable(game.DOORS[i]))
		game.player = Vector2i(1, 1)
		assert(not game.path_to(room.position + Vector2i(1, 1)).is_empty(), "Every building interior must be accessible through its entrance")
	for seed_value in range(20):
		game.rng.seed = seed_value
		game.new_raid()
		var indoor_count = 0
		for crate in game.loot:
			indoor_count += int(game.is_indoors(crate.pos))
		assert(indoor_count == 3)
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 0, "loot_kind": 2, "searched": false})
	game.hp = 50
	game.reserve = 0
	game.ticks = 0
	game.cargo = 0
	game.combat = false
	game.search_body(0)
	assert(game.enemies[0].searched and game.hp == 75 and game.reserve == 7 and game.cargo == 1 and game.ticks == 1)
	game.search_body(0)
	assert(game.ticks == 1 and game.cargo == 1, "Bodies can only be searched once")
	game.enemies[0].searched = false
	game.player = Vector2i(5, 1)
	game.search_body(0)
	assert(not game.enemies[0].searched and game.ticks == 1, "Must be on or adjacent to a body")
	game.player = Vector2i(1, 1)
	game.enemies[0].hp = 60
	game.search_body(0)
	assert(game.ticks == 1, "Living enemies cannot be searched")
	game.enemies[0].hp = 0
	game.combat = true
	game.ap = 0
	game.search_body(0)
	assert(game.ticks == 1 and not game.enemies[0].searched)
	game.ap = 2
	game.search_body(0)
	assert(game.ticks == 2 and game.ap == 1 and game.enemies[0].searched)
	game.enemies[0].searched = false
	game.combat = false
	game.enemies.append({"pos": Vector2i(5, 5), "hp": 60, "facing": Vector2i.DOWN})
	var previous = game.enemies[1].pos
	game.search_body(0)
	assert(game.distance(previous, game.enemies[1].pos) == 1, "A body search advances patrols once")
	game.camera = Vector2(-999, 9999)
	game.clamp_camera()
	assert(game.camera == Vector2(0, 504))
	game.player = Vector2i(20, 20)
	game.center_player()
	assert(Rect2(game.camera, game.MAP_VIEW_SIZE).has_point(Vector2(game.player) * game.CELL))
	print("PASS: 24x24 map, cover gaps including diagonals, single building entrances, accessible interiors, indoor loot bias, body search timing/AP/rewards/patrols, no duplicate or remote search, camera bounds")
	return true

func test_objective_visibility(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.player = Vector2i(13, 5)
	game.objective = Vector2i(15, 5)
	game.refresh()
	assert(not game.objective_visible(), "Building wall must conceal nearby objective")
	assert(not game.player_can_see(game.objective), "Loot behind a building wall must be hidden")
	assert(game.objective_button.disabled)
	var previous_camera = game.camera
	game.center_objective()
	assert(game.camera == previous_camera, "Navigation must not leak hidden location")
	game.player = Vector2i(15, 6)
	game.refresh()
	assert(game.objective_visible() and not game.objective_button.disabled)
	assert(game.player_can_see(game.objective), "Nearby loot in clear sight is visible")
	game.player = Vector2i(1, 1)
	game.objective = Vector2i(10, 1)
	game.refresh()
	assert(not game.objective_visible(), "Clear sight outside range is insufficient")
	assert(not game.player_can_see(game.objective), "Panning to distant loot does not reveal it")
	game.objective_collected = true
	game.exfil = Vector2i(22, 22)
	game.refresh()
	assert(not game.objective_visible() and not game.objective_button.disabled and game.objective_button.text == "EXFIL")
	game.center_objective()
	assert(Rect2(game.camera, game.MAP_VIEW_SIZE).has_point(Vector2(game.exfil) * game.CELL), "Extraction is locatable after pickup without seeing it")
	game.new_raid()
	assert(not game.objective_collected and game.objective_button.disabled)
	print("PASS: indoor objective spawn, wall/range concealment, guarded navigation, sight reveal, extraction navigation after collection, raid reset")
	return true

func test_combat_options(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	game.combat = true
	assert(game.ap == 4)
	game.enemy_turn()
	assert(game.ap == 8)
	game.combat = true
	game.enemy_turn()
	assert(game.ap == 8, "Banked AP must cap at eight")
	game.combat = true
	game.ap = 1
	game.enemy_turn()
	assert(game.ap == 5, "Unused AP must carry over and gain four")
	game.combat = true
	game.ap = 4
	game.enemies.append({"pos": Vector2i(4, 1), "hp": 1000, "facing": Vector2i.RIGHT})
	game.selected = 0
	game.choose_shot(0)
	assert(game.shot_chance(Vector2i(4, 1)) == 71)
	game.choose_shot(1)
	assert(game.shot_chance(Vector2i(4, 1)) == 51)
	game.choose_shot(2)
	assert(game.shot_chance(Vector2i(4, 1)) == 56)
	game.aim_weapon()
	assert(game.ap == 3 and game.aiming and game.shot_chance(Vector2i(4, 1)) == 86)
	game.aim_weapon()
	assert(game.ap == 3, "Aim cannot stack or spend twice")
	game.enemies.clear()
	game.enemy_turn()
	assert(game.aiming and game.ap == 7, "Aim persists across turns when no hit lands")
	game.combat = true
	game.move_to(Vector2i(2, 1))
	assert(not game.aiming and game.ap == 6)
	game.aim_weapon()
	game.take_damage(0)
	assert(game.aiming, "Misses must not cancel Aim")
	game.take_damage(12)
	assert(not game.aiming)
	# Actual enemy-phase misses preserve Aim, while a real hit cancels it.
	var enemy_rolls = RandomNumberGenerator.new()
	var miss_seed = -1
	var hit_seed = -1
	for candidate in range(1000):
		enemy_rolls.seed = candidate
		var first_roll = enemy_rolls.randi_range(1, 100)
		var second_roll = enemy_rolls.randi_range(1, 100)
		if first_roll > 87 and second_roll > 87:
			miss_seed = candidate
		if first_roll <= 87 and second_roll <= 87:
			hit_seed = candidate
		if miss_seed >= 0 and hit_seed >= 0:
			break
	assert(miss_seed >= 0 and hit_seed >= 0)
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 60, "facing": Vector2i.LEFT})
	game.aiming = true
	game.combat = true
	game.hp = 100
	game.rng.seed = miss_seed
	game.enemy_turn()
	assert(game.aiming and game.hp == 100)
	game.rng.seed = hit_seed
	game.enemy_turn()
	assert(not game.aiming and game.hp == 76)

	for mode in range(3):
		var samples = RandomNumberGenerator.new()
		game.enemies.clear()
		game.player = Vector2i(1, 1)
		game.enemies.append({"pos": Vector2i(4, 1), "hp": 1000, "facing": Vector2i.RIGHT})
		game.selected = 0
		game.combat = true
		game.ap = 8
		game.ammo = 7
		game.aiming = true
		game.choose_shot(mode)
		game.rng.seed = 42
		samples.seed = 42
		var rounds = samples.randi_range(2, 3) if mode == 2 else 1
		var hits = 0
		var chance = game.shot_chance(game.enemies[0].pos)
		for round_index in range(rounds):
			if samples.randi_range(1, 100) <= chance:
				hits += 1
		game.shoot()
		var damages = [35, 60, 35]
		assert(game.enemies[0].hp == 1000 - hits * damages[mode])
		assert(game.ammo == 7 - rounds and game.ap == 8 - (2 if mode == 2 else 1))
		assert(game.aiming, "Firing any attack must preserve Aim")
		var remaining = game.ammo
		game.shoot()
		assert(game.aiming and game.ammo < remaining, "Aim must persist through successive attacks")
	game.choose_shot(2)
	game.ammo = 1
	game.ap = 8
	assert(not game.can_fire())
	game.shoot()
	assert(game.ammo == 1 and game.ap == 8, "Burst requires at least two loaded rounds")
	game.ammo = 2
	game.ap = 1
	assert(not game.can_fire())
	game.ap = 2
	game.shoot()
	assert(game.ammo == 0 and game.ap == 0)
	game.new_raid()
	assert(game.ap == 4 and not game.aiming and game.shot_mode == 0)
	print("PASS: four AP, banking/cap, body/head/burst odds and damage, ammo/AP accounting, Aim bonus/persistence through multiple shots/movement/hit cancellation, invalid attacks, raid reset")
	return true

func test_full_wall_corners(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	var defender = Vector2i(2, 3)
	var attacker = Vector2i(4, 5)
	assert(game.is_corner_edge(defender, Vector2i.RIGHT))
	assert(game.adjacent_cover(defender))
	assert(game.line_of_sight(defender, attacker) and game.line_of_sight(attacker, defender))
	assert(game.cover_at(defender, attacker))
	assert(game.hit_chance(attacker, defender) == 38, "Corner reduces incoming aim by 25 points")
	assert(game.hit_chance(defender, attacker) == 63, "Peeking around own corner does not penalize outgoing shots")
	assert(not game.cover_at(defender, Vector2i(1, 5)), "Opposite side flanks corner cover")
	assert(not game.cover_at(defender, Vector2i(2, 5)), "Shots along exposed side do not receive wall protection")
	assert(not game.line_of_sight(defender, Vector2i(5, 3)))
	assert(not game.cover_at(defender, Vector2i(5, 3)), "Corner cover never allows firing through solid walls")
	assert(not game.adjacent_cover(Vector2i(2, 4)), "Diagonal-only wall proximity does not grant cover")
	assert(game.cover_at(Vector2i(4, 1), Vector2i(6, 3)), "Corners work on horizontal wall faces too")
	game.player = attacker
	game.enemies.append({"pos": defender, "hp": 60, "facing": Vector2i.DOWN})
	game.selected = 0
	game.combat = true
	game.refresh()
	assert("38%" in game.intel.text and "COVER" in game.intel.text, "Enemy corner cover is reflected in shot preview")
	game.player = defender
	game.enemies[0].pos = attacker
	game.enemies[0].facing = Vector2i.UP
	game.refresh()
	assert("63%" in game.intel.text and "COVER" in game.intel.text, "Player gets corner cover and keeps outgoing accuracy")
	print("PASS: automatic full-wall corner cover, incoming penalty, unpenalized peeking, flanking, blocked walls, cardinal adjacency, horizontal corners, player/enemy preview")
	return true
