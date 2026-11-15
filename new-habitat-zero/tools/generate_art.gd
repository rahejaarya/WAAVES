extends SceneTree

# Generates the game's pixel art into res://art/.
# Run:  Godot --headless --path . -s res://tools/generate_art.gd
# Everything is drawn at native resolution: one tile = 16 art pixels. The world is rendered
# at 320x180 and scaled up 3x as a whole, so every pixel on screen is the same size.
# The Moonbase sheets (48px tiles) are downsampled 3x to match.
# Edit the PNGs by hand afterwards if you like; re-running this script overwrites them.

const SCALE := 1
const ASTRO := 24  # astronaut frame size (bigger than a 16px tile)
const OUT := Color("#14181c")
const M0 := Color("#283035")
const M1 := Color("#3f4b52")
const M2 := Color("#64737a")
const M3 := Color("#93a3a8")
const M4 := Color("#c6d1d2")
const WHITE := Color("#eef3f1")
const SUIT_SHADE := Color("#b9c4c7")
const TEAL := Color("#4fd1c5")
const TEAL_DK := Color("#21706c")
const YELLOW := Color("#e8c25a")
const RED := Color("#e0584f")
const GREEN := Color("#6cc66a")
const GREEN_DK := Color("#2f7a3c")
const SCREEN := Color("#1d3f52")
const GLASS := Color("#8fd0e8")
const BROWN := Color("#6b4a32")
const BROWN_DK := Color("#46301f")
const SHADOW := Color(0, 0, 0, 0.32)

const ROOM_FLOORS := {
	"main": Color("#596462"), "dining": Color("#5f655c"), "garden": Color("#334739"),
	"med": Color("#6b7676"), "lab": Color("#575861"), "restroom": Color("#5c6260"),
	"sleep": Color("#5b5f6b"), "airlock": Color("#535c5d"), "corridor": Color("#4a5456"),
}


