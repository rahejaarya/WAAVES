extends CanvasLayer

# Day / Time Slot / Choice task system.
# Every time slot offers up to three choices, referred to as Day.Slot.Choice
# (for example 1.1.3). Picking a choice on the task board pins it; the player then
# walks to that choice's machine and presses E to carry it out. Points marked
# "next day" are credited when the next day starts (after sleeping).

const LAST_DAY := 5
const POWER_CATEGORY := "power"
# Day.Slot.Choice codes (like 1.1.3) are for debugging only. Turn this on to see them.
const SHOW_DEBUG_CODES := false

var player: CharacterBody2D
var day := 1
var slot := 1
var score := 0
var pending_score := 0
var power_picks := 0
var filters_inspected := false
var filters_cleaned := false
var seismometer_bumped := false
var used_leak_detector := false
var leak_found := false
var leak_fixed := false
var shelter_taken := false
var water_offered := false
var water_checked := false
var awaiting_bed := false
var slot_options: Array[Dictionary] = []
var completed_ids: Array[String] = []
var choice_log: Array[String] = []
var current_action: Dictionary = {}
var pinned_action_id := ""
var active := false
var ended := false
var final_status := ""
var mistakes := 0
var progress := 0
var target_progress := 0
var target_cells: Array[int] = []
var dial_target := 0
var math_target := 0
var expected_sequence: Array[int] = []
var selected_sequence: Array[int] = []
var random_source := RandomNumberGenerator.new()

@onready var status_label: Label = %StatusLabel
@onready var score_label: Label = %ScoreLabel
@onready var banner_label: Label = %BannerLabel
@onready var deadline_label: Label = %DeadlineLabel
@onready var event_label: Label = %EventLabel
@onready var resource_label: Label = %ResourceLabel
@onready var choice_list: VBoxContainer = %ChoiceList
@onready var manual_panel: ScrollContainer = %ManualPanel
@onready var manual_text: RichTextLabel = %ManualText
@onready var challenge_panel: VBoxContainer = %ChallengePanel
@onready var challenge_instructions: Label = %ChallengeInstructions
@onready var challenge_progress: Label = %ChallengeProgress
@onready var challenge_area: Control = %ChallengeArea
@onready var modal: PanelContainer = %Modal
@onready var mission_scroll: ScrollContainer = %MissionScroll
@onready var modal_title: Label = %ModalTitle
@onready var board: Control = %Board
@onready var outcome_label: Label = %OutcomeLabel
@onready var begin_button: Button = %BeginButton
@onready var manual_button: Button = %ManualButton
@onready var close_button: Button = %CloseButton
@onready var learn_more: RichTextLabel = %LearnMore


func _ready() -> void:
	random_source.randomize()
	close_button.pressed.connect(_on_close_pressed)
	manual_button.pressed.connect(_toggle_manual)
	begin_button.pressed.connect(_restart_campaign)
	manual_text.text = _manual_text()
	manual_text.meta_clicked.connect(_open_link)
	learn_more.meta_clicked.connect(_open_link)
	_prepare_slot()
	# Start in the habitat so the player sees the world immediately.
	_set_board_open(false)


func _process(_delta: float) -> void:
	if not is_instance_valid(status_label) or not is_instance_valid(player):
		return
	status_label.text = "BEDTIME  /  DAY %d OF %d" % [day, LAST_DAY] if awaiting_bed else "DAY %d OF %d     %s" % [day, LAST_DAY, "MORNING" if slot == 1 else "AFTERNOON"]
	score_label.text = "POINTS  %d     COMING TOMORROW  +%d" % [score, pending_score]
	if ended:
		banner_label.text = "GAME OVER" if final_status.begins_with("GAME OVER") else "YOU MADE IT!"
		return
	if active:
		return
	var pinned := get_pinned_action()
	if not pinned.is_empty():
		banner_label.text = "%sYOUR TASK: %s  •  GO TO %s AND PRESS E" % [_code_prefix(pinned), str(pinned["short"]).to_upper(), _station_name(str(pinned["station"]))]
	elif awaiting_bed:
		banner_label.text = "DONE FOR TODAY  •  FIND A BED AND PRESS E TO SLEEP"
	else:
		var place: String = get_parent().call("_room_title", get_parent().call("_room_id_at_player"))
		banner_label.text = "YOU ARE IN: %s   •   PRESS TAB TO PICK A TASK" % place
	deadline_label.text = _deadline_text()
	var alert_color := Color("#9ce4cf")
	if deadline_label.text.begins_with("CRITICAL"):
		alert_color = Color("#ff817a")
	elif deadline_label.text.begins_with("WARNING"):
		alert_color = Color("#ffd18a")
	deadline_label.add_theme_color_override("font_color", alert_color)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_board()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and bool(board.visible):
			_on_close_pressed()
			get_viewport().set_input_as_handled()


func is_board_open() -> bool:
	return bool(board.visible)


func get_pinned_action() -> Dictionary:
	for action: Dictionary in slot_options:
		if str(action["id"]) == pinned_action_id:
			return action
	return {}


func get_pinned_task_title() -> String:
	var pinned := get_pinned_action()
	return "" if pinned.is_empty() else str(pinned["short"])


func toggle_board() -> void:
	if ended:
		return
	if active:
		_stop_minigame()
		return
	_set_board_open(not bool(board.visible))


# Text for the on-screen hint when the player stands next to a machine.
func station_hint(station_id: String) -> String:
	if ended:
		return ""
	if station_id == "bed":
		return "BED  •  PRESS E TO SLEEP" if awaiting_bed else "BED  •  YOU CAN SLEEP AFTER THE AFTERNOON TASK"
	var here := _station_name(station_id)
	var pinned := get_pinned_action()
	if not pinned.is_empty() and str(pinned["station"]) == station_id:
		return "%s  •  PRESS E TO START YOUR TASK" % here
	if awaiting_bed:
		return "%s  •  DONE FOR TODAY, GO TO BED" % here
	if not pinned.is_empty():
		return "%s  •  YOUR TASK IS AT %s" % [here, _station_name(str(pinned["station"]))]
	return "%s  •  PRESS TAB TO PICK A TASK" % here


func interact_with_station(station_id: String) -> void:
	if ended or active:
		return
	if station_id == "bed":
		if awaiting_bed:
			_sleep()
		return
	if awaiting_bed:
		return
	var pinned := get_pinned_action()
	if pinned.is_empty():
		outcome_label.text = "Pick a task first. Then go to its machine and press E."
		_set_board_open(true)
		return
	if str(pinned["station"]) == station_id:
		_start_action(pinned)


