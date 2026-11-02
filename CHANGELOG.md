# Changelog

Completed work, newest first. Section numbers refer to `docs/kitchen_plan.md`.

## The working kitchen: per-face cooking, the pot, stove, spoon, vessels and press (Section 6, checkpoints 2 and 3)

**Physics and chemistry (Sections 1–3, extended)**
- Each piece of food now has six faces, each with its own temperature, moisture, browning, char and skin. A face draws heat through whatever it touches: the liquid it's wetted by, hot metal or the board it rests on (contact), and open air. The old piece-wide surface values are now area-weighted means. Under uniform exposure the per-face model reproduced all 234 earlier checks exactly before it was recalibrated.
- A wet core can no longer pass 100°C: heat beyond boiling turns its water to steam. A dried crust insulates the core and lets its outer skin run hotter than the millimetre under it, which is where browning happens. Because the old model let the core overshoot, the heat model was recalibrated against real frying:
  - 10 mm fries at 180°C are golden and cooked through at about six minutes, and still moist inside.
  - Blanching at 130°C cooks them through but leaves them pale. This is the first fry of a double fry; the old check said they stayed raw.
  - At 220°C they burn.
  - The potato's `cook_seconds` moved from 400 to 320, browning slowed and oil uptake from replaced water halved.
- Food dries into the air below boiling, by vapour-pressure-driven evaporation (`WaterVapour`, with a Lewis-analogy mass-transfer coefficient). Food resting out keeps cooking from its own heat, steam-dries, cools in the wind, and its crust goes limp as water creeps back out to it.
- Skin lets less water, fat and flavour through than cut flesh (`skin_permeability`), and food shrinks as it loses water (`shrinkage_per_water_lost`).
- Flavour moves between food and a medium only as far as the medium dissolves it (`FlavourProfile.FAT_SOLUBILITY` / `WATER_SOLUBILITY`):
  - Chilli makes chilli oil but barely heats water.
  - Salted water seasons a boiled potato, while salt in food stays put in oil.
  - Diffusion now doubles every 40°C rather than every 20°C.
- Browning adds more aroma and savouriness.
- `KitchenAir` (in `data/air/`) is the open air on the cliff top: temperature, wind and humidity. Wind strips heat from the pot, cools resting food and blows the flame away from under the pot.

**The pot (`CookingPot`, `PotLayout`, `PotPlacement`, `MediumChemistry`)**
- **Three thermal masses:**
  - the base over the burner;
  - the rim and walls, which lose heat to the wind by convection and to the sky by radiation;
  - the liquid, whose open surface loses heat and, for water, evaporates before it boils.
- **Flame:** spreads wider with its level. A small flame heats only the middle of the base, and a flame wider than the pot wastes heat up its sides. Steel conducts sideways poorly, so the middle of the base is a hot spot: food over the burner browns first. The pot is authored with a 5 mm clad base.
- **Placement:** food sinks or floats by buoyancy, with clinging steam bubbles lifting it, and displaces the liquid. A piece on the floor touches the metal through a film of the liquid, only the part below the liquid line is wetted, and the rest is in the warm air over the pot.
  - In a shallow fry (200–400 g of oil), food browns underneath first and has to be turned.
  - Raw potato sinks in oil, and a fry that has given up its water floats.
  - A crowded pot heaps food onto food, and bubbling or stirring slides it back off.
- **Agitation:** bubbling and stirring raise heat transfer into food.
- **Oil chemistry:**
  - Oil breaks down with heat (oxidation), with steam from wet food (hydrolysis) and fast once it smokes. Sunflower oil smokes at 210°C. That's between unrefined and refined oil, chosen so that frying at 180°C stays possible with hand-pressed oil.
  - Worn oil smokes sooner, tastes acrid, darkens, and browns and greases food more.
  - Water never smokes.
- **Metal lag:** the metal runs hotter than the oil and carries it on for a while after the flame is turned down.
- **Cost:** a pot of 24 fries costs about 60 ms of simulation per simulated second.

