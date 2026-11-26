extends Control
## 幻想气象局 · 主界面控制器
##
## 读取 Climate/*.csv 的逐月气候数据；模拟时钟按城市的时间系统（历法锚定 + 时区）显示；
## 每天的天气由 WeatherEngine 按世界三层种子确定性生成（同一天永远同一份天气）。
## 随机评分筛选机制尚未实装（月度预生成即其前置结构）。
##
## 软件偏好（偏好城市 / 界面语言 / 城市名称语言 / 界面背景不透明度）由本脚本持有并写盘，
## 「偏好设置」窗口（嵌入主窗口的子窗口）只负责改数据。
## 界面文字：场景里的静态文字由 UiText.install() 登记，代码里的文字走 UiText.t()/f()
## （译文在 Localization/<语言>.yaml 的 ui 组，键 = 中文原文）。
##
## 开发辅助环境变量：FF_TIME_SCALE（时间流速）、FF_FORCE_SKY（强制天气型）、
## FF_OPEN_EDITOR（启动即开编辑器）、FF_PREFS_FILE（重定向偏好文件，测试时不污染真实偏好）。

const DATA_DIR := "res://Climate"

const ID_RELOAD := 100
const ID_NEXT_DAY := 101
const ID_EDITOR := 103
const ID_RESUME_NOW := 104
const ID_PREFS := 105
const ID_CALENDAR := 106
const ID_QUIT := 102
const ID_HELP_GUIDE := 200
const ID_HELP_ABOUT := 201

# 顶栏菜单序号
const MENU_MAIN := 0
const MENU_HELP := 1

# 主菜单项序号（_build_menus 里的添加顺序）
const MI_CITY := 0
const MI_SPEED := 1
const MI_RELOAD := 2
const MI_NEXT_DAY := 3
const MI_RESUME := 4
const MI_CALENDAR := 5
const MI_EDITOR := 6
const MI_PREFS := 7
const MI_QUIT := 9

# 「界面背景不透明度」作用的五个面板
const PANEL_PATHS := [
	"Margin/Column/TopBar",
	"Margin/Column/Body/StatsPanel",
	"Margin/Column/Body/CenterPanel",
	"Margin/Column/Body/MonthPanel",
	"Margin/Column/StatusBar",
]

# 「使用说明」对话框的最小尺寸（宽固定，高随换行后的文字自适应）
const HELP_DIALOG_WIDTH := Vector2i(680, 0)

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

# 使用说明 / 关于：逐段可翻译（界面语言的 ui 组以中文原文为键）
const HELP_PARAS: Array = [
	"【数据】",
	"Climate/ 目录下的每个 CSV 视为一座城市。逐行一个月：12 个月值 + 键名（首列或末列均可，自动识别）+ 注释列（可省略）；月份表头行会被自动跳过。",
	"已支持键名：平均日高温 / 平均日低温 / 平均日均温 / 平均降水量 / 平均日照时长 / 平均湿度 / 气象记录高温 / 气象记录低温 / 平均降水天数 / 平均降雪天数。其他键（如“气候表现-*”）会被原样保留，供未来扩展。",
	"",
	"【当前机制】",
	"· 随机种子分三层（年/月/日），来自城市所属的世界；同一天永远生成同一份天气。",
	"· 雨日数量按当月「平均降水天数」锁定；非雨日按日照时长分晴/阴；月降水量与月均温向气候表对账（强度见世界设置）。",
	"· 高低温在月均值上叠加确定性波动，并被当月气象记录钳制。",
	"· 顶栏“菜单”里可切换城市、调整时间流速、跳到下一日、恢复现在、打开设置编辑器与偏好设置。",
	"",
	"【尚未实装】",
	"随机评分筛选、气候现象（台风/寒潮等）、世界级气象（水晶雨等）、自定义历法规则。",
]
const ABOUT_PARAS: Array = [
	"幻想气象局 FictForecast",
	"",
	"为幻想世界提供一份可靠的天气预报——用于创作，以及向同好炫耀。",
	"",
	"版本 %s",
	"月度确定性生成 · 三层种子 · 图表随机柏林面 · 世界时钟 · 设置编辑器",
	"（随机评分筛选尚未实装）",
]

var climates: Array[ClimateData] = []
var climate: ClimateData = null
var engine: WeatherEngine = null

