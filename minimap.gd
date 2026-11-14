extends Control

const MAP_SCALE := 4.2
const PANEL_COLOR := Color(0.025, 0.065, 0.085, 0.94)
const ROOM_COLOR := Color(0.12, 0.23, 0.28, 0.98)
const ROOM_OUTLINE := Color(0.38, 0.75, 0.79, 0.95)
const MAP_LINK := Color(0.34, 0.58, 0.62, 0.82)
const ROOM_ACTIVE := Color(0.19, 0.40, 0.43, 1.0)
const ROOM_ACTIVE_OUTLINE := Color("#fff0a6")

const ROOMS := [
	{"id": "garden", "label": "GARDEN", "center": Vector2(0, -18.5), "size": Vector2(8, 7)},
	{"id": "dining", "label": "DINING", "center": Vector2(0, -10), "size": Vector2(10, 8)},
	{"id": "med", "label": "MED", "center": Vector2(-10, -10), "size": Vector2(8, 8)},
	{"id": "rest", "label": "REST", "center": Vector2(10, -10), "size": Vector2(8, 8)},
	{"id": "lab", "label": "LAB", "center": Vector2(-10, 0), "size": Vector2(8, 8)},
	{"id": "main", "label": "MAIN", "center": Vector2(0, 0), "size": Vector2(10, 8)},
	{"id": "sleep", "label": "SLEEP", "center": Vector2(10, 0), "size": Vector2(8, 8)},
	{"id": "airlock", "label": "AIRLOCK", "center": Vector2(0, 8), "size": Vector2(4, 4)},
	{"id": "outside", "label": "OUTSIDE", "center": Vector2(0, 17), "size": Vector2(18, 18)}
]

const LINKS := [
	["main", "dining"], ["dining", "garden"], ["dining", "med"],
	["med", "lab"], ["lab", "main"], ["dining", "rest"],
	["rest", "sleep"], ["main", "sleep"], ["main", "airlock"], ["airlock", "outside"]
]

var player: Node3D
var current_room_id := "main"


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return

	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, PANEL_COLOR, true)
	draw_rect(panel, ROOM_OUTLINE, false, 1.2)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(12, 21), "HABITAT MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#baf9f3"))
	draw_line(Vector2(10, 29), Vector2(size.x - 10, 29), ROOM_OUTLINE, 1.0)

	var map_center := Vector2(size.x * 0.5, size.y * 0.53)
	var points: Dictionary = {}
	for room: Dictionary in ROOMS:
		points[room["id"]] = _to_map(room["center"], map_center)

	for link: Array in LINKS:
		draw_line(points[link[0]], points[link[1]], MAP_LINK, 2.0)

	for room: Dictionary in ROOMS:
		var center: Vector2 = points[room["id"]]
		var is_current_room: bool = room["id"] == current_room_id
		if room["id"] == "outside":
			var outside_size: Vector2 = room["size"]
			var radius: float = outside_size.x * MAP_SCALE * 0.5
			var outside_color := ROOM_ACTIVE if is_current_room else Color(0.20, 0.27, 0.20, 0.92)
			var outside_outline := ROOM_ACTIVE_OUTLINE if is_current_room else ROOM_OUTLINE
			draw_circle(center, radius, outside_color)
			draw_arc(center, radius, 0.0, TAU, 36, outside_outline, 2.0 if is_current_room else 1.2)
			draw_string(font, Vector2(center.x - radius, center.y + 3), room["label"], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 7, Color("#f1f5df"))
		else:
			var room_size: Vector2 = room["size"] * MAP_SCALE
			var rect := Rect2(center - room_size * 0.5, room_size)
			draw_rect(rect, ROOM_ACTIVE if is_current_room else ROOM_COLOR, true)
			draw_rect(rect, ROOM_ACTIVE_OUTLINE if is_current_room else ROOM_OUTLINE, false, 2.0 if is_current_room else 1.0)
			draw_string(font, Vector2(rect.position.x, center.y + 3), room["label"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 7, Color("#fff0a6") if is_current_room else Color("#e1f3f3"))

	# Tiny outside markers mirror the solar panels and dish in the world.
	var solar_left := _to_map(Vector2(-4.2, 17.0), map_center)
	var solar_right := _to_map(Vector2(-1.5, 17.0), map_center)
	var dish := _to_map(Vector2(4.2, 17.0), map_center)
	draw_rect(Rect2(solar_left - Vector2(4, 2), Vector2(8, 4)), Color("#52b9dc"), true)
	draw_rect(Rect2(solar_right - Vector2(4, 2), Vector2(8, 4)), Color("#52b9dc"), true)
	draw_circle(dish, 3.0, Color("#f0d68c"))

	if is_instance_valid(player):
		var marker := _to_map(Vector2(player.global_position.x, player.global_position.z), map_center)
		draw_circle(marker, 4.0, Color("#8effee"))
		draw_arc(marker, 7.0, 0.0, TAU, 24, Color(0.56, 1.0, 0.92, 0.8), 1.0)


func _to_map(world_position: Vector2, map_center: Vector2) -> Vector2:
	return map_center + world_position * MAP_SCALE
