extends Control
class_name MainMenu
## Main menu screen - New Game, Continue, Delete Save, Options

signal start_new_game(slot: int, archetype_id: String)
signal continue_game(slot: int)

enum MenuMode { MAIN, DELETE_SLOT, CONFIRM_DELETE, NO_SLOTS_WARNING }

const SLOT_COUNT := 3
const SAVE_PATH_TEMPLATE := "user://save_slot_%s.dat"
const SLOT_NAMES := ["A", "B", "C"]

var _mode: MenuMode = MenuMode.MAIN
var _selected_index: int = 0
var _selected_slot_index: int = 0
var _slot_data: Array[Dictionary] = []

# Main menu options - dynamically built based on save state
var _main_options: Array[Dictionary] = []

@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/TitleLabel
@onready var subtitle_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/SubtitleLabel
@onready var options_container: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBox/OptionsContainer
@onready var hint_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/HintLabel


func _ready() -> void:
	_refresh_slot_data()
	_build_main_options()
	_update_display()


func _refresh_slot_data() -> void:
	_slot_data.clear()
	for i in range(SLOT_COUNT):
		var slot_name: String = SLOT_NAMES[i]
		var save_path := SAVE_PATH_TEMPLATE % slot_name
		var data := {"name": slot_name, "index": i, "exists": false, "timestamp": "", "day": 0, "money": 0}

		if FileAccess.file_exists(save_path):
			var file := FileAccess.open(save_path, FileAccess.READ)
			if file:
				var save_data: Variant = file.get_var()
				file.close()
				if save_data is Dictionary:
					data["exists"] = true
					data["timestamp"] = save_data.get("timestamp", "Unknown")
					data["day"] = save_data.get("current_day", 0)
					data["money"] = save_data.get("money", 0)

		_slot_data.append(data)


func _build_main_options() -> void:
	_main_options.clear()

	# New Game - always available
	_main_options.append({"id": "new_game", "label": "New Game"})

	# Continue - only if at least one save exists
	var most_recent_slot := _get_most_recent_slot()
	if most_recent_slot >= 0:
		_main_options.append({"id": "continue", "label": "Continue", "slot": most_recent_slot})

	# Delete Save - only if at least one save exists
	if _has_any_save():
		_main_options.append({"id": "delete", "label": "Delete Save"})

	# Options - placeholder
	_main_options.append({"id": "options", "label": "Options"})


func _has_any_save() -> bool:
	for data in _slot_data:
		if data["exists"]:
			return true
	return false


func _get_most_recent_slot() -> int:
	# Return the slot with the most recent timestamp, or -1 if no saves
	var most_recent_slot := -1
	var most_recent_time := ""

	for data in _slot_data:
		if data["exists"]:
			var timestamp: String = data["timestamp"]
			if timestamp > most_recent_time:
				most_recent_time = timestamp
				most_recent_slot = data["index"]

	return most_recent_slot


func _get_empty_slot_count() -> int:
	var count := 0
	for data in _slot_data:
		if not data["exists"]:
			count += 1
	return count


func _update_display() -> void:
	match _mode:
		MenuMode.MAIN:
			_show_main_menu()
		MenuMode.DELETE_SLOT:
			_show_delete_slots()
		MenuMode.CONFIRM_DELETE:
			_show_confirm_delete()


func _show_main_menu() -> void:
	title_label.text = "CHANKO NABE"
	subtitle_label.text = "A CammTec Production"
	subtitle_label.show()
	hint_label.text = "Arrow Keys: Navigate | E: Select"

	# Clear and rebuild options
	for child in options_container.get_children():
		child.queue_free()

	for i in range(_main_options.size()):
		var option: Dictionary = _main_options[i]
		var button := Button.new()
		button.text = option["label"]
		button.custom_minimum_size = Vector2(250, 45)
		options_container.add_child(button)

	# Clamp selection
	_selected_index = clampi(_selected_index, 0, _main_options.size() - 1)

	await get_tree().process_frame
	_update_selection()


