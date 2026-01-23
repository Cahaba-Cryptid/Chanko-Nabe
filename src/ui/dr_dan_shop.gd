extends Control
class_name DrDanShop
## Dr. Dan's Back-Alley Van shop interface with 3-column layout
## Sells cybernetic augments, genetic mutations, and procedures

signal item_purchased(item: Dictionary, character: CharacterData)
signal shop_closed

const ITEMS_PATH := "res://data/dr_dan_items.json"
const HOLD_TIME_REQUIRED := 0.5  # Seconds to hold V to purchase

# Item list (left column)
@onready var scroll_container: ScrollContainer = $Panel/MarginContainer/HBox/ItemListPanel/ItemListVBox/ItemListScroll
@onready var items_container: VBoxContainer = $Panel/MarginContainer/HBox/ItemListPanel/ItemListVBox/ItemListScroll/ItemsContainer

# Description panel (middle column)
@onready var item_image: TextureRect = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/ItemImage
@onready var item_name_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/ItemNameLabel
@onready var description_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/DescriptionLabel
@onready var effect_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/StatsVBox/EffectLabel
@onready var duration_label: Label = $Panel/MarginContainer/HBox/DescriptionPanel/DescriptionVBox/StatsVBox/DurationLabel
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

	# Price (apply Cybergoth discount for augments)
	var price_lbl := Label.new()
	var display_price := _get_item_price(item)
	price_lbl.text = str(display_price)
	price_lbl.custom_minimum_size = Vector2(50, 0)
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


func _get_item_price(item: Dictionary) -> int:
	## Get the effective price for an item, applying archetype discounts for augments
	## Cybergoth: -15% cost on cybernetic augments
	## Breeder: -15% cost on genetic augments
	## Palate enhancements have escalating cost based on character's enhancement count
	var base_price: int = item.get("price", 0)
	var item_type: String = item.get("type", "")

	if item_type == "augment" and _character:
		var augment_category: String = item.get("augment_category", "")
		var cost_reduction := 0.0

		if augment_category == "cybernetic":
			cost_reduction = _character.get_archetype_passive("cybernetic_augment_cost_reduction", 0.0)
		elif augment_category == "genetic":
			cost_reduction = _character.get_archetype_passive("genetic_augment_cost_reduction", 0.0)

		if cost_reduction > 0.0:
			base_price = int(float(base_price) * (1.0 - cost_reduction))

	# Palate enhancements have escalating cost
	if item_type == "palate" and _character:
		# Count how many palate items are in cart
		var palate_in_cart := _get_palate_items_in_cart_count()
		var total_enhancements := _character.palate_enhancements + palate_in_cart
		base_price = _character.get_palate_enhancement_cost()
		# Adjust for items already in cart
		for i in range(palate_in_cart):
			match total_enhancements - palate_in_cart + i:
				0: base_price = 500
				1: base_price = 1000
				2: base_price = 2000
				_: base_price = 4000
		# Get the actual next price
		match total_enhancements:
			0: base_price = 500
			1: base_price = 1000
			2: base_price = 2000
			_: base_price = 4000

	return base_price


func _get_palate_items_in_cart_count() -> int:
	## Count how many palate enhancement items are in the cart
	var count := 0
	for item_id in _cart:
		for item in _items:
			if item.get("id", "") == item_id and item.get("type", "") == "palate":
				count += _cart.get(item_id, 0)
	return count


func _update_selection_visuals() -> void:
	for i in range(_item_rows.size()):
		var row := _item_rows[i]
		var item: Dictionary = _items[i]
		var price: int = _get_item_price(item)
		var is_selected := (i == _selected_index)
		var can_afford := GameManager.money >= (_cart_total + price)
		var is_available := can_afford and _can_add_item(item)

		# Get the name label (second child)
		var name_lbl: Label = row.get_child(1) as Label

		if is_selected:
			# Highlight selected row
			name_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))  # Green tint for Dr. Dan
			# Show arrows more prominently
			(row.get_child(0) as Label).add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			(row.get_child(3) as Label).add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		else:
			if is_available:
				name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			else:
				name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			# Dim arrows for non-selected
			(row.get_child(0) as Label).add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
			(row.get_child(3) as Label).add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))


func _can_add_item(item: Dictionary) -> bool:
	## Check if an item can be added to cart (beyond just affordability)
	var item_id: String = item.get("id", "")
	var item_type: String = item.get("type", "")

	# Augments can only be added once
	if item_type == "augment" and _cart.has(item_id):
		return false

	# Contracts are limited by womb capacity
	if item_type == "contract" and _character:
		var bb_gain: int = item.get("bb_factor_gain", 1)
		var current_bb := _character.bb_factor
		var cart_bb := _get_cart_bb_factor_total()
		if current_bb + cart_bb + bb_gain > _character.womb_capacity:
			return false

	# Kinks can only be purchased once and may have prerequisites
	if item_type == "kink" and _character:
		var kink_id: String = item.get("kink_id", "")
		# Already has this kink or it's in cart
		if _character.has_kink(kink_id) or _cart.has(item_id):
			return false
		# Check prerequisite kink (must have it or be in cart)
		var requires_kink: String = item.get("requires_kink", "")
		if not requires_kink.is_empty():
			var has_prereq := _character.has_kink(requires_kink)
			var prereq_in_cart := _is_kink_in_cart(requires_kink)
			if not has_prereq and not prereq_in_cart:
				return false

	# Palate enhancements can only be purchased for neutral categories
	if item_type == "palate" and _character:
		var food_category: String = item.get("food_category", "")
		# Can only enhance neutral categories (not liked, not disliked)
		if not _character.can_enhance_palate(food_category):
			return false
		# Check if already in cart
		if _cart.has(item_id):
			return false

	return true


