# TDExtract

Godot 4.6.3 prototype of a touch-first, grid-based military extraction game.
Inspired by Mini DAYZ, Shattered Pixel Dungeon, Tarkov's raid stakes, and XCOM's action economy. No borrowed assets. The fixed map is 24×24 with three single-entrance buildings; each raid randomizes your outdoor insertion and extraction within the two-tile edge band, six patrols, and four loot crates (three indoors and one outdoors).

## Play

Open `project.godot` in Godot 4.6.3 and press F6/F5, or run `godot --path .`.

- Drag with touch or the left mouse button to pan the map without advancing time. Mouse wheel scrolls vertically; Shift + wheel scrolls horizontally. Center returns to the operator; Objective only centers on a pickup currently in sight. After collecting it, the button becomes Exfil and locates extraction from anywhere.
- Tap/click a reachable tile to travel along its shortest path. Every tile costs one world tick. The world stays still while you decide.
- Blue is your operator, gold is supply crates, green is extraction. Each crate randomly contains ammo (seven reserve rounds), health (up to 25 HP), ammo and health together, a bandage, or all three, plus one supply. Every raid has at least one crate containing a bandage. Crates are shown only within six tiles and clear line of sight. Unopened crates all look identical; contents are revealed only on pickup. Enemies appear within six tiles and line of sight. They detect you only inside a 90-degree forward cone in their arrow direction; patrol steps turn them toward their movement.
- Contact interrupts movement immediately. A guard that has spotted you holds position, becomes selected, and the map frames both you and that guard. Each combat turn starts with four action points; unused AP is discarded when you end your turn: moving one tile costs one AP; firing costs one or two AP depending on the weapon; burst costs two AP. Tap a hostile to select it and see its hit chance; press Fire to commit the shot. The pistol holds seven rounds; other weapons have their own magazine sizes. You start with a full magazine and 24 spare rounds. The HUD shows Gun (loaded rounds), Ammo (carried spare rounds), and Total (both combined). Reloading costs one world tick during exploration, or two AP in combat. A partial reload uses only the rounds you have; a full gun or empty reserve spends no time.
- End Turn grants living enemies two actions each. Solid gray walls block movement and line of sight. Striped waist-high barriers block movement but allow vision and fire. A floor-tile gap separates every low barrier from full walls, including diagonally. Standing directly beside a low barrier automatically grants cover against shots coming from that side: incoming hit odds lose 25 percentage points. Standing beside an exposed full-wall corner also automatically grants the same 25-point defensive bonus against incoming shots around that corner, with automatic peeking from the adjoining open tile. Players and enemies can see and fire around the corner without moving or spending extra AP; peeking also lets enemies fire back at the exposed position. Flat wall faces and obstructed openings still block vision and shots, and firing around your own corner carries no accuracy penalty. Side/rear attacks flank cover. Shooting over your own cover never reduces your accuracy; only the target’s cover and range affect the shot. Eliminating the last engaged enemy immediately resumes exploration without an extra enemy turn. Distant unengaged patrols do not keep combat active. A fresh engagement starts with four AP. Break contact to resume exploration.
- First collect the purple objective, which spawns at least eight Manhattan tiles from your insertion on a reachable floor tile inside a building. It is shown only within six tiles and line of sight. Extraction stays hidden until the pickup, then is revealed globally. Then stand on the extraction tile and press Extract to bank your cargo. Death loses raid cargo. Banked supplies persist locally (`user://stash.json`); a new raid resets health and ammunition.

Defeated enemies leave an X-shaped body. Stand on or beside it and tap it or press Search. Searching costs one world tick in exploration or one AP and one tick in combat, grants hidden randomized ammo/health/bandage loot, and can only be done once. In exploration, patrols advance during the search.

This is an initial mechanics prototype, with abstract tactical symbols rather than final pixel art. Armor, sound, multiple maps, weapon pickups, and a full stash/loadout economy are future work. Player weapon choice is currently a pre-raid selector; enemies retain their existing attacks. Enemy AI uses simple patrols and greedy pursuit. No real-time simulation or procedural map generation.

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

