extends PanelContainer
class_name ContestSetupDialog
## Dialog for setting up a contest entry - select rank, view opponent, pay entry fee

signal contest_started(character: CharacterData, opponent: Dictionary, rank: Dictionary)
signal dialog_closed

var _character: CharacterData
var _ranks: Array[Dictionary] = []
var _opponents: Array[Dictionary] = []
var _difficulty_settings: Dictionary = {}
var _selected_rank_index: int = 0
var _selected_opponent: Dictionary = {}

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var rank_list: VBoxContainer = $MarginContainer/VBox/HBox/RankPanel/RankList
@onready var opponent_label: Label = $MarginContainer/VBox/HBox/InfoPanel/OpponentLabel
@onready var stats_label: Label = $MarginContainer/VBox/HBox/InfoPanel/StatsLabel
@onready var rewards_label: Label = $MarginContainer/VBox/HBox/InfoPanel/RewardsLabel
@onready var entry_fee_label: Label = $MarginContainer/VBox/EntryFeeLabel
@onready var hint_label: Label = $MarginContainer/VBox/HintLabel


func _ready() -> void:
	hide()
	_load_contest_data()


func _load_contest_data() -> void:
	var file := FileAccess.open("res://data/contest_opponents.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			for rank in data.get("ranks", []):
				_ranks.append(rank)
			for opp in data.get("opponents", []):
				_opponents.append(opp)
			_difficulty_settings = data.get("difficulty_settings", {})
		file.close()


func open_dialog(character: CharacterData) -> void:
	_character = character
	_selected_rank_index = character.contest_rank

	# Clamp to highest unlocked rank
	var max_rank := mini(character.contest_highest_rank + 1, _ranks.size() - 1)
	_selected_rank_index = mini(_selected_rank_index, max_rank)

	_select_random_opponent()
	_refresh_display()
	show()
	GameManager.is_paused = true


func close_dialog() -> void:
	hide()
	GameManager.is_paused = false
	dialog_closed.emit()


func _select_random_opponent() -> void:
	if _opponents.is_empty():
		_selected_opponent = {}
		return

	# Pick a random opponent
	_selected_opponent = _opponents[randi() % _opponents.size()]


func _refresh_display() -> void:
	if not _character:
		return

	title_label.text = "%s - Contest Entry" % _character.display_name
	_refresh_rank_list()
	_refresh_opponent_info()
	_refresh_rewards_info()
	_update_entry_fee()
	_update_hint()


func _refresh_rank_list() -> void:
	for child in rank_list.get_children():
		child.queue_free()

	var max_unlocked := _character.contest_highest_rank + 1

	for i in range(_ranks.size()):
		var rank := _ranks[i]
		var btn := Button.new()
		btn.text = rank.get("name", "???")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(120, 30)

		# Lock ranks not yet unlocked
		if i > max_unlocked:
			btn.text += " [LOCKED]"
			btn.modulate = Color(0.5, 0.5, 0.5)
		elif i == _selected_rank_index:
			btn.text = "> " + btn.text

		# Can't afford?
		var entry_fee: int = rank.get("entry_fee", 0)
		if entry_fee > GameManager.money:
			btn.modulate = Color(0.7, 0.5, 0.5)

		rank_list.add_child(btn)

	await get_tree().process_frame
	_update_selection_visuals()


func _refresh_opponent_info() -> void:
	if _selected_opponent.is_empty():
		opponent_label.text = "Opponent: ???"
		stats_label.text = ""
		return

	opponent_label.text = "Opponent: %s" % _selected_opponent.get("name", "???")

	var personality: String = _selected_opponent.get("personality", "unknown")
	var likes: Array = _selected_opponent.get("likes", [])
	var dislikes: Array = _selected_opponent.get("dislikes", [])

	var stats_text := "Style: %s\n" % personality.capitalize()
	stats_text += "Capacity: %d\n" % _selected_opponent.get("capacity", 100)
	stats_text += "\nPreferences: ???"  # Hidden until discovered

	stats_label.text = stats_text


func _refresh_rewards_info() -> void:
	if _selected_rank_index >= _ranks.size():
		rewards_label.text = ""
		return

	var rank := _ranks[_selected_rank_index]
	var rewards_text := "Rewards (Win):\n"
	rewards_text += "  $%d\n" % rank.get("prize_money", 0)
	rewards_text += "  +%d XP\n" % rank.get("prize_xp", 0)
	rewards_text += "  +%d Followers" % rank.get("prize_followers", 0)

	rewards_label.text = rewards_text


func _update_entry_fee() -> void:
	if _selected_rank_index >= _ranks.size():
		entry_fee_label.text = ""
		return

	var rank := _ranks[_selected_rank_index]
	var fee: int = rank.get("entry_fee", 0)
	var can_afford := GameManager.money >= fee

	entry_fee_label.text = "Entry Fee: $%d" % fee
	if not can_afford:
		entry_fee_label.text += " (Can't afford!)"
		entry_fee_label.modulate = Color(1.0, 0.5, 0.5)
	else:
		entry_fee_label.modulate = Color(1.0, 1.0, 1.0)


func _update_hint() -> void:
	var current_day: int = TimeManager.current_day if TimeManager else 0
	var can_contest := _character.can_enter_contest(current_day)

	if not can_contest:
		hint_label.text = "Already competed today! Come back tomorrow."
	else:
		hint_label.text = "W/S: Select Rank | E: Enter Contest | Q: Back"


func _update_selection_visuals() -> void:
	var buttons := rank_list.get_children()
	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		btn.flat = (i != _selected_rank_index)
		if i == _selected_rank_index:
			btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	var max_unlocked := _character.contest_highest_rank + 1

	# Navigation
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		_selected_rank_index = maxi(0, _selected_rank_index - 1)
		_refresh_display()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		_selected_rank_index = mini(max_unlocked, mini(_ranks.size() - 1, _selected_rank_index + 1))
		_refresh_display()

	# Enter contest
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_try_enter_contest()

	# Cancel
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("back"):
		close_dialog()


func _try_enter_contest() -> void:
	if _selected_rank_index >= _ranks.size():
		return

	var rank := _ranks[_selected_rank_index]
	var fee: int = rank.get("entry_fee", 0)

	# Check if can afford
	if GameManager.money < fee:
		return

	# Check if already competed today
	var current_day: int = TimeManager.current_day if TimeManager else 0
	if not _character.can_enter_contest(current_day):
		return

	# Deduct entry fee
	GameManager.add_money(-fee)

	# Mark as competed today
	_character.last_contest_day = current_day

	hide()
	GameManager.is_paused = false
	contest_started.emit(_character, _selected_opponent, rank)
