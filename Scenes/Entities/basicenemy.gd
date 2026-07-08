extends CharacterBody2D

var catcher : Node2D  # Changed type to Node2D to safely reference TipSprite or Player
var offSet = Vector2(0, 8)

var direction = 1
const SPEED = 30.0
const KNOCKBACK_FORCE = 60.0
const KNOCKBACK_DURATION = 0.1
const BLINK_INTERVAL = 0.01

# --- Projectile (post-swallow) tuning ---
const PROJECTILE_SPEED = 220.0
const PROJECTILE_LIFETIME = 2.0

@onready var animation = $AnimatedSprite2D
@onready var timerwalk = $Timerwalk
@onready var timerstop = $Timerstop
@onready var collision_shape = $Area2D/HurtBox
@onready var hitbox = $HitBox
@onready var player = %Player

@export var gravity : int = 700
var is_moving = true

var hp = 2
var knockback_time = 0.0
var blink_timer = 0.0
var is_caught = false  # Guard flag to stop enemy movement calculations immediately

var is_swallowed = false   # True while dormant inside the player, waiting to be spat out
var is_projectile = false  # True while flying back out as the player's spit attack
var _projectile_timer = 0.0

func _ready():
	add_to_group("enemies")

	timerwalk.wait_time = 2
	timerstop.wait_time = 1
	timerwalk.start()
	animation.flip_h = false

func _physics_process(delta):
	# Dormant inside the player after being swallowed - do nothing until fired
	if is_swallowed:
		return

	# Flying back out as the player's spit attack
	if is_projectile:
		_process_projectile(delta)
		return

	# If caught by the tongue, lock to catcher's position and skip regular AI/physics
	if is_caught and catcher:
		global_position = catcher.global_position
		
		# Detect when the tongue has fully re-entered the player's mouth (INACTIVE state)
		if player and player.tongue.current_state == TongueAttack.TongueState.INACTIVE:
			_get_swallowed()
		return

	if not is_on_floor():
		velocity.y += gravity * delta
	
	if knockback_time > 0:
		knockback_time -= delta
		blink_timer -= delta
		if blink_timer <= 0:
			animation.visible = not animation.visible
			blink_timer = BLINK_INTERVAL
	else:
		animation.visible = true
		
		if is_moving:
			play_anim("walk")
			velocity.x = direction * SPEED
		elif not is_moving and hp <= 0:
			play_anim("hurt")
			hitbox.set_deferred("disabled", true)
		else:
			play_anim("idle")
			velocity.x = 0
	
	move_and_slide()
	
	if hp == 0:
		collision_shape.set_deferred("disabled", true)

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

func reduceHp():
	play_anim("hurt")
	hp -= 1
	if hp > 0:
		knockback()
	else:
		dead()

func knockback():
	knockback_time = KNOCKBACK_DURATION
	blink_timer = BLINK_INTERVAL
	velocity.x = -direction * KNOCKBACK_FORCE
	hitbox.set_deferred("disabled", true)

func dead():
	hitbox.set_deferred("disabled", true)
	knockback()
	play_anim("hurt")
	if hp <= 0:
		hitbox.set_deferred("disabled", true)
		is_moving = false

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

	# While flying back out as a projectile: hurt other enemies, ignore the player who fired us
	if is_projectile:
		if body == player:
			return
		if body.is_in_group("enemies") and body != self:
			if body.has_method("reduceHp"):
				body.reduceHp()
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
# SWALLOW / SPIT (bloated player mechanic)
# ==========================================

# Called once the tongue has fully retracted with this enemy caught in it.
# Instead of being destroyed, the enemy goes dormant and hides inside the
# player until it's fired back out as the "spit" attack.
func _get_swallowed() -> void:
	print("swallowed called, player = ", player)
	is_caught = false
	is_swallowed = true
	visible = false
	velocity = Vector2.ZERO

	if player:
		if "last_eaten_enemy" in player:
			player.last_eaten_enemy = self
		if "is_bloated" in player:
			player.is_bloated = true

# Called by PlayerController when the bloated player uses their attack.
# Reactivates this same enemy instance as a projectile fired from `origin`
# in `facing_direction` (1 = right, -1 = left).
func fire_as_projectile(facing_direction: int, origin: Vector2) -> void:
	is_swallowed = false
	is_projectile = true
	visible = true
	global_position = origin

	direction = facing_direction if facing_direction != 0 else 1
	animation.flip_h = direction < 0
	velocity = Vector2(direction * PROJECTILE_SPEED, 0)
	_projectile_timer = PROJECTILE_LIFETIME

	# Keep the tongue-catch hitbox off, but re-enable the body hurtbox so this
	# can register hits against other enemies while it flies.
	hitbox.set_deferred("disabled", true)
	collision_shape.set_deferred("disabled", false)

	play_anim("walk")

func _process_projectile(delta: float) -> void:
	# Straight-line shot: no gravity applied while airborne as a projectile.
	move_and_slide()

	_projectile_timer -= delta
	if _projectile_timer <= 0.0:
		queue_free()