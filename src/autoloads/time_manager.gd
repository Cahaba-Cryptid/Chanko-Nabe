extends Node
## Manages game time, day/night cycle, and scheduling

signal time_updated(hour: int, minute: int)
signal period_changed(period: String)
signal day_started()
signal day_ended()
signal task_completed(character: CharacterData, task: TaskData)
signal activity_logged(message: String)

enum TimePeriod { MORNING, AFTERNOON, EVENING, NIGHT }

const MINUTE_INCREMENT := 10
const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const DAY_START_HOUR := 6
const DAY_END_HOUR := 22

@export var time_scale: float = 1.0  # Ticks per real second (each tick = 10 game minutes)
@export var auto_advance_days: bool = true

var current_hour: int = 8
var current_minute: int = 0
var is_running: bool = false
var _accumulated_time: float = 0.0

var _active_assignments: Array[Dictionary] = []  # {character, task, location, time_remaining}
var _task_original_durations: Dictionary = {}  # character_id -> original duration


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if not is_running:
		return

	if GameManager.is_paused:
		return

	_accumulated_time += delta * time_scale

	while _accumulated_time >= 1.0:
		_accumulated_time -= 1.0
		_advance_minute()


func _advance_minute() -> void:
	current_minute += MINUTE_INCREMENT

	if current_minute >= MINUTES_PER_HOUR:
		current_minute = 0
		_advance_hour()

	time_updated.emit(current_hour, current_minute)
	_update_assignments()
	_process_hunger_mood_fatigue()
	_process_milk_production()


func _advance_hour() -> void:
	var old_period := get_current_period()
	current_hour += 1

	if current_hour >= HOURS_PER_DAY:
		current_hour = 0

	var new_period := get_current_period()
	if old_period != new_period:
		period_changed.emit(get_period_name(new_period))

	if current_hour == DAY_END_HOUR and auto_advance_days:
		_end_day()


func _end_day() -> void:
	day_ended.emit()
	_process_end_of_day()

	# Check quota at end of week (before advancing day)
	if GameManager.is_week_end():
		GameManager.process_end_of_week()
	elif GameManager.grace_period_active:
		GameManager.process_grace_day()

	GameManager.advance_day()
	_start_new_day()


func _start_new_day() -> void:
	current_hour = DAY_START_HOUR
	current_minute = 0
	day_started.emit()


func _process_end_of_day() -> void:
	# Pay salaries (Licensee player reduces NPC salaries)
	var player := _get_player_character()
	var salary_reduction := 0.0
	if player:
		salary_reduction = player.get_archetype_passive("npc_salary_reduction", 0.0)

	var total_salary := 0
	for character in GameManager.characters:
		if character.is_player:
			continue  # Player doesn't pay themselves
		var salary: int = character.daily_salary
		if salary_reduction > 0.0:
			salary = int(float(salary) * (1.0 - salary_reduction))
		total_salary += salary

	GameManager.spend_money(total_salary)

	# Process follower decay for all characters
	_process_follower_decay()

	# Process burnout recovery for all characters
	_process_burnout_recovery()

	# Clear remaining assignments
	for assignment in _active_assignments:
		var character: CharacterData = assignment["character"]
		character.clear_assignment()
	_active_assignments.clear()


func _process_burnout_recovery() -> void:
	## Tick down burnout debuff durations at end of day
	for character in GameManager.characters:
		if character.burnout_days_remaining > 0:
			var old_penalty: int = character.burnout_charm_penalty
			character.tick_burnout()
			if character.burnout_days_remaining <= 0:
				var msg := "%s recovered from burnout (charm restored)" % character.display_name
				activity_logged.emit(msg)
				print(msg)


