extends Control
## 幻想气象局 · 主界面控制器
##
## v1 范围：读取 Climate/*.csv 的逐月气候数据；模拟时间按可调流速推进；
## 每天用「日照加权随机」抽出 晴/阴/雨，并给出日高低温与降雨可能。
## 随机评分筛选机制尚未实装（引擎已按“单日候选”结构预留）。
##
## 开发辅助：环境变量 FF_TIME_SCALE 可在启动时覆盖时间流速倍率。

const DATA_DIR := "res://Climate"

const ID_RELOAD := 100
const ID_NEXT_DAY := 101
const ID_EDITOR := 103
const ID_RESUME_NOW := 104
const ID_QUIT := 102
const ID_HELP_GUIDE := 200
const ID_HELP_ABOUT := 201

# 时间流速选项：[菜单文本, 倍率]
const TIME_SPEEDS: Array = [
	["暂停", 0.0],
	["1×（与真实时间同步）", 1.0],
	["60×（1 秒 = 1 分钟）", 60.0],
	["600×（1 秒 = 10 分钟）", 600.0],
	["3600×（1 秒 = 1 小时）", 3600.0],
]

# 本月气候背景面板：[语义键, 显示名, 数值格式]
const MONTH_ROWS: Array = [
	["high_temp", "平均日高温", "%.1f °C"],
	["low_temp", "平均日低温", "%.1f °C"],
	["precip", "平均降水量", "%.1f mm"],
	["rain_days", "平均降水天数", "%.1f 天"],
	["snow_days", "平均降雪天数", "%.1f 天"],
	["humidity", "平均湿度", "%.0f %%"],
	["sunshine", "平均日照时长", "%.1f 小时"],
]

const WEEKDAY_NAMES := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

## 与 WeatherEngine.Sky 数值一致（0=晴 1=阴 2=雨）；GDScript 常量折叠
## 不解析跨类枚举成员，故此处用本地枚举。
enum SkyKind { SUNNY, CLOUDY, RAINY }

const SKY_NAMES := {
	SkyKind.SUNNY: "晴",
	SkyKind.CLOUDY: "阴",
	SkyKind.RAINY: "雨",
}
const SKY_DESC := {
	SkyKind.SUNNY: "高压气团控制，天空晴朗",
	SkyKind.CLOUDY: "云层增厚，阳光时隐时现",
	SkyKind.RAINY: "降水云系过境，出门记得带伞",
}
const SKY_BG := {
	SkyKind.SUNNY: Color(0.16, 0.38, 0.62),
	SkyKind.CLOUDY: Color(0.27, 0.32, 0.41),
	SkyKind.RAINY: Color(0.16, 0.21, 0.28),
}

var climates: Array[ClimateData] = []
var climate: ClimateData = null
var engine: WeatherEngine = null

var sim_date := {"year": 2026, "month": 1, "day": 1}
var sim_unix := 0.0           # 世界 Unix 时间（已含历法锚定与时区叠加——时间的异质感）
var world_time_offset := 0.0  # 总偏移秒数 = 时间系统偏差 + 城市时区差 + 历法锚定
var time_of_day := 0.0        # 当日 0:00 起经过的秒数（显示帧内派生）
var time_speed := 1.0         # 默认与系统时间同步（m3 批复：1秒过1分钟太吓人）
var current_sky: int = SkyKind.SUNNY
var _last_date_key := ""

var city_menu: PopupMenu
var speed_menu: PopupMenu
var help_dialog: AcceptDialog
var about_dialog: AcceptDialog
var month_value_labels := {}  # 语义键 -> 数值 Label

@onready var background: ColorRect = $Background
@onready var menu_bar: MenuBar = $Margin/Column/TopBar/HBox/MenuBar
@onready var clock_label: Label = $Margin/Column/TopBar/HBox/Clock
@onready var high_value: Label = $Margin/Column/Body/StatsPanel/StatsBox/HighRow/HighValue
@onready var low_value: Label = $Margin/Column/Body/StatsPanel/StatsBox/LowRow/LowValue
@onready var rain_value: Label = $Margin/Column/Body/StatsPanel/StatsBox/RainRow/RainValue
@onready var flavor_label: Label = $Margin/Column/Body/StatsPanel/StatsBox/Flavor
@onready var weather_icon: WeatherIcon = $Margin/Column/Body/CenterPanel/CenterBox/WeatherIcon
@onready var weather_name: Label = $Margin/Column/Body/CenterPanel/CenterBox/WeatherName
@onready var weather_desc: Label = $Margin/Column/Body/CenterPanel/CenterBox/WeatherDesc
@onready var month_title: Label = $Margin/Column/Body/MonthPanel/MonthBox/MonthTitle
@onready var month_rows: VBoxContainer = $Margin/Column/Body/MonthPanel/MonthBox/MonthRows
@onready var status_label: Label = $Margin/Column/StatusBar/StatusLabel


