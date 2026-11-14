extends CharacterBody2D

const SPEED = 220.0
const JUMP_VELOCITY = -420.0
const GRAVITY = 980.0

@onready var sprite: Sprite2D = $Sprite2D

func _physics_process(delta):
    var move_left = Input.is_physical_key_pressed(KEY_A)
    var move_right = Input.is_physical_key_pressed(KEY_D)
    var jump_pressed = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE)

    if not is_on_floor():
        velocity.y += GRAVITY * delta

    if jump_pressed and is_on_floor():
        velocity.y = JUMP_VELOCITY

    var direction = 0.0
    if move_left:
        direction -= 1.0
    if move_right:
        direction += 1.0

    if direction != 0:
        velocity.x = direction * SPEED
        sprite.flip_h = direction < 0
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)

    move_and_slide()