func _process_follower_decay() -> void:
	## Process follower decay for all characters at end of day
	## Followers decay if character hasn't streamed or socialized recently
	## Charm stat slows decay rate
	const BASE_DECAY_PERCENT := 5.0  # 5% decay per day without activity
	const DAYS_BEFORE_DECAY := 1  # Grace period before decay starts

	for character in GameManager.characters:
		var days_since_stream: int = GameManager.current_day - character.last_stream_day
		var days_since_socialize: int = GameManager.current_day - character.last_socialize_day
		var days_inactive: int = mini(days_since_stream, days_since_socialize)

		# No decay if they've been active within grace period
		if days_inactive <= DAYS_BEFORE_DECAY:
			continue

		# Calculate decay - charm reduces it (0 charm = full decay, 100 charm = 50% decay)
		var charm_reduction: float = character.charm / 200.0  # 0.0 to 0.5
		var decay_percent: float = BASE_DECAY_PERCENT * (1.0 - charm_reduction)

		# E-Girl and Cybergoth archetype reduce follower decay
		var decay_reduction: float = character.get_archetype_passive("follower_decay_reduction", 0.0)
		decay_percent *= (1.0 - decay_reduction)

		var decay_amount: int = int(character.followers * decay_percent / 100.0)

		# Minimum decay of 1 if they have followers
		if character.followers > 0 and decay_amount < 1:
			decay_amount = 1

		var old_followers: int = character.followers
		character.followers = maxi(0, character.followers - decay_amount)

		if decay_amount > 0:
			var msg := "%s lost %d followers (inactive)" % [character.display_name, decay_amount]
			activity_logged.emit(msg)
			print(msg)


func _process_hunger_mood_fatigue() -> void:
	## Process hunger/mood/fatigue effects every game tick (10 minutes)
	## - Empty stomach (fullness 0) drains mood
	## - Low mood (below 20) increases fatigue
	## - Eating (fullness > 0) slowly restores mood if hungry
	const HUNGER_MOOD_DRAIN := 1  # Mood lost per tick when stomach empty
	const LOW_MOOD_THRESHOLD := 20  # Below this, fatigue builds
	const FATIGUE_GAIN_RATE := 2  # Fatigue gained per tick when mood is low
	const EATING_MOOD_RESTORE := 1  # Mood restored per tick when fed and mood < 50

	for character in GameManager.characters:
		# Skip if character is busy (they're focused on task)
		if character.is_busy():
			continue

		var old_fatigue: int = character.fatigue
		var old_mood: int = character.mood

		# Hunger affects mood
		if character.stomach_fullness == 0:
			# Empty stomach - mood drops
			character.modify_mood(-HUNGER_MOOD_DRAIN)
		elif character.mood < 50:
			# Has food in stomach and mood is below neutral - slowly recover mood
			character.modify_mood(EATING_MOOD_RESTORE)

		# Low mood causes fatigue buildup
		if character.mood < LOW_MOOD_THRESHOLD:
			character.modify_fatigue(FATIGUE_GAIN_RATE)
		elif character.fatigue > 0 and character.mood >= 50:
			# If mood is decent, slowly recover from fatigue
			character.modify_fatigue(-1)

		# Log exhaustion events
		if character.fatigue >= 100 and old_fatigue < 100:
			var msg := "%s is exhausted and can't work!" % character.display_name
			activity_logged.emit(msg)
			print(msg)


