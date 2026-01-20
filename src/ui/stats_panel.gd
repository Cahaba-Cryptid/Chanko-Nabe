extends Control
class_name StatsPanel
## Character stats display panel with portrait based on belly size

signal panel_closed

# Stats labels (left column)
@onready var name_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/NameLabel
@onready var level_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/LevelLabel
@onready var charm_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/CharmLabel
@onready var talent_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/TalentLabel
@onready var stamina_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/StaminaLabel
@onready var style_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/StyleLabel
@onready var weight_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/WeightLabel
@onready var fullness_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/FullnessLabel
@onready var bb_factor_label: Label = $Panel/MarginContainer/HBox/LeftColumn/StatsPanel/StatsVBox/BBFactorLabel

# Mood display
@onready var mood_label: Label = $Panel/MarginContainer/HBox/LeftColumn/MoodPanel/MoodVBox/MoodLabel

# Portrait (right column)
@onready var portrait_image: TextureRect = $Panel/MarginContainer/HBox/RightColumn/PortraitPanel/PortraitVBox/PortraitImage
@onready var portrait_placeholder: Label = $Panel/MarginContainer/HBox/RightColumn/PortraitPanel/PortraitVBox/PortraitPlaceholder

var _character: CharacterData


func _ready() -> void:
	hide()


func open_panel(character: CharacterData) -> void:
	_character = character
	_refresh_display()
	show()


func close_panel() -> void:
	_character = null
	hide()
	panel_closed.emit()


func _refresh_display() -> void:
	if not _character:
		return

	# Name and level
	if name_label:
		name_label.text = _character.display_name

	if level_label:
		level_label.text = "Level: %d" % _character.level

	# Core stats
	if charm_label:
		charm_label.text = "Charm: %d" % _character.charm

	if talent_label:
		talent_label.text = "Talent: %d" % _character.talent

	if stamina_label:
		stamina_label.text = "Stamina: %d" % _character.stamina

	if style_label:
		style_label.text = "Style: %d" % _character.style

	# Physical stats
	if weight_label:
		weight_label.text = "Weight: %d" % _character.weight

	if fullness_label:
		fullness_label.text = "Fullness: %d/%d" % [_character.stomach_fullness, _character.stomach_capacity]

	if bb_factor_label:
		if _character.bb_factor > 0:
			bb_factor_label.text = "BB Factor: %d" % _character.bb_factor
			bb_factor_label.show()
		else:
			bb_factor_label.hide()

	# Mood
	if mood_label:
		mood_label.text = _character.get_mood_text()
		_update_mood_color()

	# Portrait
	_update_portrait()


func _update_mood_color() -> void:
	if not mood_label:
		return

	var mood_text := _character.get_mood_text()
	match mood_text:
		"Ecstatic":
			mood_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		"Happy":
			mood_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		"Neutral":
			mood_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		"Unhappy":
			mood_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		"Miserable":
			mood_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


func _update_portrait() -> void:
	var tier := _character.get_portrait_tier()

	# For now, show placeholder text
	# Later this will load actual portrait images based on character ID and tier
	if portrait_placeholder:
		portrait_placeholder.text = "Portrait %d" % tier
		portrait_placeholder.show()

	if portrait_image:
		# Future: Load portrait based on character and tier
		# var portrait_path := "res://assets/portraits/%s_tier%d.png" % [_character.id, tier]
		# if ResourceLoader.exists(portrait_path):
		#     portrait_image.texture = load(portrait_path)
		#     portrait_placeholder.hide()
		portrait_image.texture = null


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("back"):
		close_panel()
		get_viewport().set_input_as_handled()
