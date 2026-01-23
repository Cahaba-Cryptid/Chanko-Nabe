extends Control
class_name ItemsMenu
## Character inventory menu for eating food items

signal item_eaten(item: Dictionary, character: CharacterData)
signal menu_closed

@onready var title_label: Label = $Panel/VBox/Header/TitleLabel
@onready var character_label: Label = $Panel/VBox/Header/CharacterLabel
@onready var stomach_label: Label = $Panel/VBox/Header/StomachLabel
@onready var items_container: VBoxContainer = $Panel/VBox/ScrollContainer/ItemsContainer
@onready var description_label: Label = $Panel/VBox/Footer/DescriptionLabel
@onready var cart_label: Label = $Panel/VBox/Footer/CartSection/CartLabel
@onready var cart_fill_label: Label = $Panel/VBox/Footer/CartSection/CartFillLabel
@onready var time_skip_label: Label = $Panel/VBox/Footer/CartSection/TimeSkipLabel
@onready var hint_label: Label = $Panel/VBox/Footer/HintLabel

var _item_buttons: Array[Button] = []
var _selected_index: int = 0
var _character: CharacterData

# Eating queue (similar to shopping cart)
var _eat_queue: Array[Dictionary] = []
var _queue_fill: int = 0
var _queue_time: int = 0


func _ready() -> void:
	hide()


func open_menu(character: CharacterData) -> void:
	_character = character
	_selected_index = 0
	_clear_queue()
	_create_item_buttons()
	_refresh_display()
	show()


func close_menu() -> void:
	_character = null
	_clear_queue()
	hide()
	menu_closed.emit()


func _clear_queue() -> void:
	_eat_queue.clear()
	_queue_fill = 0
	_queue_time = 0


func _refresh_display() -> void:
	if not _character:
		return

	if title_label:
		title_label.text = "INVENTORY"

	if character_label:
		character_label.text = _character.display_name

	if stomach_label:
		var projected_fill := _character.stomach_fullness + _queue_fill
		stomach_label.text = "Stomach: %d/%d" % [projected_fill, _character.stomach_capacity]

	_update_description()
	_update_queue_display()


func _create_item_buttons() -> void:
	# Clear existing buttons
	_item_buttons.clear()
	for child in items_container.get_children():
		child.queue_free()

	if not _character or _character.inventory.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items in inventory."
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		items_container.add_child(empty_label)
		return

	# Create button for each inventory item
	for i in range(_character.inventory.size()):
		var item: Dictionary = _character.inventory[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		var quantity: int = item.get("quantity", 1)
		var fill: int = item.get("fill", 0)
		var eat_time: int = item.get("eat_time", 10)
		var name_str := "%dx %s" % [quantity, item.get("name", "???")]
		btn.text = "  %s    +%d    %dm" % [name_str, fill, eat_time]

		items_container.add_child(btn)
		_item_buttons.append(btn)

	# Wait a frame for buttons to be added, then update visuals
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_selection_visuals()


func _update_selection_visuals() -> void:
	for i in range(_item_buttons.size()):
		var btn := _item_buttons[i]
		var item: Dictionary = _character.inventory[i]
		var fill: int = item.get("fill", 0)

		# Check if stomach can fit including queue
		var can_fit: bool = (_character.stomach_fullness + _queue_fill + fill) <= _character.stomach_capacity
		# Check if item has any remaining quantity (after queue consumption)
		var available := _get_available_quantity(item)
		var is_selected := (i == _selected_index)

		# Grey out if can't fit or none available
		if not can_fit or available <= 0:
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0)

		# Selection highlight
		if is_selected:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.2, 0.2)
			style.border_color = Color(1.0, 0.85, 0.4)
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", style)
		else:
			btn.remove_theme_stylebox_override("normal")


func _get_available_quantity(item: Dictionary) -> int:
	## Get quantity available after accounting for items in queue
	var item_id: String = item.get("id", "")
	var inventory_qty: int = item.get("quantity", 0)
	var queued_qty := 0

	for queued_item in _eat_queue:
		if queued_item.get("id", "") == item_id:
			queued_qty = queued_item.get("quantity", 0)
			break

	return inventory_qty - queued_qty


