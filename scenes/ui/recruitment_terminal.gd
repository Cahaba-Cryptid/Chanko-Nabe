extends Control
class_name RecruitmentTerminal
## Recruitment terminal UI for placing ads and viewing/hiring applicants

signal terminal_closed

enum TerminalMode { ADS, APPLICANTS }

@onready var mode_label: Label = $Panel/VBox/Header/ModeLabel
@onready var money_label: Label = $Panel/VBox/Header/MoneyLabel
@onready var content_container: VBoxContainer = $Panel/VBox/ContentScroll/ContentContainer
@onready var info_panel: PanelContainer = $Panel/VBox/InfoPanel
@onready var info_label: Label = $Panel/VBox/InfoPanel/InfoLabel
@onready var controls_label: Label = $Panel/VBox/ControlsLabel

var _mode: TerminalMode = TerminalMode.ADS
var _selected_index: int = 0
var _ad_tiers: Array = []
var _applicants: Array = []

const ARCHETYPE_COLORS := {
	"feeder": Color(0.9, 0.7, 0.5),
	"glutton": Color(0.9, 0.6, 0.4),
	"egirl": Color(0.9, 0.5, 0.8),
	"broodmother": Color(0.7, 0.5, 0.9),
	"hucow": Color(0.5, 0.8, 0.7),
	"cybergoth": Color(0.5, 0.7, 0.9)
}


func _ready() -> void:
	hide()
	GameManager.applicant_pool_changed.connect(_on_applicant_pool_changed)
	GameManager.money_changed.connect(_on_money_changed)


func open_terminal() -> void:
	_ad_tiers = GameManager.get_ad_tiers()
	_applicants = GameManager.applicant_pool.duplicate()
	_mode = TerminalMode.ADS
	_selected_index = 0
	_update_money_display()
	_refresh_display()
	show()


func close_terminal() -> void:
	hide()
	terminal_closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("back") or event.is_action_pressed("game_menu"):
		close_terminal()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		_switch_mode()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_down"):
		_navigate(1)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("accept"):
		_select_current()
		get_viewport().set_input_as_handled()
		return

	# X to reject applicant
	if event is InputEventKey and event.pressed and event.keycode == KEY_X:
		if _mode == TerminalMode.APPLICANTS and not _applicants.is_empty():
			_reject_current_applicant()
			get_viewport().set_input_as_handled()
			return


func _switch_mode() -> void:
	if _mode == TerminalMode.ADS:
		_mode = TerminalMode.APPLICANTS
	else:
		_mode = TerminalMode.ADS
	_selected_index = 0
	_refresh_display()


func _navigate(direction: int) -> void:
	var max_items := _ad_tiers.size() if _mode == TerminalMode.ADS else _applicants.size()
	if max_items == 0:
		return
	_selected_index = wrapi(_selected_index + direction, 0, max_items)
	_refresh_display()


func _select_current() -> void:
	match _mode:
		TerminalMode.ADS:
			_place_selected_ad()
		TerminalMode.APPLICANTS:
			_hire_selected_applicant()


func _place_selected_ad() -> void:
	if _ad_tiers.is_empty() or _selected_index >= _ad_tiers.size():
		return

	var tier: Dictionary = _ad_tiers[_selected_index]
	var tier_id: String = tier.get("id", "")

	if GameManager.place_recruitment_ad(tier_id):
		_applicants = GameManager.applicant_pool.duplicate()
		_refresh_display()


func _hire_selected_applicant() -> void:
	if _applicants.is_empty() or _selected_index >= _applicants.size():
		return

	var applicant: Dictionary = _applicants[_selected_index]
	var hired := GameManager.hire_applicant(applicant)

	if hired:
		_applicants = GameManager.applicant_pool.duplicate()
		_selected_index = mini(_selected_index, maxi(0, _applicants.size() - 1))
		_refresh_display()


