class_name KitchenAudio
extends Node

## The kitchen's sound, driven from the simulation. The pot's beds follow
## what is actually happening in it: frying oil hisses as hard as the food
## in it is steaming and crackles as hard as it bubbles, rising in pitch as
## the oil gets hotter; water burbles at the boil; the burner roars with
## its gas. The hands make one-shots: the spark that lights the burner, the
## press's ratchet every eighth of a turn, the blade knocking the board, and
## a bite layered from the five bite sounds by BiteSound's weights and
## pitch. Every sound is synthesised (SoundSynth) unless a recorded sample
## is given for it.

## Steam (g/s) at which frying sizzles at full voice.
const FULL_SIZZLE_STEAM_G_PER_S: float = 0.5
## Oil temperature range over which the sizzle rises in pitch.
const SIZZLE_PITCH_FROM_C: float = 110.0
const SIZZLE_PITCH_TO_C: float = 200.0
## Below this level a bed stops playing.
const SILENT: float = 0.01
## How fast the pouring sound dies away once pouring stops, per second.
const POUR_DECAY_PER_S: float = 5.0
## Grams per second for a full pouring sound.
const FULL_POUR_G_PER_S: float = 40.0
const RATCHET_PER_TURN: int = 8
## Bite layers quieter than this are left out.
const BITE_LAYER_FLOOR: float = 0.05

@export var simulation: KitchenSimulation
@export var stove: StoveView
@export var pot_view: PotView
@export var press_view: PressView
@export var board: CuttingBoard
@export var vessels: Array[PourVesselView] = []
## Recorded bite samples in BiteSound.Layer order (crisp, crunch, soft,
## squelch, chew). Any left empty are synthesised.
@export var recorded_bites: Array[AudioStream] = []

var sizzle: AudioStreamPlayer3D
var crackle: AudioStreamPlayer3D
var boil: AudioStreamPlayer3D
var gas: AudioStreamPlayer3D
var pour: AudioStreamPlayer3D

var _spark: AudioStreamPlayer3D
var _ratchet: AudioStreamPlayer3D
var _knock: AudioStreamPlayer3D
var _sprinkle: AudioStreamPlayer3D
var _plop: AudioStreamPlayer3D
var _set_down: AudioStreamPlayer3D
var _bites: Dictionary[BiteSound.Layer, AudioStreamPlayer] = {}
var _pouring: float = 0.0
var _turns_since_click: float = 0.0

func _ready() -> void:
	sizzle = _bed_player(SoundSynth.Bed.SIZZLE, pot_view, -6.0)
	crackle = _bed_player(SoundSynth.Bed.CRACKLE, pot_view, -8.0)
	boil = _bed_player(SoundSynth.Bed.BOIL, pot_view, -6.0)
	gas = _bed_player(SoundSynth.Bed.GAS, stove, -18.0)
	pour = _bed_player(SoundSynth.Bed.POUR, pot_view, -10.0)
	_spark = _shot_player(SoundSynth.shot(SoundSynth.Shot.SPARK), stove, -8.0)
	_ratchet = _shot_player(SoundSynth.shot(SoundSynth.Shot.RATCHET), press_view, -10.0)
	_knock = _shot_player(SoundSynth.shot(SoundSynth.Shot.KNOCK), board, -6.0)
	_sprinkle = _shot_player(SoundSynth.shot(SoundSynth.Shot.SPRINKLE), board, -14.0)
	_plop = _shot_player(SoundSynth.shot(SoundSynth.Shot.PLOP), pot_view, -10.0)
	_set_down = _shot_player(SoundSynth.shot(SoundSynth.Shot.SET_DOWN), board, -12.0)
	for layer in BiteSound.Layer.values():
		var player := AudioStreamPlayer.new()
		var recorded: AudioStream = recorded_bites[layer] if layer < recorded_bites.size() else null
		player.stream = recorded if recorded else SoundSynth.bite(layer)
		add_child(player)
		_bites[layer] = player
	stove.lit.connect(func() -> void: _spark.play())
	press_view.cranked.connect(_on_cranked)
	board.pieces_cut.connect(func(_count: int, _steadied: bool) -> void: _knock.play())
	board.bitten.connect(play_bite)
	board.piece_placed.connect(func(_view: FoodPieceView) -> void: play_at(_set_down, board.global_position))
	pot_view.pieces_dropped_in.connect(func(_count: int) -> void:
		if simulation.pot.has_pool() and simulation.pot.medium.fat_fraction < 0.5:
			_plop.play())
	for vessel in vessels:
		vessel.poured.connect(func(grams: float) -> void: _pouring += grams)

