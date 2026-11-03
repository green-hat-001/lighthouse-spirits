class_name DishBook
extends RefCounted

## The caretaker's own names for the dishes they have made, kept by
## fingerprint, and which of them they have put up for service. A dish is
## never authored: it is named the first time the player plates it and
## names it, and recognised whenever it is made the same way again. Kept
## in user://dish_book.cfg.

const PATH: String = "user://dish_book.cfg"

static var _names: Dictionary[String, String] = {}
static var _on_menu: Dictionary[String, bool] = {}
static var _loaded: bool = false

static func name_of(fingerprint: String) -> String:
	_ensure_loaded()
	return _names.get(fingerprint, "")

static func is_named(fingerprint: String) -> bool:
	return name_of(fingerprint) != ""

## Names a dish, or forgets its name if `dish_name` is blank, and saves.
static func name_dish(fingerprint: String, dish_name: String) -> void:
	_ensure_loaded()
	var trimmed := dish_name.strip_edges()
	if trimmed == "":
		_names.erase(fingerprint)
		_on_menu.erase(fingerprint)
	else:
		_names[fingerprint] = trimmed
	save()

static func is_on_menu(fingerprint: String) -> bool:
	_ensure_loaded()
	return _on_menu.get(fingerprint, false)

## Puts a named dish up for service, or takes it off. Unnamed dishes can't
## go on the menu.
static func set_on_menu(fingerprint: String, on_menu: bool) -> bool:
	if not is_named(fingerprint):
		return false
	_on_menu[fingerprint] = on_menu
	save()
	return true

## Every named dish on the menu, by name.
static func menu() -> PackedStringArray:
	_ensure_loaded()
	var names := PackedStringArray()
	for fingerprint in _on_menu:
		if _on_menu[fingerprint] and _names.has(fingerprint):
			names.append(_names[fingerprint])
	names.sort()
	return names

static func save() -> Error:
	var config := ConfigFile.new()
	for fingerprint in _names:
		config.set_value("names", fingerprint, _names[fingerprint])
		config.set_value("menu", fingerprint, _on_menu.get(fingerprint, false))
	return config.save(PATH)

static func load_saved() -> bool:
	_loaded = true
	_names.clear()
	_on_menu.clear()
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return false
	if config.has_section("names"):
		for fingerprint in config.get_section_keys("names"):
			_names[fingerprint] = str(config.get_value("names", fingerprint))
			_on_menu[fingerprint] = bool(config.get_value("menu", fingerprint, false))
	return true

## Forgets every name in memory (the saved book is untouched until the next
## save).
static func reset() -> void:
	_loaded = true
	_names.clear()
	_on_menu.clear()

static func _ensure_loaded() -> void:
	if not _loaded:
		load_saved()