func _set_board_open(open: bool) -> void:
	board.visible = open
	if is_instance_valid(player):
		player.set_process(not open and not ended)
		if open:
			player.stop()
	if is_instance_valid(modal):
		# Whole-pixel offsets so the board always sits on the pixel grid.
		var inset := Vector2i(40, 14) if active else Vector2i(4, 4)
		modal.anchor_left = 0.0
		modal.anchor_top = 0.0
		modal.anchor_right = 1.0
		modal.anchor_bottom = 1.0
		modal.offset_left = inset.x
		modal.offset_top = inset.y
		modal.offset_right = -inset.x
		modal.offset_bottom = -inset.y
	if open:
		_refresh_board()


func _on_close_pressed() -> void:
	if ended:
		return
	if active:
		_stop_minigame()
		return
	_set_board_open(false)


# Leaves a minigame without finishing it. The task stays picked, so the player can
# walk back to the machine and press E to try again.
func _stop_minigame() -> void:
	minigame_token += 1
	active = false
	current_action = {}
	for child in challenge_area.get_children():
		child.queue_free()
	outcome_label.text = "Task stopped. Go back to the machine and press E to try again."
	_set_board_open(false)


func _refresh_board() -> void:
	if not is_instance_valid(modal_title):
		return
	modal_title.text = ("%s%s" % [_code_prefix(current_action), str(current_action.get("short", "TASK")).to_upper()]) if active else ("TASKS  /  DAY %d  /  %s" % [day, "MORNING" if slot == 1 else "AFTERNOON"])
	resource_label.text = "POINTS  %d     COMING TOMORROW  +%d" % [score, pending_score]
	event_label.text = "BEDTIME  /  You're done for today! Go to a bed and press E to sleep. Tomorrow is Day %d." % (day + 1) if awaiting_bed else _event_text()
	event_label.get_parent().visible = not active
	resource_label.get_parent().visible = not active
	choice_list.visible = not manual_panel.visible and not active and not awaiting_bed
	outcome_label.visible = not active and outcome_label.text != ""
	challenge_panel.visible = active
	manual_button.visible = not active and not ended
	# On the game-over / win screen the board must stay open (Play Again is the way out).
	close_button.visible = not ended
	close_button.text = "Stop task [Tab]" if active else "Close [Tab]"
	if ended:
		choice_list.visible = false
		manual_panel.visible = false
		challenge_panel.visible = false
		manual_button.visible = false
		begin_button.visible = true
		begin_button.text = "PLAY AGAIN"
		outcome_label.text = final_status
		outcome_label.visible = true
		return
	begin_button.visible = false
	if choice_list.visible:
		_rebuild_choices()


func _rebuild_choices() -> void:
	for child in choice_list.get_children():
		child.queue_free()
	for index in range(slot_options.size()):
		var action: Dictionary = slot_options[index]
		var chosen := str(action["id"]) == pinned_action_id
		var button := Button.new()
		button.text = "%s%s%s\n%s\n> %s" % [
			"YOUR PICK  ▸  " if chosen else "",
			_code_prefix(action),
			str(action["short"]).to_upper(),
			str(action["title"]),
			_station_name(str(action["station"])),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_color_override("font_color", Color("#edf4f1"))
		button.add_theme_color_override("font_hover_color", Color("#ffffff"))
		button.add_theme_color_override("font_pressed_color", Color("#baf9f3"))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var border := Color("#e7c47d") if chosen else Color("#48656c")
		button.add_theme_stylebox_override("normal", _panel_style(Color("#2c3d33") if chosen else Color("#20363e"), border))
		button.add_theme_stylebox_override("hover", _panel_style(Color("#29474e"), Color("#71ded3")))
		button.pressed.connect(_choose_action.bind(index))
		choice_list.add_child(button)


func _toggle_manual() -> void:
	manual_panel.visible = not manual_panel.visible
	manual_button.text = "Back to tasks" if manual_panel.visible else "How to Play"
	_refresh_board()


func _choose_action(index: int) -> void:
	if ended or active or awaiting_bed or index < 0 or index >= slot_options.size():
		return
	var action: Dictionary = slot_options[index]
	pinned_action_id = str(action["id"])
	outcome_label.text = "Good pick! Walk to %s and press E to do it." % _station_name(str(action["station"]))
	_set_board_open(false)


func _start_action(action: Dictionary) -> void:
	current_action = action
	learn_more.text = "\nLearn more from NASA: " + _link_bbcode(str(TASK_LINKS.get(str(action["id"]), "environment")))
	dust_left = 0
	active = true
	outcome_label.text = ""
	mistakes = 0
	progress = 0
	selected_sequence.clear()
	challenge_area.show()
	_set_board_open(true)
	_start_minigame()
	_refresh_board()


# ---------------------------------------------------------------- minigames
# Every task has its own themed puzzle. The kinds (the "game" column in ACTIONS):
#   readings - a grid of readings; use the science rule to find the right ones
#   order    - shuffled steps; work out the right order from the clues
#   question - a short word problem or chart about the task; type the answer
#   memory   - remember a color code, then enter it
#   dust     - find the squares that match the moon-dust color

const MAX_MISSES := 3

var reading_misses := 0
var minigame_token := 0  # bumps every time a minigame starts/stops (cancels old timers)


func _start_minigame() -> void:
	minigame_token += 1
	for child in challenge_area.get_children():
		child.queue_free()
	target_cells.clear()
	selected_sequence.clear()
	reading_misses = 0
	match str(current_action["game"]):
		"dust":
			challenge_instructions.text = str(current_action["challenge"])
			_start_dust_game()
		"readings":
			_start_readings()
		"order":
			_start_order()
		"memory":
			_start_memory()
		_:
			_start_question()


func _clear_area() -> void:
	for child in challenge_area.get_children():
		child.queue_free()


func _distinct(count: int, low: int, high: int) -> Array[int]:
	var pool: Array[int] = []
	for value in range(low, high + 1):
		pool.append(value)
	pool.shuffle()
	return pool.slice(0, count)


func _pick(options: Array) -> Variant:
	return options[random_source.randi_range(0, options.size() - 1)]


# ------------------------------------------------------------ readings grid

# Returns {"text": instructions, "labels": [...], "targets": [indices]}.
func _readings_data(id: String) -> Dictionary:
	var labels: Array[String] = []
	var targets: Array[int] = []
	var text := ""
	match id:
		"neutron_survey":
			text = "Water ice soaks up neutrons, so spots with hidden ice give LOW neutron counts. Find the 3 lowest counts."
			var values := _distinct(12, 10, 99)
			labels.assign(values.map(func(v: int) -> String: return str(v)))
			targets = _extreme_indices(values, 3, false)
		"heat_probe":
			text = "Heat leaks up from inside the Moon. Find the 3 WARMEST spots to put the probe."
			var values := _distinct(12, -30, 25)
			labels.assign(values.map(func(v: int) -> String: return "%dC" % v))
			targets = _extreme_indices(values, 3, true)
		"leak_detector":
			text = "Air hisses loudest right next to the hole. Find the 3 LOUDEST readings."
			var values := _distinct(12, 20, 95)
			labels.assign(values.map(func(v: int) -> String: return "%d dB" % v))
			targets = _extreme_indices(values, 3, true)
		"thermal_check":
			text = "Where heat escapes, the outside wall gets warmer. Find the 3 WARMEST spots on the wall."
			var values := _distinct(12, -60, -5)
			labels.assign(values.map(func(v: int) -> String: return "%dC" % v))
			targets = _extreme_indices(values, 3, true)
		"collect_rock":
			text = "Rocks with lots of iron are the most useful. Pick the 3 rocks with the MOST iron."
			var values := _distinct(12, 2, 30)
			labels.assign(values.map(func(v: int) -> String: return "%d%% Fe" % v))
			targets = _extreme_indices(values, 3, true)
		"soil_composition":
			var mineral: String = _pick(["ILMENITE", "OLIVINE", "PYROXENE"])
			var facts := {"ILMENITE": "has oxygen and titanium in it", "OLIVINE": "is a green crystal from deep inside the Moon", "PYROXENE": "formed when old lava cooled"}
			text = "Find the 3 bits of %s in the dirt (it %s). Look carefully: the names are similar!" % [mineral, facts[mineral]]
			var decoys: Array = ["BASALT", "GLASS", "DUST", "IRON", "OLIVINE", "PYROXENE", "ILMENITE", "FELDSPAR"]
			decoys.erase(mineral)
			for i in range(12):
				labels.append(mineral if i < 3 else str(_pick(decoys)))
			targets.assign([0, 1, 2])
		"rover_battery":
			text = "A healthy battery cell reads 12, 13 or 14 volts. Find the 3 BAD cells."
			for i in range(12):
				labels.append("%dV" % (int(_pick([5, 7, 9, 10, 11, 15, 16])) if i < 3 else random_source.randi_range(12, 14)))
			targets.assign([0, 1, 2])
		"weather_station":
			text = "The Moon has no air, so there is no wind, rain or clouds there! Turn on the 3 sensors that WILL work on the Moon."
			var good: Array = ["TEMP", "SUNLIGHT", "DUST", "QUAKE", "RADIATION"]
			good.shuffle()
			var bad: Array = ["WIND", "RAIN", "CLOUDS", "SNOW", "FOG", "THUNDER", "HUMIDITY"]
			bad.shuffle()
			labels.assign(good.slice(0, 3) + bad.slice(0, 6))
			targets.assign([0, 1, 2])
		"water_storage":
			text = "Each gauge shows yesterday → today. A tank is leaking if its water went DOWN. Find the 3 leaking tanks."
			for i in range(9):
				var before := random_source.randi_range(5, 9) * 10
				var after := before - random_source.randi_range(2, 9) if i < 3 else before + (random_source.randi_range(1, 5) if i % 3 == 0 else 0)
				labels.append("%d→%d" % [before, after])
			targets.assign([0, 1, 2])
	# Shuffle positions so targets aren't always first.
	var order: Array[int] = []
	for i in range(labels.size()):
		order.append(i)
	order.shuffle()
	var shuffled: Array[String] = []
	var new_targets: Array[int] = []
	for new_index in range(order.size()):
		shuffled.append(labels[order[new_index]])
		if targets.has(order[new_index]):
			new_targets.append(new_index)
	return {"text": text, "labels": shuffled, "targets": new_targets}


func _extreme_indices(values: Array[int], count: int, highest: bool) -> Array[int]:
	var indices: Array[int] = []
	for i in range(values.size()):
		indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool: return values[a] > values[b] if highest else values[a] < values[b])
	return indices.slice(0, count)


