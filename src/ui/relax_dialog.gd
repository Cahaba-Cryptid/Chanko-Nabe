extends PanelContainer
class_name RelaxDialog
## Dialog for selecting relax duration - pauses game and restores energy

signal duration_selected(minutes: float)
signal dialog_closed

const ENERGY_PER_HOUR := 10  # Energy restored per hour of relaxing

var _character: CharacterData = null
var _selected_index: int = 0
var _duration_options: Array[Dictionary] = []  # {label, minutes, is_full_recovery}

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var energy_label: Label = $MarginContainer/VBox/EnergyLabel
@onready var options_container: VBoxContainer = $MarginContainer/VBox/OptionsContainer
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel


func _ready() -> void:
	hide()


func open_dialog(character: CharacterData) -> void:
	_character = character
	_selected_index = 0
	_build_options()
	_update_display()
	show()
	GameManager.push_pause("relax_dialog")


func _build_options() -> void:
	_duration_options.clear()

	# Fixed duration options
	_duration_options.append({"label": "1 hour", "minutes": 60.0, "is_full_recovery": false})
	_duration_options.append({"label": "3 hours", "minutes": 180.0, "is_full_recovery": false})
	_duration_options.append({"label": "5 hours", "minutes": 300.0, "is_full_recovery": false})
	_duration_options.append({"label": "10 hours", "minutes": 600.0, "is_full_recovery": false})

	# Full recovery option
	if _character:
		var energy_needed := 100 - _character.energy
		var hours_needed := ceili(float(energy_needed) / float(ENERGY_PER_HOUR))
		var minutes_needed := hours_needed * 60.0
		_duration_options.append({
			"label": "Full recovery (%d hours)" % hours_needed,
			"minutes": minutes_needed,
			"is_full_recovery": true
		})


func _update_display() -> void:
	if not _character:
		return

	title_label.text = "%s - Relax" % _character.display_name
	energy_label.text = "Current Energy: %d/100" % _character.energy

	# Clear existing option buttons
	for child in options_container.get_children():
		child.queue_free()

	# Create option buttons
	for i in range(_duration_options.size()):
		var option := _duration_options[i]
		var button := Button.new()
		button.text = option["label"]
		button.custom_minimum_size = Vector2(200, 40)
		options_container.add_child(button)

	# Wait a frame for buttons to be added, then update selection
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_selection_visuals()


func _update_selection_visuals() -> void:
	var buttons := options_container.get_children()
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		if i == _selected_index:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.2, 0.2)
			style.border_color = Color(1.0, 0.85, 0.4)
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			button.add_theme_stylebox_override("normal", style)
		else:
			button.remove_theme_stylebox_override("normal")


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("move_up"):
		_selected_index = wrapi(_selected_index - 1, 0, _duration_options.size())
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_index = wrapi(_selected_index + 1, 0, _duration_options.size())
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_close_dialog()
		get_viewport().set_input_as_handled()


func _confirm_selection() -> void:
	var option := _duration_options[_selected_index]
	duration_selected.emit(option["minutes"])
	_close_dialog()


func _close_dialog() -> void:
	close_dialog()


func close_dialog() -> void:
	hide()
	GameManager.pop_pause("relax_dialog")
	dialog_closed.emit()


func get_energy_restored(minutes: float) -> int:
	## Calculate how much energy would be restored for given minutes
	var hours := minutes / 60.0
	return int(hours * ENERGY_PER_HOUR)
