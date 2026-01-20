extends Control
class_name MainScreen
## Main hub screen with 3-zone layout and keyboard navigation
## Zone 2 is the main interaction hub - roster and character details

signal return_to_main_menu_requested

enum MenuState { ROSTER, CHARACTER_DETAIL, ASSIGNING }

const CharacterTokenScene := preload("res://src/ui/character_token.tscn")
const VendiShopScene := preload("res://scenes/ui/vendi_shop.tscn")
const DrDanShopScene := preload("res://scenes/ui/dr_dan_shop.tscn")
const ItemsMenuScene := preload("res://scenes/ui/items_menu.tscn")
const StatsPanelScene := preload("res://scenes/ui/stats_panel.tscn")
const RelaxDialogScene := preload("res://scenes/ui/relax_dialog.tscn")
const SaveLoadMenuScene := preload("res://scenes/ui/save_load_menu.tscn")
const BingeDialogScene := preload("res://scenes/ui/binge_dialog.tscn")
const StreamSetupDialogScene := preload("res://scenes/ui/stream_setup_dialog.tscn")
const RecruitmentTerminalScene := preload("res://scenes/ui/recruitment_terminal.tscn")

@onready var background: TextureRect = $Background
@onready var zone1: PanelContainer = $Zone1  # Bottom panel - stations
@onready var zone2: PanelContainer = $Zone2  # Top right panel - roster/menu
@onready var zone3: PanelContainer = $Zone3  # Top left panel - info
@onready var characters_container: HBoxContainer = $Zone2/Zone2Content/VBox/CharactersContainer
@onready var stations_container: HBoxContainer = $Zone1/Zone1Content/StationsContainer
@onready var detail_panel: CharacterDetailPanel = $Zone2/Zone2Content/CharacterDetailPanel

# Zone 2 - License/Talent sections (created dynamically if not in scene)
var license_section: VBoxContainer
var license_label: Label
var license_token_container: HBoxContainer
var talent_label: Label

# Zone 3 labels
@onready var money_label: Label = $Zone3/Zone3Content/VBox/MoneyLabel
@onready var day_label: Label = $Zone3/Zone3Content/VBox/DayLabel
@onready var time_label: Label = $Zone3/Zone3Content/VBox/TimeLabel
@onready var period_label: Label = $Zone3/Zone3Content/VBox/PeriodLabel
@onready var ticker_clip: Control = $Zone3/Zone3Content/VBox/TickerClip
@onready var ticker_label: Label = $Zone3/Zone3Content/VBox/TickerClip/TickerLabel

# Quota labels
@onready var quota_header_label: Label = $Zone3/Zone3Content/VBox/QuotaSection/QuotaHeaderLabel
@onready var quota_progress_label: Label = $Zone3/Zone3Content/VBox/QuotaSection/QuotaProgressLabel
@onready var quota_days_label: Label = $Zone3/Zone3Content/VBox/QuotaSection/QuotaDaysLabel
@onready var debt_label: Label = $Zone3/Zone3Content/VBox/QuotaSection/DebtLabel
@onready var grace_warning_label: Label = $Zone3/Zone3Content/VBox/QuotaSection/GraceWarningLabel

# Activity log
@onready var activity_log: VBoxContainer = $Zone2/Zone2Content/VBox/ActivityScroll/ActivityLog
const MAX_ACTIVITY_ENTRIES := 10

# Sticky warnings (milk, etc) - displayed above regular log
var _sticky_warnings: Dictionary = {}  # character_id -> Label

var _menu_state: MenuState = MenuState.ROSTER
var _selected_character_index: int = 0
var _selected_station_index: int = 0
var _character_tokens: Array[CharacterToken] = []
var _station_buttons: Array[Button] = []
var _station_base_names: Array[String] = []

# Ticker state
const TICKER_SPEED := 50.0  # Pixels per second
var _ticker_messages: Array[String] = [
	"CAMMTEC NEWS: Performance metrics are up 12% this quarter...",
	"REMINDER: Weekly quota payments are due every Sunday at midnight...",
	"BREAKING: Off-world mining operations expand to asteroid belt...",
	"TIP: Keep your streamers happy for better content performance...",
	"ALERT: CammTec takes 40% of all earnings. This is non-negotiable...",
]
var _current_ticker_index: int = 0

# Vendi shop
var _vendi_shop: VendiShop = null

# Dr. Dan's shop
var _dr_dan_shop: DrDanShop = null

# Items menu
var _items_menu: ItemsMenu = null

# Stats panel
var _stats_panel: StatsPanel = null

# Relax dialog
var _relax_dialog: RelaxDialog = null
var _pending_relax_character: CharacterData = null

# Save/Load menu
var _save_load_menu: SaveLoadMenu = null