**The counter (Section 6.4–6.9)**
- `KitchenSimulation` owns the pot, the board's resting food, food held in the air, the press and the liquid stores, and advances them all in `_physics_process`. Scene nodes only draw them and turn the player's hands into calls (6.9).
- **Stove (6.4):** drag round the knob to turn it, from off (straight up) through 270° to full. Turning it on from off sparks it alight. The flame is a ring of flickering blue tongues, sized from the burner's data, that spreads under the pot and leans in the wind. A light under the pot glows with it.
- **Pot (6.5):**
  - **Liquid:** sits at its true level. It shimmers more as oil gets hotter, darkens as oil breaks down, reddens with chilli, and trembles then rolls as water boils.
  - **Food:** each piece sits where the layout puts it, ringed by sizzle foam as hard as it's steaming.
  - **Air:** steam and smoke drift downwind, and wet food spatters hot oil.
- **Slotted spoon:** drag in the pot to stir, and out over the rim to lift and drain what the bowl caught. Let go over the board to set it down, or anywhere else to slide it back. Right-click a piece in the pot to turn it.
- **Board:** Space while pressing a piece lifts it together with every piece touching it, so a whole cut potato lifts at once. Let go over the pot to drop it in, in the layout it was held in.
- **Vessels:** the water jug, oil bottle and oil cup pour from the spout once tipped past where the liquid reaches it. A full vessel pours at a slight tilt; a nearly empty one has to be tipped right over. The bottle is corked until right-clicked. The cup pours into the pot or the bottle, and the jug never runs dry.
- **Oil press (6.6):** circle the crank to turn it. The hopper fills by clicking the sunflower head (50 g a time). Oil drips into the cup below (or onto the counter if the cup has been taken away), and seed cake piles up at the end of the barrel. Turning backwards presses nothing.
- **Cutting (6.3):**
  - Cut halves ease apart along the cut, or jolt sideways when unsteadied.
  - Cuts that crumble shed crumbs onto the board.
  - While you draw the mezzaluna, the line it will cut is shown on every piece, snapped exactly as the cut will be.
- **Food shader (6.7):** per face, so skin, cut flesh, browning and char each show where they are. A crisping crust blisters, wet and oily food shines, and hot, wet food in the air gives off wisps of steam.
- **Taste (6.8):** T over a piece on the board takes a real bite (the bitten end is cut off) and says, in words, how it feels, tastes and how hot it is, e.g. "Crisp outside, fluffy and tender inside. Toasty. Scalding hot." No scores. The bite is heard as well, layered from the five bite sounds by the piece's `BiteSound` weights and pitched by its size.
- **Sound (`KitchenAudio`, `SoundSynth`):** every sound is synthesised at startup, with no samples needed. The simulation then drives loudness and pitch:
  - frying oil hisses as hard as the food is steaming and crackles as hard as it bubbles, rising in pitch with the oil's temperature;
  - water burbles toward and at the boil;
  - the burner roars with its gas, and the spark clicks when it lights;
  - the press ratchets every eighth of a turn;
  - the blade knocks the board on each cut;
  - pouring gurgles.

  Recorded bite samples can replace the synthesised layers through `KitchenAudio.recorded_bites`. A fresh 10 mm stick in 154°C oil takes about 10 s to start sizzling, the time its faces take to reach boiling.
- **Controls hint:** moved to the top of the screen.

**Checks**
- Integration suite: 234 → 338 checks. New coverage:
  - per-face cooking, cut faces as flesh, and rolling turning the faces;
  - drying and cooling in the wind, and resting fries cooking on and going limp;
  - shallow frying browning underneath, and the hot spot over the burner;
  - buoyancy and displacement, and oil breakdown and smoke;
  - wind slowing the pot, and open water evaporating;
  - solubility, the spoon, and the cost of a full pot;
  - the synthesised sounds, and the burner sound following the gas;
  - every station driven through its own grips in the real scene.
- **Mutation-checked:** removing core boiling, putting the top face of shallow-fried food under the oil, and turning buoyancy off each fail the suite.
- **Screenshots** in `docs/screenshots/kitchen_*.png`. They were rendered in a cloud container on the OpenGL fallback with a software rasteriser, so the lighting is flatter and paler than the Forward+ game.

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
