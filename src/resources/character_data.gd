extends Resource
class_name CharacterData
## Data container for character/talent information

@export var id: String = ""
@export var display_name: String = ""
@export var portrait: Texture2D
@export var is_player: bool = false  # True for the player character
@export var archetype_id: String = ""  # Archetype (feeder, breeder, egirl, cybergoth, hucow, licensee)
@export var license_number: int = 0  # Randomized per save for Licensee players (4 digits)

# Core stats (0-100 scale)
@export_group("Stats")
@export_range(0, 100) var charm: int = 50
@export_range(0, 100) var talent: int = 50
@export_range(0, 100) var stamina: int = 50
@export_range(0, 100) var style: int = 50

# Physical / Stomach
@export_group("Physical")
@export var weight: int = 100            # Current weight (affects shopping time, etc.)
@export var stomach_capacity: int = 100  # Max fullness
@export var stomach_fullness: int = 0    # Current fullness (0 = empty)
@export var womb_capacity: int = 1       # Max BB Factor (surrogacy limit)
@export var bb_factor: int = 0           # Current pregnancy level (0 = none, capped by womb_capacity)

# Milk production
@export var milk_capacity: int = 100     # Max milk storage
@export var milk_current: int = 0        # Current milk amount
@export var is_lactating: bool = false   # True if producing milk (Hucow archetype, pregnant, or lactation augment)
@export var milk_full_ticks: int = 0     # Ticks spent at 100% capacity (discomfort builds)

# Current state
@export_group("State")
@export_range(0, 100) var mood: int = 75
@export_range(0, 100) var energy: int = 100
@export_range(0, 100) var fatigue: int = 0  # Increases when mood is too low, maxed = can't work
@export var experience: int = 0
@export var level: int = 1

# Assignment
@export_group("Assignment")
@export var current_location_id: String = ""
@export var current_task_id: String = ""
@export var task_time_remaining: float = 0.0

# Traits that affect gameplay
@export_group("Traits")
@export var traits: Array[String] = []

# Inventory - stores purchased items
@export_group("Inventory")
@export var inventory: Array[Dictionary] = []

# Food queue - items queued for binging
@export_group("Food Queue")
@export var food_queue: Array[Dictionary] = []

# Augments - permanent cybernetic/genetic enhancements
@export_group("Augments")
@export var augments: Array[Dictionary] = []

# Pending Dr. Dan treatments - items being administered during station time
@export_group("Dr. Dan")
@export var pending_dr_dan_treatments: Array[Dictionary] = []

# Pending stream data - stream setup info for when streaming completes
@export_group("Stream")
@export var pending_stream_data: Dictionary = {}

# Salary and costs
@export_group("Economy")
@export var daily_salary: int = 50
@export var total_earnings: int = 0

# Followers - determines stream income, decays without activity
@export_group("Followers")
@export var followers: int = 100  # Base follower count
@export var last_stream_day: int = 0  # Day of last stream (for decay tracking)
@export var last_socialize_day: int = 0  # Day of last socialize (for decay tracking)

# Debuffs - temporary stat penalties
@export_group("Debuffs")
@export var burnout_charm_penalty: int = 0  # Charm reduction from burnout (clears over time)
@export var burnout_days_remaining: int = 0  # Days until burnout penalty clears


## Cached archetype data (loaded once per session)
static var _archetype_cache: Dictionary = {}


