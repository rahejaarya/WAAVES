extends CanvasLayer

# Room name, interaction hint, deck plan and the red leak alarm.

@onready var room_label: Label = %RoomLabel
@onready var hint_panel: PanelContainer = %HintPanel
@onready var hint_label: Label = %HintLabel
@onready var minimap: Control = %Minimap
@onready var alarm: ColorRect = %Alarm

var alarm_time := 0.0


func set_room(title: String) -> void:
	room_label.text = title


func set_hint(text: String) -> void:
	hint_panel.visible = text != ""
	hint_label.text = text


func set_alarm(on: bool, delta: float) -> void:
	alarm.visible = on
	if on:
		alarm_time += delta
		alarm.color.a = 0.06 + 0.06 * (0.5 + 0.5 * sin(alarm_time * 4.0))
