class_name KitchenSimulation
extends Node

## Owns every simulation object in the outdoor kitchen and advances them
## all in _physics_process: the pot on the stove, the food resting on the
## board, food held in the air on the spoon, and the oil press. Scene nodes
## only wrap these objects - they read their state to draw it and turn the
## player's hands into calls on them - so no scene script holds food logic.

@export var air: KitchenAir
@export var vessel: CookingVessel
@export var stove: HeatSource
@export var press_equipment: KitchenEquipment
## Liquids the counter offers.
@export var oil: Ingredient
@export var water: Ingredient
@export var seeds: Ingredient
@export var seed_cake: Ingredient
## How much the oil cup and bottle hold, in grams.
@export var cup_capacity_g: float = 230.0
@export var bottle_capacity_g: float = 700.0
@export var jug_capacity_g: float = 2000.0
## Most seeds the press's hopper takes, in grams.
@export var hopper_capacity_g: float = 250.0

var pot: CookingPot
var board: RestingSurface
## Food held up in the air - on the spoon, or in the hand.
var held: RestingSurface
var press: ManualProcessor
var cup: LiquidStore
var bottle: LiquidStore
var jug: LiquidStore
## Seed cake the press has pushed out, in grams.
var cake_g: float = 0.0

func _ready() -> void:
	if air == null:
		air = KitchenAir.new()
	pot = CookingPot.new(vessel, air.temp_c, air)
	pot.burner = stove
	board = RestingSurface.new(air)
	held = RestingSurface.new(air, 0.0, 0.0)
	press = ManualProcessor.new(press_equipment, Transformation.load_catalog())
	cup = LiquidStore.new(cup_capacity_g, air.temp_c)
	bottle = LiquidStore.new(bottle_capacity_g, air.temp_c)
	jug = LiquidStore.new(jug_capacity_g, air.temp_c, water, true)

func _physics_process(delta: float) -> void:
	pot.advance(delta)
	board.advance(delta)
	held.advance(delta)

## Puts seeds in the press's hopper, up to what it holds. Returns grams
## loaded.
func load_seeds(grams: float) -> float:
	var room: float = hopper_capacity_g - press.loaded_g
	var loading: float = minf(grams, room)
	if loading <= 0.0 or not press.load_input(seeds, loading):
		return 0.0
	return loading

## Applies crank turns to the press and sends what comes out where it
## goes: oil into the cup (if it sits under the spout - otherwise it runs
## onto the counter), seed cake out of the end of the barrel. Returns the
## grams of oil that came out.
func crank(turns: float, cup_under_spout: bool) -> float:
	if press.work(turns) <= 0.0:
		return 0.0
	var oil_g: float = press.take_output(oil)
	cake_g += press.take_output(seed_cake)
	if cup_under_spout and oil_g > 0.0:
		cup.receive(oil, oil_g, oil.flavour, air.temp_c)
	return oil_g

## Pours from a store into the pot for dt seconds at the given rate, and
## returns grams poured. Refused (0) when the pot can't take that liquid.
func pour_into_pot(store: LiquidStore, rate_g_per_s: float, dt: float) -> float:
	if store.ingredient == null or store.is_empty():
		return 0.0
	var wanted: float = rate_g_per_s * dt
	if not store.unlimited:
		wanted = minf(wanted, store.grams)
	if wanted <= 0.0 or not pot.add_medium(store.ingredient, wanted, store.temp_c, store.flavour, store.traits):
		return 0.0
	return store.draw(wanted)

## Pours from one store into another and returns grams moved.
func pour_into(store: LiquidStore, target: LiquidStore, rate_g_per_s: float, dt: float) -> float:
	if store.ingredient == null or store.is_empty():
		return 0.0
	var wanted: float = rate_g_per_s * dt
	if not store.unlimited:
		wanted = minf(wanted, store.grams)
	var moved: float = target.receive(store.ingredient, wanted, store.flavour, store.temp_c, store.traits)
	store.draw(moved)
	return moved
