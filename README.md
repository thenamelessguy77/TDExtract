# TDExtract

Godot 4.6.3 prototype of a touch-first, grid-based military extraction game.
Inspired by Mini DAYZ, Shattered Pixel Dungeon, Tarkov's raid stakes, and XCOM's action economy. No borrowed assets. The fixed map is 48×48, arranged as four districts with 12 single-entrance buildings. Each raid randomizes outdoor insertion and extraction within the two-tile edge band, 24 patrols, and 16 loot crates (12 indoors and four outdoors). Every district starts with six guards and four crates, with randomized positions. Drag to explore the full map; use the wheel or −/+ buttons to zoom.

## Play

Open `project.godot` in Godot 4.6.3 and press F6/F5, or run `godot --path .`.

- Drag with touch or the left mouse button to pan the map without advancing time. Mouse wheel zooms around the pointer; −/+ map buttons zoom around the map center on touch or desktop (50%–150%). Zooming spends no ticks or AP. Center returns to the operator; Objective only centers on a pickup currently in sight. After collecting it, the button becomes Exfil and locates extraction from anywhere.
- Tap/click a reachable tile to travel along its shortest path. Every tile costs one world tick. Player and patrol movement animate together at about 0.09 seconds per tile; travel stops on contact, loot choices, or exhausted AP. Enemy turns also animate their actual tile paths. Gameplay actions are locked while actors move; New Raid cancels travel safely. The world stays still while you decide.
- Blue is your operator, gold is supply crates, green is extraction. Each crate contains exactly one random item category, with equal chances: a gun, seven rounds of one ammo type, a health kit, or a bandage. Gun crates contain one rifle, shotgun, sniper, or SMG with its loaded magazine, without bonus spare ammo or medical items. Crates are shown only within ten tiles and clear line of sight. Unopened crates all look identical; contents are revealed only on pickup. Enemies appear within ten tiles and line of sight. They detect you only inside a 90-degree forward cone in their arrow direction; patrol steps turn them toward their movement.
- Contact interrupts movement immediately. A guard that has spotted you holds position, becomes selected, and the map frames both you and that guard. Each combat turn starts with four action points; unused AP is discarded when you end your turn: moving one tile costs one AP; firing costs one or two AP depending on the weapon; burst costs two AP. Tap a hostile to select it and see its hit chance; press Fire to commit the shot. The pistol holds seven rounds; other weapons have their own magazine sizes. A fresh operator starts with a seven-round pistol and 24 spare 9mm rounds. Extraction carries your equipped gun, its loaded rounds, and all carried ammo pools into the next run. The HUD shows Gun (loaded rounds), Ammo (matching spare rounds and type), and Total (all carried rounds, including the equipped magazine). Open Inventory to see the gun, loaded rounds, every carried ammo pool, health kits, and bandages. Reloading costs one world tick during exploration, or two AP in combat. A partial reload uses only the rounds you have; a full gun or empty reserve spends no time.
- End Turn grants living enemies two actions each. Solid gray walls block movement and line of sight. Striped waist-high barriers block movement but allow vision and fire. A floor-tile gap separates every low barrier from full walls, including diagonally. Standing directly beside a low barrier automatically grants cover against shots coming from that side: incoming hit odds lose 25 percentage points. Standing beside an exposed full-wall corner also automatically grants the same 25-point defensive bonus against incoming shots around that corner, with automatic peeking from the adjoining open tile. Players and enemies can see and fire around the corner without moving or spending extra AP; peeking also lets enemies fire back at the exposed position. Flat wall faces and obstructed openings still block vision and shots, and firing around your own corner carries no accuracy penalty. Side/rear attacks flank cover. Shooting over your own cover never reduces your accuracy; only the target’s cover and range affect the shot. Eliminating the last engaged enemy immediately resumes exploration without an extra enemy turn. Distant unengaged patrols do not keep combat active. A fresh engagement starts with four AP. Break contact to resume exploration.
- First collect the purple objective, which spawns at least sixteen Manhattan tiles from your insertion on a reachable floor tile inside a building. It is shown only within ten tiles and line of sight. Extraction stays hidden until the pickup, then is revealed globally. Then stand on the extraction tile and press Extract to bank your cargo. Death loses raid cargo. Banked supplies persist locally (`user://stash.json`); a new raid resets health and ammunition.