func _ready() -> void:
	SettingsStore.ensure_defaults()
	var env_scale := OS.get_environment("FF_TIME_SCALE")
	if env_scale.is_valid_float():
		time_speed = maxf(env_scale.to_float(), 0.0)
	_build_month_rows()
	_build_menus()
	_build_dialogs()
	background.color = _sky_bg_color()
	_reload_climates()
	_apply_world_time()
	# m3 批复小修：启动时容器可能未随字体度量完成重排（面板排开），延迟强制重排
	await get_tree().process_frame
	await get_tree().process_frame
	$Margin/Column/Body.queue_sort()
	$Margin/Column.queue_sort()
	# 开发辅助：FF_OPEN_EDITOR=1 或命令行追加 `-- --open-editor` 启动时直接打开设置编辑器
	if OS.get_environment("FF_OPEN_EDITOR") == "1" or OS.get_cmdline_user_args().has("--open-editor"):
		_open_settings_editor.call_deferred()
	# 开发辅助：FF_FORCE_SKY=0/1/2 强制天气型（晴/阴/雨），用于测试图标与配色
	var env_sky := OS.get_environment("FF_FORCE_SKY")
	if env_sky.is_valid_int():
		current_sky = clampi(env_sky.to_int(), 0, 2)
		weather_icon.sky = current_sky
		weather_name.text = SKY_NAMES[current_sky]
		weather_desc.text = SKY_DESC[current_sky]
		background.color = _sky_bg_color()


func _process(delta: float) -> void:
	_advance_time(delta * time_speed)
	_update_clock()
	background.color = background.color.lerp(_sky_bg_color(), minf(delta * 2.5, 1.0))


# —— 时间（历法锚定 + 时区叠加：时间的异质感）——

## 解析当前城市的时间上下文：时间系统偏差(分) + 城市时区差(分) + 历法锚定(天)。
## 非法/留空 → UTC/公历（批复口径）。返回也带 id，供状态栏展示。
func _time_context() -> Dictionary:
	var tz_min := 0
	var cal_days := 0
	var times_id := "UTC"
	var cal_id := "公历"
	if climate != null:
		var cd := SettingsStore.load_city(climate.city_name)
		var wid := str(cd.get("world", ""))
		tz_min += int(cd.get("timez", 0))
		if wid != "" and SettingsStore.list_world_ids().has(wid):
			var w := SettingsStore.load_world(wid)
			var want_t := str(cd.get("times", ""))
			var want_c := str(cd.get("calendar", ""))
			for bt in w.get("base_times", []):
				if str(bt.get("id", "")) == want_t:
					tz_min += int(bt.get("offset_minutes", 0))
					times_id = want_t
			for bd in w.get("base_dates", []):
				if str(bd.get("id", "")) == want_c:
					cal_days += int(bd.get("offset_days", 0))
					cal_id = want_c
	return {"tz_min": tz_min, "cal_days": cal_days, "times_id": times_id, "cal_id": cal_id}


## 以现实时刻为锚，应用世界时间偏移（“恢复现在”也走这里）。
func _apply_world_time() -> void:
	var ctx := _time_context()
	world_time_offset = ctx["tz_min"] * 60.0 + ctx["cal_days"] * 86400.0
	sim_unix = Time.get_unix_time_from_system() + world_time_offset
	_last_date_key = ""
	_sync_date_from_clock()
	_update_clock()


func _sync_date_from_clock() -> void:
	var dt := Time.get_datetime_dict_from_unix_time(int(sim_unix))
	var key := "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
	if key != _last_date_key:
		_last_date_key = key
		sim_date = {"year": dt.year, "month": dt.month, "day": dt.day}
		_refresh_day()


func _advance_time(seconds: float) -> void:
	if seconds <= 0.0:
		return
	sim_unix += seconds
	_sync_date_from_clock()


