extends PanelContainer
class_name SaveLoadMenu
## Pause menu - Resume or return to Main Menu (auto-save system)

signal menu_closed
signal return_to_main_menu_requested

enum MenuMode { MAIN, CONFIRM_MAIN_MENU }
enum MainOption { MAIN_MENU, RESUME }

var _mode: MenuMode = MenuMode.MAIN
var _selected_main_option: int = 0
var _confirm_selection: int = 0  # 0 = Yes, 1 = No

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var main_options_container: VBoxContainer = $MarginContainer/VBox/MainOptionsContainer
@onready var slots_container: VBoxContainer = $MarginContainer/VBox/SlotsContainer
@onready var confirm_container: VBoxContainer = $MarginContainer/VBox/ConfirmContainer
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel


func _ready() -> void:
	hide()


func open_menu() -> void:
	_mode = MenuMode.MAIN
	_selected_main_option = 1  # Default to Resume
	_update_display()
	show()
	GameManager.push_pause("save_load_menu")


func close_menu() -> void:
	hide()
	GameManager.pop_pause("save_load_menu")
	menu_closed.emit()


func _update_display() -> void:
	# Hide all containers first
	main_options_container.hide()
	slots_container.hide()
	confirm_container.hide()

	match _mode:
		MenuMode.MAIN:
			_show_main_menu()
		MenuMode.CONFIRM_MAIN_MENU:
			_show_confirm_main_menu()


func _show_main_menu() -> void:
	title_label.text = "Game Menu"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Esc: Resume"

	# Clear and rebuild main options
	for child in main_options_container.get_children():
		child.queue_free()

	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return

	var options := ["Main Menu", "Resume"]
	for i in range(options.size()):
		var button := Button.new()
		button.text = options[i]
		button.custom_minimum_size = Vector2(200, 40)
		main_options_container.add_child(button)

	main_options_container.show()

	# Update selection after a frame
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_main_selection()


func _show_confirm_main_menu() -> void:
	title_label.text = "Return to Main Menu?"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Cancel"

	# Clear and rebuild confirm options
	for child in confirm_container.get_children():
		child.queue_free()

	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return

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
	if not is_instance_valid(self) or not visible:
		return
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
		MenuMode.CONFIRM_MAIN_MENU:
			_handle_confirm_input(event)


func _handle_main_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		_selected_main_option = 1 - _selected_main_option  # Toggle 0/1
		_update_main_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_select_main_option()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back") or event.is_action_pressed("game_menu"):
		close_menu()
		get_viewport().set_input_as_handled()


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		_confirm_selection = 1 - _confirm_selection
		_update_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _confirm_selection == 0:  # Yes - return to main menu
			hide()
			GameManager.pop_pause("save_load_menu")
			return_to_main_menu_requested.emit()
		else:  # No - go back to game menu
			_mode = MenuMode.MAIN
			_selected_main_option = 1  # Default to Resume
			_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_mode = MenuMode.MAIN
		_selected_main_option = 1  # Default to Resume
		_update_display()
		get_viewport().set_input_as_handled()


func _select_main_option() -> void:
	match _selected_main_option:
		0:  # Main Menu
			_mode = MenuMode.CONFIRM_MAIN_MENU
			_confirm_selection = 1  # Default to "No"
			_update_display()
		1:  # Resume
			close_menu()