# Binge dialog
var _binge_dialog: BingeDialog = null
var _pending_binge_character: CharacterData = null

# Stream setup dialog
var _stream_setup_dialog: StreamSetupDialog = null
var _pending_stream_character: CharacterData = null

# Recruitment terminal
var _recruitment_terminal: RecruitmentTerminal = null

# Pause display alternation
const PAUSE_FLASH_INTERVAL := 1.0  # Seconds between alternating
var _pause_flash_timer: float = 0.0
var _pause_show_time: bool = false  # false = show "Paused", true = show time

# Hold Q to close all menus
const HOLD_Q_CLOSE_TIME := 0.5  # Seconds to hold Q to close all menus
var _is_holding_q: bool = false
var _hold_q_time: float = 0.0

# Empty log waiting animation
const WAITING_ANIMATION_SPEED := 0.5  # Seconds per frame
var _waiting_frame: int = 0
var _waiting_timer: float = 0.0
var _waiting_label: Label = null
const WAITING_FRAMES := [".", "..", "..."]


func _ready() -> void:
	_setup_license_talent_sections()
	_setup_stations()
	_setup_detail_panel()
	_setup_zone3()


func _setup_license_talent_sections() -> void:
	# Try to get nodes from scene, create dynamically if not found
	var vbox: VBoxContainer = $Zone2/Zone2Content/VBox

	license_section = vbox.get_node_or_null("LicenseSection")
	if not license_section:
		# Create license section dynamically
		license_section = VBoxContainer.new()
		license_section.name = "LicenseSection"
		license_section.visible = false
		license_section.add_theme_constant_override("separation", 5)

		license_label = Label.new()
		license_label.name = "LicenseLabel"
		license_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4, 1))
		license_label.add_theme_font_size_override("font_size", 14)
		license_label.text = "[LICENSE #0000]"
		license_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		license_section.add_child(license_label)

		license_token_container = HBoxContainer.new()
		license_token_container.name = "LicenseTokenContainer"
		license_token_container.add_theme_constant_override("separation", 10)
		license_token_container.alignment = BoxContainer.ALIGNMENT_CENTER
		license_section.add_child(license_token_container)

		var separator := HSeparator.new()
		license_section.add_child(separator)

		# Insert at the beginning of VBox
		vbox.add_child(license_section)
		vbox.move_child(license_section, 0)
	else:
		license_label = license_section.get_node("LicenseLabel")
		license_token_container = license_section.get_node("LicenseTokenContainer")

	talent_label = vbox.get_node_or_null("TalentLabel")
	if not talent_label:
		# Create talent label dynamically
		talent_label = Label.new()
		talent_label.name = "TalentLabel"
		talent_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		talent_label.add_theme_font_size_override("font_size", 12)
		talent_label.text = "TALENT"
		talent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Insert before CharactersContainer
		var char_container_idx := characters_container.get_index()
		vbox.add_child(talent_label)
		vbox.move_child(talent_label, char_container_idx)


func refresh_characters() -> void:
	# Clear existing tokens
	_character_tokens.clear()
	for child in characters_container.get_children():
		child.queue_free()
	for child in license_token_container.get_children():
		child.queue_free()

	# Check if player is Licensee
	var player: CharacterData = _get_player_character()
	var is_licensee := player != null and player.archetype_id == "licensee"

	if is_licensee:
		# Show license section with player token
		license_section.show()
		license_label.text = "[LICENSE #%04d]" % player.license_number

		# Create player token in license section
		var player_token: CharacterToken = CharacterTokenScene.instantiate()
		license_token_container.add_child(player_token)
		player_token.setup(player)
		_character_tokens.append(player_token)

		# Create NPC tokens in talent section
		for character in GameManager.characters:
			if not character.is_player:
				var token: CharacterToken = CharacterTokenScene.instantiate()
				characters_container.add_child(token)
				token.setup(character)
				_character_tokens.append(token)
	else:
		# Hide license section, show all characters in talent section
		license_section.hide()

		for character in GameManager.characters:
			var token: CharacterToken = CharacterTokenScene.instantiate()
			characters_container.add_child(token)
			token.setup(character)
			_character_tokens.append(token)

	_selected_character_index = 0
	_update_selection_visuals()


func _get_player_character() -> CharacterData:
	for character in GameManager.characters:
		if character.is_player:
			return character
	return null


func _setup_stations() -> void:
	for child in stations_container.get_children():
		if child is Button:
			_station_buttons.append(child)
			_station_base_names.append(child.text)  # Store original name


func _setup_detail_panel() -> void:
	if detail_panel:
		detail_panel.tab_selected.connect(_on_detail_tab_selected)


