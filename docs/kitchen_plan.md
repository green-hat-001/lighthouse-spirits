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
- Oil has no smoke point yet: at full flame it keeps getting hotter (about 350°C at equilibrium), so the player has to manage the flame. Smoking and burnt oil are not modelled.
- Water migration, oil uptake and browning constants were tuned against realistic targets. 10mm fries at 180°C are cooked through in about 3.5 minutes and golden at 4–5. At 130°C they're pale, greasy and still raw at 5. At 220°C they burn. 25mm potato cubes boil tender in about 9 minutes and fall apart after 15–20.

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

*Status: 4.1–4.5 code done and covered by the integration suite (`systems/food/food_perception.gd`, `food_texture.gd`, `food_appearance.gd`, `bite_sound.gd`, `dish.gd`, `dish_describer.gd`, `liquid_portion.gd`, `dish_nourishment.gd`). **4.6 not started: it waits for the user's go-ahead**, because it deletes `CulinaryCraftingMatrix` and the technique data and changes the F-key harness and the lifecycle test.*

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
- **4.6 Migration:** retire `CulinaryCraftingMatrix` and the technique `.tres` files, and replace `_test_crafting_math` and the two-servings assertion. *Check:* the integration suite passes on the new model.

## 5. Falling, catching and the moon

- **5.1 Decisions (blocking):** what happens to an uncaught spirit, chance vs a readable outcome, and how catching works. See the open questions in `CLAUDE.md`.
- **5.2 Spirit strength:** the runtime state accumulates ascension strength from each `FeedingResult`.
- **5.3 State machine:** add `FALLING` and `CAUGHT`, plus a new outcome if spirits can be lost. Update the enum, `LEGAL_TRANSITIONS`, the `_states` map, `STATE_NAMES` in both test scripts, and add bus signals. *Check:* the integration test covers fall-and-catch, and the fed path is updated.
- **5.4 Moon progression:** a module listens for ascensions, and moon growth stages are data.
- **5.5 Moon visuals** 🎨

## 6. The 3D kitchen

*Status: checkpoint 1 of 3 built and awaiting the user's play-test: the kitchen scene (`scenes/kitchen/kitchen.tscn`), three-quarter camera rig, pointer and interaction framework, and the cutting board with the mezzaluna, steadying and rolling. Checkpoint 2 (stove, pot, frying) waits on the oil-supply decision below. Checkpoint 3 is the food shader polish, taste captions and the press.*

*Changed from the first draft:*
- A cut is a drag across the bare board through the food. Pressing on a piece picks it up to move it, and right-clicking a piece rolls it onto its side. `kitchen_steady` (Space or Shift) holds the food during a cut.
- One stroke cuts every piece it crosses, so laid-out planks can be cut into sticks in one pass.
- Pieces render as axis-aligned boxes with the food cel shader. Unsteadied cuts show as pieces sliding apart, never rotating, so the view always matches the simulation.
- The camera keeps its horizontal field of view, so the counter stays framed in tiled or portrait windows.
- **Open decision before checkpoint 2:** frying needs a lot of oil. At the current press data, 200g of oil is about 290 crank turns. Options: a starting bottle, fewer turns per gram, or shallow frying in a pan. Also: are pantry potatoes and seeds unlimited for now?

- **6.1 Kitchen scene and camera** 🎨: counter, stove, pot, board. Greybox meshes until the kit exists.
- **6.2 Interaction framework** ⚠: mouse raycast picking, grab and place, hold and drag inputs.
- **6.3 Mezzaluna** 🎨⚠: a drag defines the cut, snapped to the piece's axes, with a rocking animation. A hold input steadies the food. Pieces render as the nearest match from a cut-piece kit (halves, planks, sticks, dice).
- **6.4 Stove knob:** turned by dragging, with the flame visual following it.
- **6.5 Pot:** pour oil, add pieces, lift them out with a slotted spoon.
- **6.6 Oil press:** turn the handle by dragging in a circle.
- **6.7 Food shader** ⚠🎨: cel-shaded browning, char and gloss driven by 4.2.
- **6.8 Taste test** 🎨: plays the layered bite sound from 4.3, using recorded crunch, crisp, soft, squelch and chew samples.
- **6.9 Scene–simulation bridge:** scene nodes wrap simulation objects, and the simulation steps in `_physics_process`. *Check:* no scene script contains food logic.

**Acceptance:** make fries by hand, and see them brown and hear them crunch.

## 7. Dishes, naming and service

- **7.1 Plating:** pieces on a plate become a `Dish`.
- **7.2 Naming:** the player names a dish, stored by fingerprint.
- **7.3 Service menu.** Open question: are menu entries recipes cooked to order, or cooked stock?
- **7.4 Serving:** adapt `DishServingStation` to the new dish and equipment gating.
- **7.5 Persistence:** named dishes are saved with progression.

## Assets (🎨)

Mezzaluna, cutting board, potato, cut-piece kit, gas stove with knob, pot, oil surface, slotted spoon, oil press, plate, sunflower head, chilli, the moon, and recorded bite sounds.
