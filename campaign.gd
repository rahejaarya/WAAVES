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

var player: CharacterBody3D
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

var status_label: Label
var score_label: Label
var banner_label: Label
var deadline_label: Label
var event_label: Label
var resource_label: Label
var choice_list: VBoxContainer
var manual_panel: ScrollContainer
var manual_text: RichTextLabel
var challenge_panel: VBoxContainer
var challenge_instructions: Label
var challenge_progress: Label
var challenge_area: Control
var modal: PanelContainer
var mission_scroll: ScrollContainer
var modal_title: Label
var board: Control
var outcome_label: Label
var begin_button: Button
var manual_button: Button


func _ready() -> void:
	random_source.randomize()
	_build_interface()
	_prepare_slot()
	# Start in the habitat so the player sees the 3D world immediately.
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
		elif event.keycode == KEY_ESCAPE and bool(board.visible) and not active:
			_set_board_open(false)
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
	if ended or active:
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
		player.set_physics_process(not open and not ended)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or ended else Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(modal):
		if active:
			modal.anchor_left = 0.24
			modal.anchor_top = 0.18
			modal.anchor_right = 0.76
			modal.anchor_bottom = 0.82
		else:
			modal.anchor_left = 0.12
			modal.anchor_top = 0.06
			modal.anchor_right = 0.88
			modal.anchor_bottom = 0.94
	if open:
		_refresh_board()


