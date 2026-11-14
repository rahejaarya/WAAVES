extends CharacterBody2D

const SPEED := 220.0

@onready var sprite: Sprite2D = $Sprite2D


func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	velocity = direction * SPEED
	move_and_slide()

	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0

	# Keep the astronaut on the visible wireframe floor.
	var view_size := get_viewport_rect().size
	position.x = clampf(position.x, 28.0, view_size.x - 28.0)
	position.y = clampf(position.y, view_size.y * 0.43 + 26.0, view_size.y * 0.94 - 32.0)