func _is_kink_in_cart(kink_id: String) -> bool:
	## Check if a kink certification is already in the cart
	for item_id in _cart:
		for item in _items:
			if item.get("id", "") == item_id and item.get("kink_id", "") == kink_id:
				return true
	return false


func _update_description() -> void:
	if _items.is_empty():
		return

	var item: Dictionary = _items[_selected_index]

	if item_name_label:
		item_name_label.text = item.get("name", "???")

	if description_label:
		description_label.text = item.get("description", "")

	if effect_label:
		var effect: String = item.get("effect", "")
		if effect.is_empty():
			effect_label.text = ""
		else:
			effect_label.text = "Effect: %s" % effect

	if duration_label:
		var procedure_time: int = item.get("procedure_time", 0)
		if procedure_time > 0:
			duration_label.text = "Procedure: %d min" % procedure_time
		else:
			duration_label.text = ""

	if price_label:
		var display_price := _get_item_price(item)
		var base_price: int = item.get("price", 0)
		if display_price < base_price:
			# Show discounted price with strikethrough on original
			price_label.text = "Price: %d (was %d)" % [display_price, base_price]
		else:
			price_label.text = "Price: %d" % display_price

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

		var price: int = _get_item_price(item_data)
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
			hint_label.text = "Processing... %s\nQ to Close" % bar
		else:
			hint_label.text = "Hold V to Purchase\nQ to Close"


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Hold V to purchase (check raw key first)
	if event is InputEventKey:
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
			return

	# Close shop
	if event.is_action_pressed("back"):
		close_shop()
		get_viewport().set_input_as_handled()
	# Navigation
	elif event.is_action_pressed("move_up"):
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
	var price: int = _get_item_price(item)
	var item_type: String = item.get("type", "consumable")

	# Check affordability
	if GameManager.money < (_cart_total + price):
		return

	# For permanent augments, only allow one in cart
	if item_type == "augment":
		if _cart.has(item_id):
			return  # Already have one in cart
		_cart[item_id] = 1
	elif item_type == "contract":
		# Check womb capacity - can't exceed it with contracts
		var bb_gain: int = item.get("bb_factor_gain", 1)
		var current_bb := _character.bb_factor
		var cart_bb := _get_cart_bb_factor_total()
		if current_bb + cart_bb + bb_gain > _character.womb_capacity:
			return  # Would exceed womb capacity
		if _cart.has(item_id):
			_cart[item_id] += 1
		else:
			_cart[item_id] = 1
	else:
		# Consumables/procedures can be stacked
		if _cart.has(item_id):
			_cart[item_id] += 1
		else:
			_cart[item_id] = 1

	_update_cart_display()
	_update_selection_visuals()
	_update_money_display()


func _get_cart_bb_factor_total() -> int:
	## Calculate total BB Factor gain from all contracts in cart
	var total := 0
	for item_id in _cart:
		var quantity: int = _cart[item_id]
		# Find item data
		for item in _items:
			if item.get("id", "") == item_id and item.get("type", "") == "contract":
				total += item.get("bb_factor_gain", 1) * quantity
				break
	return total


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

	var total_procedure_time: float = 0.0
	var purchased_items: Array[Dictionary] = []

	# Process all items
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
		var procedure_time: int = item_data.get("procedure_time", 0)

		# Add procedure time
		total_procedure_time += procedure_time * quantity

		# Store purchased items with quantity for later processing
		var purchase_entry := item_data.duplicate()
		purchase_entry["quantity"] = quantity
		purchased_items.append(purchase_entry)

		# Log the purchase
		var total_item_cost := item_price * quantity
		var activity_msg: String
		if quantity == 1:
			activity_msg = "%s got %s for $%d" % [_character.display_name, item_name, total_item_cost]
		else:
			activity_msg = "%s got %dx %s for $%d" % [_character.display_name, quantity, item_name, total_item_cost]
		TimeManager.activity_logged.emit(activity_msg)

		item_purchased.emit(item_data, _character)

	# Handle differently based on whether this is the player or not
	if _character.is_player:
		# Player: Apply effects immediately and skip time
		for purchase in purchased_items:
			var quantity: int = purchase.get("quantity", 1)
			var item_type: String = purchase.get("type", "")
			match item_type:
				"augment":
					_character.add_augment(purchase)
					_apply_augment(purchase)
				"infusion":
					_apply_infusion(purchase, quantity)
				"procedure":
					_apply_procedure(purchase, quantity)
				"contract":
					_apply_contract(purchase, quantity)
				"kink":
					_apply_kink(purchase)
				"palate":
					_apply_palate_enhancement(purchase)

		var time_to_skip := int(total_procedure_time)
		TimeManager.skip_time(time_to_skip)
	else:
		# Non-player: Store treatments and assign to station
		_character.pending_dr_dan_treatments = purchased_items
		_character.current_task_id = "Dr. Dan's"
		_character.task_time_remaining = total_procedure_time

	close_shop()


