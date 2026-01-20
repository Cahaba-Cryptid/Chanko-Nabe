extends Resource
class_name DialogueData
## Data container for a dialogue sequence
##
## Usage:
##   var dialogue := DialogueData.new()
##   dialogue.add_line("vex", "hey there. welcome to cammtec.")
##   dialogue.add_line("vex", "try not to get sent to the mines, ok?")
##   DialogueManager.play(dialogue)
##
## For choices (future):
##   dialogue.add_choice("vex", "what do you want to do?", ["Option A", "Option B"])

## Each entry is a Dictionary with:
## - speaker_id: String (key from speakers.json)
## - text: String (the dialogue line)
## - choices: Array[String] (optional, for branching - future feature)
## - on_complete: Callable (optional, called when this line completes)
var lines: Array[Dictionary] = []

## Optional callback when entire dialogue sequence completes
var on_dialogue_complete: Callable

## Optional ID for tracking which dialogues have been seen
var dialogue_id: String = ""


func add_line(speaker_id: String, text: String, on_complete: Callable = Callable()) -> DialogueData:
	## Add a dialogue line. Returns self for chaining.
	var line := {
		"speaker_id": speaker_id,
		"text": text,
		"choices": [] as Array[String]
	}
	if on_complete.is_valid():
		line["on_complete"] = on_complete
	lines.append(line)
	return self


func add_choice(speaker_id: String, text: String, choices: Array[String], on_complete: Callable = Callable()) -> DialogueData:
	## Add a dialogue line with choices (future feature). Returns self for chaining.
	var line := {
		"speaker_id": speaker_id,
		"text": text,
		"choices": choices
	}
	if on_complete.is_valid():
		line["on_complete"] = on_complete
	lines.append(line)
	return self


func set_on_complete(callback: Callable) -> DialogueData:
	## Set callback for when dialogue completes. Returns self for chaining.
	on_dialogue_complete = callback
	return self


func set_id(id: String) -> DialogueData:
	## Set dialogue ID for tracking. Returns self for chaining.
	dialogue_id = id
	return self


func get_line(index: int) -> Dictionary:
	## Get line at index, or empty dict if out of bounds
	if index >= 0 and index < lines.size():
		return lines[index]
	return {}


func get_line_count() -> int:
	return lines.size()


func is_empty() -> bool:
	return lines.is_empty()


## Static helper to create dialogue from JSON data (for external dialogue files)
static func from_dict(data: Dictionary) -> DialogueData:
	var dialogue := DialogueData.new()
	dialogue.dialogue_id = data.get("id", "")

	var lines_data: Array = data.get("lines", [])
	for line_data in lines_data:
		var speaker: String = line_data.get("speaker", "system")
		var text: String = line_data.get("text", "")
		var choices: Array = line_data.get("choices", [])

		if choices.is_empty():
			dialogue.add_line(speaker, text)
		else:
			var choices_typed: Array[String] = []
			for c in choices:
				choices_typed.append(str(c))
			dialogue.add_choice(speaker, text, choices_typed)

	return dialogue