var sim_date := {"year": 2026, "month": 1, "day": 1}
var sim_unix := 0.0           # 世界 Unix 时间（已含历法锚定与时区叠加——时间的异质感）
var world_time_offset := 0.0  # 总偏移秒数 = 时间系统偏差 + 城市时区差 + 历法锚定
var time_of_day := 0.0        # 当日 0:00 起经过的秒数（显示帧内派生）
var time_speed := 1.0         # 默认与系统时间同步（m3 批复：1秒过1分钟太吓人）
var _time_ready := false      # _apply_world_time() 跑过之后 sim_unix 才有意义
var current_sky: int = SkyKind.SUNNY
var _last_date_key := ""

var prefs: Dictionary = {}            # 软件偏好（SettingsStore.PREFS_DEFAULTS 骨架）
var _prefs_save_timer: Timer          # 偏好改动防抖写盘

var main_menu: PopupMenu
var help_menu: PopupMenu
var city_menu: PopupMenu
var speed_menu: PopupMenu
var help_dialog: AcceptDialog
var about_dialog: AcceptDialog
var quit_dialog: ConfirmationDialog   # 编辑器仍在运行时的退出确认
var month_value_labels := {}  # 语义键 -> 数值 Label

var editor_process_pid: int = 0

@onready var background: ColorRect = $Background
@onready var prefs_panel: Window = $Preferences
@onready var calendar_panel: Window = $Calendar
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
	prefs = SettingsStore.load_preferences()
	# 界面语言：先登记场景里的静态文字（必须在任何代码改写它们之前），再换成当前语言
	UiText.set_language(str(prefs.get("ui_lang", "zh")))
	UiText.install(self, true)
	SettingsStore.apply_ui_font(str(prefs.get("ui_lang", "zh")))
	# 关主窗口先走 _request_quit（编辑器还开着时要问一句），不再由场景树直接退出
	get_tree().auto_accept_quit = false
	var env_scale := OS.get_environment("FF_TIME_SCALE")
	if env_scale.is_valid_float():
		time_speed = maxf(env_scale.to_float(), 0.0)
	_build_month_rows()
	_build_menus()
	_build_dialogs()
	background.color = _sky_bg_color()
	_reload_climates()
	_apply_world_time()
	_apply_panel_opacity()
	_apply_name_fonts()
	# 偏好改动防抖写盘（拖动不透明度滑条时不逐帧写文件）
	_prefs_save_timer = Timer.new()
	_prefs_save_timer.one_shot = true
	_prefs_save_timer.wait_time = 0.5
	_prefs_save_timer.timeout.connect(_save_prefs)
	add_child(_prefs_save_timer)
	prefs_panel.prefs = prefs
	prefs_panel.preference_changed.connect(_on_preference_changed)
	calendar_panel.date_picked.connect(_on_calendar_day_picked)
	calendar_panel.now_requested.connect(func() -> void:
		_apply_world_time()
		_update_clock())
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
		weather_name.text = UiText.t(SKY_NAMES[current_sky])
		weather_desc.text = UiText.t(SKY_DESC[current_sky])
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
	_time_ready = true
	_last_date_key = ""
	_sync_date_from_clock()
	_update_clock()


## 城市的时间系统变了（切换城市 / 重新加载）：换算时钟偏移，但保持“同一时刻”——
## 偏移的差值从 sim_unix 里增减，已经跳过去的天数不会丢。
func _refresh_time_offset() -> void:
	var ctx := _time_context()
	var offset: float = ctx["tz_min"] * 60.0 + ctx["cal_days"] * 86400.0
	sim_unix += offset - world_time_offset
	world_time_offset = offset
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
	clock_label.text = UiText.f("%04d年%02d月%02d日 %s  %02d:%02d:%02d", [
		dt.year, dt.month, dt.day,
		UiText.t(WEEKDAY_NAMES[wd]), dt.hour, dt.minute, dt.second,
	])


@warning_ignore("integer_division")
static func _weekday(year: int, month: int, day: int) -> int:
	# Sakamoto 算法：返回 0=周日 … 6=周六
	const T := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var y := year - (1 if month < 3 else 0)
	return (y + y / 4 - y / 100 + y / 400 + T[month - 1] + day) % 7


# —— 数据 ——

