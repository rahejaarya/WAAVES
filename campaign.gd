extends CanvasLayer

const MAX_TIME_POINTS := 50
const SLEEP_HOURS := 8

var player: CharacterBody3D
var day := 1
var slot := 1
var time_points := MAX_TIME_POINTS
var research_points := 0
var score := 0
var pending_score := 0
var power_actions_picked := 0
var filters_inspected := false
var filters_cleaned := false
var water_checked := false
var leak_found := false
var leak_fixed := false
var flare_shelter_reached := false
var neutron_survey_done := false
var seismometer_recalibration_due := false
var rock_samples := 0
var dust_samples := 0
var garden_neglect_days := 0
var garden_failure_pending := false
var garden_failure_days := 0
var garden_checked_today := false
var awaiting_bed := false
var slot_options: Array[Dictionary] = []
var completed_slot_actions: Array[String] = []
var action_history: Array[String] = []
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
var skip_button: Button


func _ready() -> void:
	random_source.randomize()
	_build_interface()
	_prepare_slot()
	# Start in the habitat so the player sees the 3D world immediately.
	_set_board_open(false)


func _process(_delta: float) -> void:
	if is_instance_valid(status_label) and is_instance_valid(player):
		status_label.text = "REST PERIOD  /  DAY %d OF 5" % day if awaiting_bed else "DAY %02d OF 5     WORK SHIFT %d OF 2     TIME  %02d / %02d TP" % [day, slot, time_points, MAX_TIME_POINTS]
		score_label.text = "SCORE  %04d     RESEARCH AP  %03d" % [score, research_points]
		if not active and not ended:
			var place: String = get_parent().call("_room_title", get_parent().call("_room_id_at_player"))
			var pinned: String = get_pinned_task_title()
			banner_label.text = ("TASK PINNED: %s  •  FIND THE STATION AND PRESS E" % pinned) if pinned != "" else "CURRENT AREA: %s   •   TAB: OPEN TASKS" % place
			deadline_label.text = "SLEEP WINDOW  /  8 HOURS  /  REPORT TO A BUNK AND PRESS E" if awaiting_bed else _deadline_text()
			var alert_color := Color("#9ce4cf")
			if deadline_label.text.begins_with("CRITICAL"):
				alert_color = Color("#ff817a")
			elif deadline_label.text.begins_with("WARNING"):
				alert_color = Color("#ffd18a")
			deadline_label.add_theme_color_override("font_color", alert_color)
		elif ended:
			banner_label.text = "CREW STATUS: DECEASED" if final_status.begins_with("CREW DECEASED") else "CREW STATUS: SAFE"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_board()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and bool(board.visible):
			_set_board_open(false)
			get_viewport().set_input_as_handled()


func is_board_open() -> bool:
	return bool(board.visible)


func get_pinned_task_title() -> String:
	for action: Dictionary in slot_options:
		if str(action["id"]) == pinned_action_id:
			return str(action["title"])
	return ""


func toggle_board() -> void:
	if ended:
		return
	_set_board_open(not bool(board.visible))


func interact_with_station(station_id: String) -> void:
	if ended or active:
		return
	if station_id == "bed":
		if not awaiting_bed:
			outcome_label.text = "Work time is still active. Complete or skip the current shift; your rest period starts after Shift 2."
			_set_board_open(true)
			_refresh_board()
			return
		_advance_to_next_day()
		return
	# A pinned mission takes priority at its assigned station. If another active
	# mission is at this station, let the player start it without making them
	# return to the task board first.
	if pinned_action_id != "":
		for index in range(slot_options.size()):
			if str(slot_options[index].get("station", "")) == station_id and str(slot_options[index]["id"]) == pinned_action_id:
				pinned_action_id = ""
				_start_action(index)
				return
	for index in range(slot_options.size()):
		if str(slot_options[index].get("station", "")) == station_id:
			pinned_action_id = ""
			_start_action(index)
			return
	_start_bonus_task(station_id)


func _start_bonus_task(station_id: String) -> void:
	var tasks := {
		"garden": ["Hydroponics care", "inspect", "Check the grow lights, nutrient flow, and seedling indicators."],
		"medical": ["Medical scan", "bandage", "Complete the suit-up medical wrap in the marked order."],
		"lab_console": ["Signal calibration", "pattern", "Repeat the instrument's recorded color sequence."],
		"seismometer": ["Seismometer tune-up", "dial", "Tune the calibration dial to the displayed reference."],
		"life_support": ["Life support flow check", "valves", "Verify water, oxygen, and CO₂ lines in order."],
		"airlock_filter": ["Airlock filter clean", "brush", "Clear the highlighted dust deposits from the filter."],
		"neutron_station": ["Neutron reading", "scan", "Select the three stable spectrometer readings."],
		"rover_station": ["Rover battery check", "inspect", "Inspect the three battery and connector indicators."],
		"field_station": ["Surface sensor calibration", "dial", "Set the surface instrument to its reference value."],
		"sample_station": ["Sample collection", "sample", "Select the three marked mineral-bearing areas."],
		"hull_station": ["Hull patch practice", "wrench", "Turn the repair tool through four quarter-turns."],
		"solar_station": ["Solar array output check", "math", "Solve the array output calibration check."],
		"eva_station": ["EVA equipment check", "inspect", "Verify the three suit and tether indicators."]
	}
	if not tasks.has(station_id):
		outcome_label.text = "There is no playable station here. Move closer to habitat equipment and press E."
		return
	var task: Array = tasks[station_id]
	current_action = {
		"id": "bonus_%s" % station_id,
		"code": "BONUS",
		"title": str(task[0]),
		"brief": "A quick station practice task.",
		"tp": 0,
		"points": 10,
		"when": "now",
		"game": str(task[1]),
		"location": "bonus",
		"challenge": str(task[2]),
		"category": "bonus",
		"result": "Practice task complete.",
		"station": station_id,
		"bonus_task": true
	}
	_start_action_data(current_action)


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
	column.custom_minimum_size.y = 0
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
	close_button.pressed.connect(func() -> void: _set_board_open(false))
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
	resource_card.name = "Campaign resources"
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
	manual_button.text = "Field Manual"
	manual_button.pressed.connect(_toggle_manual)
	footer.add_child(manual_button)
	skip_button = Button.new()
	skip_button.text = "Skip this shift (no points)"
	skip_button.pressed.connect(_skip_slot)
	footer.add_child(skip_button)
	begin_button = Button.new()
	begin_button.text = "Start campaign"
	begin_button.visible = false
	begin_button.pressed.connect(_restart_campaign)
	footer.add_child(begin_button)
	_refresh_board()