func _build_interface() -> void:
	var root := Control.new()
	root.name = "Campaign Interface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Label", Color("#e0e9e6"))
	ui_theme.set_color("font_color", "RichTextLabel", Color("#d6e1de"))
	ui_theme.set_color("font_color", "Button", Color("#e8f2ef"))
	ui_theme.set_color("font_hover_color", "Button", Color("#ffffff"))
	ui_theme.set_color("font_pressed_color", "Button", Color("#baf9f3"))
	ui_theme.set_color("font_disabled_color", "Button", Color("#75858a"))
	ui_theme.set_stylebox("normal", "Button", _panel_style(Color("#20363e"), Color("#48656c")))
	ui_theme.set_stylebox("hover", "Button", _panel_style(Color("#29474e"), Color("#71ded3")))
	ui_theme.set_stylebox("pressed", "Button", _panel_style(Color("#14282f"), Color("#83eee2")))
	ui_theme.set_stylebox("focus", "Button", _panel_style(Color("#29474e"), Color("#baf9f3")))
	ui_theme.set_stylebox("disabled", "Button", _panel_style(Color("#1a292e"), Color("#35474c")))
	root.theme = ui_theme
	add_child(root)
	var status_plate := Panel.new()
	status_plate.position = Vector2(12, 108)
	status_plate.size = Vector2(700, 116)
	status_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_plate.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.072, 0.86), Color("#456b70")))
	root.add_child(status_plate)

	status_label = Label.new()
	status_label.position = Vector2(22, 116)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color("#baf9f3"))
	root.add_child(status_label)
	score_label = Label.new()
	score_label.position = Vector2(22, 138)
	score_label.add_theme_font_size_override("font_size", 12)
	score_label.add_theme_color_override("font_color", Color("#9ed9d2"))
	root.add_child(score_label)
	banner_label = Label.new()
	banner_label.position = Vector2(22, 158)
	banner_label.add_theme_font_size_override("font_size", 12)
	banner_label.add_theme_color_override("font_color", Color("#d3e3e4"))
	root.add_child(banner_label)
	deadline_label = Label.new()
	deadline_label.position = Vector2(22, 180)
	deadline_label.custom_minimum_size = Vector2(660, 38)
	deadline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deadline_label.add_theme_font_size_override("font_size", 12)
	deadline_label.add_theme_color_override("font_color", Color("#ffd18a"))
	root.add_child(deadline_label)

	board = Control.new()
	board.name = "Mission Control Board"
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.visible = false
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(board)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.035, 0.88)
	board.add_child(shade)

	modal = PanelContainer.new()
	modal.name = "Mission Console"
	modal.anchor_left = 0.12
	modal.anchor_top = 0.06
	modal.anchor_right = 0.88
	modal.anchor_bottom = 0.94
	modal.add_theme_stylebox_override("panel", _panel_style(Color("#16272e"), Color("#56c6c2")))
	board.add_child(modal)
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 22)
	outer.add_theme_constant_override("margin_right", 22)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 14)
	modal.add_child(outer)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_scroll = ScrollContainer.new()
	mission_scroll.name = "Mission Control Scroll Area"
	mission_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mission_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(mission_scroll)
	mission_scroll.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	modal_title = Label.new()
	modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_title.add_theme_font_size_override("font_size", 23)
	modal_title.add_theme_color_override("font_color", Color("#baf9f3"))
	header.add_child(modal_title)
	var close_button := Button.new()
	close_button.text = "Close  [Tab]"
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	event_label = Label.new()
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.custom_minimum_size.y = 52
	event_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_label.add_theme_color_override("font_color", Color("#e5eeee"))
	var event_card := PanelContainer.new()
	event_card.name = "Mission briefing card"
	event_card.add_theme_stylebox_override("panel", _panel_style(Color("#1c3038"), Color("#527078")))
	event_card.add_child(event_label)
	column.add_child(event_card)
	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 13)
	resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_label.add_theme_color_override("font_color", Color("#87d7d1"))
	var resource_card := PanelContainer.new()
	resource_card.name = "Campaign points"
	resource_card.add_theme_stylebox_override("panel", _panel_style(Color("#14262d"), Color("#354f56")))
	resource_card.add_child(resource_label)
	column.add_child(resource_card)
	outcome_label = Label.new()
	outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome_label.add_theme_color_override("font_color", Color("#ffdb8f"))
	column.add_child(outcome_label)

	choice_list = VBoxContainer.new()
	choice_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choice_list.add_theme_constant_override("separation", 7)
	column.add_child(choice_list)

	manual_panel = ScrollContainer.new()
	manual_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	manual_panel.custom_minimum_size.y = 280
	manual_panel.visible = false
	column.add_child(manual_panel)
	manual_text = RichTextLabel.new()
	manual_text.bbcode_enabled = true
	manual_text.fit_content = true
	manual_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_text.text = _manual_text()
	manual_panel.add_child(manual_text)

	challenge_panel = VBoxContainer.new()
	challenge_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	challenge_panel.visible = false
	column.add_child(challenge_panel)
	challenge_instructions = Label.new()
	challenge_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	challenge_instructions.add_theme_font_size_override("font_size", 17)
	challenge_instructions.add_theme_color_override("font_color", Color("#e6efec"))
	challenge_panel.add_child(challenge_instructions)
	challenge_progress = Label.new()
	challenge_progress.add_theme_color_override("font_color", Color("#87d7d1"))
	challenge_progress.add_theme_font_size_override("font_size", 15)
	challenge_panel.add_child(challenge_progress)
	challenge_area = VBoxContainer.new()
	challenge_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	challenge_panel.add_child(challenge_area)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	manual_button = Button.new()
	manual_button.text = "How to Play"
	manual_button.pressed.connect(_toggle_manual)
	footer.add_child(manual_button)
	begin_button = Button.new()
	begin_button.text = "Play"
	begin_button.visible = false
	begin_button.pressed.connect(_restart_campaign)
	footer.add_child(begin_button)
	_refresh_board()


func _on_close_pressed() -> void:
	if not active:
		_set_board_open(false)


