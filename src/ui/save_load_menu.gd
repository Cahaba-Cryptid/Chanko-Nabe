extends PanelContainer
class_name SaveLoadMenu
## Pause menu for saving and loading game - slots A, B, C

signal menu_closed
signal return_to_main_menu_requested

enum MenuMode { MAIN, SAVE, LOAD, CONFIRM_OVERWRITE, CONFIRM_MAIN_MENU }
enum MainOption { SAVE, LOAD, MAIN_MENU, RESUME }

const SLOT_NAMES := ["A", "B", "C"]
const SAVE_PATH_TEMPLATE := "user://save_slot_%s.dat"

var _mode: MenuMode = MenuMode.MAIN
var _selected_main_option: int = 0
var _selected_slot_index: int = 0
var _confirm_selection: int = 0  # 0 = Yes, 1 = No (for overwrite confirm)
var _slot_data: Array[Dictionary] = []  # Cached slot info

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var main_options_container: VBoxContainer = $MarginContainer/VBox/MainOptionsContainer
@onready var slots_container: VBoxContainer = $MarginContainer/VBox/SlotsContainer
@onready var confirm_container: VBoxContainer = $MarginContainer/VBox/ConfirmContainer
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel


func _ready() -> void:
	hide()


func open_menu() -> void:
	_mode = MenuMode.MAIN
	_selected_main_option = 0
	_selected_slot_index = 0
	_refresh_slot_data()
	_update_display()
	show()
	GameManager.is_paused = true


func close_menu() -> void:
	hide()
	GameManager.is_paused = false
	menu_closed.emit()


func _refresh_slot_data() -> void:
	_slot_data.clear()
	for i in range(SLOT_NAMES.size()):
		var slot_name: String = SLOT_NAMES[i]
		var save_path := SAVE_PATH_TEMPLATE % slot_name
		var data := {"name": slot_name, "exists": false, "timestamp": "", "day": 0, "money": 0}

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


func _update_display() -> void:
	# Hide all containers first
	main_options_container.hide()
	slots_container.hide()
	confirm_container.hide()

	match _mode:
		MenuMode.MAIN:
			_show_main_menu()
		MenuMode.SAVE:
			_show_slot_selection("Save Game")
		MenuMode.LOAD:
			_show_slot_selection("Load Game")
		MenuMode.CONFIRM_OVERWRITE:
			_show_confirm_overwrite()
		MenuMode.CONFIRM_MAIN_MENU:
			_show_confirm_main_menu()


func _show_main_menu() -> void:
	title_label.text = "Game Menu"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Esc: Resume"

	# Clear and rebuild main options
	for child in main_options_container.get_children():
		child.queue_free()

	var options := ["Save Game", "Load Game", "Main Menu", "Resume"]
	for i in range(options.size()):
		var button := Button.new()
		button.text = options[i]
		button.custom_minimum_size = Vector2(200, 40)
		main_options_container.add_child(button)

	main_options_container.show()

	# Update selection after a frame
	await get_tree().process_frame
	_update_main_selection()


func _show_slot_selection(title: String) -> void:
	title_label.text = title
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Back"

	# Clear and rebuild slot buttons
	for child in slots_container.get_children():
		child.queue_free()

	for i in range(_slot_data.size()):
		var data := _slot_data[i]
		var button := Button.new()

		if data["exists"]:
			var money_str := _format_money(data["money"])
			button.text = "Slot %s - Day %d | %s | %s" % [data["name"], data["day"], money_str, data["timestamp"]]
		else:
			button.text = "Slot %s - Empty" % data["name"]

		button.custom_minimum_size = Vector2(400, 40)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slots_container.add_child(button)

	slots_container.show()

	await get_tree().process_frame
	_update_slot_selection()


