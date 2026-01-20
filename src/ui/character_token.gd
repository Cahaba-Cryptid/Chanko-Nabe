extends Control
class_name CharacterToken
## Character display token for roster menu

@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var portrait: TextureRect = $Panel/VBox/Portrait
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var panel: PanelContainer = $Panel

var character_data: CharacterData
var is_selected := false


func _ready() -> void:
	# Connect to time updates to refresh countdown
	TimeManager.time_updated.connect(_on_time_updated)


func _on_time_updated(_hour: int, _minute: int) -> void:
	if not character_data:
		return

	# Count down for assigned characters
	if not character_data.current_task_id.is_empty():
		character_data.task_time_remaining -= 10.0  # Subtract 10 minutes per tick

		# Task complete - release character
		if character_data.task_time_remaining <= 0:
			character_data.clear_assignment()

		refresh_display()


func setup(character: CharacterData) -> void:
	character_data = character
	refresh_display()


func refresh_display() -> void:
	if not character_data:
		return

	if name_label:
		name_label.text = character_data.display_name

	if status_label:
		status_label.text = _get_status_text()

	# Grey out if assigned (not available)
	_update_availability_visual()


func _get_status_text() -> String:
	if not character_data:
		return "???"

	# Show exhausted status first (highest priority)
	if character_data.is_exhausted():
		return "Exhausted!"

	if character_data.is_available():
		return "Idle"
	else:
		var remaining := int(character_data.task_time_remaining)
		@warning_ignore("integer_division")
		var hours := remaining / 60
		var minutes := remaining % 60
		return "%s\n%dh %02dm" % [character_data.current_task_id, hours, minutes]


func _update_availability_visual() -> void:
	if not panel:
		return

	if character_data and not character_data.is_available():
		# Grey out assigned characters
		modulate = Color(0.6, 0.6, 0.6)
	else:
		modulate = Color(1.0, 1.0, 1.0)


func set_selected(value: bool) -> void:
	is_selected = value
	# Visual feedback for selection via border
	if panel:
		if is_selected:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.15, 0.15, 0.15)
			style.border_color = Color(1.0, 0.85, 0.4)  # Gold/yellow border
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			panel.add_theme_stylebox_override("panel", style)
		else:
			panel.remove_theme_stylebox_override("panel")
