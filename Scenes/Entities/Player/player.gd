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
@onready var ctimer: Timer = $CoyoteTimer

# ==========================================
# TUNING / EXPORTS
# ==========================================
@export_group("Movement")
@export var SPEED: int = 140
@export var SPEED_BLOATED: int = 80
@export var JUMP_VELOCITY: int = -400
@export var CHARGED_JUMP_VELOCITY: int = -600
@export var JUMP_VELOCITY_BLOATED: int = -320
@export var CHARGED_JUMP_VELOCITY_BLOATED: int = -450
@export var GRAVITY: int = 550
@export_range(0.0, 1.0) var friction: float = 0.3
@export_range(0.0, 1.0) var acceleration: float = 0.2

@export_group("Stats")
@export var max_hp: int = 5
@export var KNOCKBACK_X: float = 150.0
@export var KNOCKBACK_Y: float = -100.0
@export var INVULN_TIME: float = 1.0
@export var BLINK_INTERVAL: float = 0.01

@export_group("Mechanics")
@export var RESPAWN_FALL_Y: float = 320.0
@export var RESPAWN_POSITION: Vector2 = Vector2(40, 40)
@export var max_charge_time: float = 0.5
@export var spit_duration: float = 0.35

# ==========================================
# RUNTIME STATE
# ==========================================
var hp = Global.health
var direction: float = 0.0
var last_facing: int = 1

var is_bloated: bool = false
var is_kneeling: bool = false
var can_jump: bool = true
var is_ko: bool = false
var is_invulnerable: bool = false
var is_knockback: bool = false

var charge_time: float = 0.0
var blink_timer: float = 0.0
var spit_timer: float = 0.0
var last_eaten_enemy: Node = null

# ==========================================
# LIFECYCLE
# ==========================================
func _ready() -> void:
	hp = max_hp
	add_to_group("player")
	
	inv_timer.wait_time = INVULN_TIME
	inv_timer.one_shot = true
	inv_timer.timeout.connect(_on_invuln_timer_timeout)
	
	ctimer.one_shot = true
	ctimer.timeout.connect(_on_coyote_timer_timeout)

func _physics_process(delta: float) -> void:
	if position.y > RESPAWN_FALL_Y:
		position = RESPAWN_POSITION
		Global.reduce_life()

	update_inputs()
	handle_visuals(delta)
	
	var was_on_floor = is_on_floor()

	# 1. APPLY GRAVITY & STATES
	if not is_on_floor():
		velocity.y = lerpf(velocity.y, GRAVITY, 0.02)
		
	execute_state(delta)

	# 2. APPLY PHYSICS
	move_and_slide()

	# 3. POST-MOVEMENT CHECKS (Coyote Timer & Landing)
	handle_floor_transitions(was_on_floor)
	update_state_transitions()
	check_one_way_platforms()

# ==========================================
# CORE LOGIC
# ==========================================
func execute_state(delta: float) -> void:
	if is_ko:
		current_state = State.KO  

	charge.emitting = false

	match current_state:
		State.IDLE:
			apply_friction()
			handle_jump_input()
		
		State.MOVE:
			apply_movement()
			handle_jump_input()
		
		State.AIR:
			if not is_knockback:
				if direction != 0:
					apply_movement()
				else:
					apply_friction()
			handle_jump_input()
		
		State.KNEEL:
			apply_friction()
			handle_charge_jump(delta)
		
		State.ATTACK:
			if is_on_floor():
				apply_friction()
			handle_attack_timers(delta)
		
		State.KO:
			velocity.y = 0
			apply_friction()

func update_inputs() -> void:
	if is_knockback or current_state == State.ATTACK:
		direction = 0
		return

	direction = Input.get_axis("left", "right")
	if direction != 0:
		last_facing = int(sign(direction))

	is_kneeling = Input.is_action_pressed("kneel") and not is_bloated

	# Handle Attack Input
	if Input.is_action_just_pressed("lick") and not is_ko and current_state not in [State.ATTACK, State.KNEEL]:
		if tongue.current_state == TongueAttack.TongueState.INACTIVE:
			current_state = State.ATTACK
			if is_bloated:
				_start_spit_attack()
			else:
				AudioManager.play_unique(AudioManager.tongue)
				tongue.start_attack(last_facing)

func update_state_transitions() -> void:
	if current_state == State.KO or spit_timer > 0.0 or tongue.current_state != TongueAttack.TongueState.INACTIVE:
		return
		
	if not is_on_floor():
		current_state = State.AIR
	elif is_kneeling:
		current_state = State.KNEEL
	elif direction != 0:
		current_state = State.MOVE
	else:
		current_state = State.IDLE

# ==========================================
# MOVEMENT & ACTIONS
# ==========================================
func apply_friction() -> void:
	velocity.x = lerp(velocity.x, 0.0, friction)