func _refresh_board() -> void:
	if not is_instance_valid(modal_title):
		return
	modal_title.text = ("%s  /  DAY %d  /  SLOT %d" % [str(current_action.get("title", "STATION TASK")).to_upper(), day, slot]) if active else ("MISSION CONTROL  /  DAY %d  /  SLOT %d" % [day, slot])
	resource_label.text = "TIME POINTS  %d / %d     RESEARCH AP  %d     SCORE  %d     PENDING NEXT DAY  +%d" % [time_points, MAX_TIME_POINTS, research_points, score, pending_score]
	event_label.text = "REST PERIOD  /  Sleep for 8 hours at a crew bunk to begin the next day." if awaiting_bed else _event_text()
	event_label.visible = not active
	resource_label.visible = not active
	choice_list.visible = not manual_panel.visible and not active
	outcome_label.visible = not active
	challenge_panel.visible = active
	skip_button.visible = not manual_panel.visible and not active and not ended and not awaiting_bed
	manual_button.visible = not active and not ended
	if awaiting_bed:
		choice_list.visible = false
	if ended:
		choice_list.visible = false
		manual_panel.visible = false
		challenge_panel.visible = false
		skip_button.visible = false
		manual_button.visible = false
		begin_button.visible = true
		begin_button.text = "RESPAWN / RESTART MISSION"
		outcome_label.text = final_status
		return
	begin_button.visible = false
	if not manual_panel.visible and not active:
		_rebuild_choices()


