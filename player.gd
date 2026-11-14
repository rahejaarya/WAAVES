extends CharacterBody2D

const SPEED := 220.0
const GRAVITY := 1100.0
const JUMP_SPEED := 470.0
const JUMP_BUFFER_SECONDS := 0.12

@onready var sprite: Sprite2D = $Sprite2D

var jump_buffer := 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_W or event.physical_keycode == KEY_UP:
			jump_buffer = JUMP_BUFFER_SECONDS


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0

	velocity.x = direction.x * SPEED
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	if jump_buffer > 0.0 and is_on_floor():
		velocity.y = -JUMP_SPEED
		jump_buffer = 0.0
	else:
		velocity.y += GRAVITY * delta

	move_and_slide()

	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0

	# Keep the astronaut inside the visible play area.
	var view_size := get_viewport_rect().size
	position.x = clampf(position.x, 32.0, view_size.x - 32.0)
	position.y = maxf(position.y, view_size.y * 0.20)
