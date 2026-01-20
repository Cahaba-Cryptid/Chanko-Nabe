extends Node
## Main game manager singleton - handles global game state

signal money_changed(new_amount: int)
signal day_changed(new_day: int)
signal game_paused(is_paused: bool)
signal weekly_earnings_changed(new_amount: int)
signal quota_status_changed()
signal grace_period_started(shortfall: int, late_fee: int)
signal grace_period_ended(success: bool)
signal game_over_debt()
signal applicant_pool_changed()
signal ad_status_changed()

# Economy constants
const CAMMTEC_CUT_PERCENT := 0.40  # CammTec takes 40% of all streaming income
const FEEDING_COST := 50  # $50 per feeding session (binge)

# Quota/Debt constants
const STARTING_DEBT := 25000
const STARTING_QUOTA := 10000
const QUOTA_ESCALATION := 0.20  # 20% increase per week
const GRACE_PERIOD_DAYS := 3
const BASE_LATE_FEE := 500  # First offense late fee
const LATE_FEE_ESCALATION := 500  # Additional fee per repeat offense

var money: int = 1000:  # ¤1,000 starting funds ($1,000)
	set(value):
		money = max(0, value)
		money_changed.emit(money)

var current_day: int = 1:
	set(value):
		current_day = value
		day_changed.emit(current_day)

var is_paused: bool = false:
	set(value):
		is_paused = value
		game_paused.emit(is_paused)

# Quota/Debt state
var debt: int = STARTING_DEBT  # Total debt owed to CammTec
var current_week: int = 1  # Which week we're in
var current_quota: int = STARTING_QUOTA  # This week's quota target
var weekly_earnings: int = 0  # Earnings tracked this week (net, after CammTec cut)
var grace_period_active: bool = false
var grace_days_remaining: int = 0
var grace_shortfall: int = 0  # Amount owed during grace period
var grace_late_fee: int = 0  # Late fee for this grace period
var late_fee_count: int = 0  # How many times player has paid late fees (escalates fee)

var characters: Array[Resource] = []
var locations: Array[Resource] = []

# Recruitment system
var applicant_pool: Array[Dictionary] = []  # Pending applicants
var active_ads: Array[Dictionary] = []  # Currently running ads
var _recruitment_data: Dictionary = {}  # Cached recruitment.json data

# Station configuration (modifiable for upgrades)
var station_data := {
	"Cam Studio": { "slots": 2, "duration": 300.0 },      # 5 hours
	"Dr. Dan's": { "slots": 1, "duration": 120.0 },        # 2 hours
	"Contest": { "slots": 1, "duration": 180.0 },         # 3 hours (eating contest)
	"Socialize": { "slots": 3, "duration": 120.0 },       # 2 hours (follower capture)
	"Relax": { "slots": 2, "duration": 60.0 },            # Variable duration (fatigue recovery)
	"Binge": { "slots": 99, "duration": 60.0 },           # Hidden station - consume queued food
	"Milking": { "slots": 2, "duration": 60.0 },          # 1 hour - collect milk for income
}


func _ready() -> void:
	pass


func get_station_slots(station_name: String) -> int:
	if station_data.has(station_name):
		return station_data[station_name].get("slots", 1)
	return 1


func get_station_duration(station_name: String) -> float:
	if station_data.has(station_name):
		return station_data[station_name].get("duration", 60.0)
	return 60.0


func upgrade_station_slots(station_name: String, additional_slots: int = 1) -> void:
	if station_data.has(station_name):
		station_data[station_name]["slots"] += additional_slots


func add_money(amount: int) -> void:
	money += amount
	# Track earnings for quota (this is the net amount player receives)
	if amount > 0:
		add_weekly_earnings(amount)


func spend_money(amount: int) -> bool:
	if money >= amount:
		money -= amount
		return true
	return false


func can_afford(amount: int) -> bool:
	return money >= amount


# =============================================================================
# QUOTA / DEBT SYSTEM
# =============================================================================

func add_weekly_earnings(amount: int) -> void:
	## Add to this week's earnings tracker
	weekly_earnings += amount
	weekly_earnings_changed.emit(weekly_earnings)
	quota_status_changed.emit()

	# Check if grace period obligation is now met
	if grace_period_active:
		var total_owed := grace_shortfall + grace_late_fee
		if weekly_earnings >= total_owed:
			_complete_grace_period(true)


