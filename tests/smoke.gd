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
	assert(game.enemies.size() == 3 and game.loot.size() == 7)
	var cells = [game.player, game.exfil]
	for e in game.enemies:
		assert(game.walkable(e.pos) and not cells.has(e.pos))
		cells.append(e.pos)
	for p in game.loot:
		assert(game.walkable(p) and not cells.has(p))
		cells.append(p)
	var before = game.ticks
	await process_frame
	await process_frame
	assert(game.ticks == before, "Idle world must not advance")
	game.enemies.clear()
	game.player = Vector2i(1, 1)
	game.loot.clear()
	game.loot.append(Vector2i(2, 1))
	game.move_to(Vector2i(5, 1))
	assert(game.ticks == before + 4)
	assert(game.cargo == 1)
	assert(game.player == Vector2i(5, 1))
	game.enemies.append({"pos": Vector2i(7, 1), "hp": 60})
	game.combat = false
	game.player = Vector2i(1, 1)
	game.move_to(Vector2i(5, 1))
	assert(game.combat and game.player == Vector2i(2, 1), "Contact must interrupt travel")
	game.move_to(Vector2i(4, 1))
	assert(game.ap == 0)
	game.move_to(Vector2i(5, 1))
	assert(game.player == Vector2i(4, 1))
	game.enemy_turn()
	assert(game.ap == 2)
	assert(game.hit_chance(Vector2i(2, 1), Vector2i(4, 1)) > game.hit_chance(Vector2i(1, 1), Vector2i(7, 1)))
	assert(not game.line_of_sight(Vector2i(2, 3), Vector2i(5, 3)))
	assert(game.cover_at(Vector2i(2, 3), Vector2i(5, 3)))
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
	assert(game.ticks == 1 and game.ap == 2)
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
	assert(game.combat and game.ap == 2 and game.ticks == 3, "Contact during exploration reload must not charge combat AP")
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
	game.loot.append(Vector2i(2, 1))
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