## A pinch of spice let go at a point patters down there.
func play_sprinkle(at: Vector3) -> void:
	play_at(_sprinkle, at)

## Plays a one-shot from a point, a touch higher or lower each time so a
## run of them doesn't sound mechanical.
func play_at(player: AudioStreamPlayer3D, at: Vector3) -> void:
	player.global_position = at
	player.pitch_scale = randf_range(0.92, 1.08)
	player.play()

## Plays a bite: each layer at its weight, pitched for the piece's size.
func play_bite(sound: BiteSound) -> void:
	for layer in sound.weights:
		var weight: float = sound.weights[layer]
		if weight < BITE_LAYER_FLOOR:
			continue
		var player := _bites[layer]
		player.volume_db = linear_to_db(weight)
		player.pitch_scale = sound.pitch
		player.play()

func _process(delta: float) -> void:
	var pot := simulation.pot
	var oily: bool = pot.has_pool() and pot.medium.fat_fraction > 0.5
	var watery: bool = pot.has_pool() and not oily
	# Net steam dips below zero for a moment when cold food condenses vapour
	# onto itself; that is silence, not a sizzle.
	var steaming: float = clampf(sqrt(maxf(pot.steam_g_per_s, 0.0) / FULL_SIZZLE_STEAM_G_PER_S), 0.0, 1.0)
	_set_level(sizzle, steaming if oily else 0.0)
	sizzle.pitch_scale = lerpf(0.85, 1.2, clampf((pot.temp_c - SIZZLE_PITCH_FROM_C) / (SIZZLE_PITCH_TO_C - SIZZLE_PITCH_FROM_C), 0.0, 1.0))
	_set_level(crackle, clampf(pot.bubbling * 1.6, 0.0, 1.0) if oily else 0.0)
	var simmer: float = clampf((pot.temp_c - 75.0) / 25.0, 0.0, 1.0) * 0.25 if watery else 0.0
	_set_level(boil, maxf(pot.bubbling, simmer) if watery else 0.0)
	var flame: float = simulation.stove.effective_level(pot.flame_level) if simulation.stove else pot.flame_level
	_set_level(gas, lerpf(0.3, 1.0, flame) if flame > 0.0 else 0.0)
	_set_level(pour, clampf(_pouring / maxf(delta, 0.001) / FULL_POUR_G_PER_S, 0.0, 1.0))
	_pouring = 0.0

func _on_cranked(turns: float) -> void:
	_turns_since_click += turns
	var click_every: float = 1.0 / RATCHET_PER_TURN
	if _turns_since_click >= click_every:
		_turns_since_click = fmod(_turns_since_click, click_every)
		_ratchet.play()

static func _set_level(player: AudioStreamPlayer3D, level: float) -> void:
	if level < SILENT:
		if player.playing:
			player.stop()
		return
	player.volume_db = player.get_meta(&"base_db", 0.0) + linear_to_db(level)
	if not player.playing:
		player.play()

func _bed_player(kind: SoundSynth.Bed, at: Node3D, base_db: float) -> AudioStreamPlayer3D:
	var player := _shot_player(SoundSynth.bed(kind), at, base_db)
	player.set_meta(&"base_db", base_db)
	return player

func _shot_player(stream: AudioStream, at: Node3D, base_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = base_db
	player.unit_size = 1.5
	at.add_child(player)
	return player
