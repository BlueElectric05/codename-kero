extends CharacterBody2D
class_name PlayerController

# ==========================================
# STATE
# ==========================================

enum State { IDLE, MOVE, AIR, KNEEL, ATTACK, KO, SWING }
var current_state: State = State.IDLE

# ==========================================
# NODE REFERENCES
# ==========================================

@onready var progress_bar: ProgressBar = $"../UI/Health Bar/ProgressBar"
@onready var sprite: Sprite2D = $Animation/Sprite2D       
@onready var inv_timer: Timer = $Invulnerability
@onready var anim_player: AnimationPlayer = $Animation/AnimationPlayer  
@onready var charge: CPUParticles2D = $charge
@onready var tongue_rope: Line2D = $TongueRope
@onready var tongue_hitbox: Area2D = $TongueHitbox

# ==========================================
# TUNING / EXPORTS
# ==========================================

@export var SPEED: int = 140
@export var max_tongue_length: float = 80.0
@export var tongue_attack_duration: float = 0.3
@export var max_swing_distance: float = 120.0
@export var swing_acceleration: float = 450.0
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
@export var BLINK_INTERVAL: float = 0.01  # How fast the sprite flashes (in seconds)

@export var RESPAWN_FALL_Y: float = 256.0
@export var RESPAWN_POSITION: Vector2 = Vector2(40, 40)

@export var max_charge_time: float = 0.5

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
var _hit_enemies_this_attack: Array = []
var tongue_attack_timer: float = 0.0

var is_swinging: bool = false
var swing_anchor: Vector2 = Vector2.ZERO
var rope_length: float = 0.0
var _swing_timer: float = 0.0
var has_swung_this_jump: bool = false
var on_platform_layer: bool = false
var is_ko: bool = false
var is_invulnerable: bool = false
var is_knockback: bool = false

var charge_time: float = 0.0
var blink_timer: float = 0.0  # Tracks our code-based flashing time

# ==========================================
# LIFECYCLE
# ==========================================

func _ready() -> void:
	hp = max_hp

	inv_timer.wait_time = INVULN_TIME
	inv_timer.one_shot = true
	inv_timer.timeout.connect(_on_invuln_timer_timeout)
	tongue_hitbox.body_entered.connect(_on_tongue_body_entered)

func _physics_process(delta: float) -> void:
	# 1. GLOBAL CHECKS (happen regardless of state)
	handle_respawn()
	if is_on_floor():
		has_swung_this_jump = false
	if not is_swinging:
		apply_gravity()
	update_inputs()
	check_one_way_platforms()
	
	# --- Lick & Swing Input Check ---
	if not is_ko and roll_instance == null:
		if not is_attacking and not is_swinging:
			if Input.is_action_just_pressed("lick"):
				_start_tongue_attack()
			elif Input.is_action_just_pressed("swing") or Input.is_key_pressed(KEY_E):
				_try_start_swing()
				
	if is_attacking:
		_update_tongue_attack(delta)
	elif is_swinging:
		_swing_timer += delta
		_draw_swing_tongue()
	
	# --- Code-Based Blinking Mechanism ---
	if is_invulnerable and anim_player.current_animation != "hurt" and hp > 0:  # Only blink if not playing a specific invulnerability animation
		blink_timer += delta
		if blink_timer >= BLINK_INTERVAL:
			blink_timer = 0.0
			sprite.visible = not sprite.visible  # Rapidly flips visibility on and off
	else:
		sprite.visible = true  # Force visible when not invulnerable
	# -------------------------------------
	
	charge.emitting = false
	# 2. STATE EXECUTION
	if is_ko:
		current_state = State.KO  

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
		State.SWING:
			state_swing(delta)

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
	# REMOVED: AnimationPlayer overrides that used to freeze the landing frame

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
	velocity.x = lerp(velocity.x, 0.0, friction)

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
	if is_swinging:
		current_state = State.SWING
		return
	if is_attacking:
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
	if is_knockback:
		direction = 0
		return
	if is_attacking:
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
	blink_timer = 0.0  # Reset our script flash timer

	set_collision_layer_value(1, false)  
	set_collision_mask_value(1, false)   

	current_state = State.AIR
	was_in_air = true

	inv_timer.start()
	# REMOVED: anim_player.play("blink") — handoff entirely to delta-timer visibility updates