func _reject_current_applicant() -> void:
	if _applicants.is_empty() or _selected_index >= _applicants.size():
		return

	var applicant: Dictionary = _applicants[_selected_index]
	GameManager.reject_applicant(applicant)
	_applicants = GameManager.applicant_pool.duplicate()
	_selected_index = mini(_selected_index, maxi(0, _applicants.size() - 1))
	_refresh_display()


func _refresh_display() -> void:
	_update_mode_label()
	_clear_content()

	match _mode:
		TerminalMode.ADS:
			_display_ads()
			_update_ad_info()
			controls_label.text = "[Left/Right] Switch Tab  [Up/Down] Navigate  [Enter] Place Ad  [Q] Close"
		TerminalMode.APPLICANTS:
			_display_applicants()
			_update_applicant_info()
			controls_label.text = "[Left/Right] Switch Tab  [Up/Down] Navigate  [Enter] Hire  [X] Reject  [Q] Close"


func _update_mode_label() -> void:
	var ads_text := "ADS" if _mode != TerminalMode.ADS else "> ADS <"
	var app_text := "APPLICANTS" if _mode != TerminalMode.APPLICANTS else "> APPLICANTS <"
	var app_count := " (%d)" % _applicants.size() if not _applicants.is_empty() else ""
	mode_label.text = "%s    %s%s" % [ads_text, app_text, app_count]


func _update_money_display() -> void:
	money_label.text = "Balance: $%d" % GameManager.money


func _clear_content() -> void:
	for child in content_container.get_children():
		child.queue_free()


func _display_ads() -> void:
	for i in range(_ad_tiers.size()):
		var tier: Dictionary = _ad_tiers[i]
		var is_selected := (i == _selected_index)
		var can_afford := GameManager.can_afford(tier.get("cost", 0))

		var entry := _create_ad_entry(tier, is_selected, can_afford)
		content_container.add_child(entry)

	# Show active ads
	if not GameManager.active_ads.is_empty():
		var separator := HSeparator.new()
		content_container.add_child(separator)

		var active_label := Label.new()
		active_label.text = "ACTIVE ADS:"
		active_label.add_theme_font_size_override("font_size", 12)
		active_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		content_container.add_child(active_label)

		for ad in GameManager.active_ads:
			var tier := GameManager.get_ad_tier(ad.get("tier_id", ""))
			var ad_entry := Label.new()
			ad_entry.text = "  %s - %d day(s) remaining" % [
				tier.get("name", "Unknown"),
				ad.get("days_remaining", 0)
			]
			ad_entry.add_theme_font_size_override("font_size", 11)
			ad_entry.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
			content_container.add_child(ad_entry)


func _create_ad_entry(tier: Dictionary, is_selected: bool, can_afford: bool) -> Control:
	var container := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = tier.get("name", "Unknown")
	name_label.custom_minimum_size.x = 150
	name_label.add_theme_font_size_override("font_size", 14)

	var cost_label := Label.new()
	cost_label.text = "$%d" % tier.get("cost", 0)
	cost_label.custom_minimum_size.x = 80
	cost_label.add_theme_font_size_override("font_size", 14)

	var count_range: Array = tier.get("applicant_count", [1, 2])
	var count_label := Label.new()
	count_label.text = "%d-%d applicants" % [count_range[0], count_range[1]]
	count_label.add_theme_font_size_override("font_size", 12)

	if is_selected:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		cost_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		count_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	elif not can_afford:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		cost_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		count_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	container.add_child(name_label)
	container.add_child(cost_label)
	container.add_child(count_label)

	return container


func _update_ad_info() -> void:
	if _ad_tiers.is_empty() or _selected_index >= _ad_tiers.size():
		info_label.text = "No ad tiers available"
		return

	var tier: Dictionary = _ad_tiers[_selected_index]
	var stat_range: Array = tier.get("stat_range", [30, 50])
	var salary_range: Array = tier.get("salary_range", [40, 80])
	var duration: int = tier.get("duration_days", 1)

	var text := "%s\n\n" % tier.get("description", "")
	text += "Stat Range: %d-%d\n" % [stat_range[0], stat_range[1]]
	text += "Salary Range: $%d-$%d/day\n" % [salary_range[0], salary_range[1]]
	text += "Duration: %d day(s)" % duration

	info_label.text = text


