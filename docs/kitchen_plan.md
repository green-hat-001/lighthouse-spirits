# Kitchen plan

The build plan for the simulated 3D kitchen described in `CLAUDE.md` under Cooking model.

**Workflow.** Build the code one section at a time, tested and checked, and move straight on to the next section; stop only where a section waits on a user decision. Models are not made between sections. Each finished section lists what it needs in `docs/models_needed.md`, and a later session builds them in batches through a Blender MCP server. Completed work goes in `CHANGELOG.md`, and features go in `README.md` once the suite confirms them.

**Ordering.** Sections 1–4 are pure simulation: no art, all checkable in the headless integration suite. Section 5 waits on open design decisions. Sections 6–7 need authored assets. French fries are the end-to-end acceptance test: potato → mezzaluna → pot of oil on the gas stove → fries judged by colour and taste.

⚠ marks parts that have to be built bespoke. 🎨 marks steps that wait on assets.

## 1. Food state model

*Status: code done and covered by the integration suite (`systems/food/`, `resources/flavour_profile.gd`, the physical fields on `Ingredient`). Models not yet made.*

**1.1 Food state.** `FoodPiece` holds one piece's physical state: size in mm, mass, moisture, core and surface temperature, core doneness, surface browning, char, absorbed oil, structural integrity and flavour. *Check:* a piece created from an ingredient starts with the expected values.

**1.2 Ingredient physical properties.** `Ingredient` gains a physical form (solid, granular, liquid), composition (water, starch, sugar, fat, protein), density, whole size, cutting fragility and a flavour profile, plus a `validate()` that rejects out-of-range data. Potato, sunflower seeds and chilli are authored. *Check:* all three validate, and a deliberately bad ingredient built in code fails.

*Changed from the first draft:* browning rate moves to 2.4 and ideal doneness ranges move to 4.5, where they are first used.

**1.3 Flavour.** Fixed axes: sweet, salty, sour, bitter, umami, heat, aroma. Mixing is weighted by mass. *Check:* mixing equal masses of two profiles gives the midpoint.

**1.4 Cutting geometry** ⚠. Pieces are boxes and cuts are axis-aligned planes, so one piece becomes two. Mass is conserved, there is a minimum piece thickness, and thin pieces lose integrity. Every perpendicular cut made without steadying damages the pieces. *Check:* a potato cut at 10mm steps along one axis and then, steadied, along another gives 10mm sticks whose masses sum to the original; the same cross-cuts unsteadied give damaged pieces.

*Changed from the first draft:* cuts are axis-aligned, so wedges are out of scope for now.

## 2. Heat and cooking simulation

*Status: code done and covered by the integration suite (`systems/food/food_heating.gd`, `systems/kitchen/cooking_pot.gd`, `resources/heat_source.gd`, `resources/cooking_vessel.gd`, `resources/kitchen_equipment.gd`). Models not yet made.*

*Changed from the first draft:*
- Browning speed comes from each ingredient's sugar, starch and protein, not a separate authored browning-rate field.
- Boiled food keeps its water rather than gaining more; softening comes from overcooking with a wet surface.
- At full flame oil keeps getting hotter (about 340°C at equilibrium), so the player has to manage the flame. *Superseded in checkpoint 2:* oil now smokes past its smoke point and breaks down (`MediumChemistry`).
- Water migration, oil uptake and browning constants were tuned against realistic targets. *Recalibrated in checkpoint 2,* once a wet core was capped at 100°C and crust was made to insulate:
  - 10mm fries at 180°C are cooked through and golden at about six minutes, and still moist inside.
  - Blanched at 130°C they cook through but stay pale and greasy.
  - At 220°C they burn.
  - 25mm potato cubes boil tender in about 8 minutes and fall apart after 15–20.

- **2.1 Gas stove:** flame level 0–1 → heat output. Equipment is a `.tres`.
- **2.2 Pot and medium:** the pot holds oil, water or nothing. The medium heats from the flame, loses heat, and drops when cold food goes in. *Check:* oil at full flame reaches about 180°C in the expected time, cools when the flame is lowered, and dips when a batch is added.
- **2.3 Heat into food:** the surface follows the medium, and the core heats more slowly with thickness (cooking time grows with thickness squared). *Check:* a 5mm stick cooks through before a 15mm stick at the same oil temperature.
- **2.4 Surface changes:** moisture evaporates above 100°C. Browning starts around 140°C, scaled by sugar and starch and faster when the surface is dry; the ingredient's browning rate is added here. Char sets in above a threshold, and oil absorption rises when the oil is too cool. *Check:* 180°C gives golden, crisp fries; 130°C gives pale, greasy ones; 220°C chars them.
- **2.5 Water cooking:** water caps at 100°C, so nothing browns. Food softens and gains moisture, and overcooked food loses structure. *Check:* boiled potato never browns and goes mushy if left too long.
- **2.6 Deterministic clock:** fixed-step simulation independent of frame rate. *Check:* identical results within tolerance at `time_scale` 1 and 10.