func _start_readings(note := "") -> void:
	_clear_area()
	var data := _readings_data(str(current_action["id"]))
	challenge_instructions.text = data["text"]
	target_cells.assign(data["targets"])
	reading_misses = 0
	var labels: Array = data["labels"]
	var grid := GridContainer.new()
	grid.columns = 4 if labels.size() > 9 else 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	challenge_area.add_child(grid)
	for index in range(labels.size()):
		var tile := Button.new()
		tile.text = str(labels[index])
		tile.custom_minimum_size = Vector2(54, 14)
		tile.focus_mode = Control.FOCUS_NONE
		tile.pressed.connect(_press_reading.bind(index, tile))
		grid.add_child(tile)
	challenge_progress.text = note if note != "" else "Left to find: %d" % target_cells.size()


func _press_reading(index: int, tile: Button) -> void:
	if target_cells.has(index):
		target_cells.erase(index)
		tile.disabled = true
		tile.add_theme_stylebox_override("disabled", _panel_style(Color("#2c4a33"), Color("#6cc66a")))
		challenge_progress.text = "Good! Left to find: %d" % target_cells.size()
		if target_cells.is_empty():
			_finish_minigame()
		return
	mistakes += 1
	reading_misses += 1
	tile.add_theme_stylebox_override("normal", _panel_style(Color("#5a2626"), Color("#e0584f")))
	if reading_misses >= MAX_MISSES:
		_start_readings("Too many misses! New readings came in. Try again.")
	else:
		challenge_progress.text = "Not that one. Misses: %d / %d" % [reading_misses, MAX_MISSES]


# ------------------------------------------------------------ order puzzles

const ORDER_PUZZLES := {
	"water_recovery": {
		"steps": ["Collect used water", "Filter out dirt", "Clean it with heat", "Pump it to the tank"],
		"clues": ["Pumping to the tank is the very last step.", "Filtering happens right after collecting.", "Heat-cleaning comes after filtering."],
	},
	"oxygen_recycle": {
		"steps": ["Fill with water", "Turn on power", "Split the water", "Send oxygen out"],
		"clues": ["Filling with water comes first.", "You can't split water without power.", "Oxygen is sent into the base last."],
	},
	"backup_oxygen": {
		"steps": ["Check tank pressure", "Open the valve", "Listen for the hiss", "Close the valve"],
		"clues": ["Never open a tank before checking its pressure.", "You can only hear the hiss while the valve is open.", "Closing the valve is the last step."],
	},
	"flare_medical": {
		"steps": ["Wash your hands", "Check your heartbeat", "Take your temperature", "Write it in the log"],
		"clues": ["Doctors always wash their hands first.", "Write in the log after all the checks.", "Check your heartbeat before your temperature."],
	},
	"fix_leak": {
		"steps": ["Clean around the hole", "Put on the patch", "Press it flat", "Test the air pressure"],
		"clues": ["A patch won't stick to a dirty wall.", "Press the patch flat right after putting it on.", "Only test the air pressure once the patch is done."],
	},
	"quake_shelter": {
		"steps": ["Turn off the heater", "Move away from shelves", "Sit down", "Buckle in"],
		"clues": ["Turn off the heater before anything else.", "Get away from shelves before you sit down.", "Buckle in once you're sitting."],
	},
}


