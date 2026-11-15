@tool
class_name Room
extends Node2D

# One room (or hallway) of the habitat. tile_rect is in tile coordinates (16px tiles)
# and includes the room's walls. Machines that belong to the room are its children.

@export var room_id := ""
@export var title := ""
@export var tile_rect := Rect2i()
@export var is_hallway := false
@export var map_color := Color("#1a2b31")


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("rooms")


func contains_tile(tile: Vector2i) -> bool:
	return tile_rect.has_point(tile)
