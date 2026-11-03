# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Vision

An isolated, wind-swept coastal lighthouse that is both a sanctuary and a waystation. Transient soul-spirits — Warawara, in the sense of *The Boy and the Heron* — drift in carrying deficits of weight, hunger and instability. The caretaker shelters them, cooks for them, and sends them on. The subject is hospitality, emotional nourishment and passage, not throughput.

This game deliberately departs from frantic restaurant time-management. Where a design choice is ambiguous, resolve it toward the calmer option:

- **Intentional over frantic.** Don't add pressure mechanics that reward speed or punish hesitation. The player should be able to stop and look at the sea.
- **Coastal rhythm over a ticking clock.** Cadence comes from tides, weather and the lighthouse's own routine — not from order timers or a service rush.
- **Tactile over twitchy.** Cooking is physical and fully manual: cutting, steadying, turning the flame up and down, tasting. There are no minigames, button prompts, quality scores or recipe timers. See Cooking model.
- **Nourishment is visible on the body.** Feeding changes a spirit's luminescence, buoyancy and mass. State is read off the creature, not off a health bar.
- **Every spirit is passing through.** Ascension is the goal and the ending; keeping a spirit is not a win condition.

The loop: shelter and observe → forage → prepare → serve and elevate → retrofit the lighthouse, which opens new foraging zones and better equipment for needier spirits.

**Where the challenge comes from.** It comes from volatile coastal weather, not a service rush. Storms, fog and tides change what can be foraged, how troubled arriving spirits are and what they need. The player keeps the sanctuary running by adapting and using judgement, not by working faster. Demon waves with spirits fighting alongside the player were considered and set aside in favour of weather, because combat turns care into min-maxing and makes spirits something you keep and use.

**Ascension and the moon.** Every spirit that ascends joins a great, happy moon of Warawara that grows in the sky over the course of the game, so progress is something you see rather than a number. How well a spirit was fed decides how likely it is to reach the moon. A poorly fed spirit may fall during its ascension, and the caretaker is responsible for catching it. Letting a spirit die is the failure the player must not allow.

## Cooking model

Cooking is a physical simulation that stays close to real gastronomy, played in an outdoor kitchen on the cliff top beside the lighthouse. The caretaker is first-person: they walk about the cliff top, and step up to the counter to work, where the view becomes a fixed three-quarter look down at one station, panning between stations and glancing sideways when the mouse nears a screen edge. They stand still while working. The mouse is always locked: captured while walking, confined to the window at the counter.

- **Cutting** uses a mezzaluna, chosen as an echo of the moon. The player drags it with the mouse to make precise cuts, and holds a button to steady the food so it doesn't fall apart while making the perpendicular cut.
- **Heat is controlled directly.** The player sets the flame size and manages the temperature by hand. Nothing has a set recipe or time, including baking.
- **Doneness is judged by the player** from how the food looks, and by taste-testing it. Bite sounds come from the food's texture: a perfect French fry is crisp, and a poorly cooked dosa is squelchy.
- **Dishes are emergent.** The player combines any ingredients, equipment and real techniques, then names the result and chooses whether to put it up for service. For example, they chop a potato, discover that the oil press turns sunflower seeds into oil, fry the potato into fries, and improve them with chilli oil.
- **Bad food can still be served.** A poorly cooked or burnt dish is weaker and makes the spirit less likely to reach the moon. It is never thrown away as a failure.
- **Starting equipment** is an oil press, a gas stove and a pot. Hired help or automation for repetitive prep may come later but is not part of the core.
- **Oil is pressed by hand at first.** One crank turn presses 20g of seed, so a 200g shallow-fry of oil is about 29 turns. Automated presses arrive later as a lighthouse retrofit.
- **The pantry is unlimited for now.** Baskets never run out until foraging exists.

For the code, this means food is modelled as physical state that processes change over time: piece size and shape, moisture, core temperature, surface browning, fat, structure and flavour. Ingredient properties, equipment and ingredient-to-ingredient transformations (seeds to oil; oil and chilli to chilli oil) are authored as `.tres`. Finished dishes are never authored.

