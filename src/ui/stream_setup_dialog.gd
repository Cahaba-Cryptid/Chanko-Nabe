extends PanelContainer
class_name StreamSetupDialog
## Dialog for setting up a stream - select kit and add inventory items

signal stream_started(stream_data: Dictionary)
signal dialog_closed

var _character: CharacterData
var _selected_column: int = 0  # 0 = kits, 1 = inventory
var _selected_kit_index: int = 0
var _selected_inv_index: int = 0
var _current_kit: Dictionary = {}
var _stream_items: Array[Dictionary] = []  # Items queued for stream
var _kits: Array[Dictionary] = []

# Hold V to start stream
const HOLD_DURATION := 0.5
var _hold_timer: float = 0.0
var _is_holding: bool = false

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var kits_list: VBoxContainer = $MarginContainer/VBox/HBox/KitsPanel/KitsScroll/KitsList
@onready var inventory_list: VBoxContainer = $MarginContainer/VBox/HBox/InventoryPanel/InventoryScroll/InventoryList
@onready var queue_list: VBoxContainer = $MarginContainer/VBox/HBox/QueuePanel/QueueScroll/QueueList
@onready var preview_label: Label = $MarginContainer/VBox/PreviewLabel
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel


func _ready() -> void:
	hide()
	_load_kits()