func get_quota_progress_percent() -> float:
	## Returns 0.0 to 1.0+ representing progress toward quota
	if current_quota <= 0:
		return 1.0
	return float(weekly_earnings) / float(current_quota)


func get_days_until_week_end() -> int:
	## Returns days remaining in current week (1-7 scale, 0 = week ends today)
	var day_of_week := (current_day - 1) % 7  # 0-6
	return 6 - day_of_week


func is_week_end() -> bool:
	## Returns true if today is the last day of the week
	return get_days_until_week_end() == 0


func get_grace_total_owed() -> int:
	## Returns total amount owed during grace period
	return grace_shortfall + grace_late_fee


func process_end_of_week() -> void:
	## Called at end of day 7, 14, 21, etc. - check quota
	if grace_period_active:
		# Don't start new week while in grace
		return

	if weekly_earnings >= current_quota:
		_quota_met()
	else:
		_quota_missed()


func _quota_met() -> void:
	## Player made quota - apply payment to debt, advance to next week
	var payment := mini(current_quota, debt)
	debt -= payment

	print("Quota met! $%d applied to debt. Remaining debt: $%d" % [payment, debt])

	# Reset for next week
	weekly_earnings = 0
	current_week += 1
	current_quota = int(float(STARTING_QUOTA) * pow(1.0 + QUOTA_ESCALATION, current_week - 1))

	quota_status_changed.emit()
	weekly_earnings_changed.emit(weekly_earnings)


func _quota_missed() -> void:
	## Player missed quota - enter grace period
	grace_period_active = true
	grace_days_remaining = GRACE_PERIOD_DAYS
	grace_shortfall = current_quota - weekly_earnings
	grace_late_fee = BASE_LATE_FEE + (late_fee_count * LATE_FEE_ESCALATION)

	print("Quota missed! Shortfall: $%d, Late fee: $%d" % [grace_shortfall, grace_late_fee])
	print("You have %d days to pay $%d" % [grace_days_remaining, get_grace_total_owed()])

	grace_period_started.emit(grace_shortfall, grace_late_fee)
	quota_status_changed.emit()


func process_grace_day() -> void:
	## Called at end of each day during grace period
	if not grace_period_active:
		return

	grace_days_remaining -= 1
	quota_status_changed.emit()

	# Check if they've earned enough
	var total_owed := get_grace_total_owed()
	if weekly_earnings >= total_owed:
		_complete_grace_period(true)
	elif grace_days_remaining <= 0:
		_complete_grace_period(false)


func _complete_grace_period(success: bool) -> void:
	## End grace period - either paid off or game over
	grace_period_active = false

	if success:
		# Paid off the grace period obligation
		var total_owed := grace_shortfall + grace_late_fee
		weekly_earnings -= total_owed  # Deduct what was owed
		debt -= grace_shortfall  # Apply shortfall to debt (late fee is just penalty)
		late_fee_count += 1  # Escalate future late fees

		print("Grace period survived! Late fees paid. Debt remaining: $%d" % debt)

		# Advance to next week
		current_week += 1
		current_quota = int(float(STARTING_QUOTA) * pow(1.0 + QUOTA_ESCALATION, current_week - 1))
		weekly_earnings = maxi(0, weekly_earnings)  # Keep any excess

		grace_period_ended.emit(true)
		quota_status_changed.emit()
		weekly_earnings_changed.emit(weekly_earnings)
	else:
		# Failed to pay - game over
		print("Grace period failed. Off to the mines...")
		grace_period_ended.emit(false)
		game_over_debt.emit()


func reset_quota_state() -> void:
	## Reset quota/debt for new game
	debt = STARTING_DEBT
	current_week = 1
	current_quota = STARTING_QUOTA
	weekly_earnings = 0
	grace_period_active = false
	grace_days_remaining = 0
	grace_shortfall = 0
	grace_late_fee = 0
	late_fee_count = 0
	quota_status_changed.emit()


func advance_day() -> void:
	current_day += 1
	_process_daily_events()


func _process_daily_events() -> void:
	# Process end-of-day calculations
	for character in characters:
		if character.has_method("process_daily"):
			character.process_daily()

	# Process recruitment (ad expiry, applicant decay)
	process_recruitment_daily()