## Mission — how this gets built

Solo developer, methodical clean architecture, minimal viable loops, clever production trade-offs. The constraints matter more than they look:

- **Production-grade only.** No placeholders, no `# TODO: implement`, no stubbed state machines. If a system is too large for one pass, implement the complete foundational module rather than a thin slice of all of it.
- **Scope discipline is the job.** Prefer modular systems, parameter-driven variation and asset swapping over bespoke one-off content. A new spirit species, ingredient, piece of equipment, transformation or retrofit should be a new `.tres`, never new code. Dishes are never authored at all; they emerge from play. If something can only be built bespoke, say so before building it.
- **Architecture first.** Explicit state machines, decoupled signals, data-driven resources. Define states, transitions and terminal conditions before writing the code that implements them.
- **Modular, verifiable tasks.** Break systemic features into pieces small enough that each states its own pass/fail check.
- **No fluff.** Skip preamble and cheerleading; lead with the deliverable.

When delivering a system, work in this order:

1. **State and logic breakdown** — inputs, transitions, terminal conditions.
2. **Implementation** — self-contained typed scripts, data separated from controller logic.
3. **An explicit verification criterion** — the observable that proves it works.
4. **The next dependency** required to test the feature in-engine.

## Art direction

Stylized low-poly, cel-shaded, Ghibli-influenced, authored in Blender as modular kits so the asset budget stays bounded. Hand-painted or custom cel-shaded textures; variety comes from swapping meshes and shifting parameters across shared kits.

The spirit rendered in-game today is a procedurally built sphere with an emissive material — a stand-in, not a style target. Visual quality here has to come from authored assets; don't push the procedural placeholder further in code chasing a look it can't reach.

## Settled decisions

- **Godot 4 + GDScript**, not Unity 6 — lighter footprint, native Linux, faster solo iteration.
- Engine installed via pacman at `/usr/bin/godot`. The project lives on the Games partition because the home partition is nearly full.
- The spirit FSM is **flat, not hierarchical** — seven states with clean guard conditions didn't justify an HFSM. The per-state strategy classes are shaped so a hierarchy can be added later without touching the transition table or the event bus.

## Status and open questions

Phase 1 (spirit FSM, lighthouse progression) is complete and covered by the integration suite. The simulated 3D kitchen described in Cooking model is built section by section from `docs/kitchen_plan.md`. Done and covered by the suite:
- Sections 1–4, including 4.6: the crafting matrix is retired, and spirits are fed real plated food.
- All three checkpoints of Section 6.
- 7.1 plating and 7.2 naming.
- The mystical layer: essences, ecosystems, butchery, grains, spices and pot coverings.

None of the counter has been play-tested yet. The cut-piece kit and whole models for the new ingredients wait on assets. All sound is synthesised (`SoundSynth`) until recorded samples replace it. Section 5 waits on the open questions below, and 7.3 (what the service menu means for spirits) waits on the user. `FeedingResult` stays the only contract with the spirit FSM.

- **Patience is currently a real-time countdown** (`patience_seconds` 25s, then a 10s recovery window, then an `UNFED` outcome). This sits in tension with "coastal rhythm rather than a ticking clock." The loop has been played and approved as-is, so don't quietly re-time it — raise the question if the area comes up. Volatile weather is now the intended source of pressure, which strengthens the case for replacing the timer.
- **What happens to a spirit that falls and isn't caught.** The stated stake is "don't let them die"; the actual mechanic is undecided.
- **Whether falling is probabilistic or deterministic.** "Less likely to reach the moon" suggests chance. The alternative is a deterministic outcome the player can read off the spirit's body before it launches, which fits *Nourishment is visible on the body*.
- **How catching works.** A reflex catch would conflict with *Intentional over frantic*; a slow, readable fall would fit it.
- **Whether the moon grants collective abilities**, such as calming a storm or opening a foraging zone. This was suggested but not confirmed.
- **Whether the moon replaces kindled light** as the currency for retrofits or exists alongside it.

## Project