func _load_kits() -> void:
	var file := FileAccess.open("res://data/stream_kits.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var error := json.parse(file.get_as_text())
		if error == OK:
			var data: Dictionary = json.data
			for kit in data.get("kits", []):
				_kits.append(kit)
		file.close()


func open_dialog(character: CharacterData) -> void:
	_character = character
	_selected_column = 0
	_selected_kit_index = 0
	_selected_inv_index = 0
	_current_kit = _kits[0] if not _kits.is_empty() else {}
	_stream_items.clear()
	_hold_timer = 0.0
	_is_holding = false
	_refresh_display()
	show()
	GameManager.push_pause("stream_setup_dialog")


func _process(delta: float) -> void:
	if not visible:
		return

	if _is_holding:
		_hold_timer += delta
		_update_hint()
		if _hold_timer >= HOLD_DURATION:
			_start_stream()
			_is_holding = false
			_hold_timer = 0.0


func close_dialog() -> void:
	# Return any queued items back to inventory
	for item in _stream_items:
		var qty: int = item.get("quantity", 1)
		for _i in range(qty):
			_character.add_to_inventory(item)
	_stream_items.clear()

	hide()
	GameManager.pop_pause("stream_setup_dialog")
	dialog_closed.emit()


func _refresh_display() -> void:
	if not _character:
		return

	title_label.text = "%s - Stream Setup" % _character.display_name
	_refresh_kits_list()
	_refresh_inventory_list()
	_refresh_queue_list()
	_update_preview()
	_update_hint()


func _refresh_kits_list() -> void:
	for child in kits_list.get_children():
		child.queue_free()

	for i in range(_kits.size()):
		var kit := _kits[i]
		var btn := Button.new()
		var price: int = kit.get("price", 0)
		var milk_price: int = kit.get("milk_price", 0)
		var requires_lactating: bool = kit.get("requires_lactating", false)

		# Build display text with appropriate currency
		if milk_price > 0:
			btn.text = "%s (%d milk)" % [kit.get("name", "???"), milk_price]
		elif price > 0:
			btn.text = "%s ($%d)" % [kit.get("name", "???"), price]
		else:
			btn.text = kit.get("name", "???")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(140, 30)

		# Grey out if can't afford or doesn't meet requirements
		var can_use := true
		var required_kinks: Array = kit.get("required_kinks", [])
		if requires_lactating and not _character.is_lactating:
			can_use = false
		if price > 0 and price > GameManager.money:
			can_use = false
		if milk_price > 0:
			var effective_milk := _get_effective_milk_value()
			if milk_price > effective_milk:
				can_use = false
		if not required_kinks.is_empty() and not _character.has_required_kinks(required_kinks):
			can_use = false

		if not can_use:
			btn.modulate = Color(0.5, 0.5, 0.5)

		kits_list.add_child(btn)

	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_selection_visuals()


func _refresh_inventory_list() -> void:
	for child in inventory_list.get_children():
		child.queue_free()

	var food_items := _get_food_items_from_inventory()
	var remaining_capacity := _get_remaining_capacity()

	if food_items.is_empty():
		var label := Label.new()
		label.text = "(No items)"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		inventory_list.add_child(label)
	else:
		for i in range(food_items.size()):
			var item := food_items[i]
			var fill: int = item.get("fill", 0)
			var btn := Button.new()
			btn.text = "%s x%d" % [item.get("name", "???"), item.get("quantity", 1)]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(140, 30)

			# Grey out items that won't fit
			if fill > remaining_capacity:
				btn.modulate = Color(0.5, 0.5, 0.5)

			inventory_list.add_child(btn)

	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_selection_visuals()


func _refresh_queue_list() -> void:
	for child in queue_list.get_children():
		child.queue_free()

	# Show kit contents first
	if not _current_kit.is_empty():
		var contents: Array = _current_kit.get("contents", [])
		if not contents.is_empty():
			var kit_label := Label.new()
			kit_label.text = "-- Kit Items --"
			kit_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
			queue_list.add_child(kit_label)

			for content in contents:
				var label := Label.new()
				label.text = "  %s x%d" % [_get_item_name(content.get("id", "")), content.get("quantity", 1)]
				label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
				queue_list.add_child(label)

	# Show added inventory items
	if not _stream_items.is_empty():
		var added_label := Label.new()
		added_label.text = "-- Added Items --"
		added_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
		queue_list.add_child(added_label)

		for item in _stream_items:
			var label := Label.new()
			label.text = "  %s x%d" % [item.get("name", "???"), item.get("quantity", 1)]
			label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
			queue_list.add_child(label)

	if _current_kit.is_empty() or (_current_kit.get("contents", []).is_empty() and _stream_items.is_empty()):
		var label := Label.new()
		label.text = "(Empty stream)"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		queue_list.add_child(label)


func _get_item_name(item_id: String) -> String:
	## Look up item name from vendi_items.json
	var file := FileAccess.open("res://data/vendi_items.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			for item in data.get("items", []):
				if item.get("id", "") == item_id:
					file.close()
					return item.get("name", item_id)
		file.close()
	return item_id


func _update_preview() -> void:
	var kit_price: int = _current_kit.get("price", 0)
	var milk_price: int = _current_kit.get("milk_price", 0)
	var base_duration: int = _current_kit.get("base_duration", 120)
	var quality_mult: float = _current_kit.get("quality_multiplier", 1.0)

	# Calculate total fill from kit contents
	var kit_fill := _get_kit_fill()
	var added_fill := _get_added_items_fill()
	var total_fill := kit_fill + added_fill

	# Quality bonus scales with fill value: +0.01x per fill point from added items
	# (e.g., 100 fill item = +1.0x, 10 fill item = +0.1x)
	var extra_mult := added_fill * 0.01
	var final_mult := quality_mult + extra_mult

	# Duration increases with added items (scales with fill too)
	@warning_ignore("integer_division")
	var added_duration := added_fill / 5  # 1 min per 5 fill
	var total_duration := base_duration + added_duration

	@warning_ignore("integer_division")
	var hours := total_duration / 60
	var minutes := total_duration % 60
	var time_str := "%dh %dm" % [hours, minutes] if hours > 0 else "%dm" % minutes

	# Projected stomach fill
	var projected := _character.stomach_fullness + total_fill

	# Build cost string based on currency type
	var cost_str: String
	if milk_price > 0:
		cost_str = "%d milk" % milk_price
	else:
		cost_str = "$%d" % kit_price

	preview_label.text = "Kit: %s | Time: %s | Quality: %.2fx | Stomach: %d/%d -> %d" % [
		cost_str, time_str, final_mult,
		_character.stomach_fullness, _character.stomach_capacity,
		mini(projected, _character.stomach_capacity)
	]


func _update_hint() -> void:
	if _is_holding:
		@warning_ignore("narrowing_conversion")
		var progress := mini(_hold_timer / HOLD_DURATION, 1.0)
		var bar_length := 10
		@warning_ignore("narrowing_conversion")
		var filled := int(progress * bar_length)
		var bar := "[" + "=".repeat(filled) + " ".repeat(bar_length - filled) + "]"
		hint_label.text = "Starting stream... %s" % bar
	elif _selected_column == 0:
		hint_label.text = "Up/Down: Select Kit | Right: Add Items | Hold V: Start | Q: Back"
	else:
		hint_label.text = "Up/Down: Select | D: Add | A: Remove | Left: Kits | Hold V: Start | Q: Back"


func _get_food_items_from_inventory() -> Array[Dictionary]:
	var food_items: Array[Dictionary] = []
	for item in _character.inventory:
		# Include food and buff items
		var item_type: String = item.get("type", "")
		if item_type == "food" or item_type == "buff":
			food_items.append(item)
	return food_items


func _get_kit_fill() -> int:
	## Calculate total fill from current kit contents
	var total := 0
	var contents: Array = _current_kit.get("contents", [])
	for content in contents:
		var item_id: String = content.get("id", "")
		var qty: int = content.get("quantity", 1)
		var fill := _get_item_fill(item_id)
		total += fill * qty
	return total


func _get_item_fill(item_id: String) -> int:
	## Look up fill value from vendi_items.json
	var file := FileAccess.open("res://data/vendi_items.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			for item in data.get("items", []):
				if item.get("id", "") == item_id:
					file.close()
					return item.get("fill", 0)
		file.close()
	return 0


func _get_added_items_fill() -> int:
	var total := 0
	for item in _stream_items:
		var fill: int = item.get("fill", 0)
		var qty: int = item.get("quantity", 1)
		total += fill * qty
	return total


func _get_total_added_items_count() -> int:
	var count := 0
	for item in _stream_items:
		count += item.get("quantity", 1)
	return count


func _get_remaining_capacity() -> int:
	var kit_fill := _get_kit_fill()
	var added_fill := _get_added_items_fill()
	var projected := _character.stomach_fullness + kit_fill + added_fill
	return maxi(0, _character.stomach_capacity - projected)


func _can_use_current_kit() -> bool:
	## Check if current kit can be used (affordable and meets requirements)
	var kit_price: int = _current_kit.get("price", 0)
	var milk_price: int = _current_kit.get("milk_price", 0)
	var requires_lactating: bool = _current_kit.get("requires_lactating", false)
	var required_kinks: Array = _current_kit.get("required_kinks", [])

	# Check lactation requirement
	if requires_lactating and not _character.is_lactating:
		return false

	# Check kink requirements
	if not required_kinks.is_empty() and not _character.has_required_kinks(required_kinks):
		return false

	# Check cash cost
	if kit_price > 0 and GameManager.money < kit_price:
		return false

	# Check milk cost (Hucow milk_value_bonus increases purchasing power)
	if milk_price > 0:
		var effective_milk := _get_effective_milk_value()
		if effective_milk < milk_price:
			return false

	return true


func _get_effective_milk_value() -> int:
	## Get milk value with Hucow bonus applied (increases purchasing power)
	var milk_value_bonus: float = _character.get_archetype_passive("milk_value_bonus", 0.0)
	return int(float(_character.milk_current) * (1.0 + milk_value_bonus))


func _update_selection_visuals() -> void:
	# Update kit list selection
	var kit_children := kits_list.get_children()
	for i in range(kit_children.size()):
		var child := kit_children[i]
		if child is Button:
			if i == _selected_kit_index and _selected_column == 0:
				_apply_selected_style(child)
			else:
				child.remove_theme_stylebox_override("normal")

	# Update inventory list selection
	var inv_children := inventory_list.get_children()
	for i in range(inv_children.size()):
		var child := inv_children[i]
		if child is Button:
			if i == _selected_inv_index and _selected_column == 1:
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

	# Handle hold V to start stream
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_V:
			if key_event.pressed and not key_event.echo:
				# Check if can afford and meets requirements
				if _can_use_current_kit():
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
		if _selected_column == 0:
			_selected_column = 1
			_update_selection_visuals()
			_update_hint()
		else:
			_add_to_stream()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		if _selected_column == 1:
			_selected_column = 0
			_update_selection_visuals()
			_update_hint()
		else:
			_remove_from_stream()
		get_viewport().set_input_as_handled()


func _navigate_vertical(direction: int) -> void:
	if _selected_column == 0:
		# Navigating kits
		if not _kits.is_empty():
			_selected_kit_index = wrapi(_selected_kit_index + direction, 0, _kits.size())
			_current_kit = _kits[_selected_kit_index]
			_refresh_queue_list()
			_update_preview()
	else:
		# Navigating inventory
		var food_items := _get_food_items_from_inventory()
		if not food_items.is_empty():
			_selected_inv_index = wrapi(_selected_inv_index + direction, 0, food_items.size())
	_update_selection_visuals()


func _add_to_stream() -> void:
	## Add selected inventory item to stream queue (D key in inventory column)
	if _selected_column != 1:
		return

	var food_items := _get_food_items_from_inventory()
	if _selected_inv_index >= 0 and _selected_inv_index < food_items.size():
		var item := food_items[_selected_inv_index]
		var fill: int = item.get("fill", 0)

		# Only add if it fits within remaining capacity
		if fill <= _get_remaining_capacity():
			# Remove from character inventory
			var item_id: String = item.get("id", "")
			for i in range(_character.inventory.size()):
				if _character.inventory[i].get("id", "") == item_id:
					var inv_item := _character.inventory[i]
					var qty: int = inv_item.get("quantity", 1)
					if qty > 1:
						inv_item["quantity"] = qty - 1
					else:
						_character.inventory.remove_at(i)
					break

			# Add to stream items (stacking)
			var found := false
			for stream_item in _stream_items:
				if stream_item.get("id", "") == item_id:
					stream_item["quantity"] = stream_item.get("quantity", 1) + 1
					found = true
					break

			if not found:
				var new_item := item.duplicate()
				new_item["quantity"] = 1
				_stream_items.append(new_item)

			_refresh_display()


func _remove_from_stream() -> void:
	## Remove last added item from stream queue back to inventory (A key)
	if _stream_items.is_empty():
		return

	# Get last item
	var last_item := _stream_items[_stream_items.size() - 1]
	var qty: int = last_item.get("quantity", 1)

	# Return one to inventory
	_character.add_to_inventory(last_item)

	# Update stream items
	if qty > 1:
		last_item["quantity"] = qty - 1
	else:
		_stream_items.pop_back()

	_refresh_display()


func _start_stream() -> void:
	# Final affordability check
	if not _can_use_current_kit():
		return

	var kit_price: int = _current_kit.get("price", 0)
	var milk_price: int = _current_kit.get("milk_price", 0)

	# Pay for kit (cash or milk)
	if kit_price > 0:
		GameManager.spend_money(kit_price)
	if milk_price > 0:
		# Hucow milk_value_bonus means they spend less actual milk
		var milk_value_bonus: float = _character.get_archetype_passive("milk_value_bonus", 0.0)
		var actual_milk_spent := int(float(milk_price) / (1.0 + milk_value_bonus))
		_character.spend_milk(actual_milk_spent)

	# Build stream data
	var base_duration: int = _current_kit.get("base_duration", 120)
	var quality_mult: float = _current_kit.get("quality_multiplier", 1.0)
	var added_fill := _get_added_items_fill()

	# Quality bonus scales with fill: +0.01x per fill point from added items
	var extra_mult := added_fill * 0.01

	# Duration scales with fill: 1 min per 5 fill
	@warning_ignore("integer_division")
	var added_duration := added_fill / 5

	var stream_data := {
		"kit_id": _current_kit.get("id", "standard_stream"),
		"kit_name": _current_kit.get("name", "Standard Stream"),
		"kit_contents": _current_kit.get("contents", []),
		"added_items": _stream_items.duplicate(true),
		"total_duration": base_duration + added_duration,
		"quality_multiplier": quality_mult + extra_mult,
		"total_fill": _get_kit_fill() + added_fill,
		"milk_spent": milk_price,
		"stream_kinks": _current_kit.get("stream_kinks", [])
	}

	# Clear stream items (they're now part of the stream, not returning to inventory)
	_stream_items.clear()

	stream_started.emit(stream_data)
	hide()
	GameManager.pop_pause("stream_setup_dialog")
