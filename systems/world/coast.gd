class_name Coast
extends Node3D

## The outdoor setting around the kitchen: sky, sea, cliff top, grass,
## lighthouse. Dresses the imported models with what glTF can't carry: the
## lighthouse lamp gets a glowing material and a warm light of its own, and
## the grass field gets the wind shader.

const GRASS_SHADER: Shader = preload("res://shaders/coast_grass.gdshader")

@export var lamp_color: Color = Color(1.0, 0.86, 0.55)
@export var lamp_glow: float = 4.0
@export var lamp_light_range_m: float = 14.0

@onready var _lighthouse: Node3D = $Lighthouse
@onready var _grass: Node3D = $Grass

func _ready() -> void:
	_light_lamp()
	var blades := ShaderMaterial.new()
	blades.shader = GRASS_SHADER
	for mesh in _grass.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		instance.material_override = blades
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _light_lamp() -> void:
	var lamp := _lighthouse.find_child("lamp", true, false) as MeshInstance3D
	if lamp == null:
		return
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = lamp_color
	glow.emission_enabled = true
	glow.emission = lamp_color
	glow.emission_energy_multiplier = lamp_glow
	lamp.material_override = glow
	var light := OmniLight3D.new()
	light.light_color = lamp_color
	light.light_energy = 2.0
	light.omni_range = lamp_light_range_m
	lamp.add_child(light)
	light.position = lamp.get_aabb().get_center()
