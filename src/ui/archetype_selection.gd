extends Control
class_name ArchetypeSelection
## Archetype selection screen - choose your archetype and save slot

signal archetype_selected(slot: int, archetype_id: String, player_name: String, starter_augment_id: String)
signal cancelled

enum SelectionPhase { ARCHETYPE, NAME, AUGMENT_CHOICE, SLOT, CONFIRM_OVERWRITE }

const SLOT_COUNT := 3
const SAVE_PATH_TEMPLATE := "user://save_slot_%s.dat"
const SLOT_NAMES := ["A", "B", "C"]
const CYBERGOTH_STARTER_AUGMENTS := [
	"starter_breast_enhancer",
	"starter_stomach_liner",
	"starter_womb_reinforcement"
]

var _phase: SelectionPhase = SelectionPhase.ARCHETYPE
var _archetypes: Array[Dictionary] = []
var _selected_archetype_index: int = 0
var _selected_slot_index: int = 0
var _selected_augment_index: int = 0
var _confirm_selection: int = 1  # 0 = Yes, 1 = No
var _slot_data: Array[Dictionary] = []
var _player_name: String = ""
var _starter_augment_id: String = ""
var _starter_augments: Array[Dictionary] = []  # Loaded from dr_dan_items.json

@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/TitleLabel
@onready var content_container: HBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBox/ContentContainer
@onready var archetype_list: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBox/ContentContainer/ArchetypeList
@onready var details_panel: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBox/ContentContainer/DetailsPanel
@onready var archetype_name_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/ContentContainer/DetailsPanel/ArchetypeNameLabel
@onready var archetype_desc_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/ContentContainer/DetailsPanel/ArchetypeDescLabel
@onready var passives_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/ContentContainer/DetailsPanel/PassivesLabel
@onready var starting_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/ContentContainer/DetailsPanel/StartingLabel
@onready var slot_container: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBox/SlotContainer
@onready var name_container: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBox/NameContainer
@onready var name_input: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBox/NameContainer/NameInput
@onready var hint_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBox/HintLabel


func _ready() -> void:
	_load_archetypes()
	_load_starter_augments()
	_refresh_slot_data()
	_update_display()


func _notification(what: int) -> void:
	# Release LineEdit focus when this screen is hidden
	# This ensures other screens can receive keyboard input
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		if name_input:
			name_input.release_focus()