@warning_ignore("integer_division")
func _update_clock() -> void:
	var dt := Time.get_datetime_dict_from_unix_time(int(sim_unix))
	time_of_day = float(dt.hour * 3600 + dt.minute * 60 + dt.second)
	var wd := _weekday(dt.year, dt.month, dt.day)
	clock_label.text = "%04d年%02d月%02d日 %s  %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day,
		WEEKDAY_NAMES[wd], dt.hour, dt.minute, dt.second,
	]


@warning_ignore("integer_division")
static func _weekday(year: int, month: int, day: int) -> int:
	# Sakamoto 算法：返回 0=周日 … 6=周六
	const T := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var y := year - (1 if month < 3 else 0)
	return (y + y / 4 - y / 100 + y / 400 + T[month - 1] + day) % 7


# —— 数据 ——

func _reload_climates() -> void:
	var kept := climate
	climates.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir != null:
		for fname in dir.get_files():
			if fname.get_extension().to_lower() != "csv":
				continue
			var cd := ClimateData.load_from_file(DATA_DIR.path_join(fname))
			if cd != null:
				climates.append(cd)
	climates.sort_custom(func(a, b): return a.city_name.naturalnocasecmp_to(b.city_name) < 0)
	climate = null
	for c in climates:
		if kept != null and c.source_path == kept.source_path:
			climate = c
			break
	if climate == null and not climates.is_empty():
		climate = climates[0]
	engine = _build_engine()
	_rebuild_city_menu()
	_refresh_day()


## 构造天气引擎：接入世界（三层种子/波动参数）与城市（噪点/坐标）上下文。
func _build_engine() -> WeatherEngine:
	if climate == null:
		return null
	var city_data := SettingsStore.load_city(climate.city_name)
	var wid := str(city_data.get("world", ""))
	var world_data := {}
	if wid != "" and SettingsStore.list_world_ids().has(wid):
		world_data = SettingsStore.load_world(wid)
	return WeatherEngine.new(climate, wid, world_data, city_data)


# —— 界面刷新 ——

func _refresh_day() -> void:
	_refresh_month_panel()
	if climate == null or engine == null:
		current_sky = SkyKind.SUNNY
		weather_icon.sky = current_sky
		weather_name.text = "暂无数据"
		weather_desc.text = "把逐月气候 CSV 放进 Climate/ 目录，再从菜单重新加载"
		high_value.text = "—"
		low_value.text = "—"
		rain_value.text = "—"
		flavor_label.text = ""
		_update_status()
		return
	var rep := engine.day_report(sim_date.year, sim_date.month, sim_date.day)
	current_sky = rep["sky"]
	weather_icon.sky = current_sky
	var is_snow: bool = rep.get("snow", false)
	weather_name.text = "雪" if is_snow else SKY_NAMES[current_sky]
	weather_desc.text = "低温降水，落地成雪" if is_snow else SKY_DESC[current_sky]
	high_value.text = "%.0f°C" % rep["high"]
	low_value.text = "%.0f°C" % rep["low"]
	rain_value.text = "%d%%" % roundi(rep["rain_prob"] * 100.0)
	if current_sky == SkyKind.RAINY:
		flavor_label.text = "种子 %s · 今日降水 %.1f mm%s · 湿度 %.0f%%" % [
			rep["seed_key"], rep.get("precip_mm", 0.0),
			"（雪）" if is_snow else "", rep.get("humidity", 0.0),
		]
	else:
		flavor_label.text = "种子 %s · 日日照 %.1f 小时 · 湿度 %.0f%%" % [
			rep["seed_key"], rep["sun_daily"], rep.get("humidity", 0.0),
		]
	_update_status()


func _refresh_month_panel() -> void:
	month_title.text = "%d 月气候背景" % sim_date.month
	for row in MONTH_ROWS:
		var label: Label = month_value_labels.get(row[0], null)
		if label == null:
			continue
		var v := NAN
		if climate != null:
			v = climate.month_value(row[0], sim_date.month)
		var fmt: String = row[2]
		label.text = "—" if is_nan(v) else (fmt % v)