func _on_invuln_timer_timeout() -> void:
	is_invulnerable = false
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	
	# Reset sprite back to a clean default state
	sprite.visible = true
	sprite.modulate.a = 1.0

func _on_coyote_timer_timeout() -> void:
	can_jump = false

# ==========================================
# TONGUE ATTACK & SWING MECHANICS
# ==========================================

func _start_tongue_attack() -> void:
	is_attacking = true
	tongue_attack_timer = 0.0
	_hit_enemies_this_attack.clear()
	tongue_hitbox.monitoring = true
	tongue_rope.visible = true
	AudioManager.play_unique(AudioManager.swallow)

func _update_tongue_attack(delta: float) -> void:
	tongue_attack_timer += delta
	var progress := tongue_attack_timer / tongue_attack_duration
	if progress >= 1.0:
		_end_tongue_attack()
		return

	var mouth_pos := get_mouth_local_position()
	var target_offset := Vector2(max_tongue_length * last_facing, 0.0)
	var tongue_target_pos := mouth_pos + target_offset

	var ext_point := Vector2.ZERO
	if progress < 0.4:
		var ratio := progress / 0.4
		ext_point = mouth_pos.lerp(tongue_target_pos, ratio)
	elif progress < 0.6:
		ext_point = tongue_target_pos
	else:
		var ratio := (1.0 - progress) / 0.4
		ext_point = mouth_pos.lerp(tongue_target_pos, max(0.0, ratio))

	tongue_rope.points = PackedVector2Array([mouth_pos, ext_point])
	tongue_hitbox.position = ext_point
	queue_redraw()

func _end_tongue_attack() -> void:
	is_attacking = false
	tongue_hitbox.monitoring = false
	tongue_rope.visible = false
	queue_redraw()

func _on_tongue_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if body in _hit_enemies_this_attack:
		return
	_hit_enemies_this_attack.append(body)
	if body.has_method("reduceHp"):
		body.reduceHp()

func _try_start_swing() -> void:
	if is_on_floor():
		print("[SWING] Cannot swing while on the floor.")
		return
	if has_swung_this_jump:
		print("[SWING] Already swung during this jump. Reset on floor contact.")
		return
		
	print("[SWING] Attempting swing. Player position: ", global_position)
	var anchor = get_closest_swing_point()
	if anchor != Vector2.ZERO:
		is_swinging = true
		has_swung_this_jump = true
		_swing_timer = 0.0
		swing_anchor = anchor
		rope_length = global_position.distance_to(swing_anchor)
		rope_length = clamp(rope_length, 40.0, max_swing_distance)
		print("[SWING] Grappled! Anchor at: ", swing_anchor, " rope_length: ", rope_length)
		AudioManager.play_unique(AudioManager.swallow)
	else:
		print("[SWING] No close swing point anchor found within range.")

func _update_swing(delta: float) -> void:
	velocity.y += GRAVITY * delta
	var rope_vector = global_position - swing_anchor
	var distance = rope_vector.length()
	
	if direction != 0:
		var tangent = Vector2(-rope_vector.y, rope_vector.x).normalized()
		if tangent.dot(Vector2(direction, 0)) < 0:
			tangent = -tangent
		velocity += tangent * swing_acceleration * delta

	if distance >= rope_length:
		global_position = swing_anchor + rope_vector.normalized() * rope_length
		var direction_to_anchor = -rope_vector.normalized()
		var radial_vel = velocity.dot(direction_to_anchor)
		if radial_vel < 0:
			velocity -= radial_vel * direction_to_anchor

func _draw_swing_tongue() -> void:
	var mouth_pos := get_mouth_local_position()
	tongue_rope.points = PackedVector2Array([mouth_pos, to_local(swing_anchor)])
	tongue_rope.visible = true

