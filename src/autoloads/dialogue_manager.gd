extends Node
## DialogueManager - Global dialogue system coordinator
##
## Usage:
##   var dialogue := DialogueData.new()
##   dialogue.add_line("vex", "hey there.")
##   dialogue.add_line("vex", "welcome to cammtec.")
##   DialogueManager.play(dialogue)
##
## With callback:
##   DialogueManager.play(dialogue, func(): print("Dialogue done!"))
##
## Check state:
##   if DialogueManager.is_playing():
##       # dialogue is active

signal dialogue_started
signal dialogue_ended
signal line_shown(speaker_id: String, text: String)

## The dialogue box scene
const DIALOGUE_BOX_SCENE := preload("res://scenes/ui/dialogue_box.tscn")

## Current dialogue box instance
var _dialogue_box: DialogueBox = null

## Current dialogue data
var _current_dialogue: DialogueData = null

## Current line index
var _current_line_index: int = 0

## Callback for when dialogue ends
var _on_complete_callback: Callable

## Track seen dialogues (by ID) for one-time dialogues
var _seen_dialogues: Dictionary = {}

## Queue for pending dialogues (if one plays while another is active)
var _dialogue_queue: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func play(dialogue: DialogueData, on_complete: Callable = Callable()) -> void:
	## Play a dialogue sequence. Optionally provide a callback for when it ends.
	if dialogue == null or dialogue.is_empty():
		if on_complete.is_valid():
			on_complete.call()
		return

	# If dialogue is already playing, queue this one
	if is_playing():
		_dialogue_queue.append({
			"dialogue": dialogue,
			"on_complete": on_complete
		})
		return

	_start_dialogue(dialogue, on_complete)


func play_once(dialogue: DialogueData, on_complete: Callable = Callable()) -> void:
	## Play dialogue only if it hasn't been seen before (requires dialogue_id set)
	if dialogue.dialogue_id.is_empty():
		push_warning("DialogueManager.play_once() called with no dialogue_id - playing anyway")
		play(dialogue, on_complete)
		return

	if has_seen(dialogue.dialogue_id):
		if on_complete.is_valid():
			on_complete.call()
		return

	play(dialogue, on_complete)


func has_seen(dialogue_id: String) -> bool:
	## Check if a dialogue has been seen
	return _seen_dialogues.has(dialogue_id)


func mark_seen(dialogue_id: String) -> void:
	## Mark a dialogue as seen
	_seen_dialogues[dialogue_id] = true


func clear_seen() -> void:
	## Clear all seen dialogue tracking (for new game)
	_seen_dialogues.clear()


func is_playing() -> bool:
	## Returns true if dialogue is currently active
	return _dialogue_box != null and _dialogue_box.is_active()


func skip_current() -> void:
	## Skip the current dialogue entirely
	if is_playing():
		_end_dialogue()


func _start_dialogue(dialogue: DialogueData, on_complete: Callable) -> void:
	_current_dialogue = dialogue
	_current_line_index = 0
	_on_complete_callback = on_complete

	# Mark as seen if it has an ID
	if not dialogue.dialogue_id.is_empty():
		mark_seen(dialogue.dialogue_id)

	# Create dialogue box if needed
	if _dialogue_box == null:
		_dialogue_box = DIALOGUE_BOX_SCENE.instantiate()
		_dialogue_box.line_completed.connect(_on_line_completed)
		_dialogue_box.dialogue_finished.connect(_on_dialogue_finished)

		# Add to the scene tree at a high level so it appears over everything
		var root := get_tree().root
		root.add_child(_dialogue_box)

	# Pause the game while dialogue is active
	get_tree().paused = true

	dialogue_started.emit()
	_show_current_line()


func _show_current_line() -> void:
	if _current_dialogue == null:
		return

	var line := _current_dialogue.get_line(_current_line_index)
	if line.is_empty():
		_end_dialogue()
		return

	var speaker_id: String = line.get("speaker_id", "system")
	var text: String = line.get("text", "")

	_dialogue_box.show_line(speaker_id, text)
	line_shown.emit(speaker_id, text)


func _on_line_completed() -> void:
	## Called when player advances past current line
	if _current_dialogue == null:
		return

	# Call per-line callback if set
	var line := _current_dialogue.get_line(_current_line_index)
	if line.has("on_complete"):
		var callback: Callable = line["on_complete"]
		if callback.is_valid():
			callback.call()

	# Advance to next line
	_current_line_index += 1
	if _current_line_index >= _current_dialogue.get_line_count():
		_end_dialogue()
	else:
		_show_current_line()


func _on_dialogue_finished() -> void:
	## Called when dialogue box closes
	pass  # Handled by _end_dialogue


func _end_dialogue() -> void:
	if _dialogue_box:
		_dialogue_box.close_box()

	# Call dialogue complete callback
	if _current_dialogue and _current_dialogue.on_dialogue_complete.is_valid():
		_current_dialogue.on_dialogue_complete.call()

	# Call play() callback
	if _on_complete_callback.is_valid():
		_on_complete_callback.call()

	_current_dialogue = null
	_current_line_index = 0
	_on_complete_callback = Callable()

	# Unpause
	get_tree().paused = false

	dialogue_ended.emit()

	# Process queue
	if not _dialogue_queue.is_empty():
		var next: Dictionary = _dialogue_queue.pop_front()
		_start_dialogue(next["dialogue"], next["on_complete"])


## Save/Load support for seen dialogues
func get_save_data() -> Dictionary:
	return {
		"seen_dialogues": _seen_dialogues.duplicate()
	}


func load_save_data(data: Dictionary) -> void:
	_seen_dialogues = data.get("seen_dialogues", {}).duplicate()


## Helper to create quick one-liner dialogues
static func quick(speaker_id: String, text: String) -> DialogueData:
	var dialogue := DialogueData.new()
	dialogue.add_line(speaker_id, text)
	return dialogue


## Helper to create Vex dialogue (most common)
static func vex(text: String) -> DialogueData:
	return quick("vex", text)


## Helper to create multi-line Vex dialogue
static func vex_lines(lines: Array[String]) -> DialogueData:
	var dialogue := DialogueData.new()
	for line in lines:
		dialogue.add_line("vex", line)
	return dialogue