func _refresh_board() -> void:
	if not is_instance_valid(modal_title):
		return
	modal_title.text = ("%s%s" % [_code_prefix(current_action), str(current_action.get("short", "TASK")).to_upper()]) if active else ("TASKS  /  DAY %d  /  %s" % [day, "MORNING" if slot == 1 else "AFTERNOON"])
	resource_label.text = "POINTS  %d     COMING TOMORROW  +%d" % [score, pending_score]
	event_label.text = "BEDTIME  /  You're done for today! Go to a bed and press E to sleep. Tomorrow is Day %d." % (day + 1) if awaiting_bed else _event_text()
	event_label.visible = not active
	resource_label.visible = not active
	choice_list.visible = not manual_panel.visible and not active and not awaiting_bed
	outcome_label.visible = not active
	challenge_panel.visible = active
	manual_button.visible = not active and not ended
	if ended:
		choice_list.visible = false
		manual_panel.visible = false
		challenge_panel.visible = false
		manual_button.visible = false
		begin_button.visible = true
		begin_button.text = "PLAY AGAIN"
		outcome_label.text = final_status
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
		button.text = "%s%s%s\n%s\n\nGO TO  %s" % [
			"YOUR PICK  ▸  " if chosen else "",
			_code_prefix(action),
			str(action["short"]).to_upper(),
			str(action["title"]),
			_station_name(str(action["station"])),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 104)
		button.add_theme_font_size_override("font_size", 14)
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

func _start_minigame() -> void:
	for child in challenge_area.get_children():
		child.queue_free()
	target_cells.clear()
	var kind := str(current_action["game"])
	challenge_instructions.text = str(current_action["challenge"])
	if kind in ["brush", "sample", "scan", "inspect"]:
		var labels := {"brush": ["DUST", "CLEAN"], "sample": ["SHINY", "PLAIN"], "scan": ["BEEP", "QUIET"], "inspect": ["PROBLEM", "OK"]}
		for _target_index in range(3):
			var cell := random_source.randi_range(0, 8)
			while target_cells.has(cell):
				cell = random_source.randi_range(0, 8)
			target_cells.append(cell)
		target_progress = target_cells.size()
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		challenge_area.add_child(grid)
		for cell_index in range(9):
			var is_target: bool = target_cells.has(cell_index)
			var tile := Button.new()
			tile.text = str(labels[kind][0] if is_target else labels[kind][1])
			tile.custom_minimum_size = Vector2(142, 50)
			tile.add_theme_stylebox_override("normal", _panel_style(Color("#8b6a38") if is_target else Color("#34474d"), Color("#e7c47d") if is_target else Color("#587078")))
			tile.pressed.connect(_press_grid_cell.bind(cell_index, tile))
			grid.add_child(tile)
		challenge_progress.text = "Left to find: 3"
	elif kind in ["dial", "math"]:
		var answer := SpinBox.new()
		answer.min_value = 0
		answer.max_value = 200
		answer.step = 1
		answer.custom_minimum_size.x = 180
		if kind == "math":
			var left := random_source.randi_range(12, 48)
			var right := random_source.randi_range(3, 12)
			math_target = left + right
			challenge_instructions.text += "\nSolve this: %d + %d = ?" % [left, right]
		else:
			dial_target = random_source.randi_range(24, 76)
			answer.max_value = 99
			challenge_instructions.text += "\nTurn the dial to %d, then press Check." % dial_target
		var row := HBoxContainer.new()
		challenge_area.add_child(row)
		row.add_child(answer)
		var verify := Button.new()
		verify.text = "Check answer" if kind == "math" else "Check"
		verify.pressed.connect(_verify_math.bind(answer) if kind == "math" else _verify_dial.bind(answer))
		row.add_child(verify)
		challenge_progress.text = "Keep trying until you get it right."
	elif kind == "pattern":
		var colors: Array[String] = ["RED", "BLUE", "GREEN", "GOLD"]
		expected_sequence.clear()
		for _step in range(5):
			expected_sequence.append(random_source.randi_range(0, colors.size() - 1))
		var reference := Label.new()
		var sequence_text := " → ".join(expected_sequence.map(func(value: int) -> String: return colors[value]))
		reference.text = "COPY THESE COLORS\n" + sequence_text
		reference.add_theme_font_size_override("font_size", 20)
		challenge_area.add_child(reference)
		challenge_instructions.text += "\nPress the color buttons in the same order."
		for color_index in range(colors.size()):
			var key := Button.new()
			key.text = colors[color_index]
			key.custom_minimum_size = Vector2(0, 52)
			key.add_theme_color_override("font_color", [Color("#ff7777"), Color("#72bfff"), Color("#77df9a"), Color("#ffd56a")][color_index])
			key.pressed.connect(_press_color.bind(color_index))
			challenge_area.add_child(key)
		challenge_progress.text = "Colors done: 0 / 5"
	elif kind == "bandage":
		expected_sequence = [0, 2, 1, 3]
		target_progress = expected_sequence.size()
		challenge_instructions.text += "\nDo the steps in this order: 1, 3, 2, 4."
		for segment in range(4):
			var wrap := Button.new()
			wrap.text = "Step %d" % (segment + 1)
			wrap.custom_minimum_size = Vector2(0, 44)
			wrap.pressed.connect(_press_sequence.bind(segment, wrap))
			challenge_area.add_child(wrap)
		challenge_progress.text = "Steps done: 0 / 4"
	elif kind == "valves":
		expected_sequence = [0, 1, 2]
		target_progress = expected_sequence.size()
		challenge_instructions.text += "\nTurn them in this order: water, then oxygen, then air out."
		var valve_labels: Array[String] = ["Water", "Oxygen", "Air out"]
		for step in range(valve_labels.size()):
			var valve := Button.new()
			valve.text = valve_labels[step]
			valve.custom_minimum_size = Vector2(0, 44)
			valve.pressed.connect(_press_sequence.bind(step, valve))
			challenge_area.add_child(valve)
		challenge_progress.text = "Steps done: 0 / 3"
	else:
		target_progress = 4
		var turn := Button.new()
		turn.text = "Turn the wrench"
		turn.custom_minimum_size.y = 58
		turn.pressed.connect(_turn_tool.bind(turn))
		challenge_area.add_child(turn)
		challenge_progress.text = "Turns: 0 / 4"