func _update_description() -> void:
	if not description_label:
		return

	if _character.inventory.is_empty():
		description_label.text = "Visit Vendi to buy food."
		return

	if _selected_index >= 0 and _selected_index < _character.inventory.size():
		var item: Dictionary = _character.inventory[_selected_index]
		var desc: String = item.get("description", "")
		var fill: int = item.get("fill", 0)

		var can_fit: bool = (_character.stomach_fullness + _queue_fill + fill) <= _character.stomach_capacity
		var available := _get_available_quantity(item)

		if available <= 0:
			desc += " [All queued]"
		elif not can_fit:
			desc += " [Stomach full]"

		description_label.text = desc
	else:
		description_label.text = "Select items to eat."


func _update_queue_display() -> void:
	if not cart_label or not cart_fill_label or not time_skip_label:
		return

	if _eat_queue.is_empty():
		cart_label.text = "To Eat: Nothing"
	else:
		var item_count := 0
		for queued_item in _eat_queue:
			item_count += queued_item.get("quantity", 1)

		if item_count == 1:
			cart_label.text = "To Eat: 1 item"
		else:
			cart_label.text = "To Eat: %d items" % item_count

	cart_fill_label.text = "Fill: +%d" % _queue_fill
	time_skip_label.text = "Time: +%d min" % _queue_time


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("move_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_add_to_queue()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):  # Space to eat
		_eat_queued()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		close_menu()
		get_viewport().set_input_as_handled()


func _navigate(direction: int) -> void:
	if _character.inventory.is_empty():
		return

	_selected_index = wrapi(_selected_index + direction, 0, _character.inventory.size())
	_update_selection_visuals()
	_update_description()


func _add_to_queue() -> void:
	if _character.inventory.is_empty():
		return

	if _selected_index < 0 or _selected_index >= _character.inventory.size():
		return

	var item: Dictionary = _character.inventory[_selected_index]
	var fill: int = item.get("fill", 0)
	var eat_time: int = item.get("eat_time", 10)

	# Check if can fit
	if (_character.stomach_fullness + _queue_fill + fill) > _character.stomach_capacity:
		return

	# Check if any available
	if _get_available_quantity(item) <= 0:
		return

	# Add to queue
	var item_id: String = item.get("id", "")
	var found := false
	for queued_item in _eat_queue:
		if queued_item.get("id", "") == item_id:
			queued_item["quantity"] = queued_item.get("quantity", 1) + 1
			found = true
			break

	if not found:
		var new_queued := item.duplicate()
		new_queued["quantity"] = 1
		_eat_queue.append(new_queued)

	_queue_fill += fill
	_queue_time += eat_time

	_refresh_display()
	_update_selection_visuals()


func _eat_queued() -> void:
	if _eat_queue.is_empty() or not _character:
		return

	# Fill stomach
	_character.eat(_queue_fill)

	# Remove items from inventory and log activities
	for queued_item in _eat_queue:
		var quantity: int = queued_item.get("quantity", 1)
		var item_name: String = queued_item.get("name", "???")
		var item_id: String = queued_item.get("id", "")

		# Remove from inventory
		for _i in range(quantity):
			_remove_from_inventory(item_id)

		# Log the eating
		var activity_msg: String
		if quantity == 1:
			activity_msg = "%s ate %s" % [_character.display_name, item_name]
		else:
			activity_msg = "%s ate %dx %s" % [_character.display_name, quantity, item_name]
		TimeManager.activity_logged.emit(activity_msg)
		print(activity_msg)

		item_eaten.emit(queued_item, _character)

	# Skip time based on eating
	TimeManager.skip_time(_queue_time)

	# Close menu after eating
	close_menu()


func _remove_from_inventory(item_id: String) -> void:
	## Remove one of an item from inventory
	for i in range(_character.inventory.size() - 1, -1, -1):
		var inv_item: Dictionary = _character.inventory[i]
		if inv_item.get("id", "") == item_id:
			var qty: int = inv_item.get("quantity", 1)
			if qty <= 1:
				_character.inventory.remove_at(i)
			else:
				inv_item["quantity"] = qty - 1
			return