func _release_swing(boost: bool) -> void:
	print("[SWING] Releasing swing hook.")
	is_swinging = false
	tongue_rope.visible = false
	if boost:
		velocity.y = JUMP_VELOCITY * 0.85
		velocity.x += last_facing * 120.0
	can_jump = true
	current_state = State.AIR

func state_swing(delta: float) -> void:
	_update_swing(delta)
	
	# Release swing immediately if player lands on the floor or swings above the anchor
	if is_on_floor() or global_position.y < swing_anchor.y - 10.0:
		_release_swing(false)
		return
		
	# Release swing if hop action is pressed, OR if swing action is pressed, OR if raw key E is pressed after a minor buffer
	var release_pressed := Input.is_action_just_pressed("hop") or Input.is_action_just_pressed("swing")
	if not release_pressed and Input.is_key_pressed(KEY_E) and _swing_timer > 0.2:
		release_pressed = true
		
	if release_pressed:
		_release_swing(true)

func get_closest_swing_point() -> Vector2:
	var player_pos = global_position
	var start_pos = global_position + get_mouth_local_position()
	var closest_pos = Vector2.ZERO
	var min_dist = 999999.0
	
	var space_state := get_world_2d().direct_space_state
	
	# 1. Search manual SwingPoint group nodes (like in Tutorial)
	var swing_nodes := get_tree().get_nodes_in_group("swing_point")
	for swing_node in swing_nodes:
		var shapes = swing_node.find_children("*", "CollisionShape2D", true, false)
		for child in shapes:
			if player_pos.y < child.global_position.y - 10.0:
				continue
			var dist = player_pos.distance_to(child.global_position)
			if dist < min_dist:
				# Cast a ray to verify line of sight (Terrain layer is 16)
				var query = PhysicsRayQueryParameters2D.create(start_pos, child.global_position, 16)
				var result = space_state.intersect_ray(query)
				if result.is_empty():
					min_dist = dist
					closest_pos = child.global_position
				
	# 2. Search TileMapLayer for painted Swingqodrul tiles dynamically
	var tilemap = get_parent().find_child("TileMapLayer", true, false) if get_parent() else null
	if tilemap and tilemap.tile_set:
		var tileset = tilemap.tile_set
		var swing_sources := []
		for i in range(tileset.get_source_count()):
			var source_id = tileset.get_source_id(i)
			var source = tileset.get_source(source_id)
			if source is TileSetAtlasSource:
				var tex = source.texture
				if tex and tex.resource_path.contains("Swingqodrul"):
					swing_sources.append(source_id)
					
		if swing_sources.size() > 0:
			for cell in tilemap.get_used_cells():
				var source_id = tilemap.get_cell_source_id(cell)
				if source_id in swing_sources:
					var local_pos = tilemap.map_to_local(cell)
					local_pos.y += 8.0  # Align to the bottom visual hook point
					var global_pos = tilemap.to_global(local_pos)
					if player_pos.y < global_pos.y - 10.0:
						continue
					var dist = player_pos.distance_to(global_pos)
					if dist < min_dist:
						# Cast a ray to verify line of sight (Terrain layer is 16)
						var query = PhysicsRayQueryParameters2D.create(start_pos, global_pos, 16)
						var result = space_state.intersect_ray(query)
						if result.is_empty():
							min_dist = dist
							closest_pos = global_pos
						
	if min_dist <= max_swing_distance:
		print("[SWING] Success! Closest anchor found at: ", closest_pos, " dist: ", min_dist)
		return closest_pos
	
	print("[SWING] Closest swing point is too far, blocked by terrain, or player is above it. Distance: ", min_dist)
	return Vector2.ZERO

func get_mouth_local_position() -> Vector2:
	var offset_x := 8.0 if last_facing == 1 else -8.0
	return Vector2(offset_x, -18.0)

func _draw() -> void:
	if is_attacking and tongue_rope.visible and tongue_rope.points.size() > 1:
		draw_circle(tongue_rope.points[1], 3.0, Color(0.88, 0.33, 0.42, 1))