func _show_confirm_overwrite() -> void:
	title_label.text = "Overwrite Save?"
	hint_label.text = "Arrow Keys: Navigate | E: Select"

	# Clear and rebuild confirm options
	for child in confirm_container.get_children():
		child.queue_free()

	var slot_data := _slot_data[_selected_slot_index]
	var info_label := Label.new()
	info_label.text = "Slot %s already contains a save from Day %d.\nAre you sure you want to overwrite?" % [slot_data["name"], slot_data["day"]]
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_container.add_child(info_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	confirm_container.add_child(spacer)

	var yes_button := Button.new()
	yes_button.text = "Yes, Overwrite"
	yes_button.custom_minimum_size = Vector2(200, 40)
	confirm_container.add_child(yes_button)

	var no_button := Button.new()
	no_button.text = "No, Cancel"
	no_button.custom_minimum_size = Vector2(200, 40)
	confirm_container.add_child(no_button)

	confirm_container.show()

	await get_tree().process_frame
	_update_confirm_selection()


func _show_confirm_main_menu() -> void:
	title_label.text = "Return to Main Menu?"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Cancel"

	# Clear and rebuild confirm options
	for child in confirm_container.get_children():
		child.queue_free()

	var info_label := Label.new()
	info_label.text = "Your game will be saved automatically.\nReturn to main menu?"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_container.add_child(info_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	confirm_container.add_child(spacer)

	var yes_button := Button.new()
	yes_button.text = "Yes, Return to Menu"
	yes_button.custom_minimum_size = Vector2(200, 40)
	confirm_container.add_child(yes_button)

	var no_button := Button.new()
	no_button.text = "No, Keep Playing"
	no_button.custom_minimum_size = Vector2(200, 40)
	confirm_container.add_child(no_button)

	confirm_container.show()

	await get_tree().process_frame
	_update_confirm_selection()


func _update_main_selection() -> void:
	var children := main_options_container.get_children()
	for i in range(children.size()):
		if children[i] is Button:
			var button: Button = children[i]
			if i == _selected_main_option:
				_apply_selected_style(button)
			else:
				button.remove_theme_stylebox_override("normal")


func _update_slot_selection() -> void:
	var children := slots_container.get_children()
	for i in range(children.size()):
		if children[i] is Button:
			var button: Button = children[i]
			if i == _selected_slot_index:
				_apply_selected_style(button)
			else:
				button.remove_theme_stylebox_override("normal")


func _update_confirm_selection() -> void:
	# Confirm buttons are at index 2 and 3 (after label and spacer)
	var children := confirm_container.get_children()
	if children.size() < 4:
		return

	var yes_button: Button = children[2]
	var no_button: Button = children[3]

	if _confirm_selection == 0:  # Yes
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
		MenuMode.SAVE, MenuMode.LOAD:
			_handle_slot_input(event)
		MenuMode.CONFIRM_OVERWRITE:
			_handle_confirm_input(event)
		MenuMode.CONFIRM_MAIN_MENU:
			_handle_main_menu_confirm_input(event)


func _handle_main_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_main_option = wrapi(_selected_main_option - 1, 0, 4)
		_update_main_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_main_option = wrapi(_selected_main_option + 1, 0, 4)
		_update_main_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_select_main_option()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back") or event.is_action_pressed("game_menu"):
		close_menu()
		get_viewport().set_input_as_handled()


func _handle_slot_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_slot_index = wrapi(_selected_slot_index - 1, 0, SLOT_NAMES.size())
		_update_slot_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_slot_index = wrapi(_selected_slot_index + 1, 0, SLOT_NAMES.size())
		_update_slot_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_select_slot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_mode = MenuMode.MAIN
		_selected_main_option = 0
		_update_display()
		get_viewport().set_input_as_handled()


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		_confirm_selection = 1 - _confirm_selection  # Toggle between 0 and 1
		_update_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _confirm_selection == 0:  # Yes - do the overwrite
			_do_save(SLOT_NAMES[_selected_slot_index])
			_mode = MenuMode.MAIN
			_update_display()
		else:  # No - go back to slot selection
			_mode = MenuMode.SAVE
			_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_mode = MenuMode.SAVE
		_update_display()
		get_viewport().set_input_as_handled()


func _handle_main_menu_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		_confirm_selection = 1 - _confirm_selection
		_update_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _confirm_selection == 0:  # Yes - return to main menu
			hide()
			GameManager.is_paused = false
			return_to_main_menu_requested.emit()
		else:  # No - go back to game menu
			_mode = MenuMode.MAIN
			_selected_main_option = 0
			_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_mode = MenuMode.MAIN
		_selected_main_option = 0
		_update_display()
		get_viewport().set_input_as_handled()


func _select_main_option() -> void:
	match _selected_main_option:
		0:  # Save
			_mode = MenuMode.SAVE
			_selected_slot_index = 0
			_update_display()
		1:  # Load
			_mode = MenuMode.LOAD
			_selected_slot_index = 0
			_update_display()
		2:  # Main Menu
			_mode = MenuMode.CONFIRM_MAIN_MENU
			_confirm_selection = 1  # Default to "No"
			_update_display()
		3:  # Resume
			close_menu()


func _select_slot() -> void:
	var slot_name: String = SLOT_NAMES[_selected_slot_index]
	var slot_info := _slot_data[_selected_slot_index]

	if _mode == MenuMode.SAVE:
		if slot_info["exists"]:
			# Need to confirm overwrite
			_mode = MenuMode.CONFIRM_OVERWRITE
			_confirm_selection = 0  # Default to "Yes"
			_update_display()
		else:
			_do_save(slot_name)
			_mode = MenuMode.MAIN
			_update_display()
	elif _mode == MenuMode.LOAD:
		if slot_info["exists"]:
			_do_load(slot_name)
			close_menu()
		# If empty, do nothing


func _do_save(slot_name: String) -> void:
	var save_path := SAVE_PATH_TEMPLATE % slot_name

	# Build save data
	var save_data := {
		"money": GameManager.money,
		"current_day": GameManager.current_day,
		"timestamp": _get_timestamp(),
		"current_hour": TimeManager.current_hour,
		"current_minute": TimeManager.current_minute,
		"characters": []
	}

	for character in GameManager.characters:
		if character.has_method("to_dict"):
			save_data["characters"].append(character.to_dict())

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
		print("Game saved to slot %s" % slot_name)
		_refresh_slot_data()


func _do_load(slot_name: String) -> void:
	var save_path := SAVE_PATH_TEMPLATE % slot_name

	if not FileAccess.file_exists(save_path):
		return

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file:
		var save_data: Variant = file.get_var()
		file.close()

		if save_data is Dictionary:
			GameManager.money = save_data.get("money", 1000)
			GameManager.current_day = save_data.get("current_day", 1)
			TimeManager.current_hour = save_data.get("current_hour", 8)
			TimeManager.current_minute = save_data.get("current_minute", 0)

			# Load characters
			var char_data_array: Array = save_data.get("characters", [])
			for i in range(mini(char_data_array.size(), GameManager.characters.size())):
				var char_dict: Dictionary = char_data_array[i]
				var character: CharacterData = GameManager.characters[i]
				if character.has_method("from_dict"):
					character.from_dict(char_dict)

			print("Game loaded from slot %s" % slot_name)


func _get_timestamp() -> String:
	var datetime := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [
		datetime["year"],
		datetime["month"],
		datetime["day"],
		datetime["hour"],
		datetime["minute"]
	]


func _format_money(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return "¤" + result
