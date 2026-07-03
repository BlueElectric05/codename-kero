extends CharacterBody2D

var direction = 1
const SPEED = 30.0
const KNOCKBACK_FORCE = 60.0
const KNOCKBACK_DURATION = 0.1
const BLINK_INTERVAL = 0.01

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

func _ready():
	timerwalk.wait_time = 2
	timerstop.wait_time = 1
	timerwalk.start()
	animation.flip_h = false

func _physics_process(delta):
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
	
	if knockback_time == 0 and not hitbox.disabled:
		animation.visible = true
		hitbox.set_deferred("disabled", false)
		
	if hp == 0:
		collision_shape.set_deferred("disabled", true)

func _on_timerwalk_timeout():
	is_moving = false
	timerstop.start()
	timerwalk.stop()
	
func _on_timerstop_timeout():
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


func _on_die_finished():
	queue_free()


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.name == "Player" : 
		body.reduceHP()

func play_anim(anim_name: String) -> void:
	if animation.sprite_frames.has_animation(anim_name):
		animation.play(anim_name)
	elif anim_name == "hurt" and animation.sprite_frames.has_animation("captured"):
		animation.play("captured")
	else:
		animation.play("idle")
