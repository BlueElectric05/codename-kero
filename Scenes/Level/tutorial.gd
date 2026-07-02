extends Node2D
class_name MapRoot

func _ready() -> void:
	call_deferred("_position_player")

func _position_player() -> void:
	var player := find_child("Player", true, false)
	if player == null:
		return

	var spawn_name := GameState.next_spawn_point
	var spawn_point: Node = null

	if spawn_name != "":
		spawn_point = find_child(spawn_name, true, false)
	if spawn_point == null:
		spawn_point = find_child("SpawnPoint", true, false)
	if spawn_point == null:
		return

	player.global_position = spawn_point.global_position
	GameState.next_spawn_point = ""