func apply_movement() -> void:
	var target_speed = SPEED_BLOATED if is_bloated else SPEED
	velocity.x = lerp(velocity.x, direction * float(target_speed), acceleration)

func handle_jump_input() -> void:
	if Input.is_action_just_pressed("hop") and can_jump:
		jump()

func handle_charge_jump(delta: float) -> void:
	if Input.is_action_just_released("hop") and charge_time > 0.0:
		jump(charge_time >= max_charge_time)
		charge_time = 0.0
		sprite.material.set_shader_parameter("enabled", false)
		return

	if Input.is_action_pressed("hop"):
		charge_time = min(charge_time + delta, max_charge_time)
		if charge_time >= max_charge_time:
			anim_player.play("charging")
			charge.emitting = true
		else:
			AudioManager.play_unique(AudioManager.charge)
			sprite.material.set_shader_parameter("enabled", false)
	else:
		charge_time = 0.0
		sprite.material.set_shader_parameter("enabled", false)

func handle_attack_timers(delta: float) -> void:
	if spit_timer > 0.0:
		spit_timer -= delta
		if spit_timer <= 0.0:
			is_bloated = false
			current_state = State.IDLE
	elif tongue.current_state == TongueAttack.TongueState.INACTIVE:
		current_state = State.IDLE

func jump(charged: bool = false) -> void:
	can_jump = false
	ctimer.stop()

	var active_jump_vel = CHARGED_JUMP_VELOCITY if charged else JUMP_VELOCITY
	if is_bloated:
		active_jump_vel = CHARGED_JUMP_VELOCITY_BLOATED if charged else JUMP_VELOCITY_BLOATED
		
	velocity.y = active_jump_vel

	if charged:
		Particles.play_effect("dust", global_position)
		AudioManager.play_unique(AudioManager.superjump)
	else:
		AudioManager.play_unique(AudioManager.step)

func handle_floor_transitions(was_on_floor: bool) -> void:
	# Just landed
	if not was_on_floor and is_on_floor():
		can_jump = true
		is_knockback = false
		AudioManager.play_unique(AudioManager.step)
		Particles.play_effect("dust2", global_position)
		
	# Walked off a ledge (Start Coyote Time)
	elif was_on_floor and not is_on_floor() and velocity.y >= 0:
		can_jump = true
		ctimer.start()

func _on_coyote_timer_timeout() -> void:
	can_jump = false


func handle_visuals(delta: float) -> void:
	if current_state != State.KNEEL and charge_time > 0.0:
		charge_time = 0.0
		sprite.material.set_shader_parameter("enabled", false)

	if is_invulnerable and anim_player.current_animation != "hurt" and hp > 0:  
		blink_timer += delta
		if blink_timer >= BLINK_INTERVAL:
			blink_timer = 0.0
			sprite.visible = not sprite.visible  
	else:
		sprite.visible = true  

func reduceHP() -> void:
	if is_invulnerable: return  

	hp -= 1
	Global.health = hp
	progress_bar.value = hp

	AudioManager.play_unique(AudioManager.ouch)

	if hp <= 0:
		is_ko = true
	else:
		apply_knockback()

func apply_knockback() -> void:
	velocity.x = -last_facing * KNOCKBACK_X
	velocity.y = KNOCKBACK_Y
	is_knockback = true
	is_invulnerable = true
	blink_timer = 0.0  
	
	set_collision_layer_value(1, false)  
	set_collision_mask_value(1, false)   
	current_state = State.AIR
	inv_timer.start()

func _on_invuln_timer_timeout() -> void:
	is_invulnerable = false
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	sprite.visible = true
	sprite.modulate.a = 1.0

# ==========================================
# PLATFORMS & COMBAT HELPERS
# ==========================================
func check_one_way_platforms() -> void:
	if not is_on_floor(): return

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision.get_normal() == Vector2.UP:
			var collider := collision.get_collider()
			if collider and get_collision_mask_value(10):
				return
				
func drop_through_platform() -> void:
	set_collision_mask_value(10, false)

func _start_spit_attack() -> void:
	spit_timer = spit_duration
	if is_instance_valid(last_eaten_enemy):
		if last_eaten_enemy.has_method("fire_as_projectile"):
			last_eaten_enemy.fire_as_projectile(last_facing, tongue.global_position)
	last_eaten_enemy = null

func reload() -> void:
	if get_tree():
		get_tree().reload_current_scene()
		global_position = RESPAWN_POSITION
		hp = max_hp

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "death":
		AudioManager.play_unique(AudioManager.pop)
		Global.reduce_life()
		Particles.play_effect("dustsplode", global_position)
		
		await get_tree().create_timer(0.5).timeout
		reload()

		queue_free()
		