func _process_milk_production() -> void:
	## Process milk production and discomfort for lactating characters every tick
	## Production rate scales with weight, fullness, and BB factor
	## Being at max capacity causes discomfort that builds over time
	const BASE_PRODUCTION := 1  # Base milk produced per tick
	const DISCOMFORT_MOOD_PENALTY := 1  # Mood lost per tick when full
	const SEVERE_DISCOMFORT_THRESHOLD := 10  # Ticks until severe discomfort
	const SEVERE_ENERGY_PENALTY := 1  # Energy lost per tick at severe discomfort

	for character in GameManager.characters:
		if not character.is_lactating:
			continue

		# If at capacity, accumulate discomfort instead of producing
		if character.is_milk_full():
			character.milk_full_ticks += 1

			# Apply discomfort penalties
			character.modify_mood(-DISCOMFORT_MOOD_PENALTY)

			# Severe discomfort (10+ ticks) also drains energy
			if character.milk_full_ticks >= SEVERE_DISCOMFORT_THRESHOLD:
				character.modify_energy(-SEVERE_ENERGY_PENALTY)

			# Log when hitting thresholds
			if character.milk_full_ticks == 1:
				var msg := "%s's milk storage is full!" % character.display_name
				activity_logged.emit(msg)
			elif character.milk_full_ticks == SEVERE_DISCOMFORT_THRESHOLD:
				var msg := "%s is in severe discomfort from being too full!" % character.display_name
				activity_logged.emit(msg)
		else:
			# Reset discomfort if not full
			character.milk_full_ticks = 0

			# Calculate production rate
			# Base rate modified by: weight (+1% per 10 lbs over 100), fullness (+50% when stomach full), BB factor (+25% per BB)
			var production := float(BASE_PRODUCTION)

			# Weight bonus: heavier = more production
			var weight_bonus := maxf(0.0, (character.weight - 100) / 1000.0)  # +0.1% per lb over 100
			production *= (1.0 + weight_bonus)

			# Fullness bonus: full stomach = more production
			var fullness_ratio := float(character.stomach_fullness) / float(character.stomach_capacity)
			production *= (1.0 + fullness_ratio * 0.5)  # Up to +50% at full stomach

			# BB factor bonus: pregnancy increases production
			production *= (1.0 + character.bb_factor * 0.25)  # +25% per BB factor

			# Hucow archetype bonus
			var hucow_bonus: float = character.get_archetype_passive("milk_production_bonus", 0.0)
			production *= (1.0 + hucow_bonus)

			# Add milk (capped by capacity)
			var produced := int(production)
			if produced > 0:
				character.add_milk(produced)

			# Warn at 80% capacity
			var milk_percent: float = character.get_milk_percent()
			if milk_percent >= 80.0 and milk_percent - (float(produced) / float(character.milk_capacity) * 100.0) < 80.0:
				var msg := "%s's milk storage is at %d%% - consider milking soon" % [character.display_name, int(milk_percent)]
				activity_logged.emit(msg)


func _update_assignments() -> void:
	var completed: Array[Dictionary] = []

	for assignment in _active_assignments:
		assignment["time_remaining"] -= MINUTE_INCREMENT

		var character: CharacterData = assignment["character"]
		character.task_time_remaining = assignment["time_remaining"]

		if assignment["time_remaining"] <= 0:
			completed.append(assignment)

	for assignment in completed:
		_complete_assignment(assignment)


func _complete_assignment(assignment: Dictionary) -> void:
	var character: CharacterData = assignment["character"]
	var task: TaskData = assignment["task"]
	var location: LocationData = assignment["location"]

	var results := task.apply_results(character, location)

	GameManager.add_money(results["income"])
	character.clear_assignment()

	_active_assignments.erase(assignment)
	task_completed.emit(character, task)


func start_time() -> void:
	is_running = true


func stop_time() -> void:
	is_running = false


func set_time(hour: int, minute: int = 0) -> void:
	current_hour = clamp(hour, 0, 23)
	current_minute = clamp(minute, 0, 59)
	time_updated.emit(current_hour, current_minute)


func get_current_period() -> TimePeriod:
	if current_hour >= 6 and current_hour < 12:
		return TimePeriod.MORNING
	elif current_hour >= 12 and current_hour < 17:
		return TimePeriod.AFTERNOON
	elif current_hour >= 17 and current_hour < 21:
		return TimePeriod.EVENING
	else:
		return TimePeriod.NIGHT


func get_period_name(period: TimePeriod) -> String:
	match period:
		TimePeriod.MORNING:
			return "Morning"
		TimePeriod.AFTERNOON:
			return "Afternoon"
		TimePeriod.EVENING:
			return "Evening"
		TimePeriod.NIGHT:
			return "Night"
	return "Unknown"


func get_time_string() -> String:
	return "%02d:%02d" % [current_hour, current_minute]


func get_remaining_day_time() -> float:
	# Returns minutes until day ends
	var remaining_hours := DAY_END_HOUR - current_hour
	var remaining_minutes := MINUTES_PER_HOUR - current_minute
	return (remaining_hours * MINUTES_PER_HOUR) + remaining_minutes


