extends CharacterBody2D
class_name PlayerController

# ==========================================
# STATE
# ==========================================

enum State { IDLE, MOVE, AIR, KNEEL, ATTACK, KO }
var current_state: State = State.IDLE

# ==========================================
# NODE REFERENCES
# ==========================================

@onready var progress_bar: ProgressBar = $"../UI/Health Bar/ProgressBar"
@onready var sprite: Sprite2D = $Animation/Sprite2D       # adjust to your actual sprite node path
@onready var inv_timer: Timer = $Invulnerability
@onready var anim_player: AnimationPlayer = $Animation/AnimationPlayer  # adjust to your actual path
@onready var charge: CPUParticles2D = $charge

# ==========================================
# TUNING / EXPORTS
# ==========================================

@export var SPEED: int = 140
@export var SPEED_BLOATED: int = 80
@export var JUMP_VELOCITY: int = -400
@export var CHARGED_JUMP_VELOCITY: int = -600
@export var GRAVITY: int = 550

@export_range(0.0, 1.0) var friction: float = 0.3
@export_range(0.0, 1.0) var acceleration: float = 0.2

@export var max_hp: int = 5

@export var KNOCKBACK_X: float = 150.0
@export var KNOCKBACK_Y: float = -100.0
@export var INVULN_TIME: float = 1.0

@export var RESPAWN_FALL_Y: float = 256.0
@export var RESPAWN_POSITION: Vector2 = Vector2(40, 40)

@export var max_charge_time: float = 1.0

# ==========================================
# RUNTIME STATE
# ==========================================

var hp: int
var direction: float = 0.0
var last_facing: int = 1
var roll_instance: Node = null

var is_bloated: bool = false
var is_kneeling: bool = false
var was_in_air: bool = false
var can_jump: bool = true
var is_attacking: bool = false
var on_platform_layer: bool = false
var is_ko: bool = false
var is_invulnerable: bool = false
var is_knockback: bool = false

var charge_time: float = 0.0

# ==========================================
# LIFECYCLE
# ==========================================

func _ready() -> void:
	hp = max_hp

	inv_timer.wait_time = INVULN_TIME
	inv_timer.one_shot = true
	inv_timer.timeout.connect(_on_invuln_timer_timeout)

func _physics_process(delta: float) -> void:
	# 1. GLOBAL CHECKS (happen regardless of state)
	handle_respawn()
	apply_gravity()
	update_inputs()
	check_one_way_platforms()
	
	charge.emitting = false
	# 2. STATE EXECUTION
	if is_ko:
		current_state = State.KO  # KO overrides whatever state we'd otherwise be in

	# Safety reset: if we leave KNEEL any other way (got hit, walked off a
	# ledge, etc.) without releasing "hop", don't carry leftover charge
	# into the next crouch.
	if current_state != State.KNEEL and charge_time > 0.0:
		charge_time = 0.0
		_reset_charge_visual()

	match current_state:
		State.IDLE:
			state_idle()
		State.MOVE:
			state_move()
		State.AIR:
			state_air()
			was_in_air = true
		State.KNEEL:
			state_kneel()
		State.ATTACK:
			state_attack()
		State.KO:
			state_ko()

	if was_in_air and current_state != State.AIR:
		_on_landed()

	# 3. APPLY PHYSICS
	move_and_slide()

	# 4. DETERMINE NEXT STATE (for next frame)
	update_state_transitions()

func _on_landed() -> void:
	AudioManager.play_unique(AudioManager.step)
	Particles.play_effect("dust2", global_position)
	was_in_air = false
	is_knockback = false

	# If we landed mid-invulnerability (e.g. just took knockback), keep blinking
	if is_invulnerable:
		anim_player.play("blinking")

# ==========================================
# STATE BEHAVIORS
# ==========================================

func state_idle() -> void:
	velocity.x = lerp(velocity.x, 0.0, friction)

	if Input.is_action_just_pressed("hop") and is_on_floor():
		jump()

func state_move() -> void:
	var target_speed: int = SPEED_BLOATED if is_bloated else SPEED
	velocity.x = lerp(velocity.x, direction * float(target_speed), acceleration)

	if Input.is_action_just_pressed("hop") and is_on_floor():
		jump()