Lighthouse Spirits is a Godot 4.7 (Forward+) game written entirely in GDScript. A lighthouse caretaker cooks dishes for "Warawara" spirits. Fed spirits ascend and leave "kindled light", and the caretaker spends that light on lighthouse retrofits. The Godot binary is `/usr/bin/godot`, installed with pacman. The `godot` MCP server in `.mcp.json` points at the same binary.

## Commands

```sh
# Headless integration test (the only test suite). Exits 0 on pass, 1 on fail.
godot --headless --path . res://scenes/integration_test.tscn

# Required after adding or renaming any script with a `class_name`. Headless runs
# do not rebuild the global class cache, so without this every reference to the
# new type fails to parse.
godot --headless --editor --quit --path .

# Play the game (the main scene: the outdoor kitchen).
# Walking: WASD to walk, mouse to look, E at the counter to step in, Esc to
# free the mouse (click to take it back).
# At the counter: A/D along the counter (pass, board, stove, press), W/S to look
# out to sea and back, mouse to a screen edge to glance sideways, Esc to
# step back. Board: click a basket, drag across the board to cut (Space
# steadies), drag a piece to move it, right-click to roll it, Space + drag
# to lift it with everything touching it, T to taste. Stove: drag round the
# knob. Pot: drag to stir with the slotted spoon, drag out over the rim to
# lift, right-click a piece to turn it, right-click the pot to tip its liquid
# out; let a lifted sheet (hide, big leaf) go over the pot to cover it,
# press it to lift it off. Jug/bottle/cup: drag over the pot or the serving
# board to pour (right-click uncorks the bottle; hold Space with the cup
# over the pot to dip it). Pantry: click a shelf to take from it,
# right-click for the next ingredient; spices and grains are carried and
# let go over the pot, the board or the plate. The first stroke through a
# whole fish, bird or crab dresses it. Pass: N names the plated dish, M
# puts it on the menu. Press: click the sunflower head for seeds, drag
# round the crank.
godot --path .

# Model kit: rebuild (all, or the named models), validate against
# docs/models_needed.md, and render previews. A rebuild overwrites both
# models/<name>.blend and its .glb under assets/models/, so a model that has
# been hand-edited in Blender must not be rebuilt by name.
blender --background --factory-startup --python tools/blender/build_models.py [-- potato pot]
blender --background --factory-startup --python tools/blender/validate_models.py
blender --background --factory-startup --python tools/blender/preview_models.py -- <out_dir>
# The outdoor setting (cliff top, lighthouse, sea stacks, grass) has its own
# builder so it can never overwrite the kitchen kit. validate_models.py covers both.
blender --background --factory-startup --python tools/blender/build_environment.py [-- lighthouse ...]

# Write docs/ingredient_tree.md from the live catalog and food web.
godot --headless --path . -s res://tools/godot/ingredient_tree_doc.gd

# Manual play harness: F = serve a plate cooked by the simulation (fries with
# simmered kelp and clams), U = buy cheapest retrofit, R = spawn a new spirit
# after the current one departs
godot --path . res://scenes/test_sanctuary.tscn
```

There are no separate unit tests and no single-test runner. `scripts/test/integration_test.gd` runs pure checks first (serving, the kitchen simulation, essences, the food web, grains, seasoning, coverings, the shipped world, progression economy/unlocks/persistence), then runs a two-spirit lifecycle simulation at `Engine.time_scale = 10`. To add a check, write a `_test_*` function that uses `_expect_equal`/`_expect_near` (which takes an optional tolerance) and call it from `_ready()`. Call `LighthouseProgression.reset()` before the lifecycle run so the station multipliers stay at 1.0. The persistence test writes to the real `user://progression.cfg`, and the plating test to `user://dish_book.cfg`. `CookedPlates` (`scripts/test/`) cooks plates in code through the real simulation for the suite and the harness.