## 3. Equipment and transformations

*Status: code done and covered by the integration suite (`resources/transformation.gd`, `systems/kitchen/manual_processor.gd`, `data/transformations/`, equipment gating on `LighthouseUpgrade` and `LighthouseProgression`). Models not yet made.*

*Changed from the first draft:*
- Infusion needed no new rule. Chilli oil emerges from the flavour exchange and char bitterness already in Section 2's `FoodHeating`, and fried food picks up the oil's flavour as it soaks oil in.
- Chilli barely burned at 200°C, so `Ingredient` gained `char_susceptibility` (potato 1, chilli 6): thin, sugary skins burn far faster.
- Transformation validation checks conservation: the outputs together may not hold more water, starch, sugar, fat or protein than the input.
- Equipment gating is additive for now. `LighthouseUpgrade.unlocked_equipment` and `LighthouseProgression.is_equipment_unlocked` exist, but technique gating stays until 4.6 retires techniques. The stove, pot and press are all starting equipment, so no shipped upgrade unlocks equipment yet.

- **3.1 Transformation resource:** inputs + equipment + conditions → outputs, e.g. sunflower seeds + press → oil + seed cake.
- **3.2 Oil press:** output accumulates as the player turns the handle. *Check:* 100g of seeds yields the expected amount of oil.
- **3.3 Infusion without a recipe:** flavour moves between food and the medium, faster when hot. Chilli oil emerges as oil whose heat axis has risen, and burning the chilli raises the bitter axis instead. *Check:* chilli held in 100°C oil makes spicy oil; at 200°C the oil turns bitter.
- **3.4 Equipment gating:** `LighthouseUpgrade` unlocks equipment instead of techniques, and existing upgrades are migrated. *Check:* the progression tests are updated and pass.

## 4. Perception and outcomes

*Status: done, including 4.6. The crafting matrix and techniques are retired; spirits are fed real plated food through `DishServingStation`.*

*Changed from the first draft:*
- Texture has a sixth axis, firmness, so raw vegetables can crunch.
- Bite layers are crisp, crunch, soft, squelch and chew. Squelch comes from grease or mush, not plain wetness, so tender boiled potato bites softly.
- `FeedingResult.ascension_strength` defaults to 1.0, so the legacy crafting path is unaffected until 4.6.
- `Ingredient` gained `ideal_doneness_min/max` (potato 1.0–2.0, chilli 0.3–1.5).
- Nourishment comes from real energy content (starch, sugar and protein at 4 kcal/g, fat at 9) and calming from flavour and serving warmth. The pacing constants against spirit deficits are provisional and get tuned in 4.6.

- **4.1 Texture:** state → crispness, softness, chewiness, wetness, greasiness. *Check:* 180°C fries score high on crispness; undercooked fries score high on wetness.
- **4.2 Visual parameters:** state → shader values (browning, char, oil gloss), as a pure mapping.
- **4.3 Bite sound selection:** texture → sound layers, weights and pitch. *Check:* crisp fries select crunch; soggy ones select squelch.
- **4.4 Dish identity:** a plate of pieces and sauces becomes a `Dish` with a fingerprint of its ingredients and how they were cooked. *Check:* two batches cooked the same way share a fingerprint; burnt and perfect batches don't.
- **4.5 Nourishment:** Dish → `FeedingResult`, with a new ascension-strength field. Quality is measured against each ingredient's ideal doneness ranges (added to `Ingredient` here), never a recipe. *Check:* perfect fries > burnt fries > raw potato, and burnt fries still feed a spirit.
- **4.6 Migration:** retire `CulinaryCraftingMatrix` and the technique `.tres` files, and replace `_test_crafting_math` and the two-servings assertion. *Check:* the integration suite passes on the new model. *Done:* the lifecycle serves half a potato's fries with simmered kelp and clams and still ascends in two servings.