func assign_character_to_task(character: CharacterData, task: TaskData, location: LocationData) -> bool:
	if not character.is_available():
		return false

	if not task.can_perform(character):
		return false

	if location and not location.character_meets_requirements(character):
		return false

	var duration := task.base_duration
	character.assign_to_location(location.id if location else "", task.id, duration)

	_active_assignments.append({
		"character": character,
		"task": task,
		"location": location,
		"time_remaining": duration
	})

	return true


func cancel_assignment(character: CharacterData) -> void:
	for i in range(_active_assignments.size() - 1, -1, -1):
		if _active_assignments[i]["character"] == character:
			_active_assignments.remove_at(i)
			character.clear_assignment()
			break


func get_active_assignment_count() -> int:
	return _active_assignments.size()


func skip_time(minutes: float) -> void:
	## Fast-forward time by specified minutes, processing all character tasks
	var remaining := minutes

	# Store original durations for characters starting tasks
	for character in GameManager.characters:
		if character.task_time_remaining > 0 and not _task_original_durations.has(character.id):
			_task_original_durations[character.id] = character.task_time_remaining

	while remaining > 0:
		var tick := minf(remaining, float(MINUTE_INCREMENT))
		remaining -= tick

		# Process character task timers
		for character in GameManager.characters:
			if character.task_time_remaining > 0:
				character.task_time_remaining -= tick
				if character.task_time_remaining <= 0:
					var original_duration: float = _task_original_durations.get(character.id, 0.0)
					_task_original_durations.erase(character.id)
					_on_character_task_complete(character, original_duration)

		# Process hunger/mood/fatigue during skip
		_process_hunger_mood_fatigue()

		# Advance game time
		current_minute += int(tick)
		while current_minute >= MINUTES_PER_HOUR:
			current_minute -= MINUTES_PER_HOUR
			_advance_hour()

	time_updated.emit(current_hour, current_minute)


func _on_character_task_complete(character: CharacterData, original_duration: float = 0.0) -> void:
	## Called when a character's timed task finishes
	var station_name := character.current_task_id
	character.task_time_remaining = 0.0
	character.current_task_id = ""

	# Special handling for different station types
	match station_name:
		"Relax":
			_complete_relax_task(character, original_duration)
		"Binge":
			_complete_binge_task(character)
		"Contest":
			_complete_contest_task(character)
		"Socialize":
			_complete_socialize_task(character)
		"Dr. Dan's":
			_complete_dr_dan_task(character)
		"Cam Studio":
			_complete_stream_task(character)
		"Milking":
			_complete_milking_task(character)
		_:
			_complete_standard_task(character, station_name)


func _complete_standard_task(character: CharacterData, station_name: String) -> void:
	## Standard station completion - generates income based on followers, drains energy
	# Base income scales with followers: $1 per 100 followers, minimum $10
	var follower_income := maxi(10, character.followers / 100)
	var licensee_bonus := _get_licensee_effectiveness_bonus()
	var effectiveness := character.get_effectiveness(licensee_bonus) / 100.0
	var raw_income := follower_income * (0.5 + effectiveness)

	# Pregnancy bonus: BB factor increases stream income (+10% per BB)
	if character.bb_factor > 0:
		var pregnancy_bonus := character.bb_factor * 0.10
		# Breeder archetype: +15% surrogacy/pregnancy income
		var surrogacy_bonus: float = character.get_archetype_passive("surrogacy_income_bonus", 0.0)
		pregnancy_bonus *= (1.0 + surrogacy_bonus)
		raw_income *= (1.0 + pregnancy_bonus)

	# Body size bonus: Bigger = better (+5% per belly tier, +5% per bust tier)
	var belly_bonus := character.get_belly_tier() * 0.05
	var bust_bonus := character.get_bust_tier() * 0.05
	raw_income *= (1.0 + belly_bonus + bust_bonus)

	# CammTec takes their cut (40%)
	var after_cut := raw_income * (1.0 - GameManager.CAMMTEC_CUT_PERCENT)
	# House always wins - round down to nearest 5
	var final_income := int(after_cut / 5) * 5

	GameManager.add_money(final_income)
	character.add_experience(10)
	_apply_energy_drain(character, 15)

	# Track last stream day for follower decay
	character.last_stream_day = GameManager.current_day

	var activity_msg := "%s streamed and earned $%d (after CammTec cut)" % [character.display_name, final_income]
	activity_logged.emit(activity_msg)
	print(activity_msg)