func _show_delete_slots() -> void:
	title_label.text = "Delete Save"
	subtitle_label.hide()
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Back"

	# Clear and rebuild slot buttons
	for child in options_container.get_children():
		child.queue_free()

	for i in range(_slot_data.size()):
		var data: Dictionary = _slot_data[i]
		var button := Button.new()

		if data["exists"]:
			var money_str := _format_money(data["money"])
			button.text = "Slot %s - Day %d | %s" % [data["name"], data["day"], money_str]
		else:
			button.text = "Slot %s - Empty" % data["name"]
			button.disabled = true

		button.custom_minimum_size = Vector2(350, 45)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		options_container.add_child(button)

	# Find first valid (non-empty) slot
	_selected_slot_index = 0
	for i in range(_slot_data.size()):
		if _slot_data[i]["exists"]:
			_selected_slot_index = i
			break

	await get_tree().process_frame
	_update_slot_selection()


func _show_confirm_delete() -> void:
	title_label.text = "Confirm Delete"
	subtitle_label.hide()
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Cancel"

	var slot_data: Dictionary = _slot_data[_selected_slot_index]

	# Clear and rebuild
	for child in options_container.get_children():
		child.queue_free()

	var info_label := Label.new()
	info_label.text = "Delete Slot %s (Day %d)?" % [slot_data["name"], slot_data["day"]]
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_container.add_child(info_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	options_container.add_child(spacer)

	var yes_button := Button.new()
	yes_button.text = "Yes, Delete"
	yes_button.custom_minimum_size = Vector2(200, 45)
	options_container.add_child(yes_button)

	var no_button := Button.new()
	no_button.text = "No, Cancel"
	no_button.custom_minimum_size = Vector2(200, 45)
	options_container.add_child(no_button)

	_selected_index = 1  # Default to "No"

	await get_tree().process_frame
	_update_confirm_selection()


func _update_selection() -> void:
	var buttons := options_container.get_children()
	for i in range(buttons.size()):
		if buttons[i] is Button:
			var button: Button = buttons[i]
			if i == _selected_index:
				_apply_selected_style(button)
			else:
				button.remove_theme_stylebox_override("normal")


func _update_slot_selection() -> void:
	var buttons := options_container.get_children()
	for i in range(buttons.size()):
		if buttons[i] is Button:
			var button: Button = buttons[i]
			if i == _selected_slot_index:
				_apply_selected_style(button)
			else:
				button.remove_theme_stylebox_override("normal")


func _update_confirm_selection() -> void:
	# Confirm buttons are at index 2 and 3 (after label and spacer)
	var children := options_container.get_children()
	if children.size() < 4:
		return

	var yes_button: Button = children[2]
	var no_button: Button = children[3]

	if _selected_index == 0:  # Yes
		_apply_selected_style(yes_button)
		no_button.remove_theme_stylebox_override("normal")
	else:  # No
		yes_button.remove_theme_stylebox_override("normal")
		_apply_selected_style(no_button)


func _apply_selected_style(button: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2)
	style.border_color = Color(1.0, 0.85, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", style)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	match _mode:
		MenuMode.MAIN:
			_handle_main_input(event)
		MenuMode.DELETE_SLOT:
			_handle_delete_input(event)
		MenuMode.CONFIRM_DELETE:
			_handle_confirm_input(event)
		MenuMode.NO_SLOTS_WARNING:
			_handle_no_slots_input(event)


func _handle_main_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_index = wrapi(_selected_index - 1, 0, _main_options.size())
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_index = wrapi(_selected_index + 1, 0, _main_options.size())
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_select_main_option()
		get_viewport().set_input_as_handled()


func _handle_delete_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_move_slot_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_move_slot_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _slot_data[_selected_slot_index]["exists"]:
			_mode = MenuMode.CONFIRM_DELETE
			_selected_index = 1  # Default to "No"
			_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_mode = MenuMode.MAIN
		_selected_index = 0
		_update_display()
		get_viewport().set_input_as_handled()


func _move_slot_selection(direction: int) -> void:
	# Skip empty slots when navigating
	var start := _selected_slot_index
	_selected_slot_index = wrapi(_selected_slot_index + direction, 0, SLOT_COUNT)

	# Find next valid slot
	var attempts := 0
	while not _slot_data[_selected_slot_index]["exists"] and attempts < SLOT_COUNT:
		_selected_slot_index = wrapi(_selected_slot_index + direction, 0, SLOT_COUNT)
		attempts += 1

	# If no valid slot found, stay at original
	if not _slot_data[_selected_slot_index]["exists"]:
		_selected_slot_index = start

	_update_slot_selection()


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		_selected_index = 1 - _selected_index  # Toggle 0/1
		_update_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _selected_index == 0:  # Yes - delete
			_delete_slot(_selected_slot_index)
			_refresh_slot_data()
			_build_main_options()
			# Go back to main menu if no saves left, else back to delete
			if _has_any_save():
				_mode = MenuMode.DELETE_SLOT
			else:
				_mode = MenuMode.MAIN
				_selected_index = 0
			_update_display()
		else:  # No - cancel
			_mode = MenuMode.DELETE_SLOT
			_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_mode = MenuMode.DELETE_SLOT
		_update_display()
		get_viewport().set_input_as_handled()


func _select_main_option() -> void:
	if _selected_index >= _main_options.size():
		return

	var option: Dictionary = _main_options[_selected_index]

	match option["id"]:
		"new_game":
			_start_new_game()
		"continue":
			var slot: int = option.get("slot", 0)
			continue_game.emit(slot)
		"delete":
			_mode = MenuMode.DELETE_SLOT
			_selected_slot_index = 0
			_update_display()
		"options":
			# Placeholder - show message
			print("Options not yet implemented")


func _start_new_game() -> void:
	# Always refresh slot data to ensure it's current
	_refresh_slot_data()

	var empty_count := _get_empty_slot_count()

	if empty_count == 0:
		# No empty slots - show warning
		_show_no_slots_warning()
	else:
		# Proceed to archetype selection
		# For now, emit with first empty slot - archetype selection will handle slot choice
		start_new_game.emit(-1, "")  # -1 means "go to archetype selection"


func _show_no_slots_warning() -> void:
	title_label.text = "No Empty Slots"
	subtitle_label.text = "Delete a save to start a new game."
	subtitle_label.show()
	hint_label.text = "E/Q: Back to Menu"

	# Clear options
	for child in options_container.get_children():
		child.queue_free()

	var back_button := Button.new()
	back_button.text = "Back to Menu"
	back_button.custom_minimum_size = Vector2(200, 45)
	options_container.add_child(back_button)

	_selected_index = 0
	_mode = MenuMode.NO_SLOTS_WARNING

	await get_tree().process_frame
	_apply_selected_style(back_button)


func _handle_no_slots_input(event: InputEvent) -> void:
	# Any accept or back action returns to main menu
	if event.is_action_pressed("accept") or event.is_action_pressed("back"):
		_mode = MenuMode.MAIN
		_selected_index = 0
		_update_display()
		get_viewport().set_input_as_handled()


func _delete_slot(slot_index: int) -> void:
	var slot_name: String = SLOT_NAMES[slot_index]
	var save_path := SAVE_PATH_TEMPLATE % slot_name

	if FileAccess.file_exists(save_path):
		var err := DirAccess.remove_absolute(save_path)
		if err == OK:
			print("Deleted save slot %s" % slot_name)
		else:
			print("Failed to delete save slot %s" % slot_name)


func _format_money(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return "$" + result


## Get slot data for external use (e.g., archetype selection)
func get_slot_data() -> Array[Dictionary]:
	_refresh_slot_data()
	return _slot_data
