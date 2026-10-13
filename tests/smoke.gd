extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var save_existed = FileAccess.file_exists("user://stash.json")
	var original_save = FileAccess.get_file_as_string("user://stash.json") if save_existed else ""
	var game = load("res://main.tscn").instantiate()
	game.animations_enabled = false
	root.add_child(game)
	await process_frame
	game.saved_gear = game.default_gear()
	game.rng.seed = 77
	game.new_raid()
	assert(game.distance(game.player, game.exfil) >= 8)
	assert(game.enemies.size() == 24 and game.loot.size() == 16)
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
	game.loot.append({"pos": Vector2i(2, 1), "kind": 0})
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
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.ap == 4)
	game.ap = 2
	assert(game.hit_chance(Vector2i(2, 1), Vector2i(4, 1)) > game.hit_chance(Vector2i(1, 1), Vector2i(7, 1)))
	assert(not game.line_of_sight(Vector2i(13, 4), Vector2i(15, 4)))
	assert(not game.cover_at(Vector2i(13, 4), Vector2i(15, 4)), "Full walls block shots rather than apply low cover")
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
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.finished and game.hp == 0 and game.stash == bank)
	for seed_value in range(100):
		game.rng.seed = seed_value
		game.new_raid()
		assert(game.distance(game.player, game.exfil) >= 8)
		game.enemies.clear()
		assert(not game.path_to(game.exfil).is_empty(), "Extraction must be connected to insertion")
	assert(test_spotting_visibility(game), "Spotting visibility checks must complete")
	assert(test_automatic_combat_end(game), "Automatic combat exit checks must complete")
	assert(test_corner_peeking(game), "Peeking checks must complete")
	assert(test_full_wall_corners(game), "Corner-cover checks must complete")
	assert(test_combat_options(game), "Expanded combat tests must complete")
	assert(test_objective_visibility(game), "Objective visibility checks must complete")
	assert(test_map_and_bodies(game), "Expanded map checks must complete")
	assert(test_objective_facing_loot(game), "New raid mechanics must complete")
	assert(test_health_and_cover(game), "Health and cover checks must all complete")
	assert(test_ammo(game), "Ammo checks must all complete")
	assert(test_weapons(game), "Weapon checks must complete")
	assert(test_gear_loot_and_persistence(game), "Typed ammo and persistent gun checks must complete")
	assert(await test_bleeding_and_bandages(game), "Bleeding and bandage checks must complete")
	assert(test_enemy_ai(game), "Enemy AI checks must complete")
	assert(test_sight_and_zoom(game), "Sight and zoom checks must complete")
	assert(await test_animated_movement(game), "Animated movement checks must complete")
	assert(await test_shot_meter(game), "Shot timing checks must complete")
	print("PASS: randomized placements, idle freeze, movement ticks, loot, contact interruption, AP, enemy turn, LOS, cover, range, shooting, reloading, extraction, death, 100 raid seeds")
	if save_existed:
		var restore_file = FileAccess.open("user://stash.json", FileAccess.WRITE)
		restore_file.store_string(original_save)
		restore_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://stash.json"))
	game.queue_free()
	quit(0)

func test_ammo(game) -> bool:
	game.new_raid()
	assert(game.ammo == 7 and game.reserve == 24)
	assert(game.ammo_status.text == "GUN 7/7 • AMMO 24 9mm • TOTAL 31")
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
	game.loot.append({"pos": Vector2i(2, 1), "kind": 0})
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
	assert(game.ammo_status.text == "GUN 0/7 • AMMO 7 9mm • TOTAL 7")
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
	game.loot.append({"pos": Vector2i(2, 1), "kind": 1})
	game.move_to(Vector2i(2, 1))
	assert(game.hp == 50 and game.health_kits == 1 and game.ticks == 1, "Health pickups are carried without automatic healing")
	game.move_to(Vector2i(1, 1))
	game.move_to(Vector2i(2, 1))
	assert(game.health_kits == 1, "A looted crate cannot award a kit twice")
	game.show_inventory()
	assert("Health kits: 1" in game.inventory_dialog.dialog_text and "Bandages: 1" in game.inventory_dialog.dialog_text)
	game.inventory_dialog.custom_action.emit("heal")
	assert(game.hp == 75 and game.health_kits == 0 and game.ticks == 4)
	game.inventory_dialog.hide()
	game.use_health_kit()
	assert(game.hp == 75 and game.ticks == 4, "No kit must cost no time")
	game.health_kits = 2
	game.hp = 90
	game.combat = true
	game.ap = 0
	game.use_health_kit()
	assert(game.hp == 90 and game.health_kits == 2)
	game.ap = 4
	game.use_health_kit()
	assert(game.hp == 100 and game.health_kits == 1 and game.ap == 3 and game.ticks == 4, "Combat kits cost one AP and cap health")
	game.use_health_kit()
	assert(game.health_kits == 1 and game.ap == 3, "Full health must not waste a kit or AP")
	game.hp = 70
	game.bleeding = true
	game.use_health_kit()
	assert(game.hp == 95 and game.bleeding and game.ap == 2, "Health kits do not stop bleeding")
	game.bleeding = false
	var north = Vector2i(3, 8)
	var south = Vector2i(3, 10)
	assert(not game.walkable(Vector2i(3, 9)) and not game.blocks_sight(Vector2i(3, 9)))
	assert(game.line_of_sight(north, south) and game.line_of_sight(south, north), "Low cover must allow reciprocal sight and fire")
	assert(game.adjacent_low_cover(north) and game.adjacent_low_cover(south))
	assert(game.cover_at(north, south) and game.cover_at(south, north), "Both sides of a barrier receive cover")
	assert(not game.cover_at(north, Vector2i(3, 6)), "Rear attacks flank cover")
	assert(not game.cover_at(north, Vector2i(1, 8)), "Side attacks flank cover")
	assert(not game.cover_at(Vector2i(2, 8), south), "A distant barrier does not protect the target")
	assert(game.hit_chance(north, south) == 60 and game.hit_chance(south, north) == 60)
	assert(game.hit_chance(south, Vector2i(2, 8)) == 80, "Firing over your own cover has no accuracy penalty")
	assert(game.hit_chance(Vector2i(2, 8), south) == 55, "Only the defender's cover reduces incoming aim")
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
	assert("COVER" in game.intel.text and "60%" in game.intel.text)
	game.shoot()
	assert(game.ammo == 6 and game.ap == 1, "Player can fire across low cover")
	# An enemy firing over its own cover at an uncovered flank keeps 80% aim.
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
		if first > 55 and first <= 80 and second > 55 and second <= 80:
			firing_seed = candidate
			break
	assert(firing_seed >= 0)
	game.rng.seed = firing_seed
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.hp == 76, "Enemy can fire twice over its own cover without an aim penalty")
	assert(not game.walkable(Vector2i(3, 3)) and game.blocks_sight(Vector2i(3, 3)))
	assert(not game.line_of_sight(Vector2i(13, 4), Vector2i(15, 4)), "Full walls still block visibility")
	print("PASS: carried health kits, inventory medical actions, health cap, one-tick/one-AP healing, invalid uses, low-cover movement/LOS, automatic directional cover, flanking, reciprocal shots, own-cover accuracy, cover HUD")
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
		assert(game.enemies.size() == 24)
		assert(game.objective != game.exfil and game.walkable(game.objective) and game.is_indoors(game.objective))
		assert(game.loot.size() == 16 and not game.objective_collected)
		objective_locations[game.objective] = true
		for e in game.enemies:
			assert(game.DIRS.has(e.facing) and e.pos != game.objective)
		for crate in game.loot:
			assert(crate.pos != game.objective and crate.kind >= 0 and crate.kind <= 3)
			loot_kinds[crate.kind] = true
		game.enemies.clear()
		assert(not game.path_to(game.objective).is_empty())
	assert(objective_locations.size() > 1 and loot_kinds.size() == 4)
	game.player = game.exfil
	var bank = game.stash
	game.extract()
	assert(not game.finished and game.stash == bank and game.extract_button.disabled)
	game.player = Vector2i(1, 1)
	game.objective = Vector2i(2, 1)
	game.move_to(game.objective)
	assert(game.objective_collected)
	for kind in range(4):
		game.loot.clear()
		game.loot.append({"pos": Vector2i(3, 1), "kind": kind})
		game.player = Vector2i(2, 1)
		game.hp = 50
		game.reserve = 0
		var kits_before = game.health_kits
		var bandages_before = game.bandages
		game.move_to(Vector2i(3, 1))
		assert(game.health_kits == kits_before + (1 if kind == 1 else 0))
		assert(game.bandages == bandages_before + (1 if kind == 3 else 0))
		assert(game.reserve == (7 if kind == 0 else 0))
		assert(game.hp == 50, "Loot never automatically heals")
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
	game.player = Vector2i(13, 4)
	guard = {"pos": Vector2i(15, 4), "hp": 60, "facing": Vector2i.LEFT}
	assert(not game.enemy_can_see_player(guard), "Full walls still block facing-based detection")
	print("PASS: distant randomized objective, locked extraction, objective pickup, sixteen varied crates, directional sight, player visibility, patrol facing, low/full cover detection")
	return true