func _setup_zone3() -> void:
	# Connect to signals
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.day_changed.connect(_on_day_changed)
	GameManager.game_paused.connect(_on_game_paused)
	GameManager.quota_status_changed.connect(_on_quota_status_changed)
	GameManager.weekly_earnings_changed.connect(_on_weekly_earnings_changed)
	GameManager.grace_period_started.connect(_on_grace_period_started)
	GameManager.grace_period_ended.connect(_on_grace_period_ended)
	TimeManager.time_updated.connect(_on_time_updated)
	TimeManager.period_changed.connect(_on_period_changed)
	TimeManager.activity_logged.connect(_on_activity_logged)

	# Initial display
	_update_money_display()
	_update_day_display()
	_update_time_display()
	_update_period_display()
	_update_quota_display()
	_reset_ticker()


func _process(delta: float) -> void:
	_update_ticker(delta)
	_update_pause_flash(delta)
	_update_hold_q_close(delta)
	_update_sticky_warnings()
	_update_empty_log_animation(delta)


func _update_ticker(delta: float) -> void:
	if not ticker_label or not ticker_clip:
		return

	# Move ticker left
	ticker_label.position.x -= TICKER_SPEED * delta

	# When ticker scrolls completely off screen, reset with next message
	if ticker_label.position.x + ticker_label.size.x < 0:
		_current_ticker_index = (_current_ticker_index + 1) % _ticker_messages.size()
		_reset_ticker()


func _reset_ticker() -> void:
	if ticker_label and ticker_clip:
		var message := _ticker_messages[_current_ticker_index]
		var follower_text := _get_follower_ticker_text()
		ticker_label.text = message + "     " + follower_text
		# Start from right edge of clip area
		ticker_label.position.x = ticker_clip.size.x


func _get_follower_ticker_text() -> String:
	## Build follower count string for ticker display
	var parts: Array[String] = []
	for character in GameManager.characters:
		var followers_str := _format_number(character.followers)
		parts.append("%s: %s" % [character.display_name, followers_str])
	return "FOLLOWERS: " + " | ".join(parts)


func _update_pause_flash(delta: float) -> void:
	if not GameManager.is_paused:
		return

	_pause_flash_timer += delta
	if _pause_flash_timer >= PAUSE_FLASH_INTERVAL:
		_pause_flash_timer = 0.0
		_pause_show_time = not _pause_show_time
		_update_time_display()


func _update_hold_q_close(delta: float) -> void:
	if not _is_holding_q:
		return

	_hold_q_time += delta
	if _hold_q_time >= HOLD_Q_CLOSE_TIME:
		_close_all_menus()
		_is_holding_q = false
		_hold_q_time = 0.0


func _update_empty_log_animation(delta: float) -> void:
	if not activity_log:
		return

	# Check if log is empty (no regular entries, only sticky warnings or the waiting label)
	var waiting_count := 1 if _waiting_label else 0
	var regular_count := activity_log.get_child_count() - _sticky_warnings.size() - waiting_count

	if regular_count == 0:
		# Show waiting animation
		if not _waiting_label:
			_waiting_label = Label.new()
			_waiting_label.add_theme_font_size_override("font_size", 12)
			_waiting_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			activity_log.add_child(_waiting_label)

		# Update animation
		_waiting_timer += delta
		if _waiting_timer >= WAITING_ANIMATION_SPEED:
			_waiting_timer = 0.0
			_waiting_frame = (_waiting_frame + 1) % WAITING_FRAMES.size()
			_waiting_label.text = "Waiting" + WAITING_FRAMES[_waiting_frame]
	else:
		# Hide/remove waiting animation when log has entries
		if _waiting_label:
			_waiting_label.queue_free()
			_waiting_label = null
			_waiting_timer = 0.0
			_waiting_frame = 0


func _close_all_menus() -> void:
	## Close all open overlay menus
	if _vendi_shop and _vendi_shop.visible:
		_vendi_shop.close_shop()
	if _dr_dan_shop and _dr_dan_shop.visible:
		_dr_dan_shop.close_shop()
	if _items_menu and _items_menu.visible:
		_items_menu.close_menu()
	if _stats_panel and _stats_panel.visible:
		_stats_panel.close_panel()
	if _relax_dialog and _relax_dialog.visible:
		_relax_dialog.close_dialog()
	if _save_load_menu and _save_load_menu.visible:
		_save_load_menu.close_menu()
	if _binge_dialog and _binge_dialog.visible:
		_binge_dialog.close_dialog()
	if _recruitment_terminal and _recruitment_terminal.visible:
		_recruitment_terminal.close_terminal()


func _on_money_changed(_new_amount: int) -> void:
	_update_money_display()


func _on_day_changed(_new_day: int) -> void:
	_update_day_display()


func _on_time_updated(_hour: int, _minute: int) -> void:
	_update_time_display()


func _on_period_changed(_period: String) -> void:
	_update_period_display()


