extends Node2D

@onready var dust = $dust
@onready var dust2 = $dust2
@onready var charge = $charge
@onready var dustsplode = $dustsplode

func play_effect(effect_name: String, position: Vector2):
	var effect: Node2D = null

	match effect_name:
		"dust":
			effect = dust
		"dust2":
			effect = dust2
		"charge":
			effect = charge
		"dustsplode":
			effect = dustsplode

	if effect:
		effect.global_position = position
		effect.restart()  
