extends Node2D
class_name TongueAttack

enum TongueState { INACTIVE, EXTENDING, RETRACTING }
var current_state: TongueState = TongueState.INACTIVE

@export var max_length: float = 60.0
@export var extension_speed: float = 0.15 # Time in seconds to reach full length
@export var retraction_speed: float = 0.15 # Time in seconds to pull back

@onready var line_2d: Line2D = $Line2D
@onready var tip_sprite: Sprite2D = $TipSprite
@onready var hitbox: Area2D = $TipSprite/Hitbox

var current_length: float = 0.0
var tongue_direction: Vector2 = Vector2.RIGHT
var target_length: float = 0.0
var tween: Tween

signal attack_finished

func _ready() -> void:
	# Clear any editor design lines and hide the tongue initially
	line_2d.clear_points()
	line_2d.add_point(Vector2.ZERO) # Start point (mouth)
	line_2d.add_point(Vector2.ZERO) # End point (tip)
	visible = false
	hitbox.monitoring = false

func _physics_process(_delta: float) -> void:
	if current_state == TongueState.INACTIVE:
		return
		
	# Update the visual line and tip position dynamically
	var tip_position = tongue_direction * current_length
	
	line_2d.set_point_position(1, tip_position)
	tip_sprite.position = tip_position

func start_attack(facing_direction: int) -> void:
	if current_state != TongueState.INACTIVE:
		return
		
	# Set direction based on player facing (1 for right, -1 for left)
	tongue_direction = Vector2(facing_direction, 0).normalized()
	current_length = 0.0
	visible = true
	hitbox.monitoring = true
	current_state = TongueState.EXTENDING
	
	# Smoothly animate extension using a Tween
	if tween: tween.kill()
	tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "current_length", max_length, extension_speed)
	tween.tween_callback(_on_extended_fully)

func _on_extended_fully() -> void:
	current_state = TongueState.RETRACTING
	
	# Smoothly animate retraction
	if tween: tween.kill()
	tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "current_length", 0.0, retraction_speed)
	tween.tween_callback(_reset_tongue)

func _reset_tongue() -> void:
	current_state = TongueState.INACTIVE
	visible = false
	hitbox.monitoring = false
	attack_finished.emit()

# --- Hitbox Interaction ---
func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") or body.is_in_group("collectibles"):
		if body.has_method("get_caught"):
			body.get_caught(tip_sprite)
			
		_on_extended_fully()