func _rebuild_choices() -> void:
	for child in choice_list.get_children():
		child.queue_free()
	for index in range(slot_options.size()):
		var action: Dictionary = slot_options[index]
		if completed_slot_actions.has(str(action["id"])):
			continue
		var button := Button.new()
		var reward_text := _reward_summary(action)
		button.text = "%s   /   %s\n%s\n\nDESTINATION  %s     •     COST  %d TP%s" % [str(action["code"]), str(action["title"]).to_upper(), str(action["brief"]), str(action["station"]).replace("_", " ").to_upper(), int(action["tp"]), ("     •     " + reward_text if reward_text != "" else "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 104)
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", Color("#edf4f1"))
		button.add_theme_color_override("font_hover_color", Color("#ffffff"))
		button.add_theme_color_override("font_pressed_color", Color("#baf9f3"))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", _panel_style(Color("#20363e"), Color("#48656c")))
		button.add_theme_stylebox_override("hover", _panel_style(Color("#29474e"), Color("#71ded3")))
		button.add_theme_stylebox_override("disabled", _panel_style(Color("#1a292e"), Color("#35474c")))
		button.pressed.connect(_choose_action.bind(index))
		choice_list.add_child(button)


func _toggle_manual() -> void:
	manual_panel.visible = not manual_panel.visible
	choice_list.visible = not manual_panel.visible
	manual_button.text = "Back to choices" if manual_panel.visible else "Field Manual"
	_refresh_board()


func _choose_action(index: int) -> void:
	if ended or active or index < 0 or index >= slot_options.size():
		return
	var action: Dictionary = slot_options[index]
	pinned_action_id = str(action["id"])
	var station := str(action.get("station", ""))
	outcome_label.text = "TASK PINNED  /  Walk up to the %s station and press E to begin." % station.replace("_", " ").to_upper()
	_set_board_open(false)


func _start_action(index: int) -> void:
	_start_action_data(slot_options[index])


func _start_action_data(action: Dictionary) -> void:
	var best_cost := ceili(float(action["tp"]) * 0.5)
	if time_points < best_cost:
		outcome_label.text = "Not enough TP to start this task. A clean run needs %d TP; daily TP resets to 50 tomorrow." % best_cost
		return
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


func _start_minigame() -> void:
	for child in challenge_area.get_children():
		child.queue_free()
	target_cells.clear()
	var kind := str(current_action["game"])
	challenge_instructions.text = str(current_action["challenge"])
	if kind in ["brush", "sample", "scan", "inspect"]:
		var labels := {"brush": ["DUST", "CLEAR"], "sample": ["MINERAL", "REGOLITH"], "scan": ["H SIGNAL", "BACKGROUND"], "inspect": ["CHECK", "NORMAL"]}
		for target_index in range(3):
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
		challenge_progress.text = "Correct readings remaining: 3"
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
			challenge_instructions.text += "\nSolve the calibration check: %d + %d = ?" % [left, right]
		else:
			dial_target = random_source.randi_range(24, 76)
			answer.max_value = 99
			challenge_instructions.text += "\nSet the instrument dial to %d and verify the calibration." % dial_target
		var row := HBoxContainer.new()
		challenge_area.add_child(row)
		row.add_child(answer)
		var verify := Button.new()
		verify.text = "Submit answer" if kind == "math" else "Verify reading"
		verify.pressed.connect(_verify_math.bind(answer) if kind == "math" else _verify_dial.bind(answer))
		row.add_child(verify)
		challenge_progress.text = "Use the live reading; one incorrect submission costs time."
	elif kind == "dial_legacy":
		dial_target = random_source.randi_range(24, 76)
		challenge_instructions.text += "\nSet the instrument dial to %d and verify the calibration." % dial_target
		var row := HBoxContainer.new()
		challenge_area.add_child(row)
		var dial := SpinBox.new()
		dial.min_value = 0
		dial.max_value = 99
		dial.step = 1
		dial.custom_minimum_size.x = 160
		row.add_child(dial)
		var verify := Button.new()
		verify.text = "Verify reading"
		verify.pressed.connect(_verify_dial.bind(dial))
		row.add_child(verify)
		challenge_progress.text = "Calibration tolerance: ±2 units"
	elif kind == "pattern":
		var colors: Array[String] = ["RED", "BLUE", "GREEN", "GOLD"]
		expected_sequence.clear()
		for _step in range(5):
			expected_sequence.append(random_source.randi_range(0, colors.size() - 1))
		var reference := Label.new()
		var sequence_text := " → ".join(expected_sequence.map(func(value: int) -> String: return colors[value]))
		reference.text = "REFERENCE SIGNAL\n" + sequence_text
		reference.add_theme_font_size_override("font_size", 20)
		challenge_area.add_child(reference)
		challenge_instructions.text += "\nRepeat the recorded color sequence on the four calibration keys."
		for color_index in range(colors.size()):
			var key := Button.new()
			key.text = colors[color_index]
			key.custom_minimum_size = Vector2(0, 52)
			key.add_theme_color_override("font_color", [Color("#ff7777"), Color("#72bfff"), Color("#77df9a"), Color("#ffd56a")][color_index])
			key.pressed.connect(_press_sequence.bind(color_index, key))
			challenge_area.add_child(key)
		challenge_progress.text = "Correct keys: 0 / 5"
	elif kind == "bandage":
		expected_sequence = [0, 2, 1, 3]
		target_progress = expected_sequence.size()
		challenge_instructions.text += "\nWrap in sequence: lower anchor, upper anchor, center, secure end."
		for segment in range(4):
			var wrap := Button.new()
			wrap.text = "Apply bandage strip %d" % (segment + 1)
			wrap.custom_minimum_size = Vector2(0, 44)
			wrap.pressed.connect(_press_sequence.bind(segment, wrap))
			challenge_area.add_child(wrap)
		challenge_progress.text = "Correct wraps: 0 / 4"
	elif kind == "valves":
		expected_sequence = [0, 1, 2]
		target_progress = expected_sequence.size()
		challenge_instructions.text += "\nFollow the documented sequence: water feed → oxygen cell → CO₂ return."
		var labels: Array[String] = ["Water feed", "Oxygen cell", "CO₂ return"]
		for step in range(labels.size()):
			var valve := Button.new()
			valve.text = labels[step]
			valve.custom_minimum_size = Vector2(0, 44)
			valve.pressed.connect(_press_sequence.bind(step, valve))
			challenge_area.add_child(valve)
		challenge_progress.text = "Verified steps: 0 / 3"
	else:
		target_progress = 4
		var turn := Button.new()
		turn.text = "Turn the tool one quarter-turn"
		turn.custom_minimum_size.y = 58
		turn.pressed.connect(_turn_tool.bind(turn))
		challenge_area.add_child(turn)
		challenge_progress.text = "Complete turns: 0 / 4"


func _press_grid_cell(index: int, tile: Button) -> void:
	if target_cells.has(index):
		target_cells.erase(index)
		progress += 1
		tile.disabled = true
		tile.text = "DONE"
		challenge_progress.text = "Correct readings remaining: %d" % target_cells.size()
		if target_cells.is_empty():
			_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "That reading is outside the target signature. Recheck the highlighted instrument data. Errors: %d" % mistakes


func _verify_dial(dial: SpinBox) -> void:
	if absf(dial.value - float(dial_target)) <= 2.0:
		_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Reading outside tolerance. Adjust the dial and retry. Errors: %d" % mistakes


func _verify_math(answer: SpinBox) -> void:
	if int(answer.value) == math_target:
		_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Incorrect calculation. Recheck the two sensor values. Errors: %d" % mistakes


func _press_sequence(index: int, button: Button) -> void:
	var next_index := selected_sequence.size()
	if next_index < expected_sequence.size() and expected_sequence[next_index] == index:
		selected_sequence.append(index)
		button.disabled = true
		challenge_progress.text = "Verified steps: %d / %d" % [selected_sequence.size(), expected_sequence.size()]
		if selected_sequence.size() == expected_sequence.size():
			_finish_minigame()
	else:
		mistakes += 1
		challenge_progress.text = "Sequence mismatch. Follow the manual order and retry. Errors: %d" % mistakes


func _turn_tool(button: Button) -> void:
	progress += 1
	button.text = "Tool rotation %d / 4" % progress
	challenge_progress.text = "Complete turns: %d / 4" % progress
	if progress >= 4:
		_finish_minigame()


func _finish_minigame() -> void:
	if bool(current_action.get("bonus_task", false)):
		var bonus_points := int(current_action.get("points", 10))
		score += bonus_points
		outcome_label.text = "STATION TASK COMPLETE  /  +%d POINTS" % bonus_points
		active = false
		current_action.clear()
		_refresh_board()
		return
	var base_cost := int(current_action["tp"])
	var actual_cost := ceili(float(base_cost) * 0.5) if mistakes == 0 else base_cost
	if time_points < actual_cost:
		outcome_label.text = "Task verified, but the errors used too much time. TP remaining: %d; retry for a clean, faster run." % time_points
		mistakes = 0
		progress = 0
		selected_sequence.clear()
		_start_minigame()
		return
	time_points -= actual_cost
	var action_id := str(current_action["id"])
	_resolve_action(current_action)
	_award_action_points(current_action)
	pinned_action_id = ""
	action_history.append("%s — %s" % [str(current_action["code"]), str(current_action["title"])])
	if str(current_action["category"]) == "power":
		power_actions_picked += 1
	var clean_run := "FAST, CLEAN EXECUTION: 50% TP saved." if mistakes == 0 else "Task passed with rework: full TP charged."
	outcome_label.text = "%s  %d/%d TP used. %s" % [str(current_action["result"]), actual_cost, base_cost, clean_run]
	active = false
	if day == 4 and slot == 1:
		completed_slot_actions.append(action_id)
		if action_id == "flare_power_test":
			_game_over("Power work during the solar particle event left the crew exposed. Mission ended.")
			return
		if action_id == "flare_shelter":
			flare_shelter_reached = true
			_advance_to_slot_two()
			return
		if completed_slot_actions.size() == 1:
			_refresh_board()
			return
		if not flare_shelter_reached:
			_game_over("The solar particle event arrived before the crew reached the shielded core.")
			return
		_advance_to_slot_two()
		return
	_advance_after_action()


func _resolve_action(action: Dictionary) -> void:
	match str(action["id"]):
		"inspect_filters":
			filters_inspected = true
		"clean_filters":
			filters_cleaned = true
		"inspect_and_clean_filters":
			filters_inspected = true
			filters_cleaned = true
		"neutron_survey":
			neutron_survey_done = true
		"seismometer_bump":
			seismometer_recalibration_due = true
		"rerun_seismometer":
			seismometer_recalibration_due = false
		"water_recovery":
			pass
		"water_storage":
			water_checked = true
		"leak_detector", "seismo_leak":
			leak_found = true
		"fix_leak":
			leak_fixed = true
		"verify_patch":
			leak_fixed = true
		"flare_shelter":
			flare_shelter_reached = true
		"collect_rock":
			rock_samples += 1
			research_points += 10
		"collect_dust":
			dust_samples += 1
			research_points += 10
		"analyze_rock":
			rock_samples = maxi(rock_samples - 1, 0)
			research_points += 2
		"analyze_dust":
			dust_samples = maxi(dust_samples - 1, 0)
			research_points += 2
		"garden_check":
			garden_checked_today = true
			garden_neglect_days = 0
			garden_failure_pending = false
			garden_failure_days = 0
		"inspect_power":
			power_actions_picked = 0
		"garden_plant_failure":
			garden_failure_pending = false


func _award_action_points(action: Dictionary) -> void:
	var points := int(action["points"])
	if points <= 0:
		return
	if str(action["when"]) == "next":
		pending_score += points
	else:
		score += points


func _advance_after_action() -> void:
	if day == 1 and slot == 1 and str(current_action["id"]) == "water_recovery":
		outcome_label.text += " The water-recovery upgrade used the remaining shift; Day 1 Slot 2 is skipped."
		_advance_to_next_day()
		return
	if day == 5 and slot == 1 and not leak_fixed:
		_game_over("Cabin pressure was still falling when the moonquake struck. The habitat could not hold pressure.")
		return
	if day == 5 and slot == 2:
		_win_campaign()
		return
	if slot == 1:
		_advance_to_slot_two()
	else:
		_advance_to_next_day()


func _advance_to_slot_two() -> void:
	if day == 4 and not flare_shelter_reached:
		_game_over("The solar particle event arrived before the crew reached the shielded core.")
		return
	if day == 5 and not leak_fixed:
		_game_over("The pressure boundary was not repaired before the moonquake.")
		return
	slot = 2
	completed_slot_actions.clear()
	_prepare_slot()
	_refresh_board()


func _advance_to_next_day() -> void:
	if not awaiting_bed:
		awaiting_bed = true
		slot_options.clear()
		pinned_action_id = ""
		outcome_label.text = "Work shifts complete. This is your 8-hour rest period. Find any crew bunk and press E to sleep through the night."
		_set_board_open(true)
		_refresh_board()
		return
	awaiting_bed = false
	if garden_checked_today:
		garden_neglect_days = 0
		garden_failure_pending = false
		garden_failure_days = 0
	else:
		garden_neglect_days += 1
		if garden_failure_pending:
			garden_failure_days += 1
			if garden_failure_days >= 1:
				_game_over("The unattended crop rack failed. Food production stopped before the crew restored it.")
				return
		else:
			var failure_chance := minf(0.12 * float(garden_neglect_days), 0.72)
			if random_source.randf() < failure_chance:
				garden_failure_pending = true
				garden_failure_days = 0
	if day == 2 and not water_checked:
		outcome_label.text = "Water storage was not checked on Day 2: −1 point on Day 3."
	if day == 3 and not filters_cleaned:
		_game_over("Airlock filter dust reached the habitat air system. Day 4 survival condition failed.")
		return
	if day == 5:
		_win_campaign()
		return
	day += 1
	slot = 1
	time_points = MAX_TIME_POINTS
	completed_slot_actions.clear()
	garden_checked_today = false
	if pending_score != 0:
		score += pending_score
		pending_score = 0
	if day == 4 and not filters_cleaned:
		_game_over("Airlock dust was still circulating when the solar particle event began. Mission ended.")
		return
	if day == 3 and not water_checked:
		score -= 1
		pending_score = 0
		outcome_label.text = "Water tank inspection was skipped: Day 3 penalty −1 point."
	_prepare_slot()
	_refresh_board()


func _skip_slot() -> void:
	if active or ended:
		return
	if day == 4 and slot == 1 and not flare_shelter_reached:
		_game_over("The crew skipped the shelter window and was exposed to the solar particle event.")
		return
	if day == 5 and slot == 1 and not leak_fixed:
		_game_over("The hull puncture was not repaired before the moonquake.")
		return
	if day == 5 and slot == 2:
		_win_campaign()
		return
	if slot == 1:
		_advance_to_slot_two()
	else:
		_advance_to_next_day()


func _start_new_day(next_day: int) -> void:
	day = next_day
	slot = 1
	time_points = MAX_TIME_POINTS
	completed_slot_actions.clear()
	garden_checked_today = false
	if pending_score != 0:
		score += pending_score
		pending_score = 0
	_prepare_slot()
	_refresh_board()


func _prepare_slot() -> void:
	slot_options = _build_slot_options()
	if garden_failure_pending or garden_neglect_days >= 3:
		var has_garden_check := false
		for action: Dictionary in slot_options:
			if action["id"] == "garden_check":
				has_garden_check = true
		if not has_garden_check:
			var garden_actions := _daily_action_pool().filter(func(action: Dictionary) -> bool: return action["id"] == "garden_check")
			if garden_actions.size() > 0:
				if slot_options.size() >= 3:
					slot_options[slot_options.size() - 1] = garden_actions[0]
				else:
					slot_options.append(garden_actions[0])
	completed_slot_actions.clear()
	for index in range(slot_options.size()):
		slot_options[index]["code"] = "%d.%d.%d" % [day, slot, index + 1]


func _build_slot_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if day == 1 and slot == 1:
		options = [
			_make_action("neutron_survey", "Drive the neutron spectrometer transect", "Map hydrogen-sensitive neutron counts; a low epithermal-neutron signal is a water-ice proxy, not a direct image.", 10, 5, "next", "scan", "outside", "Compare the three target readings with the background transect. The instrument records count rates for later map comparison."),
			_make_action("seismometer_bump", "Calibrate the lunar seismometer", "In the Lab, use the labeled sensor station to set its baseline. Contact invalidates this first run; recalibrate next slot.", 10, 0, "now", "dial", "lab", "At the labeled SEISMOMETER station, set the calibration reference, verify the baseline, then record the contact flag. This run is invalidated and must be repeated."),
			_make_action("water_recovery", "Improve water-recovery hardware efficiency", "Inspect the recovery loop, replace the limiting filter, and verify the conductivity reading. This long task uses the rest of the shift.", 20, 10, "now", "valves", "main", "Verify the recovery sequence in order: water feed, oxygen cell, CO₂ return. The improved loop supports both potable water and oxygen generation."),
		]
	elif day == 1 and slot == 2:
		var seismic_option := _make_action("rerun_seismometer", "A. Re-run the lunar seismometer calibration", "Return to the labeled sensor station in the Lab and repeat the baseline after accidental contact.", 10, 7, "now", "dial", "lab", "At the labeled SEISMOMETER station, set the reference calibration and verify a stable baseline waveform.") if seismometer_recalibration_due else _make_action("heat_probe", "B. Deploy the heat probe", "Record a thermal gradient at the lunar surface; this measures local heat flow rather than a planet-wide core temperature.", 10, 5, "now", "scan", "outside", "Compare the three stable probe readings and reject the outlier before logging the thermal profile.")
		options = [
			_make_action("soil_composition", "Analyze soil composition", "Separate a small regolith aliquot and log its visible mineral fractions.", 10, 6, "now", "sample", "lab", "Select three mineral-bearing areas in the sample image; record the result as a composition screen, not a resource guarantee."),
			seismic_option,
			_make_action("magnetometer", "Calibrate the magnetometer", "Take a quiet baseline, then record the local magnetic field. Lunar crustal anomalies are localized.", 10, 5, "now", "pattern", "lab", "Tune to the calibration reference, then record the field without moving the sensor.")
		]
	elif day == 2 and slot == 1:
		options.append(_filter_action())
		_append_random_actions(options, 2)
	elif day == 2 and slot == 2:
		if not filters_inspected:
			options.append(_filter_action())
		if power_actions_picked >= 2:
			options.append(_make_action("inspect_power", "Inspect the power bus for overuse", "Review load, battery state of charge, and generation before reconnecting nonessential loads.", 10, 10, "now", "dial", "main", "Match the bus load target and identify the overloaded branch before restoring power."))
		_append_random_actions(options, 3 - options.size())
	elif day == 3 and slot == 1:
		if not filters_cleaned:
			options.append(_clean_filter_action() if filters_inspected else _filter_action())
		options.append(_leak_detector_action())
		_append_random_actions(options, 3 - options.size())
	elif day == 3 and slot == 2:
		if not filters_cleaned:
			options.append(_clean_filter_action() if filters_inspected else _inspect_and_clean_filter_action())
		if not leak_found:
			options.append(_make_action("seismo_leak", "Use the Lab seismometer record to locate the impact", "At the labeled sensor station, compare the overnight waveform timestamp with the cabin pressure drop to narrow the puncture location.", 10, 6, "now", "scan", "lab", "Use the labeled SEISMOMETER station: match impact time and amplitude to the pressure trend. Record the likely hull sector; then repair it outside."))
		if options.size() < 3:
			_append_random_actions(options, 3 - options.size())
	elif day == 4 and slot == 1:
		var leak_action := _make_action("fix_leak", "1. Patch the investigated puncture", "Use the logged leak location, install the pressure patch, and verify cabin pressure is stable.", 20, 0, "now", "wrench", "outside", "Clean the rim, seat the patch, and verify the pressure trace. A leak found on Day 3 has the needed location data.") if leak_found and not leak_fixed else _make_action("leak_detector", "1. Find the puncture with the ultrasonic leak detector", "If it was not localized yesterday, scan the habitat skin and log the leak location.", 20, 0, "now", "scan", "outside", "Sweep the hull panels and compare the ultrasonic return with the baseline until the puncture signature is confirmed.")
		options = [
			leak_action,
			_make_action("flare_power_test", "2. Run a power-intensive test during the flare", "The test draws power when the solar-particle warning requires immediate sheltering.", 10, 0, "now", "dial", "main", "Attempt to synchronize the load. The flare window makes this unsafe."),
			_make_action("flare_shelter", "3. Enter the radiation shelter", "Move to the shielded core. You may repair the hull first in this slot, then select this option.", 10, 0, "now", "wrench", "main", "Confirm the shelter hatch and seal sequence before the radiation alarm reaches its peak.")
		]
	elif day == 4 and slot == 2:
		if not flare_shelter_reached:
			_game_over("The solar particle event arrived before the crew reached the shielded core.")
			return options
		options = [
			_make_action("flare_medical", "Do a medical check", "Record symptoms and crew status after the radiation alarm.", 4, 2, "now", "inspect", "med", "Check three crew-health indicators and note changes for Mission Control."),
			_make_action("flare_monitor", "Monitor radiation levels", "Compare shelter dosimeter readings with the warning threshold.", 4, 2, "now", "dial", "main", "Set the monitor to the reference interval and verify the accumulated dose reading."),
			_make_action("flare_filter", "Inspect the air filter", "Confirm particulate filtration is operating after the airlock contamination event.", 4, 2, "now", "brush", "airlock", "Remove the three highlighted dust deposits and confirm the filter path is clear.")
		]
	elif day == 5 and slot == 1:
		var repair_action := _make_action("fix_leak", "Repair the rock-impact puncture", "The moonquake is survivable only if the habitat pressure boundary is repaired before the second slot.", 20, 0, "now", "wrench", "outside", "Install the patch over the logged puncture and verify the pressure trace has stopped falling.") if not leak_fixed else _make_action("verify_patch", "Verify the pressure-boundary patch", "Inspect the completed repair and confirm cabin pressure is stable before the moonquake.", 10, 0, "now", "inspect", "outside", "Check the patch edge and compare two pressure readings. Any continuing drop means the repair is incomplete.")
		options = [repair_action]
		_append_random_actions(options, 2)
	else:
		options = [
			_make_action("quake_seismometer", "Record the moonquake on the Lab seismometer", "Use the labeled station to arm the calibrated waveform recorder and capture the event. You can survive without taking shelter.", 10, 8, "now", "dial", "lab", "At the labeled SEISMOMETER station, confirm the calibrated baseline and arm the event trigger before the shaking."),
			_make_action("quake_shelter", "Take shelter", "Move away from equipment and verify the crew is secured during the moonquake.", 10, 5, "now", "inspect", "main", "Confirm three crew restraint points and the shelter status indicator."),
		]
		_append_random_actions(options, 1)
	return options


func _append_random_actions(options: Array[Dictionary], count: int) -> void:
	if count <= 0:
		return
	var pool := _daily_action_pool()
	pool.shuffle()
	for action: Dictionary in pool:
		if options.size() >= 3 or count <= 0:
			break
		var already_present := false
		for existing: Dictionary in options:
			if existing["id"] == action["id"]:
				already_present = true
				break
		if not already_present:
			options.append(action)
			count -= 1


func _daily_action_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = [
		_make_action("oxygen_recycle", "Test oxygen-generation and CO₂ removal", "Check electrolysis, oxygen partial pressure, and carbon-dioxide removal as separate life-support functions.", 10, 6, "now", "valves", "main", "Verify water feed, oxygen cell, and CO₂ return in the ECLSS service order."),
		_make_action("rover_battery", "Inspect the rover battery and connections", "Check connector seating, temperature, charge state, and load response before the next traverse.", 10, 8, "next", "inspect", "outside", "Inspect three connector and battery-status indicators, then confirm the stable reading."),
		_make_action("radiation_sensor", "Deploy a surface radiation sensor", "Place the dosimeter away from the habitat and record a background interval.", 10, 5, "next", "dial", "outside", "Set the measurement interval and verify the sensor baseline before logging."),
		_make_action("collect_rock", "Collect and seal a lunar rock sample", "Record location and sample ID, seal the container, and bring it to the laboratory for composition screening.", 10, 7, "now", "sample", "outside", "Select the three candidate mineral-bearing areas and log the sample location. This adds 10 research AP."),
		_make_action("thermal_check", "Inspect habitat thermal telemetry", "Compare internal and external temperature readings across the insulation boundary; identify an abnormal gradient.", 10, 6, "now", "scan", "outside", "Compare the three thermal sensor pairs and flag the location with the largest unexplained gradient."),
		_make_action("solar_calibration", "Calibrate the solar array", "Check array pointing, output current, and dust-related power loss before changing the power budget.", 10, 7, "next", "math", "outside", "Match the array output reference and verify the current reading after calibration.", "power"),
		_make_action("backup_oxygen", "Test the emergency oxygen supply", "Verify reserve pressure, regulator response, and the isolation valve without venting the reserve.", 10, 5, "now", "valves", "main", "Check regulator, isolation, and reserve status in the safe sequence.", "power"),
		_make_action("antenna_check", "Inspect the communications antenna", "Check pointing, connector condition, and link quality; do not transmit during an unverified power fault.", 10, 6, "next", "math", "outside", "Tune the antenna to the recorded ground-station frequency and verify the link indicator."),
		_make_action("environment_station", "Deploy a lunar surface environment station", "Log surface temperature, radiation, and dust exposure. The Moon has no Earth-like weather to forecast.", 10, 8, "now", "inspect", "outside", "Confirm the temperature, radiation, and dust channels are active before recording the site."),
		_make_action("water_storage", "Check the water storage tanks", "Inspect tank level, leak status, and conductivity-qualified potable-water supply.", 10, 7, "now", "inspect", "main", "Check tank level, line pressure, and water-quality status. Skipping this on Day 2 costs 1 point on Day 3.", "power"),
		_make_action("collect_dust", "Collect a sealed regolith aliquot", "Collect a small surface sample with a logged location and keep it sealed for laboratory grain-size analysis.", 10, 0, "now", "sample", "outside", "Select the three marked regolith areas, label the aliquot, and log its collection site. Adds 10 research AP."),
		_make_action("garden_check", "Check the hydroponic crop rack", "Inspect leaf condition, nutrient flow, and grow-light operation; replace a failed plant before the crop is lost.", 10, 0, "now", "inspect", "garden", "Find the stressed plant indicators and confirm the replacement seedling is established."),
		_make_action("treat_sprain", "Treat the crew ankle strain", "Stabilize the joint and record pain and mobility before returning to EVA preparation.", 10, 0, "now", "bandage", "med", "Apply the wrap in the marked lower-anchor, upper-anchor, center, secure-end sequence.")
	]
	if rock_samples > 0:
		pool.append(_make_action("analyze_rock", "Analyze a sealed rock sample", "Compare grain and mineral features under the laboratory imager; preserve the sample ID and collection context.", 10, 0, "now", "sample", "lab", "Select three candidate mineral-bearing regions. Adds 2 research AP and consumes one sample."))
	if dust_samples > 0:
		pool.append(_make_action("analyze_dust", "Measure a regolith aliquot", "Inspect particle-size and agglutinate features; record uncertainty instead of inferring a resource deposit.", 10, 0, "now", "sample", "lab", "Select three representative grains and log the aliquot. Adds 2 research AP and consumes one sample."))
	return pool


func _filter_action() -> Dictionary:
	return _make_action("inspect_filters", "Inspect the airlock filters", "Trace the pressure-drop and particulate readings to find where lunar dust entered the filtration path. Cleaning is scheduled for the next shift.", 10, 0, "now", "inspect", "airlock", "Compare the three filter-stage indicators and identify the blocked stage. Cleaning is then scheduled.")


func _clean_filter_action() -> Dictionary:
	return _make_action("clean_filters", "Clean and verify the airlock filters", "Remove the lunar dust deposits and verify airflow and filter differential pressure before the next EVA.", 10, 0, "now", "brush", "airlock", "Brush the three highlighted dust deposits, then verify the airflow indicator returns to its normal band.")


func _inspect_and_clean_filter_action() -> Dictionary:
	return _make_action("inspect_and_clean_filters", "Find and clean the airlock filter blockage", "Trace the blocked stage, remove the trapped lunar dust, and verify airflow in one recovery procedure.", 20, 0, "now", "brush", "airlock", "Identify the blocked stage, then brush away the three deposits and verify the airflow indicator.")


func _leak_detector_action() -> Dictionary:
	return _make_action("leak_detector", "Locate the pressure leak with ultrasound", "Sweep the habitat skin, compare the ultrasonic return with the pressure trend, and log the puncture location for repair.", 10, 0, "now", "scan", "outside", "Compare the three acoustic returns with the baseline; isolate and record the puncture signature.")


func _make_action(id: String, title: String, brief: String, tp: int, points: int, when: String, game: String, location: String, challenge: String, category: String = "") -> Dictionary:
	var result_text := "Task complete."
	if id == "inspect_filters":
		result_text = "The blocked filter stage is identified; cleaning is scheduled."
	elif id == "clean_filters":
		result_text = "Airlock filters are clean and airflow is verified."
	elif id == "leak_detector":
		result_text = "Ultrasound and pressure data confirm the leak location; repair is queued."
	elif id == "seismo_leak":
		result_text = "The impact record matches the pressure-drop time; leak location is confirmed."
	elif id == "fix_leak":
		result_text = "The pressure patch is installed and the cabin pressure trace is stable."
	elif id == "flare_shelter":
		result_text = "The crew is inside the shielded core before peak exposure."
	elif id == "water_recovery":
		result_text = "Recovery-loop restriction is corrected and the verification sequence passed."
	var station := "seismometer" if id in ["seismometer_bump", "rerun_seismometer", "seismo_leak", "quake_seismometer"] else "airlock_filter" if location == "airlock" else "medical" if location == "med" else "garden" if location == "garden" else "lab_console" if location == "lab" else "life_support" if location == "main" else _exterior_station_for_action(id)
	return {"id": id, "title": title, "brief": brief, "tp": tp, "points": points, "when": when, "game": game, "location": location, "challenge": challenge, "category": category, "result": result_text, "station": station}


func _exterior_station_for_action(action_id: String) -> String:
	match action_id:
		"neutron_survey":
			return "neutron_station"
		"heat_probe", "radiation_sensor", "thermal_check", "environment_station":
			return "field_station"
		"rover_battery":
			return "rover_station"
		"collect_rock", "collect_dust":
			return "sample_station"
		"solar_calibration":
			return "solar_station"
		"leak_detector", "fix_leak", "verify_patch":
			return "hull_station"
		_:
			return "eva_station"


func _at_location(location: String) -> bool:
	var current_room: String = str(get_parent().call("_room_id_at_player"))
	if location == "outside":
		return current_room == "outside"
	return current_room == location


func _reward_summary(action: Dictionary) -> String:
	var notes: Array[String] = []
	if int(action["points"]) > 0:
		notes.append("+%d points %s" % [int(action["points"]), "next day" if str(action["when"]) == "next" else "now"])
	if str(action["id"]) == "collect_rock" or str(action["id"]) == "collect_dust":
		notes.append("+10 AP")
	if action["id"] == "analyze_rock" or action["id"] == "analyze_dust":
		notes.append("+2 AP")
	return "; ".join(notes)


func _event_text() -> String:
	match day:
		1:
			return "ASSIGNMENTS  /  One mission per shift. Bonus station drills earn points. Sleep 8 hours after Shift 2."
		2:
			return "EVENT: Lunar dust is trapped in the airlock filters. Locate the blocked stage today; clean it by Day 3 or the air system fails."
		3:
			return "EVENT: A small impact may have punctured the pressure boundary overnight. Find the leak and preserve its location for repair."
		4:
			return "EVENT: Solar particle warning for Slot 2. Reach the shielded core in Slot 1. Dust-cleaning and shelter deadlines are survival-critical."
		_:
			return "EVENT: Moonquake. Verify the hull patch before the shaking begins; record the seismometer or take shelter."


func _deadline_text() -> String:
	if day == 3 and not filters_cleaned:
		return "CRITICAL  /  Air filters fail tonight unless cleaned before sleep."
	if day == 2 and not filters_cleaned:
		return "WARNING  /  Clear airlock dust by end of Day 3 to protect habitat air."
	if day == 4 and not flare_shelter_reached:
		return "CRITICAL  /  Solar storm imminent. Reach the shielded core this shift or the crew will die."
	if day == 5 and not leak_fixed:
		return "CRITICAL  /  Hull pressure is falling. Repair the leak before the moonquake."
	if day >= 3 and not leak_found and not leak_fixed:
		return "WARNING  /  Leak not located. Find and repair it before the Day 5 moonquake."
	if garden_failure_pending:
		return "WARNING  /  Crop rack is failing. Inspect and replant in the Garden today."
	if day == 2 and not water_checked:
		return "OPTIONAL  /  Check water storage to avoid a 1 point penalty tomorrow."
	return "SURVIVAL SYSTEMS NOMINAL  /  Two work shifts, then 8 hours of sleep."


func _manual_text() -> String:
	return "[b]FIELD MANUAL — HABITAT OPERATIONS[/b]\n\n[b]How a shift works[/b]\nThe campaign lasts five days. Each day has two work shifts and an 8-hour sleep period after Shift 2. Each shift offers a mission assignment; optional station drills earn bonus points. You do not need to finish every task. Use Mission Control (TAB) to choose a mission, close it, walk to its station and press E. You can skip a shift from Mission Control.\n\n[b]Scoring and research[/b]\nPoints marked “next day” are credited when the next day starts. Research Actions add Research AP (separate from score). Field samples must be collected outside and analyzed in the Lab. Failed minigames can be retried, but mistakes use more TP.\n\n[b]Survival deadlines[/b]\n• Day 2: Inspect the airlock filter stages. Clean the dust by Day 3 or the habitat air system fails.\n• Day 2: Check water storage to avoid the −1 Day 3 score penalty.\n• Day 3: Use ultrasonic leak detection or correlate the pressure drop with the seismometer impact record.\n• Day 4 Slot 1: Repair the leak if located, then enter the shielded core. You may do both in this slot. Power-intensive work during the solar-particle warning is fatal.\n• Day 5 Slot 1: The pressure boundary must be repaired before the moonquake.\n• Garden: Each unchecked day increases crop-failure risk. A failed crop causes mission loss unless the rack is checked and replanted in time.\n\n[b]Research notes[/b]\nNeutron spectroscopy measures neutron populations. Hydrogen moderates neutrons, so a reduced epithermal-neutron signal can indicate hydrogen-bearing material; it does not directly image or prove an ice deposit. Record the rover transect, background and uncertainty.\n\nLife support tasks are separated: water recovery purifies and checks water; oxygen generation electrolyzes water; air revitalization removes CO₂ and trace contaminants. Never treat a single “oxygen recycling” reading as proof that all loops work.\n\nLunar rock and regolith tasks are screening studies. Log sample IDs and sites, keep samples sealed, and record mineral observations without claiming a deposit is economically valuable. The Moon has no Earth-like weather; the surface station records temperature, radiation and dust exposure.\n\n[b]NASA reference material[/b]\nNASA ECLSS: https://www.nasa.gov/reference/environmental-control-and-life-support-systems-eclss/\nNASA Lunar Prospector neutron spectrometer: https://science.nasa.gov/mission/lunar-prospector/\nNASA lunar dust health and operations brief: https://www.nasa.gov/wp-content/uploads/2023/12/ochmo-tb-011-lunar-dust-technical-brief.pdf\nNASA lunar surface environment: https://www.nasa.gov/reference/moonbase-environment/\nNASA Artemis radiation monitoring and shelter thresholds: https://science.nasa.gov/missions/artemis/artemis-2/to-protect-artemis-ii-astronauts-nasa-experts-keep-eyes-on-sun/\n\nThis is a playable research-training scenario based on NASA-published methods. It is a fictional habitat, and its minigames are not flight procedures or medical advice."


func _game_over(reason: String) -> void:
	ended = true
	active = false
	final_status = "CREW DECEASED\n%s\nFinal score: %d points    Research AP: %d\nSelect RESPAWN to start again." % [reason, score, research_points]
	_set_board_open(true)
	_refresh_board()


func _win_campaign() -> void:
	ended = true
	active = false
	if pending_score != 0:
		score += pending_score
		pending_score = 0
	final_status = "CAMPAIGN COMPLETE\nThe habitat held pressure, filtered the dust, sheltered the crew, and recorded the moonquake.\nFinal score: %d points    Research AP: %d" % [score, research_points]
	_set_board_open(true)
	_refresh_board()


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