func _reload_climates() -> void:
	var kept := climate
	SettingsStore.invalidate_localization_cache()  # 编辑器是独立进程，可能改过本地化文件
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
	if climate == null:
		climate = _preferred_climate()
	engine = _build_engine()
	_remember_last_city()
	_rebuild_city_menu()
	if _time_ready:
		_refresh_time_offset()
	_refresh_day()


func _find_climate(city_id: String) -> ClimateData:
	for c in climates:
		if c.city_name == city_id:
			return c
	return null


## 启动时展示哪座城市：偏好城市 → 上次展示的城市 → 列表第一座（《幻想气象局.md》软件系统设置）。
func _preferred_climate() -> ClimateData:
	var want := _find_climate(str(prefs.get("default_city", "")))
	if want == null:
		want = _find_climate(str(prefs.get("last_city", "")))
	if want == null and not climates.is_empty():
		want = climates[0]
	return want


## 切换当前城市：重建引擎（带世界/城市上下文），并按新城市的时间系统换算时钟。
func _activate_city(c: ClimateData) -> void:
	climate = c
	engine = _build_engine()
	_remember_last_city()
	_rebuild_city_menu()
	_refresh_time_offset()
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
		weather_icon.snow = false
		weather_name.text = UiText.t("暂无数据")
		weather_desc.text = UiText.t("把逐月气候 CSV 放进 Climate/ 目录，再从菜单重新加载")
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
	weather_icon.snow = is_snow
	weather_name.text = UiText.t("雪") if is_snow else UiText.t(SKY_NAMES[current_sky])
	weather_desc.text = UiText.t("低温降水，落地成雪") if is_snow else UiText.t(SKY_DESC[current_sky])
	high_value.text = "%.0f°C" % rep["high"]
	low_value.text = "%.0f°C" % rep["low"]
	rain_value.text = "%d%%" % roundi(rep["rain_prob"] * 100.0)
	var common := "种子 %s · 日日照 %.1f 小时 · 风 %.1f m/s · 湿度 %.0f%%"
	if current_sky == SkyKind.RAINY:
		flavor_label.text = UiText.f("种子 %s · 今日降水 %.1f mm%s · 风 %.1f m/s · 湿度 %.0f%%", [
			rep["seed_key"], rep.get("precip_mm", 0.0),
			UiText.t("（雪）") if is_snow else "", rep.get("wind", 0.0), rep.get("humidity", 0.0),
		])
	else:
		flavor_label.text = UiText.f(common, [
			rep["seed_key"], rep["sun_daily"], rep.get("wind", 0.0), rep.get("humidity", 0.0),
		])
	_update_status()


func _refresh_month_panel() -> void:
	month_title.text = UiText.f("%d 月气候背景", [sim_date.month])
	for row in MONTH_ROWS:
		var label: Label = month_value_labels.get(row[0], null)
		if label == null:
			continue
		var v := NAN
		if climate != null:
			v = climate.month_value(row[0], sim_date.month)
		var fmt: String = row[2]
		label.text = "—" if is_nan(v) else (UiText.t(fmt) % v)  # 单位（“%.1f 天”这类）也走翻译


func _update_status() -> void:
	if climate == null:
		status_label.text = UiText.t("未加载气候数据 · 期望位置 Climate/*.csv")
		return
	var extra := ""
	if climate.extra_keys.size() > 0:
		extra = " " + UiText.f("· 另有 %d 个未映射键已原样保留", [climate.extra_keys.size()])
	var skipped := ""
	if climate.skipped_rows > 0:
		skipped = " " + UiText.f("· 跳过 %d 行", [climate.skipped_rows])
	# 城市基础数据（Cities/<ID>.json）：坐标、海拔、所属世界、历法、时间系统
	var cd := SettingsStore.load_city(climate.city_name)
	var ctx := _time_context()
	var world_shown := "—"
	if str(cd.world) != "":
		var wd := SettingsStore.world_display_name(str(cd.world))
		world_shown = str(cd.world) if wd.is_empty() else wd
	status_label.text = UiText.f("城市：%s（%.1f°, %.1f°, %.0fm · 世界 %s · 历法 %s · 时间系统 %s · 时区 %+d 分）　·　数据：%s　·　机制：三层种子 + 月度确定性生成（雨日锁定/降水对账/距平零和/露点中介）%s%s", [
		_city_label(climate.city_name), float(cd.long), float(cd.lati), float(cd.alti),
		world_shown, UiText.t(str(ctx["cal_id"])), UiText.t(str(ctx["times_id"])), int(cd.timez),
		climate.source_path.get_file(), extra, skipped,
	])


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


