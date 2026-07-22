extends Camera2D

@export var player : PlayerController


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_instance_valid(player):
		position = player.global_position
