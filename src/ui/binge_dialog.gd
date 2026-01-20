extends PanelContainer
class_name BingeDialog
## Dialog for managing food queue and starting a binge session

signal binge_started(total_fill: int)
signal dialog_closed

var _character: CharacterData
var _selected_index: int = 0

# Hold V to start binge
const HOLD_DURATION := 0.5  # seconds to hold V
var _hold_timer: float = 0.0
var _is_holding: bool = false

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var inventory_list: VBoxContainer = $MarginContainer/VBox/HBox/InventoryPanel/InventoryScroll/InventoryList
@onready var queue_list: VBoxContainer = $MarginContainer/VBox/HBox/QueuePanel/QueueScroll/QueueList
@onready var stomach_label: Label = $MarginContainer/VBox/StomachLabel
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel


func _ready() -> void:
	hide()


func open_dialog(character: CharacterData) -> void:
	_character = character
	_selected_index = 0
	_hold_timer = 0.0
	_is_holding = false
	_refresh_display()
	show()
	GameManager.is_paused = true


func _process(delta: float) -> void:
	if not visible:
		return

	# Handle hold V to start binge
	if _is_holding:
		_hold_timer += delta
		_update_hint()
		if _hold_timer >= HOLD_DURATION:
			_start_binge()
			_is_holding = false
			_hold_timer = 0.0


func close_dialog() -> void:
	hide()
	GameManager.is_paused = false
	dialog_closed.emit()


func _refresh_display() -> void:
	if not _character:
		return

	title_label.text = "%s - Binge" % _character.display_name
	_refresh_inventory_list()
	_refresh_queue_list()
	_update_stomach_display()
	_update_hint()


func _refresh_inventory_list() -> void:
	for child in inventory_list.get_children():
		child.queue_free()

	var food_items := _get_food_items_from_inventory()
	var remaining_capacity := _get_remaining_capacity()

	if food_items.is_empty():
		var label := Label.new()
		label.text = "(No food items)"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		inventory_list.add_child(label)
	else:
		for i in range(food_items.size()):
			var item := food_items[i]
			var fill: int = item.get("fill", 0)
			var btn := Button.new()
			btn.text = "%s x%d (Fill: %d)" % [item.get("name", "???"), item.get("quantity", 1), fill]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(180, 30)

			# Grey out items that won't fit
			if fill > remaining_capacity:
				btn.modulate = Color(0.5, 0.5, 0.5)

			inventory_list.add_child(btn)

	await get_tree().process_frame
	_update_selection_visuals()


func _refresh_queue_list() -> void:
	for child in queue_list.get_children():
		child.queue_free()

	if _character.food_queue.is_empty():
		var label := Label.new()
		label.text = "(Queue empty)"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		queue_list.add_child(label)
	else:
		for i in range(_character.food_queue.size()):
			var item := _character.food_queue[i]
			var btn := Button.new()
			btn.text = "%s x%d" % [item.get("name", "???"), item.get("quantity", 1)]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(180, 30)
			queue_list.add_child(btn)

	await get_tree().process_frame
	_update_selection_visuals()


func _update_stomach_display() -> void:
	var queue_fill := _get_total_queue_fill()
	var projected := _character.stomach_fullness + queue_fill
	var time_preview := _get_binge_time_preview()

	if _character.food_queue.is_empty():
		stomach_label.text = "Stomach: %d/%d" % [
			_character.stomach_fullness,
			_character.stomach_capacity
		]
	else:
		stomach_label.text = "Stomach: %d/%d (After: %d) | Time: %s" % [
			_character.stomach_fullness,
			_character.stomach_capacity,
			mini(projected, _character.stomach_capacity),
			time_preview
		]


func _get_binge_time_preview() -> String:
	## Returns formatted time string for how long the binge will take
	var base_duration := GameManager.get_station_duration("Binge")
	var item_count := _character.get_food_queue_count()
	# Scale duration based on items in queue (more items = longer binge)
	var total_duration := base_duration + (item_count * 10.0)  # +10 min per item

	var hours := int(total_duration / 60.0)
	var minutes := int(total_duration) % 60

	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	else:
		return "%dm" % minutes


