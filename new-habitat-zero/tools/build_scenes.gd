extends SceneTree

# One-time builder: creates the TileSet, player animations, input map and the scenes
# (player, machine, hud, campaign, main) as real node trees you can edit in the editor.
# Run AFTER generate_art.gd and an import:
#   Godot --headless --path . --import
#   Godot --headless --path . -s res://tools/build_scenes.gd
# WARNING: re-running overwrites the scenes in res://scenes/ (including hand edits).

const T := 16

# Floor tile column in interior_tiles.png row 0.
const FLOOR := {"main": 0, "dining": 1, "garden": 2, "med": 3, "lab": 4, "restroom": 5, "sleep": 6, "airlock": 7, "corridor": 8}
const WALL := Vector2i(0, 1)
const WALL_LIGHT := Vector2i(1, 1)
const DOOR := Vector2i(2, 1)

# center/size in tiles. Same layout as the 3D Habitat Zero.
const ROOMS := [
	{"id": "main", "node": "MainRoom", "title": "MAIN ROOM", "center": Vector2i(0, 0), "size": Vector2i(16, 12)},
	{"id": "dining", "node": "DiningRoom", "title": "DINING ROOM", "center": Vector2i(0, -16), "size": Vector2i(16, 12)},
	{"id": "garden", "node": "Garden", "title": "GARDEN", "center": Vector2i(0, -28), "size": Vector2i(12, 10)},
	{"id": "med", "node": "MedicalBay", "title": "MEDICAL BAY", "center": Vector2i(-18, -16), "size": Vector2i(12, 12)},
	{"id": "lab", "node": "Lab", "title": "LAB", "center": Vector2i(-18, 0), "size": Vector2i(12, 12)},
	{"id": "restroom", "node": "Restroom", "title": "RESTROOM", "center": Vector2i(18, -16), "size": Vector2i(12, 12)},
	{"id": "sleep", "node": "Bedroom", "title": "BEDROOM", "center": Vector2i(18, 0), "size": Vector2i(12, 12)},
	{"id": "airlock", "node": "Airlock", "title": "AIRLOCK", "center": Vector2i(0, 13), "size": Vector2i(8, 8)},
]
const LINKS := [
	["main", "dining"], ["dining", "garden"], ["dining", "med"], ["med", "lab"], ["lab", "main"],
	["dining", "restroom"], ["restroom", "sleep"], ["main", "sleep"], ["main", "airlock"],
]
const OUTSIDE := Rect2i(-17, 17, 34, 34)
const MAP_BOUNDS := Rect2i(-27, -36, 54, 89)

# room id -> [[node name, texture, station id, bottom-centre in tiles], ...]
const FURNITURE := {
	"main": [
		["LifeSupport", "life_support", "life_support", Vector2(-5, -3)],
		["Crate", "crate", "", Vector2(5.5, -4)],
		["Crate2", "crate", "", Vector2(4.5, -4)],
		["Plant", "plant", "", Vector2(-6.5, 4)],
		["Plant2", "plant", "", Vector2(5.5, 4)],
	],
	"dining": [
		["Table", "table", "", Vector2(-3, -16)],
		["Table2", "table", "", Vector2(3, -16)],
		["Plant", "plant", "", Vector2(-6.5, -20)],
		["Locker", "locker", "", Vector2(5.5, -19)],
	],
	"garden": [
		["GardenBeds", "garden", "garden", Vector2(0, -27)],
		["GardenBedsWest", "garden", "", Vector2(-3.5, -27)],
		["GardenBedsEast", "garden", "", Vector2(3.5, -27)],
	],
	"med": [
		["MedicalAnalyzer", "medical", "medical", Vector2(-18, -19)],
		["Locker", "locker", "", Vector2(-22.5, -19)],
		["Plant", "plant", "", Vector2(-14.5, -12)],
	],
	"lab": [
		["LabBench", "lab_console", "lab_console", Vector2(-18, -4)],
		["Seismometer", "seismometer", "seismometer", Vector2(-20.5, 3)],
		["Crate", "crate", "", Vector2(-14.5, 4)],
	],
	"restroom": [
		["Toilet", "toilet", "", Vector2(14.5, -20)],
		["Toilet2", "toilet", "", Vector2(16.5, -20)],
		["Locker", "locker", "", Vector2(21.5, -19)],
	],
	"sleep": [
		["Bed", "bed", "bed", Vector2(21.5, -2)],
		["Bed2", "bed", "bed", Vector2(21.5, 3)],
		["Locker", "locker", "", Vector2(14.5, -3)],
	],
	"airlock": [
		["AirFilters", "airlock_filter", "airlock_filter", Vector2(-2.5, 13)],
		["SuitLocker", "locker", "", Vector2(2.5, 13)],
	],
}
const OUTSIDE_STATIONS := [
	["NeutronScanner", "neutron_station", "neutron_station", Vector2(-7, 23)],
	["RoverBattery", "rover_station", "rover_station", Vector2(7, 23)],
	["ScienceSensors", "field_station", "field_station", Vector2(12, 28)],
	["RockSamples", "sample_station", "sample_station", Vector2(-12, 28)],
	["HullTools", "hull_station", "hull_station", Vector2(5, 19)],
	["SolarPanels", "solar_station", "solar_station", Vector2(-8, 34)],
	["Antenna", "eva_station", "eva_station", Vector2(10, 37)],
]
# Regions of art/moonbase_props.png (Moon_Tileset_B downsampled to 16px tiles)
const ROCK_BIG := Rect2i(128, 125, 48, 32)
const ROCK_SMALL := Rect2i(224, 128, 32, 32)
const CRATERS := [Rect2i(96, 0, 32, 32), Rect2i(0, 208, 48, 32), Rect2i(16, 0, 16, 16), Rect2i(32, 0, 32, 16), Rect2i(80, 0, 16, 16)]