The food model checks build their ingredients in code. The exceptions read shipped content on purpose, and are meant to fail if it breaks:
- the validation check;
- `_test_shipped_world`, which validates every ingredient, essence and species, and checks the food web's promises (cooked bream fillet hovers, grouse skin resists char, and so on);
- `_test_every_carcass_dresses`;
- the kitchen station checks (`_test_kitchen_stations`). They run in the real scene with the shipped pot, stove, press and oil, and expect 0.05 turns per gram and a 0.35 oil yield.

The rest of the suite asserts against the shipped `data/` content, not fixtures, so some content-only changes break it:
- The lifecycle serves half a potato's fries with two simmered sea kelp blades and two tide pool clams, and expects exactly two servings. `SAFETY_TIMEOUT` is sized for the timings in `example_spirit_basic.tres`.
- The progression tests hardcode upgrade ids, costs and multipliers. They also assert `available_upgrades().size() == 2` after the burner is bought, so adding a new upgrade with no prerequisites, or one that requires the burner, fails the suite even though it is a pure `.tres` addition.
- `_test_shipped_world` expects six species and at least 90 ingredients.

If you change this data on purpose, update the matching expected values in the test in the same change.

## Architecture

The game has three decoupled modules, and each dependency points in one direction:

```
LighthouseProgression ──(unlocks, station multipliers)──> DishServingStation
kitchen food ──Dish──> DishNourishment ──(FeedingResult)──> DishServingStation
DishServingStation ──SpiritEventBus.feed_spirit_requested──> SpiritController/FSM
Spirit FSM ──SpiritEventBus.spirit_lifecycle_complete("ASCENDED")──> LighthouseProgression (+light)
```

- **Autoloads** (`autoload/`):
  - `SpiritEventBus` is a signal-only hub. External systems talk to spirits *only* through its signals and never call a `SpiritController` directly.
  - `LighthouseProgression` owns the light, the purchased upgrades and the save/load, and it emits its own signals. There is only one lighthouse, so it does not go through the bus.
- **Serving** (`systems/culinary/`): `DishServingStation` is the *only* bridge from the kitchen to spirits.
  - It takes a plated `Dish`, refuses one with locked ingredients, and turns it into a `FeedingResult` through `DishNourishment`.
  - It adds the affinity bonus when the dish's dominant affinity (by mass) matches the spirit's archetype, and applies the progression station multipliers.
  - Then it emits on the bus. The crafting matrix and techniques it replaced are gone.
- **Spirit** (`systems/spirit/`):
  - `SpiritController` (the `scenes/spirit.tscn` root) owns a `SpiritRuntimeState`, which is a mutable per-spawn copy of the stats. The `SpiritArchetype` resource itself is never mutated.
  - `SpiritController` also owns a `SpiritStateMachine`, a flat FSM with one strategy class per state in `states/`. State hooks return the next state or `NO_TRANSITION`.
  - Every transition is checked against `LEGAL_TRANSITIONS`. Adding a state means updating the `SpiritState.State` enum, the legality table, the `_states` map, and the `STATE_NAMES` arrays in both test scripts.
  - `ctx.outcome` (`ASCENDED` / `UNFED`) is set on the path into `DEPARTED`, and `StateDeparted` broadcasts it.
  - `FeedingResult` is the only data contract between the culinary module and the FSM.
- **Data-driven content** (`resources/` for the scripts, `data/` for `.tres` instances): you add ingredients, essences, species, equipment, archetypes and upgrades by authoring new `.tres` files, not new code.
  - `LighthouseProgression` loads every `.tres` in `res://data/upgrades/` automatically. `IngredientCatalog` loads every ingredient under `res://data/ingredients/` (subfolders too) and every species in `res://data/creatures/`, and resolves the food web.
  - Only ingredients with `available_from_start` are usable before an upgrade unlocks them.
  - The world's content is described, as the game computes it, in `docs/ingredient_tree.md`. Regenerate it with `godot --headless --path . -s res://tools/godot/ingredient_tree_doc.gd` after changing content.
  - Upgrade `prerequisites` are upgrade `id` StringNames, and their multipliers stack multiplicatively.