The integration check exercises ammo tracking, partial reloads, reload tick/AP costs, crate ammo pickup, real scene initialization, placement uniqueness, idle freeze, movement ticks, loot pickup, travel interruption, action points, enemy turns, range/cover/LOS, firing, and extraction. It restores the existing bank after testing.

A browser input check is available as `node tests/browser.cjs` with Playwright and Chromium installed and the HTTP server running. It tests both mouse and emulated touch startup/input and verifies the rendered world stays frozen while idle. See `DESIGN.md` for the product direction and planned increments.

## GitHub downloads and hosting

The `Build and publish web game` Actions workflow builds and tests on pushes to `main`. Its build artifact contains `TDExtract-web.zip` (artifact downloads require a GitHub login).

To create a regular GitHub download, manually run the workflow with **Publish a downloadable web build** selected. It creates a prerelease with the ZIP attached. For a public repository, the release asset is downloadable without a GitHub login.

To host a playable browser build, set **Settings → Pages → Source → GitHub Actions**, then manually run the workflow with **Publish the playable website** selected. The deployment reports the actual website URL after success. Downloads and hosting can be selected independently. Selected publications become available after the workflow run succeeds.

## Combat options

Select a weapon using the top-left dropdown before your first action. The choice locks for the raid once you move, enter combat, reload, search, or bandage; New Raid unlocks it again and keeps the selected weapon. Ammo pickups currently replenish a shared spare-round pool for the equipped weapon.

Select Body, Head, or Burst, then tap an enemy and Fire. The displayed hit chance includes range, target cover, shot mode, and Aim.

| Weapon | Magazine | Body damage | Body/Head AP | Range (tiles) | Accuracy before cover/Aim | Burst |
| --- | --- | --- | --- | --- | --- | --- |
| Pistol | 7 | 35 | 1 | 6 | 95 − 8 per tile | Yes |
| Rifle | 20 | 40 | 1 | 6 | 95 − 6 per tile | Yes |
| Shotgun | 6 | 55 | 2 | 4 | 105 − 15 per tile | No |
| Sniper | 5 | 65 | 2 | 6 | 95 − 3 per tile | No |
| SMG | 25 | 24 | 1 | 6 | 100 − 10 per tile | Yes |

Body uses the weapon's base damage and accuracy. Head deals approximately 1.71× damage with −20 accuracy points. Burst uses base damage per round, −15 accuracy points per round, and costs two AP. Pistol burst represents rapid successive shots. Shotgun is a single abstract close-range hit, not separately simulated pellets. Sniper retains the current six-tile sight limit, with better accuracy at longer visible distances. These are initial tuning values.

Burst independently rolls each round, requires at least two loaded rounds, and fires two if only two remain. Aim costs one AP and adds 30 accuracy points (maximum 95%) to every attack, including all burst rounds. It stays active through firing and ending turns, and only moving or taking damage cancels it. Repeated Aim does not stack. Ending a turn without acting still lets enemies act; unused AP does not carry over. Enemies still get two actions each.

## Bleeding and bandages

Each damaging hit has a 15% chance to start bleeding. Misses cannot cause bleeding, and the status does not stack. Bleeding removes three HP per exploration tick (including each tile moved, reloading, and body searches), or once at the end of the enemy phase in combat. Combat AP actions do not each cause additional bleeding damage. Nothing advances while idle. Bleeding damage cancels Aim and can kill the operator; travel stops immediately on death.

You start each raid with one bandage. Crates and searchable bodies can provide more; their contents remain hidden until looted. The Bandage button displays the carried count and is enabled only when bleeding, alive, and able to pay the action cost. Using one stops bleeding, restores no HP, and costs one world tick outside combat or one AP in combat. Outside combat, patrols still advance during treatment. Healing pickups restore HP but never stop bleeding. A new raid resets bleeding and bandages.
