extends Control
class_name ContestMinigame
## Eating contest minigame - head-to-head competition on dual conveyor belts

signal contest_finished(result: Dictionary)
signal contest_cancelled

# Contest state
enum State { SETUP, COUNTDOWN, PLAYING, FINISHED }
var _state: State = State.SETUP

# Character data
var _player_character: CharacterData
var _opponent_data: Dictionary = {}
var _rank_data: Dictionary = {}

# Food data
var _foods: Array[Dictionary] = []
var _food_categories: Array[String] = []

# Game state
var _time_remaining: float = 90.0
var _player_score: int = 0
var _cpu_score: int = 0
var _player_fullness: int = 0
var _cpu_fullness: int = 0
var _player_slowdown_stacks: int = 0
var _cpu_slowdown_stacks: int = 0
var _stack_decay_timer: float = 0.0
const STACK_DECAY_INTERVAL := 2.0  # Seconds per stack decay

# Conveyor belts - arrays of food items on each belt
var _belt_top: Array[Dictionary] = []  # Moving right, player advantage
var _belt_bottom: Array[Dictionary] = []  # Moving left, CPU advantage
var _spawn_timer: float = 0.0
const SPAWN_INTERVAL := 1.5
const BELT_SPEED := 100.0  # Pixels per second

# Player position and grabbing
var _player_y_position: int = 0  # 0 = center, -1 = top belt, 1 = bottom belt
var _player_grabbing: bool = false
var _player_eating: bool = false
var _player_eat_timer: float = 0.0
var _current_eating_food: Dictionary = {}

# CPU state
var _cpu_y_position: int = 0
var _cpu_grabbing: bool = false
var _cpu_eating: bool = false
var _cpu_eat_timer: float = 0.0
var _cpu_target_food: Dictionary = {}
var _cpu_decision_timer: float = 0.0

# Overstuffed mashing
var _mash_required: bool = false
var _mash_progress: float = 0.0
const MASH_THRESHOLD := 3.0  # Mashes needed to swallow when overstuffed

# Tolerance tracking (for after contest)
var _tolerance_gained: Dictionary = {}  # {category: count}

# Visual references
@onready var timer_label: Label = $UI/TimerLabel
@onready var player_score_label: Label = $UI/PlayerScoreLabel
@onready var cpu_score_label: Label = $UI/CPUScoreLabel
@onready var player_fullness_bar: ProgressBar = $UI/PlayerFullnessBar
@onready var cpu_fullness_bar: ProgressBar = $UI/CPUFullnessBar
@onready var player_stack_label: Label = $UI/PlayerStackLabel
@onready var cpu_stack_label: Label = $UI/CPUStackLabel
@onready var belt_top_container: Control = $BeltTop
@onready var belt_bottom_container: Control = $BeltBottom
@onready var player_sprite: Control = $PlayerSprite
@onready var cpu_sprite: Control = $CPUSprite
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var result_panel: PanelContainer = $UI/ResultPanel
@onready var hint_label: Label = $UI/HintLabel
@onready var mash_indicator: Control = $UI/MashIndicator


func _ready() -> void:
	_load_food_data()
	hide()