func _press_grid_cell(index: int, tile: Button) -> void:
	if target_cells.has(index):
		target_cells.erase(index)
		progress += 1
		tile.disabled = true
		tile.text = "DONE"
		challenge_progress.text = "Left to find: %d" % target_cells.size()
		if target_cells.is_empty():
			_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Not that one. Try again! Misses: %d" % mistakes


func _verify_dial(dial: SpinBox) -> void:
	if absf(dial.value - float(dial_target)) <= 2.0:
		_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Not quite. Move the dial and try again. Misses: %d" % mistakes


func _verify_math(answer: SpinBox) -> void:
	if int(answer.value) == math_target:
		_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Not quite. Add the numbers again. Misses: %d" % mistakes


func _press_color(index: int) -> void:
	var next_index := selected_sequence.size()
	if next_index < expected_sequence.size() and expected_sequence[next_index] == index:
		selected_sequence.append(index)
		challenge_progress.text = "Colors done: %d / %d" % [selected_sequence.size(), expected_sequence.size()]
		if selected_sequence.size() == expected_sequence.size():
			_finish_minigame()
	else:
		mistakes += 1
		selected_sequence.clear()
		challenge_progress.text = "Oops, wrong color! Start again from the first one. Misses: %d" % mistakes


func _press_sequence(index: int, button: Button) -> void:
	var next_index := selected_sequence.size()
	if next_index < expected_sequence.size() and expected_sequence[next_index] == index:
		selected_sequence.append(index)
		button.disabled = true
		challenge_progress.text = "Steps done: %d / %d" % [selected_sequence.size(), expected_sequence.size()]
		if selected_sequence.size() == expected_sequence.size():
			_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Wrong order. Check the list and try again. Misses: %d" % mistakes