func _complete_relax_task(character: CharacterData, original_duration: float) -> void:
	## Relax station - restores energy based on time spent
	const ENERGY_PER_HOUR := 10

	var old_energy := character.energy
	var hours_relaxed := original_duration / 60.0
	var energy_restored := int(hours_relaxed * ENERGY_PER_HOUR)

	character.modify_energy(energy_restored)
	var actual_restored := character.energy - old_energy

	var activity_msg := "%s relaxed for %d hours and recovered %d energy" % [character.display_name, int(hours_relaxed), actual_restored]
	activity_logged.emit(activity_msg)
	print(activity_msg)


func _complete_contest_task(character: CharacterData) -> void:
	## Eating contest - placeholder for future functionality
	character.add_experience(15)
	_apply_energy_drain(character, 20)

	var activity_msg := "%s participated in an eating contest" % character.display_name
	activity_logged.emit(activity_msg)
	print(activity_msg)


func _complete_socialize_task(character: CharacterData) -> void:
	## Socialize - helps maintain followers and gain new ones
	character.add_experience(5)
	_apply_energy_drain(character, 10)
	character.modify_mood(10)

	# Track last socialize day for follower decay
	character.last_socialize_day = GameManager.current_day

	# Gain some followers from socializing (charm helps)
	var charm_bonus := character.charm / 50.0  # 0-2x multiplier
	var followers_gained := int(10 * charm_bonus)

	# E-Girl archetype bonus: +20% socializing gains
	var socialize_bonus: float = character.get_archetype_passive("socializing_bonus", 0.0)
	followers_gained = int(float(followers_gained) * (1.0 + socialize_bonus))

	character.followers += followers_gained

	var activity_msg := "%s went socializing (+%d followers)" % [character.display_name, followers_gained]
	activity_logged.emit(activity_msg)
	print(activity_msg)