- **Food** (`systems/food/`) and **Kitchen** (`systems/kitchen/`) are the kitchen simulation. Plated food reaches spirits through `DishServingStation`.
  - `FoodPiece` is the physical state of one piece of a SOLID ingredient: grams of solids, water and oil, a core, and a surface shell split into six **faces** (`FoodPiece.Face`: ±X, ±Y, ±Z, indexed per face in `face_temp_c`, `face_moisture`, `face_browning`, `face_char`, `face_skin`). Each face's share of the shell is its share of the area. `surface_*` are area-weighted means; setting one sets every face. Cutting makes fresh flesh faces, and `roll()` rotates the faces with the piece.
  - `FoodCutting` is the pure geometry of axis-aligned mezzaluna cuts.
  - `FoodHeating` is the pure physics of one piece in a `HeatExposure`. Every face draws heat through three channels: the liquid it's wetted by, contact (hot metal, the board), and air (which also dries it, via `WaterVapour`). A wet core never passes 100°C, and dry crust insulates and runs hotter at its outside, where browning happens. Flavour exchange follows `FlavourProfile` fat and water solubility. It returns a `HeatExchange`, split by channel, so whoever owns each source can conserve energy and mass. Uniform exposure (no per-face values) is a piece fully immersed in a stirred medium; the tests use it.
  - `CookingPot` owns a `CookingVessel`, an optional `HeatSource`, the `KitchenAir`, the liquid and the pieces, and advances in fixed steps. Its heat sits in three thermal masses: the base over the burner, the rim and walls, and the liquid.
    - `PotLayout` places each piece (a `PotPlacement`): it sinks or floats by buoyancy, displaces the liquid, and is wetted below the liquid line.
    - The pot builds each piece's per-face exposure from its placement.
    - `MediumChemistry` wears frying oil out: breakdown, the smoke point, acrid flavour, and boosts to browning and uptake.
  - `RestingSurface` is food out in the air: the board, or held on the spoon.
  - `LiquidStore` is a pourable store: cup, bottle, jug.
  - `KitchenAir` (`resources/`, data in `data/air/`) is the open air: temperature, wind, humidity. Weather will be authored as instances of it.
  - `Ingredient` carries the physical, thermal and cooking-medium data all of these need, plus a `validate()`. This includes skin permeability, shrinkage and, for oils, smoke point and breakdown rates. The older ingredients (kelp, clam, herb, ember root) have no physical data yet and don't validate.
  - Equipment resources extend `KitchenEquipment` and live in `data/equipment/`. `LighthouseProgression.is_equipment_unlocked` gates them. `CookingVessel` carries the pot's real geometry and metal; `HeatSource` carries how far the flame spreads.
  - `FoodPerception` maps a piece's state to `FoodTexture`, `FoodAppearance` (with per-face values) and `BiteSound`. `TasteNote` puts a bite into words.
  - `Dish` holds plated pieces and `LiquidPortion`s and has a `fingerprint()` (via `DishDescriber`) and a `dominant_affinity()`. `DishNourishment` turns a `Dish` into a `FeedingResult`, including `ascension_strength`. `DishBook` keeps the player's names for dishes by fingerprint (`user://dish_book.cfg`), and which dishes are on the menu.
  - **Mystical essences:**
    - A `MysticTrait` (`data/traits/`) is one of eight effects the physics understands (LIFT, GLOW, EMBER, FROST, CHAR_WARD, BLOOM, SOOTHE, NOURISH). It names a trigger (`TraitEffects.activation`), its fat and water solubility, and how it travels by diet.
    - Food, media and plated liquids carry `TraitDoses`. Essences infuse by solubility like flavour, act in `FoodHeating` through `TraitEffects.act`, lift food in `PotLayout` and on a `RestingSurface`, and feed or calm spirits in `DishNourishment`.
    - An ingredient's authored doses are `traits` (`TraitDose`); `inherited_traits` are computed.
  - **Ecosystems:**
    - A `Creature` (`data/creatures/`) has a diet and `CreaturePart`s (tissue, ingredient, count, uses). `FoodWeb` passes diet essences into tissues at each trait's `diet_share`, prey first.
    - A whole carcass (an ingredient with `creature`) is dressed on the board into its parts. `dressed_in_field` species offer their parts from the pantry instead.
  - **Physical extras on `Ingredient`:**
    - rendering fat (`render_temp_c`, `renders_into`);
    - grain hydration (`water_uptake_capacity`, `hydration_rate_per_s`) and grain heaps (`FoodPiece.count`, `FoodPiece.handful`);
    - seasoning potency and scoop (`flavour_potency`, `scoop_g`, `Seasoning`);
    - `pliability`, for covering a pot;
    - `raw_firmness`, `edible_share`, `lore` and `pantry_shelf`.
  - **Pot coverings:** `CookingPot.cover_with` seals a pot with a thin, wide piece. The headspace steams food above the liquid (condensation in `FoodHeating`) or bakes it in a dry pot, and the covering cooks too.
  - A `Transformation` in `data/transformations/` (loaded automatically) describes what one piece of equipment does to one bulk ingredient, e.g. pressing seeds into oil. `ManualProcessor` runs it from the player's work. Transformations are the only authored recipes, and they never describe a finished dish.
  - A piece's local Y axis is height, matching Godot. Food is never rotated off the world's axes in the kitchen, so the food shader picks a face by the world normal.