func _start_order() -> void:
	_clear_area()
	var id := str(current_action["id"])
	var steps: Array[String] = []
	var clues: Array = []
	if id == "flare_shelter":
		# Shelter door: lock the bolts from smallest number to largest.
		var numbers := _distinct(5, 1, 49)
		numbers.sort()
		steps.assign(numbers.map(func(v: int) -> String: return "Bolt %d" % v))
		clues = ["Close the heavy shelter door: lock the bolts from the SMALLEST number to the LARGEST."]
	else:
		var puzzle: Dictionary = ORDER_PUZZLES[id]
		steps.assign(puzzle["steps"])
		clues = puzzle["clues"].duplicate()
		clues.shuffle()
	expected_sequence.clear()
	for i in range(steps.size()):
		expected_sequence.append(i)
	selected_sequence.clear()
	challenge_instructions.text = "Do the steps in the right order. Clues:\n• " + "\n• ".join(clues)
	var buttons: Container = HFlowContainer.new() if id == "flare_shelter" else VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	buttons.add_theme_constant_override("h_separation", 2)
	buttons.add_theme_constant_override("v_separation", 2)
	challenge_area.add_child(buttons)
	var shown: Array[int] = expected_sequence.duplicate()
	shown.shuffle()
	for step_index in shown:
		var button := Button.new()
		button.text = steps[step_index]
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_press_order.bind(step_index, button, buttons))
		buttons.add_child(button)
	challenge_progress.text = "Steps done: 0 / %d" % steps.size()


func _press_order(step_index: int, button: Button, buttons: Control) -> void:
	var next_index := selected_sequence.size()
	if step_index == expected_sequence[next_index]:
		selected_sequence.append(step_index)
		button.disabled = true
		challenge_progress.text = "Steps done: %d / %d" % [selected_sequence.size(), expected_sequence.size()]
		if selected_sequence.size() == expected_sequence.size():
			_finish_minigame()
		return
	mistakes += 1
	selected_sequence.clear()
	for child in buttons.get_children():
		(child as Button).disabled = false
	challenge_progress.text = "Wrong order! Read the clues again and start over. Misses: %d" % mistakes


# ------------------------------------------------------------ memory code

const MEMORY_COLORS: Array[String] = ["RED", "BLUE", "GREEN", "GOLD"]
const MEMORY_TINTS: Array[Color] = [Color("#ff7777"), Color("#72bfff"), Color("#77df9a"), Color("#ffd56a")]


func _start_memory() -> void:
	_clear_area()
	expected_sequence.clear()
	for _step in range(5):
		expected_sequence.append(random_source.randi_range(0, MEMORY_COLORS.size() - 1))
	challenge_instructions.text = "The magnetometer needs its 5-color power-on code. Watch the code, then enter it from memory!"
	var code := Label.new()
	code.name = "Code"
	challenge_area.add_child(code)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	challenge_area.add_child(row)
	for color_index in range(MEMORY_COLORS.size()):
		var key := Button.new()
		key.text = MEMORY_COLORS[color_index]
		key.focus_mode = Control.FOCUS_NONE
		key.custom_minimum_size = Vector2(44, 14)
		key.add_theme_color_override("font_color", MEMORY_TINTS[color_index])
		key.pressed.connect(_press_memory.bind(color_index))
		row.add_child(key)
	_show_memory_code()


func _show_memory_code() -> void:
	selected_sequence.clear()
	var code: Label = challenge_area.get_node_or_null("Code")
	if code == null:
		return
	code.text = "CODE:  " + "  ".join(expected_sequence.map(func(v: int) -> String: return MEMORY_COLORS[v]))
	code.add_theme_color_override("font_color", Color("#ffd35c"))
	challenge_progress.text = "Memorize it! It hides in 4 seconds."
	var token := minigame_token
	await get_tree().create_timer(4.0).timeout
	if token != minigame_token or not active or not is_instance_valid(code):
		return
	code.text = "CODE:  ?  ?  ?  ?  ?"
	challenge_progress.text = "Now enter the code. Colors done: 0 / 5"


func _press_memory(color_index: int) -> void:
	var code: Label = challenge_area.get_node_or_null("Code")
	if code != null and not code.text.contains("?"):
		return  # still showing the code
	var next_index := selected_sequence.size()
	if expected_sequence[next_index] == color_index:
		selected_sequence.append(color_index)
		challenge_progress.text = "Colors done: %d / 5" % selected_sequence.size()
		if selected_sequence.size() == expected_sequence.size():
			_finish_minigame()
		return
	mistakes += 1
	challenge_progress.text = "Wrong color! Watch the code again. Misses: %d" % mistakes
	_show_memory_code()


# ------------------------------------------------------- questions / charts

func _question_data(id: String) -> Array:
	match id:
		"seismometer_bump", "rerun_seismometer", "quake_seismometer":
			var tiny := random_source.randi_range(2, 9) * 5
			var deep := tiny + random_source.randi_range(2, 6) * 5
			var strong := deep + random_source.randi_range(2, 6) * 5
			var chart := "SENSITIVITY CHART\n• Strong shallow moonquake: %d\n• Deep moonquake: %d\n• Tiny rumble: %d" % [strong, deep, tiny]
			if id == "quake_seismometer":
				return ["The base is shaking hard: this is a strong shallow moonquake! Set the dial to the right number from the chart.\n" + chart, strong]
			return ["Most moonquakes start deep inside the Moon. Set the seismometer to listen for a DEEP moonquake.\n" + chart, deep]
		"seismo_leak":
			var minutes := _distinct(4, 5, 55)
			var sizes := [random_source.randi_range(3, 9), random_source.randi_range(3, 9), random_source.randi_range(60, 95), random_source.randi_range(3, 9)]
			var lines := []
			for i in range(4):
				lines.append("• 3:%02d  spike size %d" % [minutes[i], sizes[i]])
			return ["The space rock hit made the BIGGEST spike last night. How many minutes after 3:00 did it hit?\n" + "\n".join(lines), minutes[2]]
		"inspect_power":
			var made := random_source.randi_range(5, 9) * 10
			var heater := random_source.randi_range(3, 5) * 10
			var lights := random_source.randi_range(1, 2) * 10
			var lab := made - heater - lights + random_source.randi_range(1, 4) * 5
			return ["The solar panels make %d power. The heater uses %d, the lights use %d and the lab uses %d. How much MORE power is being used than made?" % [made, heater, lights, lab], heater + lights + lab - made]
		"flare_monitor":
			var outside := random_source.randi_range(3, 9) * 100
			return ["The shelter's thick walls block 9 out of every 10 parts of radiation. The meter outside reads %d. What should the meter INSIDE read?" % outside, outside / 10]
		"radiation_sensor":
			var normal := random_source.randi_range(1, 4) * 10
			var danger := normal + random_source.randi_range(2, 6) * 20
			return ["Normal radiation here is %d. Dangerous is %d. Set the warning alarm exactly HALFWAY between them." % [normal, danger], (normal + danger) / 2]
		"solar_calibration", "flare_power":
			if random_source.randi_range(0, 1) == 0:
				var sun := random_source.randi_range(4, 8) * 10
				var panel := random_source.randi_range(1, 3) * 10
				return ["Solar panels work best facing the Sun. The Sun is %d degrees above the ground and the panel is tilted %d degrees. How many more degrees should you tilt it?" % [sun, panel], sun - panel]
			var panels := random_source.randi_range(3, 6)
			var each := random_source.randi_range(4, 9)
			return ["Each clean solar panel makes %d power. The base has %d panels. How much power do they make all together?" % [each, panels], each * panels]
		"antenna_check":
			var question := _antenna_problem()
			return [question, math_target]
	return ["%s\nHow many steps is that? (1)" % str(current_action["title"]), 1]


