# Where we are: session hand-off

Read this first, then `CLAUDE.md` (vision, cooking model, architecture, commands). Written at the end of the session that built the kitchen simulation, the outdoor scene and the first-person caretaker.

## State in one paragraph

Work is on branch **`kitchen-simulation`** (not merged to `main`), and everything is committed. The game's main scene is the **outdoor kitchen** (`scenes/kitchen/kitchen.tscn`): a first-person caretaker walks a cliff top beside a lighthouse and steps up to a counter to work. The only interactive cooking so far is the **cutting board**: baskets, mezzaluna cuts, steadying and rolling. Under it sits a complete, tested **food simulation** (cutting, heat, frying, boiling, browning, charring, oil uptake, the oil press, flavour, texture, bite sounds, dish fingerprints, nourishment), not yet wired to the stove or to serving. The integration suite passes with **234 checks**.

## Files to read, in order

1. `CLAUDE.md`: vision, the cooking model (the user's design), settled decisions, open questions, architecture, commands, conventions.
2. `docs/kitchen_plan.md`: the section-by-section build plan, with a status line and "changed from the first draft" notes for each section.
3. `CHANGELOG.md`: everything done, newest first.
4. `README.md`: only what's confirmed working.
5. `docs/models_needed.md`: every model, with sizes, pivots and slots. All are built.
6. `docs/screenshots/`: what the scene looks like.

## Done

| Plan section | What | State |
|---|---|---|
| 1 | Food state model: `FoodPiece` (grams of solids, water and oil; surface shell and core), `FoodCutting`, `FlavourProfile`, physical `Ingredient` data | Done, tested |
| 2 | Heat: `FoodHeating` (pure physics), `CookingPot`, `HeatSource`, `CookingVessel` | Done, tested, sim only |
| 3 | `Transformation` (conservation-checked), `ManualProcessor` (oil press), equipment gating | Done, tested, sim only |
| 4.1–4.5 | `FoodPerception` (texture, appearance, `BiteSound`), `Dish` and fingerprint, `DishNourishment` (`FeedingResult.ascension_strength`) | Done, tested, sim only |
| 6, checkpoint 1 | Cutting board scene, mezzaluna gesture, steadying, rolling, food cel shader | Built; **the user has not play-tested the cutting yet** |
| Models | 16 kitchen models (built by the other session) plus 4 environment models (cliff top, lighthouse, sea stack, grass field), all passing `validate_models.py` | Done |
| Outdoor scene | Sky, sea and grass shaders, sun, fog, glow, cliff, lighthouse with glowing lamp, sea stacks; the user **likes the look** | Done |
| First-person | `Caretaker` (WASD, mouse look, ledge guard, 3.2 m/s, no sliding), `KitchenViewMode` FSM, E to step in and Esc to step out, edge-peek at the counter, mouse always locked | Done; the user reported sliding, slow walking and no mouse lock, all fixed. **Not yet re-confirmed by the user** |

## The plan, step by step

A condensed copy of `docs/kitchen_plan.md`, which has the full pass/fail check for each step and the deviation notes. ✅ done and tested · 🟡 built, waiting on the user · ⬜ not started · ⛔ blocked on a user decision.

**1. Food state model** ✅
- 1.1 `FoodPiece` physical state ✅
- 1.2 Ingredient physical data and `validate()` ✅
- 1.3 Flavour axes and mass-weighted mixing ✅
- 1.4 Cutting geometry: mass conserved, thin slices crumble, unsteadied perpendicular cuts damage pieces ✅

**2. Heat and cooking** ✅ (simulation only)
- 2.1 Gas stove: flame level to watts ✅
- 2.2 Pot and medium: heating, heat loss, a cold batch dropping the oil's temperature ✅
- 2.3 Heat into food: time grows with thickness² ✅
- 2.4 Surface: evaporation, browning, char, oil uptake ✅
- 2.5 Water: capped at 100°C, softening when overcooked ✅
- 2.6 Fixed-step, frame-rate-independent simulation ✅

**3. Equipment and transformations** ✅ (simulation only)
- 3.1 `Transformation` resource with conservation checks ✅
- 3.2 Oil press driven by crank work ✅
- 3.3 Infusion (chilli oil) emerging with no rule of its own ✅
- 3.4 Equipment gating on upgrades ✅ (additive; technique gating is removed in 4.6)

**4. Perception and outcomes**
- 4.1 Texture ✅
- 4.2 Appearance (shader values) ✅
- 4.3 Bite-sound layer selection ✅
- 4.4 Dish fingerprint ✅
- 4.5 Nourishment and ascension strength ✅
- 4.6 Retire `CulinaryCraftingMatrix` and techniques, re-tune spirit pacing, give kelp/clam/herb/ember root physical data or retire them ⛔ needs the user's go-ahead

**5. Falling, catching and the moon** ⛔
- 5.1 Decisions (uncaught spirit, chance vs readable, catch style, moon vs kindled light) ⛔
- 5.2 Spirit strength from `FeedingResult.ascension_strength` ⬜
- 5.3 FSM: `FALLING` and `CATCHING` states, legality table, `STATE_NAMES` in both test scripts ⬜
- 5.4 Moon progression module ⬜
- 5.5 Moon visuals and model ⬜

**6. The 3D kitchen**, built in three checkpoints
- Checkpoint 1 🟡: scene, camera, pointer, interaction framework (6.1, 6.2), the mezzaluna board (6.3), food shader (6.7, first pass). Plus, beyond the plan: the outdoor setting ✅ and the first-person caretaker with step-in/out and edge-peek 🟡
- Checkpoint 2 ⬜ **next**: stove knob (6.4); pot with pouring, pieces in and slotted-spoon lift-out (6.5); the frying loop on screen
- Checkpoint 3 ⬜: oil press crank (6.6), food shader polish (6.7), taste test with bite captions and later audio (6.8)
- 6.9 Scene–simulation bridge: views wrap sim objects and no scene script holds food logic. This is the rule for every checkpoint; the board already follows it.
- The **cut-piece kit** (halves, planks, sticks, dice) models are deferred until the rule for matching a cut piece to a mesh is written. Cut pieces are boxes for now.

**7. Dishes, naming and service** ⬜
- 7.1 Plating onto a plate to make a `Dish` ⬜
- 7.2 Naming a dish, stored by fingerprint ⬜
- 7.3 Service menu ⛔ (recipes cooked to order, or cooked stock?)
- 7.4 Serving through `DishServingStation` with equipment gating ⬜
- 7.5 Persistence of named dishes ⬜

## Next up

1. **Ask how the cutting and the walking feel.** The user hasn't reported on either since the fixes. Tune `walk_speed_mps` and `mouse_sensitivity` on the Caretaker if asked.
2. **Checkpoint 2 of Section 6:** stove knob (drag to set the flame; `knob` pivot on `gas_stove.glb`), pot (pouring oil and water, dropping pieces in, lifting them out with the slotted spoon), and the frying loop, visually using `FoodPieceView` plus the food shader. `CookingPot` and `FoodHeating` already do the physics. The pot's `liquid_surface` and the cup's `oil_surface` are hidden in `kitchen.tscn` until this checkpoint drives them.
3. **Checkpoint 3:** taste test (bite captions now, audio later from recorded samples), oil press crank (`crank` pivot; 0.05 turns per gram), food shader polish.
4. **Waiting on the user:**
   - **4.6:** retiring `CulinaryCraftingMatrix` and the technique `.tres` files deletes working code and changes the spirit test harness. Get an explicit go-ahead.
   - **Section 5:** falling and catching spirits, and the moon. It's blocked on the open questions in `CLAUDE.md`: what happens to an uncaught spirit, chance vs a readable outcome, how catching works, and whether the moon replaces kindled light.
   - **7.3:** is the service menu recipes cooked to order, or cooked stock?

## Decisions the user made (already in CLAUDE.md or the plan)

- Weather volatility is the game's challenge. Demon waves were rejected.
- Ascended spirits form a moon. Poorly fed spirits may fall, and the caretaker catches them.
- Cooking is a fully manual, realistic simulation: mezzaluna, a hold to steady cuts, manual flame, doneness judged by eye and taste, emergent named dishes, and bad food can still be served.
- The kitchen is **outdoors** on the cliff top beside the lighthouse. The view is **first-person** while walking and the three-quarter station view at the counter. No character model.
- Oil is pressed by hand (0.05 turns per gram); automated presses come later as a retrofit. The pantry is unlimited until foraging exists.

## How the user wants to work

- **Code first, section by section, straight on to the next section**; stop only where a section is blocked on the user's decision. Models are batched into `docs/models_needed.md` for a Blender session.
- **Keep `CHANGELOG.md` current** (every completed piece), `README.md` (only confirmed-working features), and `docs/models_needed.md`.
- **The mouse is always locked in games**: captured for mouse look, confined when a cursor is needed, re-asserted every focused frame.
- Commits go on `kitchen-simulation`, and each commit message ends with the Co-Authored-By line.
- Give the user something they can **play** (the main scene), not just tests.

## Commands

```sh
godot --path .                                                    # play (main scene: the kitchen)
godot --headless --path . res://scenes/integration_test.tscn      # the suite (~25 s, exits 0/1)
godot --headless --editor --quit --path .                         # after adding/renaming a class_name, or to reimport assets
blender --background --factory-startup --python tools/blender/build_models.py -- <name>        # kitchen kit
blender --background --factory-startup --python tools/blender/build_environment.py -- <name>   # environment
blender --background --factory-startup --python tools/blender/validate_models.py               # all 20 models
```

## Gotchas learned the hard way

- **Hand-written `.tscn` transforms are row-major.** `Transform3D(...)` lists the basis rows. Writing columns gives the inverse rotation; the camera once faced away from the scene because of this. Compute transforms with a script rather than typing them.
- **Never run `build_models.py` with no names** unless you mean to rebuild and overwrite all 16 kitchen models. The environment has its own builder for this reason.
- **The terrain's faces must stay wound upward** (`recalc=False` in `cliff_top()`). Recalculating normals flipped the open heightfield, and the caretaker sank through the one-sided collision.
- **Collision for environment models is generated at import time** (per-node physics in their `.glb.import` `_subresources`). Building trimesh collision from a mesh at runtime returns nothing in headless runs.
- **Imported models get the cel look** from `tools/godot/toon_post_import.gd`, set as each `.glb`'s import script. New `.glb` files need that line added to their `.import` file, followed by a reimport. Delete `.godot/imported/<name>.glb-*` to force it.
- **Screenshots:** the user's tiling Wayland window manager ignores the requested window size. Render into a fixed-size `SubViewport` from a `-s` SceneTree script, save the PNG and view it. That's how every visual here was checked.
- **In bash heredocs with `'EOF'`**, write GDScript line continuations as a single `\`. A doubled one broke parsing once.
- **When slicing in tests or scripts**, stop while a full step plus `FoodCutting.MIN_PIECE_THICKNESS_MM` still fits. `FoodCutting.cut` correctly refuses thinner remainders and returns an empty array.
- **Every section so far was mutation-checked:** break the central rule on purpose and confirm the suite fails. One mutant survived at first (conduction ignoring thickness) until a stronger test was added.
