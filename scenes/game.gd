extends Node
## Game coordinator - manages flow between menus and gameplay

const SAVE_PATH := "user://save.dat"

const DraftPickDialogScene := preload("res://scenes/ui/draft_pick_dialog.tscn")

var _pending_draft_pick: bool = false  # Whether we need to show draft pick after gameplay starts
var _draft_pick_dialog: DraftPickDialog = null

@onready var main_menu: MainMenu = $MainMenu
@onready var archetype_selection: ArchetypeSelection = $ArchetypeSelection
@onready var gameplay: Node = $Gameplay


func _ready() -> void:
	# One-time cleanup of old save slot files (migrated to single save.dat)
	_cleanup_old_save_slots()

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


func _cleanup_old_save_slots() -> void:
	## Remove orphaned save files from old 3-slot system
	var old_slots := ["user://save_slot_A.dat", "user://save_slot_B.dat", "user://save_slot_C.dat"]
	for old_path in old_slots:
		if FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(old_path)
			print("Cleaned up old save: %s" % old_path)


func _show_main_menu() -> void:
	main_menu.show()
	archetype_selection.hide()
	gameplay.hide()
	TimeManager.stop_time()
	GameManager.clear_pause_stack()
	GameManager.is_paused = true  # Main menu is always paused


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

	GameManager.clear_pause_stack()  # Fresh start for gameplay
	TimeManager.start_time()


func _on_start_new_game() -> void:
	_show_archetype_selection()


func _on_continue_game() -> void:
	_load_game()
	_show_gameplay()


func _on_archetype_selected(archetype_id: String, player_name: String, starter_augment_id: String) -> void:
	_start_new_game(archetype_id, player_name, starter_augment_id)
	_show_gameplay()

	# Show draft pick if Licensee (after gameplay is visible)
	if _pending_draft_pick:
		_pending_draft_pick = false
		_show_draft_pick_dialog()


func _on_archetype_cancelled() -> void:
	_show_main_menu()


func _on_day_changed(new_day: int) -> void:
	# Auto-save at the start of each new day (but not during initial game setup)
	# Skip save if no characters exist yet (happens during _start_new_game initialization)
	if GameManager.characters.is_empty():
		return
	_save_game()
	print("Auto-saved (Day %d)" % new_day)


func _start_new_game(archetype_id: String, player_name: String, starter_augment_id: String = "") -> void:
	# Clear existing game state
	GameManager.characters.clear()
	GameManager.contest_rivals.clear()
	GameManager.money = 0
	GameManager.current_day = 1
	GameManager.reset_quota_state()  # Reset quota/debt system
	GameManager.clear_recruitment_state()  # Reset recruitment system
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
	# Only set default followers if archetype didn't override
	if player.followers == 100:  # Default value, archetype didn't change it
		player.followers = 50

	# Generate license number for Licensee archetype
	if archetype_id == "licensee":
		player.license_number = randi_range(1000, 9999)

	# Apply starter augment for Cybergoth
	if starter_augment_id != "":
		_apply_starter_augment(player, starter_augment_id)

	GameManager.add_character(player)
	print("Added player character: %s, total characters: %d" % [player.display_name, GameManager.characters.size()])

	# Add starting NPCs if applicable (Licensee gets 1)
	if starting_npcs > 0:
		if archetype_id == "licensee":
			# Licensee gets draft pick dialog instead of random NPC
			_pending_draft_pick = true
		else:
			_add_starting_npc()

	# Save initial game state (unless waiting for draft pick)
	if not _pending_draft_pick:
		_save_game()


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

	# NPCs get random food preferences for contests
	npc.randomize_food_preferences()

	GameManager.add_character(npc)


func _show_draft_pick_dialog() -> void:
	## Show the draft pick dialog for Licensee archetype
	if not _draft_pick_dialog:
		_draft_pick_dialog = DraftPickDialogScene.instantiate()
		gameplay.add_child(_draft_pick_dialog)
		_draft_pick_dialog.rookie_selected.connect(_on_draft_rookie_selected)
		_draft_pick_dialog.dialog_cancelled.connect(_on_draft_cancelled)

	_draft_pick_dialog.open_dialog()