func _load_food_data() -> void:
	var file := FileAccess.open("res://data/contest_foods.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			_food_categories = Array(data.get("categories", []))
			for food in data.get("foods", []):
				_foods.append(food)
		file.close()


func start_contest(character: CharacterData, opponent: Dictionary, rank: Dictionary) -> void:
	_player_character = character
	_opponent_data = opponent
	_rank_data = rank

	# Reset state
	_state = State.COUNTDOWN
	_time_remaining = 90.0
	_player_score = 0
	_cpu_score = 0
	_player_fullness = 0
	_cpu_fullness = 0
	_player_slowdown_stacks = 0
	_cpu_slowdown_stacks = 0
	_stack_decay_timer = 0.0
	_belt_top.clear()
	_belt_bottom.clear()
	_spawn_timer = 0.0
	_player_y_position = 0
	_player_grabbing = false
	_player_eating = false
	_cpu_y_position = 0
	_cpu_grabbing = false
	_cpu_eating = false
	_cpu_target_food = {}
	_mash_required = false
	_mash_progress = 0.0
	_tolerance_gained.clear()

	_update_ui()
	show()

	# Start countdown
	_start_countdown()


func _start_countdown() -> void:
	countdown_label.show()
	countdown_label.text = "3"
	await get_tree().create_timer(1.0).timeout
	countdown_label.text = "2"
	await get_tree().create_timer(1.0).timeout
	countdown_label.text = "1"
	await get_tree().create_timer(1.0).timeout
	countdown_label.text = "GO!"
	await get_tree().create_timer(0.5).timeout
	countdown_label.hide()
	_state = State.PLAYING


func _process(delta: float) -> void:
	if not visible:
		return

	match _state:
		State.PLAYING:
			_process_game(delta)
		State.FINISHED:
			_process_finished(delta)


func _process_game(delta: float) -> void:
	# Update timer
	_time_remaining -= delta
	if _time_remaining <= 0:
		_time_remaining = 0
		_end_contest()
		return

	# Spawn food
	_spawn_timer += delta
	if _spawn_timer >= SPAWN_INTERVAL:
		_spawn_timer = 0.0
		_spawn_food()

	# Move belts
	_move_belts(delta)

	# Process eating timers
	_process_eating(delta)

	# Process stack decay
	_stack_decay_timer += delta
	if _stack_decay_timer >= STACK_DECAY_INTERVAL:
		_stack_decay_timer = 0.0
		if _player_slowdown_stacks > 0:
			_player_slowdown_stacks -= 1
		if _cpu_slowdown_stacks > 0:
			_cpu_slowdown_stacks -= 1

	# CPU AI
	_process_cpu_ai(delta)

	_update_ui()


func _process_finished(_delta: float) -> void:
	# Wait for input to close
	pass


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _state != State.PLAYING:
		return

	# Movement (W/S or Up/Down)
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		_move_player(-1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		_move_player(1)

	# Grab (E or ui_accept)
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		if _mash_required:
			_mash_progress += 1.0
			if _mash_progress >= MASH_THRESHOLD:
				_finish_eating_player()
		elif not _player_eating and not _player_grabbing:
			_try_grab_food()

	# Cancel (Q or ui_cancel)
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("back"):
		_cancel_contest()


func _move_player(direction: int) -> void:
	if _player_eating or _player_grabbing:
		return

	# Apply slowdown - slower movement with stacks
	var move_delay := 0.0
	if _player_slowdown_stacks > 0:
		move_delay = _player_slowdown_stacks * 0.1

	_player_y_position = clampi(_player_y_position + direction, -1, 1)
	_update_player_position()


func _try_grab_food() -> void:
	var belt: Array[Dictionary]
	if _player_y_position == -1:
		belt = _belt_top
	elif _player_y_position == 1:
		belt = _belt_bottom
	else:
		return  # In center, can't grab

	# Find closest food in grab range
	var grab_range := 80.0
	var player_x := 200.0  # Player's X position on belt

	for food in belt:
		var food_x: float = food.get("x", 0.0)
		if abs(food_x - player_x) < grab_range:
			_start_eating_player(food, belt)
			return


func _start_eating_player(food: Dictionary, belt: Array[Dictionary]) -> void:
	belt.erase(food)
	_player_eating = true
	_current_eating_food = food
	_player_eat_timer = 0.5  # Base eat time

	# Check if overstuffed
	var soft_cap := _player_character.stomach_capacity
	var food_fill: int = food.get("fill", 10)

	if _player_fullness + food_fill > soft_cap:
		_mash_required = true
		_mash_progress = 0.0


func _finish_eating_player() -> void:
	var food := _current_eating_food
	var category: String = food.get("category", "")
	var base_points: int = food.get("points", 50)
	var fill: int = food.get("fill", 10)

	# Calculate points with preference modifier
	var preference := _player_character.get_food_preference(category)
	var point_modifier := 1.0

	if preference == 1:  # Liked
		point_modifier = 1.5
	elif preference == -1:  # Disliked
		point_modifier = 0.75
		_player_slowdown_stacks += 1
		# Track tolerance
		if not _tolerance_gained.has(category):
			_tolerance_gained[category] = 0
		_tolerance_gained[category] += 1

	# Overstuffed bonus for followers (applied at end)
	var soft_cap := _player_character.stomach_capacity
	if _player_fullness >= soft_cap:
		point_modifier *= 1.25  # Fan bonus

	var final_points := int(base_points * point_modifier)
	_player_score += final_points
	_player_fullness += fill

	# Check for pass out
	var hard_cap := _player_character.get_contest_hard_cap()
	if _player_fullness >= hard_cap:
		_end_contest_pass_out(true)
		return

	_player_eating = false
	_mash_required = false
	_mash_progress = 0.0
	_current_eating_food = {}


func _process_eating(delta: float) -> void:
	if _player_eating and not _mash_required:
		_player_eat_timer -= delta
		if _player_eat_timer <= 0:
			_finish_eating_player()

	if _cpu_eating:
		_cpu_eat_timer -= delta
		if _cpu_eat_timer <= 0:
			_finish_eating_cpu()


func _spawn_food() -> void:
	if _foods.is_empty():
		return

	var food := _foods[randi() % _foods.size()].duplicate()

	# Spawn on random belt
	if randf() > 0.5:
		food["x"] = -50.0  # Start off-screen left (moves right)
		food["belt"] = "top"
		_belt_top.append(food)
	else:
		food["x"] = 850.0  # Start off-screen right (moves left)
		food["belt"] = "bottom"
		_belt_bottom.append(food)


func _move_belts(delta: float) -> void:
	# Top belt moves right
	for food in _belt_top:
		food["x"] += BELT_SPEED * delta

	# Bottom belt moves left
	for food in _belt_bottom:
		food["x"] -= BELT_SPEED * delta

	# Remove food that's off-screen
	_belt_top = _belt_top.filter(func(f): return f["x"] < 850.0)
	_belt_bottom = _belt_bottom.filter(func(f): return f["x"] > -50.0)


func _update_player_position() -> void:
	if not player_sprite:
		return

	var target_y := 300.0  # Center
	if _player_y_position == -1:
		target_y = 150.0  # Top belt
	elif _player_y_position == 1:
		target_y = 450.0  # Bottom belt

	player_sprite.position.y = target_y


# =============================================================================
# CPU AI
# =============================================================================

func _process_cpu_ai(delta: float) -> void:
	if _cpu_eating:
		return

	_cpu_decision_timer += delta

	var decision_delay: float = _get_cpu_reaction_delay()
	if _cpu_decision_timer < decision_delay:
		return

	_cpu_decision_timer = 0.0

	# Find best food to go for
	var best_food := _find_best_cpu_target()

	if best_food.is_empty():
		# Move toward center if no target
		if _cpu_y_position != 0:
			_cpu_y_position = 0
		return

	_cpu_target_food = best_food

	# Move toward target belt
	var target_belt: String = best_food.get("belt", "")
	if target_belt == "top" and _cpu_y_position != -1:
		_cpu_y_position = -1
	elif target_belt == "bottom" and _cpu_y_position != 1:
		_cpu_y_position = 1

	# Try to grab if in range
	_try_grab_cpu()


func _get_cpu_reaction_delay() -> float:
	var difficulty: String = _rank_data.get("difficulty", "easy")
	match difficulty:
		"easy": return 0.8
		"medium": return 0.5
		"hard": return 0.25
		_: return 0.8


func _find_best_cpu_target() -> Dictionary:
	var personality: String = _opponent_data.get("personality", "greedy")
	var likes: Array = _opponent_data.get("likes", [])
	var dislikes: Array = _opponent_data.get("dislikes", [])
	var decision_quality: float = _get_decision_quality()

	var best_food: Dictionary = {}
	var best_score := -999.0

	# Check both belts
	var all_foods: Array[Dictionary] = []
	all_foods.append_array(_belt_top)
	all_foods.append_array(_belt_bottom)

	for food in all_foods:
		var category: String = food.get("category", "")
		var food_x: float = food.get("x", 0.0)
		var belt: String = food.get("belt", "")

		# Score based on personality
		var score := 0.0
		var base_points: int = food.get("points", 50)

		# Preference scoring
		if category in likes:
			score += base_points * 1.5
		elif category in dislikes:
			score -= 50  # Avoid disliked
		else:
			score += base_points

		# Personality modifiers
		match personality:
			"greedy":
				# Prioritize high value food
				score += base_points * 0.5
			"sniper":
				# Only go for liked food
				if category not in likes:
					score -= 200
			"bully":
				# TODO: Factor in if player is going for it
				pass
			"cautious":
				# Prefer home belt (bottom for CPU)
				if belt == "bottom":
					score += 30
				else:
					score -= 50

		# Distance factor - prefer closer food
		var cpu_x := 600.0  # CPU's X position
		var distance := abs(food_x - cpu_x)
		score -= distance * 0.1

		# Random factor based on decision quality
		if randf() > decision_quality:
			score += randf_range(-50, 50)

		if score > best_score:
			best_score = score
			best_food = food

	return best_food


func _get_decision_quality() -> float:
	var difficulty: String = _rank_data.get("difficulty", "easy")
	match difficulty:
		"easy": return 0.5
		"medium": return 0.75
		"hard": return 0.95
		_: return 0.5


func _try_grab_cpu() -> void:
	if _cpu_target_food.is_empty():
		return

	var belt: Array[Dictionary]
	if _cpu_y_position == -1:
		belt = _belt_top
	elif _cpu_y_position == 1:
		belt = _belt_bottom
	else:
		return

	var grab_range := 80.0
	var cpu_x := 600.0

	var food_x: float = _cpu_target_food.get("x", 0.0)
	if abs(food_x - cpu_x) < grab_range and _cpu_target_food in belt:
		_start_eating_cpu(_cpu_target_food, belt)


func _start_eating_cpu(food: Dictionary, belt: Array[Dictionary]) -> void:
	belt.erase(food)
	_cpu_eating = true
	_cpu_eat_timer = 0.5
	_cpu_target_food = food


func _finish_eating_cpu() -> void:
	var food := _cpu_target_food
	var category: String = food.get("category", "")
	var base_points: int = food.get("points", 50)
	var fill: int = food.get("fill", 10)

	var likes: Array = _opponent_data.get("likes", [])
	var dislikes: Array = _opponent_data.get("dislikes", [])

	var point_modifier := 1.0
	if category in likes:
		point_modifier = 1.5
		# TODO: Show heart visual
	elif category in dislikes:
		point_modifier = 0.75
		_cpu_slowdown_stacks += 1
		# TODO: Show grimace visual

	var final_points := int(base_points * point_modifier)
	_cpu_score += final_points
	_cpu_fullness += fill

	# Check for CPU pass out
	var cpu_hard_cap: int = _opponent_data.get("capacity", 100) + _opponent_data.get("stuffing_skill", 1) * 10
	if _cpu_fullness >= cpu_hard_cap:
		_end_contest_pass_out(false)
		return

	_cpu_eating = false
	_cpu_target_food = {}


# =============================================================================
# END CONTEST
# =============================================================================

func _end_contest() -> void:
	_state = State.FINISHED

	var won := _player_score > _cpu_score

	# Apply tolerance gains
	for category in _tolerance_gained:
		var count: int = _tolerance_gained[category]
		for i in range(count):
			_player_character.add_food_tolerance(category)

	# Calculate rewards
	var rewards := {
		"won": won,
		"player_score": _player_score,
		"cpu_score": _cpu_score,
		"tolerance_gained": _tolerance_gained
	}

	if won:
		rewards["money"] = _rank_data.get("prize_money", 100)
		rewards["xp"] = _rank_data.get("prize_xp", 10)
		rewards["followers"] = _rank_data.get("prize_followers", 50)

		# Check if rank was beaten
		var rank_index := _get_rank_index(_rank_data.get("id", "beginner"))
		if rank_index > _player_character.contest_highest_rank:
			_player_character.contest_highest_rank = rank_index
			rewards["rank_up"] = true

	_show_results(rewards)


func _end_contest_pass_out(player_passed_out: bool) -> void:
	_state = State.FINISHED

	# Apply tolerance even on pass out
	for category in _tolerance_gained:
		var count: int = _tolerance_gained[category]
		for i in range(count):
			_player_character.add_food_tolerance(category)

	var rewards := {
		"won": not player_passed_out,
		"player_score": _player_score,
		"cpu_score": _cpu_score,
		"passed_out": player_passed_out,
		"tolerance_gained": _tolerance_gained
	}

	if not player_passed_out:
		rewards["money"] = _rank_data.get("prize_money", 100)
		rewards["xp"] = _rank_data.get("prize_xp", 10)
		rewards["followers"] = _rank_data.get("prize_followers", 50)

	_show_results(rewards)


func _get_rank_index(rank_id: String) -> int:
	match rank_id:
		"beginner": return 0
		"amateur": return 1
		"pro": return 2
		"elite": return 3
		_: return 0


func _show_results(rewards: Dictionary) -> void:
	result_panel.show()

	var result_text := ""
	if rewards.get("passed_out", false):
		result_text = "PASSED OUT!\n\n"
	elif rewards.get("won", false):
		result_text = "VICTORY!\n\n"
	else:
		result_text = "DEFEAT\n\n"

	result_text += "Your Score: %d\n" % rewards.get("player_score", 0)
	result_text += "CPU Score: %d\n\n" % rewards.get("cpu_score", 0)

	if rewards.get("won", false):
		result_text += "Rewards:\n"
		result_text += "  $%d\n" % rewards.get("money", 0)
		result_text += "  +%d XP\n" % rewards.get("xp", 0)
		result_text += "  +%d Followers\n" % rewards.get("followers", 0)
		if rewards.get("rank_up", false):
			result_text += "\n  RANK UP!"

	# Show tolerance progress
	var tolerance: Dictionary = rewards.get("tolerance_gained", {})
	if not tolerance.is_empty():
		result_text += "\n\nTolerance Progress:"
		for category in tolerance:
			result_text += "\n  %s: +%d" % [category.capitalize(), tolerance[category]]

	result_text += "\n\nPress E to continue"

	var result_label: Label = result_panel.get_node_or_null("ResultLabel")
	if result_label:
		result_label.text = result_text

	# Wait for input to finish
	await _wait_for_continue()

	result_panel.hide()
	hide()
	contest_finished.emit(rewards)


func _wait_for_continue() -> void:
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact"):
			break


func _cancel_contest() -> void:
	hide()
	contest_cancelled.emit()


# =============================================================================
# UI UPDATE
# =============================================================================

func _update_ui() -> void:
	if not visible:
		return

	# Timer
	if timer_label:
		var minutes := int(_time_remaining) / 60
		var seconds := int(_time_remaining) % 60
		timer_label.text = "%d:%02d" % [minutes, seconds]

	# Scores
	if player_score_label:
		player_score_label.text = "You: %d" % _player_score
	if cpu_score_label:
		cpu_score_label.text = "%s: %d" % [_opponent_data.get("name", "CPU"), _cpu_score]

	# Fullness bars
	if player_fullness_bar:
		var soft_cap := _player_character.stomach_capacity if _player_character else 100
		player_fullness_bar.max_value = soft_cap
		player_fullness_bar.value = _player_fullness
		# Color based on zone
		if _player_fullness >= soft_cap:
			player_fullness_bar.modulate = Color(1.0, 0.5, 0.0)  # Orange for overstuffed
		else:
			player_fullness_bar.modulate = Color(1.0, 1.0, 1.0)

	if cpu_fullness_bar:
		var cpu_cap: int = _opponent_data.get("capacity", 100)
		cpu_fullness_bar.max_value = cpu_cap
		cpu_fullness_bar.value = _cpu_fullness

	# Slowdown stacks
	if player_stack_label:
		player_stack_label.text = "[%d]" % _player_slowdown_stacks if _player_slowdown_stacks > 0 else ""
	if cpu_stack_label:
		cpu_stack_label.text = "[%d]" % _cpu_slowdown_stacks if _cpu_slowdown_stacks > 0 else ""

	# Mash indicator
	if mash_indicator:
		mash_indicator.visible = _mash_required

	# Hint
	if hint_label:
		if _mash_required:
			hint_label.text = "MASH E TO SWALLOW! (%.0f/%.0f)" % [_mash_progress, MASH_THRESHOLD]
		elif _player_eating:
			hint_label.text = "Eating..."
		else:
			hint_label.text = "W/S: Move | E: Grab | Q: Quit"

	# Update belt visuals
	_update_belt_visuals()


func _update_belt_visuals() -> void:
	# This would update food item positions on screen
	# For now, we'll rely on the scene having the visual nodes
	pass
