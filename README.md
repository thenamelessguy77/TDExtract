# TDExtract

Godot 4.6.3 prototype of a touch-first, grid-based military extraction game.
Inspired by Mini DAYZ, Shattered Pixel Dungeon, Tarkov's raid stakes, and XCOM's action economy. No borrowed assets. The fixed map is 24×24 with three single-entrance buildings; each raid randomizes your insertion, extraction, three patrols, and four loot crates (three indoors and one outdoors).

## Play

Open `project.godot` in Godot 4.6.3 and press F6/F5, or run `godot --path .`.

- Drag with touch or the left mouse button to pan the map without advancing time. Mouse wheel scrolls vertically; Shift + wheel scrolls horizontally. Center returns to the operator; Objective centers on the pickup (or extraction once collected).
- Tap/click a reachable tile to travel along its shortest path. Every tile costs one world tick. The world stays still while you decide.
- Blue is your operator, gold is supply crates, green is extraction. Each crate randomly contains ammo (seven reserve rounds), health (up to 25 HP), or both, plus one supply. Unopened crates all look identical; contents are revealed only on pickup. Enemies appear within six tiles and line of sight. They detect you only inside a 90-degree forward cone in their arrow direction; patrol steps turn them toward their movement.
- Contact interrupts movement immediately. You get two action points per combat turn: moving one tile or firing costs one AP. Tap a hostile to select it and see its hit chance; press Fire to commit the shot. The gun holds seven rounds; you start with 24 reserve rounds. The HUD shows loaded rounds, reserve rounds, and total carried ammo (loaded + reserve). Reloading costs one world tick during exploration, or two AP in combat. A partial reload uses only the rounds you have; a full gun or empty reserve spends no time.
- End Turn grants living enemies two actions each. Solid gray walls block movement and line of sight. Striped waist-high barriers block movement but allow vision and fire. A floor-tile gap separates every low barrier from full walls, including diagonally. Standing directly beside a low barrier automatically grants cover against shots coming from that side: incoming hit odds lose 25 percentage points. Side/rear attacks flank cover. Shooting over your own cover never reduces your accuracy; only the target’s cover and range affect the shot. Break contact to resume exploration.
- First collect the purple objective, which spawns at least eight Manhattan tiles from your insertion on a reachable floor tile. Then stand on the extraction tile and press Extract to bank your cargo. Death loses raid cargo. Banked supplies persist locally (`user://stash.json`); a new raid resets health and ammunition.

Defeated enemies leave an X-shaped body. Stand on or beside it and tap it or press Search. Searching costs one world tick in exploration or one AP and one tick in combat, grants hidden randomized ammo/health loot, and can only be done once. In exploration, patrols advance during the search.

This is an initial mechanics prototype, with abstract tactical symbols rather than final pixel art. Equipment, weapon selection, armor, sound, multiple maps, and a full stash/loadout economy are future work. Enemy AI uses simple patrols and greedy pursuit. No real-time simulation or procedural map generation.

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