func _complete_stream_task(character: CharacterData) -> void:
	## Stream completion - process food eaten on stream, generate income with quality multiplier
	var stream_data: Dictionary = character.pending_stream_data
	var kit_name: String = stream_data.get("kit_name", "Standard Stream")
	var quality_mult: float = stream_data.get("quality_multiplier", 1.0)
	var total_fill: int = stream_data.get("total_fill", 0)
	var kit_contents: Array = stream_data.get("kit_contents", [])
	var added_items: Array = stream_data.get("added_items", [])
	var stream_kinks: Array = stream_data.get("stream_kinks", [])

	# Calculate base income from followers
	var follower_income := maxi(10, character.followers / 100)
	var licensee_bonus := _get_licensee_effectiveness_bonus()
	var effectiveness := character.get_effectiveness(licensee_bonus) / 100.0
	var raw_income := follower_income * (0.5 + effectiveness) * quality_mult

	# Audience match multiplier - how well stream content matches follower preferences
	var audience_match := character.get_audience_match(stream_kinks)
	raw_income *= audience_match

	# Pregnancy bonus: BB factor increases stream income (+10% per BB)
	if character.bb_factor > 0:
		var pregnancy_bonus := character.bb_factor * 0.10
		# Breeder archetype: +15% surrogacy/pregnancy income
		var surrogacy_bonus: float = character.get_archetype_passive("surrogacy_income_bonus", 0.0)
		pregnancy_bonus *= (1.0 + surrogacy_bonus)
		raw_income *= (1.0 + pregnancy_bonus)

	# Body size bonus: Bigger = better (+5% per belly tier, +5% per bust tier)
	var belly_bonus := character.get_belly_tier() * 0.05
	var bust_bonus := character.get_bust_tier() * 0.05
	raw_income *= (1.0 + belly_bonus + bust_bonus)

	# CammTec takes their cut (40%)
	var after_cut := raw_income * (1.0 - GameManager.CAMMTEC_CUT_PERCENT)
	var final_income := maxi(25, int(after_cut / 5) * 5)  # Round down to nearest $5, minimum $25

	# Shift audience preferences toward this stream's kinks (5% per stream)
	character.shift_audience_preferences(stream_kinks)

	GameManager.add_money(final_income)
	character.add_experience(15)
	_apply_energy_drain(character, 20)

	# Track last stream day for follower decay
	character.last_stream_day = GameManager.current_day

	# Process food consumption from stream (kit contents + added items)
	var items_eaten := 0

	# Process kit contents - look up fill values from vendi_items.json
	for content in kit_contents:
		var item_id: String = content.get("id", "")
		var qty: int = content.get("quantity", 1)
		var fill := _get_item_fill_from_json(item_id)
		total_fill += fill * qty  # Add to total (stream_data.total_fill may already have this)
		items_eaten += qty

	# Process added items from inventory
	for item in added_items:
		var qty: int = item.get("quantity", 1)
		items_eaten += qty

	# Apply food fill to stomach
	if total_fill > 0:
		var old_fullness := character.stomach_fullness
		character.eat(total_fill)
		var actual_fill := character.stomach_fullness - old_fullness

		# Streaming capacity training - reduced chance compared to binge (showing off, not pushing limits)
		var fullness_percent := float(character.stomach_fullness) / float(character.stomach_capacity) * 100.0
		var capacity_gained := 0
		if fullness_percent >= 75.0:
			# Half the chance of binge (12.5% to 25% instead of 25% to 50%)
			var capacity_chance := (0.25 + (fullness_percent - 75.0) / 100.0) * 0.5
			if randf() < capacity_chance:
				capacity_gained = randi_range(1, 2)  # Less gain than binge
				character.stomach_capacity += capacity_gained

		# Weight gain from eating on stream (distributes to body parts)
		var weight_gained := total_fill / 50
		if weight_gained > 0:
			character.add_weight(weight_gained)

	# Followers gained from stream quality
	var follower_gain := int(5 * quality_mult)
	var charm_bonus := character.charm / 100.0
	follower_gain = int(follower_gain * (1.0 + charm_bonus))
	character.followers += follower_gain

	# Improve mood from successful stream
	character.modify_mood(5)

	# Clear pending stream data
	character.pending_stream_data = {}

	# Build activity message
	var activity_msg := "%s completed %s, earned $%d (+%d followers)" % [
		character.display_name, kit_name, final_income, follower_gain
	]
	activity_logged.emit(activity_msg)
	print(activity_msg)