func _on_game_paused(_is_paused: bool) -> void:
	# Reset flash state when pause changes
	_pause_flash_timer = 0.0
	_pause_show_time = false  # Start by showing "Paused"
	_update_time_display()


func _on_activity_logged(message: String) -> void:
	add_activity(message)


func _update_money_display() -> void:
	if money_label:
		money_label.text = "¤%s" % _format_number(GameManager.money)


func _update_day_display() -> void:
	if day_label:
		day_label.text = "Day %d" % GameManager.current_day


func _update_time_display() -> void:
	if time_label:
		if GameManager.is_paused:
			if _pause_show_time:
				time_label.text = TimeManager.get_time_string()
			else:
				time_label.text = "Paused"
		else:
			time_label.text = TimeManager.get_time_string()


func _update_period_display() -> void:
	if period_label:
		period_label.text = TimeManager.get_period_name(TimeManager.get_current_period())


func _update_quota_display() -> void:
	# Week header
	if quota_header_label:
		quota_header_label.text = "WEEK %d QUOTA" % GameManager.current_week

	# Quota progress
	if quota_progress_label:
		var earnings_str := _format_number(GameManager.weekly_earnings)
		var quota_str := _format_number(GameManager.current_quota)
		quota_progress_label.text = "¤%s / ¤%s" % [earnings_str, quota_str]

		# Color based on progress
		var progress := GameManager.get_quota_progress_percent()
		var days_remaining := GameManager.get_days_until_week_end()
		var expected_progress := 1.0 - (float(days_remaining) / 7.0)

		if GameManager.grace_period_active:
			# During grace: red if behind on grace obligation
			var grace_owed := GameManager.get_grace_total_owed()
			if GameManager.weekly_earnings >= grace_owed:
				quota_progress_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))  # Green - met grace
			else:
				quota_progress_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))  # Red - behind
		elif progress >= 1.0:
			quota_progress_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))  # Green - met quota
		elif progress >= expected_progress:
			quota_progress_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))  # Gold - on track
		elif progress >= expected_progress * 0.7:
			quota_progress_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))  # Orange - behind
		else:
			quota_progress_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))  # Red - way behind

	# Days remaining
	if quota_days_label:
		if GameManager.grace_period_active:
			quota_days_label.text = ""  # Hide during grace period (shown in warning)
		else:
			var days := GameManager.get_days_until_week_end()
			if days == 0:
				quota_days_label.text = "Week ends today!"
				quota_days_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
			elif days == 1:
				quota_days_label.text = "1 day remaining"
				quota_days_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			else:
				quota_days_label.text = "%d days remaining" % days
				quota_days_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# Debt
	if debt_label:
		if GameManager.debt > 0:
			debt_label.text = "Debt: ¤%s" % _format_number(GameManager.debt)
			debt_label.show()
		else:
			debt_label.text = "DEBT PAID!"
			debt_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
			debt_label.show()

	# Grace period warning
	if grace_warning_label:
		if GameManager.grace_period_active:
			var total_owed := GameManager.get_grace_total_owed()
			var still_owed := maxi(0, total_owed - GameManager.weekly_earnings)
			grace_warning_label.text = "GRACE: %d days! Owe ¤%s" % [
				GameManager.grace_days_remaining,
				_format_number(still_owed)
			]
			grace_warning_label.show()
		else:
			grace_warning_label.hide()


func _on_quota_status_changed() -> void:
	_update_quota_display()


func _on_weekly_earnings_changed(_new_amount: int) -> void:
	_update_quota_display()


func _on_grace_period_started(shortfall: int, late_fee: int) -> void:
	var total := shortfall + late_fee
	var msg := "QUOTA MISSED! Pay ¤%s in %d days or face relocation." % [
		_format_number(total), GameManager.GRACE_PERIOD_DAYS
	]
	add_activity(msg)
	_update_quota_display()


func _on_grace_period_ended(success: bool) -> void:
	if success:
		add_activity("Grace period survived! Late fee paid.")
	else:
		add_activity("Grace period failed. Relocation imminent...")
	_update_quota_display()


