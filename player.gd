extends CharacterBody3D

const MOVE_SPEED := 4.8
const GRAVITY := 18.0
const JUMP_SPEED := 6.5
const JUMP_BUFFER_SECONDS := 0.14
const PLAYER_RADIUS := 0.42
const WALKABLE_RECTS := [
	Rect2(Vector2(-6.0, -33.0), Vector2(12.0, 10.0)),
	Rect2(Vector2(-8.0, -22.0), Vector2(16.0, 12.0)),
	Rect2(Vector2(-24.0, -22.0), Vector2(12.0, 12.0)),
	Rect2(Vector2(12.0, -22.0), Vector2(12.0, 12.0)),
	Rect2(Vector2(-24.0, -6.0), Vector2(12.0, 12.0)),
	Rect2(Vector2(-8.0, -6.0), Vector2(16.0, 12.0)),
	Rect2(Vector2(12.0, -6.0), Vector2(12.0, 12.0)),
	Rect2(Vector2(-4.0, 9.0), Vector2(8.0, 8.0)),
	Rect2(Vector2(-1.1, -10.55), Vector2(2.2, 5.1)),
	Rect2(Vector2(-1.1, -23.05), Vector2(2.2, 2.1)),
	Rect2(Vector2(-19.1, -10.55), Vector2(2.2, 5.1)),
	Rect2(Vector2(-11.55, -17.1), Vector2(5.1, 2.2)),
	Rect2(Vector2(6.45, -17.1), Vector2(5.1, 2.2)),
	Rect2(Vector2(17.1, -10.55), Vector2(2.2, 5.1)),
	Rect2(Vector2(-11.55, -1.1), Vector2(5.1, 2.2)),
	Rect2(Vector2(6.45, -1.1), Vector2(5.1, 2.2)),
	Rect2(Vector2(-1.1, 6.5), Vector2(2.2, 4.1))
]
const OUTSIDE_CENTER := Vector2(0.0, 29.0)
const OUTSIDE_RADIUS := 17.0

@onready var astronaut: Node3D = $Astronaut

var jump_buffer := 0.0
var walk_phase := 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			jump_buffer = JUMP_BUFFER_SECONDS


func _physics_process(delta: float) -> void:
	var local_direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		local_direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		local_direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		local_direction.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		local_direction.z += 1.0
	if local_direction.length_squared() > 1.0:
		local_direction = local_direction.normalized()
	var direction := global_transform.basis * local_direction
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	if jump_buffer > 0.0 and is_on_floor():
		velocity.y = JUMP_SPEED
		jump_buffer = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	_confine_to_walkable_area()

	if local_direction.length_squared() > 0.0:
		var target_rotation := atan2(-local_direction.x, -local_direction.z)
		astronaut.rotation.y = lerp_angle(astronaut.rotation.y, target_rotation, minf(delta * 10.0, 1.0))
	if is_on_floor() and direction.length_squared() > 0.0:
		walk_phase += delta * 12.0
		astronaut.position.y = sin(walk_phase) * 0.035
	else:
		astronaut.position.y = move_toward(astronaut.position.y, 0.0, delta * 0.3)


func _confine_to_walkable_area() -> void:
	var position_on_plane := Vector2(global_position.x, global_position.z)
	var nearest_position := position_on_plane
	var nearest_distance_squared := INF
	var is_walkable := false

	for rect: Rect2 in WALKABLE_RECTS:
		var safe_rect := rect.grow(-PLAYER_RADIUS)
		if safe_rect.has_point(position_on_plane):
			is_walkable = true
			break
		var rect_position := Vector2(
			clampf(position_on_plane.x, safe_rect.position.x, safe_rect.end.x),
			clampf(position_on_plane.y, safe_rect.position.y, safe_rect.end.y)
		)
		var distance_squared := position_on_plane.distance_squared_to(rect_position)
		if distance_squared < nearest_distance_squared:
			nearest_position = rect_position
			nearest_distance_squared = distance_squared

	var safe_outside_radius := OUTSIDE_RADIUS - PLAYER_RADIUS
	var outside_offset := position_on_plane - OUTSIDE_CENTER
	if outside_offset.length_squared() <= safe_outside_radius * safe_outside_radius:
		is_walkable = true
	else:
		var outside_position := OUTSIDE_CENTER + outside_offset.normalized() * safe_outside_radius
		var outside_distance_squared := position_on_plane.distance_squared_to(outside_position)
		if outside_distance_squared < nearest_distance_squared:
			nearest_position = outside_position

	if not is_walkable:
		var corrected_position := global_position
		corrected_position.x = nearest_position.x
		corrected_position.z = nearest_position.y
		global_position = corrected_position
