# Changelog

Completed work, newest first. Section numbers refer to `docs/kitchen_plan.md`.

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