# —— 菜单 ——

func _build_menus() -> void:
	# MenuBar 的菜单 = 直接把 PopupMenu 挂为子节点，显示标题另设（不用节点名：节点名保持稳定）
	main_menu = PopupMenu.new()
	main_menu.name = "MainMenu"
	menu_bar.add_child(main_menu)

	city_menu = PopupMenu.new()
	city_menu.name = "CityMenu"
	main_menu.add_child(city_menu)
	main_menu.add_submenu_item("", "CityMenu")
	city_menu.index_pressed.connect(_on_city_selected)

	speed_menu = PopupMenu.new()
	speed_menu.name = "SpeedMenu"
	main_menu.add_child(speed_menu)
	main_menu.add_submenu_item("", "SpeedMenu")
	speed_menu.index_pressed.connect(_on_speed_selected)

	main_menu.add_item("", ID_RELOAD)
	main_menu.add_item("", ID_NEXT_DAY)
	main_menu.add_item("", ID_RESUME_NOW)
	main_menu.add_item("", ID_CALENDAR)
	main_menu.add_item("", ID_EDITOR)
	main_menu.add_item("", ID_PREFS)
	main_menu.add_separator()
	main_menu.add_item("", ID_QUIT)
	main_menu.id_pressed.connect(_on_main_menu)

	help_menu = PopupMenu.new()
	help_menu.name = "HelpMenu"
	menu_bar.add_child(help_menu)
	help_menu.add_item("", ID_HELP_GUIDE)
	help_menu.add_item("", ID_HELP_ABOUT)
	help_menu.id_pressed.connect(_on_help_menu)
	_fill_menu_texts()


## 菜单文字（切换界面语言时重填；项的序号固定，见 MI_* 常量）。
func _fill_menu_texts() -> void:
	menu_bar.set_menu_title(MENU_MAIN, UiText.t("菜单"))
	menu_bar.set_menu_title(MENU_HELP, UiText.t("帮助"))
	main_menu.set_item_text(MI_CITY, UiText.t("城市"))
	main_menu.set_item_text(MI_SPEED, UiText.t("时间流速"))
	main_menu.set_item_text(MI_RELOAD, UiText.t("重新加载气候数据"))
	main_menu.set_item_text(MI_NEXT_DAY, UiText.t("跳到下一日"))
	main_menu.set_item_text(MI_RESUME, UiText.t("恢复现在"))
	main_menu.set_item_text(MI_CALENDAR, UiText.t("日历…"))
	main_menu.set_item_text(MI_EDITOR, UiText.t("设置编辑器"))
	main_menu.set_item_text(MI_PREFS, UiText.t("偏好设置…"))
	main_menu.set_item_text(MI_QUIT, UiText.t("退出"))
	help_menu.set_item_text(0, UiText.t("使用说明"))
	help_menu.set_item_text(1, UiText.t("关于"))
	_rebuild_speed_menu()  # m3.8 重写时弄丢的这行：不补上的话时间流速子菜单一直是空的


func _rebuild_city_menu() -> void:
	if city_menu == null:
		return
	city_menu.clear()
	if climates.is_empty():
		city_menu.add_item(UiText.t("（Climate/ 下没有找到 CSV）"), 0)
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
		speed_menu.add_item(UiText.t(TIME_SPEEDS[i][0]), i)
		speed_menu.set_item_checked(i, is_equal_approx(time_speed, TIME_SPEEDS[i][1]))


func _on_city_selected(index: int) -> void:
	if index < 0 or index >= climates.size():
		return
	_activate_city(climates[index])


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
		ID_CALENDAR:
			calendar_panel.open(sim_date.duplicate())
		ID_EDITOR:
			_open_settings_editor()
		ID_PREFS:
			_open_preferences()
		ID_QUIT:
			_request_quit()


func _on_help_menu(id: int) -> void:
	match id:
		ID_HELP_GUIDE:
			help_dialog.popup_centered(HELP_DIALOG_WIDTH)
		ID_HELP_ABOUT:
			about_dialog.popup_centered()


# —— 设置编辑器（THX 惯例：独立进程）与退出流程 ——

func _editor_running() -> bool:
	return editor_process_pid > 0 and OS.is_process_running(editor_process_pid)


