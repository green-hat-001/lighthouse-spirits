# Changelog

Completed work, newest first. Section numbers refer to `docs/kitchen_plan.md`.

## Walking feel and mouse lock

- The mouse is always locked. It's captured while walking and confined to the window at the counter, so the edge-peek can't run off-screen. The mode is re-asserted every frame while the window has focus, because the single capture request at startup could be dropped under Wayland and leave no lock at all. Esc while walking is still the deliberate way to free it, and a click locks it again.
- Stepping in puts the hand in the middle of the screen.
- No more sliding: walking accelerates at 14 m/s² and brakes at 40 m/s², so letting go stops the caretaker within a few frames.
- Walking speed raised from 1.6 to 3.2 m/s.
- Integration suite: 226 → 234 checks, covering full walking pace, stopping without sliding, and the mouse mode in every view state.

## First-person caretaker

- The kitchen is now the main scene. Play in the editor (or `godot --path .`) opens it; the spirit harness is still at `scenes/test_sanctuary.tscn`.
- Added the first-person `Caretaker`: WASD walking at an unhurried 1.6 m/s, mouse look, no running or jumping. A ledge guard means they never step off the cliff or the edge of the land, so you can stand at the lip and look down at the sea.
- Added `KitchenViewMode`, a flat FSM (walking, stepping in, at the counter, stepping out) that owns the single camera:
  - E at the counter glides the view down to the nearest station.
  - Esc glides it back to your eyes. The field of view eases from 80° walking to 62° at the counter.
  - Esc while walking frees the mouse, and a click takes it back.
  - Stepping out mid-cut abandons the stroke cleanly.
- At the counter, pushing the mouse toward either screen edge glances up to 26° that way, to see the baskets or the stove without leaving the board. The middle 62% of the screen never turns the view, and the view holds still while you're mid-drag.
- `CounterViews` replaces `CameraRig`. It supplies the station poses, the sea vista and the peek; the kitchen moves the camera.
- Collision: trimesh collision for the terrain, lighthouse and sea stacks is generated at import time, and the counter has a box. Fixed the terrain's faces, which pointed downward and made its collision one-sided from below.
- A small HUD: an aiming dot while walking, the "E — work at the counter" prompt, and a controls hint at the counter.
- Integration suite: 191 → 226 checks. It covers the view-mode transitions, counter reach, the peek mapping, and a physics run in the real scene: standing on the cliff top, walking at the cliff edge without going over, and stepping in and out.
- Mutation check: disabling the ledge guard fails the cliff-edge check.

## The outdoor kitchen, first mockup

- The kitchen now stands outdoors on the cliff top beside the lighthouse (`scenes/world/coast.tscn`, instanced into the kitchen):
  - A painted sky shader with a warm horizon haze, a sun glow and slow two-tone cumulus.
  - A sea shader with rolling swells, colour that deepens with distance, and foam where the sea meets the cliff and rocks.
  - Late-afternoon sun with tight shadow cascades for the counter, depth fog that melts the sea into the horizon, glow and light SSAO.
  - New Blender-built models: the cliff top and headland, the lighthouse with its keeper's cottage and a glowing lamp, three sea stacks, and 2,600 grass tufts that sway in the wind off the sea. They're built by `tools/blender/build_environment.py`, and all 20 models pass `validate_models.py`.
- Swapped every greybox for the model kit. Whole potatoes and chillies on the board are their real models and turn with the piece when rolled. Baskets show their contents, and the mezzaluna, board and counter are the kit's.
- Imported models get the cel look (toon diffuse and specular, a soft rim, capped metalness) from `tools/godot/toon_post_import.gd`.
- The camera opens on a sea vista and settles onto the board. W/↑ looks out to sea again and S/↓ comes back. Each station is now a full camera pose.
- The stove, pot, press, oil bottle, water jug, slotted spoon and a sunflower head are on the counter as set dressing; they don't work until checkpoints 2 and 3.
- Decisions: oil is pressed by hand at 0.05 turns per gram (about 29 turns for a 200g shallow-fry), with automated presses to come as a retrofit. The pantry is unlimited until foraging exists.
- Integration suite: 191 checks, including the camera look actions.

## Model kit: every model in `docs/models_needed.md`

