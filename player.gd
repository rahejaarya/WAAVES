extends CharacterBody2D

const SPEED = 220.0

@onready var sprite: Sprite2D = $Sprite2D

func _physics_process(_delta):
    var move_x = 0.0
    var move_y = 0.0

    if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
        move_x -= 1.0
    if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
        move_x += 1.0
    if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
        move_y -= 1.0
    if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
        move_y += 1.0

    var direction = Vector2(move_x, move_y)
    if direction.length() > 0:
        direction = direction.normalized()

    velocity = direction * SPEED
    move_and_slide()

    if direction.x < 0:
        sprite.flip_h = true
    elif direction.x > 0:
        sprite.flip_h = false