## 5. Falling, catching and the moon

- **5.1 Decisions (blocking):** what happens to an uncaught spirit, chance vs a readable outcome, and how catching works. See the open questions in `CLAUDE.md`.
- **5.2 Spirit strength:** the runtime state accumulates ascension strength from each `FeedingResult`.
- **5.3 State machine:** add `FALLING` and `CAUGHT`, plus a new outcome if spirits can be lost. Update the enum, `LEGAL_TRANSITIONS`, the `_states` map, `STATE_NAMES` in both test scripts, and add bus signals. *Check:* the integration test covers fall-and-catch, and the fed path is updated.
- **5.4 Moon progression:** a module listens for ascensions, and moon growth stages are data.
- **5.5 Moon visuals** 🎨

## 6. The 3D kitchen

*First-person caretaker (after the mockup):* the player walks the cliff top in first person (WASD, mouse look, a ledge guard at the cliff), presses E at the counter to step into the station view, and Esc to step back. At the counter, pushing the mouse to a screen edge glances sideways. Decided by the user: first-person, no character model.

*Outdoor mockup (between checkpoints 1 and 2):* the greybox is replaced by the model kit, and the kitchen stands in its outdoor setting on the cliff top: sky, sea, cliff, lighthouse, sea stacks and grass. The camera opens on a sea vista (W/↑ to look out again, S/↓ to come back). The stove, pot, press, bottle, jug, spoon and sunflower are set dressing until checkpoints 2 and 3 make them work.

*Status: checkpoints 1–3 built and covered by the integration suite, awaiting the user's play-test.*
- **Checkpoint 1:** the scene, camera, pointer and the cutting board.
- **Checkpoint 2:** the stove knob and flame, the pot with pouring, food in and the slotted spoon, and the frying loop on screen.
- **Checkpoint 3:**
  - the oil press crank, hopper, cup and seed cake;
  - per-face food shader polish;
  - the taste test with captions and synthesised bite sounds;
  - cutting polish.
- **The polish pass (Section 9 below):** models for the whole larder, cut pieces as meshes, the pantry dresser, the hands, ink, light and motion. Recorded bite samples are optional, since synthesised layers stand in.

*Changed in checkpoints 2 and 3:*
- **Per-face heat transfer.** The simulation went further than the first draft. Each face of each piece is exposed to what it touches in the pot: the metal through a film of oil, the oil, or the air above it. The pot is three thermal masses (the base over the burner, the rim and walls, the liquid) out in the cliff-top wind. Food sinks or floats by buoyancy and displaces the oil. With hand-pressed oil the fry is shallow, so food browns underneath and must be turned. See the latest `CHANGELOG.md` entry.
- **Moving food between stations:** carry it in the hand by steadying while pressing a piece (the whole touching cluster lifts), then let go over the pot. The slotted spoon lifts food out onto the board. A plate is Section 7.
- **The oil bottle and cup:** both are pressed-oil stores. The cup fills under the press and pours into the pot or the bottle. The bottle is corked, and right-click pulls the cork. The water jug never runs dry.
- **The sunflower head** is the seed source for the press, 50 g a click.
- **Taste:** T on a piece on the board bites the end off it, a real cut. The caption describes texture, flavour and warmth in words.

*Changed from the first draft:*
- A cut is a drag across the bare board through the food. Pressing on a piece picks it up to move it, and right-clicking a piece rolls it onto its side. `kitchen_steady` (Space or Shift) holds the food during a cut.
- One stroke cuts every piece it crosses, so laid-out planks can be cut into sticks in one pass.
- Pieces are never rotated off the box's axes, and unsteadied cuts show as pieces sliding apart, so the view always matches the simulation. Cut pieces are drawn as meshes built for each cut (9.3), not boxes.
- The camera keeps its horizontal field of view, so the counter stays framed in tiled or portrait windows.
- **Decided:** oil is pressed by hand, at 0.05 turns per gram (about 29 turns for 200g of oil). Automated presses come later as a lighthouse retrofit. The pantry is unlimited until foraging exists.
- The kitchen is outdoors, on the cliff top beside the lighthouse.