func _display_applicants() -> void:
	if _applicants.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No applicants. Place an ad to attract talent."
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		content_container.add_child(empty_label)
		return

	for i in range(_applicants.size()):
		var applicant: Dictionary = _applicants[i]
		var is_selected := (i == _selected_index)
		var can_afford := GameManager.can_afford(applicant.get("signing_bonus", 0))

		var entry := _create_applicant_entry(applicant, is_selected, can_afford)
		content_container.add_child(entry)


func _create_applicant_entry(applicant: Dictionary, is_selected: bool, can_afford: bool) -> Control:
	var container := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = applicant.get("display_name", "Unknown")
	name_label.custom_minimum_size.x = 120
	name_label.add_theme_font_size_override("font_size", 13)

	var archetype_id: String = applicant.get("archetype_id", "feeder")
	var arch_data := CharacterData._get_archetype_data(archetype_id)
	var arch_label := Label.new()
	arch_label.text = arch_data.get("name", archetype_id.capitalize())
	arch_label.custom_minimum_size.x = 90
	arch_label.add_theme_font_size_override("font_size", 12)
	arch_label.add_theme_color_override("font_color", ARCHETYPE_COLORS.get(archetype_id, Color.WHITE))

	var salary_label := Label.new()
	salary_label.text = "$%d/day" % applicant.get("daily_salary", 50)
	salary_label.custom_minimum_size.x = 70
	salary_label.add_theme_font_size_override("font_size", 12)

	var days_remaining := GameManager.get_applicant_days_remaining(applicant)
	var days_label := Label.new()
	days_label.text = "%dd" % days_remaining
	days_label.custom_minimum_size.x = 30
	days_label.add_theme_font_size_override("font_size", 11)
	if days_remaining <= 1:
		days_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	elif days_remaining <= 2:
		days_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))

	if is_selected:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		salary_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	elif not can_afford:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		salary_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	container.add_child(name_label)
	container.add_child(arch_label)
	container.add_child(salary_label)
	container.add_child(days_label)

	return container


func _update_applicant_info() -> void:
	if _applicants.is_empty() or _selected_index >= _applicants.size():
		info_label.text = "Select an applicant to view details"
		return

	var applicant: Dictionary = _applicants[_selected_index]
	var archetype_id: String = applicant.get("archetype_id", "feeder")
	var arch_data := CharacterData._get_archetype_data(archetype_id)

	var text := "%s (%s)\n\n" % [
		applicant.get("display_name", "Unknown"),
		arch_data.get("name", archetype_id.capitalize())
	]

	text += "Stats:\n"
	text += "  Charm: %d  Talent: %d\n" % [applicant.get("charm", 0), applicant.get("talent", 0)]
	text += "  Stamina: %d  Style: %d\n\n" % [applicant.get("stamina", 0), applicant.get("style", 0)]

	text += "Followers: %d\n" % applicant.get("followers", 0)
	text += "Daily Salary: $%d\n" % applicant.get("daily_salary", 0)
	text += "Signing Bonus: $%d\n\n" % applicant.get("signing_bonus", 0)

	var days_remaining := GameManager.get_applicant_days_remaining(applicant)
	text += "Leaves in %d day(s)" % days_remaining

	info_label.text = text


func _on_applicant_pool_changed() -> void:
	if visible:
		_applicants = GameManager.applicant_pool.duplicate()
		if _mode == TerminalMode.APPLICANTS:
			_refresh_display()


func _on_money_changed(_amount: int) -> void:
	if visible:
		_update_money_display()
		_refresh_display()