func _on_draft_rookie_selected(selected: CharacterData, rejected: Array[CharacterData]) -> void:
	## Handle draft pick selection
	# Give the selected rookie a proper ID
	selected.id = "starter_npc"

	# Add selected rookie to the roster
	GameManager.add_character(selected)

	# Store rejected rookies as contest rivals
	GameManager.set_contest_rivals(rejected)

	# Refresh the main screen to show the new character
	var main_screen: MainScreen = gameplay.get_node_or_null("MainScreen")
	if main_screen:
		main_screen.refresh_characters()

	# Now save the initial game state
	_save_game()

	print("Draft complete: Selected %s, %d rivals stored" % [selected.display_name, rejected.size()])


func _on_draft_cancelled() -> void:
	## Handle draft cancellation - for now, just pick the first candidate
	# In the future, this could return to main menu or force a selection
	print("Draft cancelled - this shouldn't happen in normal gameplay")


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


func _apply_starter_augment(player: CharacterData, augment_id: String) -> void:
	## Apply a starter augment to the player (Cybergoth only)
	var file := FileAccess.open("res://data/dr_dan_items.json", FileAccess.READ)
	if not file:
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK or not json.data is Dictionary:
		return

	var items: Array = json.data.get("items", [])
	for item in items:
		if item is Dictionary and item.get("id", "") == augment_id:
			# Add the augment to player
			player.add_augment(item)

			# Apply stat changes
			var stat_changes: Dictionary = item.get("stat_changes", {})
			if stat_changes.has("stomach_capacity"):
				player.stomach_capacity += stat_changes["stomach_capacity"]
			if stat_changes.has("milk_capacity"):
				player.milk_capacity += stat_changes["milk_capacity"]
			if stat_changes.has("womb_capacity"):
				player.womb_capacity += stat_changes["womb_capacity"]

			print("Applied starter augment: %s" % item.get("name", augment_id))
			return


func _save_game() -> void:
	var save_data := {
		"version": 2,
		"money": GameManager.money,
		"current_day": GameManager.current_day,
		"timestamp": _get_timestamp(),
		"current_hour": TimeManager.current_hour,
		"current_minute": TimeManager.current_minute,
		"quota": {
			"debt": GameManager.debt,
			"current_week": GameManager.current_week,
			"current_quota": GameManager.current_quota,
			"weekly_earnings": GameManager.weekly_earnings,
			"grace_period_active": GameManager.grace_period_active,
			"grace_days_remaining": GameManager.grace_days_remaining,
			"grace_shortfall": GameManager.grace_shortfall,
			"grace_late_fee": GameManager.grace_late_fee,
			"late_fee_count": GameManager.late_fee_count
		},
		"recruitment": {
			"applicant_pool": GameManager.applicant_pool,
			"active_ads": GameManager.active_ads
		},
		"station_data": GameManager.station_data,
		"characters": [],
		"contest_rivals": []
	}

	for character in GameManager.characters:
		if character.has_method("to_dict"):
			save_data["characters"].append(character.to_dict())

	for rival in GameManager.contest_rivals:
		if rival.has_method("to_dict"):
			save_data["contest_rivals"].append(rival.to_dict())

	print("Saving %d characters, %d rivals" % [save_data["characters"].size(), save_data["contest_rivals"].size()])

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("Load failed: save file not found")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		print("Load failed: could not open save file")
		return

	var save_data: Variant = file.get_var()
	file.close()

	if not save_data is Dictionary:
		print("Load failed: save data is not a Dictionary")
		return

	# Check save version and migrate if needed
	var save_version: int = save_data.get("version", 1)
	if save_version < 2:
		save_data = _migrate_save_v1_to_v2(save_data)
		print("Migrated save from v1 to v2")

	# Load basic state
	GameManager.money = save_data.get("money", 1000)
	GameManager.current_day = save_data.get("current_day", 1)
	TimeManager.current_hour = save_data.get("current_hour", 8)
	TimeManager.current_minute = save_data.get("current_minute", 0)

	# Load quota/debt state
	var quota_data: Dictionary = save_data.get("quota", {})
	GameManager.debt = quota_data.get("debt", GameManager.STARTING_DEBT)
	GameManager.current_week = quota_data.get("current_week", 1)
	GameManager.current_quota = quota_data.get("current_quota", GameManager.STARTING_QUOTA)
	GameManager.weekly_earnings = quota_data.get("weekly_earnings", 0)
	GameManager.grace_period_active = quota_data.get("grace_period_active", false)
	GameManager.grace_days_remaining = quota_data.get("grace_days_remaining", 0)
	GameManager.grace_shortfall = quota_data.get("grace_shortfall", 0)
	GameManager.grace_late_fee = quota_data.get("grace_late_fee", 0)
	GameManager.late_fee_count = quota_data.get("late_fee_count", 0)

	# Load recruitment state
	var recruitment_data: Dictionary = save_data.get("recruitment", {})
	GameManager.applicant_pool.clear()
	for app in recruitment_data.get("applicant_pool", []):
		GameManager.applicant_pool.append(app)
	GameManager.active_ads.clear()
	for ad in recruitment_data.get("active_ads", []):
		GameManager.active_ads.append(ad)

	# Load station upgrades
	var saved_stations: Dictionary = save_data.get("station_data", {})
	for station_name in saved_stations:
		if GameManager.station_data.has(station_name):
			GameManager.station_data[station_name] = saved_stations[station_name]

	# Load characters
	GameManager.characters.clear()
	var char_data_array: Array = save_data.get("characters", [])
	print("Loading: found %d character entries" % char_data_array.size())
	for char_dict in char_data_array:
		if char_dict is Dictionary:
			var character := CharacterData.new()
			character.from_dict(char_dict)
			GameManager.characters.append(character)
			print("  Loaded character: %s (is_player=%s)" % [character.display_name, character.is_player])

	# Load contest rivals
	GameManager.contest_rivals.clear()
	var rivals_data_array: Array = save_data.get("contest_rivals", [])
	for rival_dict in rivals_data_array:
		if rival_dict is Dictionary:
			var rival := CharacterData.new()
			rival.from_dict(rival_dict)
			GameManager.contest_rivals.append(rival)


