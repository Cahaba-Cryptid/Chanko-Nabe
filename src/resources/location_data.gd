extends Resource
class_name LocationData
## Data container for location information

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

@export_group("Availability")
@export var is_unlocked: bool = false
@export var unlock_cost: int = 0
@export var unlock_day_requirement: int = 1

@export_group("Capacity")
@export var max_characters: int = 1
@export var upgrade_level: int = 0
@export var max_upgrade_level: int = 5

@export_group("Tasks")
@export var available_task_ids: Array[String] = []

@export_group("Modifiers")
@export var income_multiplier: float = 1.0
@export var experience_multiplier: float = 1.0
@export var stat_requirements: Dictionary = {}  # e.g., {"charm": 30}


func can_unlock(current_money: int, current_day: int) -> bool:
	if is_unlocked:
		return false
	return current_money >= unlock_cost and current_day >= unlock_day_requirement


func unlock() -> void:
	is_unlocked = true


func can_upgrade() -> bool:
	return is_unlocked and upgrade_level < max_upgrade_level


func get_upgrade_cost() -> int:
	return unlock_cost * (upgrade_level + 1)


func upgrade() -> void:
	if can_upgrade():
		upgrade_level += 1
		max_characters += 1
		income_multiplier += 0.1
		experience_multiplier += 0.05


func character_meets_requirements(character: CharacterData) -> bool:
	for stat_name in stat_requirements:
		var required_value: int = stat_requirements[stat_name]
		var character_value: int = character.get(stat_name)
		if character_value < required_value:
			return false
	return true


func get_effective_income(base_income: int) -> int:
	return int(base_income * income_multiplier)


func get_effective_experience(base_xp: int) -> int:
	return int(base_xp * experience_multiplier)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"is_unlocked": is_unlocked,
		"upgrade_level": upgrade_level,
		"max_characters": max_characters,
		"income_multiplier": income_multiplier,
		"experience_multiplier": experience_multiplier
	}


func from_dict(data: Dictionary) -> void:
	is_unlocked = data.get("is_unlocked", false)
	upgrade_level = data.get("upgrade_level", 0)
	max_characters = data.get("max_characters", 1)
	income_multiplier = data.get("income_multiplier", 1.0)
	experience_multiplier = data.get("experience_multiplier", 1.0)
