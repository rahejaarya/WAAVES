extends CharacterBody3D

const MOVE_SPEED := 4.8
const GRAVITY := 18.0
const JUMP_SPEED := 6.5
const JUMP_BUFFER_SECONDS := 0.14

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

	if local_direction.length_squared() > 0.0:
		var target_rotation := atan2(-local_direction.x, -local_direction.z)
		astronaut.rotation.y = lerp_angle(astronaut.rotation.y, target_rotation, minf(delta * 10.0, 1.0))
	if is_on_floor() and direction.length_squared() > 0.0:
		walk_phase += delta * 12.0
		astronaut.position.y = sin(walk_phase) * 0.035
	else:
		astronaut.position.y = move_toward(astronaut.position.y, 0.0, delta * 0.3)