## 打开设置编辑器（THX 系列惯例：独立进程启动，整窗即编辑器，
## 可拖动/缩放/关闭，与游戏主程序互不影响）。
func _open_settings_editor() -> void:
	if _editor_running():
		status_label.text = UiText.t("设置编辑器已在运行（独立窗口）")
		return
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	editor_process_pid = OS.create_process(exe, ["--path", proj, "res://scenes/editor.tscn"])
	if editor_process_pid <= 0:
		editor_process_pid = 0
		status_label.text = UiText.t("设置编辑器启动失败")
	else:
		status_label.text = UiText.t("已启动设置编辑器（独立窗口）")


## 主程序退出时主动击杀自己拉起的编辑器进程——
## 是“主程序执行的返回动作”，而不是靠子窗口关系连带关闭（m2.1 批复）。
## m3.8 批复：强杀前先确认。编辑器把未保存的改动持续存成草稿（user://editor_drafts），
## 下次启动时询问是否恢复——所以强杀最多丢掉半秒内的输入。
func _request_quit() -> void:
	if _editor_running():
		if not quit_dialog.visible:
			quit_dialog.popup_centered()
		return
	_quit_now()


func _quit_now() -> void:
	_kill_editor_process()
	get_tree().quit()


func _kill_editor_process() -> void:
	if _editor_running():
		OS.kill(editor_process_pid)
	editor_process_pid = 0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_request_quit()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_sync_ui_language_from_disk()


## 设置编辑器是独立进程，可能在「本地化」页把界面语言改掉了：回到主窗口时对齐一次。
func _sync_ui_language_from_disk() -> void:
	if prefs.is_empty():
		return
	var lang := str(SettingsStore.load_preferences().get("ui_lang", "zh"))
	if lang != UiText.language():
		prefs["ui_lang"] = lang
		_apply_ui_language()
		_save_prefs()


func _exit_tree() -> void:
	_kill_editor_process()
	_save_prefs()  # 防抖窗口内的改动（比如滑条刚拖完就关窗）不丢


## 城市显示名：按「城市名称语言」读 Localization/<语言>.yaml，缺失回退 zh，再回退文件名。
## 「城市副标题语言」留空以外时在主名后面补小字副名（同名 / 同语言 / 缺译文时不补）。
func _city_label(id: String) -> String:
	var n := SettingsStore.city_display_name(id, str(prefs.get("city_name_lang", "zh")))
	if n.is_empty():
		n = id.capitalize()
	var sub := _city_sub_label(id, n)
	return n if sub.is_empty() else "%s %s" % [n, sub]


func _city_sub_label(id: String, main_name: String) -> String:
	var lang := str(prefs.get("city_sub_lang", "en"))
	if lang.is_empty() or lang == str(prefs.get("city_name_lang", "zh")):
		return ""
	var s := SettingsStore.city_display_name(id, lang)
	return s if not s.is_empty() and s != main_name else ""


# —— 偏好设置（非独立窗口：嵌入主窗口的子窗口 scenes/preferences.tscn）——

func _open_preferences() -> void:
	prefs_panel.open()


## 日历跳转：换算目标日期与现实锚定日期的秒差加到世界时钟上——当日的时刻（几点几分）保持不变。
func _on_calendar_day_picked(year: int, month: int, day: int) -> void:
	var cur := Time.get_unix_time_from_datetime_dict({
		"year": int(sim_date.year), "month": int(sim_date.month), "day": int(sim_date.day),
		"hour": 0, "minute": 0, "second": 0,
	})
	var tgt := Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": 0, "minute": 0, "second": 0,
	})
	sim_unix += float(tgt - cur)
	_sync_date_from_clock()
	_update_clock()


func _on_preference_changed(key: String) -> void:
	match key:
		"default_city":
			# 选了偏好城市就切过去看——即时反馈；留空则只更新菜单文字
			var c := _find_climate(str(prefs.get("default_city", "")))
			if c != null and c != climate:
				_activate_city(c)
			else:
				_rebuild_city_menu()
			_save_prefs()
		"ui_lang":
			SettingsStore.invalidate_localization_cache()
			_apply_ui_language()
			_save_prefs()
		"city_name_lang":
			SettingsStore.invalidate_localization_cache()
			_apply_name_fonts()
			_rebuild_city_menu()
			_refresh_day()
			_save_prefs()
		"city_sub_lang":
			SettingsStore.invalidate_localization_cache()
			_rebuild_city_menu()
			_refresh_day()
			_save_prefs()
		"panel_opacity":
			_apply_panel_opacity()
			_prefs_save_timer.start()