func _update_hint() -> void:
	if _is_holding:
		@warning_ignore("narrowing_conversion")
		var progress := mini(_hold_timer / HOLD_DURATION, 1.0)
		var bar_length := 10
		@warning_ignore("narrowing_conversion")
		var filled := int(progress * bar_length)
		var bar := "[" + "=".repeat(filled) + " ".repeat(bar_length - filled) + "]"
		hint_label.text = "Starting binge... %s" % bar
	elif _character.food_queue.is_empty():
		hint_label.text = "Up/Down: Select | D: Add to Queue | Q: Back"
	else:
		hint_label.text = "Up/Down: Select | A: Remove | D: Add | Hold V: Start Binge | Q: Back"


func _get_food_items_from_inventory() -> Array[Dictionary]:
	var food_items: Array[Dictionary] = []
	for item in _character.inventory:
		if item.get("type", "") == "food":
			food_items.append(item)
	return food_items


func _get_total_queue_fill() -> int:
	var total := 0
	for item in _character.food_queue:
		var fill: int = item.get("fill", 0)
		var qty: int = item.get("quantity", 1)
		total += fill * qty
	return total


func _get_remaining_capacity() -> int:
	## Returns how much more fill can be added to queue before hitting capacity
	var queue_fill := _get_total_queue_fill()
	var projected := _character.stomach_fullness + queue_fill
	return maxi(0, _character.stomach_capacity - projected)


func _is_stomach_full_with_queue() -> bool:
	## Returns true if queue already fills character to capacity
	return _get_remaining_capacity() <= 0


func _update_selection_visuals() -> void:
	# Update inventory list selection
	var inv_children := inventory_list.get_children()
	for i in range(inv_children.size()):
		var child := inv_children[i]
		if child is Button:
			if i == _selected_index:
				_apply_selected_style(child)
			else:
				child.remove_theme_stylebox_override("normal")


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

	# Handle hold V to start binge
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_V:
			if key_event.pressed and not key_event.echo:
				if not _character.food_queue.is_empty():
					_is_holding = true
					_hold_timer = 0.0
			elif not key_event.pressed:
				_is_holding = false
				_hold_timer = 0.0
				_update_hint()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("back"):
		close_dialog()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_up"):
		_navigate_vertical(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_vertical(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_add_to_queue()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		_remove_from_queue()
		get_viewport().set_input_as_handled()


func _navigate_vertical(direction: int) -> void:
	var food_items := _get_food_items_from_inventory()
	if not food_items.is_empty():
		_selected_index = wrapi(_selected_index + direction, 0, food_items.size())
	_update_selection_visuals()


func _add_to_queue() -> void:
	## Add selected inventory item to queue (D key)
	var food_items := _get_food_items_from_inventory()
	if _selected_index >= 0 and _selected_index < food_items.size():
		var item := food_items[_selected_index]
		var fill: int = item.get("fill", 0)

		# Only add if it fits within remaining capacity
		if fill <= _get_remaining_capacity():
			_character.add_to_food_queue(item)
			_refresh_display()


func _remove_from_queue() -> void:
	## Remove one of the selected item type from queue back to inventory (A key)
	var food_items := _get_food_items_from_inventory()
	if _selected_index < 0 or _selected_index >= food_items.size():
		return

	var selected_item := food_items[_selected_index]
	var item_id: String = selected_item.get("id", "")

	# Find this item in the queue and remove one
	for queue_item in _character.food_queue:
		if queue_item.get("id", "") == item_id:
			var removed := _character.remove_from_food_queue(item_id)
			if not removed.is_empty():
				_character.add_to_inventory(removed)
			_refresh_display()
			return


func _start_binge() -> void:
	if _character.food_queue.is_empty():
		return

	var total_fill := _get_total_queue_fill()
	binge_started.emit(total_fill)
	close_dialog()
