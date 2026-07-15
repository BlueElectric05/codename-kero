extends CharacterBody2D

var catcher : Node2D  # Changed type to Node2D to safely reference TipSprite or Player
var offSet = Vector2(0, 8)

var direction = 1
const SPEED = 30.0
@export var KNOCKBACK_FORCE_MIN: float = 40.0
@export var KNOCKBACK_FORCE_MAX: float = 90.0
@export var KNOCKBACK_DURATION: float = 1.0
@export var DEATH_FRICTION: float = 0.15 

# --- Projectile (post-swallow) tuning ---
const PROJECTILE_SPEED = 220.0
const PROJECTILE_LIFETIME = 2.0

@onready var animation = $AnimatedSprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var timerwalk = $Timerwalk
@onready var timerstop = $Timerstop
@onready var collision_shape = $Area2D/HurtBox
@onready var hitbox = $HitBox
@onready var player : PlayerController = get_tree().get_first_node_in_group("player")
@onready var ledge_detector: RayCast2D = $RayCast2D

@export var gravity : int = 700
@export var ledge_detect_distance : int = 8
var is_moving = true

var hp = 2
var knockback_time = 0.0
var is_caught = false  # Guard flag to stop enemy movement calculations immediately

var is_swallowed = false   # True while dormant inside the player, waiting to be spat out
var is_projectile = false  # True while flying back out as the player's spit attack
var _projectile_timer = 0.0
var is_dead = false

func _ready():
	add_to_group("enemies")

	timerwalk.wait_time = 2
	timerstop.wait_time = 1
	timerwalk.start()
	animation.flip_h = false

func _physics_process(delta):
	if is_swallowed:
		return

	if is_projectile:
		_process_projectile(delta)
		return

	if is_caught and catcher:
		global_position = catcher.global_position + offSet
		if player and player.tongue.current_state == TongueAttack.TongueState.INACTIVE:
			_get_swallowed()
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	# --- DEAD: locked into death pose forever, just let physics settle ---
	if is_dead:
		animation.visible = true
		play_anim("hurt")
		if knockback_time > 0:
			knockback_time -= delta
		else:
			velocity.x = lerp(velocity.x, 0.0, DEATH_FRICTION)   # slide to a stop, don't drift forever
		move_and_slide()
		return

	if knockback_time > 0:
		knockback_time -= delta
	else:
		animation.visible = true
		if is_moving:
			ledge_detector.position.x = direction * ledge_detect_distance
			ledge_detector.force_raycast_update()

			if not ledge_detector.is_colliding() and is_on_floor():
				direction *= -1
				animation.flip_h = !animation.flip_h
				ledge_detector.position.x = direction * ledge_detect_distance
				ledge_detector.force_raycast_update()
				timerwalk.stop()
				timerstop.start()
			else:
				play_anim("walk")
				velocity.x = direction * SPEED
		elif not is_moving and hp <= 0:
			play_anim("hurt")
			hitbox.set_deferred("disabled", true)
		else:
			play_anim("idle")
			velocity.x = 0

	move_and_slide()

func _on_timerwalk_timeout():
	if is_caught: return
	is_moving = false
	timerstop.start()
	timerwalk.stop()
	
func _on_timerstop_timeout():
	if is_caught: return
	is_moving = true
	direction *= -1  
	animation.flip_h = !animation.flip_h
	timerwalk.start()
	timerstop.stop()

func reduceHp(hit_dir: int = 0):
	if is_dead:
		return  
	hp -= 1
	knockback(hit_dir)  
	if hp <= 0:
		dead()
	else:
		play_anim("hurt")

func knockback(hit_dir: int = 0):
	Particles.play_effect("spark", global_position)
	knockback_time = KNOCKBACK_DURATION
	var force = randf_range(KNOCKBACK_FORCE_MIN, KNOCKBACK_FORCE_MAX)
	var dir = hit_dir if hit_dir != 0 else direction
	velocity.x = dir * force
	hitbox.set_deferred("disabled", true)

func dead():
	is_dead = true
	is_moving = false
	timerwalk.stop()
	timerstop.stop()
	hitbox.set_deferred("disabled", true)
	collision_shape.set_deferred("disabled", true)
	play_anim("hurt")

# This matches the method requested by your tongue system script: body.get_caught(tip_sprite)
func get_caught(new_catcher: Node2D):
	print("Caught on", name)
	is_caught = true
	catcher = new_catcher
	
	# Disable collisions so it doesn't bump things on the ride back
	hitbox.set_deferred("disabled", true)
	collision_shape.set_deferred("disabled", true)
	
	# Stop background AI behaviors
	timerwalk.stop()
	timerstop.stop()
	play_anim("hurt")

func _on_die_finished():
	queue_free()

func _on_area_2d_body_entered(body: Node2D) -> void:
	if is_caught: return

	if is_projectile:
		if body == player:
			return
		if body.is_in_group("enemies") and body != self:
			if body.has_method("reduceHp"):
				body.reduceHp(direction)
			queue_free()
		return

	if body.name == "Player" : 
		body.reduceHP()

func play_anim(anim_name: String) -> void:
	if animation.sprite_frames.has_animation(anim_name):
		animation.play(anim_name)
	elif anim_name == "hurt" and animation.sprite_frames.has_animation("captured"):
		animation.play("captured")
	else:
		animation.play("idle")

# ==========================================
# SWALLOW / SPIT
# ==========================================

func _get_swallowed() -> void:
	is_caught = false
	is_swallowed = true
	visible = false
	velocity = Vector2.ZERO
	AudioManager.play_unique(AudioManager.swallow)
	if not player:
		push_warning("Dung swallowed but no player reference found (missing 'player' group?)")
		return

	if "last_eaten_enemy" in player:
		player.last_eaten_enemy = self
	if "is_bloated" in player:
		player.is_bloated = true


func fire_as_projectile(facing_direction: int, origin: Vector2) -> void:
	is_swallowed = false
	is_projectile = true
	visible = true
	global_position = origin + offSet

	direction = facing_direction if facing_direction != 0 else 1
	animation.flip_h = direction < 0
	velocity = Vector2(direction * PROJECTILE_SPEED, 0)
	_projectile_timer = PROJECTILE_LIFETIME

	hitbox.set_deferred("disabled", true)
	collision_shape.set_deferred("disabled", false)

	play_anim("spat")
	animation_player.play("spin")

func _process_projectile(delta: float) -> void:
	move_and_slide()

	_projectile_timer -= delta
	if _projectile_timer <= 0.0:
		queue_free()

func _on_visible_on_screen_enabler_2d_screen_exited() -> void:
	if is_projectile or is_dead:
		queue_free()
