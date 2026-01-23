extends PanelContainer
class_name PreferenceSelectionDialog
## Dialog for selecting food preferences before first contest

signal preferences_selected(likes: Array, dislikes: Array)
signal dialog_cancelled

const FOOD_CATEGORIES := ["fried", "rice", "noodles", "grilled", "sweet", "soup"]
const CATEGORY_NAMES := {
	"fried": "Fried Foods",
	"rice": "Rice Dishes",
	"noodles": "Noodles",
	"grilled": "Grilled Items",
	"sweet": "Sweets",
	"soup": "Soups & Stews"
}

var _character: CharacterData
var _selected_likes: Array[String] = []
var _selected_dislikes: Array[String] = []
var _current_column: int = 0  # 0 = likes, 1 = dislikes
var _current_index: int = 0

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var likes_list: VBoxContainer = $MarginContainer/VBox/HBox/LikesPanel/LikesList
@onready var dislikes_list: VBoxContainer = $MarginContainer/VBox/HBox/DislikesPanel/DislikesList
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel
@onready var confirm_button: Button = $MarginContainer/VBox/ConfirmButton


func _ready() -> void:
	hide()


func open_dialog(character: CharacterData) -> void:
	_character = character
	_selected_likes.clear()
	_selected_dislikes.clear()
	_current_column = 0
	_current_index = 0

	title_label.text = "%s - Choose Food Preferences" % character.display_name

	_refresh_display()
	show()
	GameManager.push_pause("preference_selection_dialog")


func close_dialog() -> void:
	hide()
	GameManager.pop_pause("preference_selection_dialog")
	dialog_cancelled.emit()


func _refresh_display() -> void:
	_refresh_category_list(likes_list, true)
	_refresh_category_list(dislikes_list, false)
	_update_hint()
	_update_confirm_button()
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_selection_visuals()


func _refresh_category_list(list_container: VBoxContainer, is_likes_column: bool) -> void:
	## Populate a column with category buttons
	for child in list_container.get_children():
		child.queue_free()

	var selected_in_column: Array[String] = _selected_likes if is_likes_column else _selected_dislikes
	var selected_in_other: Array[String] = _selected_dislikes if is_likes_column else _selected_likes
	var selected_icon := "♥" if is_likes_column else "✗"
	var selected_color := Color(0.5, 1.0, 0.5) if is_likes_column else Color(1.0, 0.5, 0.5)

	for category in FOOD_CATEGORIES:
		var btn := Button.new()
		btn.text = CATEGORY_NAMES.get(category, category.capitalize())
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(150, 30)

		if category in selected_in_column:
			btn.text = "[%s] %s" % [selected_icon, btn.text]
			btn.modulate = selected_color
		elif category in selected_in_other:
			btn.modulate = Color(0.5, 0.5, 0.5)  # Grey if selected in other column
		else:
			btn.text = "[ ] " + btn.text

		list_container.add_child(btn)


func _update_selection_visuals() -> void:
	var likes_buttons := likes_list.get_children()
	var dislikes_buttons := dislikes_list.get_children()

	# Reset all button styles
	for btn in likes_buttons:
		if btn is Button:
			btn.flat = true
	for btn in dislikes_buttons:
		if btn is Button:
			btn.flat = true

	# Highlight current selection
	if _current_column == 0 and _current_index < likes_buttons.size():
		var btn: Button = likes_buttons[_current_index]
		btn.flat = false
		btn.grab_focus()
	elif _current_column == 1 and _current_index < dislikes_buttons.size():
		var btn: Button = dislikes_buttons[_current_index]
		btn.flat = false
		btn.grab_focus()


func _update_hint() -> void:
	var likes_remaining := 2 - _selected_likes.size()
	var dislikes_remaining := 2 - _selected_dislikes.size()

	var hint_parts: Array[String] = []
	if likes_remaining > 0:
		hint_parts.append("Select %d more LIKE%s" % [likes_remaining, "S" if likes_remaining > 1 else ""])
	if dislikes_remaining > 0:
		hint_parts.append("Select %d more DISLIKE%s" % [dislikes_remaining, "S" if dislikes_remaining > 1 else ""])

	if hint_parts.is_empty():
		hint_label.text = "Ready! Press E to confirm or Q to cancel"
	else:
		hint_label.text = " | ".join(hint_parts) + " | A/D: Switch | W/S: Select | E: Toggle | Q: Cancel"


func _update_confirm_button() -> void:
	var can_confirm := _selected_likes.size() == 2 and _selected_dislikes.size() == 2
	confirm_button.disabled = not can_confirm
	confirm_button.text = "Confirm (E)" if can_confirm else "Select 2 Likes & 2 Dislikes"


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Navigation
	if event.is_action_pressed("move_up"):
		_current_index = maxi(0, _current_index - 1)
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_current_index = mini(FOOD_CATEGORIES.size() - 1, _current_index + 1)
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		_current_column = 0
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_current_column = 1
		_update_selection_visuals()
		get_viewport().set_input_as_handled()

	# Toggle selection or confirm
	if event.is_action_pressed("accept"):
		if _can_confirm():
			_confirm_selection()
		else:
			_toggle_current_selection()
		get_viewport().set_input_as_handled()

	# Cancel
	if event.is_action_pressed("back"):
		close_dialog()
		get_viewport().set_input_as_handled()


func _toggle_current_selection() -> void:
	if _current_index >= FOOD_CATEGORIES.size():
		return

	var category: String = FOOD_CATEGORIES[_current_index]

	if _current_column == 0:
		# Toggling likes
		if category in _selected_likes:
			_selected_likes.erase(category)
		elif category not in _selected_dislikes and _selected_likes.size() < 2:
			_selected_likes.append(category)
	else:
		# Toggling dislikes
		if category in _selected_dislikes:
			_selected_dislikes.erase(category)
		elif category not in _selected_likes and _selected_dislikes.size() < 2:
			_selected_dislikes.append(category)

	_refresh_display()


func _can_confirm() -> bool:
	return _selected_likes.size() == 2 and _selected_dislikes.size() == 2


func _confirm_selection() -> void:
	if not _can_confirm():
		return

	hide()
	GameManager.pop_pause("preference_selection_dialog")
	preferences_selected.emit(Array(_selected_likes), Array(_selected_dislikes))