func _apply_procedure(item_data: Dictionary, quantity: int) -> void:
	## Apply immediate effects from procedures
	## Cybergoth archetype: +50% effect on augments
	var item_type: String = item_data.get("type", "")
	var effect_multiplier := 1.0
	if item_type == "augment" and _character:
		var effect_bonus: float = _character.get_archetype_passive("augment_effect_bonus", 0.0)
		effect_multiplier = 1.0 + effect_bonus

	var stat_changes: Dictionary = item_data.get("stat_changes", {})
	for stat_name in stat_changes:
		var base_change: int = stat_changes[stat_name] * quantity
		var change := int(float(base_change) * effect_multiplier)
		match stat_name:
			"stamina":
				_character.stamina = clampi(_character.stamina + change, 0, 100)
			"charm":
				_character.charm = clampi(_character.charm + change, 0, 100)
			"talent":
				_character.talent = clampi(_character.talent + change, 0, 100)
			"style":
				_character.style = clampi(_character.style + change, 0, 100)
			"stomach_capacity":
				_character.stomach_capacity += change
			"weight":
				_character.add_weight(change)


func _apply_infusion(item_data: Dictionary, quantity: int) -> void:
	## Apply immediate effects from IV drip infusions
	var item_id: String = item_data.get("id", "")
	for _i in range(quantity):
		match item_id:
			"energy_drip":
				_character.energy = clampi(_character.energy + 40, 0, 100)
			"appetite_drip":
				# Temporary stomach capacity boost - could be handled via status effect
				_character.stomach_capacity += 20
			"mood_infusion":
				_character.mood = clampi(_character.mood + 50, 0, 100)
			"recovery_drip":
				# Reduces fullness and restores energy
				_character.stomach_fullness = maxi(_character.stomach_fullness - 50, 0)
				_character.energy = clampi(_character.energy + 30, 0, 100)
			"performance_infusion":
				# Temporary charm boost - could be handled via status effect
				_character.charm = clampi(_character.charm + 15, 0, 100)


func _apply_contract(item_data: Dictionary, quantity: int) -> void:
	## Apply surrogacy contract effects - increase BB Factor
	var bb_gain: int = item_data.get("bb_factor_gain", 1)
	var total_gain := bb_gain * quantity
	_character.bb_factor = mini(_character.bb_factor + total_gain, _character.womb_capacity)


func _apply_kink(item_data: Dictionary) -> void:
	## Unlock a kink for the character
	var kink_id: String = item_data.get("kink_id", "")
	if kink_id.is_empty():
		return
	_character.add_kink(kink_id)


func _apply_palate_enhancement(item_data: Dictionary) -> void:
	## Upgrade a neutral food category to liked for the character
	var food_category: String = item_data.get("food_category", "")
	if food_category.is_empty():
		return
	if _character.enhance_palate(food_category):
		TimeManager.activity_logged.emit("%s now loves %s!" % [_character.display_name, food_category.capitalize()])


func _apply_augment(item_data: Dictionary) -> void:
	## Apply augment stat changes with archetype effect bonuses
	## Cybergoth: +50% effect on cybernetic augments
	## Breeder: +50% effect on genetic augments
	var stat_changes: Dictionary = item_data.get("stat_changes", {})
	if stat_changes.is_empty():
		return

	var effect_multiplier := 1.0
	if _character:
		var augment_category: String = item_data.get("augment_category", "")
		var effect_bonus := 0.0

		if augment_category == "cybernetic":
			effect_bonus = _character.get_archetype_passive("cybernetic_augment_effect_bonus", 0.0)
		elif augment_category == "genetic":
			effect_bonus = _character.get_archetype_passive("genetic_augment_effect_bonus", 0.0)

		effect_multiplier = 1.0 + effect_bonus

	for stat_name in stat_changes:
		var base_change: int = stat_changes[stat_name]
		var change := int(float(base_change) * effect_multiplier)
		match stat_name:
			"stamina":
				_character.stamina = clampi(_character.stamina + change, 0, 100)
			"charm":
				_character.charm = clampi(_character.charm + change, 0, 100)
			"talent":
				_character.talent = clampi(_character.talent + change, 0, 100)
			"style":
				_character.style = clampi(_character.style + change, 0, 100)
			"stomach_capacity":
				_character.stomach_capacity += change
			"weight":
				_character.add_weight(change)


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
