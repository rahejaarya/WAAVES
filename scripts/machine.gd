@tool
class_name Machine
extends StaticBody2D

# A machine or prop standing on the floor. Its origin is the bottom-centre of the sprite.
# Give it a station_id to make it a task station the player can use with E
# (the ids match the tasks in campaign.gd). Leave station_id empty for decoration.

@export var station_id := "":
	set(value):
		station_id = value
		_refresh()
@export var texture: Texture2D:
	set(value):
		texture = value
		_refresh()
## Height (px) of the solid part at the base of the sprite. 0 = automatic.
@export var footprint_height := 0.0:
	set(value):
		footprint_height = value
		_refresh()
@export var solid := true:
	set(value):
		solid = value
		_refresh()

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_refresh()
	if station_id != "" and not Engine.is_editor_hint():
		add_to_group("stations")


func _refresh() -> void:
	if not is_node_ready():
		return
	sprite.texture = texture
	if texture == null:
		return
	var size := texture.get_size()
	sprite.offset = Vector2(0, -size.y / 2.0)
	var height := footprint_height if footprint_height > 0.0 else minf(size.y * 0.6, size.y - 2.0)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(size.x - 2.0, 4.0), height)
	collision.shape = shape
	collision.position = Vector2(0, -height / 2.0)
	collision.disabled = not solid


# Distance from a world point to this machine's solid base.
func distance_to(point: Vector2) -> float:
	if texture == null:
		return global_position.distance_to(point)
	var size := texture.get_size()
	var rect := Rect2(global_position - Vector2(size.x / 2.0, size.y * 0.6), Vector2(size.x, size.y * 0.6))
	var closest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return closest.distance_to(point)


func set_highlighted(on: bool) -> void:
	sprite.modulate = Color(1.25, 1.25, 1.1) if on else Color.WHITE


# World position just above the sprite (for the task arrow).
func top_position() -> Vector2:
	var h := texture.get_size().y if texture else 16.0
	return global_position + Vector2(0, -h - 2)
