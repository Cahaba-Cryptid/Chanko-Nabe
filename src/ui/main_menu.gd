extends Control
class_name MainMenu
## Main menu screen - New Game, Continue, Options (single save slot)

signal start_new_game
signal continue_game

enum MenuMode { MAIN, CONFIRM_OVERWRITE }

const SAVE_PATH := "user://save.dat"

var _mode: MenuMode = MenuMode.MAIN
var _selected_index: int = 0
var _save_exists: bool = false
var _save_day: int = 0
var _save_money: int = 0

# Main menu options - dynamically built based on save state
var _main_options: Array[Dictionary] = []

@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/TitleLabel
@onready var subtitle_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/SubtitleLabel
@onready var options_container: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBox/OptionsContainer
@onready var hint_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/HintLabel
@onready var version_label: Label = $VersionLabel


func _ready() -> void:
	version_label.text = "v%s" % GameManager.VERSION
	_refresh_save_data()
	_build_main_options()
	_update_display()


func _refresh_save_data() -> void:
	_save_exists = false
	_save_day = 0
	_save_money = 0

	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var save_data: Variant = file.get_var()
			file.close()
			if save_data is Dictionary:
				_save_exists = true
				_save_day = save_data.get("current_day", 0)
				_save_money = save_data.get("money", 0)


func _build_main_options() -> void:
	_main_options.clear()

	# Continue - only if save exists (show first when available)
	if _save_exists:
		_main_options.append({"id": "continue", "label": "Continue (Day %d)" % _save_day})

	# New Game - always available
	_main_options.append({"id": "new_game", "label": "New Game"})

	# Options - placeholder
	_main_options.append({"id": "options", "label": "Options"})


func has_save() -> bool:
	return _save_exists


func _update_display() -> void:
	match _mode:
		MenuMode.MAIN:
			_show_main_menu()
		MenuMode.CONFIRM_OVERWRITE:
			_show_confirm_overwrite()


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
	if not is_instance_valid(self) or not visible:
		return
	_update_selection()


func _show_confirm_overwrite() -> void:
	title_label.text = "Start New Game?"
	subtitle_label.text = "Your existing save (Day %d) will be overwritten." % _save_day
	subtitle_label.show()
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Cancel"

	# Clear and rebuild
	for child in options_container.get_children():
		child.queue_free()

	var yes_button := Button.new()
	yes_button.text = "Yes, Start New Game"
	yes_button.custom_minimum_size = Vector2(250, 45)
	options_container.add_child(yes_button)

	var no_button := Button.new()
	no_button.text = "No, Cancel"
	no_button.custom_minimum_size = Vector2(250, 45)
	options_container.add_child(no_button)

	_selected_index = 1  # Default to "No"

	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_selection()


func _update_selection() -> void:
	var buttons := options_container.get_children()
	for i in range(buttons.size()):
		if buttons[i] is Button:
			var button: Button = buttons[i]
			if i == _selected_index:
				_apply_selected_style(button)
			else:
				button.remove_theme_stylebox_override("normal")


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
		MenuMode.CONFIRM_OVERWRITE:
			_handle_confirm_input(event)


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


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		_selected_index = 1 - _selected_index  # Toggle 0/1
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _selected_index == 0:  # Yes - start new game
			start_new_game.emit()
		else:  # No - cancel
			_mode = MenuMode.MAIN
			_selected_index = 0
			_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_mode = MenuMode.MAIN
		_selected_index = 0
		_update_display()
		get_viewport().set_input_as_handled()


func _select_main_option() -> void:
	if _selected_index >= _main_options.size():
		return

	var option: Dictionary = _main_options[_selected_index]

	match option["id"]:
		"new_game":
			if _save_exists:
				# Show confirmation
				_mode = MenuMode.CONFIRM_OVERWRITE
				_selected_index = 1  # Default to "No"
				_update_display()
			else:
				# No save exists, proceed directly
				start_new_game.emit()
		"continue":
			continue_game.emit()
		"options":
			# Placeholder - show message
			print("Options not yet implemented")


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
