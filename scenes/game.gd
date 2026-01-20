extends Node
## Game coordinator - manages flow between menus and gameplay

const SAVE_PATH_TEMPLATE := "user://save_slot_%s.dat"
const SLOT_NAMES := ["A", "B", "C"]

var _current_slot: int = -1  # Active save slot for auto-save

@onready var main_menu: MainMenu = $MainMenu
@onready var archetype_selection: ArchetypeSelection = $ArchetypeSelection
@onready var gameplay: Node = $Gameplay


func _ready() -> void:
	# Connect signals
	main_menu.start_new_game.connect(_on_start_new_game)
	main_menu.continue_game.connect(_on_continue_game)
	archetype_selection.archetype_selected.connect(_on_archetype_selected)
	archetype_selection.cancelled.connect(_on_archetype_cancelled)

	# Connect main screen signals
	var main_screen: MainScreen = gameplay.get_node_or_null("MainScreen")
	if main_screen:
		main_screen.return_to_main_menu_requested.connect(_on_return_to_main_menu_from_gameplay)

	# Connect day change for auto-save
	GameManager.day_changed.connect(_on_day_changed)

	# Connect game over signal
	GameManager.game_over_debt.connect(_on_game_over_debt)

	# Start at main menu
	_show_main_menu()


func _show_main_menu() -> void:
	main_menu.show()
	archetype_selection.hide()
	gameplay.hide()
	TimeManager.stop_time()
	GameManager.is_paused = true


func _show_archetype_selection() -> void:
	main_menu.hide()
	archetype_selection.show()
	gameplay.hide()


func _show_gameplay() -> void:
	main_menu.hide()
	archetype_selection.hide()
	gameplay.show()

	# Refresh the main screen
	var main_screen: MainScreen = gameplay.get_node_or_null("MainScreen")
	if main_screen:
		main_screen.refresh_characters()

	GameManager.is_paused = false
	TimeManager.start_time()


func _on_start_new_game(_slot: int, _archetype_id: String) -> void:
	# Slot -1 means "go to archetype selection"
	_show_archetype_selection()


func _on_continue_game(slot: int) -> void:
	_current_slot = slot
	_load_game(slot)
	_show_gameplay()


func _on_archetype_selected(slot: int, archetype_id: String, player_name: String) -> void:
	_current_slot = slot
	_start_new_game(slot, archetype_id, player_name)
	_show_gameplay()


func _on_archetype_cancelled() -> void:
	_show_main_menu()


func _on_day_changed(_new_day: int) -> void:
	# Auto-save at the start of each new day
	if _current_slot >= 0:
		_save_game(_current_slot)
		print("Auto-saved to slot %s (Day %d)" % [SLOT_NAMES[_current_slot], _new_day])


func _start_new_game(slot: int, archetype_id: String, player_name: String) -> void:
	# Clear existing game state
	GameManager.characters.clear()
	GameManager.money = 0
	GameManager.current_day = 1
	GameManager.reset_quota_state()  # Reset quota/debt system
	TimeManager.current_hour = 8
	TimeManager.current_minute = 0

	# Load archetype data
	var archetype_data := _get_archetype_data(archetype_id)
	var starting_money: int = archetype_data.get("starting_money", 750)
	var starting_npcs: int = archetype_data.get("starting_npcs", 0)

	GameManager.money = starting_money

	# Create player character
	var player := CharacterData.new()
	player.id = "player"
	player.display_name = player_name
	player.is_player = true
	player.archetype_id = archetype_id
	player.apply_archetype_creation_bonuses()

	# Set low starting stats (incentivizes hiring talent)
	player.charm = 15
	player.talent = 10
	player.stamina = 20
	player.style = 12
	player.daily_salary = 0
	player.mood = 50
	player.energy = 80
	player.followers = 50

	# Generate license number for Licensee archetype
	if archetype_id == "licensee":
		player.license_number = randi_range(1000, 9999)

	GameManager.add_character(player)

	# Add starting NPCs if applicable (Licensee gets 1)
	if starting_npcs > 0:
		_add_starting_npc()

	# Save initial game state
	_save_game(slot)


func _add_starting_npc() -> void:
	# Create a basic starting NPC
	var npc := CharacterData.new()
	npc.id = "starter_npc"
	npc.display_name = "Rookie"
	npc.is_player = false
	npc.archetype_id = "feeder"  # Default archetype for starter NPC
	npc.apply_archetype_creation_bonuses()

	# Modest stats
	npc.charm = 35
	npc.talent = 30
	npc.stamina = 40
	npc.style = 30
	npc.daily_salary = 30
	npc.mood = 60
	npc.energy = 100
	npc.followers = 500

	GameManager.add_character(npc)


func _get_archetype_data(archetype_id: String) -> Dictionary:
	var file := FileAccess.open("res://data/archetypes.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			var archetypes: Array = data.get("archetypes", [])
			for arch in archetypes:
				if arch is Dictionary and arch.get("id", "") == archetype_id:
					return arch
	return {}


func _save_game(slot: int) -> void:
	var slot_name: String = SLOT_NAMES[slot]
	var save_path := SAVE_PATH_TEMPLATE % slot_name

	var save_data := {
		"version": 1,
		"money": GameManager.money,
		"current_day": GameManager.current_day,
		"timestamp": _get_timestamp(),
		"current_hour": TimeManager.current_hour,
		"current_minute": TimeManager.current_minute,
		"characters": []
	}

	for character in GameManager.characters:
		if character.has_method("to_dict"):
			save_data["characters"].append(character.to_dict())

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()


func _load_game(slot: int) -> void:
	var slot_name: String = SLOT_NAMES[slot]
	var save_path := SAVE_PATH_TEMPLATE % slot_name

	if not FileAccess.file_exists(save_path):
		return

	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return

	var save_data: Variant = file.get_var()
	file.close()

	if not save_data is Dictionary:
		return

	# Load basic state
	GameManager.money = save_data.get("money", 1000)
	GameManager.current_day = save_data.get("current_day", 1)
	TimeManager.current_hour = save_data.get("current_hour", 8)
	TimeManager.current_minute = save_data.get("current_minute", 0)

	# Load characters
	GameManager.characters.clear()
	var char_data_array: Array = save_data.get("characters", [])
	for char_dict in char_data_array:
		if char_dict is Dictionary:
			var character := CharacterData.new()
			character.from_dict(char_dict)
			GameManager.characters.append(character)


func _get_timestamp() -> String:
	var datetime := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [
		datetime["year"],
		datetime["month"],
		datetime["day"],
		datetime["hour"],
		datetime["minute"]
	]


## Called from gameplay to return to main menu
func return_to_main_menu() -> void:
	# Save before returning
	if _current_slot >= 0:
		_save_game(_current_slot)

	_current_slot = -1

	# Reset menu state before showing
	main_menu._mode = MainMenu.MenuMode.MAIN
	main_menu._selected_index = 0
	main_menu._refresh_slot_data()
	main_menu._build_main_options()

	_show_main_menu()
	main_menu._update_display()


func _on_return_to_main_menu_from_gameplay() -> void:
	return_to_main_menu()


func _on_game_over_debt() -> void:
	# Failed to pay grace period - game over
	TimeManager.stop_time()
	GameManager.is_paused = true

	# Delete the save file since game is over
	if _current_slot >= 0:
		var slot_name: String = SLOT_NAMES[_current_slot]
		var save_path := SAVE_PATH_TEMPLATE % slot_name
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
		print("Game Over - Save file deleted for slot %s" % slot_name)

	_current_slot = -1

	# For now, just return to main menu
	# TODO: Show game over screen with relocation paperwork
	return_to_main_menu()