func _start_question() -> void:
	_clear_area()
	var data := _question_data(str(current_action["id"]))
	challenge_instructions.text = str(data[0])
	math_target = int(data[1])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	challenge_area.add_child(row)
	var answer := SpinBox.new()
	answer.min_value = -999
	answer.max_value = 999
	answer.step = 1
	answer.value = 0
	answer.custom_minimum_size.x = 60
	row.add_child(answer)
	var verify := Button.new()
	verify.text = "Check answer"
	verify.pressed.connect(_verify_math.bind(answer))
	row.add_child(verify)
	challenge_progress.text = "Type the answer, then press Check."


func _verify_math(answer: SpinBox) -> void:
	# Read what's typed in the box (the SpinBox value only updates when you press Enter
	# or click away); fall back to the value if the box holds something else.
	var typed := answer.get_line_edit().text.strip_edges()
	var guess := typed.to_int() if typed.is_valid_int() else int(answer.value)
	answer.set_value_no_signal(guess)
	if guess == math_target:
		_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Not quite. Read the problem again and try again. Misses: %d" % mistakes


# Short word problems about the antenna. Sets math_target and returns the question.
func _antenna_problem() -> String:
	match random_source.randi_range(0, 3):
		0:
			var now := random_source.randi_range(30, 60)
			var boost := random_source.randi_range(10, 35)
			math_target = now + boost
			return "The antenna's signal to Earth is at %d%%. Pointing the dish straight at Earth adds %d%% more. What is the signal now (in %%)?" % [now, boost]
		1:
			var need := random_source.randi_range(60, 95)
			var have := random_source.randi_range(25, need - 10)
			math_target = need - have
			return "Mission Control needs a signal strength of %d to hear you clearly. The antenna is only at %d. How much stronger does the signal need to get?" % [need, have]
		2:
			var bolts := random_source.randi_range(2, 5)
			var turns := random_source.randi_range(2, 6)
			math_target = bolts * turns
			return "The antenna dish has %d loose bolts. Each bolt needs %d turns of the wrench to tighten. How many turns is that in all?" % [bolts, turns]
		_:
			var wait := random_source.randi_range(3, 12)
			math_target = 1 + wait + 1
			return "A radio message takes about 1 second to travel from the Moon to Earth. Mission Control waits %d seconds, then answers. The answer takes 1 second to come back. How many seconds after you call do you hear them?" % wait


# ------------------------------------------------------- airlock dust game
# A grid of plain colored squares. Only the ones that exactly match the moon-dust color are
# dusty; the others are look-alike colors. Three misses and the dust shifts around.

const DUST_COLUMNS := 6
const DUST_ROWS := 4
const DUST_TARGETS := 5
const DUST_COLOR := Color("#8b7d68")
const DUST_DECOYS: Array[Color] = [
	Color("#7f8466"),  # olive grey
	Color("#8f7266"),  # rusty brown
	Color("#748190"),  # blue grey
	Color("#9b8c5f"),  # sandy yellow
	Color("#7b7b78"),  # plain grey
	Color("#657f78"),  # teal grey
	Color("#a08672"),  # light tan
]
const CLEAN_COLOR := Color("#c6d1d2")

var dust_left := 0
var dust_misses := 0


func _start_dust_game() -> void:
	_clear_area()
	if dust_left <= 0:
		dust_left = DUST_TARGETS
	dust_misses = 0
	var key := HBoxContainer.new()
	key.add_theme_constant_override("separation", 3)
	var key_label := Label.new()
	key_label.text = "Dust looks like this:"
	key.add_child(key_label)
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.add_theme_stylebox_override("panel", _dust_style(DUST_COLOR, Color("#14181c")))
	key.add_child(swatch)
	challenge_area.add_child(key)
	var grid := GridContainer.new()
	grid.columns = DUST_COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	challenge_area.add_child(grid)
	var cells: Array[int] = []
	for i in range(DUST_COLUMNS * DUST_ROWS):
		cells.append(i)
	cells.shuffle()
	var dusty := cells.slice(0, dust_left)
	for i in range(DUST_COLUMNS * DUST_ROWS):
		var is_dust := dusty.has(i)
		var fill := DUST_COLOR if is_dust else DUST_DECOYS[random_source.randi_range(0, DUST_DECOYS.size() - 1)]
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(16, 16)
		tile.focus_mode = Control.FOCUS_NONE
		tile.add_theme_stylebox_override("normal", _dust_style(fill, Color("#14181c")))
		tile.add_theme_stylebox_override("hover", _dust_style(fill, Color("#ffffff")))
		tile.add_theme_stylebox_override("pressed", _dust_style(fill.darkened(0.2), Color("#ffffff")))
		tile.add_theme_stylebox_override("disabled", _dust_style(CLEAN_COLOR, Color("#48656c")))
		tile.pressed.connect(_press_dust.bind(is_dust, tile))
		grid.add_child(tile)
	challenge_progress.text = "Dusty squares left: %d" % dust_left


func _press_dust(is_dust: bool, tile: Button) -> void:
	if is_dust:
		tile.disabled = true
		dust_left -= 1
		challenge_progress.text = "Dusty squares left: %d" % dust_left
		if dust_left <= 0:
			_finish_minigame()
		return
	mistakes += 1
	dust_misses += 1
	tile.add_theme_stylebox_override("normal", _dust_style(Color("#e0584f"), Color("#14181c")))
	if dust_misses >= MAX_MISSES:
		_start_dust_game()
		challenge_progress.text = "Too many misses! The dust moved around. Left: %d" % dust_left
	else:
		challenge_progress.text = "That's not dust. Misses: %d / %d   Left: %d" % [dust_misses, MAX_MISSES, dust_left]


func _dust_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	return style


