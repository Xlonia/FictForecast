extends Window
## 日历（公历，0.0.1 收官批复）：月视图网格，点日期跳转——保留当日的时刻，只换日期。
## 嵌在主窗口内的子窗口（随主程序关闭）。跳转由主界面执行（本窗口只发信号）；
## “回到现在”同主菜单的「恢复现在」。

signal date_picked(year: int, month: int, day: int)
signal now_requested

var _year := 2026
var _month := 1
var _current := {"year": 0, "month": 0, "day": 0}   # 主界面正在显示的那天（高亮用）

@onready var prev_btn: Button = $Panel/Column/Header/PrevBtn
@onready var next_btn: Button = $Panel/Column/Header/NextBtn
@onready var month_label: Label = $Panel/Column/Header/MonthLabel
@onready var day_grid: GridContainer = $Panel/Column/DayGrid
@onready var now_btn: Button = $Panel/Column/Footer/NowBtn
@onready var close_btn: Button = $Panel/Column/Footer/CloseBtn


func _ready() -> void:
	close_btn.pressed.connect(hide)
	now_btn.pressed.connect(_on_now)
	prev_btn.pressed.connect(_go_month.bind(-1))
	next_btn.pressed.connect(_go_month.bind(1))


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()


## 打开：current = 主界面正在显示的 {year, month, day}（高亮）。
func open(current: Dictionary) -> void:
	_current = current.duplicate()
	_year = int(current.get("year", 2026))
	_month = int(current.get("month", 1))
	_rebuild()
	if visible:
		grab_focus()
	else:
		popup_centered()


func _go_month(delta: int) -> void:
	_month += delta
	if _month < 1:
		_month = 12
		_year -= 1
	elif _month > 12:
		_month = 1
		_year += 1
	_rebuild()


func _on_now() -> void:
	now_requested.emit()
	hide()


func _rebuild() -> void:
	month_label.text = UiText.f("%d 年 %d 月", [_year, _month])
	for c in day_grid.get_children():
		day_grid.remove_child(c)
		c.queue_free()
	var main := get_parent()  # 主界面控制器：借用它的星期算法（0=周日）
	var lead := 0
	if main != null and main.get("_weekday") != null:
		lead = main._weekday(_year, _month, 1)
	for i in lead:
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(44, 30)
		day_grid.add_child(pad)
	var days: int = WeatherEngine._days_in_month(_year, _month)
	for d in range(1, days + 1):
		var btn := Button.new()
		btn.text = str(d)
		btn.custom_minimum_size = Vector2(44, 30)
		var is_current: bool = int(_current.get("year", 0)) == _year \
				and int(_current.get("month", 0)) == _month and int(_current.get("day", 0)) == d
		if is_current:
			btn.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3))
		var day := d
		btn.pressed.connect(func() -> void:
			date_picked.emit(_year, _month, day)
			_current = {"year": _year, "month": _month, "day": day}
			_rebuild()
			hide())
		day_grid.add_child(btn)