- **Kitchen scene** (`scenes/kitchen/`, scripts in `systems/kitchen/view/`) is the playable view layer and the main scene.
  - `Kitchen` owns the one camera and a flat `KitchenViewMode` FSM: WALKING → STEPPING_IN → AT_COUNTER → STEPPING_OUT → WALKING. It gates every input by mode. It also routes food between the stations: board to pot, spoon to board, sunflower head to press. Tasting goes through it too.
  - `KitchenSimulation` owns every simulation object (pot, board, plate and held `RestingSurface`s, press, liquid stores) and steps them in `_physics_process`. The views (`CuttingBoard`, `StoveView`, `PotView`, `PourVesselView`, `PressView`, `SeedSource`, `IngredientSource`) only draw state and turn the player's hands into calls. No scene script holds food logic.
  - `CuttingBoard` is any food surface. The serving board is an instance with `allows_cutting` off and room for liquids; what is on it is the `Dish`. `IngredientSource` is a pantry shelf (`Ingredient.Shelf`) whose right-click turns to the next ingredient. Spices and grains are carried as a pinch or handful and let go where they land.
  - `KitchenAudio` drives synthesised sound (`SoundSynth`) from the simulation: the sizzle follows steam, the crackle follows bubbling, and the pitch follows oil temperature. It also plays the one-shots of the hands. `KitchenAudio.recorded_bites` swaps in recorded bite layers.
  - The `Caretaker` (`systems/player/`, `scenes/player/`) is the first-person body. It has a ledge guard so it never walks off the cliff.
  - `CounterViews` supplies the station poses, the sea vista and the edge-peek.
  - `KitchenPointer` raycasts mouse input into `Interactable` areas, and their owners turn it into simulation calls. Knobs and the crank read circular drags through `CircularDrag`. The pointer is live only at the counter, and cancels any hold when the player steps away.
- **World** (`scenes/world/coast.tscn`, `systems/world/coast.gd`) is the outdoor setting: a painted sky shader, the sea shader, sun, fog and glow, the cliff top, the lighthouse, sea stacks and a wind-blown grass field. Imported `.glb` models get the toon look from `tools/godot/toon_post_import.gd`, which is set as each model's import script. The terrain, lighthouse and sea stacks get trimesh collision at import time through the per-node physics settings in their `.glb.import` files. That also works in headless runs, where building collision from a mesh at runtime does not. The terrain's faces must stay wound upward (see `build_environment.py`), or its collision is one-sided from below.
- `ElementalAffinity.Type` is the shared tag enum. Ingredients and archetypes both use it, so neither module depends on the other's scripts.

## Conventions

- Scripts use `class_name` with typed GDScript, and they use `##` doc comments to explain design intent. Match this style.
- `.tres`/`.tscn` files are sometimes hand-written without `uid=`. When the editor re-saves them it adds UIDs and drops default-valued properties, and that diff is harmless.