var machine_scene: PackedScene


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui"))
	_input_map()
	_theme()
	var tileset := _tileset()
	_save(_machine_scene(), "res://scenes/machine.tscn")
	machine_scene = load("res://scenes/machine.tscn")
	_save(_player_scene(), "res://scenes/player.tscn")
	_save(_hud_scene(), "res://scenes/hud.tscn")
	_save(_campaign_scene(), "res://scenes/campaign.tscn")
	_save(_main_scene(tileset), "res://scenes/main.tscn")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/main.tscn")
	ProjectSettings.set_setting("display/window/size/viewport_width", 320)
	ProjectSettings.set_setting("display/window/size/viewport_height", 180)
	ProjectSettings.set_setting("display/window/size/window_width_override", 1280)
	ProjectSettings.set_setting("display/window/size/window_height_override", 720)
	ProjectSettings.set_setting("gui/theme/custom", "res://ui/theme.tres")
	ProjectSettings.set_setting("gui/theme/custom_font", "res://ui/pixel_font.tres")
	ProjectSettings.save()
	quit()


func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("wrote " if err == OK else "FAILED ", path)
	root.free()


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	if node.scene_file_path != "":
		return  # instanced scene: its insides belong to that scene
	for child in node.get_children():
		_own(child, owner_node)


func _add(parent: Node, child: Node, node_name: String) -> Node:
	child.name = node_name
	parent.add_child(child)
	return child


func _input_map() -> void:
	var actions := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_E], "task_board": [KEY_TAB],
	}
	for action: String in actions:
		var events := []
		for key: int in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			events.append(event)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})


func _tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(T, T)
	tileset.add_physics_layer()
	var interior := TileSetAtlasSource.new()
	interior.texture = load("res://art/interior_tiles.png")
	interior.texture_region_size = Vector2i(T, T)
	tileset.add_source(interior, 0)
	for i in range(FLOOR.size()):
		interior.create_tile(Vector2i(i, 0))
	for coords in [WALL, WALL_LIGHT, DOOR]:
		interior.create_tile(coords)
	var half := T / 2.0
	var square := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for coords in [WALL, WALL_LIGHT]:
		var data := interior.get_tile_data(coords, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, square)
	var ground := TileSetAtlasSource.new()
	ground.texture = load("res://art/moon_ground.png")
	ground.texture_region_size = Vector2i(T, T)
	tileset.add_source(ground, 1)
	for i in range(4):
		ground.create_tile(Vector2i(i, 0))
	ResourceSaver.save(tileset, "res://art/habitat_tileset.tres")
	return load("res://art/habitat_tileset.tres")


func _machine_scene() -> Node:
	var root := StaticBody2D.new()
	root.name = "Machine"
	root.set_script(load("res://scripts/machine.gd"))
	_add(root, Sprite2D.new(), "Sprite2D")
	_add(root, CollisionShape2D.new(), "CollisionShape2D")
	_own_children(root)
	return root


func _own_children(root: Node) -> void:
	for child in root.get_children():
		_own(child, root)


