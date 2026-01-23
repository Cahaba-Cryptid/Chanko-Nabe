extends PanelContainer
class_name DraftPickDialog
## Dialog for selecting a rookie NPC when starting as Licensee

signal rookie_selected(selected: CharacterData, rejected: Array[CharacterData])
signal dialog_cancelled

const ROOKIE_STAT_MIN := 20
const ROOKIE_STAT_MAX := 45
const ROOKIE_FOLLOWERS_MIN := 300
const ROOKIE_FOLLOWERS_MAX := 600
const ROOKIE_SALARY_MIN := 25
const ROOKIE_SALARY_MAX := 45

const CATEGORY_NAMES := {
	"fried": "Fried",
	"rice": "Rice",
	"noodles": "Noodles",
	"grilled": "Grilled",
	"sweet": "Sweet",
	"soup": "Soup"
}

# Archetypes available for rookies (excluding Licensee)
const ROOKIE_ARCHETYPES := ["glutton", "broodmother", "egirl", "cybergoth", "hucow"]

var _candidates: Array[CharacterData] = []
var _selected_index: int = 0
var _candidate_panels: Array[PanelContainer] = []

@onready var title_label: Label = $MarginContainer/VBox/TitleLabel
@onready var candidates_container: HBoxContainer = $MarginContainer/VBox/CandidatesContainer


func _ready() -> void:
	hide()
	_candidate_panels = [
		$MarginContainer/VBox/CandidatesContainer/Candidate1,
		$MarginContainer/VBox/CandidatesContainer/Candidate2,
		$MarginContainer/VBox/CandidatesContainer/Candidate3
	]


func open_dialog() -> void:
	_generate_candidates()
	_selected_index = 0
	_refresh_display()
	show()
	GameManager.push_pause("draft_pick_dialog")


func close_dialog() -> void:
	hide()
	GameManager.pop_pause("draft_pick_dialog")


func _generate_candidates() -> void:
	_candidates.clear()

	var recruitment_data := _load_recruitment_data()
	var name_pools: Dictionary = recruitment_data.get("name_pools", {})
	var first_names: Array = name_pools.get("first_names", ["Rookie"])
	var last_names: Array = name_pools.get("last_names", ["Talent"])

	for i in range(3):
		var candidate := CharacterData.new()
		candidate.id = "rookie_candidate_%d" % i
		candidate.is_player = false

		# Random name
		var first_name: String = first_names[randi() % first_names.size()]
		var last_name: String = last_names[randi() % last_names.size()]
		candidate.display_name = "%s %s" % [first_name, last_name]

		# Random archetype (excluding Licensee)
		candidate.archetype_id = ROOKIE_ARCHETYPES[randi() % ROOKIE_ARCHETYPES.size()]

		# Capped stats for rookies
		candidate.charm = randi_range(ROOKIE_STAT_MIN, ROOKIE_STAT_MAX)
		candidate.talent = randi_range(ROOKIE_STAT_MIN, ROOKIE_STAT_MAX)
		candidate.stamina = randi_range(ROOKIE_STAT_MIN, ROOKIE_STAT_MAX)
		candidate.style = randi_range(ROOKIE_STAT_MIN, ROOKIE_STAT_MAX)

		# Apply archetype stat adjustments (smaller bonus for rookies)
		var arch_data := CharacterData._get_archetype_data(candidate.archetype_id)
		var stat_weights: Dictionary = arch_data.get("stat_weights", {})
		if stat_weights.has("charm"):
			candidate.charm = clampi(int(candidate.charm * (1.0 + stat_weights["charm"] * 0.2)), 1, ROOKIE_STAT_MAX + 10)
		if stat_weights.has("talent"):
			candidate.talent = clampi(int(candidate.talent * (1.0 + stat_weights["talent"] * 0.2)), 1, ROOKIE_STAT_MAX + 10)
		if stat_weights.has("stamina"):
			candidate.stamina = clampi(int(candidate.stamina * (1.0 + stat_weights["stamina"] * 0.2)), 1, ROOKIE_STAT_MAX + 10)
		if stat_weights.has("style"):
			candidate.style = clampi(int(candidate.style * (1.0 + stat_weights["style"] * 0.2)), 1, ROOKIE_STAT_MAX + 10)

		# Other rookie stats
		candidate.daily_salary = randi_range(ROOKIE_SALARY_MIN, ROOKIE_SALARY_MAX)
		candidate.followers = randi_range(ROOKIE_FOLLOWERS_MIN, ROOKIE_FOLLOWERS_MAX)
		candidate.mood = 70
		candidate.energy = 100

		# Apply archetype bonuses and random food preferences
		candidate.apply_archetype_creation_bonuses()
		candidate.randomize_food_preferences()

		_candidates.append(candidate)


func _load_recruitment_data() -> Dictionary:
	var file := FileAccess.open("res://data/recruitment.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK:
			return json.data
	return {}


func _refresh_display() -> void:
	for i in range(3):
		_update_candidate_panel(i)
	_update_selection_visuals()


func _update_candidate_panel(index: int) -> void:
	if index >= _candidates.size() or index >= _candidate_panels.size():
		return

	var candidate: CharacterData = _candidates[index]
	var panel: PanelContainer = _candidate_panels[index]
	var vbox := panel.get_node("VBox") as VBoxContainer

	var name_label := vbox.get_node("NameLabel") as Label
	var archetype_label := vbox.get_node("ArchetypeLabel") as Label
	var stats_label := vbox.get_node("StatsLabel") as Label
	var prefs_label := vbox.get_node("PrefsLabel") as Label

	name_label.text = candidate.display_name

	# Get archetype display name
	var arch_data := CharacterData._get_archetype_data(candidate.archetype_id)
	archetype_label.text = arch_data.get("name", candidate.archetype_id.capitalize())

	# Stats display
	stats_label.text = "Charm: %d\nTalent: %d\nStamina: %d\nStyle: %d" % [
		candidate.charm, candidate.talent, candidate.stamina, candidate.style
	]

	# Food preferences
	var likes_str := ""
	var dislikes_str := ""
	for like in candidate.food_likes:
		if likes_str != "":
			likes_str += ", "
		likes_str += CATEGORY_NAMES.get(like, like.capitalize())
	for dislike in candidate.food_dislikes:
		if dislikes_str != "":
			dislikes_str += ", "
		dislikes_str += CATEGORY_NAMES.get(dislike, dislike.capitalize())

	prefs_label.text = "Likes: %s\nDislikes: %s" % [likes_str, dislikes_str]


func _update_selection_visuals() -> void:
	for i in range(_candidate_panels.size()):
		var panel: PanelContainer = _candidate_panels[i]
		if i == _selected_index:
			panel.modulate = Color(1.2, 1.2, 1.0)  # Highlighted
			panel.self_modulate = Color(0.3, 0.4, 0.5)  # Slightly different bg
		else:
			panel.modulate = Color(0.8, 0.8, 0.8)  # Dimmed
			panel.self_modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_selection_visuals()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_selected_index = mini(2, _selected_index + 1)
		_update_selection_visuals()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_confirm_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("back"):
		close_dialog()
		dialog_cancelled.emit()
		get_viewport().set_input_as_handled()


func _confirm_selection() -> void:
	if _selected_index < 0 or _selected_index >= _candidates.size():
		return

	var selected: CharacterData = _candidates[_selected_index]
	var rejected: Array[CharacterData] = []

	for i in range(_candidates.size()):
		if i != _selected_index:
			rejected.append(_candidates[i])

	close_dialog()
	rookie_selected.emit(selected, rejected)
