# Models needed

Every model the finished kitchen sections need, specific enough to build without the conversation that produced them. A later session builds these in Blender through a Blender MCP server.

**Before modelling:** `.mcp.json` only configures the Godot MCP server. Add a Blender MCP server first.

## Conventions for every model

- **Style:** stylized low-poly, cel-shaded, Ghibli-influenced (see Art direction in `CLAUDE.md`). Flat or hand-painted colour per material slot; no photoreal textures.
- **Scale:** real-world metres. The simulation works in millimetres; the conversion happens in code, so model at true size.
- **Axes:** the simulation's local X is length, Y is height and Z is depth, matching Godot. Blender is Z-up, and the glTF exporter maps Blender Z to Godot Y and Blender Y to Godot −Z. So in Blender: length along X, depth along Y, height along Z.
- **Origin:** centre of the base, so the object rests on a surface at height 0, unless an entry says otherwise.
- **Export:** glTF binary (`.glb`) to the path given, with transforms applied (scale 1, no rotation).
- **Materials:** use the named slots listed. The cel shader is assigned per slot in Godot.
- **Moving parts:** any part the player turns or that swaps state is a separate object with its pivot at the rotation axis, named as listed.

**Deliberately not listed yet:** the cut-piece kit (halves, planks, sticks, dice). What it has to contain depends on how Section 6.3 will match a cut piece to a mesh, and that isn't written yet. It gets added here when 6.3 is built.

## From Section 1: food state model

### Potato
- **Path:** `assets/models/ingredients/potato.glb`
- **Size:** 0.090 × 0.055 × 0.045 m in Blender (length X × depth Y × height Z). This matches `whole_size_mm = (90, 45, 55)` in `data/ingredients/potato.tres`.
- **Shape:** a slightly lumpy oval tuber with a few shallow eyes, resting on its flattest side.
- **Budget:** 300–600 triangles.
- **Material slots:** `skin` (dusty tan-brown), `flesh` (pale cream; not visible on the whole potato but reserved for cut pieces).

### Chilli
- **Path:** `assets/models/ingredients/chilli.glb`
- **Size:** 0.070 × 0.018 × 0.018 m (length X × depth Y × height Z), matching `data/ingredients/chilli.tres`.
- **Shape:** a long, gently curved chilli tapering to a point, with a short green stem and calyx at the wide end.
- **Budget:** 200–400 triangles.
- **Material slots:** `skin` (glossy red), `stem` (green), `flesh` (lighter red, reserved for cut pieces).

### Sunflower head
- **Path:** `assets/models/ingredients/sunflower_head.glb`
- **Size:** about 0.25 m across the face and 0.05 m deep, on a 0.10 m stub of stem.
- **Shape:** a mature, slightly drooping sunflower head: a ring of yellow petals around a dark seed disc. This is the foraged source of sunflower seeds; it has no ingredient data of its own yet.
- **Budget:** 800–1,500 triangles.
- **Material slots:** `petals` (warm yellow), `seed_disc` (dark brown with a lighter spiral pattern), `stem` (green).
- **Origin:** centre of the back of the seed disc.

### Sunflower seed
- **Path:** `assets/models/ingredients/sunflower_seed.glb`
- **Size:** 0.010 × 0.005 × 0.003 m.
- **Shape:** a single hulled seed kernel, teardrop shaped. Sunflower seeds are a granular ingredient handled by mass, so this mesh is instanced many times to show a pile or a scoopful.
- **Budget:** under 40 triangles.
- **Material slots:** `kernel` (pale grey-beige).

## From Section 2: heat and cooking

### Gas stove
- **Path:** `assets/models/equipment/gas_stove.glb`
- **Size:** a single-burner countertop stove, about 0.30 × 0.30 m footprint and 0.10 m tall, with a pan support grate on top.
- **Data it must match:** `data/equipment/gas_stove.tres`. The flame level is continuous from off (0) to full (1), with the lowest lit flame at 0.15.
- **Parts:**
  - `body`: enamelled casing.
  - `grate`: cast-iron pan support, about 0.22 m across. The pot sits on it.
  - `burner_cap`: the round burner head under the grate.
  - `knob`: **separate object, pivot at its rotation axis on the front face.** Rotates about 270° from off (pointing straight up) to full. The player turns it by dragging.
  - `flame_anchor`: an empty at the centre of the burner cap where the flame effect is spawned. The flame itself is an effect in Godot, not a mesh.
- **Budget:** 800–1,500 triangles.
- **Material slots:** `enamel` (muted cream or sea-green), `iron` (dark grey), `brass` (knob), `burner` (black).

