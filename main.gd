extends Node2D

const SKY := Color("#07121f")
const FLOOR := Color("#0a1d2a")
const GRID := Color(0.20, 0.83, 0.92, 0.48)
const GRID_FAINT := Color(0.20, 0.83, 0.92, 0.20)
const HUD := Color("#63f4f2")
const HUD_DIM := Color(0.39, 0.82, 0.87, 0.72)

@onready var player: CharacterBody2D = $Player

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	var horizon_y := size.y * 0.48
	var floor_bottom := size.y * 0.94

	draw_rect(Rect2(Vector2.ZERO, size), SKY)
	draw_rect(Rect2(Vector2(0, horizon_y), Vector2(size.x, floor_bottom - horizon_y)), FLOOR)
	draw_line(Vector2(0, horizon_y), Vector2(size.x, horizon_y), GRID, 1.2)

	# Perspective floor lines converge at the horizon for a simple wireframe look.
	var center_x := size.x * 0.5
	for i in range(-10, 11):
		var bottom_x := center_x + i * size.x * 0.105
		draw_line(Vector2(center_x, horizon_y), Vector2(bottom_x, floor_bottom), GRID_FAINT, 1.0)

	for step in range(1, 11):
		var t := float(step) / 10.0
		var y := horizon_y + (floor_bottom - horizon_y) * t * t
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0 if step < 8 else 1.4)

	_draw_map(size)

func _draw_map(view_size: Vector2) -> void:
	var map_size := Vector2(184, 126)
	var map_position := Vector2(view_size.x - map_size.x - 22, 22)
	var map_rect := Rect2(map_position, map_size)
	var inner := map_rect.grow(-10)
	var font := ThemeDB.fallback_font

	draw_rect(map_rect, Color(0.015, 0.06, 0.09, 0.88), true)
	draw_rect(map_rect, HUD_DIM, false, 1.2)
	draw_string(font, map_position + Vector2(10, 17), "SUIT MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD)
	draw_line(map_position + Vector2(10, 23), map_position + Vector2(map_size.x - 10, 23), HUD_DIM, 1.0)

	# A compact overhead grid and simple habitat markers make the map legible at a glance.
	for x_step in range(1, 5):
		var x := inner.position.x + inner.size.x * float(x_step) / 5.0
		draw_line(Vector2(x, inner.position.y + 18), Vector2(x, map_rect.end.y - 9), GRID_FAINT, 1.0)
	for y_step in range(1, 3):
		var y := inner.position.y + 18 + (inner.size.y - 22) * float(y_step) / 3.0
		draw_line(Vector2(inner.position.x, y), Vector2(map_rect.end.x - 9, y), GRID_FAINT, 1.0)

	# Small habitat blocks are landmarks; the bright dot tracks the astronaut.
	draw_rect(Rect2(inner.position + Vector2(16, 36), Vector2(18, 12)), Color(0.14, 0.42, 0.48, 0.8), false, 1.0)
	draw_rect(Rect2(inner.position + Vector2(84, 48), Vector2(22, 14)), Color(0.14, 0.42, 0.48, 0.8), false, 1.0)
	var player_uv := Vector2(clampf(player.global_position.x / view_size.x, 0.0, 1.0), clampf(player.global_position.y / view_size.y, 0.0, 1.0))
	var marker := inner.position + Vector2(0, 18) + Vector2(player_uv.x * (inner.size.x - 18), player_uv.y * (inner.size.y - 26))
	draw_circle(marker, 5.0, HUD)
	draw_arc(marker, 8.0, 0.0, TAU, 24, Color(HUD.r, HUD.g, HUD.b, 0.55), 1.0)