Defeated enemies leave an X-shaped body. Stand on or beside it and tap it or press Search. Searching costs one world tick in exploration or one AP and one tick in combat, grants hidden medical/supply loot and the enemy's remaining loose ammo, and can only award those items once. You may also choose to take the enemy's gun with the rounds still loaded in it. In exploration, patrols advance during the search.

This is an initial mechanics prototype, with abstract tactical symbols rather than final pixel art. Armor, sound, multiple maps, multiple carried guns, and a full stash/loadout economy are future work. Guns are now found during raids, and enemy attacks use their equipped weapon's accuracy, range, AP cost, and finite matching ammo. Enemy damage is scaled to one third of the weapon's body damage to retain the prototype's existing pistol threat level. Enemy AI uses randomized straight patrol legs, gunshot investigations, and pathfinding to remembered positions. No real-time simulation or procedural map generation.

## Web testing

Install matching Godot 4.6.3 export templates, then:

```sh
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server 8000 --directory build/web
```

Open the served build in a browser. Do not open the HTML directly from disk. The Web preset uses the compatibility renderer and disables threads, so COOP/COEP headers are unnecessary. Local browser persistence is origin-specific; clearing browser data clears the bank. Portrait layout scales from 480×800; mouse clicks and touch share the same input path.

In this cloud environment, run `bash scripts/setup.sh` to verify the Godot version, install checksum-verified web templates, run the integration check, and export. The template download is about 1.2 GB; only the web templates are retained.

For this cloud environment, use the exported XDG paths in `scripts/environment.sh` so Godot's caches and save data live in writable workspace directories.

## Android

The project uses Godot's compatibility renderer, portrait orientation, and touch-to-mouse emulation. To produce an APK/AAB, install matching export templates, OpenJDK 17, and the Android SDK through Godot's documented Android export setup. Add an Android export preset, set its package identifier, configure SDK/JDK paths, and configure your signing key securely. Android export and on-device validation have not been performed in this environment. Do not commit keystores or passwords.

## Validation

```sh
# Fail-safe timeout also catches any assertion/script failure that leaves the runner open.
timeout 20 godot --headless --path . --script res://tests/smoke.gd
```

The integration check exercises ammo tracking, partial reloads, reload tick/AP costs, crate ammo pickup, real scene initialization, placement uniqueness, idle freeze, movement ticks, loot pickup, travel interruption, action points, enemy turns, range/cover/LOS, firing, and extraction. It restores the entire existing save, including gun and ammo, after testing.

A browser input check is available as `node tests/browser.cjs` with Playwright and Chromium installed and the HTTP server running. It tests both mouse and emulated touch startup/input and verifies the rendered world stays frozen while idle. See `DESIGN.md` for the product direction and planned increments.

## GitHub downloads and hosting

The `Build and publish web game` Actions workflow builds and tests on pushes to `main`. Its build artifact contains `TDExtract-web.zip` (artifact downloads require a GitHub login).

To create a regular GitHub download, manually run the workflow with **Publish a downloadable web build** selected. It creates a prerelease with the ZIP attached. For a public repository, the release asset is downloadable without a GitHub login.

To host a playable browser build, set **Settings → Pages → Source → GitHub Actions**, then manually run the workflow with **Publish the playable website** selected. The deployment reports the actual website URL after success. Downloads and hosting can be selected independently. Selected publications become available after the workflow run succeeds.

## Combat options

A fresh operator starts with a pistol. Stepping onto a crate reveals its hidden supplies and any gun; searching a body costs one tick outside combat or one AP in combat. A found gun opens a Take Gun / Keep Current choice, interrupting travel. Taking it is part of the paid loot action: it preserves the found gun's actual loaded rounds and leaves your old gun and magazine in that container. Keeping your gun leaves the found weapon available. Tap a revealed nearby crate or search the body again to revisit the gun choice; supplies and loose ammo cannot be collected twice.

Each weapon has its own ammo pool: pistol 9mm, rifle 5.56, shotgun 12GA, sniper 7.62, and SMG .45. Ammo crates have random ammo types, and each crate has only one item category. Collected rounds of all types remain carried when you swap guns, but reloading consumes only the equipped gun's type. Enemy bodies supply matching loose ammo; taking the enemy gun also takes the rounds remaining in its magazine. Enemies expend loaded rounds, cannot shoot when empty, and spend both actions to reload from their finite spare ammo.