func _migrate_save_v1_to_v2(old_data: Dictionary) -> Dictionary:
	## Migrate v1 save format to v2
	## v1 had: money, current_day, timestamp, current_hour, current_minute, characters
	## v2 adds: version, quota, recruitment, station_data, contest_rivals
	var new_data := old_data.duplicate(true)
	new_data["version"] = 2

	# Calculate current week from day (7 days per week)
	var day: int = old_data.get("current_day", 1)
	var week: int = ((day - 1) / 7) + 1

	# Initialize quota state based on current day/week
	if not new_data.has("quota"):
		var base_quota: int = GameManager.STARTING_QUOTA
		var escalated_quota: int = int(base_quota * pow(1.0 + GameManager.QUOTA_ESCALATION, week - 1))
		new_data["quota"] = {
			"debt": GameManager.STARTING_DEBT,
			"current_week": week,
			"current_quota": escalated_quota,
			"weekly_earnings": 0,
			"grace_period_active": false,
			"grace_days_remaining": 0,
			"grace_shortfall": 0,
			"grace_late_fee": 0,
			"late_fee_count": 0
		}

	# Initialize empty recruitment state
	if not new_data.has("recruitment"):
		new_data["recruitment"] = {
			"applicant_pool": [],
			"active_ads": []
		}

	# Station data uses defaults (no upgrades in v1)
	if not new_data.has("station_data"):
		new_data["station_data"] = {}

	# No contest rivals in v1
	if not new_data.has("contest_rivals"):
		new_data["contest_rivals"] = []

	return new_data


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
	_save_game()

	# Reset menu state before showing
	main_menu._mode = MainMenu.MenuMode.MAIN
	main_menu._selected_index = 0
	main_menu._refresh_save_data()
	main_menu._build_main_options()

	_show_main_menu()
	main_menu._update_display()


func _on_return_to_main_menu_from_gameplay() -> void:
	return_to_main_menu()


func _on_game_over_debt() -> void:
	# Failed to pay grace period - game over
	TimeManager.stop_time()
	GameManager.clear_pause_stack()
	GameManager.is_paused = true

	# Delete the save file since game is over
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	print("Game Over - Save file deleted")

	# For now, just return to main menu
	# TODO: Show game over screen with relocation paperwork
	return_to_main_menu()
