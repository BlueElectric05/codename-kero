extends Node

@onready var player: Node = $Player
@onready var life_counter: Label = $UI/Label
var totalscore : int = 0
var health : int = 5
var life : int = 3

func _ready() -> void:
	life = 3
	totalscore = 0
	
	if life_counter:
		life_counter.text = str("x",life)


func reduce_life() -> void:

	print("life reduced")
	life -= 1

	if life < 0:
		life = 0

	if life_counter:
		life_counter.text = str("x",life)