class Canvas:
	var img: Image
	var w: int
	var h: int

	func _init(width: int, height: int) -> void:
		w = width
		h = height
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))

	func px(x: int, y: int, c: Color) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			img.set_pixel(x, y, c)

	func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		for yy in range(y, y + rh):
			for xx in range(x, x + rw):
				px(xx, yy, c)

	func frame(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		for xx in range(x, x + rw):
			px(xx, y, c)
			px(xx, y + rh - 1, c)
		for yy in range(y, y + rh):
			px(x, yy, c)
			px(x + rw - 1, yy, c)

	func disc(cx: float, cy: float, r: float, c: Color) -> void:
		for yy in range(int(cy - r - 1), int(cy + r + 2)):
			for xx in range(int(cx - r - 1), int(cx + r + 2)):
				if Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length() <= r:
					px(xx, yy, c)

	func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
		var steps := maxi(absi(x1 - x0), absi(y1 - y0))
		for i in range(steps + 1):
			var t := 0.0 if steps == 0 else float(i) / steps
			px(roundi(lerpf(x0, x1, t)), roundi(lerpf(y0, y1, t)), c)

	# Dark 1px outline around every opaque pixel (classic sprite outline).
	func outline() -> void:
		var copy := img.duplicate()
		for y in range(h):
			for x in range(w):
				if copy.get_pixel(x, y).a > 0.0:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx >= 0 and ny >= 0 and nx < w and ny < h and copy.get_pixel(nx, ny).a > 0.9:
						img.set_pixel(x, y, OUT)
						break

	# Soft ground shadow under an object, drawn only on empty pixels.
	func shadow(x: int, y: int, rw: int, rh: int) -> void:
		var cx := x + rw / 2.0
		var cy := y + rh / 2.0
		for yy in range(y, y + rh):
			for xx in range(x, x + rw):
				var dx := (xx + 0.5 - cx) / (rw / 2.0)
				var dy := (yy + 0.5 - cy) / (rh / 2.0)
				if dx * dx + dy * dy <= 1.0 and xx >= 0 and yy >= 0 and xx < w and yy < h and img.get_pixel(xx, yy).a == 0.0:
					img.set_pixel(xx, yy, SHADOW)

	func blit(other: Canvas, ox: int, oy: int) -> void:
		img.blit_rect(other.img, Rect2i(0, 0, other.w, other.h), Vector2i(ox, oy))

	func save(path: String) -> void:
		var out := img.duplicate()
		out.resize(w * SCALE, h * SCALE, Image.INTERPOLATE_NEAREST)
		var err: Error = out.save_png(path)
		if err != OK:
			push_error("Could not save %s (%d)" % [path, err])
		else:
			print("wrote ", path)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art"))
	_interior_tiles()
	_moon_ground()
	_astronaut()
	var machines := {
		"life_support": _life_support(), "seismometer": _seismometer(), "lab_console": _lab_console(),
		"airlock_filter": _airlock_filter(), "medical": _medical(), "garden": _garden(), "bed": _bed(),
		"neutron_station": _rover(), "rover_station": _battery_cart(), "field_station": _sensor_mast(),
		"sample_station": _sample_box(), "hull_station": _repair_kit(), "solar_station": _solar_array(),
		"eva_station": _antenna(), "table": _table(), "toilet": _toilet(), "crate": _crate(),
		"plant": _plant(), "locker": _locker(),
	}
	for key: String in machines:
		var canvas: Canvas = machines[key]
		canvas.save("res://art/%s.png" % key)
	quit()


# ------------------------------------------------------------------ tiles

func _interior_tiles() -> void:
	# Row 0: room floors (order = ROOM_FLOORS keys). Row 1: wall, wall-top, door strip.
	var keys := ROOM_FLOORS.keys()
	var sheet := Canvas.new(16 * 16, 16 * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(keys.size()):
		var base: Color = ROOM_FLOORS[keys[i]]
		var t := Canvas.new(16, 16)
		t.rect(0, 0, 16, 16, base)
		if keys[i] == "garden":
			for k in range(0, 16, 4):
				t.rect(k, 0, 1, 16, base.darkened(0.35))
				t.rect(0, k, 16, 1, base.darkened(0.35))
		else:
			for n in range(14):
				t.px(rng.randi_range(1, 14), rng.randi_range(1, 14), base.darkened(0.07))
			t.rect(0, 0, 16, 1, base.lightened(0.1))
			t.rect(0, 0, 1, 16, base.lightened(0.1))
			t.rect(0, 15, 16, 1, base.darkened(0.28))
			t.rect(15, 0, 1, 16, base.darkened(0.28))
			for corner in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
				t.px(corner.x, corner.y, base.lightened(0.25))
			if keys[i] == "corridor":
				t.rect(7, 0, 2, 16, base.darkened(0.15))
		sheet.blit(t, i * 16, 0)
	# Wall block: bevelled hull panel.
	var wall := Canvas.new(16, 16)
	wall.rect(0, 0, 16, 16, M2)
	wall.rect(0, 0, 16, 2, M3)
	wall.rect(0, 0, 2, 16, M3)
	wall.rect(0, 14, 16, 2, M1)
	wall.rect(14, 0, 2, 16, M1)
	wall.frame(4, 4, 8, 8, M1)
	wall.px(4, 4, M3)
	sheet.blit(wall, 0, 16)
	# Wall with a teal light strip (variety).
	var wall2 := Canvas.new(16, 16)
	wall2.blit(wall, 0, 0)
	wall2.rect(5, 7, 6, 2, TEAL)
	sheet.blit(wall2, 16, 16)
	# Door threshold: hazard stripes.
	var door := Canvas.new(16, 16)
	door.rect(0, 0, 16, 16, M1)
	for k in range(-16, 16, 4):
		door.line(k, 15, k + 15, 0, YELLOW)
		door.line(k + 1, 15, k + 16, 0, YELLOW)
	door.rect(0, 3, 16, 10, M1)
	door.rect(0, 4, 16, 8, ROOM_FLOORS["corridor"])
	sheet.blit(door, 32, 16)
	sheet.save("res://art/interior_tiles.png")


func _moon_ground() -> void:
	# Pulls seamless fill tiles out of the RPG Maker style A2 autotile sheet.
	# Each A2 autotile is a 96x144 block; its seamless centre is at (24, 72), 48x48.
	var a2 := Image.load_from_file(ProjectSettings.globalize_path("res://Moonbase/Moon_Tileset_A2.png"))
	var out := Image.create(48 * 4, 48, false, Image.FORMAT_RGBA8)
	var blocks := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	for i in range(blocks.size()):
		var origin: Vector2i = blocks[i] * Vector2i(96, 144)
		out.blit_rect(a2, Rect2i(origin + Vector2i(24, 72), Vector2i(48, 48)), Vector2i(i * 48, 0))
	_downsample(out).save_png("res://art/moon_ground.png")
	print("wrote res://art/moon_ground.png")
	# Rocks and craters sheet, downsampled to the same pixel grid.
	var b := Image.load_from_file(ProjectSettings.globalize_path("res://Moonbase/Moon_Tileset_B.png"))
	_downsample(b).save_png("res://art/moonbase_props.png")
	print("wrote res://art/moonbase_props.png")


# 48px-per-tile art -> 16px-per-tile art with hard (on/off) alpha, so it sits on the same
# pixel grid as everything else.
func _downsample(source: Image) -> Image:
	var img := source.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() / 3, img.get_height() / 3, Image.INTERPOLATE_LANCZOS)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			c.a = 1.0 if c.a >= 0.5 else 0.0
			img.set_pixel(x, y, c)
	return img


# ---------------------------------------------------------------- astronaut

func _astronaut() -> void:
	# 24x24 frames (the astronaut is ~1.5 tiles tall): 3 frames (idle, step A, step B)
	# x 3 rows (down, up, side-facing-right).
	var sheet := Canvas.new(ASTRO * 3, ASTRO * 3)
	for f in range(3):
		sheet.blit(_astro_frame("down", f), f * ASTRO, 0)
		sheet.blit(_astro_frame("up", f), f * ASTRO, ASTRO)
		sheet.blit(_astro_frame("side", f), f * ASTRO, ASTRO * 2)
	sheet.save("res://art/astronaut.png")


func _astro_frame(facing: String, f: int) -> Canvas:
	var c := Canvas.new(ASTRO, ASTRO)
	var VISOR := Color("#c99a3c")  # gold sun visor
	var VISOR_DK := Color("#7a5520")
	if facing == "side":
		var stride := 0 if f == 0 else (2 if f == 1 else -2)
		# Back leg, then front leg.
		c.rect(10 - stride, 17, 3, 4, SUIT_SHADE)
		c.rect(10 - stride, 20, 4, 2, M1)
		c.rect(11 + stride, 17, 3, 4, WHITE)
		c.rect(11 + stride, 20, 4, 2, M1)
		# Backpack.
		c.rect(5, 10, 4, 8, M3)
		c.rect(5, 10, 4, 1, M4)
		c.px(6, 12, TEAL)
		c.rect(6, 15, 2, 1, M2)
		# Torso.
		c.rect(9, 10, 7, 7, WHITE)
		c.rect(9, 16, 7, 1, SUIT_SHADE)
		c.rect(10, 16, 5, 1, M2)
		# Arm swinging opposite the front leg.
		c.rect(12 - stride / 2, 11, 2, 5, SUIT_SHADE)
		c.rect(12 - stride / 2, 16, 2, 2, M2)
		# Helmet.
		c.rect(10, 1, 5, 1, WHITE)
		c.rect(9, 2, 7, 1, WHITE)
		c.rect(8, 3, 9, 6, WHITE)
		c.rect(9, 9, 7, 1, SUIT_SHADE)
		c.rect(8, 8, 2, 1, SUIT_SHADE)
		c.rect(13, 4, 4, 4, VISOR)
		c.rect(13, 7, 4, 1, VISOR_DK)
		c.px(14, 4, Color("#f6dc8a"))
		c.px(9, 5, M3)
	else:
		var lift_l := 2 if f == 1 else 0
		var lift_r := 2 if f == 2 else 0
		# Legs + boots (the lifted leg is shorter).
		c.rect(8, 17, 3, 4 - lift_l, WHITE)
		c.rect(7, 20 - lift_l, 4, 2, M1)
		c.rect(13, 17, 3, 4 - lift_r, WHITE)
		c.rect(13, 20 - lift_r, 4, 2, M1)
		c.rect(15, 17, 1, 4 - lift_r, SUIT_SHADE)
		# Torso.
		c.rect(6, 10, 12, 7, WHITE)
		c.rect(17, 10, 1, 7, SUIT_SHADE)
		c.rect(6, 16, 12, 1, M2)
		# Arms swing with the opposite leg.
		c.rect(4, 11 + lift_r / 2, 2, 5, SUIT_SHADE)
		c.rect(4, 16 + lift_r / 2, 2, 2, M2)
		c.rect(18, 11 + lift_l / 2, 2, 5, SUIT_SHADE)
		c.rect(18, 16 + lift_l / 2, 2, 2, M2)
		if facing == "down":
			# Chest control box.
			c.rect(10, 12, 4, 3, M3)
			c.px(11, 13, TEAL)
			c.px(12, 13, RED)
			c.rect(7, 11, 2, 1, Color("#3d6fb5"))  # mission patch
		else:
			# Life-support backpack.
			c.rect(7, 9, 10, 8, M3)
			c.rect(7, 9, 10, 1, M4)
			c.rect(8, 11, 8, 1, M2)
			c.rect(8, 13, 8, 1, M2)
			c.px(15, 15, TEAL)
			c.px(9, 15, YELLOW)
		# Helmet.
		c.rect(9, 1, 6, 1, WHITE)
		c.rect(8, 2, 8, 1, WHITE)
		c.rect(7, 3, 10, 6, WHITE)
		c.rect(16, 3, 1, 6, SUIT_SHADE)
		c.rect(8, 9, 8, 1, SUIT_SHADE)
		if facing == "down":
			c.rect(8, 4, 8, 4, VISOR)
			c.rect(8, 7, 8, 1, VISOR_DK)
			c.px(9, 4, Color("#f6dc8a"))
			c.px(10, 4, Color("#f6dc8a"))
			c.px(9, 5, Color("#f6dc8a"))
		else:
			c.rect(7, 7, 10, 2, SUIT_SHADE)
	c.outline()
	c.shadow(6, 20, 13, 4)
	return c


# ----------------------------------------------------------------- machines
# Sprites use a 3/4 view: a lighter top face, then the front face.

func _box(c: Canvas, x: int, y: int, bw: int, bh: int, top: int, body: Color) -> void:
	c.rect(x, y, bw, bh, body)
	c.rect(x, y, bw, top, body.lightened(0.22))
	c.rect(x, y + top, bw, 1, body.darkened(0.25))
	c.rect(x + bw - 1, y + top, 1, bh - top, body.darkened(0.18))
	c.rect(x, y + bh - 1, bw, 1, body.darkened(0.35))


func _finish(c: Canvas, sx: int, sy: int, sw: int, sh: int) -> Canvas:
	c.outline()
	c.shadow(sx, sy, sw, sh)
	return c


func _life_support() -> Canvas:
	var c := Canvas.new(32, 32)
	_box(c, 2, 4, 28, 25, 5, M2)
	# Tanks.
	for tx in [4, 10]:
		c.rect(tx, 10, 5, 16, M4)
		c.rect(tx, 10, 1, 16, WHITE)
		c.rect(tx + 4, 10, 1, 16, M3)
		c.rect(tx + 1, 9, 3, 1, M3)
		c.rect(tx, 15, 5, 1, YELLOW if tx == 4 else TEAL)
	# Screen + lights.
	c.rect(17, 11, 11, 7, SCREEN)
	c.line(18, 16, 21, 13, TEAL)
	c.line(21, 13, 24, 15, TEAL)
	c.line(24, 15, 26, 12, TEAL)
	c.px(18, 21, GREEN)
	c.px(20, 21, GREEN)
	c.px(22, 21, YELLOW)
	c.px(24, 21, RED)
	# Pipes.
	c.rect(17, 24, 11, 2, M3)
	c.rect(17, 24, 11, 1, M4)
	c.rect(6, 5, 20, 1, M3)
	return _finish(c, 1, 27, 30, 5)


func _seismometer() -> Canvas:
	var c := Canvas.new(16, 16)
	c.line(3, 14, 6, 9, M3)
	c.line(12, 14, 9, 9, M3)
	c.line(8, 14, 8, 10, M3)
	c.disc(8, 7, 4, YELLOW.darkened(0.15))
	c.disc(8, 6, 3, YELLOW)
	c.rect(6, 6, 4, 1, M0)
	c.px(7, 5, RED)
	c.line(5, 6, 6, 4, M0)
	c.line(9, 4, 11, 7, M0)
	return _finish(c, 2, 13, 12, 3)


func _lab_console() -> Canvas:
	var c := Canvas.new(32, 16)
	_box(c, 1, 5, 30, 10, 4, M3)
	# Microscope.
	c.rect(5, 1, 2, 5, M1)
	c.rect(4, 5, 5, 2, M1)
	c.rect(3, 0, 4, 2, M0)
	# Screen.
	c.rect(13, 0, 10, 6, M0)
	c.rect(14, 1, 8, 4, SCREEN)
	c.rect(15, 2, 3, 1, TEAL)
	c.rect(15, 3, 5, 1, TEAL_DK)
	# Sample vials.
	for vx in [25, 27, 29]:
		c.rect(vx, 3, 1, 3, GLASS)
	c.px(25, 3, GREEN)
	c.px(27, 3, YELLOW)
	c.px(29, 3, RED)
	c.rect(4, 11, 24, 1, M2)
	return _finish(c, 0, 13, 32, 3)


func _airlock_filter() -> Canvas:
	var c := Canvas.new(16, 32)
	_box(c, 1, 3, 14, 27, 3, M2)
	c.rect(3, 8, 10, 14, M1)
	for gy in range(9, 22, 2):
		c.rect(4, gy, 8, 1, M3)
	# Dust stains.
	c.px(5, 11, BROWN)
	c.px(9, 15, BROWN)
	c.px(6, 19, BROWN)
	c.rect(3, 24, 10, 3, SCREEN)
	c.px(4, 25, YELLOW)
	c.rect(6, 25, 6, 1, TEAL)
	return _finish(c, 0, 28, 16, 4)


func _medical() -> Canvas:
	var c := Canvas.new(32, 16)
	# Exam bed.
	_box(c, 1, 5, 20, 9, 4, M4)
	c.rect(2, 5, 6, 3, WHITE)
	c.rect(9, 6, 11, 2, GLASS.darkened(0.2))
	# Analyzer.
	_box(c, 22, 0, 9, 14, 3, M3)
	c.rect(23, 4, 7, 5, SCREEN)
	c.rect(26, 5, 1, 3, RED)
	c.rect(25, 6, 3, 1, RED)
	c.px(24, 11, GREEN)
	c.px(26, 11, GREEN)
	return _finish(c, 0, 13, 32, 3)


func _garden() -> Canvas:
	var c := Canvas.new(32, 32)
	for row in range(2):
		var y := 6 + row * 13
		_box(c, 1, y, 30, 10, 3, BROWN)
		c.rect(2, y + 1, 28, 2, BROWN_DK)
		for k in range(5):
			var px := 4 + k * 6
			c.rect(px, y - 3, 2, 5, GREEN_DK)
			c.rect(px - 1, y - 4, 4, 2, GREEN)
			c.px(px + 2, y - 2, GREEN)
			if (k + row) % 2 == 0:
				c.px(px, y - 4, RED)
	c.rect(0, 2, 32, 1, Color("#f2e6a0"))
	return _finish(c, 1, 29, 30, 3)


func _bed() -> Canvas:
	var c := Canvas.new(16, 32)
	_box(c, 1, 2, 14, 28, 2, M2)
	c.rect(2, 4, 12, 24, Color("#3d5f8a"))
	c.rect(2, 4, 12, 7, WHITE)
	c.rect(3, 5, 10, 4, M4)
	c.rect(2, 11, 12, 1, Color("#2c4568"))
	c.rect(2, 26, 12, 2, Color("#2c4568"))
	return _finish(c, 0, 29, 16, 3)


func _rover() -> Canvas:
	var c := Canvas.new(32, 24)
	_box(c, 3, 6, 26, 10, 3, M4)
	c.rect(5, 2, 8, 5, M3)
	c.rect(6, 3, 6, 2, SCREEN)
	# Spectrometer arm.
	c.rect(24, 3, 2, 4, M2)
	c.rect(22, 1, 7, 2, YELLOW)
	for wx in [4, 11, 19, 25]:
		c.rect(wx, 15, 4, 5, M0)
		c.rect(wx + 1, 16, 2, 3, M1)
	c.rect(14, 9, 6, 2, TEAL)
	return _finish(c, 2, 19, 28, 4)


func _battery_cart() -> Canvas:
	var c := Canvas.new(16, 16)
	_box(c, 1, 5, 14, 8, 2, M2)
	for bx in [3, 9]:
		c.rect(bx, 2, 4, 5, M4)
		c.rect(bx + 1, 1, 2, 1, YELLOW)
		c.rect(bx, 5, 4, 1, GREEN)
	c.rect(2, 12, 3, 3, M0)
	c.rect(11, 12, 3, 3, M0)
	return _finish(c, 1, 13, 14, 3)


func _sensor_mast() -> Canvas:
	var c := Canvas.new(16, 24)
	_box(c, 4, 15, 8, 6, 2, M2)
	c.rect(7, 4, 2, 12, M4)
	c.rect(3, 3, 10, 2, M3)
	c.disc(8, 2, 2, YELLOW)
	c.line(4, 5, 2, 9, YELLOW)
	c.line(11, 5, 13, 9, YELLOW)
	c.px(6, 18, TEAL)
	c.px(9, 18, GREEN)
	return _finish(c, 3, 20, 10, 4)


func _sample_box() -> Canvas:
	var c := Canvas.new(16, 16)
	_box(c, 1, 4, 14, 10, 4, M3)
	c.rect(4, 4, 1, 2, YELLOW)
	c.rect(11, 4, 1, 2, YELLOW)
	for vx in [3, 7, 11]:
		c.rect(vx, 1, 2, 4, M4)
		c.rect(vx, 1, 2, 1, YELLOW.darkened(0.2))
	c.rect(3, 9, 10, 2, M1)
	return _finish(c, 1, 13, 14, 3)


func _repair_kit() -> Canvas:
	var c := Canvas.new(16, 16)
	_box(c, 1, 5, 14, 9, 3, Color("#a3532f"))
	c.rect(4, 3, 8, 3, Color("#d9c99c"))
	c.rect(4, 3, 8, 1, WHITE)
	c.rect(6, 9, 4, 2, M1)
	c.rect(7, 8, 2, 1, M3)
	c.rect(11, 1, 1, 5, M2)
	return _finish(c, 1, 13, 14, 3)


func _solar_array() -> Canvas:
	var c := Canvas.new(48, 32)
	for k in range(2):
		var y := 2 + k * 14
		c.rect(2, y, 44, 10, Color("#24476b"))
		for gx in range(2, 46, 6):
			c.rect(gx, y, 1, 10, Color("#5e8fbf"))
		c.rect(2, y + 5, 44, 1, Color("#5e8fbf"))
		c.rect(2, y, 44, 1, Color("#8ab7e0"))
		c.rect(22, y + 10, 4, 3, M3)
	_box(c, 40, 24, 7, 7, 2, M2)
	c.rect(41, 27, 5, 2, TEAL)
	return _finish(c, 2, 28, 44, 4)


func _antenna() -> Canvas:
	var c := Canvas.new(32, 32)
	_box(c, 11, 22, 10, 7, 2, M2)
	c.rect(15, 14, 2, 9, M3)
	c.disc(16, 10, 9, M4)
	c.disc(16, 10, 7, WHITE)
	c.disc(17, 11, 4, M4)
	c.line(16, 10, 24, 3, M2)
	c.disc(24, 3, 1.5, RED)
	c.px(13, 25, GREEN)
	return _finish(c, 9, 28, 14, 4)


func _table() -> Canvas:
	var c := Canvas.new(32, 16)
	_box(c, 3, 4, 26, 9, 5, Color("#8c7a62"))
	c.rect(8, 5, 4, 2, WHITE)
	c.rect(20, 5, 4, 2, WHITE)
	c.rect(15, 6, 2, 2, GREEN)
	c.rect(4, 13, 2, 2, M1)
	c.rect(26, 13, 2, 2, M1)
	return _finish(c, 2, 13, 28, 3)


func _toilet() -> Canvas:
	var c := Canvas.new(16, 16)
	_box(c, 3, 1, 10, 5, 2, M4)
	c.disc(8, 9, 4, WHITE)
	c.disc(8, 9, 2, GLASS.darkened(0.2))
	c.rect(6, 12, 4, 2, M4)
	return _finish(c, 2, 13, 12, 3)


func _crate() -> Canvas:
	var c := Canvas.new(16, 16)
	_box(c, 1, 3, 14, 11, 4, Color("#7a8a5a"))
	c.rect(1, 9, 14, 1, Color("#56633e"))
	c.rect(6, 3, 4, 2, YELLOW)
	return _finish(c, 1, 13, 14, 3)


func _plant() -> Canvas:
	var c := Canvas.new(16, 16)
	_box(c, 4, 9, 8, 5, 2, M3)
	c.rect(7, 3, 2, 7, GREEN_DK)
	c.rect(4, 3, 4, 3, GREEN)
	c.rect(8, 1, 4, 3, GREEN)
	c.rect(9, 5, 3, 2, GREEN)
	return _finish(c, 3, 13, 10, 3)


func _locker() -> Canvas:
	var c := Canvas.new(16, 32)
	_box(c, 1, 4, 14, 26, 3, M2)
	c.rect(7, 7, 1, 22, M1)
	c.rect(3, 9, 3, 1, M1)
	c.rect(9, 9, 3, 1, M1)
	c.px(5, 18, YELLOW)
	c.px(9, 18, YELLOW)
	return _finish(c, 0, 29, 16, 3)
