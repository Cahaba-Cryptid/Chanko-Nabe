extends Control
class_name VendiShop
## Vendi vending machine shop interface with 3-column layout

signal item_purchased(item: Dictionary, character: CharacterData)
signal shop_closed

const ITEMS_PATH := "res://data/vendi_items.json"
const HOLD_TIME_REQUIRED := 0.5  # Seconds to hold V to purchase

# Item list (left column)
@onready var scroll_container: ScrollContainer = $Panel/MarginContainer/HBox/ItemListPanel/ItemListVBox/ItemListScroll
@onready var items_container: VBoxContainer = $Panel/MarginContainer/HBox/ItemListPanel/ItemListVBox/ItemListScroll/ItemsContainer

# Description panel (middle column)
@onready var item_image: TextureRect = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/ItemImage
@onready var item_name_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/ItemNameLabel
@onready var description_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/DescriptionLabel
@onready var fill_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/StatsVBox/FillLabel
@onready var eat_time_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/StatsVBox/EatTimeLabel
@onready var price_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/StatsVBox/PriceLabel

# Cart panel (right column)
@onready var cart_items_container: VBoxContainer = $Panel/MarginContainer/HBox/CartPanel/CartVBox/CartScroll/CartItemsContainer
@onready var total_label: Label = $Panel/MarginContainer/HBox/CartPanel/CartVBox/TotalLabel
@onready var money_label: Label = $Panel/MarginContainer/HBox/CartPanel/CartVBox/MoneyLabel
@onready var hint_label: Label = $Panel/MarginContainer/HBox/CartPanel/CartVBox/HintLabel

var _items: Array = []
var _item_rows: Array[Control] = []
var _selected_index: int = 0
var _character: CharacterData

# Shopping cart
var _cart: Dictionary = {}  # item_id -> quantity
var _cart_total: int = 0

# Hold to purchase
var _hold_time: float = 0.0
var _is_holding_purchase: bool = false


func _ready() -> void:
	_load_items()
	hide()


func _load_items() -> void:
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if file:
		var json_text := file.get_as_text()
		file.close()
		var json := JSON.new()
		var error := json.parse(json_text)
		if error == OK:
			var data: Dictionary = json.data
			_items = data.get("items", [])


func open_shop(character: CharacterData) -> void:
	_character = character
	_selected_index = 0
	_clear_cart()
	_hold_time = 0.0
	_is_holding_purchase = false
	_create_item_rows()
	_update_description()
	_update_cart_display()
	_update_money_display()
	show()


func close_shop() -> void:
	_character = null
	_clear_cart()
	hide()
	shop_closed.emit()


func _clear_cart() -> void:
	_cart.clear()
	_cart_total = 0


func _process(delta: float) -> void:
	if not visible:
		return

	# Handle hold-to-purchase
	if _is_holding_purchase:
		_hold_time += delta
		_update_hint_progress()
		if _hold_time >= HOLD_TIME_REQUIRED:
			_checkout()
			_hold_time = 0.0
			_is_holding_purchase = false


func _create_item_rows() -> void:
	# Clear existing rows
	_item_rows.clear()
	for child in items_container.get_children():
		child.queue_free()

	# Create row for each item
	for i in range(_items.size()):
		var item: Dictionary = _items[i]
		var row := _create_item_row(item, i)
		items_container.add_child(row)
		_item_rows.append(row)

	# Wait a frame then update visuals
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_update_selection_visuals()