func _format_number(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result


func _input(event: InputEvent) -> void:
	# Don't process input when main screen is not visible
	if not visible:
		return

	# Hold Q to close all menus - check this BEFORE menu visibility checks
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_Q:
			if key_event.pressed and not key_event.echo:
				_is_holding_q = true
				_hold_q_time = 0.0
			elif not key_event.pressed:
				_is_holding_q = false
				_hold_q_time = 0.0
			# Don't consume the event - let menus also handle Q for immediate close

	# Don't process main screen input when overlay menus are open
	if _vendi_shop and _vendi_shop.visible:
		return
	if _dr_dan_shop and _dr_dan_shop.visible:
		return
	if _items_menu and _items_menu.visible:
		return
	if _stats_panel and _stats_panel.visible:
		return
	if _relax_dialog and _relax_dialog.visible:
		return
	if _save_load_menu and _save_load_menu.visible:
		return
	if _binge_dialog and _binge_dialog.visible:
		return
	if _recruitment_terminal and _recruitment_terminal.visible:
		return

	# Pause toggles with Space
	if event.is_action_pressed("pause"):
		GameManager.is_paused = not GameManager.is_paused
		get_viewport().set_input_as_handled()
		return

	# Game menu with Escape - open save/load menu
	if event.is_action_pressed("game_menu"):
		_open_save_load_menu()
		get_viewport().set_input_as_handled()
		return

	# R key opens recruitment terminal (from roster view only)
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if _menu_state == MenuState.ROSTER:
			_open_recruitment_terminal()
			get_viewport().set_input_as_handled()
			return

	# Don't process navigation while paused
	if GameManager.is_paused:
		return

	# Navigation
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		_handle_horizontal_nav(event)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("accept"):
		_handle_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		_handle_back()
		get_viewport().set_input_as_handled()


func _handle_horizontal_nav(event: InputEvent) -> void:
	var direction := 1 if event.is_action_pressed("move_right") else -1

	match _menu_state:
		MenuState.ROSTER:
			if _character_tokens.size() > 0:
				_selected_character_index = wrapi(
					_selected_character_index + direction,
					0,
					_character_tokens.size()
				)
		MenuState.CHARACTER_DETAIL:
			if detail_panel:
				detail_panel.navigate_tabs(direction)
		MenuState.ASSIGNING:
			if _station_buttons.size() > 0:
				_selected_station_index = wrapi(
					_selected_station_index + direction,
					0,
					_station_buttons.size()
				)

	_update_selection_visuals()


func _handle_select() -> void:
	match _menu_state:
		MenuState.ROSTER:
			_open_character_detail()
		MenuState.CHARACTER_DETAIL:
			if detail_panel:
				detail_panel.select_current_tab()
		MenuState.ASSIGNING:
			_assign_character_to_station()


func _handle_back() -> void:
	match _menu_state:
		MenuState.ASSIGNING:
			_menu_state = MenuState.CHARACTER_DETAIL
			_update_selection_visuals()
		MenuState.CHARACTER_DETAIL:
			_close_character_detail()
		MenuState.ROSTER:
			pass


func _open_character_detail() -> void:
	if _character_tokens.is_empty():
		return

	var token := _character_tokens[_selected_character_index]
	# Don't open detail for characters currently doing a task
	if not token.character_data or token.character_data.is_busy():
		return

	if detail_panel:
		characters_container.hide()
		detail_panel.show_character(token.character_data)
		_menu_state = MenuState.CHARACTER_DETAIL
		_update_selection_visuals()


func _close_character_detail() -> void:
	if detail_panel:
		detail_panel.hide()
	characters_container.show()
	_menu_state = MenuState.ROSTER
	_update_selection_visuals()
	_refresh_character_tokens()


func _refresh_character_tokens() -> void:
	for token in _character_tokens:
		token.refresh_display()


func _on_detail_tab_selected(tab_name: String) -> void:
	var token := _character_tokens[_selected_character_index]

	match tab_name:
		"Assign":
			_menu_state = MenuState.ASSIGNING
			_update_selection_visuals()
		"Binge":
			if token.character_data:
				_open_binge_dialog(token.character_data)
		"Items":
			_open_items_menu()
		"Stats":
			_open_stats_panel()
		"Shop":
			if token.character_data and token.character_data.is_player:
				_open_vendi_shop(token.character_data)


func _get_station_base_name(index: int) -> String:
	if index >= 0 and index < _station_base_names.size():
		return _station_base_names[index]
	return ""


func _get_station_occupancy(station_name: String) -> int:
	var count := 0
	for character in GameManager.characters:
		if character.current_task_id == station_name:
			count += 1
	return count


func _is_station_full(station_name: String) -> bool:
	var max_slots := GameManager.get_station_slots(station_name)
	return _get_station_occupancy(station_name) >= max_slots


func _assign_character_to_station() -> void:
	if _character_tokens.is_empty() or _station_buttons.is_empty():
		return

	var token := _character_tokens[_selected_character_index]
	var station_name := _get_station_base_name(_selected_station_index)

	# Don't assign if station is full
	if _is_station_full(station_name):
		return

	if not token.character_data:
		return

	# Special handling for Relax station - opens duration selection dialog
	# This is the ONLY station exhausted characters can use
	if station_name == "Relax":
		_open_relax_dialog(token.character_data)
		return

	# Exhausted characters can ONLY use Relax station
	if token.character_data.is_exhausted():
		return

	# Special handling for Dr. Dan's station - opens shop
	if station_name == "Dr. Dan's":
		_open_dr_dan_shop(token.character_data)
		return

	# Special handling for Cam Studio - opens stream setup dialog
	if station_name == "Cam Studio":
		_open_stream_setup(token.character_data)
		return

	# Special handling for Milking station - requires lactating character with milk
	if station_name == "Milking":
		if not token.character_data.is_lactating:
			add_activity("%s can't be milked (not lactating)" % token.character_data.display_name)
			return
		if token.character_data.milk_current <= 0:
			add_activity("%s has no milk to collect" % token.character_data.display_name)
			return
		# Proceed with standard assignment (will fall through below)

	# Standard station assignment
	var duration := GameManager.get_station_duration(station_name)
	token.character_data.current_task_id = station_name
	token.character_data.task_time_remaining = duration
	print("Assigned %s to %s for %d minutes" % [token.character_data.display_name, station_name, int(duration)])

	# If player is assigned, skip time forward to complete all tasks
	if token.character_data.is_player:
		TimeManager.skip_time(duration)
		_refresh_character_tokens()

	# Close detail panel and return to roster
	_close_character_detail()


func _open_vendi_shop(character: CharacterData) -> void:
	if not _vendi_shop:
		_vendi_shop = VendiShopScene.instantiate()
		add_child(_vendi_shop)
		_vendi_shop.shop_closed.connect(_on_vendi_shop_closed)

	_vendi_shop.open_shop(character)


func _on_vendi_shop_closed() -> void:
	# Return to roster after closing shop
	_close_character_detail()


func _open_dr_dan_shop(character: CharacterData) -> void:
	if not _dr_dan_shop:
		_dr_dan_shop = DrDanShopScene.instantiate()
		add_child(_dr_dan_shop)
		_dr_dan_shop.shop_closed.connect(_on_dr_dan_shop_closed)

	_dr_dan_shop.open_shop(character)


func _on_dr_dan_shop_closed() -> void:
	# Return to roster after closing shop
	_close_character_detail()


func _open_items_menu() -> void:
	if _character_tokens.is_empty():
		return

	var token := _character_tokens[_selected_character_index]
	if not token.character_data:
		return

	if not _items_menu:
		_items_menu = ItemsMenuScene.instantiate()
		add_child(_items_menu)
		_items_menu.menu_closed.connect(_on_items_menu_closed)

	_items_menu.open_menu(token.character_data)


func _on_items_menu_closed() -> void:
	# Stay on detail panel after closing items menu
	_refresh_character_tokens()


func _open_stats_panel() -> void:
	if _character_tokens.is_empty():
		return

	var token := _character_tokens[_selected_character_index]
	if not token.character_data:
		return

	if not _stats_panel:
		_stats_panel = StatsPanelScene.instantiate()
		add_child(_stats_panel)
		_stats_panel.panel_closed.connect(_on_stats_panel_closed)

	_stats_panel.open_panel(token.character_data)


func _on_stats_panel_closed() -> void:
	# Stay on detail panel after closing stats
	_refresh_character_tokens()


func _open_relax_dialog(character: CharacterData) -> void:
	if not _relax_dialog:
		_relax_dialog = RelaxDialogScene.instantiate()
		add_child(_relax_dialog)
		_relax_dialog.duration_selected.connect(_on_relax_duration_selected)
		_relax_dialog.dialog_closed.connect(_on_relax_dialog_closed)

	_pending_relax_character = character
	_relax_dialog.open_dialog(character)


func _on_relax_duration_selected(minutes: float) -> void:
	if not _pending_relax_character:
		return

	# BURNOUT PENALTY: If character was exhausted, apply penalties
	if _pending_relax_character.is_exhausted():
		_apply_exhaustion_penalties(_pending_relax_character)

	# Assign character to Relax with selected duration
	_pending_relax_character.current_task_id = "Relax"
	_pending_relax_character.task_time_remaining = minutes
	print("Assigned %s to Relax for %d minutes" % [_pending_relax_character.display_name, int(minutes)])

	# If player is assigned, skip time forward
	if _pending_relax_character.is_player:
		TimeManager.skip_time(minutes)
		_refresh_character_tokens()

	_pending_relax_character = null
	_close_character_detail()


func _apply_exhaustion_penalties(character: CharacterData) -> void:
	## Apply penalties when an exhausted character starts recovering
	const FOLLOWER_LOSS_PERCENT := 10  # Lose 10% of followers
	const CHARM_PENALTY := 15  # Temporary charm reduction
	const BURNOUT_DAYS := 3  # How long the charm penalty lasts

	# Follower loss - fans don't like seeing their favorite streamer burned out
	var follower_loss := int(character.followers * FOLLOWER_LOSS_PERCENT / 100.0)
	if follower_loss < 1 and character.followers > 0:
		follower_loss = 1
	character.followers = maxi(0, character.followers - follower_loss)

	# Apply temporary charm penalty (burnout makes you less appealing)
	character.apply_burnout_penalty(CHARM_PENALTY, BURNOUT_DAYS)

	# Log the penalties
	var msg := "%s burned out! Lost %d followers, charm reduced for %d days" % [
		character.display_name, follower_loss, BURNOUT_DAYS
	]
	TimeManager.activity_logged.emit(msg)
	print(msg)


func _on_relax_dialog_closed() -> void:
	_pending_relax_character = null
	# Return to station selection if dialog was cancelled
	_update_selection_visuals()


func _open_save_load_menu() -> void:
	if not _save_load_menu:
		_save_load_menu = SaveLoadMenuScene.instantiate()
		add_child(_save_load_menu)
		_save_load_menu.menu_closed.connect(_on_save_load_menu_closed)
		_save_load_menu.return_to_main_menu_requested.connect(_on_return_to_main_menu_requested)

	_save_load_menu.open_menu()


func _on_save_load_menu_closed() -> void:
	# Refresh displays in case a game was loaded
	_update_money_display()
	_update_day_display()
	_update_time_display()
	_update_period_display()
	_update_quota_display()
	_refresh_character_tokens()


func _on_return_to_main_menu_requested() -> void:
	return_to_main_menu_requested.emit()


func _open_binge_dialog(character: CharacterData) -> void:
	if not _binge_dialog:
		_binge_dialog = BingeDialogScene.instantiate()
		add_child(_binge_dialog)
		_binge_dialog.binge_started.connect(_on_binge_started)
		_binge_dialog.dialog_closed.connect(_on_binge_dialog_closed)

	_pending_binge_character = character
	_binge_dialog.open_dialog(character)


func _on_binge_started(total_fill: int) -> void:
	if not _pending_binge_character:
		return

	# Calculate duration based on items in queue (more items = longer binge)
	var base_duration := GameManager.get_station_duration("Binge")
	var item_count := _pending_binge_character.get_food_queue_count()
	var duration := base_duration + (item_count * 10.0)  # +10 min per item

	# Assign character to Binge station
	_pending_binge_character.current_task_id = "Binge"
	_pending_binge_character.task_time_remaining = duration
	print("Assigned %s to Binge (fill: %d, duration: %.0f min)" % [_pending_binge_character.display_name, total_fill, duration])

	# If player is assigned, skip time forward
	if _pending_binge_character.is_player:
		TimeManager.skip_time(duration)
		_refresh_character_tokens()

	_pending_binge_character = null
	_close_character_detail()


func _on_binge_dialog_closed() -> void:
	_pending_binge_character = null
	_update_selection_visuals()


func _open_stream_setup(character: CharacterData) -> void:
	if not _stream_setup_dialog:
		_stream_setup_dialog = StreamSetupDialogScene.instantiate()
		add_child(_stream_setup_dialog)
		_stream_setup_dialog.stream_started.connect(_on_stream_started)
		_stream_setup_dialog.dialog_closed.connect(_on_stream_dialog_closed)

	_pending_stream_character = character
	_stream_setup_dialog.open_dialog(character)


func _on_stream_started(stream_data: Dictionary) -> void:
	if not _pending_stream_character:
		return

	var duration: int = stream_data.get("total_duration", 120)

	# Store stream data for completion processing
	_pending_stream_character.pending_stream_data = stream_data

	# Assign character to Cam Studio
	_pending_stream_character.current_task_id = "Cam Studio"
	_pending_stream_character.task_time_remaining = duration
	var kit_name: String = stream_data.get("kit_name", "Standard")
	print("Assigned %s to stream (%s, duration: %d min)" % [_pending_stream_character.display_name, kit_name, duration])

	# If player is assigned, skip time forward
	if _pending_stream_character.is_player:
		TimeManager.skip_time(duration)
		_refresh_character_tokens()

	_pending_stream_character = null
	_close_character_detail()


func _on_stream_dialog_closed() -> void:
	_pending_stream_character = null
	_update_selection_visuals()


func _open_recruitment_terminal() -> void:
	if not _recruitment_terminal:
		_recruitment_terminal = RecruitmentTerminalScene.instantiate()
		add_child(_recruitment_terminal)
		_recruitment_terminal.terminal_closed.connect(_on_recruitment_terminal_closed)

	_recruitment_terminal.open_terminal()


func _on_recruitment_terminal_closed() -> void:
	# Refresh character display in case we hired someone
	refresh_characters()
	_update_selection_visuals()


func _update_selection_visuals() -> void:
	# Update character token selection (only in ROSTER state)
	for i in range(_character_tokens.size()):
		var is_selected := (i == _selected_character_index) and (_menu_state == MenuState.ROSTER)
		_character_tokens[i].set_selected(is_selected)

	# Get selected character for exhaustion check
	var selected_character: CharacterData = null
	if not _character_tokens.is_empty() and _selected_character_index < _character_tokens.size():
		selected_character = _character_tokens[_selected_character_index].character_data

	# Update station button visuals
	for i in range(_station_buttons.size()):
		var button := _station_buttons[i]
		var station_name := _get_station_base_name(i)
		var occupancy := _get_station_occupancy(station_name)
		var max_slots := GameManager.get_station_slots(station_name)
		var is_full := occupancy >= max_slots
		var is_selected := (i == _selected_station_index) and (_menu_state == MenuState.ASSIGNING)

		# Check if station is blocked for exhausted character (only Relax allowed)
		var is_blocked_by_exhaustion := false
		if selected_character and selected_character.is_exhausted() and station_name != "Relax":
			is_blocked_by_exhaustion = true

		# Update button text to show occupancy
		button.text = "%s %d/%d" % [station_name, occupancy, max_slots]

		if _menu_state == MenuState.ASSIGNING:
			if is_full or is_blocked_by_exhaustion:
				# Grey out full stations or blocked stations for exhausted characters
				button.modulate = Color(0.5, 0.5, 0.5)
				button.remove_theme_stylebox_override("normal")
			elif is_selected:
				button.modulate = Color(1.0, 1.0, 1.0)
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.2, 0.2, 0.2)
				style.border_color = Color(1.0, 0.85, 0.4)
				style.set_border_width_all(2)
				style.set_corner_radius_all(4)
				button.add_theme_stylebox_override("normal", style)
			else:
				button.modulate = Color(1.0, 1.0, 1.0)
				button.remove_theme_stylebox_override("normal")
		else:
			# Reset when not in ASSIGNING mode
			button.modulate = Color(1.0, 1.0, 1.0)
			button.remove_theme_stylebox_override("normal")


