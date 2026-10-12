# Field Operations: design direction

## Identity

A persistent, military extraction game for Android. Raid stakes come from what the operator carries in and successfully brings out. Maps are authored locations, not procedural dungeon floors. Decisions are deliberate: time advances through actions rather than reflexes.

## Raid loop

Prepare a loadout from the stash → insert at a randomized location → scout and scavenge → survive or avoid engagements → reach a randomized extraction point → bank the recovered equipment. Dying loses the deployed equipment and unextracted cargo. Future raids return to the same geography so players learn sightlines, routes, and cover positions.

The first prototype has one fixed location, random insertion/extraction/patrols/crates, local banked supply counts, and death losing cargo. Loadout selection and individual items remain to be implemented.

## Simulation contract

Exploration has no real-time updates. A tile tap finds a path; each traversed tile advances the simulation one tick, including one patrol action per living enemy. Detection interrupts the path at the first contact tick. Animation should eventually present these committed ticks without changing the underlying rules. Tick count currently measures exploration steps plus completed enemy turns; combat movement consumes AP without advancing patrols.

Combat gives the player two AP before the enemy phase. Moving a tile, firing, or reloading costs one AP. Enemies have two actions each. Shots use range, line of sight, and directional wall cover to derive a displayed probability. When no living enemy remains in sight after an enemy phase, exploration resumes. A future version should retain enemy awareness and use a deliberate disengagement threshold.

## Touch controls

Portrait-first layout. Tap terrain to move; tap a visible enemy to select it; use a separate Fire button to confirm a shot. Keep hit odds visible before committing ammunition or AP. Buttons for reloading, ending the turn, and extraction remain accessible below the map. A mouse follows exactly the same control path.

A production map should support camera panning/zooming, a movement preview and confirmation, reachable-tile/AP overlays, and a forgiving target selection hit area. Distinct shapes and labels should supplement color markers for accessibility. Final pixel art should use original assets.

## Next increments

1. Separate the deterministic raid model from rendering; add saved raid state and stronger pathfinding/AI checks.
2. Add movement previews, facing-aware cover indicators, explicit enemy awareness, and feedback for each enemy action.
3. Implement stash inventory, deployable equipment, weapon/ammo definitions, armor, and extraction conditions.
4. Expand the authored map with terrain types, door interactions, and randomized loot tables.
5. Validate real Android devices and browser persistence; add original sprites, sound, and animation.