func add_character(character: Resource) -> void:
	if character not in characters:
		characters.append(character)


func remove_character(character: Resource) -> void:
	characters.erase(character)


func get_character_count() -> int:
	return characters.size()


func save_game(slot: int = 0) -> bool:
	var save_data := {
		"version": 3,
		"money": money,
		"current_day": current_day,
		"time": {
			"hour": TimeManager.current_hour,
			"minute": TimeManager.current_minute
		},
		"quota": {
			"debt": debt,
			"current_week": current_week,
			"current_quota": current_quota,
			"weekly_earnings": weekly_earnings,
			"grace_period_active": grace_period_active,
			"grace_days_remaining": grace_days_remaining,
			"grace_shortfall": grace_shortfall,
			"grace_late_fee": grace_late_fee,
			"late_fee_count": late_fee_count
		},
		"recruitment": {
			"applicant_pool": applicant_pool,
			"active_ads": active_ads
		},
		"station_data": station_data,
		"characters": []
	}

	for character in characters:
		if character.has_method("to_dict"):
			save_data["characters"].append(character.to_dict())

	var save_path := "user://save_%d.json" % slot
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string := JSON.stringify(save_data, "\t")
		file.store_string(json_string)
		file.close()
		print("Game saved to slot %d" % slot)
		return true

	print("Failed to save game to slot %d" % slot)
	return false


func load_game(slot: int = 0) -> bool:
	var save_path := "user://save_%d.json" % slot
	if not FileAccess.file_exists(save_path):
		print("No save file found in slot %d" % slot)
		return false

	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		print("Failed to open save file in slot %d" % slot)
		return false

	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		print("Failed to parse save file: %s" % json.get_error_message())
		return false

	var save_data: Dictionary = json.data

	# Load basic state
	money = save_data.get("money", 1000)
	current_day = save_data.get("current_day", 1)

	# Load time
	var time_data: Dictionary = save_data.get("time", {})
	TimeManager.current_hour = time_data.get("hour", 8)
	TimeManager.current_minute = time_data.get("minute", 0)

	# Load quota/debt state (with defaults for old saves)
	var quota_data: Dictionary = save_data.get("quota", {})
	debt = quota_data.get("debt", STARTING_DEBT)
	current_week = quota_data.get("current_week", 1)
	current_quota = quota_data.get("current_quota", STARTING_QUOTA)
	weekly_earnings = quota_data.get("weekly_earnings", 0)
	grace_period_active = quota_data.get("grace_period_active", false)
	grace_days_remaining = quota_data.get("grace_days_remaining", 0)
	grace_shortfall = quota_data.get("grace_shortfall", 0)
	grace_late_fee = quota_data.get("grace_late_fee", 0)
	late_fee_count = quota_data.get("late_fee_count", 0)

	# Load station upgrades
	var saved_stations: Dictionary = save_data.get("station_data", {})
	for station_name in saved_stations:
		if station_data.has(station_name):
			station_data[station_name] = saved_stations[station_name]

	# Load recruitment state
	var recruitment_data: Dictionary = save_data.get("recruitment", {})
	applicant_pool = []
	for app in recruitment_data.get("applicant_pool", []):
		applicant_pool.append(app)
	active_ads = []
	for ad in recruitment_data.get("active_ads", []):
		active_ads.append(ad)
	applicant_pool_changed.emit()
	ad_status_changed.emit()

	# Load characters
	var char_data_array: Array = save_data.get("characters", [])
	characters.clear()
	for char_dict in char_data_array:
		var character := CharacterData.new()
		character.from_dict(char_dict)
		characters.append(character)

	print("Game loaded from slot %d" % slot)
	return true


func has_save(slot: int = 0) -> bool:
	var save_path := "user://save_%d.json" % slot
	return FileAccess.file_exists(save_path)


func delete_save(slot: int = 0) -> bool:
	var save_path := "user://save_%d.json" % slot
	if FileAccess.file_exists(save_path):
		var err := DirAccess.remove_absolute(save_path)
		return err == OK
	return false


# =============================================================================
# RECRUITMENT SYSTEM
# =============================================================================