- Built all 16 models: potato, chilli, sunflower head, sunflower seed, seed cake, gas stove, pot, slotted spoon, water jug, oil bottle, oil press, oil catch cup, mezzaluna, cutting board, pantry basket and counter. Each has an editable `models/<name>.blend` (Godot skips the folder via `.gdignore`) and a `.glb` export at the path the doc gives.
- The models come from `tools/blender/build_models.py`, which builds them procedurally in Blender to the doc's sizes, origins, pivots, part names and material slots. `tools/blender/validate_models.py` checks every one against the doc, and `tools/blender/preview_models.py` renders three-quarter previews.
- Measured: the pot holds 3,034 ml (data: 3,000), the oil cup 253 ml, and the press hopper about 290 g of seeds.
- The sunflower's seed disc carries a generated golden-angle spiral texture, packed into the `.blend` and embedded in the `.glb`.
- The oil bottle's cork is its own object, so it can be pulled before pouring.
- Added a Blender MCP server (`blender-mcp`) to `.mcp.json`. Its addon is installed in Blender 5.2 and serves on port 9876.
- Not yet placed in scenes: the kitchen still uses its greybox meshes.

## Kitchen Section 6, checkpoint 1: the cutting board (awaiting play-test)

- Added the kitchen scene, `scenes/kitchen/kitchen.tscn`: a counter, a cutting board, potato and chilli baskets, and a fixed three-quarter camera that glides between stations with A/D or the arrow keys.
- Added `Interactable` and `KitchenPointer`: a two-state (idle or holding) mouse-hand that raycasts into the kitchen and reports presses, drags and releases to whatever owns the object.
- Added the cutting board. Click a basket to put a whole item on the board. Drag across the bare board through food to cut it with the mezzaluna, which follows the stroke and rocks through the cut. Hold Space or Shift to steady the food, drag a piece to move it, and right-click a piece to roll it onto its side.
- Added `FoodPiece.roll()`, which turns a piece's cut history with it, and `MezzalunaGesture`, which snaps a stroke to a cut axis and offset.
- Added a cel-shaded food shader driven by the simulation: skin vs flesh, glassy cooked flesh, golden-to-brown browning, char patches, oil gloss and crumbling edges.
- Added `kitchen_steady` and the camera input actions, and set a 1280 × 720 default window.
- Integration suite: 169 → 189 checks, including the real kitchen scene: basket to board, a stroke cutting a potato, rolling, and refusing items once the board is full.
- Mutation check: rolling without turning the cut history fails two checks.

## Kitchen Section 4.1–4.5: perception and outcomes

- Added `FoodPerception` with `FoodTexture`, `FoodAppearance` and `BiteSound`: pure mappings from a piece's physical state to what the player perceives.
  - Texture: crispness, firmness, softness, chewiness, wetness, greasiness.
  - Appearance: shader values for browning, char, gloss, translucency and crumble.
  - Bite sound: weights for crisp, crunch, soft, squelch and chew layers, with thinner pieces biting higher. Raw potato crunches, a good fry is crisp, tender boiled potato is soft, and greasy fries or mush squelch.
- Added `Dish`, `LiquidPortion` and `DishDescriber`. A plate of pieces and liquids gets a fingerprint such as `potato:stick:medium:cooked:brown|sunflower_oil:heat`. The same dish cooked the same way is recognised, one stray piece doesn't change it, and burnt, raw, differently cut or chilli-oiled versions are different dishes.
- Added `DishNourishment`: dish to `FeedingResult`. Nourishment comes from real energy content, calming from flavour and how hot the food is served, and quality from each ingredient's own ideal doneness, minus char, crumbling and excess grease. Burnt food still feeds, just less surely.
- `FeedingResult` gained `ascension_strength` (default 1.0, so the current serving path is unchanged). `Ingredient` gained ideal doneness ranges.
- Integration suite: 142 → 169 checks.
- Mutation checks: quality ignoring doneness, and bite sounds ignoring sogginess, each fail the suite.
- Not done: 4.6, replacing the crafting matrix. It deletes working code and changes the playable harness, so it waits for the user.

## Kitchen Section 3: equipment and transformations