func test_map_and_bodies(game) -> bool:
	game.new_raid()
	assert(game.MAP.size() == 48 and game.MAP[0].length() == 48)
	for y in range(game.MAP_SIZE):
		for x in range(game.MAP_SIZE):
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
		assert(indoor_count == 12)
		var guards_per_district = [0, 0, 0, 0]
		var crates_per_district = [0, 0, 0, 0]
		for guard in game.enemies:
			guards_per_district[game.district_at(guard.pos)] += 1
			assert(game.distance(guard.pos, game.player) >= 5)
		for crate in game.loot:
			crates_per_district[game.district_at(crate.pos)] += 1
		assert(guards_per_district == [6, 6, 6, 6] and crates_per_district == [4, 4, 4, 4], "Patrols and loot must span every district")
		assert(game.BUILDINGS.size() == 12 and game.distance(game.player, game.objective) >= 16)
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 0, "loot_kind": 0, "searched": false})
	game.hp = 50
	game.reserve = 0
	game.ticks = 0
	game.cargo = 0
	game.combat = false
	game.search_body(0)
	assert(game.enemies[0].searched and game.hp == 50 and game.reserve == 7 and game.cargo == 1 and game.ticks == 1)
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
	assert(game.camera == Vector2(0, game.MAP_SIZE * game.CELL - game.MAP_VIEW_SIZE.y))
	game.camera = Vector2(9999, -999)
	game.clamp_camera()
	assert(game.camera == Vector2(game.MAP_SIZE * game.CELL - game.MAP_VIEW_SIZE.x, 0))
	game.player = Vector2i(20, 20)
	game.center_player()
	assert(Rect2(game.camera, game.MAP_VIEW_SIZE).has_point(Vector2(game.player) * game.CELL))
	print("PASS: 48x48 map, cover gaps including diagonals, single building entrances, accessible interiors, indoor loot bias, body search timing/AP/rewards/patrols, no duplicate or remote search, camera bounds")
	return true

func test_objective_visibility(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.player = Vector2i(13, 4)
	game.objective = Vector2i(15, 4)
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
	game.objective = Vector2i(12, 1)
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
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.ap == 4)
	game.combat = true
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.ap == 4, "Skipping a full turn must not accumulate AP")
	game.combat = true
	game.ap = 1
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.ap == 4, "Unused AP must be discarded at the next turn")
	game.combat = true
	game.ap = 4
	game.enemies.append({"pos": Vector2i(4, 1), "hp": 1000, "facing": Vector2i.RIGHT})
	game.selected = 0
	game.choose_shot(0)
	assert(game.shot_chance(Vector2i(4, 1)) == 80)
	game.choose_shot(1)
	assert(game.shot_chance(Vector2i(4, 1)) == 60)
	game.choose_shot(2)
	assert(game.shot_chance(Vector2i(4, 1)) == 65)
	game.aim_weapon()
	assert(game.ap == 3 and game.aiming and game.shot_chance(Vector2i(4, 1)) == 95)
	game.aim_weapon()
	assert(game.ap == 3, "Aim cannot stack or spend twice")
	game.enemies.clear()
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.aiming and game.ap == 4, "Aim persists across turns when no hit lands")
	game.combat = true
	game.move_to(Vector2i(2, 1))
	assert(not game.aiming and game.ap == 3)
	game.aim_weapon()
	game.take_damage(0)
	assert(game.aiming, "Misses must not cancel Aim")
	game.bleed_rng.seed = safe_bleed_seed()
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
		if first_roll > 90 and second_roll > 90:
			miss_seed = candidate
		if first_roll <= 90 and second_roll <= 90:
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
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.aiming and game.hp == 100)
	game.rng.seed = hit_seed
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(not game.aiming and game.hp == 76)

	for mode in range(3):
		var samples = RandomNumberGenerator.new()
		game.enemies.clear()
		game.player = Vector2i(1, 1)
		game.enemies.append({"pos": Vector2i(4, 1), "hp": 1000, "facing": Vector2i.RIGHT})
		game.selected = 0
		game.combat = true
		game.ap = 4
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
		assert(game.ammo == 7 - rounds and game.ap == 4 - (2 if mode == 2 else 1))
		assert(game.aiming, "Firing any attack must preserve Aim")
		var remaining = game.ammo
		game.shoot()
		assert(game.aiming and game.ammo < remaining, "Aim must persist through successive attacks")
	game.choose_shot(2)
	game.ammo = 1
	game.ap = 4
	assert(not game.can_fire())
	game.shoot()
	assert(game.ammo == 1 and game.ap == 4, "Burst requires at least two loaded rounds")
	game.ammo = 2
	game.ap = 1
	assert(not game.can_fire())
	game.ap = 2
	game.shoot()
	assert(game.ammo == 0 and game.ap == 0)
	game.new_raid()
	assert(game.ap == 4 and not game.aiming and game.shot_mode == 0)
	print("PASS: four AP per turn without carryover, body/head/burst odds and damage, ammo/AP accounting, Aim bonus/persistence through multiple shots/movement/hit cancellation, invalid attacks, raid reset")
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
	assert(game.hit_chance(attacker, defender) == 50, "Corner reduces incoming aim by 25 points")
	assert(game.hit_chance(defender, attacker) == 75, "Peeking around own corner does not penalize outgoing shots")
	assert(not game.cover_at(defender, Vector2i(1, 5)), "Opposite side flanks corner cover")
	assert(not game.cover_at(defender, Vector2i(2, 5)), "Shots along exposed side do not receive wall protection")
	assert(not game.line_of_sight(Vector2i(13, 4), Vector2i(15, 4)))
	assert(not game.cover_at(Vector2i(13, 4), Vector2i(15, 4)), "Flat walls still block shots")
	assert(not game.adjacent_cover(Vector2i(2, 4)), "Diagonal-only wall proximity does not grant cover")
	assert(game.cover_at(Vector2i(4, 1), Vector2i(6, 3)), "Corners work on horizontal wall faces too")
	game.player = attacker
	game.enemies.append({"pos": defender, "hp": 60, "facing": Vector2i.DOWN})
	game.selected = 0
	game.combat = true
	game.refresh()
	assert("50%" in game.intel.text and "COVER" in game.intel.text, "Enemy corner cover is reflected in shot preview")
	game.player = defender
	game.enemies[0].pos = attacker
	game.enemies[0].facing = Vector2i.UP
	game.refresh()
	assert("75%" in game.intel.text and "COVER" in game.intel.text, "Player gets corner cover and keeps outgoing accuracy")
	print("PASS: automatic full-wall corner cover, incoming penalty, unpenalized peeking, flanking, blocked walls, cardinal adjacency, horizontal corners, player/enemy preview")
	return true

