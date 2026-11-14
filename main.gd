extends Node3D

const MinimapScript := preload("res://minimap.gd")

const FLOOR_THICKNESS := 0.3
const WALL_HEIGHT := 1.7
const WALL_THICKNESS := 0.32
const DOOR_WIDTH := 2.8

const ROOMS := [
	{"id": "main", "title": "MAIN ROOM", "center": Vector2(0, 0), "size": Vector2(10, 8), "doors": ["north", "east", "south", "west"], "floor": Color("#263943")},
	{"id": "dining", "title": "DINING ROOM", "center": Vector2(0, -10), "size": Vector2(10, 8), "doors": ["north", "east", "south", "west"], "floor": Color("#2a3c43")},
	{"id": "garden", "title": "GARDEN", "center": Vector2(0, -18.5), "size": Vector2(8, 7), "doors": ["south"], "floor": Color("#334739")},
	{"id": "med", "title": "MED BAY", "center": Vector2(-10, -10), "size": Vector2(8, 8), "doors": ["east", "south"], "floor": Color("#35434b")},
	{"id": "lab", "title": "LAB", "center": Vector2(-10, 0), "size": Vector2(8, 8), "doors": ["north", "east"], "floor": Color("#343746")},
	{"id": "rest", "title": "REST ROOM", "center": Vector2(10, -10), "size": Vector2(8, 8), "doors": ["west", "south"], "floor": Color("#403940")},
	{"id": "sleep", "title": "SLEEPING", "center": Vector2(10, 0), "size": Vector2(8, 8), "doors": ["north", "west"], "floor": Color("#3d414b")},
	{"id": "airlock", "title": "AIRLOCK", "center": Vector2(0, 8), "size": Vector2(4, 4), "doors": ["north", "south"], "floor": Color("#43464a")}
]

const LINKS := [
	["main", "dining"], ["dining", "garden"], ["dining", "med"],
	["med", "lab"], ["lab", "main"], ["dining", "rest"],
	["rest", "sleep"], ["main", "sleep"], ["main", "airlock"]
]

const ROOM_WALL_COLOR := Color("#506a72")
const CORRIDOR_COLOR := Color("#293c43")

@onready var player: CharacterBody3D = $Player

var world_root: Node3D
var follow_camera: Camera3D
var room_label: Label
var minimap: Control
var materials: Dictionary = {}
var rooms_by_id: Dictionary = {}