func state_air() -> void:
	if is_knockback:
		return

	if direction != 0:
		var target_speed: int = SPEED_BLOATED if is_bloated else SPEED
		velocity.x = lerp(velocity.x, direction * float(target_speed), acceleration)
	else:
		velocity.x = lerp(velocity.x, 0.0, friction)

	if Input.is_action_just_pressed("hop") and can_jump:
		jump()

func state_kneel() -> void:
	velocity.x = lerp(velocity.x, 0.0, friction)

	# Check release FIRST, using whatever charge has built up so far this
	# frame — if we zero charge_time in a branch below before this check
	# runs, the jump never fires (this was the original bug).
	if Input.is_action_just_released("hop") and charge_time > 0.0:
		var charged := charge_time >= max_charge_time
		jump(charged)
		charge_time = 0.0
		_reset_charge_visual()
		return

	if Input.is_action_pressed("hop"):
		charge_time = min(charge_time + get_physics_process_delta_time(), max_charge_time)
		_update_charge_visual()
	else:
		if charge_time > 0.0:
			_reset_charge_visual()
		charge_time = 0.0

func state_attack() -> void:
	velocity.x = lerp(velocity.x, 0.0, friction)

func state_ko() -> void:
	velocity.x = lerp(velocity.x, 0.0, friction)

# ==========================================
# HELPER FUNCTIONS
# ==========================================

func update_state_transitions() -> void:
	if current_state == State.KO:
		return

	if not is_on_floor():
		current_state = State.AIR
	elif is_kneeling:
		current_state = State.KNEEL
	elif direction != 0:
		current_state = State.MOVE
	else:
		current_state = State.IDLE

func update_inputs() -> void:
	if is_knockback:
		direction = 0
		return

	direction = Input.get_axis("left", "right")
	is_kneeling = Input.is_action_pressed("kneel")

	if direction != 0:
		last_facing = int(sign(direction))

func apply_gravity() -> void:
	if not is_on_floor():
		velocity.y = lerpf(velocity.y, GRAVITY, 0.02)

func check_one_way_platforms() -> void:
	on_platform_layer = false
	if not is_on_floor():
		return

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision.get_normal() == Vector2.UP:
			var collider := collision.get_collider()
			if collider and get_collision_mask_value(10):
				on_platform_layer = true
				break

func drop_through_platform() -> void:
	# Temporarily ignore the one-way platform layer so the player falls through.
	# NOTE: this is never re-enabled elsewhere — confirm something (a timer,
	# landing check, etc.) turns mask layer 10 back on, or the player will
	# permanently ignore one-way platforms after the first drop-through.
	set_collision_mask_value(10, false)

func handle_respawn() -> void:
	if position.y > RESPAWN_FALL_Y:
		position = RESPAWN_POSITION

func jump(charged: bool = false) -> void:
	if not charged:
		AudioManager.play_unique(AudioManager.step)
	else:
		Particles.play_effect("dust", global_position)
		AudioManager.play_unique(AudioManager.superjump)
	velocity.y = CHARGED_JUMP_VELOCITY if charged else JUMP_VELOCITY
	can_jump = false
	if has_node("CoyoteTimer"):
		$CoyoteTimer.stop()

func _update_charge_visual() -> void:
	if charge_time >= max_charge_time:
		# Fully charged: hold solid white so the player knows to let go.
		anim_player.play("charging")
		charge.emitting = true
	else:
		AudioManager.play_unique(AudioManager.charge)
		charge.emitting = false
		_reset_charge_visual()


func _reset_charge_visual() -> void:
	sprite.material.set_shader_parameter("enabled", false)

func reduceHP() -> void:
	if is_invulnerable:
		return  # ignore damage while invulnerable

	hp -= 1
	progress_bar.value = hp

	apply_knockback()

	if hp <= 0:
		is_ko = true

func apply_knockback() -> void:
	# Knock away from facing direction
	velocity.x = -last_facing * KNOCKBACK_X
	velocity.y = KNOCKBACK_Y

	is_knockback = true
	is_invulnerable = true

	# Disable collisions during knockback/invuln window
	set_collision_layer_value(1, false)  # adjust layer index to your player's collision layer
	set_collision_mask_value(1, false)   # adjust to whichever mask(s) you want ignored

	current_state = State.AIR
	was_in_air = true

	inv_timer.start()
	anim_player.play("blink")

func _on_invuln_timer_timeout() -> void:
	is_invulnerable = false
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	anim_player.stop()
	sprite.visible = true
	sprite.modulate.a = 1.0

func _on_coyote_timer_timeout() -> void:
	can_jump = false