### Pot
- **Path:** `assets/models/equipment/pot.glb`
- **Size:** interior volume must hold `capacity_ml = 3000` from `data/equipment/pot.tres`. An interior 0.18 m in diameter and 0.12 m deep (about 3.05 L) fits, with walls and base about 3 mm thick.
- **Shape:** a sturdy steel or enamelled pot with two side handles and no lid.
- **Parts:**
  - `body`: the pot itself.
  - `liquid_surface`: **separate object**, a flat disc filling the interior, origin at its centre. Godot moves it up and down to match how full the pot is and swaps its material between oil and water.
- **Origin:** centre of the base, outside.
- **Budget:** 600–1,200 triangles.
- **Material slots:** `metal` (brushed steel or enamel), `handles` (darker metal), `liquid` (on the surface disc; the shader supplies oil or water colour).

### Slotted spoon
- **Path:** `assets/models/equipment/slotted_spoon.glb`
- **Size:** about 0.32 m long with a bowl 0.08 m across.
- **Shape:** a spider or slotted spoon for lifting fries out of oil, with a wooden handle.
- **Origin:** end of the handle, where the player grips it.
- **Budget:** 300–600 triangles.
- **Material slots:** `metal`, `wood`.

### Water jug and oil bottle
- **Path:** `assets/models/equipment/water_jug.glb`, `assets/models/equipment/oil_bottle.glb`
- **Size:** jug about 0.12 m wide and 0.20 m tall; bottle about 0.07 m wide and 0.25 m tall.
- **Shape:** vessels the player pours from into the pot. The bottle is clear glass, so the oil colour shows through.
- **Parts:** `body`, and `pour_point` (an empty at the spout where the pour effect starts).
- **Budget:** 300–600 triangles each.
- **Material slots:** `ceramic` (jug), `glass` and `oil` (bottle), `cork`.

## From Section 3: equipment and transformations

### Oil press
- **Path:** `assets/models/equipment/oil_press.glb`
- **Size:** a hand-cranked countertop screw press, about 0.35 m long, 0.15 m wide and 0.30 m tall.
- **Data it must match:** `data/equipment/oil_press.tres` and `data/transformations/press_sunflower_seeds.tres`. Seeds go in, and each crank turn presses 2g of seed (0.5 turns per gram). Oil drips out of the spout and seed cake is pushed out of the end of the barrel.
- **Parts:**
  - `frame`: cast-iron body, clamped or bolted to the counter.
  - `hopper`: an open funnel on top where seeds are poured in. Holds about 250g of seeds.
  - `barrel`: the horizontal pressing cylinder under the hopper.
  - `crank`: **separate object, pivot on the screw's axis** at the end of the barrel. It turns a full 360° continuously; the player turns it by dragging in a circle. Include a wooden handle grip at the end of the crank arm.
  - `oil_spout`: an empty under the barrel where the oil drip effect starts.
  - `cake_outlet`: an empty at the far end of the barrel where pressed seed cake emerges.
- **Budget:** 1,500–3,000 triangles.
- **Material slots:** `iron` (dark, slightly worn), `wood` (crank handle), `brass` (fittings).

### Oil catch cup
- **Path:** `assets/models/equipment/oil_cup.glb`
- **Size:** about 0.08 m wide and 0.07 m tall, holding about 250 ml.
- **Shape:** a small spouted cup that sits under the press spout and pours into the bottle or pot.
- **Parts:** `body`, `oil_surface` (a separate disc that rises as oil collects, like the pot's liquid surface), `pour_point` (an empty at the spout).
- **Budget:** 200–400 triangles.
- **Material slots:** `ceramic`, `oil`.

### Seed cake
- **Path:** `assets/models/ingredients/sunflower_seed_cake.glb`
- **Size:** a crumbly pressed pellet about 0.04 m long and 0.012 m across. The press extrudes several.
- **Shape:** a rough, crumbly cylinder with a fibrous surface. It is a granular ingredient handled by mass, so this mesh is instanced for however much cake the press has made.
- **Budget:** under 150 triangles.
- **Material slots:** `cake` (muted brown).

## From Section 4: perception and outcomes

Section 4 needs no models. It defines what the food shader and bite audio will be driven by:

- **Food material parameters** (for the cut-piece kit and whole ingredients): `browning`, `char`, `gloss`, `translucency`, `crumble`, each 0–1. Every food mesh needs its `flesh` and `skin` slots so the shader can brown and char them.
- **Bite sounds (audio, not models):** five recorded layers, `crisp`, `crunch`, `soft`, `squelch` and `chew`. Each is a short (0.2–0.5 s) close-miked bite, mixed by weight and pitched from 0.85 to 1.25 in Godot. They go in `assets/audio/bite/`.