static func _get_archetype_data(arch_id: String) -> Dictionary:
	## Load and cache archetype data from JSON
	if _archetype_cache.is_empty():
		var file := FileAccess.open("res://data/archetypes.json", FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data: Dictionary = json.data
				for arch in data.get("archetypes", []):
					_archetype_cache[arch.get("id", "")] = arch
			file.close()
	return _archetype_cache.get(arch_id, {})


func get_effectiveness(licensee_bonus: float = 0.0) -> float:
	## Calculate overall effectiveness based on stats, mood, and archetype weights
	## licensee_bonus: Optional effectiveness bonus from Licensee player (for NPCs)
	var effective_charm := maxi(0, charm - burnout_charm_penalty)

	# Get archetype stat weights (default to equal weights if no archetype)
	var arch_data := _get_archetype_data(archetype_id)
	var weights: Dictionary = arch_data.get("stat_weights", {})
	var charm_weight: float = weights.get("charm", 0.25)
	var talent_weight: float = weights.get("talent", 0.25)
	var stamina_weight: float = weights.get("stamina", 0.25)
	var style_weight: float = weights.get("style", 0.25)

	# Weighted stat calculation
	var base_stat := (effective_charm * charm_weight + talent * talent_weight + stamina * stamina_weight + style * style_weight)
	var mood_modifier := mood / 100.0
	var energy_modifier := energy / 100.0
	var effectiveness := base_stat * mood_modifier * energy_modifier

	# Apply Licensee bonus for NPCs
	if not is_player and licensee_bonus > 0.0:
		effectiveness *= (1.0 + licensee_bonus)

	return effectiveness


func get_effective_charm() -> int:
	## Returns charm after applying any debuffs
	return maxi(0, charm - burnout_charm_penalty)


func get_archetype_data() -> Dictionary:
	## Returns this character's archetype data
	return _get_archetype_data(archetype_id)


func get_archetype_passive(passive_name: String, default_value: Variant = 0.0) -> Variant:
	## Get a specific passive bonus from archetype
	var arch_data := get_archetype_data()
	var passives: Dictionary = arch_data.get("passives", {})
	return passives.get(passive_name, default_value)


func apply_archetype_creation_bonuses() -> void:
	## Apply one-time bonuses when character is created with an archetype
	## Call this after setting archetype_id on a new character

	# Breeder: +1 womb capacity at creation
	var womb_bonus: int = get_archetype_passive("base_womb_capacity_bonus", 0)
	if womb_bonus > 0:
		womb_capacity += womb_bonus

	# Hucow: always lactating
	var always_lactating: bool = get_archetype_passive("always_lactating", false)
	if always_lactating:
		is_lactating = true


func can_perform() -> bool:
	## Returns true if this character can perform content (Licensees cannot)
	var arch_data := get_archetype_data()
	return arch_data.get("can_perform", true)


func update_lactation_status() -> void:
	## Update lactation based on archetype, pregnancy, or augments
	# Hucow archetype always lactates
	if archetype_id == "hucow":
		is_lactating = true
		return
	# Pregnant characters lactate
	if bb_factor > 0:
		is_lactating = true
		return
	# Check for lactation augment
	if has_augment("lactation_implant"):
		is_lactating = true
		return
	is_lactating = false


func add_milk(amount: int) -> int:
	## Add milk to storage, returns amount actually added (capped by capacity)
	var space := milk_capacity - milk_current
	var added := mini(amount, space)
	milk_current += added
	return added


func spend_milk(amount: int) -> bool:
	## Spend milk (for stream kit purchases). Returns true if successful.
	if milk_current >= amount:
		milk_current -= amount
		return true
	return false


func can_afford_milk(amount: int) -> bool:
	## Check if character has enough milk
	return milk_current >= amount


func drink_milk(amount: int) -> int:
	## Consume milk as food. Returns amount actually consumed.
	## Fills stomach and removes milk from storage.
	var available := mini(amount, milk_current)
	var stomach_space := get_stomach_space()
	var consumed := mini(available, stomach_space)
	if consumed > 0:
		milk_current -= consumed
		eat(consumed)  # Each unit of milk = 1 fill
	return consumed


func get_milk_fill_value() -> int:
	## Returns how much stomach fill drinking all current milk would provide
	return mini(milk_current, get_stomach_space())


func is_milk_full() -> bool:
	## Returns true if milk storage is at capacity
	return milk_current >= milk_capacity


func get_milk_percent() -> float:
	## Returns milk fullness as percentage (0-100)
	if milk_capacity <= 0:
		return 0.0
	return float(milk_current) / float(milk_capacity) * 100.0


func is_milk_warning() -> bool:
	## Returns true if milk is at 80%+ capacity (warning threshold)
	return get_milk_percent() >= 80.0


func get_milk_discomfort_level() -> int:
	## Returns discomfort severity (0=none, 1=mild, 2=severe)
	if milk_full_ticks <= 0:
		return 0
	elif milk_full_ticks < 10:
		return 1  # Mild: just mood penalty
	else:
		return 2  # Severe: mood + energy + effectiveness penalty


func emergency_milk() -> int:
	## Emergency self-milk - clears all milk but wastes it. Returns amount cleared.
	var cleared := milk_current
	milk_current = 0
	milk_full_ticks = 0
	return cleared


func apply_burnout_penalty(charm_penalty: int, days: int) -> void:
	## Apply burnout debuff from exhaustion recovery
	burnout_charm_penalty = charm_penalty
	burnout_days_remaining = days


func tick_burnout() -> void:
	## Called at end of day to reduce burnout duration
	if burnout_days_remaining > 0:
		burnout_days_remaining -= 1
		if burnout_days_remaining <= 0:
			burnout_charm_penalty = 0


func process_daily() -> void:
	# Called at end of each day
	_recover_energy()
	_adjust_mood()
	_check_level_up()


func _recover_energy() -> void:
	if current_task_id.is_empty():
		energy = min(100, energy + 30)
	else:
		energy = min(100, energy + 10)


func _adjust_mood() -> void:
	# Mood naturally trends toward 50 if nothing affects it
	if mood > 50:
		mood -= 1
	elif mood < 50:
		mood += 1


func _check_level_up() -> void:
	var xp_needed := level * 100
	if experience >= xp_needed:
		experience -= xp_needed
		level += 1
		_on_level_up()


func _on_level_up() -> void:
	# Stat gains on level up
	charm = min(100, charm + randi_range(0, 2))
	talent = min(100, talent + randi_range(0, 2))
	stamina = min(100, stamina + randi_range(0, 2))
	style = min(100, style + randi_range(0, 2))


func add_experience(amount: int) -> void:
	experience += amount


func modify_mood(amount: int) -> void:
	mood = clamp(mood + amount, 0, 100)


func modify_energy(amount: int) -> void:
	energy = clamp(energy + amount, 0, 100)


func assign_to_location(location_id: String, task_id: String, duration: float) -> void:
	current_location_id = location_id
	current_task_id = task_id
	task_time_remaining = duration


func clear_assignment() -> void:
	current_location_id = ""
	current_task_id = ""
	task_time_remaining = 0.0


func is_available() -> bool:
	## Returns true if character can be assigned to a station (no current task, no food queued, not exhausted)
	return current_task_id.is_empty() and food_queue.is_empty() and not is_exhausted()


func is_exhausted() -> bool:
	## Returns true if fatigue is maxed out - character cannot work or binge
	return fatigue >= 100


func modify_fatigue(amount: int) -> void:
	fatigue = clampi(fatigue + amount, 0, 100)


func is_busy() -> bool:
	## Returns true if character is currently doing a task
	return not current_task_id.is_empty()


func has_food_queued() -> bool:
	return not food_queue.is_empty()


func has_trait(trait_name: String) -> bool:
	return trait_name in traits


func get_stomach_space() -> int:
	return stomach_capacity - stomach_fullness


func get_portrait_tier() -> int:
	## Returns portrait tier (1-4) based on fullness percentage and bb_factor
	## Higher bb_factor increases the tier
	var fullness_percent := 0.0
	if stomach_capacity > 0:
		fullness_percent = float(stomach_fullness) / float(stomach_capacity) * 100.0

	var base_tier := 1
	if fullness_percent > 75:
		base_tier = 4
	elif fullness_percent > 50:
		base_tier = 3
	elif fullness_percent > 25:
		base_tier = 2

	# bb_factor adds to the tier (capped at 4)
	return mini(4, base_tier + bb_factor)


func get_mood_text() -> String:
	## Returns mood as descriptive text
	if mood >= 80:
		return "Ecstatic"
	elif mood >= 60:
		return "Happy"
	elif mood >= 40:
		return "Neutral"
	elif mood >= 20:
		return "Unhappy"
	else:
		return "Miserable"


func can_eat(fill_amount: int) -> bool:
	return get_stomach_space() >= fill_amount


func eat(fill_amount: int) -> void:
	stomach_fullness = min(stomach_capacity, stomach_fullness + fill_amount)


func add_to_inventory(item: Dictionary) -> void:
	## Add an item to inventory. Stacks by item id.
	var item_id: String = item.get("id", "")
	for inv_item in inventory:
		if inv_item.get("id", "") == item_id:
			inv_item["quantity"] = inv_item.get("quantity", 1) + 1
			return
	# New item - add with quantity 1
	var new_item := item.duplicate()
	new_item["quantity"] = 1
	inventory.append(new_item)


func get_inventory_count(item_id: String) -> int:
	## Get quantity of a specific item in inventory
	for inv_item in inventory:
		if inv_item.get("id", "") == item_id:
			return inv_item.get("quantity", 0)
	return 0


func get_total_inventory_items() -> int:
	## Get total number of items in inventory
	var total := 0
	for inv_item in inventory:
		total += inv_item.get("quantity", 1)
	return total


func add_to_food_queue(item: Dictionary) -> void:
	## Add an item from inventory to food queue. Removes from inventory.
	var item_id: String = item.get("id", "")

	# Find and remove from inventory
	for i in range(inventory.size()):
		if inventory[i].get("id", "") == item_id:
			var inv_item := inventory[i]
			var qty: int = inv_item.get("quantity", 1)
			if qty > 1:
				inv_item["quantity"] = qty - 1
			else:
				inventory.remove_at(i)
			break

	# Add to food queue (stacking)
	for queue_item in food_queue:
		if queue_item.get("id", "") == item_id:
			queue_item["quantity"] = queue_item.get("quantity", 1) + 1
			return

	# New item in queue
	var new_item := item.duplicate()
	new_item["quantity"] = 1
	food_queue.append(new_item)


func remove_from_food_queue(item_id: String) -> Dictionary:
	## Remove and return one item from food queue
	for i in range(food_queue.size()):
		if food_queue[i].get("id", "") == item_id:
			var queue_item := food_queue[i]
			var qty: int = queue_item.get("quantity", 1)
			if qty > 1:
				queue_item["quantity"] = qty - 1
			else:
				food_queue.remove_at(i)
			return queue_item.duplicate()
	return {}


func get_food_queue_count() -> int:
	## Get total items in food queue
	var total := 0
	for item in food_queue:
		total += item.get("quantity", 1)
	return total


func clear_food_queue_to_inventory() -> void:
	## Return all queued food back to inventory
	for item in food_queue:
		var qty: int = item.get("quantity", 1)
		for _i in range(qty):
			add_to_inventory(item)
	food_queue.clear()


func add_augment(augment_data: Dictionary) -> void:
	## Add a permanent augment. Augments are unique - can't have duplicates.
	var augment_id: String = augment_data.get("id", "")
	for existing in augments:
		if existing.get("id", "") == augment_id:
			return  # Already have this augment
	augments.append(augment_data.duplicate())


func has_augment(augment_id: String) -> bool:
	## Check if character has a specific augment
	for augment in augments:
		if augment.get("id", "") == augment_id:
			return true
	return false


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"is_player": is_player,
		"archetype_id": archetype_id,
		"license_number": license_number,
		"charm": charm,
		"talent": talent,
		"stamina": stamina,
		"style": style,
		"weight": weight,
		"stomach_capacity": stomach_capacity,
		"stomach_fullness": stomach_fullness,
		"womb_capacity": womb_capacity,
		"bb_factor": bb_factor,
		"milk_capacity": milk_capacity,
		"milk_current": milk_current,
		"is_lactating": is_lactating,
		"milk_full_ticks": milk_full_ticks,
		"mood": mood,
		"energy": energy,
		"fatigue": fatigue,
		"experience": experience,
		"level": level,
		"current_location_id": current_location_id,
		"current_task_id": current_task_id,
		"traits": traits,
		"daily_salary": daily_salary,
		"total_earnings": total_earnings,
		"followers": followers,
		"last_stream_day": last_stream_day,
		"last_socialize_day": last_socialize_day,
		"burnout_charm_penalty": burnout_charm_penalty,
		"burnout_days_remaining": burnout_days_remaining,
		"inventory": inventory,
		"food_queue": food_queue,
		"augments": augments,
		"pending_dr_dan_treatments": pending_dr_dan_treatments,
		"pending_stream_data": pending_stream_data
	}