func _get_item_fill_from_json(item_id: String) -> int:
	## Look up fill value from vendi_items.json
	var file := FileAccess.open("res://data/vendi_items.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			for item in data.get("items", []):
				if item.get("id", "") == item_id:
					file.close()
					return item.get("fill", 0)
		file.close()
	return 0


func _complete_binge_task(character: CharacterData) -> void:
	## Binge - consume all food in queue, filling stomach and applying effects
	## Also trains stomach capacity when eating a lot
	## Costs $50 feeding fee
	var total_fill := 0
	var items_eaten := 0

	# Process all items in food queue
	for item in character.food_queue:
		var fill: int = item.get("fill", 0)
		var qty: int = item.get("quantity", 1)
		total_fill += fill * qty
		items_eaten += qty

	# Apply the fill to stomach
	var old_fullness := character.stomach_fullness
	character.eat(total_fill)
	var actual_fill := character.stomach_fullness - old_fullness

	# Clear the food queue
	character.food_queue.clear()

	# Charge feeding cost
	GameManager.spend_money(GameManager.FEEDING_COST)

	# Binging improves mood but drains some energy
	character.modify_mood(5 + items_eaten)
	_apply_energy_drain(character, 5)

	# Capacity training: eating past 75% fullness can increase stomach capacity
	var fullness_percent := float(character.stomach_fullness) / float(character.stomach_capacity) * 100.0
	var capacity_gained := 0
	if fullness_percent >= 75.0:
		# Higher fullness = better chance to gain capacity
		# 75% = 25% chance, 100% = 50% chance
		var capacity_chance := 0.25 + (fullness_percent - 75.0) / 100.0
		# Feeder archetype bonus: +25% capacity training chance
		var feeder_bonus: float = character.get_archetype_passive("capacity_training_bonus", 0.0)
		capacity_chance *= (1.0 + feeder_bonus)
		if randf() < capacity_chance:
			capacity_gained = randi_range(1, 3)
			character.stomach_capacity += capacity_gained

	# Weight gain from eating - gain 1 lb per 50 fill consumed (distributes to body parts)
	# Feeder archetype reduces weight gain by 10%
	var weight_reduction: float = character.get_archetype_passive("weight_gain_reduction", 0.0)
	var weight_gained := int(float(total_fill) / 50.0 * (1.0 - weight_reduction))
	if weight_gained > 0:
		character.add_weight(weight_gained)

	# Build activity message
	var activity_msg := "%s binged on %d items [-$%d] (filled %d)" % [character.display_name, items_eaten, GameManager.FEEDING_COST, actual_fill]
	if capacity_gained > 0:
		activity_msg += " [Stomach +%d!]" % capacity_gained
	if weight_gained > 0:
		activity_msg += " [+%d lbs]" % weight_gained

	activity_logged.emit(activity_msg)
	print(activity_msg)


func _complete_milking_task(character: CharacterData) -> void:
	## Milking station - collect milk for income, relieve discomfort
	const BASE_MILK_VALUE := 2  # $2 per unit of milk (before bonuses)

	if not character.is_lactating:
		# Not lactating, nothing to milk
		var activity_msg := "%s isn't lactating - no milk to collect" % character.display_name
		activity_logged.emit(activity_msg)
		print(activity_msg)
		return

	var milk_collected := character.milk_current
	if milk_collected <= 0:
		var activity_msg := "%s had no milk to collect" % character.display_name
		activity_logged.emit(activity_msg)
		print(activity_msg)
		return

	# Calculate income from milk
	var milk_value := float(milk_collected * BASE_MILK_VALUE)

	# Hucow archetype bonus: +15% milk value
	var value_bonus: float = character.get_archetype_passive("milk_value_bonus", 0.0)
	milk_value *= (1.0 + value_bonus)

	# CammTec takes their cut (40%)
	var after_cut := milk_value * (1.0 - GameManager.CAMMTEC_CUT_PERCENT)
	var final_income := int(after_cut / 5) * 5  # Round down to nearest $5

	# Apply effects
	GameManager.add_money(final_income)
	character.spend_milk(milk_collected)  # Clears the milk
	character.milk_full_ticks = 0  # Reset discomfort
	character.modify_mood(10)  # Relief from milking
	_apply_energy_drain(character, 5)  # Light energy cost

	var activity_msg := "%s was milked (%d units) and earned $%d" % [character.display_name, milk_collected, final_income]
	activity_logged.emit(activity_msg)
	print(activity_msg)


func _complete_dr_dan_task(character: CharacterData) -> void:
	## Dr. Dan's - apply all pending treatments when complete
	var treatments := character.pending_dr_dan_treatments
	var treatment_names: Array[String] = []

	for treatment in treatments:
		var item_type: String = treatment.get("type", "")
		var item_name: String = treatment.get("name", "???")
		var quantity: int = treatment.get("quantity", 1)
		treatment_names.append(item_name)

		match item_type:
			"augment":
				character.add_augment(treatment)
				_apply_dr_dan_augment(character, treatment)
			"infusion":
				_apply_dr_dan_infusion(character, treatment, quantity)
			"procedure":
				_apply_dr_dan_procedure(character, treatment, quantity)
			"contract":
				_apply_dr_dan_contract(character, treatment, quantity)
			"kink":
				_apply_dr_dan_kink(character, treatment)

	# Clear pending treatments
	character.pending_dr_dan_treatments.clear()

	var activity_msg := "%s finished treatment at Dr. Dan's (%s)" % [character.display_name, ", ".join(treatment_names)]
	activity_logged.emit(activity_msg)
	print(activity_msg)


func _apply_dr_dan_infusion(character: CharacterData, item_data: Dictionary, quantity: int) -> void:
	## Apply IV drip infusion effects
	var item_id: String = item_data.get("id", "")
	for _i in range(quantity):
		match item_id:
			"energy_drip":
				character.energy = clampi(character.energy + 40, 0, 100)
			"appetite_drip":
				character.stomach_capacity += 20
			"mood_infusion":
				character.mood = clampi(character.mood + 50, 0, 100)
			"recovery_drip":
				character.stomach_fullness = maxi(character.stomach_fullness - 50, 0)
				character.energy = clampi(character.energy + 30, 0, 100)
			"performance_infusion":
				character.charm = clampi(character.charm + 15, 0, 100)


func _apply_dr_dan_procedure(character: CharacterData, item_data: Dictionary, quantity: int) -> void:
	## Apply procedure effects
	var stat_changes: Dictionary = item_data.get("stat_changes", {})
	for stat_name in stat_changes:
		var change: int = stat_changes[stat_name] * quantity
		match stat_name:
			"stamina":
				character.stamina = clampi(character.stamina + change, 0, 100)
			"charm":
				character.charm = clampi(character.charm + change, 0, 100)
			"talent":
				character.talent = clampi(character.talent + change, 0, 100)
			"style":
				character.style = clampi(character.style + change, 0, 100)
			"stomach_capacity":
				character.stomach_capacity += change
			"weight":
				character.add_weight(change)


func _apply_dr_dan_contract(character: CharacterData, item_data: Dictionary, quantity: int) -> void:
	## Apply surrogacy contract effects - increase BB Factor
	var bb_gain: int = item_data.get("bb_factor_gain", 1)
	var total_gain := bb_gain * quantity
	character.bb_factor = mini(character.bb_factor + total_gain, character.womb_capacity)


func _apply_dr_dan_kink(character: CharacterData, item_data: Dictionary) -> void:
	## Unlock a kink for the character
	var kink_id: String = item_data.get("kink_id", "")
	if not kink_id.is_empty():
		character.add_kink(kink_id)


func _apply_dr_dan_augment(character: CharacterData, item_data: Dictionary) -> void:
	## Apply augment stat changes with archetype effect bonuses
	## Cybergoth: +50% effect on cybernetic augments
	## Breeder: +50% effect on genetic augments
	var stat_changes: Dictionary = item_data.get("stat_changes", {})
	if stat_changes.is_empty():
		return

	var effect_multiplier := 1.0
	var augment_category: String = item_data.get("augment_category", "")
	var effect_bonus := 0.0

	if augment_category == "cybernetic":
		effect_bonus = character.get_archetype_passive("cybernetic_augment_effect_bonus", 0.0)
	elif augment_category == "genetic":
		effect_bonus = character.get_archetype_passive("genetic_augment_effect_bonus", 0.0)

	effect_multiplier = 1.0 + effect_bonus

	for stat_name in stat_changes:
		var base_change: int = stat_changes[stat_name]
		var change := int(float(base_change) * effect_multiplier)
		match stat_name:
			"stamina":
				character.stamina = clampi(character.stamina + change, 0, 100)
			"charm":
				character.charm = clampi(character.charm + change, 0, 100)
			"talent":
				character.talent = clampi(character.talent + change, 0, 100)
			"style":
				character.style = clampi(character.style + change, 0, 100)
			"stomach_capacity":
				character.stomach_capacity += change
			"weight":
				character.add_weight(change)


func _get_station_base_income(station_name: String) -> int:
	## Returns base income for completing a task at a station
	match station_name:
		"Cam Studio":
			return 50  # $50 for 5 hours of streaming
		"Doctor's Office":
			return 0  # Medical visit doesn't generate income
		_:
			return 10


func _apply_energy_drain(character: CharacterData, base_drain: int) -> void:
	## Apply energy drain with Cybergoth archetype reduction
	var drain_reduction: float = character.get_archetype_passive("energy_drain_reduction", 0.0)
	var actual_drain := int(float(base_drain) * (1.0 - drain_reduction))
	character.modify_energy(-actual_drain)


func _get_player_character() -> CharacterData:
	## Get the player character from the character list
	for character in GameManager.characters:
		if character.is_player:
			return character
	return null


func _get_licensee_effectiveness_bonus() -> float:
	## Get NPC effectiveness bonus if player is a Licensee
	var player := _get_player_character()
	if player:
		return player.get_archetype_passive("npc_effectiveness_bonus", 0.0)
	return 0.0