func _load_recruitment_data() -> Dictionary:
	## Load and cache recruitment.json data
	if not _recruitment_data.is_empty():
		return _recruitment_data

	var file := FileAccess.open("res://data/recruitment.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_recruitment_data = json.data
		file.close()
	return _recruitment_data


func get_ad_tiers() -> Array:
	## Returns array of ad tier data
	var data := _load_recruitment_data()
	return data.get("ad_tiers", [])


func get_ad_tier(tier_id: String) -> Dictionary:
	## Returns a specific ad tier by ID
	for tier in get_ad_tiers():
		if tier.get("id", "") == tier_id:
			return tier
	return {}


func place_recruitment_ad(tier_id: String) -> bool:
	## Place an ad to attract applicants. Returns true if successful.
	var tier := get_ad_tier(tier_id)
	if tier.is_empty():
		return false

	var cost: int = tier.get("cost", 0)
	if not can_afford(cost):
		return false

	spend_money(cost)

	# Create active ad
	var ad := {
		"tier_id": tier_id,
		"days_remaining": tier.get("duration_days", 1),
		"placed_day": current_day
	}
	active_ads.append(ad)

	# Generate applicants immediately for this ad
	_generate_applicants_for_ad(tier)

	ad_status_changed.emit()
	print("Placed %s ad for $%d" % [tier.get("name", tier_id), cost])
	return true


func _generate_applicants_for_ad(tier: Dictionary) -> void:
	## Generate applicants based on ad tier
	var data := _load_recruitment_data()
	var max_pool: int = data.get("max_applicant_pool", 10)

	# Check pool limit
	if applicant_pool.size() >= max_pool:
		print("Applicant pool full - new applicants rejected")
		return

	var count_range: Array = tier.get("applicant_count", [1, 2])
	var applicant_count := randi_range(count_range[0], count_range[1])

	for _i in range(applicant_count):
		if applicant_pool.size() >= max_pool:
			break

		var applicant := _generate_applicant(tier)
		applicant_pool.append(applicant)

	applicant_pool_changed.emit()
	print("Generated %d new applicants" % applicant_count)


func _generate_applicant(tier: Dictionary) -> Dictionary:
	## Generate a single applicant based on tier settings
	var data := _load_recruitment_data()
	var name_pools: Dictionary = data.get("name_pools", {})
	var first_names: Array = name_pools.get("first_names", ["Talent"])
	var last_names: Array = name_pools.get("last_names", ["Unknown"])

	var stat_range: Array = tier.get("stat_range", [30, 50])
	var salary_range: Array = tier.get("salary_range", [40, 80])
	var archetype_weights: Dictionary = tier.get("archetype_weights", {"feeder": 1.0})

	# Generate name
	var first_name: String = first_names[randi() % first_names.size()]
	var last_name: String = last_names[randi() % last_names.size()]
	var display_name := "%s %s" % [first_name, last_name]

	# Pick archetype based on weights
	var archetype_id := _pick_weighted_archetype(archetype_weights)

	# Generate stats within range
	var stat_min: int = stat_range[0]
	var stat_max: int = stat_range[1]
	var charm := randi_range(stat_min, stat_max)
	var talent := randi_range(stat_min, stat_max)
	var stamina := randi_range(stat_min, stat_max)
	var style := randi_range(stat_min, stat_max)

	# Adjust stats based on archetype weights
	var arch_data := CharacterData._get_archetype_data(archetype_id)
	var stat_weights: Dictionary = arch_data.get("stat_weights", {})
	if stat_weights.has("charm"):
		charm = int(charm * (1.0 + stat_weights["charm"] * 0.3))
	if stat_weights.has("talent"):
		talent = int(talent * (1.0 + stat_weights["talent"] * 0.3))
	if stat_weights.has("stamina"):
		stamina = int(stamina * (1.0 + stat_weights["stamina"] * 0.3))
	if stat_weights.has("style"):
		style = int(style * (1.0 + stat_weights["style"] * 0.3))

	# Clamp stats
	charm = clampi(charm, 1, 100)
	talent = clampi(talent, 1, 100)
	stamina = clampi(stamina, 1, 100)
	style = clampi(style, 1, 100)

	# Generate salary demand
	var base_salary := randi_range(salary_range[0], salary_range[1])
	var stat_avg := (charm + talent + stamina + style) / 4.0
	var salary_modifier := stat_avg / 50.0  # Higher stats = higher salary demand
	var daily_salary := int(base_salary * salary_modifier)

	# Generate starting followers (lower tier = fewer followers)
	var stat_max_value: int = stat_range[1]
	var followers: int = randi_range(50, 200) * (stat_max_value / 40)

	# Signing bonus range
	var bonus_range: Array = data.get("signing_bonus_range", [50, 200])
	var signing_bonus := randi_range(bonus_range[0], bonus_range[1])

	return {
		"id": "applicant_%d_%d" % [current_day, randi()],
		"display_name": display_name,
		"archetype_id": archetype_id,
		"charm": charm,
		"talent": talent,
		"stamina": stamina,
		"style": style,
		"daily_salary": daily_salary,
		"signing_bonus": signing_bonus,
		"followers": followers,
		"applied_day": current_day,
		"tier_id": tier.get("id", "unknown")
	}


func _pick_weighted_archetype(weights: Dictionary) -> String:
	## Pick an archetype based on weighted probabilities
	var total := 0.0
	for w in weights.values():
		total += w

	var roll := randf() * total
	var cumulative := 0.0

	for archetype_id in weights:
		cumulative += weights[archetype_id]
		if roll <= cumulative:
			return archetype_id

	# Fallback
	return weights.keys()[0] if not weights.is_empty() else "feeder"


func hire_applicant(applicant: Dictionary) -> CharacterData:
	## Hire an applicant, converting them to a full CharacterData
	var signing_bonus: int = applicant.get("signing_bonus", 0)
	if not can_afford(signing_bonus):
		return null

	spend_money(signing_bonus)

	# Create character from applicant data
	var character := CharacterData.new()
	character.id = "npc_%d_%d" % [current_day, randi()]
	character.display_name = applicant.get("display_name", "New Hire")
	character.is_player = false
	character.archetype_id = applicant.get("archetype_id", "feeder")

	# Set stats
	character.charm = applicant.get("charm", 30)
	character.talent = applicant.get("talent", 30)
	character.stamina = applicant.get("stamina", 30)
	character.style = applicant.get("style", 30)
	character.daily_salary = applicant.get("daily_salary", 50)
	character.followers = applicant.get("followers", 100)

	# Apply archetype bonuses
	character.apply_archetype_creation_bonuses()

	# Set initial state
	character.mood = 70
	character.energy = 100
	character.fatigue = 0

	# Add to roster
	add_character(character)

	# Remove from applicant pool
	applicant_pool.erase(applicant)
	applicant_pool_changed.emit()

	print("Hired %s (Salary: $%d/day, Signing bonus: $%d)" % [
		character.display_name, character.daily_salary, signing_bonus
	])

	return character


func reject_applicant(applicant: Dictionary) -> void:
	## Remove an applicant from the pool
	applicant_pool.erase(applicant)
	applicant_pool_changed.emit()


func process_recruitment_daily() -> void:
	## Called at end of day - decay ads and applicants
	var data := _load_recruitment_data()
	var decay_days: int = data.get("applicant_decay_days", 5)

	# Process active ads
	var expired_ads: Array[Dictionary] = []
	for ad in active_ads:
		ad["days_remaining"] -= 1
		if ad["days_remaining"] <= 0:
			expired_ads.append(ad)

	for ad in expired_ads:
		active_ads.erase(ad)
		print("Ad expired: %s" % ad.get("tier_id", "unknown"))

	if not expired_ads.is_empty():
		ad_status_changed.emit()

	# Decay old applicants
	var expired_applicants: Array[Dictionary] = []
	for applicant in applicant_pool:
		var days_waiting: int = current_day - applicant.get("applied_day", current_day)
		if days_waiting >= decay_days:
			expired_applicants.append(applicant)

	for applicant in expired_applicants:
		applicant_pool.erase(applicant)
		print("Applicant left: %s" % applicant.get("display_name", "Unknown"))

	if not expired_applicants.is_empty():
		applicant_pool_changed.emit()


func get_applicant_days_remaining(applicant: Dictionary) -> int:
	## Returns how many days before applicant leaves
	var data := _load_recruitment_data()
	var decay_days: int = data.get("applicant_decay_days", 5)
	var days_waiting: int = current_day - applicant.get("applied_day", current_day)
	return maxi(0, decay_days - days_waiting)


func clear_recruitment_state() -> void:
	## Reset recruitment state for new game
	applicant_pool.clear()
	active_ads.clear()
	applicant_pool_changed.emit()
	ad_status_changed.emit()
