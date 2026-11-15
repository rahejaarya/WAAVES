extends Node2D

# Bobbing yellow arrow drawn above the machine for the task you picked (in art pixels).

const ARROW := ["#####", ".###.", "..#.."]

var time := 0.0


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	var bob := roundf(sin(time * 5.0))
	var top := Vector2(-2, -3 + bob)
	# Dark outline first, then the yellow arrow, one art pixel at a time.
	for y in range(ARROW.size()):
		for x in range(5):
			if ARROW[y][x] == "#":
				draw_rect(Rect2(top + Vector2(x - 1, y - 1), Vector2(3, 3)), Color("#14181c"))
	for y in range(ARROW.size()):
		for x in range(5):
			if ARROW[y][x] == "#":
				draw_rect(Rect2(top + Vector2(x, y), Vector2(1, 1)), Color("#ffd35c"))