func _create_item_row(item: Dictionary, _index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)

	# Left arrow (remove from cart)
	var left_arrow := Label.new()
	left_arrow.text = "<"
	left_arrow.custom_minimum_size = Vector2(20, 0)
	left_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(left_arrow)

	# Item name
	var name_label := Label.new()
	name_label.text = item.get("name", "???")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Price
	var price_lbl := Label.new()
	price_lbl.text = str(item.get("price", 0))
	price_lbl.custom_minimum_size = Vector2(40, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	row.add_child(price_lbl)

	# Right arrow (add to cart)
	var right_arrow := Label.new()
	right_arrow.text = ">"
	right_arrow.custom_minimum_size = Vector2(20, 0)
	right_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(right_arrow)

	return row


func _update_selection_visuals() -> void:
	for i in range(_item_rows.size()):
		var row := _item_rows[i]
		var item: Dictionary = _items[i]
		var price: int = item.get("price", 0)
		var is_selected := (i == _selected_index)
		var can_afford := GameManager.money >= (_cart_total + price)

		# Get the name label (second child)
		var name_label: Label = row.get_child(1) as Label

		if is_selected:
			# Highlight selected row
			name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			# Show arrows more prominently
			(row.get_child(0) as Label).add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			(row.get_child(3) as Label).add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		else:
			if can_afford:
				name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			else:
				name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			# Dim arrows for non-selected
			(row.get_child(0) as Label).add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
			(row.get_child(3) as Label).add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))


func _update_description() -> void:
	if _items.is_empty():
		return

	var item: Dictionary = _items[_selected_index]

	if item_name_label:
		item_name_label.text = item.get("name", "???")

	if description_label:
		description_label.text = item.get("description", "")

	if fill_label:
		fill_label.text = "Fill: +%d" % item.get("fill", 0)

	if eat_time_label:
		eat_time_label.text = "Eat Time: %d min" % item.get("eat_time", 0)

	if price_label:
		price_label.text = "Price: %d" % item.get("price", 0)

	# Load image if available
	if item_image:
		var image_path: String = item.get("image", "")
		if not image_path.is_empty() and ResourceLoader.exists(image_path):
			item_image.texture = load(image_path)
		else:
			item_image.texture = null


func _update_cart_display() -> void:
	# Clear existing cart items
	for child in cart_items_container.get_children():
		child.queue_free()

	# Add cart items
	_cart_total = 0
	for item_id in _cart:
		var quantity: int = _cart[item_id]
		if quantity <= 0:
			continue

		# Find item data
		var item_data: Dictionary = {}
		for item in _items:
			if item.get("id", "") == item_id:
				item_data = item
				break

		if item_data.is_empty():
			continue

		var price: int = item_data.get("price", 0)
		_cart_total += price * quantity

		# Create cart row
		var row := HBoxContainer.new()

		var name_lbl := Label.new()
		name_lbl.text = item_data.get("name", "???")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var qty_lbl := Label.new()
		qty_lbl.text = "x%d" % quantity
		qty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(qty_lbl)

		cart_items_container.add_child(row)

	# Update total
	if total_label:
		total_label.text = "Total: %s" % _format_number(_cart_total)


func _update_money_display() -> void:
	if money_label:
		money_label.text = "You have: %s" % _format_number(GameManager.money)


