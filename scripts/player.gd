extends CharacterBody2D

# Top-down astronaut. Moves with WASD / arrow keys (see Project Settings > Input Map).
# Movement runs every rendered frame (not on the 60 Hz physics tick) so it stays smooth on
# 120 Hz displays, and the locked Camera2D child keeps it fixed on the pixel grid.

const SPEED := 64.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D

var facing := "down"


func _process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * SPEED
	move_and_slide()
	_animate(direction)


func _animate(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		if absf(direction.x) > absf(direction.y):
			facing = "side"
			sprite.flip_h = direction.x < 0.0
		else:
			facing = "down" if direction.y > 0.0 else "up"
			sprite.flip_h = false
	var animation := ("walk_" if direction != Vector2.ZERO else "idle_") + facing
	if sprite.animation != animation:
		sprite.play(animation)


func stop() -> void:
	velocity = Vector2.ZERO
	sprite.play("idle_" + facing)
