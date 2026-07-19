extends Node2D

enum State { IDLE, IDLE_BLOATED, WALK, WALK_BLOATED, HOP, HOP_BLOATED, FALL, KNEEL, LICK, SPIT, HURT, DEATH }
@export var player_controller: PlayerController
@export var animplay: AnimationPlayer
@export var sprite: Sprite2D

# Cache node paths here to save performance
@onready var collision_stand: CollisionShape2D = $"../CollisionStand"
@onready var collision_crouch: CollisionShape2D = $"../CollisionCrouch"
var current_state = State.IDLE

func _process(_delta: float) -> void:
	if not player_controller:
		return
		
	# --- Image Flipping ---
	if player_controller.direction == 1:
		sprite.flip_h = false
		sprite.offset.x = 0
	elif player_controller.direction == -1:
		sprite.flip_h = true
		sprite.offset.x = -5
	
	# --- Collision Toggling (Crouch / Stand) ---
	var is_crouching = player_controller.is_kneeling and player_controller.is_on_floor()
	collision_stand.disabled = is_crouching
	collision_crouch.disabled = not is_crouching

	if player_controller.hp <= 0:
		collision_stand.disabled = true
		collision_crouch.disabled = true
		sprite.flip_h = false

	# --- State Machine Logic ---
	var new_state = determine_player_state()
	if new_state != current_state:
		current_state = new_state
		play_animation_for_state(current_state)
		
	# --- Dynamic Walk Speed Adjustment ---
	if current_state == State.WALK or current_state == State.WALK_BLOATED:
		var current_speed = abs(player_controller.velocity.x)
		animplay.speed_scale = max(current_speed / player_controller.SPEED, 0.25)

func determine_player_state() -> State:
	if player_controller.hp <= 0:
		return State.DEATH

	if player_controller.is_knockback and not player_controller.is_on_floor():
		return State.HURT

	if player_controller.current_state == player_controller.State.ATTACK:
		return State.SPIT if player_controller.is_bloated else State.LICK
		
	# Grounded States
	if player_controller.is_on_floor():
		if player_controller.is_kneeling: 
			return State.KNEEL
		elif player_controller.direction != 0:
			return State.WALK_BLOATED if player_controller.is_bloated else State.WALK
		else:
			return State.IDLE_BLOATED if player_controller.is_bloated else State.IDLE

	# Airborne States
	else: 
		if player_controller.velocity.y < 0:
			return State.HOP_BLOATED if player_controller.is_bloated else State.HOP
		else:
			return State.HOP_BLOATED if player_controller.is_bloated else State.FALL

func play_animation_for_state(state: State) -> void:
	# Reset the speed scale back to default so other states don't play in slow motion!
	animplay.speed_scale = 1.0
	
	match state:
		State.IDLE:
			animplay.play("idle")
			sprite.offset.y = 0
			if player_controller.direction == 1:
				sprite.flip_h = false
			elif player_controller.direction == -1:
				sprite.flip_h = true
		State.IDLE_BLOATED:
			animplay.play("bloated_idle")
			sprite.offset.y = 0
			if player_controller.direction == 1:
				sprite.flip_h = false
			elif player_controller.direction == -1:
				sprite.flip_h = true
		State.WALK:
			animplay.play("walk")
			sprite.offset.y = 0
		State.WALK_BLOATED:
			animplay.play("bloated_walk")
			sprite.offset.y = 0
		State.HOP:
			animplay.play("jump")
			sprite.offset.y = 4
		State.HOP_BLOATED:
			animplay.play("bloated_jump")
			sprite.offset.y = 2
		State.FALL:
			animplay.play("fall")
			sprite.offset.y = 4
		State.KNEEL:
			animplay.play("crouch")
			sprite.offset.y = 0
		State.LICK:
			if player_controller.is_on_floor():
				animplay.play("attack")
			else:
				animplay.play("attack_air")
		State.SPIT:
			if player_controller.is_on_floor():
				animplay.play("attack")
			else:
				animplay.play("attack_air")
		State.HURT:
			animplay.play("hurt")
		State.DEATH:
			animplay.play("death")