# Lighthouse Spirits

A calm cooking game set in a wind-swept coastal lighthouse. Transient spirits, the Warawara, drift in hungry and unsteady. The caretaker cooks for them by hand, watches them grow brighter and lighter, and sends them up to a great moon of spirits. See `CLAUDE.md` for the full vision and `docs/kitchen_plan.md` for the kitchen build plan.

Built with Godot 4.7 (Forward+) in GDScript.

## Running

```sh
# Headless integration suite. Exits 0 on pass, 1 on fail.
godot --headless --path . res://scenes/integration_test.tscn

# Rebuild the global class cache after adding or renaming a class_name script.
godot --headless --editor --quit --path .

# Play the game (the main scene: the outdoor kitchen).
# Walking: WASD to walk, mouse to look, E at the counter to step in, Esc to
# free the mouse (click to take it back).
# At the counter: A/D along the counter (board, stove, press), W/S to look
# out to sea and back, mouse to a screen edge to glance sideways, Esc to
# step back.
#   Board: click a basket for a whole item, drag across the board to cut
#     (hold Space to steady), drag a piece to move it, right-click to roll
#     it, Space + drag to lift it with everything touching it, T to taste.
#   Stove: drag round the knob to turn the gas.
#   Pot: drag inside with the slotted spoon to stir, drag out over the rim
#     to lift what the bowl caught, right-click a piece to turn it, right-click
#     the pot away from food to tip the liquid out.
#   Jug, bottle, cup: drag to lift and hold over the pot to pour;
#     right-click the bottle to pull its cork.
#   Press: click the sunflower head to fill the hopper, drag round the crank
#     to press oil into the cup.
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

- Cooking at the counter, all covered by the suite but not yet play-tested:
  - cutting with the mezzaluna, with the cut line shown on the food as you draw;
  - lighting the stove and setting the flame by hand;
  - pouring oil or water into the pot;
  - lifting cut food into the pot, stirring and turning it, and lifting it out with the slotted spoon;
  - pressing sunflower seeds into oil;
  - tasting.
- Watching food cook: fries ringed by sizzle foam, oil that shimmers as it heats and smokes when abused, steam and smoke in the wind, and food that browns face by face, shrinks, and steams as it rests.

**The simulation underneath**

The kitchen is built simulation-first; these are the systems the counter drives.

- Food pieces with physical state: size, mass, water, oil, temperature, doneness, browning, char, integrity and flavour.
- Mezzaluna cutting: precise axis-aligned cuts that conserve mass, thin slices that crumble, and damage when a perpendicular cut is made without holding the food steady.
- Flavour profiles on seven axes with mass-weighted mixing.
- Ingredient data validation. Potato, chilli, sunflower seeds, water, sunflower oil and sunflower seed cake are authored.
- The oil press: load sunflower seeds, turn the crank, and collect oil and seed cake. Pressing conserves what the seeds contain.
- Chilli oil without a recipe: chilli in warm oil makes it spicy, burnt chilli makes it bitter, and food fried in it picks up the flavour.
- Reading food like a cook: texture, look (browning, char, gloss, translucency) and the sound of a bite all come from the food's physical state. A good fry crackles; greasy or mushy food squelches.
- Dishes with an identity: a plate's fingerprint recognises the same dish made the same way, and tells burnt, raw or differently cut versions apart.
- Nourishment from real food: energy content feeds a spirit, flavour and warmth calm it, and how well the food was made sets how surely it carries the spirit toward the moon. Not yet connected to serving.
- Cooking on the gas stove:
  - A pot of oil or water heats through its metal by the flame you set, and loses heat to the wind and the sky. It drops when cold food goes in.
  - A small flame heats only the middle of the base, which is the hot spot.
  - The metal carries the oil on a little after the flame is turned down.
  - Water evaporates as it heats, stops at 100°C and boils away.
- Food cooking physically, face by face:
  - Every face of a piece cooks by what it touches: hot metal, oil, water or air.
  - Thickness decides how fast the middle cooks, and a wet core never passes 100°C.
  - Surfaces brown only once they dry, cool oil makes greasy food, too much heat burns it, and overcooked boiled food falls apart.
  - Shallow-fried food browns underneath and needs turning.
  - Raw potato sinks in oil, and dried-out fries float.
  - Food shrinks as it loses water.
  - Food left out keeps cooking from its own heat, cools in the wind and goes limp.
- Frying oil wears out: it smokes past 210°C, breaks down faster once smoking, and then tastes acrid and makes greasier, more bitter food.
- Flavour follows solubility: chilli makes chilli oil but not chilli water, and salted water seasons what boils in it.
