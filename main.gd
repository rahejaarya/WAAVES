extends Node3D

const MinimapScript := preload("res://minimap.gd")
const CampaignScript := preload("res://campaign.gd")

const FLOOR_THICKNESS := 0.3
const WALL_HEIGHT := 4.4
const WALL_THICKNESS := 0.32
const DOOR_WIDTH := 2.2

const ROOMS := [
	{"id": "main", "title": "MAIN ROOM", "center": Vector2(0, 0), "size": Vector2(16, 12), "doors": ["north", "east", "south", "west"], "floor": Color("#596462")},
	{"id": "dining", "title": "DINING ROOM", "center": Vector2(0, -16), "size": Vector2(16, 12), "doors": ["north", "east", "south", "west"], "floor": Color("#59635f")},
	{"id": "garden", "title": "GARDEN", "center": Vector2(0, -28), "size": Vector2(12, 10), "doors": ["south"], "floor": Color("#334739")},
	{"id": "med", "title": "MEDICAL BAY", "center": Vector2(-18, -16), "size": Vector2(12, 12), "doors": ["east", "south"], "floor": Color("#596564")},
	{"id": "lab", "title": "LAB", "center": Vector2(-18, 0), "size": Vector2(12, 12), "doors": ["north", "east"], "floor": Color("#575861")},
	{"id": "restroom", "title": "RESTROOM", "center": Vector2(18, -16), "size": Vector2(12, 12), "doors": ["west", "south"], "floor": Color("#5c6260")},
	{"id": "sleep", "title": "CREW QUARTERS", "center": Vector2(18, 0), "size": Vector2(12, 12), "doors": ["north", "west"], "floor": Color("#5b6065")},
	{"id": "airlock", "title": "AIRLOCK", "center": Vector2(0, 13), "size": Vector2(8, 8), "doors": ["north", "south"], "floor": Color("#535c5d")}
]

const LINKS := [
	["main", "dining"], ["dining", "garden"], ["dining", "med"],
	["med", "lab"], ["lab", "main"], ["dining", "restroom"],
	["restroom", "sleep"], ["main", "sleep"], ["main", "airlock"]
]

const ROOM_WALL_COLOR := Color("#aab6b3")
const CORRIDOR_COLOR := Color("#707e80")

@onready var player: CharacterBody3D = $Player

var world_root: Node3D
var follow_camera: Camera3D
var room_label: Label
var minimap: Control
var campaign_ui: CanvasLayer
var interaction_hint: Label
var hovered_station := ""
var materials: Dictionary = {}
var rooms_by_id: Dictionary = {}


func _ready() -> void:
	# Spawn clear of furniture, facing into the open main deck.
	player.position = Vector3(-2.0, 0.0, 0.0)
	player.rotation.y = 0.0
	for room: Dictionary in ROOMS:
		rooms_by_id[room["id"]] = room
	_build_environment()
	world_root = Node3D.new()
	world_root.name = "Habitat"
	add_child(world_root)
	_build_rooms()
	_build_habitat_foundation()
	_build_corridors()
	_build_outside()
	_add_room_props()
	_build_camera()
	_build_hud()
	campaign_ui = CanvasLayer.new()
	campaign_ui.name = "Campaign"
	campaign_ui.set_script(CampaignScript)
	campaign_ui.set("player", player)
	add_child(campaign_ui)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var current_room_id := _room_id_at_player()
	room_label.text = "AREA  /  " + _room_title(current_room_id)
	minimap.set("current_room_id", current_room_id)
	_update_station_hover()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and hovered_station != "" and not campaign_ui.call("is_board_open"):
		campaign_ui.call("interact_with_station", hovered_station)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_instance_valid(campaign_ui) and campaign_ui.call("is_board_open"):
			campaign_ui.call("toggle_board")
			return
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotation.y -= event.relative.x * 0.0025
		follow_camera.rotation.x = clampf(follow_camera.rotation.x - event.relative.y * 0.0022, deg_to_rad(-55.0), deg_to_rad(18.0))


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	# The lunar exterior has no blue atmospheric sky; let the LRO globe define the horizon.
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#02050a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#bbc5ce")
	environment.ambient_light_energy = 0.28
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "Soft Station Light"
	key_light.rotation_degrees = Vector3(-38, -32, 0)
	key_light.light_energy = 1.8
	key_light.shadow_enabled = true
	add_child(key_light)


func _build_rooms() -> void:
	for room: Dictionary in ROOMS:
		_build_room(room)


func _build_room(room: Dictionary) -> void:
	var center: Vector2 = room["center"]
	var size: Vector2 = room["size"]
	var floor_color: Color = room["floor"]
	_make_box(
		world_root,
		str(room["title"]) + " Floor",
		Vector3(center.x, -FLOOR_THICKNESS * 0.5, center.y),
		Vector3(size.x, FLOOR_THICKNESS, size.y),
		floor_color
	)
	_build_room_details(room)

	for side: String in ["north", "east", "south", "west"]:
		var has_door: bool = room["doors"].has(side)
		_build_wall(room, side, has_door)
		_build_wall_ribs(room, side, has_door)
		if has_door:
			_build_door_threshold(room, side)


func _build_wall_ribs(room: Dictionary, side: String, has_door: bool) -> void:
	var center: Vector2 = room["center"]
	var size: Vector2 = room["size"]
	var along_x := side == "north" or side == "south"
	var length := size.x if along_x else size.y
	var wall_offset := size.y * 0.5 if along_x else size.x * 0.5
	var inward := 0.13 if side == "north" or side == "west" else -0.13
	for rib_index in range(1, int(length / 2.5)):
		var along := -length * 0.5 + float(rib_index) * 2.5
		if has_door and absf(along) < DOOR_WIDTH * 0.5 + 0.2:
			continue
		var rib_position := Vector3(center.x, WALL_HEIGHT * 0.5, center.y)
		var rib_size := Vector3(0.055, WALL_HEIGHT - 0.34, 0.035)
		if along_x:
			rib_position.x += along
			rib_position.z += -wall_offset + inward if side == "north" else wall_offset + inward
		else:
			rib_position.z += along
			rib_position.x += -wall_offset + inward if side == "west" else wall_offset + inward
			rib_size = Vector3(0.035, WALL_HEIGHT - 0.34, 0.055)
		_make_visual_box(str(room["id"]) + " wall service rib", rib_position, rib_size, Color("#8d9b99"))


func _build_room_details(room: Dictionary) -> void:
	var center: Vector2 = room["center"]
	var size: Vector2 = room["size"]
	var title := str(room["title"])
	_make_box(world_root, title + " pressure hull ceiling", Vector3(center.x, WALL_HEIGHT + 0.04, center.y), Vector3(size.x, 0.18, size.y), Color("#8e9b99"))
	# Long, recessed ceiling lights create a clean spacecraft interior without heavy effects.
	for light_x: float in [-size.x * 0.24, size.x * 0.24]:
		_make_emissive_box(title + " ceiling light", Vector3(center.x + light_x, WALL_HEIGHT - 0.075, center.y), Vector3(0.32, 0.035, size.y * 0.68), Color("#d8ffff"), 0.8)
	var area_light := OmniLight3D.new()
	area_light.name = title + " interior light"
	area_light.position = Vector3(center.x, 2.35, center.y)
	area_light.light_color = Color("#e3f1eb")
	area_light.light_energy = 0.7
	area_light.omni_range = maxf(size.x, size.y) * 0.8
	world_root.add_child(area_light)
	# Thin floor seams break up the broad flat color into serviceable modular panels.
	for seam_x in range(1, int(size.x / 3.0)):
		var x := center.x - size.x * 0.5 + float(seam_x) * 3.0
		_make_visual_box(title + " floor seam", Vector3(x, 0.008, center.y), Vector3(0.025, 0.012, size.y - 0.5), Color("#77878a"))
	for seam_z in range(1, int(size.y / 3.0)):
		var z := center.y - size.y * 0.5 + float(seam_z) * 3.0
		_make_visual_box(title + " floor seam", Vector3(center.x, 0.009, z), Vector3(size.x - 0.5, 0.012, 0.025), Color("#77878a"))


func _build_door_threshold(room: Dictionary, side: String) -> void:
	var center: Vector2 = room["center"]
	var room_size: Vector2 = room["size"]
	var threshold_position := Vector3(center.x, 0.025, center.y)
	var threshold_size := Vector3(DOOR_WIDTH, 0.035, 0.13)
	if side == "north":
		threshold_position.z -= room_size.y * 0.5
	elif side == "south":
		threshold_position.z += room_size.y * 0.5
	elif side == "east":
		threshold_position.x += room_size.x * 0.5
		threshold_size = Vector3(0.13, 0.035, DOOR_WIDTH)
	else:
		threshold_position.x -= room_size.x * 0.5
		threshold_size = Vector3(0.13, 0.035, DOOR_WIDTH)
	_make_visual_box(str(room["title"]) + " doorway marker", threshold_position, threshold_size, Color("#4f9b9f"))
	var jamb_size := Vector3(0.28, WALL_HEIGHT - 0.16, 0.38)
	var lintel_size := Vector3(DOOR_WIDTH + 0.16, 0.24, 0.38)
	if side == "north" or side == "south":
		var wall_z := center.y + (-room_size.y * 0.5 if side == "north" else room_size.y * 0.5)
		for offset: float in [-1.0, 1.0]:
			_make_box(world_root, str(room["title"]) + " hatch jamb", Vector3(center.x + offset * DOOR_WIDTH * 0.5, WALL_HEIGHT * 0.5, wall_z), jamb_size, Color("#697a7b"))
		_make_box(world_root, str(room["title"]) + " hatch lintel", Vector3(center.x, WALL_HEIGHT - 0.12, wall_z), lintel_size, Color("#697a7b"))
		for offset: float in [-1.0, 1.0]:
			_make_visual_box(str(room["title"]) + " hatch warning light", Vector3(center.x + offset * (DOOR_WIDTH * 0.5 + 0.34), WALL_HEIGHT - 0.32, wall_z), Vector3(0.12, 0.12, 0.08), Color("#d4b766"))
	else:
		var wall_x := center.x + (room_size.x * 0.5 if side == "east" else -room_size.x * 0.5)
		jamb_size = Vector3(0.38, WALL_HEIGHT - 0.16, 0.28)
		lintel_size = Vector3(0.38, 0.24, DOOR_WIDTH + 0.16)
		for offset: float in [-1.0, 1.0]:
			_make_box(world_root, str(room["title"]) + " hatch jamb", Vector3(wall_x, WALL_HEIGHT * 0.5, center.y + offset * DOOR_WIDTH * 0.5), jamb_size, Color("#697a7b"))
		_make_box(world_root, str(room["title"]) + " hatch lintel", Vector3(wall_x, WALL_HEIGHT - 0.12, center.y), lintel_size, Color("#697a7b"))
		for offset: float in [-1.0, 1.0]:
			_make_visual_box(str(room["title"]) + " hatch warning light", Vector3(wall_x, WALL_HEIGHT - 0.32, center.y + offset * (DOOR_WIDTH * 0.5 + 0.34)), Vector3(0.08, 0.12, 0.12), Color("#d4b766"))


