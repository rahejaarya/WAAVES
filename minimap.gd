extends Control

const MAP_SCALE := 2.6
const PANEL_COLOR := Color(0.025, 0.065, 0.085, 0.94)
const ROOM_COLOR := Color(0.10, 0.17, 0.20, 0.98)
const ROOM_OUTLINE := Color(0.31, 0.52, 0.55, 0.95)
const MAP_LINK := Color(0.31, 0.47, 0.49, 0.88)
const ROOM_ACTIVE := Color(0.15, 0.34, 0.36, 1.0)
const ROOM_ACTIVE_OUTLINE := Color("#d6ba72")

const ROOMS := [
	{"id": "garden", "label": "GARDEN", "center": Vector2(0, -28), "size": Vector2(12, 10)},
	{"id": "dining", "label": "DINING", "center": Vector2(0, -16), "size": Vector2(16, 12)},
	{"id": "med", "label": "MED BAY", "center": Vector2(-18, -16), "size": Vector2(12, 12)},
	{"id": "restroom", "label": "RESTROOM", "center": Vector2(18, -16), "size": Vector2(12, 12)},
	{"id": "lab", "label": "LAB", "center": Vector2(-18, 0), "size": Vector2(12, 12)},
	{"id": "main", "label": "MAIN", "center": Vector2(0, 0), "size": Vector2(16, 12)},
	{"id": "sleep", "label": "BEDROOM", "center": Vector2(18, 0), "size": Vector2(12, 12)},
	{"id": "airlock", "label": "AIRLOCK", "center": Vector2(0, 13), "size": Vector2(8, 8)},
	{"id": "outside", "label": "OUTSIDE", "center": Vector2(0, 29), "size": Vector2(34, 34)}
]

const LINKS := [
	["main", "dining"], ["dining", "garden"], ["dining", "med"],
	["med", "lab"], ["lab", "main"], ["dining", "restroom"],
	["restroom", "sleep"], ["main", "sleep"], ["main", "airlock"], ["airlock", "outside"]
]

var player: Node3D
var current_room_id := "main"


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return

	var panel := Rect2(Vector2.ZERO, size)
	var plate := StyleBoxFlat.new()
	plate.bg_color = PANEL_COLOR
	plate.border_color = ROOM_OUTLINE
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(8)
	draw_style_box(plate, panel)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(13, 20), "HABITAT  /  DECK PLAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d8e5e2"))
	draw_string(font, Vector2(size.x - 25, 20), "N", HORIZONTAL_ALIGNMENT_CENTER, 12, 10, Color("#d6ba72"))
	draw_line(Vector2(12, 28), Vector2(size.x - 12, 28), ROOM_OUTLINE, 1.0)

	var map_center := Vector2(size.x * 0.5, size.y * 0.5)
	var points: Dictionary = {}
	for room: Dictionary in ROOMS:
		points[room["id"]] = _to_map(room["center"], map_center)

	for link: Array in LINKS:
		draw_line(points[link[0]], points[link[1]], MAP_LINK, 2.0)

	for room: Dictionary in ROOMS:
		var center: Vector2 = points[room["id"]]
		var is_current_room: bool = room["id"] == current_room_id
		#this is for when the player goes off the map 
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
			draw_string(font, Vector2(rect.position.x, center.y + 3), room["label"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 8, Color("#fff0a6") if is_current_room else Color("#d4e0df"))

	# Tiny outside markers mirror the solar panels and dish in the world.
	var solar_left := _to_map(Vector2(-7.8, 27.0), map_center)
	var solar_right := _to_map(Vector2(-4.2, 27.0), map_center)
	var dish := _to_map(Vector2(-10.0, 35.0), map_center)
	draw_rect(Rect2(solar_left - Vector2(4, 2), Vector2(8, 4)), Color("#52b9dc"), true)
	draw_rect(Rect2(solar_right - Vector2(4, 2), Vector2(8, 4)), Color("#52b9dc"), true)
	draw_circle(dish, 3.0, Color("#f0d68c"))

	if is_instance_valid(player):
		var marker := _to_map(Vector2(player.global_position.x, player.global_position.z), map_center)
		draw_circle(marker, 4.0, Color("#8effee"))
		draw_arc(marker, 7.0, 0.0, TAU, 24, Color(0.56, 1.0, 0.92, 0.8), 1.0)


func _to_map(world_position: Vector2, map_center: Vector2) -> Vector2:
	return map_center + world_position * MAP_SCALE
