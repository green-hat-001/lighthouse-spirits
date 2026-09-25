# Lighthouse Spirits

A calm cooking game set in a wind-swept coastal lighthouse. Transient spirits, the Warawara, drift in hungry and unsteady. The caretaker cooks for them by hand, watches them grow brighter and lighter, and sends them up to a great moon of spirits. See `CLAUDE.md` for the full vision and `docs/kitchen_plan.md` for the kitchen build plan.

Built with Godot 4.7 (Forward+) in GDScript.

## Running

```sh
# Headless integration suite. Exits 0 on pass, 1 on fail.
godot --headless --path . res://scenes/integration_test.tscn

# Rebuild the global class cache after adding or renaming a class_name script.
godot --headless --editor --quit --path .

# Play the game (the main scene: the outdoor kitchen, work in progress).
# Walking: WASD to walk, mouse to look, E at the counter to step in, Esc to
# free the mouse (click to take it back).
# At the counter: click a basket, drag across the board to cut, hold Space
# to steady, right-click to roll a piece, A/D along the counter, W/S to look
# out to sea and back, mouse to a screen edge to glance sideways, Esc to
# step back.
godot --path .

# Manual play harness: F serves a dish, U buys the cheapest retrofit,
# R calls in a new spirit once the current one has left.
godot --path . res://scenes/test_sanctuary.tscn
```

## What works

Everything listed here is covered by the integration suite and passes.

**Playable in the manual harness**
- Spirit lifecycle: a spirit arrives, waits, is fed, and either ascends or leaves unfed.
- Serving dishes through the serving station, with the affinity bonus and lighthouse station bonuses.
- Lighthouse progression: kindled light from ascensions, retrofit purchases, unlocks and save/load.

**Playable in the kitchen (the main scene)**
- The outdoor kitchen on the cliff top beside the lighthouse: painted sky, sea with swells and foam, cliffs, sea stacks, and grass swaying in the wind. See `docs/screenshots/`.
- Walking about in first person with WASD and the mouse. The caretaker never walks off the cliff.
- Stepping up to the counter with E and back with Esc, moving between stations, looking out to sea, and glancing sideways by moving the mouse to a screen edge.

The cutting board (baskets, mezzaluna cuts, steadying, rolling) is in the scene and covered by the suite, but hasn't been play-tested yet. The stove, pot and press are set dressing until the next checkpoints.

**Simulation only (not yet in the scene)**

The rest of the kitchen is built simulation-first. These systems work and are tested, but have no input or visuals until later in Section 6 of the kitchen plan.

- Food pieces with physical state: size, mass, water, oil, temperature, doneness, browning, char, integrity and flavour.
- Mezzaluna cutting: precise axis-aligned cuts that conserve mass, thin slices that crumble, and damage when a perpendicular cut is made without holding the food steady.
- Flavour profiles on seven axes with mass-weighted mixing.
- Ingredient data validation. Potato, chilli, sunflower seeds, water, sunflower oil and sunflower seed cake are authored.
- The oil press: load sunflower seeds, turn the crank, and collect oil and seed cake. Pressing conserves what the seeds contain.
- Chilli oil without a recipe: chilli in warm oil makes it spicy, burnt chilli makes it bitter, and food fried in it picks up the flavour.
- Reading food like a cook: texture, look (browning, char, gloss, translucency) and the sound of a bite all come from the food's physical state. A good fry crackles; greasy or mushy food squelches.
- Dishes with an identity: a plate's fingerprint recognises the same dish made the same way, and tells burnt, raw or differently cut versions apart.
- Nourishment from real food: energy content feeds a spirit, flavour and warmth calm it, and how well the food was made sets how surely it carries the spirit toward the moon. Not yet connected to serving.
- Cooking on the gas stove: a pot of oil or water heats by the flame level you set, loses heat to the kitchen, and drops when cold food goes in. Water stops at 100°C and boils away.
- Food cooking physically in oil, water or a dry pot: thickness decides how fast the middle cooks, the surface browns only once it dries, cool oil makes greasy food, too much heat burns it, and overcooked boiled food falls apart.
