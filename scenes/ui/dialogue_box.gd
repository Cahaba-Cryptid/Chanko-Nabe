extends Control
class_name DialogueBox
## Dialogue box UI for displaying character dialogue with typewriter effect
##
## Input handling:
## - First press of any action key: Complete current line instantly
## - Second press: Advance to next line
## - Action keys: WASD, Q, E, Space, Enter

signal line_completed  # Emitted when a line finishes displaying
signal dialogue_finished  # Emitted when all lines are done
signal choice_selected(index: int)  # Future: emitted when player picks a choice

@onready var panel: PanelContainer = $Panel
@onready var portrait_rect: TextureRect = $Panel/HBox/PortraitContainer/Portrait
@onready var name_label: Label = $Panel/HBox/TextContainer/NameLabel
@onready var text_label: RichTextLabel = $Panel/HBox/TextContainer/TextLabel
@onready var continue_indicator: Label = $Panel/HBox/TextContainer/ContinueIndicator

## Typewriter speed (characters per second)
@export var characters_per_second: float = 40.0

## Speaker data cache
var _speakers: Dictionary = {}

## Current state
var _current_text: String = ""
var _displayed_chars: int = 0
var _is_typing: bool = false
var _line_complete: bool = false
var _typewriter_timer: float = 0.0

## Input cooldown to prevent accidental double-press
var _input_cooldown: float = 0.0
const INPUT_COOLDOWN_TIME := 0.1


func _ready() -> void:
	_load_speakers()
	hide()
	if continue_indicator:
		continue_indicator.hide()


func _load_speakers() -> void:
	var file := FileAccess.open("res://data/speakers.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			_speakers = data.get("speakers", {})
		file.close()


func _process(delta: float) -> void:
	if not visible:
		return

	# Input cooldown
	if _input_cooldown > 0:
		_input_cooldown -= delta

	# Typewriter effect
	if _is_typing:
		_typewriter_timer += delta
		var chars_to_show := int(_typewriter_timer * characters_per_second)
		if chars_to_show > _displayed_chars:
			_displayed_chars = mini(chars_to_show, _current_text.length())
			_update_displayed_text()

			if _displayed_chars >= _current_text.length():
				_finish_typing()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _input_cooldown > 0:
		return

	# Check for action keys
	var is_action_key := false

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_SPACE, KEY_ENTER:
				is_action_key = true

	if is_action_key:
		_input_cooldown = INPUT_COOLDOWN_TIME
		get_viewport().set_input_as_handled()

		if _is_typing:
			# First press: complete the line instantly
			_displayed_chars = _current_text.length()
			_update_displayed_text()
			_finish_typing()
		elif _line_complete:
			# Second press: advance to next line
			line_completed.emit()


func show_line(speaker_id: String, text: String) -> void:
	## Display a dialogue line with typewriter effect
	var speaker_data: Dictionary = _speakers.get(speaker_id, {})

	# Set speaker name and color
	var speaker_name: String = speaker_data.get("name", speaker_id.capitalize())
	var speaker_color: String = speaker_data.get("color", "#ffffff")

	if name_label:
		name_label.text = speaker_name
		name_label.add_theme_color_override("font_color", Color.from_string(speaker_color, Color.WHITE))

	# Apply typing style (Vex uses lowercase)
	var typing_style: String = speaker_data.get("typing_style", "normal")
	if typing_style == "lowercase":
		text = text.to_lower()

	# Set portrait (placeholder if not found)
	if portrait_rect:
		var portrait_path: String = speaker_data.get("portrait", "")
		if portrait_path and ResourceLoader.exists(portrait_path):
			portrait_rect.texture = load(portrait_path)
			portrait_rect.modulate = Color.WHITE
		else:
			# Placeholder colored rect
			portrait_rect.texture = null
			portrait_rect.modulate = Color.from_string(speaker_color, ThemeColors.PORTRAIT_PLACEHOLDER)

	# Start typewriter effect
	_current_text = text
	_displayed_chars = 0
	_typewriter_timer = 0.0
	_is_typing = true
	_line_complete = false

	if continue_indicator:
		continue_indicator.hide()

	_update_displayed_text()
	show()


func _update_displayed_text() -> void:
	if text_label:
		text_label.text = _current_text.substr(0, _displayed_chars)


func _finish_typing() -> void:
	_is_typing = false
	_line_complete = true
	if continue_indicator:
		continue_indicator.show()


func close_box() -> void:
	hide()
	_is_typing = false
	_line_complete = false
	dialogue_finished.emit()


func is_active() -> bool:
	return visible


func is_typing() -> bool:
	return _is_typing
