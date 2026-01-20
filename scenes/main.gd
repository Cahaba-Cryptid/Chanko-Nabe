extends Node
## Main game scene

@onready var main_screen: MainScreen = $MainScreen


func _ready() -> void:
	_setup_initial_game_state()
	TimeManager.start_time()


func _setup_initial_game_state() -> void:
	# Add player character first (very low stats - incentivizes hiring talent)
	# TEST: Default to feeder archetype for testing, actual game will have selection screen
	var player := CharacterData.new()
	player.id = "player"
	player.display_name = "You"
	player.is_player = true
	player.archetype_id = "feeder"  # TEST: Default archetype
	player.apply_archetype_creation_bonuses()  # Apply archetype bonuses
	player.charm = 15
	player.talent = 10
	player.stamina = 20
	player.style = 12
	player.daily_salary = 0  # Player doesn't pay themselves
	player.mood = 50
	player.energy = 80
	player.followers = 50  # TEST: Player starts with few followers
	_add_starter_food(player)
	GameManager.add_character(player)

	# TEST: Add test characters (hired talent) - Remove before production
	var maisy := CharacterData.new()
	maisy.id = "maisy"
	maisy.display_name = "Maisy"
	maisy.archetype_id = "breeder"  # TEST: Breeder archetype
	maisy.apply_archetype_creation_bonuses()  # Apply archetype bonuses (+1 womb capacity)
	maisy.charm = 55
	maisy.talent = 45
	maisy.stamina = 60
	maisy.style = 50
	maisy.daily_salary = 40
	maisy.womb_capacity = 2  # TEST: At capacity for testing contract limits
	maisy.bb_factor = 2      # TEST: Pregnant with twins (at max capacity)
	maisy.followers = 2500   # TEST: Decent follower count
	maisy.update_lactation_status()  # Update lactation based on pregnancy
	_add_starter_food(maisy)
	GameManager.add_character(maisy)

	var jun := CharacterData.new()
	jun.id = "jun"
	jun.display_name = "Jun"
	jun.archetype_id = "hucow"  # TEST: Hucow archetype (always lactating)
	jun.apply_archetype_creation_bonuses()  # Apply archetype bonuses (always lactating)
	jun.charm = 70
	jun.talent = 35
	jun.stamina = 40
	jun.style = 65
	jun.daily_salary = 55
	jun.womb_capacity = 12 # TEST: High womb capacity for hyperpregnancy testing
	jun.bb_factor = 8      # TEST: Hyperpregnant with 8 babies
	jun.followers = 5000   # TEST: High follower count (charming)
	jun.update_lactation_status()  # Update lactation (Hucow always lactates)
	jun.milk_current = 60  # TEST: Start with some milk for testing milk streams
	_add_starter_food(jun)
	GameManager.add_character(jun)

	var riko := CharacterData.new()
	riko.id = "riko"
	riko.display_name = "Riko"
	riko.archetype_id = "egirl"  # TEST: E-Girl archetype
	riko.apply_archetype_creation_bonuses()  # Apply archetype bonuses
	riko.charm = 40
	riko.talent = 75
	riko.stamina = 50
	riko.style = 45
	riko.daily_salary = 50
	riko.followers = 1500   # TEST: Modest follower count
	_add_starter_food(riko)
	GameManager.add_character(riko)

	# TEST: Add a starting location - Replace with proper location loading
	var home_base := LocationData.new()
	home_base.id = "home_base"
	home_base.display_name = "Home Office"
	home_base.description = "Your starting headquarters"
	home_base.is_unlocked = true
	home_base.max_characters = 2
	GameManager.locations.append(home_base)

	# Notify main_screen to refresh after characters are added
	if main_screen:
		main_screen.refresh_characters()


# TEST: Remove before production - gives characters starter food for testing
func _add_starter_food(character: CharacterData) -> void:
	## Add dummy food items to character inventory for testing
	var foods := [
		{"id": "melon_bread", "name": "Melon Bread", "type": "food", "fill": 10, "price": 5},
		{"id": "onigiri", "name": "Onigiri", "type": "food", "fill": 15, "price": 8},
		{"id": "ramen", "name": "Instant Ramen", "type": "food", "fill": 25, "price": 12},
		{"id": "bento", "name": "Bento Box", "type": "food", "fill": 40, "price": 20},
		{"id": "cake", "name": "Strawberry Cake", "type": "food", "fill": 20, "price": 15},
	]

	# Give each character 8-16 random food items
	var num_items := randi_range(8, 16)
	for i in range(num_items):
		var food: Dictionary = foods[randi() % foods.size()].duplicate()
		character.add_to_inventory(food)


func _input(event: InputEvent) -> void:
	# Debug keys only
	if OS.is_debug_build():
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_F1:
					GameManager.add_money(10000)
				KEY_F2:
					# Add BB factor to all characters (cycles 0-4)
					for character in GameManager.characters:
						character.bb_factor = (character.bb_factor + 1) % 5
					print("BB Factor set to %d for all characters" % GameManager.characters[0].bb_factor)
				KEY_F3:
					TimeManager.time_scale *= 2
				KEY_F4:
					TimeManager.time_scale /= 2