func test_corner_peeking(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	var edge = Vector2i(2, 2)
	var target = Vector2i(5, 1)
	assert(not game.clear_ray(edge, target), "Unit-center ray is obstructed")
	assert(game.line_of_sight(edge, target) and game.line_of_sight(target, edge), "Peeking exposes a reciprocal firing line")
	assert(game.cover_at(edge, target), "Peeking retains defensive cover")
	game.player = edge
	assert(game.player_can_see(target), "Viewer can see around its own corner")
	game.enemies.append({"pos": target, "hp": 1000, "facing": Vector2i.LEFT})
	game.combat = true
	game.selected = 0
	game.ap = 4
	game.shoot()
	assert(game.ammo == 6 and game.ap == 3, "Player can commit a shot around a corner")
	assert(game.enemy_can_see_player(game.enemies[0]), "An exposed peeking player can be detected and targeted")
	game.player = Vector2i(13, 4)
	assert(not game.line_of_sight(game.player, Vector2i(15, 4)), "Flat wall cannot be bypassed")
	assert(game.peek_positions(Vector2i(13, 4)).size() == 1)
	game.player = target
	assert(not game.player_can_see(edge), "Loot cannot peek from the hidden endpoint")
	assert(game.line_of_sight(Vector2i(2, 3), Vector2i(5, 3)), "Two actors may both peek around the same exposed edge")
	assert(not game.clear_ray(Vector2i(3, 3), target), "Wall tiles cannot be virtual firing origins")
	print("PASS: corner peeking visibility and shooting, reciprocal detection, cover retained, flat-wall blocking, stationary loot cannot peek, dual-edge peeking")
	return true

func test_automatic_combat_end(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.combat = true
	game.ap = 2
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 0, "alerted": true})
	game.enemies.append({"pos": Vector2i(22, 22), "hp": 60, "alerted": false})
	var ticks_before = game.ticks
	var hp_before = game.hp
	game.finish_cleared_engagement()
	game.refresh()
	assert(not game.combat and game.end_button.disabled and game.ap == 2)
	assert(game.ticks == ticks_before and game.hp == hp_before, "Automatic exit must not grant enemies a turn")
	game.combat = true
	game.enemies[1].alerted = true
	game.finish_cleared_engagement()
	assert(game.combat, "A surviving engaged enemy keeps combat active even out of sight")
	game.enemies[1].hp = 0
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 60, "facing": Vector2i.LEFT})
	game.finish_cleared_engagement()
	assert(game.combat, "A guard that can see the player remains a threat")
	game.enemies.clear()
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 1, "facing": Vector2i.LEFT})
	game.selected = 0
	game.ap = 1
	game.ammo = 7
	game.aiming = true
	game.rng.seed = 42
	game.shoot()
	assert(game.enemies[0].hp <= 0 and not game.combat and game.ap == 0 and game.ammo == 6)
	assert(game.aiming and game.ticks == ticks_before, "Final shot keeps Aim and adds no world tick")
	assert(game.enemies[0].has("loot_kind") and not game.enemies[0].searched)
	game.enter_combat()
	assert(game.combat and game.ap == 4, "Fresh engagement starts with four AP")
	game.combat = false
	game.ap = 7
	game.enter_combat()
	assert(game.ap == 4, "Fresh engagements reset AP to four")
	print("PASS: automatic exit after final kill, distant unengaged patrols ignored, surviving threats retained, no extra enemy turn/tick/AP grant, body loot and Aim preserved, fresh engagement AP")
	return true

