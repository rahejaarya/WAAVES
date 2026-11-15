extends Node2D

# Ties the world, the player, the HUD and the day/slot campaign together.
# The level itself lives in main.tscn as nodes: World > Ground / Floors / Walls (tile layers),
# World > Objects > Rooms > <Room> > <Machine>, and World > Objects > Outside.

const TILE := 16
const INTERACT_RANGE := 13.0

@onready var player: CharacterBody2D = %Player
@onready var campaign: CanvasLayer = $Campaign
@onready var hud: CanvasLayer = $HUD
@onready var task_marker: Node2D = %TaskMarker

var rooms: Array[Room] = []
var stations: Array[Machine] = []
var hovered: Machine
var shake_time := 0.0


func _ready() -> void:
	for node in get_tree().get_nodes_in_group("rooms"):
		rooms.append(node as Room)
	# Real rooms first so a doorway counts as the room, not the hallway.
	rooms.sort_custom(func(a: Room, b: Room) -> bool: return int(a.is_hallway) < int(b.is_hallway))
	for node in get_tree().get_nodes_in_group("stations"):
		stations.append(node as Machine)
	campaign.player = player
	hud.minimap.setup(rooms, player)


func _process(delta: float) -> void:
	var room_id := _room_id_at_player()
	hud.set_room(_room_title(room_id))
	hud.minimap.current_room_id = room_id
	_update_hover()
	_update_task_marker()
	# Day 3-4: air is leaking until the hole is patched.
	hud.set_alarm(not campaign.ended and campaign.day in [3, 4] and not campaign.leak_fixed, delta)
	# Day 5: moonquake.
	if campaign.day == 5 and not campaign.ended:
		shake_time += delta
		player.camera.offset = Vector2(roundf(sin(shake_time * 37.0)), roundf(cos(shake_time * 29.0)))
	else:
		player.camera.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and hovered != null and not campaign.is_board_open():
		player.stop()
		campaign.interact_with_station(hovered.station_id)
		get_viewport().set_input_as_handled()


func _update_hover() -> void:
	var best: Machine = null
	var best_distance := INTERACT_RANGE
	if not campaign.is_board_open():
		for station in stations:
			var distance := station.distance_to(player.global_position)
			if distance < best_distance:
				best = station
				best_distance = distance
	if best != hovered:
		if hovered != null:
			hovered.set_highlighted(false)
		hovered = best
		if hovered != null:
			hovered.set_highlighted(true)
	hud.set_hint("" if hovered == null else campaign.station_hint(hovered.station_id))


func _update_task_marker() -> void:
	var station_id := ""
	var pinned: Dictionary = campaign.get_pinned_action()
	if not pinned.is_empty():
		station_id = str(pinned["station"])
	elif campaign.awaiting_bed:
		station_id = "bed"
	var target: Machine = null
	for station in stations:
		if station.station_id == station_id and (target == null or station.global_position.distance_to(player.global_position) < target.global_position.distance_to(player.global_position)):
			target = station
	task_marker.visible = target != null and not campaign.ended
	hud.minimap.target_position = target.global_position if target != null else Vector2.INF
	if target != null:
		task_marker.global_position = target.top_position()


# ---- used by campaign.gd

func _room_id_at_player() -> String:
	var tile := Vector2i((player.global_position / TILE).floor())
	for room in rooms:
		if room.contains_tile(tile):
			return room.room_id
	return "hall"


func _room_title(room_id: String) -> String:
	for room in rooms:
		if room.room_id == room_id:
			return room.title
	return "HALLWAY"