func _build_wall(room: Dictionary, side: String, has_door: bool) -> void:
	var center: Vector2 = room["center"]
	var size: Vector2 = room["size"]
	var along_x := side == "north" or side == "south"
	var total_length := size.x if along_x else size.y
	var wall_position := Vector3(center.x, WALL_HEIGHT * 0.5, center.y)
	var segment_size: Vector3
	if side == "north":
		wall_position.z -= size.y * 0.5
		segment_size = Vector3(total_length, WALL_HEIGHT, WALL_THICKNESS)
	elif side == "south":
		wall_position.z += size.y * 0.5
		segment_size = Vector3(total_length, WALL_HEIGHT, WALL_THICKNESS)
	elif side == "east":
		wall_position.x += size.x * 0.5
		segment_size = Vector3(WALL_THICKNESS, WALL_HEIGHT, total_length)
	else:
		wall_position.x -= size.x * 0.5
		segment_size = Vector3(WALL_THICKNESS, WALL_HEIGHT, total_length)

	if not has_door:
		_make_box(world_root, str(room["id"]) + " " + side + " wall", wall_position, segment_size, ROOM_WALL_COLOR)
		return

	var segment_length := (total_length - DOOR_WIDTH) * 0.5
	if segment_length <= 0.0:
		return
	for direction: float in [-1.0, 1.0]:
		var segment_position := wall_position
		if along_x:
			segment_position.x += direction * (DOOR_WIDTH * 0.5 + segment_length * 0.5)
			segment_size = Vector3(segment_length, WALL_HEIGHT, WALL_THICKNESS)
		else:
			segment_position.z += direction * (DOOR_WIDTH * 0.5 + segment_length * 0.5)
			segment_size = Vector3(WALL_THICKNESS, WALL_HEIGHT, segment_length)
		_make_box(world_root, str(room["id"]) + " " + side + " wall segment", segment_position, segment_size, ROOM_WALL_COLOR)


func _build_corridors() -> void:
	# Extend each corridor deck beneath the doorway thresholds. Its slight height
	# offset prevents coplanar floor surfaces from z-fighting at room joins.
	var corridor_deck_y := -FLOOR_THICKNESS * 0.5 + 0.025
	var doorway_overlap := 0.55
	for link: Array in LINKS:
		var first: Dictionary = rooms_by_id[link[0]]
		var second: Dictionary = rooms_by_id[link[1]]
		var first_center: Vector2 = first["center"]
		var second_center: Vector2 = second["center"]
		var first_size: Vector2 = first["size"]
		var second_size: Vector2 = second["size"]
		var delta := second_center - first_center
		var first_side := "east" if delta.x > 0.0 else "west" if delta.x < 0.0 else "south" if delta.y > 0.0 else "north"
		var second_side := "west" if delta.x > 0.0 else "east" if delta.x < 0.0 else "north" if delta.y > 0.0 else "south"
		if not first["doors"].has(first_side) or not second["doors"].has(second_side):
			push_error("Unaligned habitat link: %s -> %s" % [first["id"], second["id"]])
			continue
		var corridor_center := Vector2.ZERO
		var corridor_size := Vector2.ZERO
		if absf(delta.x) > absf(delta.y):
			var length := absf(delta.x) - (first_size.x + second_size.x) * 0.5 + doorway_overlap * 2.0
			if length <= 0.05:
				continue
			corridor_center = Vector2((first_center.x + second_center.x) * 0.5, (first_center.y + second_center.y) * 0.5)
			corridor_size = Vector2(length, DOOR_WIDTH)
		else:
			var length := absf(delta.y) - (first_size.y + second_size.y) * 0.5 + doorway_overlap * 2.0
			if length <= 0.05:
				continue
			corridor_center = Vector2(first_center.x, (first_center.y + second_center.y) * 0.5)
			corridor_size = Vector2(DOOR_WIDTH, length)
		_make_box(
			world_root,
			str(first["title"]) + " to " + str(second["title"]) + " Hall",
			Vector3(corridor_center.x, corridor_deck_y, corridor_center.y),
			Vector3(corridor_size.x, FLOOR_THICKNESS, corridor_size.y),
			CORRIDOR_COLOR
		)
		_build_corridor_shell(first, second, corridor_center, corridor_size, absf(delta.x) > absf(delta.y))


func _build_corridor_shell(first: Dictionary, _second: Dictionary, center: Vector2, size: Vector2, runs_along_x: bool) -> void:
	# A continuous pressure-hull tunnel connects each doorway; its side walls overlap
	# the room bulkheads slightly so there are no gaps at either end.
	var overlap := 0.34
	if runs_along_x:
		for side: float in [-1.0, 1.0]:
			_make_box(world_root, "Corridor pressure wall", Vector3(center.x, WALL_HEIGHT * 0.5, center.y + side * (size.y * 0.5 - WALL_THICKNESS * 0.5)), Vector3(size.x + overlap * 2.0, WALL_HEIGHT, WALL_THICKNESS), ROOM_WALL_COLOR)
	else:
		for side: float in [-1.0, 1.0]:
			_make_box(world_root, "Corridor pressure wall", Vector3(center.x + side * (size.x * 0.5 - WALL_THICKNESS * 0.5), WALL_HEIGHT * 0.5, center.y), Vector3(WALL_THICKNESS, WALL_HEIGHT, size.y + overlap * 2.0), ROOM_WALL_COLOR)
	_make_box(world_root, str(first["title"]) + " corridor ceiling", Vector3(center.x, WALL_HEIGHT + 0.10, center.y), Vector3(size.x + overlap * 2.0, 0.18, size.y + overlap * 2.0), Color("#8e9b99"))
	var light_size := Vector3(size.x * 0.52, 0.035, 0.34) if runs_along_x else Vector3(0.34, 0.035, size.y * 0.52)
	_make_emissive_box("Corridor recessed light", Vector3(center.x, WALL_HEIGHT - 0.08, center.y), light_size, Color("#d9ffff"), 0.65)


func _build_outside() -> void:
	_add_lro_moon_surface()
	var outside_center := Vector3(0, -0.17, 0)
	var surface := StaticBody3D.new()
	surface.name = "Dust covered landing apron"
	surface.position = outside_center
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 330.0
	disc_mesh.bottom_radius = 330.5
	disc_mesh.height = 0.18
	disc_mesh.radial_segments = 192
	var disc_instance := MeshInstance3D.new()
	disc_instance.mesh = disc_mesh
	var regolith_material := StandardMaterial3D.new()
	regolith_material.albedo_color = Color("#98958d")
	regolith_material.albedo_texture = load("res://assets/nasa/moon_surface/apollo11_regolith_closeup.jpg") as Texture2D
	regolith_material.uv1_scale = Vector3(32.0, 32.0, 1.0)
	regolith_material.roughness = 1.0
	regolith_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	disc_instance.material_override = regolith_material
	surface.add_child(disc_instance)
	var disc_shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 330.0
	cylinder.height = 0.18
	disc_shape.shape = cylinder
	surface.add_child(disc_shape)
	world_root.add_child(surface)

	_add_nasa_habitat_model()
	_add_solar_panels()
	_add_satellite_dish()
	_add_exterior_task_stations()
	_add_lunar_surface_rocks()
	_add_moon_route()


func _add_lro_moon_surface() -> void:
	# NASA SVS Moon model uses imagery and topography from the Lunar Reconnaissance Orbiter.
	var moon_scene := load("res://assets/nasa/moon_surface/moon_small.glb") as PackedScene
	if moon_scene == null:
		push_warning("NASA LRO Moon surface model could not be loaded.")
		return
	var globe_radius := 11447.0 # Authored scale: model radius 1.2719 units, scaled by 9,000.
	var moon := moon_scene.instantiate()
	moon.name = "NASA LRO textured lunar surface"
	moon.scale = Vector3.ONE * 9000.0
	moon.position = Vector3(0, -globe_radius, 0)
	world_root.add_child(moon)


func _add_lunar_surface_rocks() -> void:
	# Rock clusters sit beyond the marked return loop and leave the trail unobstructed.
	var rock_sites: Array[Vector3] = [
		Vector3(-25.0, -0.08, 48.0), Vector3(28.0, -0.08, 58.0),
		Vector3(-34.0, -0.08, 110.0), Vector3(38.0, -0.08, 144.0),
		Vector3(-29.0, -0.08, 188.0), Vector3(31.0, -0.08, 205.0),
		Vector3(-172.0, -0.08, 102.0), Vector3(176.0, -0.08, 112.0),
		Vector3(-120.0, -0.08, -118.0), Vector3(124.0, -0.08, -126.0),
		Vector3(-48.0, -0.08, -185.0), Vector3(52.0, -0.08, -194.0)
	]
	for index in range(rock_sites.size()):
		var rock_body := StaticBody3D.new()
		rock_body.name = "Lunar boulder %02d" % index
		var rock := MeshInstance3D.new()
		rock.name = "Irregular lunar boulder mesh"
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 1.6
		mesh.radial_segments = 12
		mesh.rings = 6
		rock.mesh = mesh
		var scale_factor := 0.55 + float(index % 3) * 0.22
		rock.scale = Vector3(scale_factor * 1.3, scale_factor * 0.72, scale_factor)
		rock.rotation = Vector3(0.18 * float(index), 0.63 * float(index), 0.11 * float(index))
		rock.material_override = _material(Color("#77736d"))
		rock_body.position = rock_sites[index]
		rock_body.add_child(rock)
		var boulder_collision := CollisionShape3D.new()
		var boulder_shape := SphereShape3D.new()
		boulder_shape.radius = scale_factor * 0.8
		boulder_collision.shape = boulder_shape
		rock_body.add_child(boulder_collision)
		world_root.add_child(rock_body)


