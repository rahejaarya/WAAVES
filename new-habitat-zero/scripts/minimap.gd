extends Control

# Deck plan in the top-right corner. Reads the Room nodes, so moving or resizing a room
# in main.tscn updates the map automatically.

const SCALE := 1.0
const PANEL := Color(0.025, 0.065, 0.085, 0.92)
const OUTLINE := Color(0.31, 0.52, 0.55, 0.95)
const ACTIVE := Color("#d6ba72")

var rooms: Array[Room] = []
var player: Node2D
var target_position := Vector2.INF
var current_room_id := ""
var bounds := Rect2i()


func setup(room_nodes: Array[Room], player_node: Node2D) -> void:
	rooms = room_nodes
	player = player_node
	bounds = Rect2i()
	for room in rooms:
		bounds = room.tile_rect if bounds.size == Vector2i.ZERO else bounds.merge(room.tile_rect)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PANEL)
	draw_rect(Rect2(Vector2.ZERO, size), OUTLINE, false, 1.0)
	if rooms.is_empty():
		return
	var origin := Vector2(size.x / 2.0, 3.0) - Vector2(bounds.position.x + bounds.size.x / 2.0, bounds.position.y) * SCALE
	for room in rooms:
		var rect := Rect2(origin + Vector2(room.tile_rect.position) * SCALE, Vector2(room.tile_rect.size) * SCALE)
		var fill := room.map_color
		if room.room_id == current_room_id:
			fill = fill.lightened(0.25)
		draw_rect(rect, fill)
		if not room.is_hallway:
			draw_rect(rect, ACTIVE if room.room_id == current_room_id else OUTLINE, false, 1.0)
	if target_position != Vector2.INF:
		var target := origin + target_position / 16.0 * SCALE
		draw_rect(Rect2((target - Vector2(1, 1)).floor(), Vector2(3, 3)), Color("#ffd35c"))
	if is_instance_valid(player):
		var dot := origin + player.global_position / 16.0 * SCALE
		draw_rect(Rect2((dot - Vector2(1, 1)).floor(), Vector2(2, 2)), Color("#ffffff"))
