extends Node2D

const SKY := Color("#07121f")
const FLOOR := Color("#091a26")
const GRID := Color(0.24, 0.84, 0.91, 0.66)
const GRID_FAINT := Color(0.24, 0.84, 0.91, 0.25)
const HUD := Color("#75f4f0")
const HUD_DIM := Color(0.50, 0.82, 0.87, 0.78)
const PANEL := Color(0.015, 0.055, 0.078, 0.90)

@onready var player: CharacterBody2D = $Player


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var view_size := get_viewport_rect().size
	var horizon_y := view_size.y * 0.43
	var floor_bottom := view_size.y * 0.94
	var center_x := view_size.x * 0.5

	draw_rect(Rect2(Vector2.ZERO, view_size), SKY)
	_draw_stars(view_size)

	# A clean perspective grid gives the player a readable floor without heavy scenery.
	draw_rect(Rect2(Vector2(0, horizon_y), Vector2(view_size.x, floor_bottom - horizon_y)), FLOOR)
	draw_line(Vector2(0, horizon_y), Vector2(view_size.x, horizon_y), GRID, 1.5)
	for i in range(-10, 11):
		var bottom_x := center_x + float(i) * view_size.x * 0.105
		draw_line(Vector2(center_x, horizon_y), Vector2(bottom_x, floor_bottom), GRID_FAINT, 1.0)
	for step in range(1, 13):
		var t := float(step) / 12.0
		var y := horizon_y + (floor_bottom - horizon_y) * t * t
		draw_line(Vector2(0, y), Vector2(view_size.x, y), GRID, 1.0 if step < 9 else 1.3)

	_draw_header()
	_draw_map(view_size, horizon_y, floor_bottom)
	_draw_controls(view_size)


func _draw_stars(view_size: Vector2) -> void:
	for i in range(34):
		var x := fposmod(float(i * 173 + 51), view_size.x)
		var y := fposmod(float(i * 79 + 19), view_size.y * 0.39)
		var radius := 1.0 if i % 5 != 0 else 1.6
		draw_circle(Vector2(x, y), radius, Color(0.55, 0.88, 0.96, 0.52))


func _draw_header() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(24, 35), "HABITAT ZERO", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, HUD)
	draw_string(font, Vector2(24, 54), "SURFACE WALK  /  JUNIOR ASTRONAUT TRAINING", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HUD_DIM)
	draw_string(font, Vector2(24, 78), "MISSION 01   •   EXPLORE THE HABITAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.92, 0.94, 0.82))


func _draw_map(view_size: Vector2, horizon_y: float, floor_bottom: float) -> void:
	var map_size := Vector2(196, 150)
	var map_position := Vector2(view_size.x - map_size.x - 20, 18)
	var map_rect := Rect2(map_position, map_size)
	var map_area := Rect2(map_position + Vector2(12, 34), map_size - Vector2(24, 46))
	var font: Font = ThemeDB.fallback_font

	draw_rect(map_rect, PANEL, true)
	draw_rect(map_rect, HUD_DIM, false, 1.2)
	draw_string(font, map_position + Vector2(12, 21), "LOCAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HUD)
	draw_string(font, map_position + Vector2(map_size.x - 12, 21), "N", HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, HUD_DIM)
	draw_line(map_position + Vector2(10, 28), map_position + Vector2(map_size.x - 10, 28), HUD_DIM, 1.0)

	for x_step in range(1, 5):
		var x := map_area.position.x + map_area.size.x * float(x_step) / 5.0
		draw_line(Vector2(x, map_area.position.y), Vector2(x, map_area.end.y), GRID_FAINT, 1.0)
	for y_step in range(1, 4):
		var y := map_area.position.y + map_area.size.y * float(y_step) / 4.0
		draw_line(Vector2(map_area.position.x, y), Vector2(map_area.end.x, y), GRID_FAINT, 1.0)

	# Simple habitat and supply landmarks on the overhead map.
	var habitat := map_area.position + Vector2(map_area.size.x * 0.22, map_area.size.y * 0.28)
	var supply := map_area.position + Vector2(map_area.size.x * 0.75, map_area.size.y * 0.66)
	draw_rect(Rect2(habitat - Vector2(7, 5), Vector2(14, 10)), Color(0.25, 0.70, 0.77, 0.95), false, 1.4)
	draw_circle(supply, 3.0, Color("#ffc96b"))

	var playable_height := maxf(floor_bottom - horizon_y, 1.0)
	var player_uv := Vector2(
		clampf(player.global_position.x / maxf(view_size.x, 1.0), 0.0, 1.0),
		clampf((player.global_position.y - horizon_y) / playable_height, 0.0, 1.0)
	)
	var marker := map_area.position + Vector2(player_uv.x * map_area.size.x, player_uv.y * map_area.size.y)
	draw_circle(marker, 5.0, HUD)
	draw_arc(marker, 8.0, 0.0, TAU, 24, Color(HUD.r, HUD.g, HUD.b, 0.60), 1.2)
	draw_string(font, map_position + Vector2(12, map_size.y - 8), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HUD)
	draw_string(font, map_position + Vector2(map_size.x - 12, map_size.y - 8), "SUPPLY", HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color("#ffc96b"))


func _draw_controls(view_size: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var position := Vector2(20, view_size.y - 48)
	draw_rect(Rect2(position - Vector2(9, 21), Vector2(252, 34)), PANEL, true)
	draw_rect(Rect2(position - Vector2(9, 21), Vector2(252, 34)), Color(0.50, 0.82, 0.87, 0.45), false, 1.0)
	draw_string(font, position, "MOVE  WASD / ARROWS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD_DIM)