func from_dict(data: Dictionary) -> void:
	id = data.get("id", "")
	display_name = data.get("display_name", "")
	is_player = data.get("is_player", false)
	archetype_id = data.get("archetype_id", "")
	license_number = data.get("license_number", 0)
	charm = data.get("charm", 50)
	talent = data.get("talent", 50)
	stamina = data.get("stamina", 50)
	style = data.get("style", 50)
	weight = data.get("weight", 100)
	stomach_capacity = data.get("stomach_capacity", 100)
	stomach_fullness = data.get("stomach_fullness", 0)
	womb_capacity = data.get("womb_capacity", 1)
	bb_factor = data.get("bb_factor", 0)
	milk_capacity = data.get("milk_capacity", 100)
	milk_current = data.get("milk_current", 0)
	is_lactating = data.get("is_lactating", false)
	milk_full_ticks = data.get("milk_full_ticks", 0)
	mood = data.get("mood", 75)
	energy = data.get("energy", 100)
	fatigue = data.get("fatigue", 0)
	experience = data.get("experience", 0)
	level = data.get("level", 1)
	current_location_id = data.get("current_location_id", "")
	current_task_id = data.get("current_task_id", "")
	traits = data.get("traits", [])
	daily_salary = data.get("daily_salary", 50)
	total_earnings = data.get("total_earnings", 0)
	followers = data.get("followers", 100)
	last_stream_day = data.get("last_stream_day", 0)
	last_socialize_day = data.get("last_socialize_day", 0)
	burnout_charm_penalty = data.get("burnout_charm_penalty", 0)
	burnout_days_remaining = data.get("burnout_days_remaining", 0)
	inventory = data.get("inventory", [])
	food_queue = data.get("food_queue", [])
	augments = data.get("augments", [])
	pending_dr_dan_treatments = data.get("pending_dr_dan_treatments", [])
	pending_stream_data = data.get("pending_stream_data", {})