func _load_starter_augments() -> void:
	_starter_augments.clear()
	var file := FileAccess.open("res://data/dr_dan_items.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			var items: Array = data.get("items", [])
			for item in items:
				if item is Dictionary and item.get("id", "") in CYBERGOTH_STARTER_AUGMENTS:
					_starter_augments.append(item)


func _load_archetypes() -> void:
	_archetypes.clear()
	var file := FileAccess.open("res://data/archetypes.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			var arch_array: Array = data.get("archetypes", [])
			for arch in arch_array:
				if arch is Dictionary:
					_archetypes.append(arch)


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


func _update_display() -> void:
	match _phase:
		SelectionPhase.ARCHETYPE:
			_show_archetype_selection()
		SelectionPhase.NAME:
			_show_name_entry()
		SelectionPhase.AUGMENT_CHOICE:
			_show_augment_choice()
		SelectionPhase.SLOT:
			_show_slot_selection()
		SelectionPhase.CONFIRM_OVERWRITE:
			_show_confirm_overwrite()


func _show_archetype_selection() -> void:
	title_label.text = "Choose Your Archetype"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Back"
	content_container.show()
	slot_container.hide()
	name_container.hide()

	# Build archetype buttons
	for child in archetype_list.get_children():
		child.queue_free()

	for i in range(_archetypes.size()):
		var arch: Dictionary = _archetypes[i]
		var button := Button.new()
		button.text = arch.get("name", "Unknown")
		button.custom_minimum_size = Vector2(150, 40)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		archetype_list.add_child(button)

	await get_tree().process_frame
	_update_archetype_selection()
	_update_details_panel()


func _show_name_entry() -> void:
	title_label.text = "Enter Your Name"
	hint_label.text = "Type your name | Enter: Confirm | Esc: Back"
	content_container.hide()
	slot_container.hide()
	name_container.show()

	# Set default name if empty
	if _player_name == "":
		name_input.text = ""
		name_input.placeholder_text = "Your name..."
	else:
		name_input.text = _player_name

	# Focus the input field
	await get_tree().process_frame
	name_input.grab_focus()
	name_input.caret_column = name_input.text.length()


func _show_augment_choice() -> void:
	title_label.text = "Choose Starting Implant"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Back"
	content_container.hide()
	slot_container.show()
	name_container.hide()

	# Build augment buttons
	for child in slot_container.get_children():
		child.queue_free()

	var intro_label := Label.new()
	intro_label.text = "As a Cybergoth, you start with one basic implant.\nChoose wisely - this shapes your early game."
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_container.add_child(intro_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	slot_container.add_child(spacer)

	for i in range(_starter_augments.size()):
		var augment: Dictionary = _starter_augments[i]
		var button := Button.new()
		button.text = "%s - %s" % [augment.get("name", "???"), augment.get("effect", "")]
		button.custom_minimum_size = Vector2(400, 45)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot_container.add_child(button)

	await get_tree().process_frame
	_update_augment_button_selection()


func _update_augment_button_selection() -> void:
	var buttons: Array[Node] = []
	for child in slot_container.get_children():
		if child is Button:
			buttons.append(child)

	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		if i == _selected_augment_index:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.2, 0.2)
			style.border_color = Color(1.0, 0.85, 0.4)
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", style)
		else:
			btn.remove_theme_stylebox_override("normal")


func _show_slot_selection() -> void:
	title_label.text = "Choose Save Slot"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Back"
	content_container.hide()
	slot_container.show()
	name_container.hide()

	# Build slot buttons
	for child in slot_container.get_children():
		child.queue_free()

	for i in range(_slot_data.size()):
		var data: Dictionary = _slot_data[i]
		var button := Button.new()

		if data["exists"]:
			var money_str := _format_money(data["money"])
			button.text = "Slot %s - Day %d | %s (Will Overwrite)" % [data["name"], data["day"], money_str]
		else:
			button.text = "Slot %s - Empty" % data["name"]

		button.custom_minimum_size = Vector2(400, 45)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot_container.add_child(button)

	# Find first empty slot, or default to 0
	_selected_slot_index = 0
	for i in range(_slot_data.size()):
		if not _slot_data[i]["exists"]:
			_selected_slot_index = i
			break

	await get_tree().process_frame
	_update_slot_button_selection()


func _show_confirm_overwrite() -> void:
	title_label.text = "Overwrite Save?"
	hint_label.text = "Arrow Keys: Navigate | E: Select | Q: Cancel"
	content_container.hide()
	slot_container.show()
	name_container.hide()

	var slot_data: Dictionary = _slot_data[_selected_slot_index]

	# Clear and rebuild
	for child in slot_container.get_children():
		child.queue_free()

	var info_label := Label.new()
	info_label.text = "Slot %s contains a Day %d save.\nStart new game and overwrite?" % [slot_data["name"], slot_data["day"]]
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_container.add_child(info_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	slot_container.add_child(spacer)

	var yes_button := Button.new()
	yes_button.text = "Yes, Start New Game"
	yes_button.custom_minimum_size = Vector2(250, 45)
	slot_container.add_child(yes_button)

	var no_button := Button.new()
	no_button.text = "No, Choose Different Slot"
	no_button.custom_minimum_size = Vector2(250, 45)
	slot_container.add_child(no_button)

	_confirm_selection = 1  # Default to "No"

	await get_tree().process_frame
	_update_confirm_button_selection()


func _update_archetype_selection() -> void:
	var buttons := archetype_list.get_children()
	for i in range(buttons.size()):
		if buttons[i] is Button:
			var button: Button = buttons[i]
			if i == _selected_archetype_index:
				_apply_selected_style(button)
			else:
				button.remove_theme_stylebox_override("normal")


func _update_details_panel() -> void:
	if _selected_archetype_index >= _archetypes.size():
		return

	var arch: Dictionary = _archetypes[_selected_archetype_index]

	archetype_name_label.text = arch.get("name", "Unknown")
	archetype_desc_label.text = arch.get("description", "")

	# Build passives text
	var passives: Dictionary = arch.get("passives", {})
	var passive_lines: Array[String] = []
	for key in passives:
		var value: Variant = passives[key]
		var formatted := _format_passive(key, value)
		if formatted != "":
			passive_lines.append(formatted)

	if passive_lines.size() > 0:
		passives_label.text = "Passives:\n" + "\n".join(passive_lines)
	else:
		passives_label.text = "Passives: None"

	# Starting conditions
	var starting_money: int = arch.get("starting_money", 750)
	var starting_npcs: int = arch.get("starting_npcs", 0)
	var can_perform: bool = arch.get("can_perform", true)

	var starting_text := "Starting: $%d" % starting_money
	if starting_npcs > 0:
		starting_text += ", %d NPC%s" % [starting_npcs, "s" if starting_npcs > 1 else ""]
	if not can_perform:
		starting_text += "\n(Cannot perform content personally)"

	starting_label.text = starting_text


func _format_passive(key: String, value: Variant) -> String:
	match key:
		"capacity_training_bonus":
			return "  +%d%% capacity training chance" % int(value * 100)
		"weight_gain_reduction":
			return "  -%d%% weight gain" % int(value * 100)
		"base_womb_capacity_bonus":
			return "  +%d base womb capacity" % int(value)
		"surrogacy_income_bonus":
			return "  +%d%% surrogacy income" % int(value * 100)
		"genetic_augment_cost_reduction":
			return "  -%d%% genetic augment cost" % int(value * 100)
		"genetic_augment_effect_bonus":
			return "  +%d%% genetic augment effects" % int(value * 100)
		"follower_decay_reduction":
			return "  -%d%% follower decay" % int(value * 100)
		"socializing_bonus":
			return "  +%d%% socializing gains" % int(value * 100)
		"energy_drain_reduction":
			return "  -%d%% energy drain" % int(value * 100)
		"cybernetic_augment_effect_bonus":
			return "  +%d%% cybernetic augment effects" % int(value * 100)
		"cybernetic_augment_cost_reduction":
			return "  -%d%% cybernetic augment cost" % int(value * 100)
		"always_lactating":
			return "  Always lactating" if value else ""
		"milk_production_bonus":
			return "  +%d%% milk production" % int(value * 100)
		"milk_value_bonus":
			return "  +%d%% milk value" % int(value * 100)
		"npc_salary_reduction":
			return "  -%d%% NPC salaries" % int(value * 100)
		"npc_effectiveness_bonus":
			return "  +%d%% NPC effectiveness" % int(value * 100)
		_:
			return ""


func _update_slot_button_selection() -> void:
	var buttons := slot_container.get_children()
	for i in range(buttons.size()):
		if buttons[i] is Button:
			var button: Button = buttons[i]
			if i == _selected_slot_index:
				_apply_selected_style(button)
			else:
				button.remove_theme_stylebox_override("normal")


func _update_confirm_button_selection() -> void:
	var children := slot_container.get_children()
	if children.size() < 4:
		return

	var yes_button: Button = children[2]
	var no_button: Button = children[3]

	if _confirm_selection == 0:
		_apply_selected_style(yes_button)
		no_button.remove_theme_stylebox_override("normal")
	else:
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

	match _phase:
		SelectionPhase.ARCHETYPE:
			_handle_archetype_input(event)
		SelectionPhase.NAME:
			_handle_name_input(event)
		SelectionPhase.AUGMENT_CHOICE:
			_handle_augment_input(event)
		SelectionPhase.SLOT:
			_handle_slot_input(event)
		SelectionPhase.CONFIRM_OVERWRITE:
			_handle_confirm_input(event)


func _handle_archetype_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_archetype_index = wrapi(_selected_archetype_index - 1, 0, _archetypes.size())
		_update_archetype_selection()
		_update_details_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_archetype_index = wrapi(_selected_archetype_index + 1, 0, _archetypes.size())
		_update_archetype_selection()
		_update_details_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_phase = SelectionPhase.NAME
		_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _handle_name_input(event: InputEvent) -> void:
	# Let LineEdit handle text input - only intercept Enter and Escape
	# Do NOT intercept Q or WASD during text entry (needed for typing)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			name_input.release_focus()  # Release focus so other screens can receive input
			_phase = SelectionPhase.ARCHETYPE
			_update_display()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER:
			# Confirm name
			var entered_name := name_input.text.strip_edges()
			if entered_name.length() > 0:
				_player_name = entered_name
				name_input.release_focus()  # Release focus when leaving name entry
				# Cybergoth gets augment choice, others go straight to slot
				var arch: Dictionary = _archetypes[_selected_archetype_index]
				if arch.get("id", "") == "cybergoth":
					_phase = SelectionPhase.AUGMENT_CHOICE
					_selected_augment_index = 0
				else:
					_starter_augment_id = ""
					_phase = SelectionPhase.SLOT
					_refresh_slot_data()
				_update_display()
			get_viewport().set_input_as_handled()


func _handle_augment_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_augment_index = wrapi(_selected_augment_index - 1, 0, _starter_augments.size())
		_update_augment_button_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_augment_index = wrapi(_selected_augment_index + 1, 0, _starter_augments.size())
		_update_augment_button_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		# Store selected augment and proceed to slot selection
		if _selected_augment_index < _starter_augments.size():
			_starter_augment_id = _starter_augments[_selected_augment_index].get("id", "")
		_phase = SelectionPhase.SLOT
		_refresh_slot_data()
		_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_phase = SelectionPhase.NAME
		_update_display()
		get_viewport().set_input_as_handled()


func _handle_slot_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_slot_index = wrapi(_selected_slot_index - 1, 0, SLOT_COUNT)
		_update_slot_button_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_slot_index = wrapi(_selected_slot_index + 1, 0, SLOT_COUNT)
		_update_slot_button_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _slot_data[_selected_slot_index]["exists"]:
			_phase = SelectionPhase.CONFIRM_OVERWRITE
			_update_display()
		else:
			_finalize_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_phase = SelectionPhase.NAME
		_update_display()
		get_viewport().set_input_as_handled()


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		_confirm_selection = 1 - _confirm_selection
		_update_confirm_button_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		if _confirm_selection == 0:  # Yes
			_finalize_selection()
		else:  # No
			_phase = SelectionPhase.SLOT
			_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_phase = SelectionPhase.SLOT
		_update_display()
		get_viewport().set_input_as_handled()


func _finalize_selection() -> void:
	var arch: Dictionary = _archetypes[_selected_archetype_index]
	var archetype_id: String = arch.get("id", "feeder")
	archetype_selected.emit(_selected_slot_index, archetype_id, _player_name, _starter_augment_id)


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
