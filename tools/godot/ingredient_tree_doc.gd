extends SceneTree
## Writes docs/ingredient_tree.md from the live catalog and food web, so the
## guide always shows what the game actually computes - including every
## essence a creature's parts inherit from its diet. Run after changing any
## ingredient, essence or species:
##   godot --headless --path . -s res://tools/godot/ingredient_tree_doc.gd
const EFFECT := ["lift", "glow", "ember", "frost", "char ward", "bloom", "soothe", "nourish"]
const TRIGGER := ["always", "raw", "once cooked", "once browned", "when hot", "once charred"]
const TISSUE := ["muscle", "fat", "skin", "bone", "organ", "eye", "keratin", "roe", "blood"]
const SHELF := ["", "Garden", "Catch", "Spices", "Grains"]
func essences(ingredient: Ingredient) -> String:
	var doses := ingredient.trait_doses()
	var parts: PackedStringArray = []
	for t in doses.traits():
		var inherited: bool = ingredient.inherited_traits.has(t)
		parts.append("%s %.2f%s" % [t.display_name, doses.get_dose(t), " (from its diet)" if inherited and not _authored(ingredient, t) else ""])
	return ", ".join(parts) if not parts.is_empty() else "none"
func _authored(ingredient: Ingredient, t: MysticTrait) -> bool:
	for d in ingredient.traits:
		if d.mystic_trait == t:
			return true
	return false
func _init() -> void:
	var lines: PackedStringArray = []
	lines.append("# The coast's ingredient tree")
	lines.append("")
	lines.append("Generated from the live catalog (`IngredientCatalog`) after the food web resolved, so every inherited essence shown is what the game computes. The `.tres` files under `data/` are the source of truth. Regenerate this page if they change.")
	lines.append("")
	lines.append("## Essences")
	lines.append("")
	lines.append("| Essence | Effect | Wakes | Dissolves into | Travels by diet into | Lore |")
	lines.append("|---|---|---|---|---|---|")
	for file_name in DirAccess.get_files_at("res://data/traits"):
		if not file_name.ends_with(".tres"):
			continue
		var t := load("res://data/traits/" + file_name) as MysticTrait
		var wakes: String = TRIGGER[t.trigger] + ("" if t.trigger == 0 else (" (%.0f°C)" % t.trigger_threshold if t.trigger == 4 else " (%.1f)" % t.trigger_threshold))
		var into: PackedStringArray = []
		if t.fat_solubility > 0.0: into.append("fat")
		if t.water_solubility > 0.0: into.append("water")
		var tissues: PackedStringArray = []
		for tissue in t.tissues: tissues.append(TISSUE[tissue])
		lines.append("| **%s** | %s ×%.2f | %s | %s | %s | %s |" % [t.display_name, EFFECT[t.effect], t.magnitude, wakes, ", ".join(into) if not into.is_empty() else "nothing",
			("%s (share %.1f)" % [", ".join(tissues), t.diet_share]) if t.carried_by_diet else "-", t.lore])
	lines.append("")
	for shelf in [1, 3, 4]:
		lines.append("## %s" % SHELF[shelf])
		lines.append("")
		lines.append("| Ingredient | Essences | Lore |")
		lines.append("|---|---|---|")
		for ingredient in IngredientCatalog.on_shelf(shelf):
			lines.append("| **%s** | %s | %s |" % [ingredient.display_name, essences(ingredient), ingredient.lore])
		lines.append("")
	lines.append("## Species")
	lines.append("")
	for creature in IngredientCatalog.creatures():
		lines.append("### %s" % creature.display_name)
		lines.append("")
		lines.append("*%s.* %s" % [creature.habitat, creature.lore])
		lines.append("")
		var counts := {}
		for food in creature.diet: counts[food.display_name] = counts.get(food.display_name, 0) + 1
		var diet: PackedStringArray = []
		for food_name in counts: diet.append(food_name if counts[food_name] == 1 else "%s ×%d" % [food_name, counts[food_name]])
		lines.append("**Eats:** %s (weighted by how much of each). %s" % [", ".join(diet), "Dressed in the field: the pantry's catch shelf offers its parts." if creature.dressed_in_field else "Comes whole to the board: the first mezzaluna stroke opens it into its parts."])
		lines.append("")
		lines.append("| Part | Tissue | Count | Essences | Edible | Uses |")
		lines.append("|---|---|---|---|---|---|")
		for part in creature.parts:
			lines.append("| **%s** | %s | %d | %s | %s | %s |" % [part.part_name, TISSUE[part.tissue], part.count, essences(part.ingredient),
				"yes" if part.ingredient.edible_share >= 1.0 else ("no" if part.ingredient.edible_share <= 0.0 else "%d%%" % roundi(part.ingredient.edible_share * 100.0)), part.uses])
		lines.append("")
	var file := FileAccess.open("res://docs/ingredient_tree.md", FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("wrote ", lines.size(), " lines")
	quit()