- Added `Transformation` (`resources/transformation.gd`): equipment plus the player's work turns one bulk ingredient into others. It validates conservation, so a press can't make fat the seeds never had. Transformations load automatically from `data/transformations/`.
- Added `ManualProcessor` (`systems/kitchen/manual_processor.gd`): hand-worked equipment that is loaded with an ingredient and driven by the player's crank turns, with outputs collected until taken. Nothing happens without the player's work.
- Authored the `oil_press` (starting equipment), `sunflower_seed_cake`, and the `press_sunflower_seeds` transformation: 100g of seeds and 50 crank turns give 35g of oil and 60g of seed cake.
- Chilli oil is emergent: chilli held in warm oil makes spicy oil, chilli burnt in hot oil makes it bitter, and fries fried in chilli oil come out spicy. No infusion rule exists; it falls out of Section 2's flavour exchange.
- Added `char_susceptibility` to `Ingredient` (chilli 6) so thin, sugary skins burn realistically fast.
- Added equipment gating: `LighthouseUpgrade.unlocked_equipment` and `LighthouseProgression.is_equipment_unlocked`.
- Fixed a test helper that sliced until the cutting code refused a too-thin remainder.
- Integration suite: 118 → 142 checks.
- Mutation checks: removing the conservation rule and disabling flavour exchange each fail the suite.

## Kitchen Section 2: heat and cooking simulation

- Added `FoodHeating` (`systems/food/food_heating.gd`), the physics of a piece of food in hot oil, water or a dry pan.
  - Heat crosses into a surface shell and conducts to the core, so cooking time grows with thickness.
  - A wet surface is pinned at 100°C while its water boils off. Once dry it browns, and it chars if far too hot.
  - Cool oil seeps into food; hot oil is held out by steam.
  - The core cooks past the ingredient's cook temperature and overcooks beyond done. Overcooked food with a wet surface falls apart, while a dry crust holds together.
  - Browning adds aroma and savouriness, char adds bitterness, and flavour diffuses between food and liquid.
- Added `CookingPot` (`systems/kitchen/cooking_pot.gd`): a vessel on a burner with its liquid and food. Cold food draws heat out of the oil. Water stops at its boiling point and boils away, and a dry pot cooks by contact. It advances in fixed 0.05s steps, so results don't depend on frame rate.
- Added kitchen equipment resources: `KitchenEquipment`, `HeatSource` (flame level to watts) and `CookingVessel`. Authored `gas_stove` and `pot`.
- Gave `Ingredient` thermal data (specific heat, conductivity, cook temperature and time, overcook softening) and cooking-medium data (boiling point, latent heat, heat transfer into food). Authored `water` and `sunflower_oil`.
- Section 1 fix from the logic review: `FoodPiece` now stores solids, water and oil in grams, and tracks a surface shell with its own moisture. Cutting conserves each exactly.
- Integration suite: 83 → 118 checks.
- Mutation checks: making conduction ignore thickness fails the thickness-scaling check. Removing the rule that pins a wet surface at 100°C fails six checks.

## Kitchen Section 1: food state model

- Added `FoodPiece` (`systems/food/food_piece.gd`), the physical state of one piece of a solid ingredient: size, mass, moisture, core and surface temperature, doneness, browning, char, absorbed oil, integrity and flavour.
- Added `FoodCutting` (`systems/food/food_cutting.gd`), the geometry behind the mezzaluna. Axis-aligned cuts turn one piece into two and conserve mass exactly. A fresh cut face dilutes browning and char and pulls surface temperature toward the core. Slices thinner than the ingredient's stable thickness crumble, and cuts under 1.5mm are refused. Every perpendicular cut made without steadying the food damages both pieces.
- Added `FlavourProfile` (`resources/flavour_profile.gd`): seven fixed taste axes with mass-weighted mixing.
- Gave `Ingredient` physical data: form (solid, granular, liquid), composition, density, whole size, cutting fragility and flavour, plus `validate()`.
- Authored `potato`, `chilli` and `sunflower_seeds`.
- Fixed the axis convention: a piece's local Y axis is height, matching Godot, so X and Z are the footprint on the board. The potato's size became 90 × 45 × 55 mm (same volume as before).
- Integration suite: 43 → 83 checks. A deliberately broken version of the perpendicular-cut rule (counting only the most recent cut axis) fails the suite, as it should.
- Logic review: re-checked mass conservation, fresh-face dilution, the thin-slice rule and the perpendicular-cut rule. One structural problem was found and is fixed at the start of Section 2: water and oil were stored as fractions of mass, which would drift once cooking changes a piece's mass. They are now stored in grams.