func _update_hint_progress() -> void:
	if hint_label:
		if _is_holding_purchase and _cart_total > 0:
			var progress := _hold_time / HOLD_TIME_REQUIRED
			var bar_length := 10
			var filled := int(progress * bar_length)
			var bar := "[" + "=".repeat(filled) + " ".repeat(bar_length - filled) + "]"
			hint_label.text = "Purchasing... %s\nQ to Close" % bar
		else:
			hint_label.text = "Hold V to Purchase\nQ to Close"


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Navigation
	if event.is_action_pressed("move_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate(1)
		get_viewport().set_input_as_handled()
	# Add to cart (right)
	elif event.is_action_pressed("move_right"):
		_add_to_cart()
		get_viewport().set_input_as_handled()
	# Remove from cart (left)
	elif event.is_action_pressed("move_left"):
		_remove_from_cart()
		get_viewport().set_input_as_handled()
	# Hold V to purchase
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_V:
			if key_event.pressed and not key_event.echo:
				_is_holding_purchase = true
				_hold_time = 0.0
			elif not key_event.pressed:
				_is_holding_purchase = false
				_hold_time = 0.0
				_update_hint_progress()
			get_viewport().set_input_as_handled()
	# Close shop
	elif event.is_action_pressed("back"):
		close_shop()
		get_viewport().set_input_as_handled()


func _navigate(direction: int) -> void:
	if _items.is_empty():
		return

	_selected_index = wrapi(_selected_index + direction, 0, _items.size())
	_update_selection_visuals()
	_update_description()
	_scroll_to_selected()


func _scroll_to_selected() -> void:
	if not scroll_container or _item_rows.is_empty():
		return

	if _selected_index < 0 or _selected_index >= _item_rows.size():
		return

	var row := _item_rows[_selected_index]
	var row_top := row.position.y
	var row_bottom := row_top + row.size.y
	var scroll_top := scroll_container.scroll_vertical
	var scroll_height := scroll_container.size.y
	var scroll_bottom := scroll_top + scroll_height

	if row_top < scroll_top:
		scroll_container.scroll_vertical = int(row_top)
	elif row_bottom > scroll_bottom:
		scroll_container.scroll_vertical = int(row_bottom - scroll_height)


func _add_to_cart() -> void:
	if _items.is_empty() or not _character:
		return

	var item: Dictionary = _items[_selected_index]
	var item_id: String = item.get("id", "")
	var price: int = item.get("price", 0)

	# Check affordability
	if GameManager.money < (_cart_total + price):
		return

	# Add to cart
	if _cart.has(item_id):
		_cart[item_id] += 1
	else:
		_cart[item_id] = 1

	_update_cart_display()
	_update_selection_visuals()
	_update_money_display()


func _remove_from_cart() -> void:
	if _items.is_empty():
		return

	var item: Dictionary = _items[_selected_index]
	var item_id: String = item.get("id", "")

	# Check if item is in cart
	if not _cart.has(item_id) or _cart[item_id] <= 0:
		return

	# Remove from cart
	_cart[item_id] -= 1
	if _cart[item_id] <= 0:
		_cart.erase(item_id)

	_update_cart_display()
	_update_selection_visuals()
	_update_money_display()


func _checkout() -> void:
	if _cart.is_empty() or not _character:
		return

	# Final affordability check
	if not GameManager.can_afford(_cart_total):
		return

	# Process purchase
	GameManager.spend_money(_cart_total)

	# Add all items to inventory
	for item_id in _cart:
		var quantity: int = _cart[item_id]

		# Find item data
		var item_data: Dictionary = {}
		for item in _items:
			if item.get("id", "") == item_id:
				item_data = item
				break

		if item_data.is_empty():
			continue

		var item_name: String = item_data.get("name", "???")
		var item_price: int = item_data.get("price", 0)

		# Add to inventory
		for _i in range(quantity):
			_character.add_to_inventory(item_data)

		# Log the purchase
		var total_item_cost := item_price * quantity
		var activity_msg: String
		if quantity == 1:
			activity_msg = "%s bought %s for $%d" % [_character.display_name, item_name, total_item_cost]
		else:
			activity_msg = "%s bought %dx %s for $%d" % [_character.display_name, quantity, item_name, total_item_cost]
		TimeManager.activity_logged.emit(activity_msg)

		item_purchased.emit(item_data, _character)

	# Skip time based on weight
	var time_to_skip := _calculate_time_skip()
	TimeManager.skip_time(time_to_skip)

	close_shop()


func _calculate_time_skip() -> int:
	## Shopping time is based on weight - heavier characters take longer.
	## Base time: 10 minutes
	## Weight penalty: +10 minutes per 50 weight above 100
	if _cart_total == 0:
		return 0

	const BASE_TIME := 10
	const WEIGHT_THRESHOLD := 100
	const WEIGHT_INCREMENT := 50
	const TIME_PER_INCREMENT := 10

	var time_skip := BASE_TIME

	if _character:
		var excess_weight := maxi(0, _character.weight - WEIGHT_THRESHOLD)
		@warning_ignore("integer_division")
		var weight_penalty := (excess_weight / WEIGHT_INCREMENT) * TIME_PER_INCREMENT
		time_skip += weight_penalty

	return time_skip


func _format_number(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result
