# Field Operations: design direction

## Identity

A persistent, military extraction game for Android. Raid stakes come from what the operator carries in and successfully brings out. The current location is 24×24 with three buildings, each with one entrance. Insertion and extraction use outdoor floor tiles in the two-tile band along the map edge, separated by at least eight tiles. Loot markers require current player sight and cannot be revealed by camera panning. Maps are authored locations, not procedural dungeon floors. Decisions are deliberate: time advances through actions rather than reflexes.

## Raid loop

Prepare a loadout from the stash → insert at a randomized location → scout and scavenge → survive or avoid engagements → reach a randomized extraction point → bank the recovered equipment. Dying loses the deployed equipment and unextracted cargo. Future raids return to the same geography so players learn sightlines, routes, and cover positions.

The first prototype has one fixed location, random insertion/extraction/patrols/crates, local banked supply counts, and death losing cargo. Loadout selection and individual items remain to be implemented.

## Simulation contract

Exploration has no real-time updates. Reloading advances the world one tick, just like a movement step. A tile tap finds a path; each traversed tile advances the simulation one tick, including one patrol action per living enemy. Detection interrupts the path at the first contact tick. Animation should eventually present these committed ticks without changing the underlying rules. Ticks count movement, exploration reloads, body searches, and completed enemy turns. Combat movement and searches consume AP without advancing patrols; enemy actions occur in the enemy phase.

Combat starts with four AP; unused AP carry over with four added after the enemy phase, capped at eight. Moving a tile or firing a single shot costs one AP; burst costs two AP; reloading costs two AP. The gun holds seven rounds, reserve ammo is tracked separately, and crates replenish the reserve by seven rounds. Enemies have two actions each. Shots use range, full-wall line-of-sight blocking, and directional low cover to derive a displayed probability. Waist-high barriers block movement but allow sight and fire. Adjacent defenders receive an automatic 25-point incoming hit-chance penalty from the covered direction; a shooter’s own cover carries no accuracy cost. Three of the four crates spawn indoors, one outdoors. Defeated enemies leave searchable bodies that cost one tick to search (also one AP in combat). Low cover always has a floor gap from full walls, including diagonals. Four loot crates per raid contain randomized ammo, health, or both, hidden until pickup. Healing restores up to 25 HP immediately, capped at 100. A distant purple objective (minimum eight Manhattan tiles from insertion) spawns inside a building and is required before extraction. Its marker and navigation are available only within player sight. Extraction is hidden until pickup, then globally revealed. Enemies have cardinal facing with a 90-degree forward detection cone, follow their patrol movement direction, and investigate the last known player location when alerted. When no living enemy remains in sight after an enemy phase, exploration resumes. A future version should retain enemy awareness and use a deliberate disengagement threshold.

## Touch controls

Portrait-first layout. Tap terrain to move; tap a visible enemy to select it; use a separate Fire button to confirm a shot. Keep mode-adjusted hit odds visible before committing ammunition or AP. Normal/head/body attacks cost one AP with damage/accuracy tradeoffs; burst costs two AP and independently rolls two to three rounds. Aim costs one AP for a 30-point bonus on the next attack, survives turns, and cancels on movement or incoming damage. Buttons for reloading, ending the turn, and extraction remain accessible below the map. A mouse follows exactly the same control path.

Touch dragging and mouse scrolling pan a clipped map view without advancing simulation. Center and Objective navigation buttons are available. A production map should also support zooming, a movement preview and confirmation, reachable-tile/AP overlays, and a forgiving target selection hit area. Distinct shapes and labels should supplement color markers for accessibility. Final pixel art should use original assets.

## Next increments

1. Separate the deterministic raid model from rendering; add saved raid state and stronger pathfinding/AI checks.
2. Add movement previews, facing-aware cover indicators, explicit enemy awareness, and feedback for each enemy action.
3. Implement stash inventory, deployable equipment, weapon/ammo definitions, armor, and extraction conditions.
4. Expand the authored map with terrain types, door interactions, and randomized loot tables.
5. Validate real Android devices and browser persistence; add original sprites, sound, and animation.