func _add_moon_route() -> void:
	# A broad, continuous loop circles the base and returns to the airlock approach.
	# Its 785 m lap is sized for a short exploration walk in this game scale.
	var center := Vector2.ZERO
	var radius := 125.0
	var segments := 128
	for segment in range(segments):
		var angle := TAU * float(segment) / float(segments)
		var next_angle := TAU * float(segment + 1) / float(segments)
		var mid_angle := (angle + next_angle) * 0.5
		var point := center + Vector2(cos(mid_angle), sin(mid_angle)) * radius
		var segment_length := radius * (next_angle - angle) + 1.2
		var trail_segment := _make_box(world_root, "Lunar return loop trail", Vector3(point.x, -0.015, point.y), Vector3(7.0, 0.08, segment_length), Color("#716d66"), -mid_angle)
		trail_segment.collision_layer = 1
	# Join the exterior airlock to the closest loop point with an uninterrupted path.
	_make_box(world_root, "Airlock to lunar loop trail", Vector3(0.0, -0.015, 71.0), Vector3(7.0, 0.08, 108.0), Color("#716d66"))
	# Direction beacons and science stops make the long route legible at a distance.
	for marker in range(8):
		var angle := TAU * float(marker) / 8.0
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		var beacon_point := point + Vector2(-sin(angle), cos(angle)) * 6.0
		_make_solid_box("Lunar route beacon post", Vector3(beacon_point.x, 1.35, beacon_point.y), Vector3(0.24, 2.7, 0.24), Color("#bbc4bd"))
		_make_emissive_box("Lunar route beacon", Vector3(beacon_point.x, 2.8, beacon_point.y), Vector3(0.5, 0.28, 0.5), Color("#5be0ce"), 1.0)
		var direction_tile := _make_visual_box("Lunar route direction tile", Vector3(point.x, 0.04, point.y), Vector3(2.0, 0.025, 0.5), Color("#d9c17e"))
		direction_tile.rotation.y = -angle
	_add_route_photo_shelter()


func _add_route_photo_shelter() -> void:
	var shelter := Vector3(28.0, 0.0, 66.0)
	_make_solid_box("Lunar field shelter plinth", shelter + Vector3(0.0, 0.16, 0.0), Vector3(12.0, 0.32, 5.0), Color("#6f7775"))
	for x: float in [-5.4, 5.4]:
		_make_solid_box("Field shelter support", shelter + Vector3(x, 1.6, 0.0), Vector3(0.22, 3.2, 0.22), Color("#9aa7a2"))
	_make_solid_box("Field shelter header", shelter + Vector3(0.0, 3.18, 0.0), Vector3(11.0, 0.22, 0.22), Color("#9aa7a2"))
	_make_textured_screen("Apollo surface panorama at field shelter", shelter + Vector3(0.0, 2.05, 0.16), Vector2(9.8, 1.24), "res://assets/nasa/moon_surface/apollo17_station6_panorama.jpg", false)


func _add_nasa_habitat_model() -> void:
	# Official NASA/LaRC HDU reference model, assembled from its two published GLB parts.
	var model_body := StaticBody3D.new()
	model_body.name = "NASA Habitat Demonstration Unit reference model"
	model_body.position = Vector3(12.0, 2.7, 35.0)
	var body_collision := CollisionShape3D.new()
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(12.2, 5.4, 7.5)
	body_collision.shape = body_shape
	model_body.add_child(body_collision)
	for model_path: String in ["res://assets/nasa/habitat-demonstration-unit-part-1.glb", "res://assets/nasa/habitat-demonstration-unit-part-2.glb"]:
		var model_scene := load(model_path) as PackedScene
		if model_scene == null:
			push_warning("NASA Habitat Demonstration Unit model failed to load: " + model_path)
			continue
		var model_part := model_scene.instantiate()
		model_part.name = model_path.get_file().get_basename().replace("-", " ")
		model_part.scale = Vector3.ONE * 0.01
		model_body.add_child(model_part)
	world_root.add_child(model_body)


func _add_solar_panels() -> void:
	for x_position: float in [-7.8, -4.2]:
		var center := Vector3(x_position, 0.42, 27.0)
		_make_visual_box("Solar panel stand", center - Vector3(0, 0.22, 0), Vector3(0.16, 0.44, 0.16), Color("#8a9996"))
		_make_visual_box("Solar panel frame", center, Vector3(3.15, 0.16, 1.8), Color("#74838a"))
		_make_visual_box("Solar panel", center + Vector3(0, 0.1, 0), Vector3(2.97, 0.07, 1.63), Color("#174b65"))
		for strip in range(1, 4):
			var line_x := x_position - 1.0 + float(strip - 1) * 0.67
			_make_visual_box("Solar panel cell line", Vector3(line_x, 0.16, 27.0), Vector3(0.035, 0.025, 1.5), Color("#66cde0"))


func _add_exterior_task_stations() -> void:
	# Field tasks each have a physical, labeled target so the Mission Control
	# destination matches the equipment the player sees outside.
	_add_exterior_station("Neutron spectrometer rover", "neutron_station", Vector3(-7.0, 0.0, 23.0), "NEUTRON SPECTROMETER\nTransect console")
	_add_exterior_station("Rover battery service cart", "rover_station", Vector3(7.0, 0.0, 23.0), "ROVER POWER\nBattery / connectors")
	_add_exterior_station("Surface environment instrument", "field_station", Vector3(12.0, 0.0, 27.0), "SURFACE STATION\nRadiation / thermal")
	_add_exterior_station("Lunar sample collection case", "sample_station", Vector3(-12.0, 0.0, 27.0), "SAMPLE CACHE\nRock / regolith")
	_add_exterior_station("Hull inspection and patch kit", "hull_station", Vector3(20.0, 0.0, 36.0), "HULL INSPECTION\nUltrasound / patch kit")
	_add_exterior_station("Solar array service terminal", "solar_station", Vector3(-7.8, 0.0, 30.5), "SOLAR ARRAY\nPointing / output")


func _add_exterior_station(station_name: String, station_id: String, station_position: Vector3, label_text: String) -> void:
	var cabinet := _make_box(world_root, station_name, station_position + Vector3(0.0, 0.82, 0.0), Vector3(1.15, 1.64, 0.78), Color("#62777a"))
	cabinet.set_meta("station_id", station_id)
	_make_visual_box(station_name + " status display", station_position + Vector3(0.0, 1.26, -0.405), Vector3(0.72, 0.38, 0.035), Color("#4bafb1"))
	_add_status_panel_face(station_position + Vector3(0.0, 1.26, -0.43), 0.58, 0.26)
	for side: float in [-1.0, 1.0]:
		_make_visual_box(station_name + " armored corner rail", station_position + Vector3(side * 0.52, 0.82, -0.405), Vector3(0.07, 1.5, 0.07), Color("#aebbb4"))
	match station_id:
		"neutron_station":
			_add_rover_detail(station_position)
		"rover_station":
			_add_battery_cart_detail(station_position)
		"field_station":
			_add_surface_sensor_detail(station_position)
		"sample_station":
			_add_sample_cache_detail(station_position)
		"hull_station":
			_add_repair_kit_detail(station_position)
		"solar_station":
			_add_solar_service_detail(station_position)
	_make_text_panel(label_text, station_position + Vector3(0.0, 2.05, -0.02), Vector2(2.65, 0.62), 0.0)


func _add_rover_detail(station_position: Vector3) -> void:
	var rover_position := station_position + Vector3(-1.75, 0.0, 0.0)
	_make_solid_box("Neutron rover chassis", rover_position + Vector3(0.0, 0.58, 0.55), Vector3(1.9, 0.5, 1.25), Color("#7a8580"))
	for wheel_x: float in [-0.82, 0.82]:
		for wheel_z: float in [0.12, 0.98]:
			var wheel := _make_visual_cylinder("Rover rugged wheel", rover_position + Vector3(wheel_x, 0.28, wheel_z), 0.28, 0.18, Color("#252f32"))
			wheel.rotation.z = PI * 0.5
			_make_visual_torus("Rover wheel tread ring", rover_position + Vector3(wheel_x * 1.05, 0.28, wheel_z), 0.2, 0.035, Color("#64706e"))
	_make_visual_strut("Spectrometer detector mast", rover_position + Vector3(0.0, 0.86, 0.72), rover_position + Vector3(0.0, 1.75, 0.72), 0.045, Color("#b7c1b8"))
	_make_visual_cylinder("Neutron detector head", rover_position + Vector3(0.0, 1.82, 0.72), 0.24, 0.24, Color("#c3b276"))
	_make_visual_box("Rover solar deck", rover_position + Vector3(0.0, 0.91, 0.55), Vector3(1.15, 0.045, 0.72), Color("#17475c"))


func _add_battery_cart_detail(station_position: Vector3) -> void:
	for wheel_x: float in [-0.48, 0.48]:
		var wheel := _make_visual_cylinder("Battery cart wheel", station_position + Vector3(wheel_x, 0.14, 0.42), 0.16, 0.12, Color("#293336"))
		wheel.rotation.z = PI * 0.5
	for battery_x: float in [-0.25, 0.25]:
		_make_visual_box("Rover removable battery module", station_position + Vector3(battery_x, 1.82, 0.42), Vector3(0.38, 0.3, 0.42), Color("#98a8a0"))
		_make_visual_box("Battery connector cap", station_position + Vector3(battery_x, 2.0, 0.42), Vector3(0.14, 0.06, 0.18), Color("#d4ba6a"))


func _add_surface_sensor_detail(station_position: Vector3) -> void:
	_make_visual_strut("Surface instrument mast", station_position + Vector3(0.0, 1.55, 0.4), station_position + Vector3(0.0, 2.85, 0.4), 0.045, Color("#c2c9bc"))
	_make_visual_cylinder("Radiation detector puck", station_position + Vector3(0.0, 2.88, 0.4), 0.22, 0.14, Color("#d0ba72"))
	_make_visual_box("Thermal sensor shade", station_position + Vector3(0.0, 2.72, 0.4), Vector3(0.7, 0.08, 0.55), Color("#798985"))
	for antenna_x: float in [-0.3, 0.3]:
		_make_visual_strut("Dust sensor antenna", station_position + Vector3(antenna_x, 1.65, 0.42), station_position + Vector3(antenna_x, 2.15, 0.42), 0.025, Color("#d9c576"))


func _add_sample_cache_detail(station_position: Vector3) -> void:
	_make_visual_box("Sample cache lid", station_position + Vector3(0.0, 1.72, 0.4), Vector3(1.28, 0.12, 0.88), Color("#aab5aa"))
	for latch_x: float in [-0.42, 0.42]:
		_make_visual_box("Sample cache latch", station_position + Vector3(latch_x, 1.65, -0.01), Vector3(0.12, 0.22, 0.06), Color("#d8bd6e"))
	for vial_x: float in [-0.34, 0.0, 0.34]:
		_make_visual_cylinder("Sealed sample canister", station_position + Vector3(vial_x, 2.03, 0.42), 0.13, 0.34, Color("#d4d5c5"))
		_make_visual_cylinder("Sample canister ID cap", station_position + Vector3(vial_x, 2.22, 0.42), 0.14, 0.06, Color("#caa85b"))


func _add_repair_kit_detail(station_position: Vector3) -> void:
	_make_visual_box("Hull repair case lid", station_position + Vector3(0.0, 1.7, 0.42), Vector3(1.3, 0.12, 0.92), Color("#b0b9ae"))
	_make_visual_box("Pressure patch roll", station_position + Vector3(0.0, 1.95, 0.44), Vector3(0.9, 0.26, 0.66), Color("#d5c99c"))
	for tool_x: float in [-0.38, 0.38]:
		_make_visual_cylinder("Patch applicator handle", station_position + Vector3(tool_x, 1.98, 0.45), 0.07, 0.38, Color("#556a6e"))