func test_spotting_visibility(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	var guard = {"pos": Vector2i(7, 1), "hp": 60, "facing": Vector2i.LEFT}
	game.enemies.append(guard)
	game.camera = Vector2(432, 504)
	assert(game.enemy_can_see_player(guard))
	game.world_tick()
	assert(game.combat and guard.pos == Vector2i(7, 1) and guard.facing == Vector2i.LEFT)
	assert(game.visible(guard) and game.selected == 0 and game.can_fire())
	var viewport = Rect2(game.camera, game.MAP_VIEW_SIZE)
	assert(viewport.has_point(Vector2(game.player) * game.CELL + Vector2(18, 18)))
	assert(viewport.has_point(Vector2(guard.pos) * game.CELL + Vector2(18, 18)), "Spotter must be in the scrolled view")
	game.camera = Vector2(432, 504)
	game.ap = 0
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(game.visible(guard) and game.selected == 0)
	assert(Rect2(game.camera, game.MAP_VIEW_SIZE).has_point(Vector2(guard.pos) * game.CELL + Vector2(18, 18)))
	# Move-to contact must stop with the detector still drawable and selectable.
	game.new_raid()
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.enemies.append({"pos": Vector2i(7, 1), "hp": 60, "facing": Vector2i.LEFT})
	game.move_to(Vector2i(5, 1))
	assert(game.combat and game.player == Vector2i(2, 1) and game.visible(game.enemies[0]))
	assert(game.selected == 0)
	print("PASS: ammo HUD wording, reciprocal spotting, detectors hold position, automatic targeting and camera framing, contact interrupts movement, threats framed after enemy turn")
	return true

func safe_bleed_seed() -> int:
	var rolls = RandomNumberGenerator.new()
	for candidate in range(1000):
		rolls.seed = candidate
		var safe = true
		for i in range(8):
			if rolls.randi_range(1, 100) <= 15:
				safe = false
		if safe:
			return candidate
	assert(false, "A deterministic non-bleeding seed is required")
	return -1

func test_weapons(game) -> bool:
	var rolls = RandomNumberGenerator.new()
	var hit_seed = -1
	for candidate in range(1000):
		rolls.seed = candidate
		if rolls.randi_range(1, 100) <= 5:
			hit_seed = candidate
			break
	assert(hit_seed >= 0)
	var magazines = [7, 20, 6, 5, 25]
	var damage = [35, 40, 55, 65, 24]
	var shot_cost = [1, 1, 2, 2, 1]
	var odds = [80, 83, 75, 89, 82]
	for weapon in range(5):
		game.new_raid()
		var found = {"pos": game.player, "weapon_id": weapon, "ammo": magazines[weapon], "gun_available": true}
		game.offer_gun(found)
		game.gun_dialog.confirmed.emit()
		game.reserve = 24
		assert(game.weapon_id == weapon and game.ammo == magazines[weapon] and game.reserve == 24)
		assert(game.ticks == 0 and game.ap == 4)
		game.enemies.clear()
		game.loot.clear()
		game.player = Vector2i(1, 1)
		game.enemies.append({"pos": Vector2i(4, 1), "hp": 1000, "facing": Vector2i.RIGHT})
		game.combat = true
		game.selected = 0
		assert(game.shot_chance(Vector2i(4, 1)) == odds[weapon], "Weapons must have distinct range/accuracy curves")
		for mode in range(2):
			game.choose_shot(mode)
			game.ap = 4
			game.rng.seed = hit_seed
			var old_hp = game.enemies[0].hp
			var old_ammo = game.ammo
			assert(game.can_fire())
			game.shoot()
			var expected_damage = roundi(damage[weapon] * 60.0 / 35.0) if mode == 1 else damage[weapon]
			assert(game.enemies[0].hp == old_hp - expected_damage)
			assert(game.ap == 4 - shot_cost[weapon] and game.ammo == old_ammo - 1)
		game.ap = shot_cost[weapon] - 1
		assert(not game.can_fire(), "Insufficient AP must block weapon-specific attacks")
		game.choose_shot(2)
		if weapon in [2, 3]:
			assert(game.shot_mode == 1 and game.shot_buttons[2].disabled, "Shotgun/sniper cannot burst")
		else:
			assert(game.shot_mode == 2 and not game.shot_buttons[2].disabled)
			game.ap = 4
			game.ammo = 2
			game.shoot()
			assert(game.ammo == 0 and game.ap == 2, "Supported bursts consume actual rounds and two AP")
		game.choose_shot(0)
		game.ap = 4
		game.ammo = 1
		game.enemies[0].pos = Vector2i(8, 1)
		assert(game.can_fire() == (weapon != 2), "Shotgun range must limit shooting without hiding the target")
		game.ammo = 0
		game.reserve = 3
		game.reload_weapon()
		assert(game.ammo == 3 and game.reserve == 0 and game.ap == 2)
		game.combat = false
		game.reserve = 100
		game.reload_weapon()
		assert(game.ammo == magazines[weapon] and game.reserve == 103 - magazines[weapon])
		game.new_raid()
		assert(game.weapon_id == 0 and game.ammo == 7, "Abandoning a raid restores the starting pistol")
	print("PASS: five weapon profiles, body/head damage and AP, accuracy curves, burst support/consumption, shotgun range, magazine-specific partial/full reloads, optional gun swaps")
	return true

func test_bleeding_and_bandages(game) -> bool:
	var rolls = RandomNumberGenerator.new()
	var bleed_seed = -1
	for candidate in range(1000):
		rolls.seed = candidate
		if rolls.randi_range(1, 100) <= game.BLEED_CHANCE:
			bleed_seed = candidate
			break
	assert(bleed_seed >= 0)
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	game.bleed_rng.seed = bleed_seed
	var state = game.bleed_rng.state
	game.take_damage(0)
	assert(game.hp == 100 and not game.bleeding and game.bleed_rng.state == state, "Misses cannot trigger bleeding")
	game.bleed_rng.seed = safe_bleed_seed()
	game.take_damage(1)
	assert(game.hp == 99 and not game.bleeding, "Damage must also be able to avoid bleeding")
	game.bleed_rng.seed = bleed_seed
	game.take_damage(1)
	assert(game.hp == 98 and game.bleeding)
	game.refresh()
	assert("BLEED -3" in game.intel.text and not game.bandage_button.disabled)
	state = game.bleed_rng.state
	game.take_damage(1)
	assert(game.hp == 97 and game.bleed_rng.state == state, "Bleeding does not stack or roll again")
	await process_frame
	await process_frame
	assert(game.hp == 97 and game.ticks == 0, "Bleeding must freeze while idle")
	game.move_to(Vector2i(4, 1))
	assert(game.hp == 88 and game.ticks == 3, "Travel must apply bleeding once per actual exploration step")
	game.ammo = 0
	game.reload_weapon()
	assert(game.hp == 85 and game.ticks == 4, "Exploration reload is one bleeding tick")
	game.enemies.append({"pos": Vector2i(5, 1), "hp": 0, "loot_kind": 0, "searched": false})
	game.search_body(0)
	assert(game.hp == 82 and game.ticks == 5, "Exploration body search is one bleeding tick")
	game.apply_loot(1, "Crate")
	assert(game.hp == 82 and game.health_kits == 1 and game.bleeding)
	game.combat = true
	game.ap = 4
	game.use_health_kit()
	game.combat = false
	assert(game.hp == 100 and game.bleeding, "Health kits must not stop bleeding")
	var dressings = game.bandages
	game.apply_loot(3, "Crate")
	assert(game.bandages == dressings + 1 and game.hp == 100)
	game.hp = 50
	game.inventory_dialog.custom_action.emit("bandage")
	assert(not game.bleeding and game.hp == 50 and game.bandages == dressings and game.ticks == 6)
	game.use_bandage()
	assert(game.ticks == 6 and game.bandages == dressings, "No bleeding must not waste time or bandages")
	game.bleeding = true
	game.bandages = 0
	game.use_bandage()
	assert(game.bleeding and game.ticks == 6, "No bandages must not stop bleeding")
	game.bandages = 1
	game.combat = true
	game.ap = 0
	game.use_bandage()
	assert(game.bleeding and game.bandages == 1 and game.ap == 0)
	game.ap = 4
	game.use_bandage()
	assert(not game.bleeding and game.hp == 50 and game.ap == 3 and game.ticks == 6 and game.bandages == 0)
	game.bleeding = true
	game.move_to(Vector2i(3, 1))
	assert(game.hp == 50, "Combat movement must not charge an extra bleeding tick")
	game.enemies.clear()
	game.enemies.append({"pos": Vector2i(6, 1), "hp": 1000, "facing": Vector2i.RIGHT})
	game.selected = 0
	game.aim_weapon()
	game.shoot()
	assert(game.hp == 50 and game.bleeding, "Combat actions do not each charge bleeding")
	game.enemies.clear()
	game.enemy_turn()
	assert(game.hp == 47 and not game.combat, "One completed combat round applies bleeding once")
	assert(not game.aiming, "Bleeding damage cancels Aim")
	game.enemies.append({"pos": Vector2i(4, 1), "hp": 0, "loot_kind": 3, "searched": false})
	game.search_body(0)
	assert(game.bandages == 1 and game.enemies[0].searched and game.bleeding, "Bodies can supply bandages without automatically using them")
	game.hp = 4
	var saved_bank = game.stash
	game.move_to(Vector2i(6, 1))
	assert(game.finished and game.hp == 0 and game.player == Vector2i(5, 1), "Bleeding death must interrupt multi-tile travel")
	assert(game.stash == saved_bank and not game.can_bandage() and not game.can_reload())
	game.new_raid()
	assert(not game.bleeding and game.bandages == 1 and game.hp == 100)
	assert(game.health_kits == 0, "A new raid resets medical supplies")
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.enemies.append({"pos": Vector2i(2, 1), "hp": 60, "facing": Vector2i.LEFT})
	game.combat = true
	var two_hits_seed = -1
	for candidate in range(1000):
		rolls.seed = candidate
		var first = rolls.randi_range(1, 100)
		var second = rolls.randi_range(1, 100)
		if first <= 90 and second <= 90:
			two_hits_seed = candidate
			break
	assert(two_hits_seed >= 0)
	game.rng.seed = two_hits_seed
	game.bleed_rng.seed = bleed_seed
	game.enemy_turn()
	assert(game.bleeding and game.hp == 73, "Actual enemy hits must trigger bleeding and exactly one three-HP round charge")
	game.inventory_dialog.custom_action.emit("bandage")
	assert(not game.bleeding and game.bandages == 0 and game.hp == 73 and game.ap == 3)
	game.new_raid()
	print("PASS: bleeding chance and misses, non-stacking status, idle freeze, exploration move/reload/search ticks, single combat-round damage, healing cannot stop bleeding, bandage crate/body loot, 1-tick/1-AP treatment, invalid uses, bleeding death/travel interruption, raid reset")
	return true

func test_gear_loot_and_persistence(game) -> bool:
	game.new_raid()
	assert(game.weapon_id == 0 and game.ammo == 7 and game.carried_ammo == [24, 0, 0, 0, 0])
	var crate_weapons = {}
	var ammo_types = {}
	var enemy_weapons = {}
	for seed_value in range(100):
		game.rng.seed = seed_value
		game.new_raid()
		for crate in game.loot:
			assert(not crate.searched and crate.kind >= 0 and crate.kind <= 3)
			assert(crate.gun_available == (crate.kind == 2), "A crate holds exactly one category, never a bonus gun")
			if crate.kind == 0:
				assert(crate.ammo_type >= 0 and crate.ammo_type < 5)
				ammo_types[crate.ammo_type] = true
			else:
				assert(crate.ammo_type == -1, "Non-ammo crates contain no spare rounds")
			if crate.gun_available:
				crate_weapons[crate.weapon_id] = true
				assert(crate.weapon_id > 0 and crate.weapon_id < 5 and crate.ammo <= game.WEAPONS[crate.weapon_id].magazine)
		for e in game.enemies:
			enemy_weapons[e.weapon_id] = true
			assert(e.ammo_type == e.weapon_id and e.ammo == game.WEAPONS[e.weapon_id].magazine and e.reserve >= 0)
	assert(crate_weapons.size() == 4 and ammo_types.size() == 5 and enemy_weapons.size() == 5)
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	game.exfil = Vector2i(10, 10)
	game.carried_ammo[1] = 7
	var crate = {"pos": Vector2i(2, 1), "kind": 2, "ammo_type": -1, "weapon_id": 1, "ammo": 6, "gun_available": true, "searched": false}
	game.loot.append(crate)
	game.move_to(Vector2i(5, 1))
	assert(game.player == Vector2i(2, 1) and game.ticks == 1 and game.gun_dialog.visible, "Discovery must interrupt travel and ask before equipping")
	assert(game.weapon_id == 0 and game.ammo == 7 and game.reserve == 24 and game.carried_ammo[1] == 7)
	assert(game.total_ammo() == 38 and "TOTAL 38" in game.ammo_status.text, "Total ammo includes rounds of other types")
	var cargo_before = game.cargo
	game.gun_dialog.canceled.emit()
	assert(game.weapon_id == 0 and not game.gun_dialog.visible and crate.gun_available)
	game.move_to(Vector2i(1, 1))
	game.move_to(Vector2i(2, 1))
	assert(game.cargo == cargo_before and game.carried_ammo[1] == 7, "Revisiting revealed loot cannot duplicate supplies or ammo")
	var tick_before = game.ticks
	game.gun_dialog.confirmed.emit()
	assert(game.weapon_id == 1 and game.ammo == 6 and game.reserve == 7 and game.ticks == tick_before)
	assert(crate.weapon_id == 0 and crate.ammo == 7 and game.carried_ammo[0] == 24, "Swap leaves actual previous gun and magazine, preserving separate ammo")
	game.carried_ammo[1] = 0
	game.ammo = 0
	assert(not game.can_reload(), "Pistol rounds cannot reload a rifle")
	game.apply_loot(0, "Crate", 2)
	assert(game.carried_ammo[2] == 7 and game.reserve == 0 and not game.can_reload())
	game.apply_loot(0, "Crate", 1)
	game.reload_weapon()
	assert(game.ammo == 7 and game.reserve == 0 and game.carried_ammo[0] == 24 and game.carried_ammo[2] == 7)
	# Recover the old pistol, then exchange back: neither gun nor ammo is duplicated.
	game.offer_gun(crate)
	game.take_found_gun()
	assert(game.weapon_id == 0 and game.ammo == 7 and game.reserve == 24 and crate.weapon_id == 1 and crate.ammo == 7)
	game.offer_gun(crate)
	game.take_found_gun()
	assert(game.weapon_id == 1 and game.ammo == 7 and crate.weapon_id == 0 and crate.ammo == 7)
	# Enemy loot has the enemy's exact gun, loaded rounds, and matching loose ammo.
	game.enemies.append({"pos": Vector2i(3, 1), "hp": 0, "weapon_id": 4, "ammo_type": 4, "ammo": 9, "reserve": 11, "loot_kind": 1, "gun_available": true, "searched": false})
	game.search_body(0)
	assert(game.carried_ammo[4] == 11 and game.enemies[0].reserve == 0 and game.gun_dialog.visible and game.weapon_id == 1)
	game.decline_gun()
	var body_tick = game.ticks
	game.search_body(0)
	assert(game.ticks == body_tick and game.carried_ammo[4] == 11, "Body gun can be revisited without looting ammo twice")
	game.gun_dialog.confirmed.emit()
	assert(game.weapon_id == 4 and game.ammo == 9 and game.reserve == 11 and game.enemies[0].weapon_id == 1 and game.enemies[0].ammo == 7)
	game.show_inventory()
	assert("9mm (PISTOL): 24 spare" in game.inventory_dialog.dialog_text and ".45 (SMG): 11 spare" in game.inventory_dialog.dialog_text)
	game.inventory_dialog.hide()
	# A real enemy uses finite ammo, matching weapon accuracy/damage/AP and reloads.
	for weapon in range(5):
		game.enemies.clear()
		game.player = Vector2i(1, 1)
		var enemy = {"pos": Vector2i(2, 1), "hp": 1000, "facing": Vector2i.LEFT, "weapon_id": weapon, "ammo_type": weapon, "ammo": 2, "reserve": 0}
		game.enemies.append(enemy)
		game.hp = 100
		game.combat = true
		game.bleeding = false
		game.bleed_rng.seed = safe_bleed_seed()
		game.rng.seed = 1
		game.enemy_turn()
		var fired = 1 if weapon in [2, 3] else 2
		assert(enemy.ammo == 2 - fired)
		enemy.ammo = 0
		enemy.reserve = 0
		var health_before = game.hp
		game.enemy_turn()
		assert(game.hp == health_before and enemy.ammo == 0, "Empty enemy guns with no ammo cannot fire")
		enemy.reserve = 3
		game.enemy_turn()
		assert(enemy.ammo == 3 and enemy.reserve == 0 and game.hp == health_before, "Enemy reload uses both actions and matching reserve")
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.hp = 100
	game.combat = true
	game.bleeding = false
	var short_range_enemy = {"pos": Vector2i(8, 1), "hp": 1000, "facing": Vector2i.LEFT, "weapon_id": 2, "ammo_type": 2, "ammo": 6, "reserve": 0, "alerted": false}
	game.enemies.append(short_range_enemy)
	game.enemy_turn()
	assert(short_range_enemy.alerted and short_range_enemy.pos == Vector2i(7, 1) and short_range_enemy.ammo == 6 and game.hp == 100, "Visible out-of-range guards must investigate without firing beyond gun range")
	# Save gun and every ammo pool on extraction, then deserialize into next raid.
	game.enemies.clear()
	game.combat = false
	game.weapon_id = 4
	game.ammo = 9
	game.carried_ammo.assign([24, 7, 3, 2, 11])
	game.player = game.exfil
	game.objective_collected = true
	var bank_before = game.stash
	game.extract()
	assert(game.finished and game.saved_gear.weapon_id == 4 and game.saved_gear.ammo == 9)
	game.load_stash()
	game.new_raid()
	assert(game.weapon_id == 4 and game.ammo == 9 and game.carried_ammo == [24, 7, 3, 2, 11], "Extracted gear survives save/reload and next raid")
	var unextracted = {"pos": game.player, "weapon_id": 2, "ammo": 4, "gun_available": true}
	game.offer_gun(unextracted)
	game.take_found_gun()
	assert(game.weapon_id == 2)
	game.load_stash()
	game.new_raid()
	assert(game.weapon_id == 4 and game.ammo == 9 and game.carried_ammo == [24, 7, 3, 2, 11], "Reopening restores secured gear but discards unextracted pickups")
	game.hp = 1
	game.take_damage(1)
	assert(game.finished and game.saved_gear == game.default_gear())
	game.load_stash()
	game.new_raid()
	assert(game.weapon_id == 0 and game.ammo == 7 and game.carried_ammo == [24, 0, 0, 0, 0], "Death persistently loses gun and ammo")
	game.stash = bank_before
	game.save_stash(game.default_gear())
	assert(game.sanitize_gear({"weapon_id": 200, "ammo": -2, "carried_ammo": [1]}) == {"weapon_id": 4, "ammo": 0, "carried_ammo": [24, 0, 0, 0, 0]})
	print("PASS: pistol start, random crate/enemy guns and typed ammo, take/decline/revisit without duplication, old gun recovery, wrong-ammo reload refusal, matching corpse gun and ammo, finite enemy fire/reload/AP, inventory view, persistent extraction/next raid/death reset")
	return true

func test_animated_movement(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	var guard = {"pos": Vector2i(3, 2), "hp": 60, "facing": Vector2i.RIGHT}
	game.enemies.append(guard)
	game.animations_enabled = true
	# Finish the long synchronous mechanics checks before measuring a short tween.
	await process_frame
	await process_frame
	game.move_to(Vector2i(2, 1))
	assert(game.busy() and game.ticks == 1 and game.player_draw_pos == Vector2(1, 1))
	assert(guard.draw_pos == Vector2(3, 2) and guard.pos != Vector2i(3, 2), "Actors start the same tick from their original positions")
	var progress_ticks = game.ticks
	game.move_to(Vector2i(6, 1))
	game.enemy_turn()
	game.show_inventory()
	assert(game.ticks == progress_ticks and not game.inventory_dialog.visible, "Inputs cannot start another action during animation")
	await create_timer(0.02).timeout
	var player_fraction = game.player_draw_pos.distance_to(Vector2(1, 1))
	var enemy_fraction = Vector2(guard.draw_pos).distance_to(Vector2(3, 2))
	assert(player_fraction > 0 and player_fraction < 1 and absf(player_fraction - enemy_fraction) < 0.001, "Player and patrol interpolate concurrently")
	await create_timer(0.15).timeout
	assert(not game.busy() and game.player_draw_pos == Vector2(game.player) and guard.draw_pos == Vector2(guard.pos))
	var idle_ticks = game.ticks
	await create_timer(0.04).timeout
	assert(game.ticks == idle_ticks, "Finishing an animation does not advance another tick")
	game.enemies.clear()
	await game.move_to(Vector2i(5, 1))
	assert(game.player == Vector2i(5, 1) and game.ticks == 4, "Each animated path tile still costs exactly one tick")
	game.player = Vector2i(1, 1)
	game.enemies.append({"pos": Vector2i(7, 1), "hp": 60, "facing": Vector2i.LEFT})
	await game.move_to(Vector2i(5, 1))
	assert(game.combat and game.player == Vector2i(2, 1) and not game.busy(), "Spotting still interrupts animated travel immediately")
	game.enemies.clear()
	game.ap = 2
	await game.move_to(Vector2i(6, 1))
	assert(game.player == Vector2i(4, 1) and game.ap == 0 and not game.busy())
	game.enemies.append({"pos": Vector2i(30, 30), "hp": 60, "facing": Vector2i.RIGHT})
	await game.enemy_turn()
	assert(game.enemies[0].motion_path.size() == 3 and game.enemies[0].draw_pos == Vector2(game.enemies[0].pos), "Enemy phase preserves both tile steps instead of sliding diagonally")
	game.enemies.clear()
	game.combat = false
	game.move_to(Vector2i(7, 1))
	assert(game.busy())
	game.new_raid()
	var insertion = game.player
	await create_timer(0.15).timeout
	assert(game.player == insertion and game.ticks == 0 and not game.busy() and game.player_draw_pos == Vector2(insertion), "New Raid safely cancels pending motion and travel")
	game.animations_enabled = false
	print("PASS: concurrent player/patrol interpolation, action locking, exact path ticks/AP, frozen idle, animated contact interruption, enemy per-tile paths, raid restart cancellation")
	return true

func test_sight_and_zoom(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	var guard = {"pos": Vector2i(11, 1), "hp": 60, "facing": Vector2i.LEFT}
	game.enemies.append(guard)
	assert(game.player_can_see(Vector2i(11, 1)) and game.visible(guard) and game.enemy_can_see_player(guard))
	guard.pos = Vector2i(12, 1)
	assert(not game.player_can_see(guard.pos) and not game.visible(guard) and not game.enemy_can_see_player(guard), "Eleven tiles is outside sight")
	guard.pos = Vector2i(11, 1)
	game.combat = true
	game.selected = 0
	for weapon in [0, 1, 3, 4]:
		game.weapon_id = weapon
		game.ammo = 1
		game.ap = 4
		assert(game.can_fire(), "Long-range weapons can fire at ten tiles")
	var long_odds = [45, 55, 75, 40]
	for i in range(4):
		game.weapon_id = [0, 1, 3, 4][i]
		assert(game.shot_chance(guard.pos) == long_odds[i])
	game.weapon_id = 2
	assert(not game.can_fire())
	guard.pos = Vector2i(7, 1)
	assert(game.can_fire() and game.shot_chance(guard.pos) == 45)
	game.camera = Vector2(400, 400)
	var anchor = Vector2(100, 120)
	var world_before = game.camera + anchor / game.map_zoom
	var ticks_before = game.ticks
	var ap_before = game.ap
	game.set_map_zoom(0.5, anchor)
	assert((game.camera + anchor / game.map_zoom).distance_to(world_before) < 0.001)
	assert(game.map_view.size * game.map_view.scale == game.MAP_VIEW_SIZE)
	game.set_map_zoom(100)
	assert(game.map_zoom == 1.5 and game.zoom_in_button.disabled)
	game.set_map_zoom(0.01)
	assert(game.map_zoom == 0.5 and game.zoom_out_button.disabled)
	assert(game.ticks == ticks_before and game.ap == ap_before, "Zooming never spends game time or AP")
	game.set_map_zoom(1)
	game.player = Vector2i(1, 1)
	guard.pos = Vector2i(1, 11)
	game.focus_contact(guard)
	var view = Rect2(game.camera, game.map_visible_size())
	assert(view.has_point(Vector2(game.player) * game.CELL + Vector2(18, 18)) and view.has_point(Vector2(guard.pos) * game.CELL + Vector2(18, 18)), "Long-distance contact frames both actors")
	for zoom in [0.5, 1.5]:
		game.new_raid()
		game.enemies.clear()
		game.loot.clear()
		game.player = Vector2i(1, 1)
		game.set_map_zoom(zoom)
		game.camera = Vector2.ZERO
		var press = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = game.ORIGIN + (Vector2(2, 1) * game.CELL + Vector2(18, 18)) * zoom
		press.pressed = true
		game._gui_input(press)
		var release = press.duplicate()
		release.pressed = false
		game._gui_input(release)
		assert(game.player == Vector2i(2, 1) and game.ticks == 1, "Tile input must select the correct cell at either zoom limit")
	game.new_raid()
	assert(game.map_zoom == 1)
	print("PASS: ten-tile sight/detection boundary, weapon ranges and long-distance accuracy, shorter shotgun range, anchored zoom and limits, fixed clipped viewport, no tick/AP cost, contact framing, raid reset")
	return true

func test_enemy_ai(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	var target = {"pos": Vector2i(4, 1), "hp": 1000, "facing": Vector2i.RIGHT}
	var near = {"pos": Vector2i(13, 1), "hp": 60, "facing": Vector2i.RIGHT}
	var far = {"pos": Vector2i(14, 1), "hp": 60, "facing": Vector2i.RIGHT}
	game.enemies.assign([target, near, far])
	game.combat = true
	game.selected = 0
	game.shoot()
	assert(near.investigating and near.investigate_pos == game.player and not near.get("alerted", false))
	assert(not far.get("investigating", false), "Gunshots reach twelve Manhattan tiles, not thirteen")
	assert(target.alerted and not target.get("investigating", false), "Visual/engaged contact has priority over noise")
	game.new_raid()
	game.enemies.clear()
	game.player = Vector2i(40, 40)
	var investigator = {"pos": Vector2i(13, 4), "hp": 60, "facing": Vector2i.LEFT}
	game.enemies.append(investigator)
	assert(not game.line_of_sight(investigator.pos, Vector2i(15, 4)))
	game.hear_gunshot(Vector2i(15, 4))
	assert(investigator.investigating, "Walls block sight but do not silence nearby gunshots")
	var crossed_door = false
	for i in range(20):
		if not investigator.investigating:
			break
		game.world_tick()
		crossed_door = crossed_door or investigator.pos == Vector2i(14, 6)
		assert(game.walkable(investigator.pos))
	assert(crossed_door and not investigator.investigating and not investigator.get("alerted", false), "Investigations navigate the entrance, look around, and expire")
	var old_pos = investigator.pos
	game.world_tick()
	assert(investigator.pos != old_pos, "A finished search resumes patrol")
	investigator.pos = Vector2i(13, 4)
	game.begin_investigation(investigator, Vector2i(15, 4))
	investigator.investigate_remaining = 1
	game.set_tile(Vector2i(14, 6), "#")
	game.investigation_step(investigator)
	game.set_tile(Vector2i(14, 6), ".")
	assert(not investigator.investigating, "Unreachable noise cannot trap guards investigating forever")
	game.enemies.clear()
	var remembered = {"pos": Vector2i(11, 1), "hp": 60, "facing": Vector2i.RIGHT, "alerted": true, "last_seen": Vector2i(7, 1), "ammo": 7, "reserve": 0}
	game.enemies.append(remembered)
	game.combat = true
	game.enemy_turn()
	assert(not game.combat and remembered.investigating and remembered.investigate_pos == Vector2i(7, 1), "Breaking contact investigates remembered position without tracking the unseen player")
	# Enemy shots emit the same audible event as player shots.
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	var shooter = {"pos": Vector2i(2, 1), "hp": 1000, "facing": Vector2i.LEFT, "ammo": 7, "reserve": 0}
	var listener = {"pos": Vector2i(14, 1), "hp": 60, "facing": Vector2i.RIGHT}
	game.enemies.assign([shooter, listener])
	game.combat = true
	game.hp = 100
	game.bleeding = false
	game.bleed_rng.seed = safe_bleed_seed()
	game.enemy_turn()
	assert(listener.investigating and listener.investigate_pos == Vector2i(2, 1))
	# A patrol leg stays straight until its budget expires or an obstruction intervenes.
	game.enemies.clear()
	game.player = Vector2i(40, 40)
	var patrol = {"pos": Vector2i(1, 1), "hp": 60, "facing": Vector2i.RIGHT, "patrol_remaining": 3}
	game.enemies.append(patrol)
	for i in range(3):
		game.patrol_step(patrol)
		assert(patrol.pos == Vector2i(2 + i, 1) and patrol.facing == Vector2i.RIGHT)
	patrol.pos = Vector2i(2, 2)
	patrol.facing = Vector2i.RIGHT
	patrol.patrol_remaining = 5
	game.patrol_step(patrol)
	assert(game.walkable(patrol.pos) and patrol.facing in [Vector2i.UP, Vector2i.DOWN], "Blocked patrols turn without reversing when a side path exists")
	var chosen_headings = {}
	for seed_value in range(30):
		game.rng.seed = seed_value
		patrol.pos = Vector2i(10, 2)
		patrol.facing = Vector2i.RIGHT
		patrol.patrol_remaining = 0
		patrol.patrol_started = false
		game.patrol_step(patrol)
		chosen_headings[patrol.facing] = true
	assert(chosen_headings.size() > 1, "Patrol choices remain randomized")
	# Silent takedown uses one tick, leaves actual enemy gear, and creates no sound.
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	var unaware = {"pos": Vector2i(3, 1), "hp": 60, "facing": Vector2i.RIGHT, "weapon_id": 4, "ammo": 8, "reserve": 11, "gun_available": true, "patrol_remaining": 0, "patrol_started": true}
	var observer = {"pos": Vector2i(10, 1), "hp": 60, "facing": Vector2i.RIGHT, "patrol_remaining": 4}
	game.enemies.assign([unaware, observer])
	game.move_to(Vector2i(2, 1))
	assert(unaware.pos == Vector2i(3, 1) and unaware.patrol_pause and game.can_takedown(0), "Patrol pauses allow an undetected rear approach")
	var takedown_tick = game.ticks
	game.select_tile(unaware.pos)
	assert(not game.combat and game.selected == 0 and not game.takedown_button.disabled and game.can_fire(), "Selecting an unaware rear target offers either silent or firearm attack")
	var ammo_before = game.ammo
	game.takedown_button.pressed.emit()
	assert(unaware.hp == 0 and unaware.ammo == 8 and unaware.reserve == 11 and not unaware.searched)
	assert(game.ticks == takedown_tick + 1 and game.ammo == ammo_before and not game.combat and not observer.get("investigating", false))
	game.silent_takedown(0)
	assert(game.ticks == takedown_tick + 1, "A dead guard cannot be taken down twice")
	unaware.hp = 60
	unaware.alerted = false
	game.player = Vector2i(3, 2)
	assert(not game.can_takedown(0), "Side adjacency is not behind")
	game.player = Vector2i(2, 1)
	game.combat = true
	assert(not game.can_takedown(0))
	game.combat = false
	unaware.alerted = true
	assert(not game.can_takedown(0))
	unaware.alerted = false
	observer.pos = Vector2i(1, 1)
	observer.facing = Vector2i.RIGHT
	assert(not game.can_takedown(0), "Another watching guard prevents an undetected takedown")
	observer.hp = 0
	game.selected = 0
	game.ap = 0
	game.shoot()
	assert(game.combat and game.ap == 3 and game.ammo == ammo_before - 1, "Choosing Fire explicitly starts combat with normal shot costs")
	game.new_raid()
	print("PASS: player/enemy gunshot hearing and range, wall-independent sound, route-based investigation/search/expiry, unreachable timeout, remembered contact, straight randomized patrol legs and blocked turns, silent rear takedown cost/gear/noise, invalid takedowns")
	return true

func test_shot_meter(game) -> bool:
	game.new_raid()
	game.enemies.clear()
	game.loot.clear()
	game.player = Vector2i(1, 1)
	var target = {"pos": Vector2i(4, 1), "hp": 1000, "facing": Vector2i.RIGHT}
	game.enemies.append(target)
	game.selected = 0
	game.combat = true
	game.meter_rng.seed = 42
	game.begin_shot()
	assert(game.meter_active and game.meter_overlay.visible and game.busy())
	assert(game.ap == 4 and game.ammo == 7 and game.ticks == 0, "Preparing a shot spends nothing")
	var position_before = game.meter_position
	game.enemy_turn()
	game.move_to(Vector2i(2, 1))
	game.reload_weapon()
	game.choose_shot(1)
	assert(game.player == Vector2i(1, 1) and game.ticks == 0 and game.shot_mode == 0)
	await create_timer(0.03).timeout
	assert(game.meter_position != position_before and game.hp == 100 and game.ap == 4 and game.ammo == 7 and target.pos == Vector2i(4, 1), "Meter moves while the tactical world stays frozen")
	game.meter_position = game.meter_center
	var tap = InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	game.meter_input(tap)
	assert(not game.meter_active and not game.meter_overlay.visible and game.last_shot_modifier == 20 and game.last_shot_chance == 95)
	assert(game.ap == 3 and game.ammo == 6 and "GREEN timing" in game.message)
	game.resolve_shot_meter()
	assert(game.ap == 3 and game.ammo == 6, "A timing tap resolves only once")
	game.ap = 4
	game.begin_shot()
	game.meter_position = 0
	var key = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	game.meter_input(key)
	assert(game.last_shot_modifier == -25 and game.last_shot_chance == 55 and game.ap == 3 and game.ammo == 5)
	game.ap = 4
	game.begin_shot()
	game.meter_position = game.meter_center + game.meter_width / 2 + 0.05
	game.resolve_shot_meter()
	assert(game.last_shot_modifier == 0 and game.last_shot_chance == 80)
	var settings = {}
	for i in range(12):
		game.ap = 4
		game.ammo = 7
		game.begin_shot()
		settings[str([game.meter_speed, game.meter_center, game.meter_width, game.meter_phase])] = true
		assert(game.meter_speed >= 1.3 and game.meter_speed <= 2.0 and game.meter_width >= 0.10 and game.meter_width <= 0.14)
		game.meter_position = game.meter_center
		game.resolve_shot_meter()
	assert(settings.size() == 12, "Each shot receives varied meter timing")
	target.hp = 1000
	game.ap = 4
	game.ammo = 7
	game.choose_shot(2)
	game.rng.seed = 42
	var rolls = RandomNumberGenerator.new()
	rolls.seed = 42
	var rounds = rolls.randi_range(2, 3)
	var hits = 0
	for i in range(rounds):
		if rolls.randi_range(1, 100) <= 85:
			hits += 1
	game.begin_shot()
	game.meter_position = game.meter_center
	game.resolve_shot_meter()
	assert(game.last_shot_chance == 85 and game.ap == 2 and game.ammo == 7 - rounds and target.hp == 1000 - hits * 35, "One meter modifier applies to every burst round with normal ammo/AP costs")
	game.choose_shot(0)
	game.ap = 4
	game.ammo = 7
	game.begin_shot()
	target.pos = Vector2i(20, 1)
	game.resolve_shot_meter()
	assert(game.ammo == 7 and game.ap == 4 and not game.meter_active, "Invalidated targets do not spend shot costs")
	target.pos = Vector2i(4, 1)
	game.selected = 0
	game.ammo = 0
	game.begin_shot()
	assert(not game.meter_active, "Empty guns cannot start timing")
	game.ammo = 7
	game.begin_shot()
	assert(game.meter_active)
	game.new_raid()
	game.resolve_shot_meter()
	assert(not game.meter_active and not game.meter_overlay.visible and game.ticks == 0 and game.ap == 4)
	print("PASS: moving randomized shot meter, frozen world and locked input, green/yellow/red accuracy modifiers and caps, mouse/keyboard commit, single-resolution ammo/AP costs, whole-burst modifier, invalid targets/empty guns, raid reset")
	return true