- **6.1 Kitchen scene and camera** 🎨: counter, stove, pot, board. Greybox meshes until the kit exists.
- **6.2 Interaction framework** ⚠: mouse raycast picking, grab and place, hold and drag inputs.
- **6.3 Mezzaluna** 🎨⚠: a drag defines the cut, snapped to the piece's axes, with a rocking animation. A hold input steadies the food. *Changed:* pieces render as a mesh built for each cut (`FoodPieceMesh`), not the nearest match from a cut-piece kit; a kit can only approximate an arbitrary cut. See 9.3.
- **6.4 Stove knob:** turned by dragging, with the flame visual following it.
- **6.5 Pot:** pour oil, add pieces, lift them out with a slotted spoon.
- **6.6 Oil press:** turn the handle by dragging in a circle.
- **6.7 Food shader** ⚠🎨: cel-shaded browning, char and gloss driven by 4.2.
- **6.8 Taste test** 🎨: plays the layered bite sound from 4.3, using recorded crunch, crisp, soft, squelch and chew samples.
- **6.9 Scene–simulation bridge:** scene nodes wrap simulation objects, and the simulation steps in `_physics_process`. *Check:* no scene script contains food logic.

**Acceptance:** make fries by hand, and see them brown and hear them crunch. *Built: the crunch is synthesised until recorded samples replace it.*

## 7. Dishes, naming and service

*Status: 7.1, 7.2, 7.4 and 7.5 done. 7.3 waits on the user.*

- **7.1 Plating:** pieces on a plate become a `Dish`. *Done:* the serving board at the pass, with drizzles and the cup as a ladle.
- **7.2 Naming:** the player names a dish, stored by fingerprint. *Done:* `DishBook`, N at the pass.
- **7.3 Service menu.** Open question: are menu entries recipes cooked to order, or cooked stock? *M puts a named dish on the menu; what the menu means for arriving spirits waits on this decision.*
- **7.4 Serving:** adapt `DishServingStation` to the new dish and equipment gating. *Done in 4.6.*
- **7.5 Persistence:** named dishes are saved. *Done:* `user://dish_book.cfg`, separate from progression.

## 8. The mystical larder (added)

Essences, ecosystems, butchery, rendering, grains, spices, pot coverings and the authored ingredient tree. All done and covered by the suite; see the latest `CHANGELOG.md` entry and `docs/ingredient_tree.md`. Still to come:
- **Foraging and fishing out on the coast:** the pantry is unlimited until then.
- **Weather that moves `KitchenAir`.**
- **Models for the new ingredients:** see `docs/models_needed.md`.

## 9. Polish: models, look and feel (added)

*Status: done and covered by the suite, awaiting the user's play-test.* Decided with the user: the pantry is a dresser behind the counter, a first-person hand is drawn, and cut pieces are built per cut instead of from a kit.

- **9.1 The larder's models:** every solid ingredient has a whole model, built from about 45 parametric shape families (`tools/blender/larder.py`), sized and coloured from its `.tres`. *Check:* `validate_models.py` passes, and the suite checks each model is within 10% of its ingredient's size.
- **9.2 The pantry dresser:** four shelves behind the counter (garden, catch, grains, spices), every unlocked ingredient in a spot of its own, laid out from the catalog, never running out. The mouse at the top of the screen lifts the eyes to it. *Check:* the suite checks spots, hover, a hundred takes, a pinch into the pot and reading a label.
- **9.3 Cut pieces:** `FoodPieceMesh` builds each piece's mesh from its size and skin: skin faces round over, cut faces stay flat, and the mesh fills exactly the piece's box. `FoodLook` (`data/looks/`) gives each ingredient its roundness and flesh grain. *Check:* the suite checks it stays in and fills its box, keeps its cut face flat, is closed, and builds in under 4 ms.
- **9.4 Look:** the food shader paints flesh grain, browns crisp edges first, blisters crust, cracks char and curls cooked fillets; ink outlines; lighting tuned for cel shading (lower sun and ambient, ACES, a fill light from the cook's side, finer shadows); a painted grain on wood, wicker, clay and paint; the pot's liquid ripples, swirls and clouds to broth.
- **9.5 Feel:** the hands (`HandView`, `HandModel`), which reach, grip, pinch and press on a spring; carried food that trails and sways, drops into place and squashes as it lands; parts that fall open when a creature is dressed; spice that falls as flecks and stays on the food; new synthesised one-shots for the sprinkle, the plop into water and food set down. A scripted reel (`tools/godot/kitchen_reel.tscn`) plays a turn at the counter through real input for recording.

## Assets (🎨)

Mezzaluna, cutting board, potato, gas stove with knob, pot, oil surface, slotted spoon, oil press, plate, sunflower head, chilli, the moon, and recorded bite sounds.