func _add_solar_service_detail(station_position: Vector3) -> void:
	_make_visual_box("Solar array calibration screen bezel", station_position + Vector3(0.0, 1.68, -0.43), Vector3(0.94, 0.56, 0.08), Color("#344d54"))
	_make_emissive_box("Solar array output readout", station_position + Vector3(0.0, 1.68, -0.48), Vector3(0.76, 0.38, 0.025), Color("#56bcd0"), 0.45)
	for control_x: float in [-0.35, 0.0, 0.35]:
		_make_visual_cylinder("Solar array tuning knob", station_position + Vector3(control_x, 1.23, -0.45), 0.07, 0.08, Color("#d1b66e"))


func _add_satellite_dish() -> void:
	var base := _make_box(world_root, "Communications antenna footing", Vector3(-10.0, 0.12, 35.0), Vector3(2.3, 0.24, 2.3), Color("#757e7c"))
	base.set_meta("station_id", "eva_station")
	_make_text_panel("COMMUNICATIONS\nAntenna / link check", Vector3(-10.0, 3.25, 33.7), Vector2(3.0, 0.66), 0.0)
	base.position.y = -0.035
	var mount := _make_box(world_root, "Antenna azimuth mount", Vector3(-10.0, 0.38, 35.0), Vector3(0.9, 0.34, 0.9), Color("#b8c2bf"))
	var pedestal := _make_box(world_root, "Antenna mast", Vector3(-10.0, 1.25, 35.0), Vector3(0.22, 1.55, 0.22), Color("#aab5b2"))
	_make_visual_strut("Antenna left brace", Vector3(-10.0, 0.72, 35.0), Vector3(-10.85, 0.24, 35.0), 0.09, Color("#87938f"))
	_make_visual_strut("Antenna right brace", Vector3(-10.0, 0.72, 35.0), Vector3(-9.15, 0.24, 35.0), 0.09, Color("#87938f"))
	_make_visual_strut("Antenna back brace", Vector3(-10.0, 0.72, 35.0), Vector3(-10.0, 0.24, 35.85), 0.09, Color("#87938f"))
	_make_visual_strut("Antenna front brace", Vector3(-10.0, 0.72, 35.0), Vector3(-10.0, 0.24, 34.15), 0.09, Color("#87938f"))
	var dish_assembly := StaticBody3D.new()
	dish_assembly.name = "Directional lunar communications dish"
	dish_assembly.set_meta("station_id", "eva_station")
	dish_assembly.position = Vector3(-10.0, 2.03, 35.0)
	dish_assembly.rotation_degrees = Vector3(-48.0, 18.0, 0.0)
	world_root.add_child(dish_assembly)
	var dish := MeshInstance3D.new()
	dish.name = "Parabolic reflector"
	dish.mesh = _make_parabolic_dish_mesh(1.2, 0.42, 24, 64)
	var reflector_material := StandardMaterial3D.new()
	reflector_material.albedo_color = Color("#bfc9c6")
	reflector_material.metallic = 0.58
	reflector_material.roughness = 0.28
	reflector_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	dish.material_override = reflector_material
	dish_assembly.add_child(dish)
	var dish_collision := CollisionShape3D.new()
	dish_collision.shape = dish.mesh.create_trimesh_shape()
	dish_assembly.add_child(dish_collision)
	# A feed horn sits at the dish focus and is held clear of the reflecting bowl.
	_make_visual_strut("Antenna feed support A", Vector3(-0.72, 0.0, 0.0), Vector3(0.0, 0.0, 0.33), 0.035, Color("#889592"), dish_assembly)
	_make_visual_strut("Antenna feed support B", Vector3(0.72, 0.0, 0.0), Vector3(0.0, 0.0, 0.33), 0.035, Color("#889592"), dish_assembly)
	_make_visual_strut("Antenna feed support C", Vector3(0.0, -0.72, 0.0), Vector3(0.0, 0.0, 0.33), 0.035, Color("#889592"), dish_assembly)
	var feed := _make_visual_cylinder("Dish feed horn", Vector3(0.0, 0.0, 0.34), 0.14, 0.36, Color("#687c80"), dish_assembly)
	feed.rotation.x = PI * 0.5
	var radome := _make_visual_sphere("Feed radome", Vector3(0.0, 0.0, 0.48), 0.19, Color("#d7dfdc"), dish_assembly)
	radome.scale = Vector3(1.0, 1.0, 0.65)
	# A small solar-battery and control cabinet makes the surface antenna self-contained.
	_make_box(world_root, "Antenna power and control unit", Vector3(-12.0, 0.82, 35.0), Vector3(1.2, 1.45, 1.0), Color("#6b7f81"))
	_make_emissive_box("Antenna telemetry display", Vector3(-12.62, 1.05, 35.0), Vector3(0.04, 0.52, 0.58), Color("#63ccd0"), 0.35)
	# Keep locals referenced while documenting that these structures are collidable.
	if not is_instance_valid(mount) or not is_instance_valid(pedestal):
		push_warning("Communications antenna structure was not created.")