## 切换界面语言：静态文字整体替换 + 动态文字逐处重画。
func _apply_ui_language() -> void:
	var lang := str(prefs.get("ui_lang", "zh"))
	UiText.set_language(lang)
	UiText.install(self)
	SettingsStore.apply_ui_font(lang)
	_fill_menu_texts()
	_rebuild_speed_menu()
	_rebuild_city_menu()
	_build_month_rows()
	_update_clock()
	_refresh_month_panel()
	_refresh_day()
	_apply_dialog_texts()
	_apply_name_fonts()
	if prefs_panel != null:
		prefs_panel._sync()


## 城市名称语言带字体时（虚构语言），显示城市名的几处改用该字体；
## 字体里没有的字自动回退到界面默认字体。
func _apply_name_fonts() -> void:
	var f := SettingsStore.language_font(str(prefs.get("city_name_lang", "zh")))
	for n in [city_menu, status_label]:
		if n == null:
			continue
		if f != null:
			n.add_theme_font_override("font", f)   # PopupMenu 是 Window、状态栏是 Control：两者都有这个方法
		else:
			n.remove_theme_font_override("font")


## 界面背景不透明度：五个面板的底色 alpha 直接取偏好值（1 = 完全不透明）。
func _apply_panel_opacity() -> void:
	var a := clampf(float(prefs.get("panel_opacity", 0.9)), 0.0, 1.0)
	for path in PANEL_PATHS:
		var pc: PanelContainer = get_node(path)
		if not pc.has_meta("base_style"):
			pc.set_meta("base_style", pc.get_theme_stylebox("panel").duplicate())
		var sb: StyleBoxFlat = (pc.get_meta("base_style") as StyleBoxFlat).duplicate()
		sb.bg_color.a = a
		pc.add_theme_stylebox_override("panel", sb)


func _remember_last_city() -> void:
	var id := climate.city_name if climate != null else ""
	if str(prefs.get("last_city", "")) != id:
		prefs["last_city"] = id
		_save_prefs()


func _save_prefs() -> void:
	if prefs.is_empty():
		return
	if _prefs_save_timer != null and not _prefs_save_timer.is_stopped():
		_prefs_save_timer.stop()
	var err := SettingsStore.save_preferences(prefs)
	if err != OK:
		push_warning("偏好写盘失败（%d）：%s" % [err, SettingsStore.prefs_path()])


# —— 面板构建 ——

func _build_month_rows() -> void:
	for c in month_rows.get_children():
		month_rows.remove_child(c)
		c.queue_free()
	month_value_labels.clear()
	for row in MONTH_ROWS:
		var hbox := HBoxContainer.new()
		var key := Label.new()
		key.text = UiText.t(row[1])
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
	help_dialog = AcceptDialog.new()
	# 说明文字很长：限定 680px 宽并自动换行。对话框嵌在主窗口里，宽过主窗口的话右侧会被裁掉。
	help_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.confirmed.connect(_quit_now)
	for d in [about_dialog, help_dialog, quit_dialog]:
		add_child(d)
	_apply_dialog_texts()


## 三个对话框的文字（切换界面语言时重设）。
func _apply_dialog_texts() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	about_dialog.title = UiText.t("关于 · 幻想气象局")
	about_dialog.dialog_text = _join(ABOUT_PARAS, version)
	about_dialog.ok_button_text = UiText.t("确定")
	help_dialog.title = UiText.t("使用说明")
	help_dialog.dialog_text = _join(HELP_PARAS, version)
	help_dialog.ok_button_text = UiText.t("确定")
	quit_dialog.title = UiText.t("编辑器仍在运行")
	quit_dialog.dialog_text = UiText.t("设置编辑器还开着。退出主程序会一并关闭它；其中未保存的改动会保留为草稿，下次打开编辑器时可以恢复。")
	quit_dialog.ok_button_text = UiText.t("仍要退出")
	quit_dialog.get_cancel_button().text = UiText.t("返回")


func _join(paras: Array, version: String) -> String:
	var out := PackedStringArray()
	for p in paras:
		out.append(UiText.f(p, [version]) if p == "版本 %s" else UiText.t(str(p)))
	return "\n".join(out)