# ------------------------------------------------------------ task results

func _finish_minigame() -> void:
	var action := current_action
	active = false
	pinned_action_id = ""
	current_action = {}
	complete_action(action)


# Applies a finished choice: flags, points, deaths, then moves the clock on.
# Kept separate from the minigame so it can be driven directly in tests.
func complete_action(action: Dictionary) -> void:
	var action_id := str(action["id"])
	completed_ids.append(action_id)
	if str(action.get("category", "")) == POWER_CATEGORY:
		power_picks += 1
	var points := int(action["points"])
	var when := str(action["when"])
	choice_log.append("%sDay %d %s: %s  —  %s" % [_code_prefix(action), day, "morning" if slot == 1 else "afternoon", str(action["short"]), _points_text(points, when)])
	if points != 0:
		if when == "next":
			pending_score += points
		else:
			score += points
	match action_id:
		"inspect_filters":
			filters_inspected = true
		"clean_filters":
			filters_cleaned = true
		"seismometer_bump":
			seismometer_bumped = true
		"leak_detector":
			leak_found = true
			used_leak_detector = true
		"seismo_leak":
			leak_found = true
		"fix_leak":
			leak_fixed = true
		"water_storage":
			water_checked = true
		"flare_shelter":
			shelter_taken = true
		"flare_power":
			_game_over("You used the solar panels while the solar flare was hitting. The flare's radiation got you.")
			return
	if day == 4 and slot == 2 and not shelter_taken:
		_game_over("You didn't go to the radiation shelter. The solar flare hit while you were out working.")
		return
	outcome_label.text = "%sDone! %s" % [_code_prefix(action), str(action["result"])]
	_advance_after_action(action_id)


func _advance_after_action(action_id: String) -> void:
	if day == 1 and slot == 1 and action_id == "water_recovery":
		outcome_label.text += "  That took a long time, so it used up your whole day."
		_end_work_day()
		return
	if day == 5 and slot == 1 and not leak_fixed:
		_game_over("The hole from the space rock was never fixed. When the moonquake hit, the air rushed out of the base.")
		return
	if day == LAST_DAY and slot == 2:
		_win_campaign()
		return
	if slot == 1:
		slot = 2
		_prepare_slot()
		_refresh_board()
	else:
		_end_work_day()


func _end_work_day() -> void:
	awaiting_bed = true
	slot_options.clear()
	pinned_action_id = ""
	outcome_label.text += "\nYou're done for today! Find a bed and press E to sleep."
	_set_board_open(true)


func _sleep() -> void:
	awaiting_bed = false
	day += 1
	slot = 1
	var wake_notes: Array[String] = []
	if pending_score != 0:
		wake_notes.append("You got +%d points from yesterday's work." % pending_score)
		score += pending_score
		pending_score = 0
	if day == 3 and water_offered and not water_checked:
		score -= 1
		wake_notes.append("Nobody checked the water tanks, so you lost 1 point.")
	if day == 4 and not filters_cleaned:
		_game_over("The moon dust in the air filters was never cleaned. Overnight it got into the air you breathe.")
		return
	outcome_label.text = "Good morning! It's Day %d.  %s" % [day, " ".join(wake_notes)]
	_prepare_slot()
	_set_board_open(true)


# ------------------------------------------------------------- choice lists

func _prepare_slot() -> void:
	pinned_action_id = ""
	slot_options = _build_slot_options()
	for index in range(slot_options.size()):
		slot_options[index]["code"] = "%d.%d.%d" % [day, slot, index + 1]
		if day < 3 and str(slot_options[index]["id"]) == "water_storage":
			water_offered = true


func _build_slot_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	match [day, slot]:
		[1, 1]:
			options = [
				_action("neutron_survey"),
				_action("seismometer_bump"),
				_action("water_recovery"),
			]
			return options  # Day 1 is never padded with random choices.
		[1, 2]:
			options = [
				_action("soil_composition"),
				_action("rerun_seismometer") if seismometer_bumped else _action("heat_probe"),
				_action("magnetometer"),
			]
			return options
		[2, 1]:
			options.append(_action("inspect_filters"))
		[2, 2]:
			if power_picks >= 2:
				options.append(_action("inspect_power"))
		[3, 1]:
			if filters_inspected and not filters_cleaned:
				options.append(_action("clean_filters"))
			options.append(_action("leak_detector"))
		[3, 2]:
			if filters_inspected and not filters_cleaned:
				options.append(_action("clean_filters"))
			if not used_leak_detector:
				options.append(_action("seismo_leak"))
		[4, 1]:
			options = [
				_action("fix_leak") if leak_found else _action("leak_detector"),
				_action("flare_power"),
				_action("flare_shelter"),
			]
			return options
		[4, 2]:
			if shelter_taken:
				options = [_action("flare_medical"), _action("flare_monitor"), _action("flare_filter")]
				return options
			# Not in the shelter: every option is a random task, and any of them is fatal.
		[5, 1]:
			options.append(_action("fix_leak"))
		[5, 2]:
			options.append(_action("quake_seismometer"))
			options.append(_action("quake_shelter"))
	_fill_with_random(options)
	return options


# From Day 2 on, pad the slot to three choices from the daily pool.
func _fill_with_random(options: Array[Dictionary]) -> void:
	var taken: Array[String] = []
	for existing: Dictionary in options:
		taken.append(str(existing["id"]))
	var fresh: Array[String] = []
	var repeats: Array[String] = []
	for id: String in RANDOM_POOL:
		if taken.has(id):
			continue
		if completed_ids.has(id):
			repeats.append(id)
		else:
			fresh.append(id)
	fresh.shuffle()
	repeats.shuffle()
	for id: String in fresh + repeats:
		if options.size() >= 3:
			break
		options.append(_action(id))


const RANDOM_POOL: Array[String] = [
	"oxygen_recycle",
	"rover_battery",
	"radiation_sensor",
	"collect_rock",
	"thermal_check",
	"solar_calibration",
	"backup_oxygen",
	"antenna_check",
	"weather_station",
	"water_storage",
]