func _make_parabolic_dish_mesh(radius: float, depth: float, rings: int, segments: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var focus := radius * radius / (4.0 * depth)
	for ring_index in range(rings):
		var inner_radius := radius * float(ring_index) / float(rings)
		var outer_radius := radius * float(ring_index + 1) / float(rings)
		for segment_index in range(segments):
			var angle_a := TAU * float(segment_index) / float(segments)
			var angle_b := TAU * float(segment_index + 1) / float(segments)
			var a0 := Vector3(inner_radius * cos(angle_a), inner_radius * sin(angle_a), -inner_radius * inner_radius / (4.0 * focus))
			var a1 := Vector3(outer_radius * cos(angle_a), outer_radius * sin(angle_a), -outer_radius * outer_radius / (4.0 * focus))
			var b0 := Vector3(inner_radius * cos(angle_b), inner_radius * sin(angle_b), -inner_radius * inner_radius / (4.0 * focus))
			var b1 := Vector3(outer_radius * cos(angle_b), outer_radius * sin(angle_b), -outer_radius * outer_radius / (4.0 * focus))
			for point: Vector3 in [a0, b0, a1, b0, b1, a1]:
				surface.set_uv(Vector2(point.x / (radius * 2.0) + 0.5, point.y / (radius * 2.0) + 0.5))
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


func _add_room_props() -> void:
	_add_med_bay_props()
	_add_dining_props()
	_add_restroom_props()
	_add_lab_props()
	_add_main_room_props()
	_add_sleeping_room_props()
	_add_airlock_props()
	_add_plant_growth_room_props()
	_add_room_photo_panels()


func _build_habitat_foundation() -> void:
	# A continuous structural deck under modules and connectors prevents falls through seams.
	_make_box(world_root, "Continuous habitat under-deck", Vector3(0.0, -0.20, -6.0), Vector3(55.0, 0.36, 58.0), Color("#596462"))


func _add_room_photo_panels() -> void:
	# Real NASA photographs add mission context to these rooms.
	var lab_mural := _make_textured_screen("Apollo 17 lunar field photo mural in lab", Vector3(-23.78, 2.1, 0.0), Vector2(9.2, 2.0), "res://assets/nasa/moon_surface/apollo17_station6_panorama.jpg", false)
	lab_mural.rotation.y = PI * 0.5
	# A close-up lunar sample photo gives the lab a real surface-science reference beside the NASA habitat model.
	_make_visual_box("Lunar sample photo panel surround", Vector3(-18.0, 2.05, 5.82), Vector3(3.35, 2.36, 0.08), Color("#394d55"))
	_make_textured_screen("Apollo 11 regolith sample reference", Vector3(-18.0, 2.05, 5.75), Vector2(3.05, 2.06), "res://assets/nasa/moon_surface/apollo11_regolith_closeup.jpg", false)
	_make_visual_box("Medical photo panel surround", Vector3(-18.0, 2.05, -21.82), Vector3(4.1, 2.96, 0.08), Color("#394d55"))
	var med_mural := _make_textured_screen("NASA ISS medical training photo mural", Vector3(-18.0, 2.05, -21.76), Vector2(3.8, 2.66), "res://assets/nasa/iss065e074846.jpg", false)
	med_mural.rotation.y = 0.0


func _add_plant_growth_room_props() -> void:
	# Veggie-inspired controlled environment racks with plant pillows and overhead LEDs.
	for rack_x: float in [-3.25, 3.25]:
		# Open rack frame leaves the trays and plants visible from the aisle.
		for frame_x: float in [-1.48, 1.48]:
			_make_visual_strut("Hydroponic rack upright", Vector3(rack_x + frame_x, 0.2, -28.0), Vector3(rack_x + frame_x, 2.92, -28.0), 0.065, Color("#9aa9a2"))
		for frame_z: float in [-0.4, 0.4]:
			_make_visual_strut("Hydroponic rack cross brace", Vector3(rack_x - 1.48, 0.35, -28.0 + frame_z), Vector3(rack_x + 1.48, 2.8, -28.0 + frame_z), 0.035, Color("#65797a"))
		for shelf: int in range(3):
			var shelf_y := 0.72 + float(shelf) * 0.78
			_make_solid_box("Hydroponic grow tray", Vector3(rack_x, shelf_y, -27.65), Vector3(2.55, 0.18, 0.56), Color("#384b43"))
			_make_visual_box("Tray stainless rim", Vector3(rack_x, shelf_y + 0.11, -27.65), Vector3(2.58, 0.035, 0.59), Color("#aab9ad"))
			_make_visual_strut("Nutrient feed tube", Vector3(rack_x - 1.25, shelf_y + 0.18, -27.25), Vector3(rack_x + 1.25, shelf_y + 0.18, -27.25), 0.035, Color("#53bcae"))
			_make_emissive_box("Plant growth LED bank", Vector3(rack_x, shelf_y + 0.52, -27.65), Vector3(2.3, 0.055, 0.24), Color("#e7a2d9"), 0.24)
			for plant: int in range(4):
				var plant_x := rack_x - 0.9 + float(plant) * 0.6
				_make_visual_cylinder("Sealed root pillow", Vector3(plant_x, shelf_y + 0.21, -27.65), 0.16, 0.19, Color("#746b57"))
				_make_visual_strut("Lettuce stem", Vector3(plant_x, shelf_y + 0.28, -27.65), Vector3(plant_x, shelf_y + 0.58, -27.65), 0.045, Color("#72a878"))
				for leaf_side: float in [-1.0, 1.0]:
					var leaf := _make_visual_sphere("Lettuce leaf", Vector3(plant_x + leaf_side * 0.13, shelf_y + 0.47, -27.65), 0.15, Color("#81bd7c"))
					leaf.scale = Vector3(1.0, 0.55, 0.72)
	var garden_unit := _make_solid_box("Garden nutrient and water service unit", Vector3(0.0, 1.15, -31.45), Vector3(3.2, 2.2, 0.8), Color("#7b8b84"))
	garden_unit.set_meta("station_id", "garden")
	_make_text_panel("CROP SERVICE\nNutrients / flow", Vector3(0.0, 2.5, -31.0), Vector2(2.5, 0.56), 0.0)
	_add_status_panel_face(Vector3(0.0, 1.48, -31.0), 1.05, 0.56)
	for gauge_x: float in [-1.15, 1.15]:
		_add_gauge(Vector3(gauge_x, 1.48, -31.0), 0.16, Color("#74d6bf"))
	for hose_x: float in [-0.85, 0.85]:
		_make_visual_strut("Garden nutrient service hose", Vector3(hose_x, 0.36, -31.38), Vector3(hose_x, 0.36, -30.72), 0.055, Color("#48aa91"))
	_make_textured_screen("Plant growth monitoring display", Vector3(0.0, 1.52, -31.02), Vector2(1.24, 0.72), "res://assets/nasa/moon_surface/lro_lunar_color_mosaic.jpg", true)


func _add_med_bay_props() -> void:
	# NASA's reference layout calls for one stowable medical stretcher with a private exam area.
	_make_solid_box("Medical stretcher frame", Vector3(-21.3, 0.4, -17.0), Vector3(2.15, 0.24, 3.1), Color("#52676e"))
	var stretcher_pad := _make_capsule_visual("Medical pressure mattress", Vector3(-21.3, 0.69, -17.0), Vector3(1.0, 0.13, 1.55), Color("#d2dcda"))
	stretcher_pad.rotation.x = PI * 0.5
	var stretcher_pillow := _make_capsule_visual("Medical head cushion", Vector3(-21.3, 0.84, -18.18), Vector3(0.66, 0.11, 0.3), Color("#71b8c0"))
	stretcher_pillow.rotation.x = PI * 0.5
	for leg_x: float in [-0.88, 0.88]:
		for leg_z: float in [-1.22, 1.22]:
			_make_visual_strut("Stretcher telescoping leg", Vector3(-21.3 + leg_x, 0.32, -17.0 + leg_z), Vector3(-21.3 + leg_x, 0.08, -17.0 + leg_z), 0.06, Color("#9aa9a7"))
			_make_visual_cylinder("Stretcher caster", Vector3(-21.3 + leg_x, 0.1, -17.0 + leg_z), 0.11, 0.08, Color("#263b43"))
	for restraint_z: float in [-18.0, -16.0]:
		_make_visual_box("Medical restraint webbing", Vector3(-21.3, 0.84, restraint_z), Vector3(1.95, 0.045, 0.1), Color("#c7a45e"))
	_make_visual_box("Medical privacy screen rail", Vector3(-21.3, 2.65, -17.0), Vector3(3.5, 0.08, 4.6), Color("#8c9b99"))
	for side: float in [-1.0, 1.0]:
		_make_visual_box("Medical privacy curtain", Vector3(-21.3 + side * 1.68, 1.78, -17.0), Vector3(0.055, 1.75, 4.35), Color("#9ab6b4"))
	var medical_analyzer := _make_solid_box("Specimen diagnostic analyzer", Vector3(-14.2, 0.82, -18.7), Vector3(2.1, 1.64, 1.35), Color("#87999a"))
	medical_analyzer.set_meta("station_id", "medical")
	_make_text_panel("MEDICAL BAY\nCrew diagnostics", Vector3(-14.2, 2.05, -18.0), Vector2(2.5, 0.58), 0.0)
	_add_status_panel_face(Vector3(-14.2, 1.28, -17.98), 1.52, 0.72)
	for button_x: float in [-0.54, -0.18, 0.18, 0.54]:
		_make_visual_cylinder("Analyzer tactile control", Vector3(-14.2 + button_x, 0.92, -17.99), 0.075, 0.05, Color("#d5b86e"))
	_make_visual_box("Diagnostic screen bezel", Vector3(-14.2, 1.67, -18.0), Vector3(1.12, 0.84, 0.16), Color("#354850"))
	_make_textured_screen("Diagnostic lunar specimen scan", Vector3(-14.2, 1.67, -18.085), Vector2(0.94, 0.62), "res://assets/nasa/moon_surface/lro_lunar_color_mosaic.jpg", true)
	for shelf_level in range(3):
		_make_solid_box("Surgical supply shelf", Vector3(-22.4, 0.55 + float(shelf_level) * 0.72, -11.2), Vector3(3.7, 0.14, 0.72), Color("#71858a"))
		_make_visual_box("Surgical shelf front rail", Vector3(-22.4, 0.68 + float(shelf_level) * 0.72, -10.82), Vector3(3.7, 0.07, 0.08), Color("#b1c0bb"))
	for kit_index in range(3):
		var kit_x := -23.3 + float(kit_index) * 0.92
		_make_solid_box("First aid kit", Vector3(kit_x, 1.03, -11.2), Vector3(0.66, 0.44, 0.5), Color("#d3e0dc"))
		_make_visual_box("First aid kit lid", Vector3(kit_x, 1.27, -11.2), Vector3(0.68, 0.06, 0.52), Color("#e7ece4"))
		_make_visual_box("First aid marking", Vector3(kit_x, 1.31, -11.2), Vector3(0.28, 0.045, 0.08), Color("#d45e58"))
		_make_visual_box("First aid latch", Vector3(kit_x, 1.04, -10.93), Vector3(0.14, 0.13, 0.05), Color("#536a6c"))
	var med_life_support := _make_solid_box("Medical oxygen and monitoring cabinet", Vector3(-13.5, 1.15, -12.0), Vector3(2.0, 2.25, 1.4), Color("#687e82"))
	med_life_support.set_meta("equipment_type", "medical_life_support")
	_make_visual_box("Medical cabinet service door", Vector3(-13.5, 1.12, -11.26), Vector3(1.65, 1.65, 0.06), Color("#91a19c"))
	_add_status_panel_face(Vector3(-13.5, 1.85, -11.2), 0.86, 0.38)
	_add_gauge(Vector3(-14.05, 0.88, -11.19), 0.18, Color("#76d3b3"))
	_add_gauge(Vector3(-12.95, 0.88, -11.19), 0.18, Color("#d7b667"))
	_make_visual_box("Life support status panel", Vector3(-13.5, 1.35, -11.27), Vector3(1.15, 0.58, 0.06), Color("#66d1c7"))
	for vent_y in range(4):
		_make_visual_box("Medical cabinet cooling louver", Vector3(-13.5, 0.48 + float(vent_y) * 0.12, -11.27), Vector3(1.1, 0.035, 0.035), Color("#354d53"))


func _add_dining_props() -> void:
	# One shared ward table plus a wall galley, keeping a straight route to the garden and adjacent rooms.
	_make_solid_box("Wardroom table pedestal", Vector3(0.0, 0.48, -15.8), Vector3(0.52, 0.92, 0.52), Color("#52666c"))
	_make_solid_box("Wardroom table", Vector3(0.0, 0.98, -15.8), Vector3(3.3, 0.16, 1.55), Color("#c3cbc5"))
	_make_visual_box("Wardroom table edge bumper", Vector3(0.0, 1.08, -15.8), Vector3(3.34, 0.05, 1.59), Color("#536a70"))
	for seat_anchor: Vector2 in [Vector2(-1.25, -17.15), Vector2(1.25, -17.15), Vector2(-1.25, -14.45), Vector2(1.25, -14.45)]:
		var seat_pad := _make_capsule_visual("Wardroom molded seat cushion", Vector3(seat_anchor.x, 0.93, seat_anchor.y), Vector3(0.43, 0.16, 0.36), Color("#738a8d"))
		seat_pad.rotation.x = PI * 0.5
	for seat_x: float in [-1.25, 1.25]:
		_make_solid_box("Wardroom seat pedestal", Vector3(seat_x, 0.48, -17.15), Vector3(0.2, 0.9, 0.2), Color("#657b7e"))
		_make_solid_box("Wardroom seat pedestal", Vector3(seat_x, 0.48, -14.45), Vector3(0.2, 0.9, 0.2), Color("#657b7e"))
		_make_visual_strut("Wardroom seat back", Vector3(seat_x, 0.65, -17.15), Vector3(seat_x, 1.32, -17.48), 0.11, Color("#546a70"))
		_make_visual_strut("Wardroom seat back", Vector3(seat_x, 0.65, -14.45), Vector3(seat_x, 1.32, -14.12), 0.11, Color("#546a70"))
	for place_x: float in [-1.05, 1.05]:
		_make_visual_box("Meal pouch", Vector3(place_x, 1.12, -15.8), Vector3(0.42, 0.16, 0.36), Color("#c99b64"))
	# Two side galley runs preserve the wide central exit to the garden.
	for counter_x: float in [-4.8, 4.8]:
		_make_solid_box("Galley lower cabinet", Vector3(counter_x, 0.58, -20.55), Vector3(2.75, 1.1, 1.05), Color("#718084"))
		_make_visual_box("Galley cabinet door", Vector3(counter_x, 0.58, -19.99), Vector3(2.48, 0.78, 0.05), Color("#8f9d9a"))
		_make_visual_box("Galley cabinet kick plate", Vector3(counter_x, 0.12, -19.98), Vector3(2.52, 0.12, 0.07), Color("#42575d"))
		for drawer_y: float in [0.38, 0.7]:
			_make_visual_box("Galley drawer seam", Vector3(counter_x, drawer_y, -19.96), Vector3(2.3, 0.025, 0.025), Color("#50666b"))
			_make_visual_cylinder("Galley drawer latch", Vector3(counter_x, drawer_y + 0.1, -19.91), 0.045, 0.08, Color("#d2bb77"))
		_make_solid_box("Galley food preparation surface", Vector3(counter_x, 1.18, -20.55), Vector3(2.9, 0.16, 1.18), Color("#c4cbc4"))
	for shelf_level in range(2):
		for locker_x: float in [-4.8, 4.8]:
			_make_solid_box("Galley overhead locker", Vector3(locker_x, 2.15 + float(shelf_level) * 0.72, -21.45), Vector3(2.7, 0.58, 0.58), Color("#75888a"))
	for food_x: float in [-5.3, -4.3, 4.3, 5.3]:
		_make_solid_box("Secured packaged food bin", Vector3(food_x, 1.52, -20.45), Vector3(0.68, 0.45, 0.55), Color("#c9a270"))
		_make_visual_box("Food bin latch", Vector3(food_x, 1.52, -20.14), Vector3(0.18, 0.16, 0.035), Color("#506a70"))


func _add_restroom_props() -> void:
	# Separate toilet and wash stations with a privacy divider and recognizable fixtures.
	_make_solid_box("Vacuum toilet housing", Vector3(21.5, 0.5, -19.2), Vector3(1.45, 0.72, 1.65), Color("#d7dedb"))
	_make_visual_torus("Vacuum toilet seat ring", Vector3(21.5, 0.9, -19.2), 0.51, 0.09, Color("#edf0e8"))
	_make_visual_box("Toilet foot restraints", Vector3(21.5, 1.03, -19.82), Vector3(1.22, 0.12, 0.18), Color("#778b8e"))
	_make_solid_box("Vacuum and waste service panel", Vector3(23.3, 1.35, -19.2), Vector3(1.3, 2.55, 1.0), Color("#71848a"))
	_make_visual_box("Waste service access hatch", Vector3(22.62, 1.3, -19.2), Vector3(0.055, 1.1, 0.75), Color("#50666d"))
	_add_status_panel_face(Vector3(22.58, 2.15, -19.2), 0.45, 0.3)
	_make_visual_strut("Vacuum waste hose", Vector3(22.3, 0.58, -19.6), Vector3(22.05, 0.32, -18.95), 0.07, Color("#334e56"))
	_make_visual_box("Toilet airflow grille", Vector3(22.62, 1.58, -19.2), Vector3(0.05, 0.8, 0.64), Color("#a9c6c2"))
	_make_visual_box("Toilet flush control", Vector3(22.61, 2.32, -19.2), Vector3(0.06, 0.3, 0.42), Color("#6acbc4"))
	_make_visual_box("Privacy partition", Vector3(18.0, 1.55, -16.2), Vector3(0.12, 3.0, 3.0), Color("#879997"))
	_make_solid_box("Sponge bath wash bench", Vector3(21.5, 0.55, -12.6), Vector3(3.4, 0.42, 1.25), Color("#bbc7c2"))
	_make_solid_box("Wash station cabinet", Vector3(21.5, 1.25, -11.2), Vector3(3.3, 2.3, 0.72), Color("#829494"))
	_make_visual_box("Wash station mirror", Vector3(21.5, 2.25, -11.57), Vector3(2.1, 0.92, 0.04), Color("#8faeaf"))
	_make_visual_box("Wash station mirror frame", Vector3(21.5, 2.25, -11.6), Vector3(2.22, 1.04, 0.055), Color("#536b70"))
	_make_visual_cylinder("Wash station faucet", Vector3(21.5, 1.65, -12.0), 0.075, 0.34, Color("#b8c4bd"))
	_make_visual_box("Wash station sink basin", Vector3(21.5, 1.48, -12.25), Vector3(1.65, 0.13, 0.66), Color("#bdc9c4"))
	_make_visual_torus("Wash station drain ring", Vector3(21.5, 1.56, -12.25), 0.11, 0.025, Color("#53686d"))
	_make_solid_box("Hygiene supplies locker", Vector3(14.5, 1.1, -12.0), Vector3(1.25, 2.1, 1.0), Color("#75898b"))
	for pack in range(3):
		var pack_y := 0.65 + float(pack) * 0.52
		_make_solid_box("Secured hygiene wipe pack", Vector3(14.5, pack_y, -11.32), Vector3(0.74, 0.34, 0.24), Color("#9dc8c2"))
		_make_visual_box("Hygiene pack tamper seal", Vector3(14.5, pack_y, -11.18), Vector3(0.56, 0.08, 0.025), Color("#e2d6a7"))
		_make_visual_box("Hygiene locker retainer", Vector3(14.5, pack_y, -11.12), Vector3(0.08, 0.3, 0.04), Color("#52686d"))


func _add_lab_props() -> void:
	# A central aisle connects both bulkhead doors; bench equipment is visibly lab-specific.
	_add_seismometer_station()
	for bench_z: float in [-4.0, 4.0]:
		var lab_bench := _make_solid_box("Laboratory instrument bench", Vector3(-18.0, 0.86, bench_z), Vector3(7.0, 0.22, 1.5), Color("#52666c"))
		lab_bench.set_meta("station_id", "lab_console")
		for leg_x: float in [-3.0, 3.0]:
			_make_solid_box("Bench pedestal", Vector3(-18.0 + leg_x, 0.43, bench_z), Vector3(0.42, 0.72, 1.22), Color("#354a51"))
		_make_visual_box("Bench edge safety rail", Vector3(-18.0, 0.99, bench_z + 0.68), Vector3(6.7, 0.055, 0.07), Color("#b0c0bc"))
		for instrument_x: float in [-20.35, -17.65, -15.0]:
			_add_lab_instrument(instrument_x, bench_z)
	for sample_x: float in [-20.8, -19.5, -16.5, -15.2]:
		_make_visual_cylinder("Sealed lunar dust sample canister", Vector3(sample_x, 1.27, 4.0), 0.27, 0.58, Color("#b7b99b"))
		_make_visual_cylinder("Sample canister locking cap", Vector3(sample_x, 1.59, 4.0), 0.3, 0.1, Color("#667982"))
	_make_solid_box("NASA habitat model exhibit plinth", Vector3(-18.0, 0.18, 0.0), Vector3(2.7, 0.32, 2.7), Color("#626e71"))
	_make_visual_box("Habitat model display label", Vector3(-18.0, 0.48, -0.86), Vector3(1.65, 0.18, 0.045), Color("#17343c"))
	_make_textured_screen("Moonquake waveform display", Vector3(-18.0, 1.12, -0.888), Vector2(0.82, 0.32), "res://assets/nasa/moon_surface/lro_lunar_color_mosaic.jpg", true)
	var lab_interaction := _make_solid_box("Laboratory task terminal", Vector3(-18.0, 1.7, -5.78), Vector3(2.5, 1.4, 0.16), Color("#243b42"))
	lab_interaction.set_meta("station_id", "lab_console")
	_make_text_panel("LAB WORKSTATION\nSamples / instruments", Vector3(-18.0, 2.65, -5.55), Vector2(3.2, 0.62), 0.0)
	for model_path: String in ["res://assets/nasa/habitat-demonstration-unit-part-1.glb", "res://assets/nasa/habitat-demonstration-unit-part-2.glb"]:
		var habitat_scene := load(model_path) as PackedScene
		if habitat_scene != null:
			var exhibit := habitat_scene.instantiate()
			exhibit.name = model_path.get_file().get_basename().replace("-", " ") + " scale model"
			exhibit.scale = Vector3.ONE * 0.001
			exhibit.position = Vector3(-18.0, 0.72, 0.37)
			world_root.add_child(exhibit)
		else:
			push_warning("NASA habitat model for the lab display could not be loaded: " + model_path)
	for case_index in range(4):
		var case_x := -20.5 + float(case_index % 2) * 4.8
		var case_z := 2.9 + float(case_index) / 2.0 * 2.0
		var case_body := _make_solid_box("Instrument storage case", Vector3(case_x, 1.18, case_z), Vector3(1.1, 0.38, 0.75), Color("#536d73"))
		case_body.rotation_degrees.z = 0.0
		_make_visual_box("Instrument case lid", Vector3(case_x, 1.4, case_z), Vector3(1.12, 0.08, 0.77), Color("#819692"))
		_make_visual_box("Instrument case ID plate", Vector3(case_x, 1.2, case_z - 0.39), Vector3(0.52, 0.16, 0.025), Color("#d3c27d"))


func _add_lab_instrument(x: float, z: float) -> void:
	# Repeated machined instrument modules give the lab a consistent hardware language.
	var base := Vector3(x, 1.13, z)
	_make_visual_box("Optical instrument foot", base, Vector3(0.92, 0.22, 0.72), Color("#92a29e"))
	_make_visual_box("Instrument dark isolation pad", base + Vector3(0.0, 0.13, 0.0), Vector3(0.74, 0.035, 0.56), Color("#263c43"))
	_make_visual_box("Lunar sample stage", base + Vector3(0.0, 0.25, 0.02), Vector3(0.46, 0.08, 0.42), Color("#b0b9b1"))
	_make_visual_cylinder("Optical objective barrel", base + Vector3(0.0, 0.55, -0.12), 0.13, 0.48, Color("#536b73"))
	_make_visual_cylinder("Objective locking ring", base + Vector3(0.0, 0.72, -0.12), 0.17, 0.075, Color("#c3a95e"))
	_make_visual_strut("Microscope support arm", base + Vector3(0.0, 0.24, 0.25), base + Vector3(0.0, 0.84, 0.25), 0.065, Color("#aebbb5"))
	_make_visual_box("Instrument control fascia", base + Vector3(0.34, 0.47, 0.22), Vector3(0.24, 0.34, 0.12), Color("#354c54"))
	_make_emissive_box("Instrument status display", base + Vector3(0.34, 0.52, 0.15), Vector3(0.16, 0.11, 0.025), Color("#60d4cf"), 0.38)
	for button_x: float in [-0.12, 0.0, 0.12]:
		_make_visual_cylinder("Instrument tactile key", base + Vector3(0.34 + button_x, 0.34, 0.14), 0.035, 0.035, Color("#d9bd70"))


func _add_seismometer_station() -> void:
	# A visible lunar seismometer makes seismic tasks discoverable in the Lab.
	_make_solid_box("Lunar seismometer isolation plinth", Vector3(-22.0, 0.22, -1.15), Vector3(1.65, 0.38, 1.4), Color("#46585b"))
	var sensor := _make_solid_box("Lunar seismometer sensor housing", Vector3(-22.0, 0.9, -1.15), Vector3(1.08, 1.4, 0.92), Color("#c0c9c2"))
	sensor.set_meta("station_id", "seismometer")
	_make_visual_cylinder("Seismometer leveling collar", Vector3(-22.0, 1.02, -1.15), 0.36, 0.12, Color("#697c7d"))
	_make_visual_cylinder("Seismometer sensor cap", Vector3(-22.0, 1.14, -1.15), 0.23, 0.18, Color("#9ab2ad"))
	_make_text_panel("LUNAR SEISMOMETER\nWaveform / calibration", Vector3(-22.0, 1.65, -1.15), Vector2(1.8, 0.48), 0.0)
	_make_text_panel("SEISMOMETER\nDay 1 calibration / Day 3 impact / Day 5 quake", Vector3(-22.0, 2.25, -5.72), Vector2(4.2, 0.72), 0.0)
	_make_textured_screen("Seismometer waveform instrument display", Vector3(-22.0, 1.72, -5.83), Vector2(2.0, 1.0), "res://assets/nasa/moon_surface/lro_lunar_color_mosaic.jpg", true)


func _make_text_panel(panel_text: String, panel_position: Vector3, panel_size: Vector2, rotation_y: float) -> void:
	var backing := _make_visual_box("Equipment information panel", panel_position, Vector3(panel_size.x, panel_size.y, 0.08), Color("#17343c"))
	backing.rotation.y = rotation_y
	var label := Label3D.new()
	label.name = "Equipment label"
	label.text = panel_text
	label.position = panel_position + Vector3(0.0, 0.0, 0.055)
	label.rotation.y = rotation_y
	label.pixel_size = 0.004
	label.font_size = 36
	label.modulate = Color("#baf9f3")
	label.outline_size = 4
	label.outline_modulate = Color("#071217")
	world_root.add_child(label)


func _add_main_room_props() -> void:
	# Three readable workstations sit to either side of the straight airlock route.
	var console_positions: Array[Vector2] = [Vector2(-4.8, 2.5), Vector2(4.8, 2.5), Vector2(-4.8, -2.5)]
	for console_position: Vector2 in console_positions:
		var console_x := console_position.x
		var console_z := console_position.y
		_make_solid_box("Command workstation desk", Vector3(console_x, 0.72, console_z), Vector3(3.25, 0.16, 1.15), Color("#8b9997"))
		for support_x: float in [-1.35, 1.35]:
			_make_visual_strut("Workstation metal leg", Vector3(console_x + support_x, 0.62, console_z), Vector3(console_x + support_x, 0.12, console_z), 0.055, Color("#a5b2ad"))
		_make_visual_box("Workstation cable tray", Vector3(console_x, 0.48, console_z), Vector3(1.6, 0.08, 0.65), Color("#43575d"))
		_make_solid_box("Workstation pedestal", Vector3(console_x, 0.34, console_z), Vector3(0.62, 0.72, 0.82), Color("#66777b"))
		_make_solid_box("Monitor stand", Vector3(console_x, 1.12, console_z - 0.32), Vector3(0.16, 0.72, 0.16), Color("#596d73"))
		_make_solid_box("Monitor housing", Vector3(console_x, 1.76, console_z - 0.31), Vector3(1.72, 1.18, 0.2), Color("#3c4e54"))
		_make_visual_box("Monitor bezel", Vector3(console_x, 1.76, console_z - 0.43), Vector3(1.56, 0.96, 0.06), Color("#778a89"))
		_make_textured_screen("NASA reference data on workstation", Vector3(console_x, 1.76, console_z - 0.425), Vector2(1.48, 0.88), "res://assets/nasa/moon_surface/lro_lunar_color_mosaic.jpg", true)
		_make_visual_box("Workstation keyboard", Vector3(console_x, 0.84, console_z + 0.4), Vector3(0.92, 0.055, 0.3), Color("#394a50"))
		for key_x in range(8):
			for key_z in range(3):
				_make_visual_box("Workstation keycap", Vector3(console_x - 0.38 + float(key_x) * 0.11, 0.88, console_z + 0.4 + float(key_z) * 0.075), Vector3(0.075, 0.025, 0.045), Color("#9aa7a1"))
		_make_solid_box("Workstation compute unit", Vector3(console_x + 1.22, 1.18, console_z - 0.25), Vector3(0.42, 0.75, 0.58), Color("#596a6e"))
		_make_visual_box("Compute unit status lights", Vector3(console_x + 1.22, 1.43, console_z - 0.554), Vector3(0.22, 0.07, 0.025), Color("#6acbc4"))
	var life_support := _make_solid_box("Main room life support cabinet", Vector3(6.55, 1.15, 2.8), Vector3(1.65, 2.3, 1.4), Color("#6e8386"))
	life_support.set_meta("station_id", "life_support")
	_make_text_panel("LIFE SUPPORT\nWater / O₂ / CO₂", Vector3(6.55, 2.65, 2.0), Vector2(2.7, 0.6), 0.0)
	_make_visual_box("Main life-support service door", Vector3(5.69, 1.24, 2.8), Vector3(0.055, 1.45, 1.08), Color("#8f9f99"))
	_add_status_panel_face(Vector3(5.64, 1.76, 2.8), 0.72, 0.4)
	_add_gauge(Vector3(5.62, 1.05, 2.52), 0.13, Color("#73d7bb"))
	_add_gauge(Vector3(5.62, 1.05, 3.08), 0.13, Color("#d8bb6b"))
	_make_emissive_box("Air filter status screen", Vector3(5.7, 1.55, 2.8), Vector3(0.04, 0.58, 0.76), Color("#63d5dc"), 0.4)
	for vent_row in range(4):
		_make_visual_box("Air filter vent", Vector3(5.68, 0.72 + float(vent_row) * 0.19, 2.8), Vector3(0.045, 0.045, 0.82), Color("#263b43"))


func _add_sleeping_room_props() -> void:
	# Keep a clear west-side lane from the crew-quarters hatch to the main hall.
	for bunk_x: float in [17.5, 22.0]:
		for level in range(2):
			var mattress_y := 0.44 + float(level) * 1.35
			# Layered padded bunk: broad cushion, soft cover, and a distinct raised pillow.
			_make_solid_box("Crew bunk bed frame", Vector3(bunk_x, mattress_y, -1.1), Vector3(2.85, 0.22, 3.45), Color("#40545d"))
			_make_visual_box("Bunk frame trim", Vector3(bunk_x, mattress_y + 0.13, -1.1), Vector3(2.72, 0.08, 3.3), Color("#90a5a2"))
			_make_visual_box("Crew bunk mattress", Vector3(bunk_x, mattress_y + 0.31, -1.1), Vector3(2.52, 0.28, 3.05), Color("#d7ded5"))
			_make_visual_box("Crew bunk quilt", Vector3(bunk_x, mattress_y + 0.465, -0.55), Vector3(2.36, 0.045, 1.82), Color("#8db9b4"))
			_make_visual_box("Crew bunk pillow", Vector3(bunk_x, mattress_y + 0.49, -2.22), Vector3(1.18, 0.18, 0.62), Color("#edf0e8"))
			for rail_x: float in [-1.38, 1.38]:
				_make_visual_strut("Bunk safety rail", Vector3(bunk_x + rail_x, mattress_y + 0.31, -2.55), Vector3(bunk_x + rail_x, mattress_y + 0.68, 0.42), 0.045, Color("#a8b6b0"))
			for strap_z: float in [-1.05, 0.15]:
				_make_visual_box("Bunk restraint strap", Vector3(bunk_x, mattress_y + 0.51, strap_z), Vector3(2.42, 0.045, 0.10), Color("#d0a75d"))
			if level == 0:
				var sleep_panel := _make_solid_box("Crew bunk sleep control", Vector3(bunk_x, 1.35, -3.02), Vector3(1.25, 0.8, 0.16), Color("#27444a"))
				sleep_panel.set_meta("station_id", "bed")
				_make_text_panel("SLEEP\nPress E to end shift", Vector3(bunk_x, 1.35, -2.92), Vector2(1.12, 0.62), 0.0)
			_make_emissive_box("Bunk reading light", Vector3(bunk_x, mattress_y + 0.92, -2.92), Vector3(0.62, 0.055, 0.12), Color("#d8f7dd"), 0.28)
		for post_x: float in [-1.3, 1.3]:
			_make_visual_strut("Bunk bed support", Vector3(bunk_x + post_x, 0.12, -2.7), Vector3(bunk_x + post_x, 2.84, -2.7), 0.075, Color("#91a09e"))
			_make_visual_strut("Bunk bed support", Vector3(bunk_x + post_x, 0.12, 0.5), Vector3(bunk_x + post_x, 2.84, 0.5), 0.075, Color("#91a09e"))
	for shelf_level in range(3):
		_make_solid_box("Crew quarters stowage shelf", Vector3(22.0, 0.55 + float(shelf_level) * 0.68, 4.0), Vector3(3.6, 0.14, 0.72), Color("#758589"))
		_make_visual_box("Crew shelf guard rail", Vector3(22.0, 0.74 + float(shelf_level) * 0.68, 4.34), Vector3(3.5, 0.12, 0.08), Color("#aebbb4"))
	for storage in range(4):
		var storage_x := 20.7 + float(storage % 2) * 1.0
		var storage_y := 0.9 + float(storage) / 2.0 * 0.68
		_make_visual_box("Personal stowage container", Vector3(storage_x, storage_y, 4.0), Vector3(0.72, 0.46, 0.52), Color("#9aa8a3"))
		_make_visual_box("Personal stowage lid", Vector3(storage_x, storage_y + 0.24, 4.0), Vector3(0.74, 0.055, 0.54), Color("#c0c9c1"))
		_make_visual_box("Stowage label plate", Vector3(storage_x, storage_y, 3.72), Vector3(0.36, 0.16, 0.025), Color("#334b52"))


func _add_airlock_props() -> void:
	_make_visual_box("Airlock inner door frame", Vector3(0, 1.45, 9.1), Vector3(5.2, 2.9, 0.24), Color("#879497"))
	for side: float in [-1.0, 1.0]:
		_make_visual_box("Airlock inner parked door leaf", Vector3(side * 2.35, 1.35, 9.28), Vector3(0.48, 2.45, 0.18), Color("#566d75"))
	_make_visual_box("Airlock outer door frame", Vector3(0, 1.45, 16.9), Vector3(5.2, 2.9, 0.24), Color("#879497"))
	for side: float in [-1.0, 1.0]:
		_make_visual_box("Airlock outer parked door leaf", Vector3(side * 2.35, 1.35, 16.72), Vector3(0.48, 2.45, 0.18), Color("#566d75"))
	var filter_station := _make_solid_box("Airlock filter service panel", Vector3(3.0, 1.5, 13.0), Vector3(0.28, 2.3, 0.9), Color("#657e84"))
	filter_station.set_meta("station_id", "airlock_filter")
	_make_text_panel("AIRLOCK FILTERS\nInspect / clean", Vector3(3.0, 2.75, 12.45), Vector2(2.6, 0.58), 0.0)
	_make_visual_box("Airlock control lights", Vector3(2.83, 1.85, 13.0), Vector3(0.06, 0.62, 0.48), Color("#72d7bf"))
	_add_status_panel_face(Vector3(2.8, 1.82, 13.0), 0.55, 0.52)
	for filter_z: float in [12.55, 13.0, 13.45]:
		var filter := _make_visual_cylinder("Replaceable airlock filter cartridge", Vector3(2.64, 1.1, filter_z), 0.16, 0.52, Color("#b5c0b6"))
		filter.rotation.z = PI * 0.5
		_make_visual_cylinder("Filter cartridge locking ring", Vector3(2.64, 1.1, filter_z), 0.19, 0.08, Color("#586c71"))
		_make_visual_box("Filter differential pressure indicator", Vector3(2.62, 1.56, filter_z), Vector3(0.05, 0.08, 0.2), Color("#d2b96f"))


func _make_visual_cylinder(cylinder_name: String, cylinder_position: Vector3, radius: float, height: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = cylinder_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	instance.mesh = mesh
	instance.position = cylinder_position
	instance.material_override = _material(color)
	(parent if parent != null else world_root).add_child(instance)
	return instance


func _make_visual_torus(torus_name: String, torus_position: Vector3, outer_radius: float, tube_radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = torus_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(outer_radius - tube_radius, 0.01)
	mesh.outer_radius = outer_radius
	mesh.rings = 32
	mesh.ring_segments = 12
	instance.mesh = mesh
	instance.position = torus_position
	instance.material_override = _material(color)
	world_root.add_child(instance)
	return instance


func _add_status_panel_face(center: Vector3, width: float, height: float) -> void:
	_make_visual_box("Instrument panel bezel", center, Vector3(width + 0.12, height + 0.12, 0.08), Color("#344c53"))
	_make_visual_box("Instrument panel glass", center + Vector3(0.0, 0.0, 0.05), Vector3(width, height, 0.025), Color("#14292f"))
	for indicator_x: float in [-width * 0.32, 0.0, width * 0.32]:
		_make_emissive_box("Instrument status indicator", center + Vector3(indicator_x, height * 0.24, 0.075), Vector3(width * 0.16, 0.055, 0.02), Color("#67d4b7"), 0.38)
	for row in range(2):
		_make_visual_box("Instrument display data line", center + Vector3(0.0, -height * 0.08 - float(row) * 0.14, 0.075), Vector3(width * 0.72, 0.025, 0.018), Color("#6d9998"))


func _add_gauge(center: Vector3, radius: float, needle_color: Color) -> void:
	var face := _make_visual_cylinder("Analog system gauge", center, radius, 0.055, Color("#d3d9cf"))
	face.rotation.x = PI * 0.5
	var bezel := _make_visual_torus("Gauge metal bezel", center + Vector3(0.0, 0.0, 0.04), radius, 0.035, Color("#687c7e"))
	bezel.rotation.x = PI * 0.5
	_make_visual_strut("Gauge indicator needle", center + Vector3(0.0, 0.0, 0.065), center + Vector3(radius * 0.45, radius * 0.55, 0.065), 0.018, needle_color)


func _make_textured_screen(screen_name: String, screen_position: Vector3, screen_size: Vector2, texture_path: String, emissive: bool) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = screen_name
	var screen_mesh := QuadMesh.new()
	screen_mesh.size = screen_size
	instance.mesh = screen_mesh
	instance.position = screen_position
	instance.rotation.y = PI
	var screen_material := StandardMaterial3D.new()
	screen_material.albedo_texture = load(texture_path) as Texture2D
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		screen_material.emission_enabled = true
		screen_material.emission_texture = screen_material.albedo_texture
		screen_material.emission_energy_multiplier = 0.32
	instance.material_override = screen_material
	world_root.add_child(instance)
	return instance


func _make_visual_strut(strut_name: String, start: Vector3, finish: Vector3, radius: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var direction := finish - start
	var instance := MeshInstance3D.new()
	instance.name = strut_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.82
	mesh.bottom_radius = radius
	mesh.height = direction.length()
	mesh.radial_segments = 10
	instance.mesh = mesh
	instance.position = (start + finish) * 0.5
	instance.quaternion = Quaternion(Vector3.UP, direction.normalized())
	instance.material_override = _material(color)
	(parent if parent != null else world_root).add_child(instance)
	return instance


func _make_solid_box(box_name: String, box_position: Vector3, box_size: Vector3, color: Color, rotation_y: float = 0.0) -> StaticBody3D:
	return _make_box(world_root, box_name, box_position, box_size, color, rotation_y)


func _make_capsule_visual(capsule_name: String, capsule_position: Vector3, capsule_scale: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = capsule_name
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.8
	instance.mesh = mesh
	instance.position = capsule_position
	instance.scale = capsule_scale
	instance.material_override = _material(color)
	world_root.add_child(instance)
	return instance


func _make_emissive_box(box_name: String, box_position: Vector3, box_size: Vector3, color: Color, strength: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = box_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = strength
	material.roughness = 0.35
	instance.material_override = material
	world_root.add_child(instance)
	return instance


func _build_camera() -> void:
	follow_camera = Camera3D.new()
	follow_camera.name = "First Person Camera"
	follow_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	follow_camera.fov = 78.0
	follow_camera.near = 0.1
	follow_camera.far = 800.0
	follow_camera.position = Vector3(0, 1.56, 0)
	player.add_child(follow_camera)
	player.get_node("Astronaut").visible = false
	follow_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var top_plate := Panel.new()
	top_plate.position = Vector2(12, 10)
	top_plate.size = Vector2(570, 112)
	top_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_plate.add_theme_stylebox_override("panel", _hud_style(Color(0.025, 0.065, 0.085, 0.82), Color("#56c6c2")))
	layer.add_child(top_plate)

	var title := _make_label("HABITAT ZERO", Vector2(22, 16), 19, Color("#baf9f3"))
	layer.add_child(title)
	room_label = _make_label("AREA  /  MAIN ROOM", Vector2(22, 43), 13, Color("#ffffff"))
	layer.add_child(room_label)
	var objective := _make_label("Explore the habitat  /  TAB: mission control  /  ESC: release cursor", Vector2(22, 65), 11, Color("#b4c7ca"))
	layer.add_child(objective)
	interaction_hint = _make_label("", Vector2.ZERO, 15, Color("#baf9f3"))
	interaction_hint.anchor_left = 0.5
	interaction_hint.anchor_right = 0.5
	interaction_hint.anchor_top = 0.72
	interaction_hint.anchor_bottom = 0.72
	interaction_hint.offset_left = -260
	interaction_hint.offset_right = 260
	interaction_hint.offset_bottom = 36
	interaction_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_hint.add_theme_font_size_override("font_size", 17)
	interaction_hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	layer.add_child(interaction_hint)
	var crosshair := Control.new()
	crosshair.name = "Aim reticle"
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -8
	crosshair.offset_right = 8
	crosshair.offset_top = -8
	crosshair.offset_bottom = 8
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for reticle_rect: Rect2 in [Rect2(Vector2(7, 0), Vector2(2, 5)), Rect2(Vector2(7, 11), Vector2(2, 5)), Rect2(Vector2(0, 7), Vector2(5, 2)), Rect2(Vector2(11, 7), Vector2(5, 2))]:
		var stroke := ColorRect.new()
		stroke.position = reticle_rect.position
		stroke.size = reticle_rect.size
		stroke.color = Color("#c5faf1")
		crosshair.add_child(stroke)
	layer.add_child(crosshair)
	var control_plate := Panel.new()
	control_plate.anchor_top = 1.0
	control_plate.anchor_bottom = 1.0
	control_plate.offset_left = 12
	control_plate.offset_top = -48
	control_plate.offset_right = 475
	control_plate.offset_bottom = -8
	control_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_plate.add_theme_stylebox_override("panel", _hud_style(Color(0.025, 0.065, 0.085, 0.82), Color("#385a61")))
	layer.add_child(control_plate)
	var controls := _make_label("MOVE  WASD / ARROWS      JUMP  SPACE      LOOK  MOUSE", Vector2.ZERO, 11, Color("#d3e3e4"))
	controls.anchor_top = 1.0
	controls.anchor_bottom = 1.0
	controls.offset_left = 22.0
	controls.offset_top = -36.0
	controls.offset_right = 420.0
	controls.offset_bottom = -12.0
	layer.add_child(controls)

	minimap = Control.new()
	minimap.name = "Station Map"
	minimap.set_script(MinimapScript)
	minimap.set("player", player)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 0.0
	minimap.anchor_bottom = 0.0
	minimap.offset_left = -262.0
	minimap.offset_right = -18.0
	minimap.offset_top = 18.0
	minimap.offset_bottom = 278.0
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(minimap)
	var map_label := _make_label("HABITAT MAP  /  TAB FOR TASKS", Vector2.ZERO, 10, Color("#baf9f3"))
	map_label.anchor_left = 1.0
	map_label.anchor_right = 1.0
	map_label.offset_left = -262
	map_label.offset_right = -18
	map_label.offset_top = 282
	map_label.offset_bottom = 300
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(map_label)


func _update_station_hover() -> void:
	hovered_station = ""
	interaction_hint.text = ""
	if campaign_ui.call("is_board_open") or follow_camera == null:
		return
	var origin := follow_camera.global_position
	var ray_direction := -follow_camera.global_transform.basis.z
	var exclude: Array[RID] = [player.get_rid()]
	for _attempt in range(10):
		var query := PhysicsRayQueryParameters3D.create(origin, origin + ray_direction * 4.5)
		query.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		if collider.has_meta("station_id"):
			hovered_station = str(collider.get_meta("station_id"))
			break
		# Only step through nearby trim or small control geometry. A wall or
		# large piece of equipment must still block interaction through it.
		if float(hit["position"].distance_to(origin)) > 0.85:
			break
		if collider is CollisionObject3D:
			exclude.append(collider.get_rid())
		else:
			break
	if hovered_station != "":
		if hovered_station == "bed":
			interaction_hint.text = "CREW BUNK  •  PRESS E TO SLEEP" if campaign_ui.get("awaiting_bed") else "CREW BUNK  •  FINISH TODAY'S TASKS BEFORE SLEEPING"
		else:
			interaction_hint.text = "%s  •  PRESS E TO START TASK" % hovered_station.replace("_", " ").to_upper()


func _make_label(text: String, label_position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = label_position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _hud_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _room_id_at_player() -> String:
	var player_position := Vector2(player.global_position.x, player.global_position.z)
	for room: Dictionary in ROOMS:
		var center: Vector2 = room["center"]
		var room_size: Vector2 = room["size"]
		if absf(player_position.x - center.x) <= room_size.x * 0.5 and absf(player_position.y - center.y) <= room_size.y * 0.5:
			return str(room["id"])
	if absf(player_position.x) > 27.5 or player_position.y > 23.0 or player_position.y < -35.0:
		return "outside"
	return "hallway"


func _room_title(room_id: String) -> String:
	if room_id == "outside":
		return "OUTSIDE"
	if room_id == "hallway":
		return "CONNECTING HALL"
	if rooms_by_id.has(room_id):
		return str(rooms_by_id[room_id]["title"])
	return "MAIN ROOM"


func _make_box(parent: Node3D, box_name: String, box_position: Vector3, box_size: Vector3, color: Color, rotation_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = box_position
	body.rotation.y = rotation_y
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _make_visual_box(box_name: String, box_position: Vector3, box_size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = box_position
	instance.material_override = _material(color)
	world_root.add_child(instance)
	return instance


func _make_visual_sphere(sphere_name: String, sphere_position: Vector3, radius: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = sphere_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.mesh = mesh
	instance.position = sphere_position
	instance.material_override = _material(color)
	(parent if parent != null else world_root).add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if materials.has(key):
		return materials[key]
	var new_material := StandardMaterial3D.new()
	new_material.albedo_color = color
	new_material.roughness = 0.82
	materials[key] = new_material
	return new_material
