extends Control
class_name CharacterDetailPanel
## Expanded character view with stats, conditions, and action tabs

signal tab_selected(tab_name: String)
signal closed

@onready var name_label: Label = $Panel/VBox/Header/NameLabel
@onready var portrait: TextureRect = $Panel/VBox/Header/Portrait
@onready var stats_container: VBoxContainer = $Panel/VBox/Content/StatsContainer
@onready var tabs_container: HBoxContainer = $Panel/VBox/TabsContainer

var character_data: CharacterData
var _tab_buttons: Array[Button] = []
var _current_tabs: Array[String] = []
var _selected_tab_index: int = 0

# Base tabs for all characters
const BASE_TABS := ["Assign", "Binge", "Items", "Stats"]
# Additional tabs for player only
const PLAYER_TABS := ["Shop"]


func _ready() -> void:
	pass


func show_character(character: CharacterData) -> void:
	character_data = character
	_setup_tabs_for_character()
	_refresh_display()

	# If character has food queued, start on Binge tab
	if character_data.has_food_queued():
		_selected_tab_index = _current_tabs.find("Binge")
		if _selected_tab_index < 0:
			_selected_tab_index = 0
	else:
		_selected_tab_index = 0

	_update_tab_visuals()
	show()


func _setup_tabs_for_character() -> void:
	# Clear existing tabs
	_tab_buttons.clear()
	for child in tabs_container.get_children():
		child.queue_free()

	# Build tab list based on character type
	_current_tabs.clear()
	for tab in BASE_TABS:
		_current_tabs.append(tab)
	if character_data and character_data.is_player:
		for tab in PLAYER_TABS:
			_current_tabs.append(tab)

	# Create tab buttons
	for tab_name in _current_tabs:
		var btn := Button.new()
		btn.text = tab_name
		btn.custom_minimum_size = Vector2(70, 30)
		tabs_container.add_child(btn)
		_tab_buttons.append(btn)


func _refresh_display() -> void:
	if not character_data:
		return

	if name_label:
		name_label.text = character_data.display_name

	# Update stats display
	if stats_container:
		# Clear existing stat labels
		for child in stats_container.get_children():
			child.queue_free()

		# Add stat labels - show effective charm if burned out
		if character_data.burnout_charm_penalty > 0:
			_add_stat_label("Charm", character_data.get_effective_charm(), " (-%d)" % character_data.burnout_charm_penalty)
		else:
			_add_stat_label("Charm", character_data.charm)
		_add_stat_label("Talent", character_data.talent)
		_add_stat_label("Stamina", character_data.stamina)
		_add_stat_label("Style", character_data.style)
		_add_stat_label("", -1)  # Spacer
		_add_stat_label("Energy", character_data.energy)
		_add_stat_label("Mood", character_data.mood, " (%s)" % character_data.get_mood_text())
		if character_data.fatigue > 0:
			_add_stat_label("Fatigue", character_data.fatigue)
		_add_stat_label("", -1)  # Spacer
		# Physical stats
		_add_stat_label("Stomach", character_data.stomach_fullness, "/%d" % character_data.stomach_capacity)
		_add_stat_label("Weight", character_data.weight, " lbs")
		_add_stat_label("", -1)  # Spacer
		_add_stat_label("Salary", character_data.daily_salary, "/day")

		if character_data.is_exhausted():
			_add_stat_label("", -1)  # Spacer
			_add_stat_label("Status", -1, "EXHAUSTED!")
		elif character_data.burnout_days_remaining > 0:
			_add_stat_label("", -1)  # Spacer
			_add_stat_label("Burnout", character_data.burnout_days_remaining, " days left")

		if not character_data.current_task_id.is_empty():
			_add_stat_label("Task", -1, character_data.current_task_id)

		if character_data.has_food_queued():
			_add_stat_label("Queued", character_data.get_food_queue_count(), " food items")

		# Show pregnancy status if pregnant
		if character_data.bb_factor > 0:
			_add_stat_label("", -1)  # Spacer
			var pregnancy_status := _get_pregnancy_status(character_data.bb_factor)
			_add_stat_label("Pregnancy", -1, pregnancy_status)
			_add_stat_label("Womb Cap", character_data.womb_capacity)


func _add_stat_label(stat_name: String, value: int, suffix: String = "") -> void:
	var label := Label.new()
	if value >= 0:
		label.text = "%s: %d%s" % [stat_name, value, suffix]
	elif not suffix.is_empty():
		label.text = "%s: %s" % [stat_name, suffix]
	else:
		label.text = ""
	stats_container.add_child(label)


func _get_pregnancy_status(bb_factor: int) -> String:
	## Returns pregnancy status text based on BB Factor
	if bb_factor >= 8:
		return "Hyperpregnant (%d)" % bb_factor
	elif bb_factor >= 5:
		return "%d babies" % bb_factor
	elif bb_factor == 4:
		return "Quads"
	elif bb_factor == 3:
		return "Triplets"
	elif bb_factor == 2:
		return "Twins"
	elif bb_factor == 1:
		return "Single"
	else:
		return "Not pregnant"


func navigate_tabs(direction: int) -> void:
	if _tab_buttons.is_empty():
		return

	_selected_tab_index = wrapi(_selected_tab_index + direction, 0, _tab_buttons.size())
	_update_tab_visuals()


func get_selected_tab() -> String:
	if _selected_tab_index >= 0 and _selected_tab_index < _current_tabs.size():
		return _current_tabs[_selected_tab_index]
	return ""


func select_current_tab() -> void:
	var tab_name := get_selected_tab()

	# If character has food queued, only allow Binge tab
	if character_data and character_data.has_food_queued() and tab_name != "Binge":
		return

	tab_selected.emit(tab_name)


func _update_tab_visuals() -> void:
	var has_food_queued := character_data and character_data.has_food_queued()

	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		var tab_name := _current_tabs[i]

		# Grey out non-Binge tabs if character has food queued
		if has_food_queued and tab_name != "Binge":
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0)

		if i == _selected_tab_index:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.25, 0.25, 0.25)
			style.border_color = Color(1.0, 0.85, 0.4)
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", style)
		else:
			btn.remove_theme_stylebox_override("normal")


func close_panel() -> void:
	hide()
	closed.emit()