func _player_scene() -> Node:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var sheet: Texture2D = load("res://art/astronaut.png")
	var rows := {"down": 0, "up": 1, "side": 2}
	for facing: String in rows:
		for kind in ["idle", "walk"]:
			var anim: String = kind + "_" + facing
			frames.add_animation(anim)
			frames.set_animation_speed(anim, 8.0)
			frames.set_animation_loop(anim, true)
			var order := [0] if kind == "idle" else [1, 0, 2, 0]
			for f: int in order:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(f * 24, rows[facing] * 24, 24, 24)
				frames.add_frame(anim, atlas)
	ResourceSaver.save(frames, "res://art/astronaut_frames.tres")

	var root := CharacterBody2D.new()
	root.name = "Player"
	root.set_script(load("res://scripts/player.gd"))
	root.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var sprite: AnimatedSprite2D = _add(root, AnimatedSprite2D.new(), "AnimatedSprite2D")
	sprite.sprite_frames = load("res://art/astronaut_frames.tres")
	sprite.animation = "idle_down"
	sprite.autoplay = "idle_down"
	sprite.offset = Vector2(0, -10)
	var shape := CircleShape2D.new()
	shape.radius = 4.5
	var collision: CollisionShape2D = _add(root, CollisionShape2D.new(), "CollisionShape2D")
	collision.shape = shape
	collision.position = Vector2(0, -2)
	var camera: Camera2D = _add(root, Camera2D.new(), "Camera2D")
	# No smoothing: the camera stays locked to the astronaut so the two are always rounded to
	# the pixel grid together (smoothing makes the astronaut jitter by a pixel).
	camera.limit_left = MAP_BOUNDS.position.x * T
	camera.limit_top = MAP_BOUNDS.position.y * T
	camera.limit_right = MAP_BOUNDS.end.x * T
	camera.limit_bottom = MAP_BOUNDS.end.y * T
	_own_children(root)
	return root


# --------------------------------------------------------------------- UI
# The UI is laid out for the 320x180 game resolution and uses one bitmap font at one size,
# so text pixels are exactly the same size as the art pixels.