func _turn_tool(button: Button) -> void:
	progress += 1
	button.text = "Turns: %d / 4" % progress
	challenge_progress.text = "Turns: %d / 4" % progress
	if progress >= 4:
		_finish_minigame()


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
	"neutron_survey": ["Scan for hidden ice", "Drive the neutron scanner over the ground to look for hydrogen. Hydrogen can mean there's frozen water hiding underground!", 5, "next", "neutron_station", "scan", "Find the three spots where the scanner beeps.", "", "You found signs of hydrogen in the ground."],
	"seismometer_bump": ["Check the seismometer", "Check the seismometer. It's a tool that feels moonquakes.", 0, "now", "seismometer", "dial", "Get the seismometer ready.", "", "Oops! You bumped the seismometer before it finished. It needs to be set up and run again."],
	"water_recovery": ["Fix the water recycler", "Make the water recycler work better by fixing a broken part inside it.", 10, "now", "life_support", "valves", "Fix the water recycler.", "", "The water recycler works better now."],
	"soil_composition": ["Study the moon dirt", "Look at moon dirt to find out what it's made of.", 6, "now", "lab_console", "sample", "Find the three shiny bits in the moon dirt.", "", "You found out what the moon dirt is made of."],
	"rerun_seismometer": ["Run the seismometer again", "Set up the seismometer again, and be careful not to bump it this time!", 7, "now", "seismometer", "dial", "Set up the seismometer again. Careful!", "", "The seismometer is working and listening for moonquakes."],
	"heat_probe": ["Put in the heat probe", "Put a heat probe into the ground to measure how much heat comes up from inside the Moon.", 5, "now", "field_station", "scan", "Find the three warm spots.", "", "The heat probe is measuring heat from inside the Moon."],
	"magnetometer": ["Turn on the magnetometer", "Send power to the magnetometer so it can measure the Moon's magnetic field.", 5, "now", "lab_console", "pattern", "Copy the colors to turn the magnetometer on.", POWER_CATEGORY, "The magnetometer is measuring the Moon's magnetic field."],
	# Day 2
	"inspect_filters": ["Check the air filters", "Look at the air filters in the airlock to find where the moon dust is stuck.", 0, "now", "airlock_filter", "inspect", "Find the three dusty spots.", "", "You found where the dust is stuck! You can clean it later."],
	"inspect_power": ["Check the power system", "The base has been using a lot of power. Check the power system.", 10, "now", "life_support", "dial", "Turn the power dial to the right number.", "", "You found what was using too much power and fixed it."],
	# Day 3
	"clean_filters": ["Clean the moon dust", "Clean the moon dust out of the air filters.", 0, "now", "airlock_filter", "brush", "Brush away the three piles of dust.", "", "The air filters are clean!"],
	"leak_detector": ["Find the air leak", "Use the leak finder to listen for air escaping from the wall.", 0, "now", "hull_station", "scan", "Find the three spots where you hear hissing.", "", "You found the leak! You can fix it later."],
	"seismo_leak": ["Use the seismometer to find the leak", "The seismometer felt the space rock hit. Use it to figure out where the hole is.", 6, "now", "seismometer", "dial", "Line up the seismometer to the time of the hit.", "", "The seismometer showed where the rock hit. You found the leak!"],
	# Day 4
	"fix_leak": ["Fix the hole in the wall", "Patch the hole the space rock made in the wall.", 0, "now", "hull_station", "wrench", "Turn the wrench to tighten the patch.", "", "The hole is patched. The air isn't leaking anymore!"],
	"flare_power": ["Test the solar panels", "Run a test on the solar panels.", 0, "now", "solar_station", "math", "Solve the math problem to test the solar panels.", POWER_CATEGORY, ""],
	"flare_shelter": ["Go to the radiation shelter", "Go to the radiation shelter, a safe room with thick walls.", 0, "now", "life_support", "wrench", "Turn the wrench to close the shelter door.", "", "You're safe inside the radiation shelter."],
	"flare_medical": ["Give yourself a checkup", "Do a health checkup on yourself.", 2, "now", "medical", "bandage", "Do the checkup steps in order.", "", "You're healthy!"],
	"flare_monitor": ["Watch radiation levels", "Keep an eye on how much radiation is outside.", 2, "now", "life_support", "dial", "Turn the radiation dial to the right number.", "", "You wrote down the radiation levels."],
	"flare_filter": ["Check the air filter", "Make sure the air filter is working.", 2, "now", "airlock_filter", "inspect", "Find the three spots to check.", "", "The air filter is working fine."],
	# Day 5
	"quake_seismometer": ["Record the moonquake", "Turn on the seismometer to record the moonquake instead of hiding.", 8, "now", "seismometer", "dial", "Get the seismometer ready before the shaking gets big!", "", "You recorded the whole moonquake, and you were totally fine!"],
	"quake_shelter": ["Take shelter", "Find a safe spot and wait for the moonquake to stop.", 5, "now", "life_support", "inspect", "Check the three safety straps.", "", "You stayed safe until the shaking stopped."],
	# Random pool (Day 2 onward)
	"oxygen_recycle": ["Test the oxygen maker", "Test the machine that makes oxygen, so the base always has air to breathe.", 6, "now", "life_support", "valves", "Turn the valves in the right order.", "", "The oxygen maker works great."],
	"rover_battery": ["Check the rover battery", "Check the moon rover's battery for loose wires or power problems.", 8, "next", "rover_station", "inspect", "Find the three loose wires.", POWER_CATEGORY, "The rover battery is fixed."],
	"radiation_sensor": ["Set up a radiation sensor", "Put a radiation sensor outside to measure how much radiation there is.", 5, "next", "field_station", "dial", "Turn the sensor dial to the right number.", "", "The radiation sensor is working."],
	"collect_rock": ["Collect moon rocks", "Pick up moon rocks and check them for useful minerals.", 7, "now", "sample_station", "sample", "Pick the three shiny rocks.", "", "You collected moon rocks and checked them."],
	"thermal_check": ["Check the base's insulation", "Check the base's insulation to make sure heat isn't leaking out into space.", 6, "now", "hull_station", "scan", "Find the three spots where heat is leaking.", "", "You checked the insulation."],
	"solar_calibration": ["Adjust the solar panels", "Adjust the solar panels so they collect more sunlight.", 7, "next", "solar_station", "math", "Solve the math problem to adjust the panels.", POWER_CATEGORY, "The solar panels collect more sunlight now."],
	"backup_oxygen": ["Test the backup oxygen", "Test the backup oxygen tanks to make sure they work in an emergency.", 5, "now", "life_support", "valves", "Turn the valves in the right order.", "", "The backup oxygen works."],
	"antenna_check": ["Fix up the antenna", "Check the antenna and make its signal to Mission Control stronger.", 6, "next", "eva_station", "math", "Solve the math problem to tune the antenna.", "", "Mission Control can hear you better now."],
	"weather_station": ["Set up a weather station", "Set up a small weather station to measure how hot or cold it is on the Moon.", 8, "now", "field_station", "inspect", "Turn on the three weather sensors.", "", "The weather station is working."],
	"water_storage": ["Check the water tanks", "Check the water tanks for leaks and see how much water is left.", 7, "now", "life_support", "inspect", "Check the three water tank gauges.", "", "The water tanks don't have any leaks."],
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


func _manual_text() -> String:
	return "[b]HOW TO PLAY[/b]\n\n[b]Your mission[/b]\nYou live on a moon base for 5 days. Every day has a morning and an afternoon. Each time, you get to pick ONE task.\n\n[b]Doing a task[/b]\n1. Press TAB and click the task you want.\n2. Walk to the machine it tells you.\n3. Press E and finish the mini-game.\n\nWhen the afternoon task is done, go to a bed and press E to sleep.\n\n[b]Points[/b]\nTasks can earn you points. Some points come right away, and some come the next morning. You won't know what a task does until you do it, so choose carefully! At the end, all your points are added up.\n\n[b]Staying safe[/b]\nSomething surprising happens almost every day. Read the message at the top of the task list. Some choices keep you safe, and some don't!\n\n[b]Learn more from NASA[/b]\nHow astronauts get air and water: https://www.nasa.gov/reference/environmental-control-and-life-support-systems-eclss/\nLooking for water on the Moon: https://science.nasa.gov/mission/lunar-prospector/\n\nThis is a made-up story, but the science ideas come from real NASA work."


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
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
