extends CharacterBody3D

const MOVE_SPEED := 4.8
const GRAVITY := 18.0
const JUMP_SPEED := 6.5
const JUMP_BUFFER_SECONDS := 0.14
const PLAYER_RADIUS := 0.42
# Anywhere at least this far from every room / hall floor is the open lunar
# surface, which has no invisible boundary. (A player standing against an outer
# wall is ~0.58 m from the room edge: half the wall plus the capsule radius.)
const OUTSIDE_CLEARANCE := 0.5

@onready var astronaut: Node3D = $Astronaut

# Room floors and hallway decks, set by main.gd from the same ROOMS / LINKS data
# that builds the level, so the walkable area always matches the hallways.
var walkable_rects: Array[Rect2] = []
# Strips through doors that lead outside. Always walkable, but they don't count
# as "the habitat" when deciding whether you are out on the open surface.
var door_exit_rects: Array[Rect2] = []
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
	if walkable_rects.is_empty():
		return
	var position_on_plane := Vector2(global_position.x, global_position.z)
	var nearest_position := position_on_plane
	var nearest_distance_squared := INF
	var is_walkable := false
	var near_habitat := false

	for rect: Rect2 in door_exit_rects:
		if rect.has_point(position_on_plane):
			return

	for rect: Rect2 in walkable_rects:
		var edge_point := Vector2(
			clampf(position_on_plane.x, rect.position.x, rect.end.x),
			clampf(position_on_plane.y, rect.position.y, rect.end.y)
		)
		if position_on_plane.distance_to(edge_point) < OUTSIDE_CLEARANCE:
			near_habitat = true
		# The corridor decks overlap room floors by 0.55 m. Shrinking both
		# rectangles by the full capsule radius created a gap at every doorway,
		# so the confinement snap kept pushing the player back into the room.
		var safe_rect := rect.grow(-PLAYER_RADIUS * 0.5)
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

	if not is_walkable and not near_habitat:
		is_walkable = true  # Out on the open surface: no boundary.

	if not is_walkable:
		var corrected_position := global_position
		corrected_position.x = nearest_position.x
		corrected_position.z = nearest_position.y
		global_position = corrected_position
