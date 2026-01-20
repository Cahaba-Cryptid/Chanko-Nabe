extends CanvasLayer
class_name HUD
## Main HUD displaying time, money, and quick info

@onready var money_label: Label = $TopBar/MoneyLabel
@onready var day_label: Label = $TopBar/DayLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var period_label: Label = $TopBar/PeriodLabel
@onready var speed_button: Button = $TopBar/SpeedButton

var _time_scales: Array[float] = [1.0, 2.0, 4.0, 8.0]
var _current_speed_index := 0


func _ready() -> void:
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.day_changed.connect(_on_day_changed)
	TimeManager.time_updated.connect(_on_time_updated)
	TimeManager.period_changed.connect(_on_period_changed)

	_update_display()


func _update_display() -> void:
	_on_money_changed(GameManager.money)
	_on_day_changed(GameManager.current_day)
	_on_time_updated(TimeManager.current_hour, TimeManager.current_minute)
	_on_period_changed(TimeManager.get_period_name(TimeManager.get_current_period()))


func _on_money_changed(new_amount: int) -> void:
	if money_label:
		money_label.text = "$%d" % new_amount


func _on_day_changed(new_day: int) -> void:
	if day_label:
		day_label.text = "Day %d" % new_day


func _on_time_updated(hour: int, minute: int) -> void:
	if time_label:
		time_label.text = "%02d:%02d" % [hour, minute]


func _on_period_changed(period: String) -> void:
	if period_label:
		period_label.text = period


func _on_speed_button_pressed() -> void:
	_current_speed_index = (_current_speed_index + 1) % _time_scales.size()
	var new_scale := _time_scales[_current_speed_index]
	TimeManager.time_scale = new_scale

	if speed_button:
		speed_button.text = "%dx" % int(new_scale)