# id: [short name, full text, points, "now"/"next", station, minigame, instructions, category, result]
const ACTIONS := {
	# Day 1
	"neutron_survey": ["Scan for hidden ice", "Drive the neutron scanner over the ground to look for hydrogen. Hydrogen can mean there's frozen water hiding underground!", 5, "next", "neutron_station", "readings", "Find the three spots where the scanner beeps.", "", "You found signs of hydrogen in the ground."],
	"seismometer_bump": ["Check the seismometer", "Check the seismometer. It's a tool that feels moonquakes.", 0, "now", "seismometer", "question", "Get the seismometer ready.", "", "Oops! You bumped the seismometer before it finished. It needs to be set up and run again."],
	"water_recovery": ["Fix the water recycler", "Make the water recycler work better by fixing a broken part inside it.", 10, "now", "life_support", "order", "Fix the water recycler.", "", "The water recycler works better now."],
	"soil_composition": ["Study the moon dirt", "Look at moon dirt to find out what it's made of.", 6, "now", "lab_console", "readings", "Find the three shiny bits in the moon dirt.", "", "You found out what the moon dirt is made of."],
	"rerun_seismometer": ["Run the seismometer again", "Set up the seismometer again, and be careful not to bump it this time!", 7, "now", "seismometer", "question", "Set up the seismometer again. Careful!", "", "The seismometer is working and listening for moonquakes."],
	"heat_probe": ["Put in the heat probe", "Put a heat probe into the ground to measure how much heat comes up from inside the Moon.", 5, "now", "field_station", "readings", "Find the three warm spots.", "", "The heat probe is measuring heat from inside the Moon."],
	"magnetometer": ["Turn on the magnetometer", "Send power to the magnetometer so it can measure the Moon's magnetic field.", 5, "now", "lab_console", "memory", "Copy the colors to turn the magnetometer on.", POWER_CATEGORY, "The magnetometer is measuring the Moon's magnetic field."],
	# Day 2
	"inspect_filters": ["Check the air filters", "Look at the air filters in the airlock to find where the moon dust is stuck.", 0, "now", "airlock_filter", "dust", "Find every square that is the same color as the moon dust.", "", "You found where the dust is stuck! You can clean it later."],
	"inspect_power": ["Check the power system", "The base has been using a lot of power. Check the power system.", 10, "now", "life_support", "question", "Turn the power dial to the right number.", "", "You found what was using too much power and fixed it."],
	# Day 3
	"clean_filters": ["Clean the moon dust", "Clean the moon dust out of the air filters.", 0, "now", "airlock_filter", "dust", "Brush away every square that is the same color as the moon dust.", "", "The air filters are clean!"],
	"leak_detector": ["Find the air leak", "Use the leak finder to listen for air escaping from the wall.", 0, "now", "hull_station", "readings", "Find the three spots where you hear hissing.", "", "You found the leak! You can fix it later."],
	"seismo_leak": ["Use the seismometer to find the leak", "The seismometer felt the space rock hit. Use it to figure out where the hole is.", 6, "now", "seismometer", "question", "Line up the seismometer to the time of the hit.", "", "The seismometer showed where the rock hit. You found the leak!"],
	# Day 4
	"fix_leak": ["Fix the hole in the wall", "Patch the hole the space rock made in the wall.", 0, "now", "hull_station", "order", "Turn the wrench to tighten the patch.", "", "The hole is patched. The air isn't leaking anymore!"],
	"flare_power": ["Test the solar panels", "Run a test on the solar panels.", 0, "now", "solar_station", "question", "Solve the math problem to test the solar panels.", POWER_CATEGORY, ""],
	"flare_shelter": ["Go to the radiation shelter", "Go to the radiation shelter, a safe room with thick walls.", 0, "now", "life_support", "order", "Turn the wrench to close the shelter door.", "", "You're safe inside the radiation shelter."],
	"flare_medical": ["Give yourself a checkup", "Do a health checkup on yourself.", 2, "now", "medical", "order", "Do the checkup steps in order.", "", "You're healthy!"],
	"flare_monitor": ["Watch radiation levels", "Keep an eye on how much radiation is outside.", 2, "now", "life_support", "question", "Turn the radiation dial to the right number.", "", "You wrote down the radiation levels."],
	"flare_filter": ["Check the air filter", "Make sure the air filter is working.", 2, "now", "airlock_filter", "dust", "Find the dusty squares on the filter.", "", "The air filter is working fine."],
	# Day 5
	"quake_seismometer": ["Record the moonquake", "Turn on the seismometer to record the moonquake instead of hiding.", 8, "now", "seismometer", "question", "Get the seismometer ready before the shaking gets big!", "", "You recorded the whole moonquake, and you were totally fine!"],
	"quake_shelter": ["Take shelter", "Find a safe spot and wait for the moonquake to stop.", 5, "now", "life_support", "order", "Check the three safety straps.", "", "You stayed safe until the shaking stopped."],
	# Random pool (Day 2 onward)
	"oxygen_recycle": ["Test the oxygen maker", "Test the machine that makes oxygen, so the base always has air to breathe.", 6, "now", "life_support", "order", "Turn the valves in the right order.", "", "The oxygen maker works great."],
	"rover_battery": ["Check the rover battery", "Check the moon rover's battery for loose wires or power problems.", 8, "next", "rover_station", "readings", "Find the three loose wires.", POWER_CATEGORY, "The rover battery is fixed."],
	"radiation_sensor": ["Set up a radiation sensor", "Put a radiation sensor outside to measure how much radiation there is.", 5, "next", "field_station", "question", "Turn the sensor dial to the right number.", "", "The radiation sensor is working."],
	"collect_rock": ["Collect moon rocks", "Pick up moon rocks and check them for useful minerals.", 7, "now", "sample_station", "readings", "Pick the three shiny rocks.", "", "You collected moon rocks and checked them."],
	"thermal_check": ["Check the base's insulation", "Check the base's insulation to make sure heat isn't leaking out into space.", 6, "now", "hull_station", "readings", "Find the three spots where heat is leaking.", "", "You checked the insulation."],
	"solar_calibration": ["Adjust the solar panels", "Adjust the solar panels so they collect more sunlight.", 7, "next", "solar_station", "question", "Solve the math problem to adjust the panels.", POWER_CATEGORY, "The solar panels collect more sunlight now."],
	"backup_oxygen": ["Test the backup oxygen", "Test the backup oxygen tanks to make sure they work in an emergency.", 5, "now", "life_support", "order", "Turn the valves in the right order.", "", "The backup oxygen works."],
	"antenna_check": ["Fix up the antenna", "Check the antenna and make its signal to Mission Control stronger.", 6, "next", "eva_station", "question", "Solve the antenna problem to tune it.", "", "Mission Control can hear you better now."],
	"weather_station": ["Set up a weather station", "Set up a small weather station to measure how hot or cold it is on the Moon.", 8, "now", "field_station", "readings", "Turn on the three weather sensors.", "", "The weather station is working."],
	"water_storage": ["Check the water tanks", "Check the water tanks for leaks and see how much water is left.", 7, "now", "life_support", "readings", "Check the three water tank gauges.", "", "The water tanks don't have any leaks."],
}


func _action(id: String) -> Dictionary:
	var data: Array = ACTIONS[id]
	# Effects (points, deaths, skipped slots) are deliberately not shown on the
	# board; the player only learns them after doing the task.
	return {
		"id": id,
		"short": str(data[0]),
		"title": str(data[1]),
		"points": int(data[2]),
		"when": str(data[3]),
		"station": str(data[4]),
		"game": str(data[5]),
		"challenge": str(data[6]),
		"category": str(data[7]),
		"result": str(data[8]),
		"code": "",
	}