func set_background_texture(texture: Texture2D) -> void:
	if background:
		background.texture = texture


func add_activity(message: String) -> void:
	if not activity_log:
		return

	# Remove waiting animation if present
	if _waiting_label:
		_waiting_label.queue_free()
		_waiting_label = null

	# Create new label for this activity
	var label := Label.new()
	label.text = "- " + message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

	# Add after sticky warnings (find first non-sticky entry)
	var insert_index := _sticky_warnings.size()
	activity_log.add_child(label)
	activity_log.move_child(label, insert_index)

	# Remove old entries if over limit (don't count sticky warnings)
	var regular_count := activity_log.get_child_count() - _sticky_warnings.size()
	while regular_count > MAX_ACTIVITY_ENTRIES:
		var old_child := activity_log.get_child(activity_log.get_child_count() - 1)
		old_child.queue_free()
		regular_count -= 1


func _update_sticky_warnings() -> void:
	## Update sticky warning labels for milk status
	if not activity_log:
		return

	for character in GameManager.characters:
		if not character.is_lactating:
			# Remove warning if no longer lactating
			_remove_sticky_warning(character.id)
			continue

		var discomfort: int = character.get_milk_discomfort_level()
		var milk_percent: float = character.get_milk_percent()

		if discomfort >= 2:
			# Severe discomfort - red warning
			var msg := "%s needs milking NOW! (severe discomfort)" % character.display_name
			_set_sticky_warning(character.id, msg, Color(1.0, 0.3, 0.3))
		elif discomfort >= 1:
			# Mild discomfort - orange warning
			var msg := "%s is full and uncomfortable (milk: %d%%)" % [character.display_name, int(milk_percent)]
			_set_sticky_warning(character.id, msg, Color(1.0, 0.6, 0.2))
		elif milk_percent >= 80.0:
			# Warning threshold - yellow
			var msg := "%s milk storage at %d%% - consider milking" % [character.display_name, int(milk_percent)]
			_set_sticky_warning(character.id, msg, Color(1.0, 0.9, 0.3))
		else:
			# No warning needed
			_remove_sticky_warning(character.id)


func _set_sticky_warning(character_id: String, message: String, color: Color) -> void:
	## Set or update a sticky warning for a character
	if _sticky_warnings.has(character_id):
		# Update existing
		var label: Label = _sticky_warnings[character_id]
		label.text = "! " + message
		label.add_theme_color_override("font_color", color)
	else:
		# Create new sticky warning
		var label := Label.new()
		label.text = "! " + message
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", color)
		_sticky_warnings[character_id] = label

		# Add at the very top
		activity_log.add_child(label)
		activity_log.move_child(label, 0)


func _remove_sticky_warning(character_id: String) -> void:
	## Remove a sticky warning for a character
	if _sticky_warnings.has(character_id):
		var label: Label = _sticky_warnings[character_id]
		label.queue_free()
		_sticky_warnings.erase(character_id)
