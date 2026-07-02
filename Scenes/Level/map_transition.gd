extends Area2D

@export var target_scene_path: String = "res://Scenes/Level/Map-2.tscn"
@export var target_spawn_name: String = "SpawnPoint"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	print("Body masuk: ", body.name, " groups: ", body.get_groups())
	if body.is_in_group("player"):
		GameState.next_spawn_point = target_spawn_name
		get_tree().change_scene_to_file(target_scene_path)
