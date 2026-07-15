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
@onready var sprite: Sprite2D = $Animation/Sprite2D       
@onready var inv_timer: Timer = $Invulnerability
@onready var anim_player: AnimationPlayer = $Animation/AnimationPlayer  
@onready var charge: CPUParticles2D = $charge
@onready var tongue: TongueAttack = $Tongue

# ==========================================
# TUNING / EXPORTS
# ==========================================

@export var SPEED: int = 140
@export var SPEED_BLOATED: int = 80
@export var JUMP_VELOCITY: int = -400
@export var CHARGED_JUMP_VELOCITY: int = -600
@export var JUMP_VELOCITY_BLOATED: int = -320
@export var CHARGED_JUMP_VELOCITY_BLOATED: int = -450
@export var GRAVITY: int = 550

@export_range(0.0, 1.0) var friction: float = 0.3
@export_range(0.0, 1.0) var acceleration: float = 0.2

@export var max_hp: int = 5

@export var KNOCKBACK_X: float = 150.0
@export var KNOCKBACK_Y: float = -100.0
@export var INVULN_TIME: float = 1.0
@export var BLINK_INTERVAL: float = 0.01  # How fast the sprite flashes (in seconds)

@export var RESPAWN_FALL_Y: float = 256.0
@export var RESPAWN_POSITION: Vector2 = Vector2(40, 40)

@export var max_charge_time: float = 0.5

@export var spit_duration: float = 0.35    # How long the spit attack locks the player in place

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

var on_platform_layer: bool = false
var is_ko: bool = false
var is_invulnerable: bool = false
var is_knockback: bool = false

var charge_time: float = 0.0
var blink_timer: float = 0.0  # Tracks our code-based flashing time

var last_eaten_enemy: Node = null  # The actual swallowed enemy, dormant, waiting to be spat out
var spit_timer: float = 0.0        # Counts down during the spit attack

# ==========================================
# LIFECYCLE
# ==========================================

func _ready() -> void:
	hp = max_hp
	add_to_group("player")
	inv_timer.wait_time = INVULN_TIME
	inv_timer.one_shot = true
	inv_timer.timeout.connect(_on_invuln_timer_timeout)

func _physics_process(delta: float) -> void:
	# 1. GLOBAL CHECKS (happen regardless of state)
	handle_respawn()
	apply_gravity()
	update_inputs()
	check_one_way_platforms()
	
	# --- Code-Based Blinking Mechanism ---
	if is_invulnerable and anim_player.current_animation != "hurt" and hp > 0:  
		blink_timer += delta
		if blink_timer >= BLINK_INTERVAL:
			blink_timer = 0.0
			sprite.visible = not sprite.visible  
	else:
		sprite.visible = true  
	# -------------------------------------
	
	charge.emitting = false

	# 2. STATE INTERRUPTS
	if is_ko:
		current_state = State.KO  

	if current_state != State.KNEEL and charge_time > 0.0:
		charge_time = 0.0
		_reset_charge_visual()

	if Input.is_action_just_pressed("lick") and not is_knockback and current_state != State.KO and current_state != State.ATTACK and current_state != State.KNEEL:
		if is_bloated:
			if tongue.current_state == TongueAttack.TongueState.INACTIVE:
				current_state = State.ATTACK
				_start_spit_attack()
		else:
			if tongue.current_state == TongueAttack.TongueState.INACTIVE:
				current_state = State.ATTACK
				tongue.start_attack(last_facing)

	# 3. STATE EXECUTION
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

	# 4. APPLY PHYSICS
	move_and_slide()

	# 5. DETERMINE NEXT STATE & LANDING (Post-movement update)
	update_state_transitions()

	if was_in_air and current_state != State.AIR:
		_on_landed()

func _on_landed() -> void:
	AudioManager.play_unique(AudioManager.step)
	Particles.play_effect("dust2", global_position)
	was_in_air = false
	is_knockback = false

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
	# Stop moving horizontally during tongue/spit action (Yoshi commitment)
	velocity.x = lerp(velocity.x, 0.0, friction)

	# Bloated players spit the eaten enemy instead of using the tongue.
	# This branch is timed by spit_timer instead of the tongue state machine.
	if spit_timer > 0.0:
		spit_timer -= get_physics_process_delta_time()
		if spit_timer <= 0.0:
			# Bloated state is spent once the spit attack finishes
			is_bloated = false
			current_state = State.IDLE
		return

	# Return to normal state loops once tongue retracts completely
	if tongue.current_state == TongueAttack.TongueState.INACTIVE:
		current_state = State.IDLE

func state_ko() -> void:
	velocity.y = 0
	velocity.x = lerp(velocity.x, 0.0, friction)
	if anim_player.current_animation == "death":
		if sprite.frame == 31:
			Particles.play_effect("dustsplode", global_position)
			sprite.visible = false

# ==========================================
# HELPER FUNCTIONS
# ==========================================

func update_state_transitions() -> void:
	if current_state == State.KO:
		return
	if spit_timer > 0.0:
		return
	if tongue.current_state != TongueAttack.TongueState.INACTIVE:
		current_state = State.ATTACK
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
	if is_knockback or current_state == State.ATTACK:
		direction = 0
		return

	direction = Input.get_axis("left", "right")

	if not is_bloated:
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

	var normal_velocity: int = CHARGED_JUMP_VELOCITY if charged else JUMP_VELOCITY
	var bloated_velocity: int = CHARGED_JUMP_VELOCITY_BLOATED if charged else JUMP_VELOCITY_BLOATED
	velocity.y = bloated_velocity if is_bloated else normal_velocity

	can_jump = false
	if has_node("CoyoteTimer"):
		$CoyoteTimer.stop()

func _update_charge_visual() -> void:
	if charge_time >= max_charge_time:
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
		return  

	hp -= 1
	progress_bar.value = hp

	apply_knockback()
	AudioManager.play_unique(AudioManager.ouch)
	if hp <= 0:
		is_ko = true

func apply_knockback() -> void:
	velocity.x = -last_facing * KNOCKBACK_X
	velocity.y = KNOCKBACK_Y

	is_knockback = true
	is_invulnerable = true
	blink_timer = 0.0  

	set_collision_layer_value(1, false)  
	set_collision_mask_value(1, false)   

	current_state = State.AIR
	was_in_air = true

	inv_timer.start()

func _on_invuln_timer_timeout() -> void:
	is_invulnerable = false
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	
	sprite.visible = true
	sprite.modulate.a = 1.0

func _on_coyote_timer_timeout() -> void:
	can_jump = false

# ==========================================
# BLOATED / EAT-AND-SPIT MECHANIC
# ==========================================
# Note: basicenemy.gd sets `is_bloated` and `last_eaten_enemy` on this player
# directly once it's fully swallowed (see its _get_swallowed() function),
# so there's no signal to wire up here - just consume last_eaten_enemy below.

func _start_spit_attack() -> void:
	spit_timer = spit_duration
	_fire_last_eaten_enemy()

func _fire_last_eaten_enemy() -> void:
	if not is_instance_valid(last_eaten_enemy):
		last_eaten_enemy = null
		return

	if last_eaten_enemy.has_method("fire_as_projectile"):
		last_eaten_enemy.fire_as_projectile(last_facing, tongue.global_position)

	last_eaten_enemy = null
