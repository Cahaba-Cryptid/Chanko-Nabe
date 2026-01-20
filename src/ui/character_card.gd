extends PanelContainer
class_name CharacterCard
## UI card displaying character info

signal card_clicked(character: CharacterData)
signal assign_requested(character: CharacterData)

@onready var portrait_rect: TextureRect = $VBox/Portrait
@onready var name_label: Label = $VBox/NameLabel
@onready var level_label: Label = $VBox/StatsContainer/LevelLabel
@onready var mood_bar: ProgressBar = $VBox/StatsContainer/MoodBar
@onready var energy_bar: ProgressBar = $VBox/StatsContainer/EnergyBar
@onready var status_label: Label = $VBox/StatusLabel
@onready var assign_button: Button = $VBox/AssignButton

var character_data: CharacterData


func setup(character: CharacterData) -> void:
	character_data = character
	_update_display()


func _update_display() -> void:
	if not character_data:
		return

	if name_label:
		name_label.text = character_data.display_name

	if level_label:
		level_label.text = "Lv.%d" % character_data.level

	if portrait_rect and character_data.portrait:
		portrait_rect.texture = character_data.portrait

	if mood_bar:
		mood_bar.value = character_data.mood

	if energy_bar:
		energy_bar.value = character_data.energy

	if status_label:
		if character_data.is_available():
			status_label.text = "Available"
		else:
			status_label.text = "Working..."

	if assign_button:
		assign_button.disabled = not character_data.is_available()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			card_clicked.emit(character_data)


func _on_assign_button_pressed() -> void:
	if character_data and character_data.is_available():
		assign_requested.emit(character_data)