func _update_status() -> void:
	if climate == null:
		status_label.text = "未加载气候数据 · 期望位置 Climate/*.csv"
		return
	var extra := ""
	if climate.extra_keys.size() > 0:
		extra = " · 另有 %d 个未映射键已原样保留" % climate.extra_keys.size()
	var skipped := ""
	if climate.skipped_rows > 0:
		skipped = " · 跳过 %d 行" % climate.skipped_rows
	# 城市基础数据（Cities/<ID>.json）：坐标、海拔、所属世界、历法、时间系统
	var cd := SettingsStore.load_city(climate.city_name)
	var ctx := _time_context()
	var world_shown := "—"
	if str(cd.world) != "":
		var wd := SettingsStore.world_display_name(str(cd.world))
		world_shown = str(cd.world) if wd.is_empty() else wd
	status_label.text = "城市：%s（%.1f°, %.1f°, %.0fm · 世界 %s · 历法 %s · 时间系统 %s · 时区 %+d 分）　·　数据：%s　·　机制：三层种子 + 月度确定性生成（雨日锁定/降水对账/距平零和/露点中介）%s%s" % [
		_city_label(climate.city_name), float(cd.long), float(cd.lati), float(cd.alti),
		world_shown, ctx["cal_id"], ctx["times_id"], int(cd.timez),
		climate.source_path.get_file(), extra, skipped,
	]


func _sky_bg_color() -> Color:
	var base: Color = SKY_BG[current_sky]
	var hh := time_of_day / 3600.0
	var dim := 1.0
	if hh < 5.0 or hh >= 21.0:
		dim = 0.38
	elif hh < 7.0:
		dim = lerpf(0.38, 1.0, (hh - 5.0) / 2.0)
	elif hh >= 19.0:
		dim = lerpf(1.0, 0.38, (hh - 19.0) / 2.0)
	return Color(base.r * dim, base.g * dim, base.b * dim)


func _fmt(v: float, fmt: String) -> String:
	return "—" if is_nan(v) else (fmt % v)


# —— 菜单 ——

func _build_menus() -> void:
	# MenuBar 的菜单 = 直接把 PopupMenu 挂为子节点，显示标题取节点名
	var m := PopupMenu.new()
	m.name = "菜单"
	menu_bar.add_child(m)

	city_menu = PopupMenu.new()
	city_menu.name = "CityMenu"
	m.add_child(city_menu)
	m.add_submenu_item("城市", "CityMenu")
	city_menu.index_pressed.connect(_on_city_selected)

	speed_menu = PopupMenu.new()
	speed_menu.name = "SpeedMenu"
	m.add_child(speed_menu)
	m.add_submenu_item("时间流速", "SpeedMenu")
	speed_menu.index_pressed.connect(_on_speed_selected)

	m.add_item("重新加载气候数据", ID_RELOAD)
	m.add_item("跳到下一日", ID_NEXT_DAY)
	m.add_item("恢复现在", ID_RESUME_NOW)
	m.add_item("设置编辑器", ID_EDITOR)
	m.add_separator()
	m.add_item("退出", ID_QUIT)
	m.id_pressed.connect(_on_main_menu)

	var h := PopupMenu.new()
	h.name = "帮助"
	menu_bar.add_child(h)
	h.add_item("使用说明", ID_HELP_GUIDE)
	h.add_item("关于", ID_HELP_ABOUT)
	h.id_pressed.connect(_on_help_menu)

	_rebuild_speed_menu()


func _rebuild_city_menu() -> void:
	if city_menu == null:
		return
	city_menu.clear()
	if climates.is_empty():
		city_menu.add_item("（Climate/ 下没有找到 CSV）", 0)
		city_menu.set_item_disabled(0, true)
		return
	for i in climates.size():
		city_menu.add_item(_city_label(climates[i].city_name), i)
		city_menu.set_item_checked(i, climates[i] == climate)


func _rebuild_speed_menu() -> void:
	if speed_menu == null:
		return
	speed_menu.clear()
	for i in TIME_SPEEDS.size():
		speed_menu.add_item(TIME_SPEEDS[i][0], i)
		speed_menu.set_item_checked(i, is_equal_approx(time_speed, TIME_SPEEDS[i][1]))


func _on_city_selected(index: int) -> void:
	if index < 0 or index >= climates.size():
		return
	climate = climates[index]
	engine = WeatherEngine.new(climate)
	_rebuild_city_menu()
	_refresh_day()


func _on_speed_selected(index: int) -> void:
	if index < 0 or index >= TIME_SPEEDS.size():
		return
	time_speed = TIME_SPEEDS[index][1]
	_rebuild_speed_menu()