Extraction saves the equipped gun, magazine, and all five spare-ammo pools locally for the next raid, including after reopening the game. Death resets the next loadout to a pistol with seven loaded and 24 spare 9mm rounds. Starting a new raid or reopening the game discards unextracted pickups and returns to the last secured loadout; only extraction updates that loadout, and death clears it. Health, health kits, and bandages reset each run; banked supplies remain safe.

Select Body, Head, or Burst, then tap an enemy and Fire. The displayed hit chance includes range, target cover, shot mode, and Aim.

| Weapon | Magazine | Body damage | Body/Head AP | Range (tiles) | Accuracy before cover/Aim | Burst |
| --- | --- | --- | --- | --- | --- | --- |
| Pistol | 7 | 35 | 1 | 10 | 95 − 5 per tile | Yes |
| Rifle | 20 | 40 | 1 | 10 | 95 − 4 per tile | Yes |
| Shotgun | 6 | 55 | 2 | 6 | 105 − 10 per tile | No |
| Sniper | 5 | 65 | 2 | 10 | 95 − 2 per tile | No |
| SMG | 25 | 24 | 1 | 10 | 100 − 6 per tile | Yes |

Body uses the weapon's base damage and accuracy. Head deals approximately 1.71× damage with −20 accuracy points. Burst uses base damage per round, −15 accuracy points per round, and costs two AP. Pistol burst represents rapid successive shots. Shotgun is a single abstract close-range hit, not separately simulated pellets. Sight uses ten total Manhattan tiles for characters, crates, bodies, and objectives. Sniper maintains better accuracy at longer visible distances. Enemy shots use the same weapon distance curves. Contacts automatically zoom out when needed to fit both actors. These are initial tuning values.

Burst independently rolls each round, requires at least two loaded rounds, and fires two if only two remain. Aim costs one AP and adds 30 accuracy points (maximum 95%) to every attack, including all burst rounds. It stays active through firing and ending turns, and only moving or taking damage cancels it. Repeated Aim does not stack. Ending a turn without acting still lets enemies act; unused AP does not carry over. Enemies still get two actions each.

## Bleeding and bandages

Each damaging hit has a 15% chance to start bleeding. Misses cannot cause bleeding, and the status does not stack. Bleeding removes three HP per exploration tick (including each tile moved, reloading, and body searches), or once at the end of the enemy phase in combat. Combat AP actions do not each cause additional bleeding damage. Nothing advances while idle. Bleeding damage cancels Aim and can kill the operator; travel stops immediately on death.

You start each raid with one bandage. Crates and searchable bodies can provide more; their contents remain hidden until looted. The Bandage button displays the carried count and is enabled only when bleeding, alive, and able to pay the action cost. Using one stops bleeding, restores no HP, and costs one world tick outside combat or one AP in combat. Outside combat, patrols still advance during treatment. Health-kit pickups go into inventory without healing. Use Kit restores up to 25 HP for one world tick outside combat or one AP in combat; it never stops bleeding. Full health, no kit, death, or insufficient AP prevents use without wasting items or time. A new raid resets bleeding and bandages.

The Inventory button opens a modal window; viewing it costs no time or AP. Its Use Kit and Bandage controls spend the same one-tick/one-AP costs as their normal actions and refresh the displayed counts, health, and bleeding status. Health kits start at zero each raid, while one bandage is supplied.

## Guard awareness and stealth

All gunshots, including enemy fire, can be heard within twelve total Manhattan tiles. Sound does not require line of sight and crosses walls. A guard that has no confirmed visual contact investigates the latest heard position instead of knowing the player's current position. Investigating guards appear amber while visible. They pathfind around obstacles, look in four directions when close to the sound, and resume patrol if nothing is found. A 32-action budget also ends blocked or unreachable investigations. Breaking visual contact preserves a search of the last actually seen position; new sight takes priority over sound. Hearing alone does not start combat.

Patrols choose randomized three-to-six-tile legs, favor their current heading, pause briefly between legs, and turn when blocked. They avoid reversing when a forward or side route is available. Their paths are decided as the world advances, rather than following a fixed route.

To make a silent takedown, stand on the tile directly behind an unaware guard while outside combat, with no guard currently seeing you. Tap the guard to select it without starting combat when the takedown is available, then press the Takedown map button (or use it directly on a nearby eligible guard). Fire remains available if you prefer to initiate normal combat. Takedown kills for one world tick, uses no ammunition, emits no gunshot sound, and leaves the guard's actual gun and ammo on the body. Other patrols and bleeding still advance during that tick. Front/side approaches, alerted guards, combat, or another guard watching you prevent the takedown.
