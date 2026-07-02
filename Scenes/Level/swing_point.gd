extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _on_body_entered(body: Node2D) -> void:
	print("SwingPoint kena BODY: ", body.name)
	_flash()

func _on_area_entered(area: Area2D) -> void:
	print("SwingPoint kena AREA: ", area.name)
	_flash()

func _flash() -> void:
	# feedback visual sementara biar keliatan tanpa buka console
	var sprite := get_parent().get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = Color.GREEN
		await get_tree().create_timer(0.3).timeout
		sprite.modulate = Color.WHITE