func _on_main_menu(id: int) -> void:
	match id:
		ID_RELOAD:
			_reload_climates()
		ID_NEXT_DAY:
			sim_unix += 86400.0
			_sync_date_from_clock()
			_update_clock()
		ID_RESUME_NOW:
			_apply_world_time()
			_update_clock()
		ID_EDITOR:
			_open_settings_editor()
		ID_QUIT:
			get_tree().quit()


var editor_process_pid: int = 0


## 打开设置编辑器（THX 系列惯例：独立进程启动，整窗即编辑器，
## 可拖动/缩放/关闭，与游戏主程序互不影响）。
func _open_settings_editor() -> void:
	if editor_process_pid > 0 and OS.is_process_running(editor_process_pid):
		status_label.text = "设置编辑器已在运行（独立窗口）"
		return
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	editor_process_pid = OS.create_process(exe, ["--path", proj, "res://scenes/editor.tscn"])
	if editor_process_pid <= 0:
		editor_process_pid = 0
		status_label.text = "设置编辑器启动失败"
	else:
		status_label.text = "已启动设置编辑器（独立窗口）"


## 主程序退出时主动击杀自己拉起的编辑器进程——
## 是“主程序执行的返回动作”，而不是靠子窗口关系连带关闭（m2.1 批复）。
func _kill_editor_process() -> void:
	if editor_process_pid > 0 and OS.is_process_running(editor_process_pid):
		OS.kill(editor_process_pid)
	editor_process_pid = 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_kill_editor_process()
		get_tree().quit()


func _exit_tree() -> void:
	_kill_editor_process()


## 城市显示名：本地化 zh.yaml 优先，缺失回退文件名 capitalize。
func _city_label(id: String) -> String:
	var n := SettingsStore.city_display_name(id)
	return n if not n.is_empty() else id.capitalize()


func _on_help_menu(id: int) -> void:
	match id:
		ID_HELP_GUIDE:
			help_dialog.popup_centered()
		ID_HELP_ABOUT:
			about_dialog.popup_centered()


# —— 面板构建 ——

func _build_month_rows() -> void:
	for row in MONTH_ROWS:
		var hbox := HBoxContainer.new()
		var key := Label.new()
		key.text = row[1]
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.add_theme_color_override("font_color", Color(0.60, 0.67, 0.78))
		var val := Label.new()
		val.text = "—"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_color_override("font_color", Color(0.85, 0.90, 0.97))
		hbox.add_child(key)
		hbox.add_child(val)
		month_rows.add_child(hbox)
		month_value_labels[row[0]] = val


func _build_dialogs() -> void:
	about_dialog = AcceptDialog.new()
	about_dialog.title = "关于 · 幻想气象局"
	about_dialog.dialog_text = "幻想气象局 FictForecast\n\n为幻想世界提供一份可靠的天气预报——用于创作，以及向同好炫耀。\n\n版本 0.0.1classic\n月份数据读取 · 日照加权随机 · 日期种子 · 设置编辑器骨架\n（随机评分筛选尚未实装）"
	help_dialog = AcceptDialog.new()
	help_dialog.title = "使用说明"
	help_dialog.dialog_text = """【数据】
Climate/ 目录下的每个 CSV 视为一座城市。逐行一个月：12 个月值 + 键名（首列或末列均可，自动识别）+ 注释列（可省略）；月份表头行会被自动跳过。
已支持键名：平均日高温 / 平均日低温 / 平均日均温 / 平均降水量 / 平均日照时长 / 平均湿度 / 气象记录高温 / 气象记录低温 / 平均降水天数 / 平均降雪天数。其他键（如“气候表现-*”）会被原样保留，供未来扩展。

【当前机制】
· 随机种子来自日期：同一天永远生成同一份天气。
· 晴/阴/雨按当月（跨月 15 天加权）的平均日照时长加权抽取。
· 高低温在月均值上叠加确定性扰动，并被当月气象记录钳制。
· 顶栏“菜单”里可切换城市、调整时间流速、跳到下一日。

【尚未实装】
随机评分筛选、天气型惯性（马尔可夫）、气象事件（台风/寒潮）、世界级气象（水晶雨等）、自定义日历。"""
	add_child(about_dialog)
	add_child(help_dialog)