func _code_prefix(action: Dictionary) -> String:
	if not SHOW_DEBUG_CODES or str(action.get("code", "")) == "":
		return ""
	return "[%s]  " % str(action["code"])


func _points_text(points: int, when: String) -> String:
	if points == 0:
		return "no points"
	return "+%d points%s" % [points, " (the next day)" if when == "next" else ""]


func _station_name(station_id: String) -> String:
	var names := {
		"neutron_station": "THE NEUTRON SCANNER (OUTSIDE)",
		"rover_station": "THE ROVER BATTERY (OUTSIDE)",
		"field_station": "THE SCIENCE SENSORS (OUTSIDE)",
		"sample_station": "THE ROCK SAMPLES BOX (OUTSIDE)",
		"hull_station": "THE HULL TOOLS (OUTSIDE)",
		"solar_station": "THE SOLAR PANELS (OUTSIDE)",
		"eva_station": "THE ANTENNA (OUTSIDE)",
		"seismometer": "THE SEISMOMETER (LAB)",
		"lab_console": "THE LAB BENCH",
		"life_support": "LIFE SUPPORT (MAIN ROOM)",
		"airlock_filter": "THE AIR FILTERS (AIRLOCK)",
		"medical": "THE MEDICAL BAY",
		"garden": "THE GARDEN",
		"bed": "A BED",
	}
	return str(names.get(station_id, station_id.replace("_", " ").to_upper()))


# ---------------------------------------------------------------- text

func _event_text() -> String:
	match day:
		1:
			return "DAY 1  /  Welcome to the Moon! Nothing strange is happening today. Press TAB to pick a task, then go do it."
		2:
			return "UH OH!  Moon dust is stuck in the air filters in the airlock!"
		3:
			return "UH OH!  Last night a tiny space rock poked a hole in the wall of the base. Air is slowly leaking out!"
		4:
			return "WARNING!  Mission Control says a solar flare will hit this afternoon. Solar flares send out dangerous radiation."
		_:
			return "WHOA!  The moon base is shaking. It's a moonquake!"


func _deadline_text() -> String:
	# No hints about consequences: only the routine.
	if awaiting_bed:
		return "BEDTIME  /  Go to a bed to start the next day."
	return "PICK ONE TASK IN THE MORNING AND ONE IN THE AFTERNOON, THEN GO TO BED."


# NASA pages used by the game (all from the original Habitat Zero field manual).
const NASA_LINKS := {
	"eclss": ["How astronauts get air and water", "https://www.nasa.gov/reference/environmental-control-and-life-support-systems-eclss/"],
	"prospector": ["Looking for water on the Moon", "https://science.nasa.gov/mission/lunar-prospector/"],
	"dust": ["Why moon dust is a problem", "https://www.nasa.gov/wp-content/uploads/2023/12/ochmo-tb-011-lunar-dust-technical-brief.pdf"],
	"environment": ["What the Moon's surface is like", "https://www.nasa.gov/reference/moonbase-environment/"],
	"radiation": ["How NASA keeps astronauts safe from the Sun", "https://science.nasa.gov/missions/artemis/artemis-2/to-protect-artemis-ii-astronauts-nasa-experts-keep-eyes-on-sun/"],
}

# Which NASA page each task links to.
const TASK_LINKS := {
	"neutron_survey": "prospector", "seismometer_bump": "environment", "water_recovery": "eclss",
	"soil_composition": "environment", "rerun_seismometer": "environment", "heat_probe": "environment",
	"magnetometer": "environment", "inspect_filters": "dust", "inspect_power": "environment",
	"clean_filters": "dust", "leak_detector": "environment", "seismo_leak": "environment",
	"fix_leak": "environment", "flare_power": "radiation", "flare_shelter": "radiation",
	"flare_medical": "radiation", "flare_monitor": "radiation", "flare_filter": "dust",
	"quake_seismometer": "environment", "quake_shelter": "environment", "oxygen_recycle": "eclss",
	"rover_battery": "environment", "radiation_sensor": "radiation", "collect_rock": "environment",
	"thermal_check": "environment", "solar_calibration": "environment", "backup_oxygen": "eclss",
	"antenna_check": "environment", "weather_station": "environment", "water_storage": "eclss",
}


func _link_bbcode(key: String) -> String:
	var link: Array = NASA_LINKS[key]
	return "[url=%s][color=#71ded3]%s[/color][/url]" % [link[1], link[0]]


func _all_links_text() -> String:
	var lines: Array[String] = []
	for key: String in NASA_LINKS:
		lines.append(_link_bbcode(key))
	return "\n".join(lines)


# Opens a [url] link (How to Play page or a task's Learn more link) in the web browser.
func _open_link(meta: Variant) -> void:
	OS.shell_open(str(meta))


func _manual_text() -> String:
	return "[color=#ffd35c]HOW TO PLAY[/color]\n\n[color=#ffd35c]Your mission[/color]\nYou live on a moon base for 5 days. Every day has a morning and an afternoon. Each time, you get to pick ONE task.\n\n[color=#ffd35c]Doing a task[/color]\n1. Press TAB and click the task you want.\n2. Walk to the machine it tells you.\n3. Press E and finish the mini-game.\n\nWhen the afternoon task is done, go to a bed and press E to sleep.\n\n[color=#ffd35c]Points[/color]\nTasks can earn you points. Some points come right away, and some come the next morning. You won't know what a task does until you do it, so choose carefully! At the end, all your points are added up.\n\n[color=#ffd35c]Staying safe[/color]\nSomething surprising happens almost every day. Read the message at the top of the task list. Some choices keep you safe, and some don't!\n\n[color=#ffd35c]Learn more from NASA[/color]\n" + _all_links_text() + "\n\nThis is a made-up story, but the science ideas come from real NASA work."


func _final_tally() -> String:
	var lines := "\n".join(choice_log) if not choice_log.is_empty() else "(You didn't finish any tasks.)"
	return "YOUR POINTS\n%s\n\nTOTAL: %d POINTS" % [lines, score]


func _game_over(reason: String) -> void:
	ended = true
	active = false
	awaiting_bed = false
	pinned_action_id = ""
	final_status = "GAME OVER  (Day %d)\n%s\n\n%s\n\nPress PLAY AGAIN to try again." % [day, reason, _final_tally()]
	_set_board_open(true)


func _win_campaign() -> void:
	ended = true
	active = false
	if pending_score != 0:
		score += pending_score
		pending_score = 0
	final_status = "YOU DID IT!\nYou stayed safe on the Moon for all 5 days. Great job!\n\n%s" % _final_tally()
	_set_board_open(true)


func _restart_campaign() -> void:
	get_tree().reload_current_scene()


func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
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
