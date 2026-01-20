extends Resource
class_name TaskData
## Data container for task/activity information

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

@export_group("Duration")
@export var base_duration: float = 60.0  # In game time units
@export var min_duration: float = 30.0
@export var max_duration: float = 120.0

@export_group("Rewards")
@export var base_income: int = 100
@export var base_experience: int = 10
@export var stat_used: String = "charm"  # Which stat affects performance

@export_group("Costs")
@export var energy_cost: int = 20
@export var mood_impact: int = -5  # Can be positive for fun tasks

@export_group("Requirements")
@export var required_location_ids: Array[String] = []
@export var min_stat_requirement: int = 0
@export var required_traits: Array[String] = []

@export_group("Risks")
@export var risk_chance: float = 0.1  # Chance of negative event
@export var risk_mood_penalty: int = -20
@export var risk_energy_penalty: int = -30


func calculate_income(character: CharacterData, location: LocationData) -> int:
	var stat_value: int = character.get(stat_used)
	var effectiveness := character.get_effectiveness()
	var stat_bonus := stat_value / 100.0

	var income := base_income * (0.5 + stat_bonus) * effectiveness

	if location:
		income = location.get_effective_income(int(income))

	return int(income)


func calculate_experience(character: CharacterData, location: LocationData) -> int:
	var xp := base_experience

	if location:
		xp = location.get_effective_experience(xp)

	# Bonus XP if stat is low (more room to learn)
	var stat_value: int = character.get(stat_used)
	if stat_value < 50:
		xp = int(xp * 1.5)

	return xp


func can_perform(character: CharacterData) -> bool:
	if character.energy < energy_cost:
		return false

	var stat_value: int = character.get(stat_used)
	if stat_value < min_stat_requirement:
		return false

	for trait_name in required_traits:
		if not character.has_trait(trait_name):
			return false

	return true


func apply_results(character: CharacterData, location: LocationData) -> Dictionary:
	var results := {
		"income": 0,
		"experience": 0,
		"risk_occurred": false,
		"messages": []
	}

	# Check for risk event
	if randf() < risk_chance:
		results["risk_occurred"] = true
		character.modify_mood(risk_mood_penalty)
		character.modify_energy(risk_energy_penalty)
		results["messages"].append("Something went wrong during the task!")
	else:
		# Normal completion
		var income := calculate_income(character, location)
		var xp := calculate_experience(character, location)

		results["income"] = income
		results["experience"] = xp

		character.add_experience(xp)
		character.total_earnings += income
		character.modify_mood(mood_impact)
		character.modify_energy(-energy_cost)

		results["messages"].append("Task completed successfully!")

	return results


func get_estimated_income_range(character: CharacterData, location: LocationData) -> Vector2i:
	# Return min/max estimated income for UI display
	var base := calculate_income(character, location)
	var min_income := int(base * 0.7)
	var max_income := int(base * 1.3)
	return Vector2i(min_income, max_income)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"base_duration": base_duration,
		"base_income": base_income,
		"base_experience": base_experience
	}