const FONT_SIZE := 10
const GLYPH_ASCENT := 7
# 5x9 glyph cells: rows 0-6 sit above the baseline, rows 7-8 are descenders.
const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"a": [".....", ".....", ".###.", "....#", ".####", "#...#", ".####"],
	"b": ["#....", "#....", "####.", "#...#", "#...#", "#...#", "####."],
	"c": [".....", ".....", ".###.", "#....", "#....", "#...#", ".###."],
	"d": ["....#", "....#", ".####", "#...#", "#...#", "#...#", ".####"],
	"e": [".....", ".....", ".###.", "#...#", "#####", "#....", ".###."],
	"f": ["..##", ".#..", ".#..", "###.", ".#..", ".#..", ".#.."],
	"g": [".....", ".....", ".####", "#...#", "#...#", ".####", "....#", "#...#", ".###."],
	"h": ["#....", "#....", "#.##.", "##..#", "#...#", "#...#", "#...#"],
	"i": [".#.", "...", "##.", ".#.", ".#.", ".#.", "###"],
	"j": ["...#", "....", "..##", "...#", "...#", "...#", "...#", "#..#", ".##."],
	"k": ["#...", "#...", "#..#", "#.#.", "##..", "#.#.", "#..#"],
	"l": ["##.", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"m": [".....", ".....", "##.#.", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
	"n": [".....", ".....", "#.##.", "##..#", "#...#", "#...#", "#...#"],
	"o": [".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###."],
	"p": [".....", ".....", "####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"q": [".....", ".....", ".####", "#...#", "#...#", ".####", "....#", "....#", "....#"],
	"r": [".....", ".....", "#.##.", "##..#", "#....", "#....", "#...."],
	"s": [".....", ".....", ".####", "#....", ".###.", "....#", "####."],
	"t": [".#..", ".#..", "###.", ".#..", ".#..", ".#..", "..##"],
	"u": [".....", ".....", "#...#", "#...#", "#...#", "#..##", ".##.#"],
	"v": [".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"w": [".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
	"x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"y": [".....", ".....", "#...#", "#...#", "#...#", ".####", "....#", "#...#", ".###."],
	"z": [".....", ".....", "#####", "...#.", "..#..", ".#...", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": [".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###"],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	"!": ["#", "#", "#", "#", "#", ".", "#"],
	"#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
	"%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
	"'": ["#", "#", ".", ".", ".", ".", "."],
	"\"": ["#.#", "#.#", "...", "...", "...", "...", "..."],
	"(": ["..#", ".#.", "#..", "#..", "#..", ".#.", "..#"],
	")": ["#..", ".#.", "..#", "..#", "..#", ".#.", "#.."],
	"[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
	"]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
	"+": [".....", ".....", "..#..", "..#..", "#####", "..#..", "..#.."],
	",": ["..", "..", "..", "..", "..", ".#", ".#", "#."],
	"-": ["...", "...", "...", "...", "###", "...", "..."],
	".": [".", ".", ".", ".", ".", ".", "#"],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	":": [".", ".", "#", ".", ".", "#", "."],
	";": ["..", "..", ".#", "..", "..", ".#", ".#", "#."],
	"=": ["....", "....", "####", "....", "####", "....", "...."],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"_": ["....", "....", "....", "....", "....", "....", "####"],
	">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
	"<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
	"*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
	"&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
	"—": ["......", "......", "......", "......", "######", "......", "......"],
	"•": ["..", "..", "..", "##", "##", "..", ".."],
	"→": [".....", "..#..", "...#.", "#####", "...#.", "..#..", "....."],
	"▸": ["...", "#..", "##.", "###", "##.", "#..", "..."],
}


func _pixel_font() -> FontFile:
	var keys := GLYPHS.keys()
	var cell := Vector2i(8, 9)
	var cols := 16
	var image := Image.create(cols * cell.x, int(ceil(keys.size() / float(cols))) * cell.y, false, Image.FORMAT_LA8)
	image.fill(Color(1, 1, 1, 0))
	var font := FontFile.new()
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	font.allow_system_fallback = false
	font.fixed_size = FONT_SIZE
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	var size := Vector2i(FONT_SIZE, 0)
	font.set_cache_ascent(0, FONT_SIZE, GLYPH_ASCENT + 1)
	font.set_cache_descent(0, FONT_SIZE, 2)
	for i in range(keys.size()):
		var key: String = keys[i]
		var rows: Array = GLYPHS[key]
		var origin := Vector2i((i % cols) * cell.x, (i / cols) * cell.y)
		var width: int = str(rows[0]).length()
		for y in range(rows.size()):
			var row: String = rows[y]
			for x in range(row.length()):
				if row[x] == "#":
					image.set_pixel(origin.x + x, origin.y + y, Color(1, 1, 1, 1))
		var codepoint := key.unicode_at(0)
		font.set_glyph_advance(0, FONT_SIZE, codepoint, Vector2(width + 1, 0))
		font.set_glyph_offset(0, size, codepoint, Vector2(0, -GLYPH_ASCENT))
		font.set_glyph_size(0, size, codepoint, Vector2(width, cell.y))
		font.set_glyph_uv_rect(0, size, codepoint, Rect2(origin, Vector2(width, cell.y)))
		font.set_glyph_texture_idx(0, size, codepoint, 0)
	# Space and a few look-alikes.
	font.set_glyph_advance(0, FONT_SIZE, " ".unicode_at(0), Vector2(3, 0))
	font.set_texture_image(0, size, 0, image)
	ResourceSaver.save(font, "res://ui/pixel_font.tres")
	image.save_png("res://ui/pixel_font_preview.png")
	return load("res://ui/pixel_font.tres")


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 2
	style.content_margin_bottom = 1
	return style


func _theme() -> Theme:
	var font := _pixel_font()
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE
	theme.set_font("normal_font", "RichTextLabel", font)
	theme.set_font("bold_font", "RichTextLabel", font)
	theme.set_font_size("normal_font_size", "RichTextLabel", FONT_SIZE)
	theme.set_font_size("bold_font_size", "RichTextLabel", FONT_SIZE)
	theme.set_color("font_color", "Label", Color("#e0e9e6"))
	theme.set_color("default_color", "RichTextLabel", Color("#d6e1de"))
	theme.set_color("font_color", "Button", Color("#e8f2ef"))
	theme.set_color("font_hover_color", "Button", Color("#ffffff"))
	theme.set_color("font_pressed_color", "Button", Color("#baf9f3"))
	theme.set_color("font_disabled_color", "Button", Color("#75858a"))
	theme.set_stylebox("normal", "Button", _style(Color("#20363e"), Color("#48656c")))
	theme.set_stylebox("hover", "Button", _style(Color("#29474e"), Color("#71ded3")))
	theme.set_stylebox("pressed", "Button", _style(Color("#14282f"), Color("#83eee2")))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "Button", _style(Color("#1a292e"), Color("#35474c")))
	theme.set_stylebox("panel", "PanelContainer", _style(Color(0.025, 0.055, 0.072, 0.9), Color("#456b70")))
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color("#10202a")
		track.set_content_margin_all(1)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color("#56c6c2")
		grab.set_content_margin_all(1)
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("grabber", bar, grab)
		theme.set_stylebox("grabber_highlight", bar, grab)
		theme.set_stylebox("grabber_pressed", bar, grab)
	var field := _style(Color("#0f1d23"), Color("#48656c"))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", _style(Color("#0f1d23"), Color("#83eee2")))
	ResourceSaver.save(theme, "res://ui/theme.tres")
	return load("res://ui/theme.tres")


func _label(parent: Node, node_name: String, color: Color, unique := true) -> Label:
	var label: Label = _add(parent, Label.new(), node_name)
	label.unique_name_in_owner = unique
	label.add_theme_color_override("font_color", color)
	return label


func _hud_scene() -> Node:
	var root := CanvasLayer.new()
	root.name = "HUD"
	root.set_script(load("res://scripts/hud.gd"))
	var screen: Control = _add(root, Control.new(), "Screen")
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var alarm: ColorRect = _add(screen, ColorRect.new(), "Alarm")
	alarm.unique_name_in_owner = true
	alarm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	alarm.color = Color(1.0, 0.15, 0.1, 0.0)
	alarm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alarm.visible = false

	var room_panel: PanelContainer = _add(screen, PanelContainer.new(), "RoomPanel")
	room_panel.anchor_left = 0.5
	room_panel.anchor_right = 0.5
	room_panel.anchor_top = 1.0
	room_panel.anchor_bottom = 1.0
	room_panel.offset_left = -45
	room_panel.offset_right = 45
	room_panel.offset_top = -15
	room_panel.offset_bottom = -2
	room_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	room_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var room_label := _label(room_panel, "RoomLabel", Color("#baf9f3"))
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_label.text = "MAIN ROOM"

	var hint_panel: PanelContainer = _add(screen, PanelContainer.new(), "HintPanel")
	hint_panel.unique_name_in_owner = true
	hint_panel.anchor_left = 0.5
	hint_panel.anchor_right = 0.5
	hint_panel.anchor_top = 1.0
	hint_panel.anchor_bottom = 1.0
	hint_panel.offset_left = -150
	hint_panel.offset_right = 150
	hint_panel.offset_top = -31
	hint_panel.offset_bottom = -18
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.07, 0.03, 0.92), Color("#d6ba72")))
	hint_panel.visible = false
	var hint_label := _label(hint_panel, "HintLabel", Color("#ffe7a6"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var minimap: Control = _add(screen, Control.new(), "Minimap")
	minimap.unique_name_in_owner = true
	minimap.set_script(load("res://scripts/minimap.gd"))
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -54
	minimap.offset_right = -2
	minimap.offset_top = 2
	minimap.offset_bottom = 92
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_own_children(root)
	return root


func _campaign_scene() -> Node:
	var root := CanvasLayer.new()
	root.name = "Campaign"
	root.layer = 2
	root.set_script(load("res://scripts/campaign.gd"))
	var ui: Control = _add(root, Control.new(), "Interface")
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Status plate (top-left, leaves room for the deck map on the right).
	var plate: PanelContainer = _add(ui, PanelContainer.new(), "StatusPanel")
	plate.position = Vector2(2, 2)
	plate.size = Vector2(260, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows: VBoxContainer = _add(plate, VBoxContainer.new(), "Rows")
	rows.add_theme_constant_override("separation", 0)
	_label(rows, "StatusLabel", Color("#baf9f3"))
	_label(rows, "ScoreLabel", Color("#9ed9d2"))
	var banner := _label(rows, "BannerLabel", Color("#ffe7a6"))
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.custom_minimum_size.x = 254
	var deadline := _label(rows, "DeadlineLabel", Color("#ffd18a"))
	deadline.visible = false  # routine reminder; it lives in How to Play instead

	# Task board.
	var board: Control = _add(ui, Control.new(), "Board")
	board.unique_name_in_owner = true
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.visible = false
	var shade: ColorRect = _add(board, ColorRect.new(), "Shade")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.035, 0.85)
	var modal: PanelContainer = _add(board, PanelContainer.new(), "Modal")
	modal.unique_name_in_owner = true
	modal.anchor_right = 1.0
	modal.anchor_bottom = 1.0
	modal.offset_left = 4
	modal.offset_top = 4
	modal.offset_right = -4
	modal.offset_bottom = -4
	modal.add_theme_stylebox_override("panel", _style(Color("#16272e"), Color("#56c6c2")))
	var scroll: ScrollContainer = _add(modal, ScrollContainer.new(), "MissionScroll")
	scroll.unique_name_in_owner = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column: VBoxContainer = _add(scroll, VBoxContainer.new(), "Column")
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)

	var header: HBoxContainer = _add(column, HBoxContainer.new(), "Header")
	var title := _label(header, "ModalTitle", Color("#ffd35c"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long titles wrap instead of pushing Close off-screen
	var close: Button = _add(header, Button.new(), "CloseButton")
	close.unique_name_in_owner = true
	close.text = "Close [Tab]"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var event_card: PanelContainer = _add(column, PanelContainer.new(), "EventCard")
	event_card.add_theme_stylebox_override("panel", _style(Color("#1c3038"), Color("#527078")))
	var event_label := _label(event_card, "EventLabel", Color("#e5eeee"))
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var resource_card: PanelContainer = _add(column, PanelContainer.new(), "ResourceCard")
	resource_card.add_theme_stylebox_override("panel", _style(Color("#14262d"), Color("#354f56")))
	_label(resource_card, "ResourceLabel", Color("#87d7d1"))
	var outcome := _label(column, "OutcomeLabel", Color("#ffdb8f"))
	outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var choices: VBoxContainer = _add(column, VBoxContainer.new(), "ChoiceList")
	choices.unique_name_in_owner = true
	choices.add_theme_constant_override("separation", 3)

	var manual: ScrollContainer = _add(column, ScrollContainer.new(), "ManualPanel")
	manual.unique_name_in_owner = true
	manual.custom_minimum_size.y = 120
	manual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	manual.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	manual.visible = false
	var manual_text: RichTextLabel = _add(manual, RichTextLabel.new(), "ManualText")
	manual_text.unique_name_in_owner = true
	manual_text.bbcode_enabled = true
	manual_text.fit_content = true
	manual_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var challenge: VBoxContainer = _add(column, VBoxContainer.new(), "ChallengePanel")
	challenge.unique_name_in_owner = true
	challenge.visible = false
	var instructions := _label(challenge, "ChallengeInstructions", Color("#e6efec"))
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(challenge, "ChallengeProgress", Color("#87d7d1"))
	var area: VBoxContainer = _add(challenge, VBoxContainer.new(), "ChallengeArea")
	area.unique_name_in_owner = true
	area.add_theme_constant_override("separation", 2)
	# "Learn more from NASA" link for the current task.
	var learn: RichTextLabel = _add(challenge, RichTextLabel.new(), "LearnMore")
	learn.unique_name_in_owner = true
	learn.bbcode_enabled = true
	learn.fit_content = true

	var footer: HBoxContainer = _add(column, HBoxContainer.new(), "Footer")
	footer.add_theme_constant_override("separation", 4)
	var manual_button: Button = _add(footer, Button.new(), "ManualButton")
	manual_button.unique_name_in_owner = true
	manual_button.text = "How to Play"
	var begin: Button = _add(footer, Button.new(), "BeginButton")
	begin.unique_name_in_owner = true
	begin.text = "Play Again"
	begin.visible = false
	_own_children(root)
	return root


# ------------------------------------------------------------------- level

func _room_rect(room: Dictionary) -> Rect2i:
	var size: Vector2i = room["size"]
	return Rect2i(room["center"] - size / 2, size)


func _main_scene(tileset: TileSet) -> Node:
	var root := Node2D.new()
	root.name = "Main"
	root.set_script(load("res://scripts/main.gd"))
	var world: Node2D = _add(root, Node2D.new(), "World")
	var ground: TileMapLayer = _add(world, TileMapLayer.new(), "Ground")
	var floors: TileMapLayer = _add(world, TileMapLayer.new(), "Floors")
	var walls: TileMapLayer = _add(world, TileMapLayer.new(), "Walls")
	for layer: TileMapLayer in [ground, floors, walls]:
		layer.tile_set = tileset
	var craters: Node2D = _add(world, Node2D.new(), "Craters")
	var objects: Node2D = _add(world, Node2D.new(), "Objects")
	objects.y_sort_enabled = true
	var marker: Node2D = _add(world, Node2D.new(), "TaskMarker")
	marker.unique_name_in_owner = true
	marker.set_script(load("res://scripts/task_marker.gd"))
	marker.z_index = 50

	# Ground everywhere.
	for y in range(MAP_BOUNDS.position.y, MAP_BOUNDS.end.y):
		for x in range(MAP_BOUNDS.position.x, MAP_BOUNDS.end.x):
			ground.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))

	var rects := {}
	for room: Dictionary in ROOMS:
		rects[room["id"]] = _room_rect(room)
	# Room floors + walls.
	for room: Dictionary in ROOMS:
		var rect: Rect2i = rects[room["id"]]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				var edge := x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
				if edge:
					walls.set_cell(cell, 0, WALL_LIGHT if (y == rect.position.y and posmod(x, 4) == 2) else WALL)
				else:
					floors.set_cell(cell, 0, Vector2i(FLOOR[room["id"]], 0))

	# Rooms container (y-sorted so the astronaut walks behind/in front of machines).
	var rooms_node: Node2D = _add(objects, Node2D.new(), "Rooms")
	rooms_node.y_sort_enabled = true
	var halls_node: Node2D = _add(rooms_node, Node2D.new(), "Hallways")
	halls_node.y_sort_enabled = true

	# Hallways + doors.
	for link: Array in LINKS:
		var a: Rect2i = rects[link[0]]
		var b: Rect2i = rects[link[1]]
		var hall_rect := Rect2i()
		if a.get_center().x == b.get_center().x:
			var top := a if a.position.y < b.position.y else b
			var bottom := b if top == a else a
			var cx := int(top.get_center().x)
			var y0 := top.end.y - 1
			var y1 := bottom.position.y
			for y in range(y0, y1 + 1):
				for x in range(cx - 1, cx + 2):
					walls.erase_cell(Vector2i(x, y))
					floors.set_cell(Vector2i(x, y), 0, DOOR if y == y0 or y == y1 else Vector2i(FLOOR["corridor"], 0))
				if y != y0 and y != y1:
					walls.set_cell(Vector2i(cx - 2, y), 0, WALL)
					walls.set_cell(Vector2i(cx + 2, y), 0, WALL)
			hall_rect = Rect2i(cx - 2, y0 + 1, 5, y1 - y0 - 1)
		else:
			var left := a if a.position.x < b.position.x else b
			var right := b if left == a else a
			var cy := int(left.get_center().y)
			var x0 := left.end.x - 1
			var x1 := right.position.x
			for x in range(x0, x1 + 1):
				for y in range(cy - 1, cy + 2):
					walls.erase_cell(Vector2i(x, y))
					floors.set_cell(Vector2i(x, y), 0, DOOR if x == x0 or x == x1 else Vector2i(FLOOR["corridor"], 0))
				if x != x0 and x != x1:
					walls.set_cell(Vector2i(x, cy - 2), 0, WALL)
					walls.set_cell(Vector2i(x, cy + 2), 0, WALL)
			hall_rect = Rect2i(x0 + 1, cy - 2, x1 - x0 - 1, 5)
		var hall := _room_node(halls_node, "Hall_%s_%s" % [link[0], link[1]], "hall", "HALLWAY", hall_rect)
		hall.is_hallway = true
		hall.map_color = Color("#2b3d42")

	# Airlock -> outside door.
	var airlock: Rect2i = rects["airlock"]
	for x in range(-1, 2):
		walls.erase_cell(Vector2i(x, airlock.end.y - 1))
		floors.set_cell(Vector2i(x, airlock.end.y - 1), 0, DOOR)

	# Room nodes with their machines.
	for room: Dictionary in ROOMS:
		var node := _room_node(rooms_node, room["node"], room["id"], room["title"], rects[room["id"]])
		node.map_color = Color("#334739") if room["id"] == "garden" else Color("#1a2b31")
		for item: Array in FURNITURE.get(room["id"], []):
			_machine(node, item[0], item[1], item[2], item[3])

	# Outside.
	var outside := _room_node(objects, "Outside", "outside", "OUTSIDE", OUTSIDE)
	outside.map_color = Color("#3a3d40")
	var stations_node: Node2D = _add(outside, Node2D.new(), "Stations")
	stations_node.y_sort_enabled = true
	for item: Array in OUTSIDE_STATIONS:
		_machine(stations_node, item[0], item[1], item[2], item[3])
	var rocks_node: Node2D = _add(outside, Node2D.new(), "Rocks")
	rocks_node.y_sort_enabled = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var tileset_b: Texture2D = load("res://art/moonbase_props.png")
	# Rocks around the edge of the outside area.
	var rock_count := 0
	for x in range(OUTSIDE.position.x, OUTSIDE.end.x + 1, 3):
		for y in [OUTSIDE.end.y + 0.6]:
			_rock(rocks_node, "Rock%d" % rock_count, tileset_b, ROCK_SMALL if rng.randf() < 0.6 else ROCK_BIG, Vector2(x + rng.randf_range(-0.5, 0.5), y))
			rock_count += 1
	for y in range(OUTSIDE.position.y + 2, OUTSIDE.end.y, 3):
		for x in [OUTSIDE.position.x - 0.6, OUTSIDE.end.x + 0.6]:
			_rock(rocks_node, "Rock%d" % rock_count, tileset_b, ROCK_SMALL if rng.randf() < 0.6 else ROCK_BIG, Vector2(x, y + rng.randf_range(-0.4, 0.4)))
			rock_count += 1
	# A few boulders inside the area (solid).
	for spot in [Vector2(-3, 30), Vector2(14, 44), Vector2(-14, 42), Vector2(3, 46)]:
		var boulder := _rock(rocks_node, "Boulder%d" % rock_count, tileset_b, ROCK_BIG, spot)
		boulder.solid = true
		rock_count += 1
	# Flat craters (drawn under everything).
	var crater_spots := [Vector2(-4, 25), Vector2(13, 33), Vector2(-13, 36), Vector2(2, 41), Vector2(-9, 46), Vector2(9, 47), Vector2(-15, 21), Vector2(15, 20)]
	for i in range(crater_spots.size()):
		var sprite: Sprite2D = _add(craters, Sprite2D.new(), "Crater%d" % i)
		var atlas := AtlasTexture.new()
		atlas.atlas = tileset_b
		atlas.region = CRATERS[i % CRATERS.size()]
		sprite.texture = atlas
		sprite.position = crater_spots[i] * T

	# Invisible fence around the outside area (leaves the airlock door open).
	var bounds: StaticBody2D = _add(outside, StaticBody2D.new(), "Boundary")
	var fence := [
		Rect2i(OUTSIDE.position.x - 1, OUTSIDE.position.y - 1, -OUTSIDE.position.x + airlock.position.x + 1, 1),
		Rect2i(airlock.end.x, OUTSIDE.position.y - 1, OUTSIDE.end.x - airlock.end.x + 1, 1),
		Rect2i(OUTSIDE.position.x - 1, OUTSIDE.position.y - 1, 1, OUTSIDE.size.y + 2),
		Rect2i(OUTSIDE.end.x, OUTSIDE.position.y - 1, 1, OUTSIDE.size.y + 2),
		Rect2i(OUTSIDE.position.x - 1, OUTSIDE.end.y, OUTSIDE.size.x + 2, 1),
	]
	for i in range(fence.size()):
		var r: Rect2i = fence[i]
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r.size * T)
		var collision: CollisionShape2D = _add(bounds, CollisionShape2D.new(), "Fence%d" % i)
		collision.shape = shape
		collision.position = (Vector2(r.position) + Vector2(r.size) / 2.0) * T

	var player: Node2D = load("res://scenes/player.tscn").instantiate()
	player.name = "Player"
	player.unique_name_in_owner = true
	objects.add_child(player)
	player.position = Vector2(0, 2 * T)

	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	hud.name = "HUD"
	root.add_child(hud)
	var campaign: Node = load("res://scenes/campaign.tscn").instantiate()
	campaign.name = "Campaign"
	root.add_child(campaign)
	_own_children(root)
	return root


func _room_node(parent: Node, node_name: String, id: String, title: String, rect: Rect2i) -> Room:
	var node := Node2D.new()
	node.set_script(load("res://scripts/room.gd"))
	node.y_sort_enabled = true
	_add(parent, node, node_name)
	node.room_id = id
	node.title = title
	node.tile_rect = rect
	return node


func _machine(parent: Node, node_name: String, texture_name: String, station_id: String, tile_pos: Vector2) -> Node:
	var machine := machine_scene.instantiate()
	machine.name = node_name
	parent.add_child(machine)
	machine.texture = load("res://art/%s.png" % texture_name)
	machine.station_id = station_id
	machine.position = tile_pos * T
	return machine


func _rock(parent: Node, node_name: String, sheet: Texture2D, region: Rect2i, tile_pos: Vector2) -> Node:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	var rock := machine_scene.instantiate()
	rock.name = node_name
	parent.add_child(rock)
	rock.texture = atlas
	rock.solid = false
	rock.footprint_height = region.size.y * 0.5
	rock.position = tile_pos * T
	return rock