func _ready() -> void:
	for room: Dictionary in ROOMS:
		rooms_by_id[room["id"]] = room
	_build_environment()
	world_root = Node3D.new()
	world_root.name = "Habitat"
	add_child(world_root)
	_build_rooms()
	_build_corridors()
	_build_outside()
	_add_simple_room_props()
	_build_camera()
	_build_hud()


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var camera_target := player.global_position + Vector3(0, 20, 10)
	follow_camera.global_position = follow_camera.global_position.lerp(camera_target, minf(delta * 7.0, 1.0))
	follow_camera.look_at(player.global_position + Vector3(0, 0.75, 0), Vector3.UP)
	room_label.text = "AREA  /  " + _room_at_player()


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#07121c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b7d2d8")
	environment.ambient_light_energy = 0.8
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "Soft Station Light"
	key_light.rotation_degrees = Vector3(-58, -28, 0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = false
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

	for side: String in ["north", "east", "south", "west"]:
		_build_wall(room, side, room["doors"].has(side))


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
	for link: Array in LINKS:
		var first: Dictionary = rooms_by_id[link[0]]
		var second: Dictionary = rooms_by_id[link[1]]
		var first_center: Vector2 = first["center"]
		var second_center: Vector2 = second["center"]
		var first_size: Vector2 = first["size"]
		var second_size: Vector2 = second["size"]
		var delta := second_center - first_center
		var corridor_center := Vector2.ZERO
		var corridor_size := Vector2.ZERO
		if absf(delta.x) > absf(delta.y):
			var length := absf(delta.x) - (first_size.x + second_size.x) * 0.5
			if length <= 0.05:
				continue
			corridor_center = Vector2((first_center.x + second_center.x) * 0.5, first_center.y)
			corridor_size = Vector2(length, DOOR_WIDTH)
		else:
			var length := absf(delta.y) - (first_size.y + second_size.y) * 0.5
			if length <= 0.05:
				continue
			corridor_center = Vector2(first_center.x, (first_center.y + second_center.y) * 0.5)
			corridor_size = Vector2(DOOR_WIDTH, length)
		_make_box(
			world_root,
			str(first["title"]) + " to " + str(second["title"]) + " Hall",
			Vector3(corridor_center.x, -FLOOR_THICKNESS * 0.5, corridor_center.y),
			Vector3(corridor_size.x, FLOOR_THICKNESS, corridor_size.y),
			CORRIDOR_COLOR
		)


func _build_outside() -> void:
	var outside_center := Vector3(0, -0.17, 17)
	var surface := StaticBody3D.new()
	surface.name = "Outside Landing Area"
	surface.position = outside_center
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 9.5
	disc_mesh.bottom_radius = 9.5
	disc_mesh.height = 0.34
	disc_mesh.radial_segments = 40
	var disc_instance := MeshInstance3D.new()
	disc_instance.mesh = disc_mesh
	disc_instance.material_override = _material(Color("#505147"))
	surface.add_child(disc_instance)
	var disc_shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 9.5
	cylinder.height = 0.34
	disc_shape.shape = cylinder
	surface.add_child(disc_shape)
	world_root.add_child(surface)

	# A low safety rail surrounds the outside pad, with a clear gap back to the airlock.
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		if absf(wrapf(angle - PI, -PI, PI)) < 0.34:
			continue
		var rail_position := Vector3(sin(angle) * 9.25, 0.27, 17.0 + cos(angle) * 9.25)
		_make_box(world_root, "Outside safety rail", rail_position, Vector3(1.85, 0.54, 0.24), Color("#66746d"), angle)

	_add_solar_panels()
	_add_satellite_dish()


func _add_solar_panels() -> void:
	for x_position: float in [-4.4, -1.4]:
		var center := Vector3(x_position, 0.42, 16.2)
		_make_visual_box("Solar panel stand", center - Vector3(0, 0.22, 0), Vector3(0.16, 0.44, 0.16), Color("#8a9996"))
		_make_visual_box("Solar panel frame", center, Vector3(2.55, 0.16, 1.55), Color("#74838a"))
		_make_visual_box("Solar panel", center + Vector3(0, 0.1, 0), Vector3(2.37, 0.07, 1.38), Color("#174b65"))
		for strip in range(1, 4):
			var line_x := x_position - 0.95 + float(strip - 1) * 0.63
			_make_visual_box("Solar panel cell line", Vector3(line_x, 0.16, 16.2), Vector3(0.035, 0.025, 1.28), Color("#66cde0"))


func _add_satellite_dish() -> void:
	_make_visual_box("Satellite dish support", Vector3(4.25, 0.72, 17.2), Vector3(0.22, 1.4, 0.22), Color("#aab5b2"))
	var dish_mesh := SphereMesh.new()
	dish_mesh.radius = 0.95
	dish_mesh.height = 0.32
	var dish := MeshInstance3D.new()
	dish.name = "Satellite dish"
	dish.mesh = dish_mesh
	dish.scale = Vector3(1, 1, 0.72)
	dish.position = Vector3(4.25, 1.35, 17.2)
	dish.material_override = _material(Color("#bdc8c1"))
	world_root.add_child(dish)
	_make_visual_box("Satellite receiver", Vector3(4.25, 1.48, 17.2), Vector3(0.18, 0.18, 0.5), Color("#526c73"))


func _add_simple_room_props() -> void:
	# Small, non-blocking shapes identify rooms while keeping the layout open for roaming.
	_make_visual_box("Dining table", Vector3(0, 0.48, -10), Vector3(2.8, 0.18, 1.5), Color("#71858a"))
	_make_visual_box("Med bay bed", Vector3(-10.7, 0.25, -10), Vector3(1.6, 0.32, 2.5), Color("#b9c5c2"))
	_make_visual_box("Med bay pillow", Vector3(-10.7, 0.45, -10.8), Vector3(1.25, 0.14, 0.55), Color("#74b8bd"))
	_make_visual_box("Lab workbench", Vector3(-10, 0.52, 2.25), Vector3(4.0, 0.2, 0.8), Color("#74758a"))
	_make_visual_box("Rest room couch", Vector3(10, 0.42, -10), Vector3(2.7, 0.7, 0.9), Color("#697d83"))
	_make_visual_box("Sleeping bunk", Vector3(10, 0.28, 0), Vector3(2.7, 0.3, 1.5), Color("#aeb9b7"))
	_make_visual_box("Main room air filter", Vector3(3.2, 0.9, 2.1), Vector3(1.2, 1.8, 0.9), Color("#71858a"))
	_make_visual_box("Air filter screen", Vector3(3.2, 1.05, 1.62), Vector3(0.72, 0.44, 0.06), Color("#63d5dc"))
	for x_position: float in [-2.2, 0.0, 2.2]:
		_make_visual_box("Garden planter", Vector3(x_position, 0.22, -18.5), Vector3(1.0, 0.42, 1.0), Color("#655744"))
		_make_visual_sphere("Garden plant", Vector3(x_position, 0.73, -18.5), 0.52, Color("#7fa777"))


func _build_camera() -> void:
	follow_camera = Camera3D.new()
	follow_camera.name = "Follow Camera"
	follow_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	follow_camera.size = 20.0
	follow_camera.near = 0.1
	follow_camera.far = 100.0
	add_child(follow_camera)
	follow_camera.global_position = player.global_position + Vector3(0, 20, 10)
	follow_camera.look_at(player.global_position + Vector3(0, 0.75, 0), Vector3.UP)
	follow_camera.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	var title := _make_label("HABITAT ZERO", Vector2(22, 16), 19, Color("#baf9f3"))
	layer.add_child(title)
	room_label = _make_label("AREA  /  MAIN ROOM", Vector2(22, 43), 13, Color("#ffffff"))
	layer.add_child(room_label)
	var objective := _make_label("Walk through the open doors to explore.", Vector2(22, 65), 11, Color("#b4c7ca"))
	layer.add_child(objective)
	var controls := _make_label("MOVE  WASD / ARROWS      JUMP  SPACE", Vector2.ZERO, 11, Color("#d3e3e4"))
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


func _room_at_player() -> String:
	var player_position := Vector2(player.global_position.x, player.global_position.z)
	if player_position.distance_to(Vector2(0, 17)) <= 9.0:
		return "OUTSIDE"
	for room: Dictionary in ROOMS:
		var center: Vector2 = room["center"]
		var room_size: Vector2 = room["size"]
		if absf(player_position.x - center.x) <= room_size.x * 0.5 and absf(player_position.y - center.y) <= room_size.y * 0.5:
			return str(room["title"])
	return "CONNECTING HALL"


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


func _make_visual_sphere(sphere_name: String, sphere_position: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = sphere_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.mesh = mesh
	instance.position = sphere_position
	instance.material_override = _material(color)
	world_root.add_child(instance)
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
