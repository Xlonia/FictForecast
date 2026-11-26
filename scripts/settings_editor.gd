extends Control
## 设置编辑器：按《幻想气象局.md》的「世界设置 / 城市设置 / 自定义语言」骨架，
## 以表单方式修改 JSON（世界/城市/语言定义）与 YAML（本地化）。
##
## 运行形态与 THX 系列一致：本场景根节点是普通 Control，由批处理/主程序以
## **独立进程**启动（godot --path <工程> res://scenes/editor.tscn），
## 整窗即编辑器，可拖动/缩放/关闭，与游戏主程序互不影响；
## 主程序退出前会先确认，再击杀自己拉起的编辑器进程。
##
## 文档与草稿（m3 草稿快照 + m3.8 批复）：
##   · 每份文档打开时记一份磁盘快照；内容与快照不同 = 未保存改动。
##   · 切换选择时，未保存的改动进“暂存区”而不是丢弃；切回来原样还在；「保存全部」一并落盘。
##   · 未保存的改动每半秒落到 user://editor_drafts/（开发期可用 FF_DRAFT_DIR 重定向）；
##     被强杀 / 崩溃后，下次启动询问是否恢复。
##   · 「地图」页给城市定点是“点击即存”，并一并保存它所依赖的世界地图配置。
## 城市坐标锚定（m3.8 批复）：城市默认锚定参考图上的位置（anchor = map），
## 调整 0° 经线 / 赤道 / 投影时不跑位，经纬度由地图配置换算；输入框旁的「经纬度锁定」
## 可以改回“以经纬度为准”（anchor = latlong）。
## 界面语言跟随软件偏好（UiText）；「本地化」页可把界面语言切到正在编辑的语言。

const ANCHOR_LATLONG := "latlong"
const ANCHOR_MAP := "map"
const FMT_ID_NAME := "%s（%s）"

# 地图画布配色
const MAP_BLANK_OUT := Color(0.045, 0.06, 0.095)   # 参考图上下缘之外
const MAP_BLANK_IN := Color(0.10, 0.12, 0.17)      # 图带里没有参考图的经度（空位）
const MAP_GRID := Color(1, 1, 1, 0.32)
const MAP_HANDLE := Color(1.0, 0.72, 0.3)          # 0° 经线 / 赤道 / 当前城市
const MAP_CITY := Color(0.55, 0.8, 1.0)            # 锚定在图上位置的城市
const MAP_LOCKED := Color(0.78, 0.86, 0.94)        # 经纬度锁定的城市
const MAP_HANDLE_RADIUS := 7.0                     # 0° 经线 / 赤道的抓取半径（像素）
const MAP_CITY_RADIUS := 11.0                      # 城市标记的抓取半径（像素）
const MAP_ZOOM_MAX := 40.0

var world_ids: Array[String] = []
var city_ids: Array[String] = []
var current_world_id := ""
var current_world := {}
var current_city_id := ""
var current_city := {}
var _zh_data := {}        # zh.yaml：显示名基准表（主界面显示名来源）
var _loc_lang := "zh"     # 本地化页当前语言
var _loc_lang_data := {}  # 当前语言文件数据（语言 = zh 时就是 _zh_data 这一份）
var _loc_def := {}        # 当前语言的语言定义（Localization/<语言>.json：name / font）
var _snapshots := {}      # 磁盘快照：文档 key → 打开时的磁盘数据
var _stash := {}          # 暂存区：文档 key → 切换前未保存的数据
var _pending_recovery: Array = []   # 启动时装入暂存区、等待用户确认的草稿
var _suspend_stash := false         # 放弃恢复 / 放弃本页改动时置真：重选文档不进暂存区
var _draft_hash := {}               # 文档 key → 已写盘草稿的哈希（内容没变不重复写）
var _status_text := ""
var _close_dialog: ConfirmationDialog
var _close_discard_btn: Button   # “不保存退出”（AcceptDialog 的自定义按钮，留引用才能随时改文字）
var _recover_dialog: ConfirmationDialog
var _recover_discard_btn: Button
var _dirty_timer: Timer
var _prefs_ui_lang := "zh"          # 上次应用的界面语言（回到窗口时对齐用）
var _form_syncing := false          # 表单回填期间屏蔽控件回写

@onready var tabs: TabContainer = $Root/Column/Tabs
@onready var status_label: Label = $Root/Column/Bottom/StatusLabel
@onready var save_btn: Button = $Root/Column/Bottom/SaveBtn
@onready var save_all_btn: Button = $Root/Column/Bottom/SaveAllBtn
@onready var revert_btn: Button = $Root/Column/Bottom/RevertBtn

# —— 世界页 ——
@onready var world_pick: OptionButton = $Root/Column/Tabs/WorldTab/Top/WorldPick
@onready var new_id_edit: LineEdit = $Root/Column/Tabs/WorldTab/Top/NewId
@onready var new_btn: Button = $Root/Column/Tabs/WorldTab/Top/NewBtn
@onready var seed_edit: LineEdit = $Root/Column/Tabs/WorldTab/Form/SeedRow/SeedEdit
@onready var time_rows: VBoxContainer = $Root/Column/Tabs/WorldTab/Form/TimeSection/Rows
@onready var time_add_btn: Button = $Root/Column/Tabs/WorldTab/Form/TimeSection/AddBtn
@onready var date_rows: VBoxContainer = $Root/Column/Tabs/WorldTab/Form/DateSection/Rows
@onready var date_add_btn: Button = $Root/Column/Tabs/WorldTab/Form/DateSection/AddBtn

# —— 城市页 ——
@onready var city_pick: OptionButton = $Root/Column/Tabs/CityTab/Top/CityPick
@onready var world_ref_pick: OptionButton = $Root/Column/Tabs/CityTab/Scroll/Form/WorldRow/WorldRefPick
@onready var name_edit: LineEdit = $Root/Column/Tabs/CityTab/Scroll/Form/NameRow/NameEdit
@onready var long_spin: SpinBox = $Root/Column/Tabs/CityTab/Scroll/Form/GeoRow/LongSpin
@onready var lati_spin: SpinBox = $Root/Column/Tabs/CityTab/Scroll/Form/GeoRow/LatiSpin
@onready var alti_spin: SpinBox = $Root/Column/Tabs/CityTab/Scroll/Form/GeoRow/AltiSpin
@onready var anchor_btn: Button = $Root/Column/Tabs/CityTab/Scroll/Form/GeoRow/AnchorBtn
@onready var timez_spin: SpinBox = $Root/Column/Tabs/CityTab/Scroll/Form/TimeZoneRow/TimezSpin
@onready var times_pick: OptionButton = $Root/Column/Tabs/CityTab/Scroll/Form/SystemRow/TimesPick
@onready var calendar_pick: OptionButton = $Root/Column/Tabs/CityTab/Scroll/Form/SystemRow/CalendarPick
@onready var wall_rows: VBoxContainer = $Root/Column/Tabs/CityTab/Scroll/Form/WallSection/Rows
@onready var wall_add_btn: Button = $Root/Column/Tabs/CityTab/Scroll/Form/WallSection/AddBtn
@onready var effect_rows: VBoxContainer = $Root/Column/Tabs/CityTab/Scroll/Form/EffectSection/Rows
@onready var effect_add_btn: Button = $Root/Column/Tabs/CityTab/Scroll/Form/EffectSection/AddBtn

# —— 地图页：参考图 + 投影 + 经纬范围（挂在当前世界文档上）；城市定点（点击即存）——
@onready var map_world_pick: OptionButton = $Root/Column/Tabs/MapTab/MapTop/MapWorldPick
@onready var map_city_pick: OptionButton = $Root/Column/Tabs/MapTab/MapTop/MapCityPick
@onready var map_load_btn: Button = $Root/Column/Tabs/MapTab/MapTop/MapLoadBtn
@onready var map_import_check: CheckBox = $Root/Column/Tabs/MapTab/MapTop/MapImportCheck
@onready var map_proj_pick: OptionButton = $Root/Column/Tabs/MapTab/MapCfg/MapProjPick
@onready var map_lat_top_spin: SpinBox = $Root/Column/Tabs/MapTab/MapCfg/MapLatTopSpin
@onready var map_lat_bottom_spin: SpinBox = $Root/Column/Tabs/MapTab/MapCfg/MapLatBottomSpin
@onready var map_aspect_btn: Button = $Root/Column/Tabs/MapTab/MapCfg/MapAspectBtn
@onready var map_equator_btn: Button = $Root/Column/Tabs/MapTab/MapCfg/MapEquatorBtn
@onready var map_center_spin: SpinBox = $Root/Column/Tabs/MapTab/MapLon/MapCenterSpin
@onready var map_pick_zero_btn: Button = $Root/Column/Tabs/MapTab/MapLon/MapPickZeroBtn
@onready var map_span_spin: SpinBox = $Root/Column/Tabs/MapTab/MapLon/MapSpanSpin
@onready var map_reset_btn: Button = $Root/Column/Tabs/MapTab/MapLon/MapResetBtn
@onready var map_readout: Label = $Root/Column/Tabs/MapTab/MapReadout
@onready var map_view: Control = $Root/Column/Tabs/MapTab/MapView

var map_texture: Texture2D = null
var map_city_id := ""
var _map_tex_path := ""      # 已加载的参考图路径（路径没变就不重复读盘）
var _map_import_copy := true # 导入参考图时复制到工程 Maps/<世界>/（软件偏好，分享包友好）
var _lock_owned := false     # 单实例锁归本进程持有（退出时释放）
var _lock_dialog: AcceptDialog
var _map_cities := {}        # 当前世界下的城市：id → 磁盘数据（_refresh_map_cities 时刷新）
var _map_syncing := false    # 控件回填期间屏蔽 value_changed 回写
var _map_dialog: FileDialog
var _map_hover_ll := Vector2.ZERO   # 鼠标处经纬度（x=纬度 y=经度）
var _map_hover_in := false          # 鼠标是否在参考图上下缘之间
var _map_pan := Vector2.ZERO        # 视图中心相对图片中心的偏移（图片归一化单位）
var _map_zoom := 1.0                # 相对“适配视图”的放大倍率
var _map_pick := ""                 # 点选模式："" | prime（0° 经线）| equator（赤道）
var _map_drag := ""                 # 拖动中："" | pan | prime | equator | city
var _map_drag_grab := Vector2.ZERO  # 平移：按下位置
var _map_drag_start := Vector2.ZERO # 平移：按下时的 _map_pan
var _map_drag_base := Vector2.ZERO  # 平移：按下时的图片显示尺寸
var _map_drag_moved := 0.0          # 平移：累计位移（小于阈值算点击）
var _map_drag_center := 0.0         # 拖 0° 经线：未取整的中央经线
var _map_drag_lon := 0.0            # 拖 0° 经线：上一帧鼠标处的经度
var _map_drag_window := {}          # 拖赤道：按下时的纬度窗口（比例尺基准）
var _map_drag_city := ""            # 拖城市标记
var _map_drag_uv := Vector2.ZERO    # 拖城市标记：当前图上位置
var _map_drag_offset := Vector2.ZERO

# —— 本地化页 ——
@onready var loc_lang_pick: OptionButton = $Root/Column/Tabs/LocTab/LocTop/LangPick
@onready var loc_new_lang_edit: LineEdit = $Root/Column/Tabs/LocTab/LocTop/NewLangEdit
@onready var loc_new_lang_btn: Button = $Root/Column/Tabs/LocTab/LocTop/NewLangBtn
@onready var loc_use_btn: Button = $Root/Column/Tabs/LocTab/LocTop/UseBtn
@onready var loc_import_btn: Button = $Root/Column/Tabs/LocTab/LocTop/ImportBtn
@onready var loc_name_edit: LineEdit = $Root/Column/Tabs/LocTab/LocDef/NameRow/NameEdit
@onready var loc_font_edit: LineEdit = $Root/Column/Tabs/LocTab/LocDef/FontRow/FontEdit
@onready var loc_font_btn: Button = $Root/Column/Tabs/LocTab/LocDef/FontRow/FontBtn
@onready var loc_preview: Label = $Root/Column/Tabs/LocTab/LocDef/Preview
@onready var loc_rows: VBoxContainer = $Root/Column/Tabs/LocTab/LocScroll/LocRows
@onready var loc_group_edit: LineEdit = $Root/Column/Tabs/LocTab/LocAdd/LocGroupEdit
@onready var loc_key_edit: LineEdit = $Root/Column/Tabs/LocTab/LocAdd/LocKeyEdit
@onready var loc_value_edit: LineEdit = $Root/Column/Tabs/LocTab/LocAdd/LocValueEdit
@onready var loc_add_btn: Button = $Root/Column/Tabs/LocTab/LocAdd/LocAddBtn
var _font_dialog: FileDialog

# —— 世界页参数（m2：波动/现象分布；m2.1 批复隐藏两项超前参数，见下方注释）——
# [m2.1 隐藏·下版本可能启用] 日照/昼夜模型实装时恢复这两个控件（tscn 中也已注释）
# @onready var w_axial_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WAxialSpin
# @onready var w_day_hours_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WDayHoursSpin
@onready var w_temp_sigma_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WTempSigmaSpin
@onready var w_smooth_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WSmoothSpin
@onready var w_total_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WTotalSpin
@onready var w_spread_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WSpreadSpin
@onready var w_comp_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WCompSpin

# —— 现象页 ——
@onready var phen_world_pick: OptionButton = $Root/Column/Tabs/PhenTab/PhenTop/PhenWorldPick
@onready var phen_pick: OptionButton = $Root/Column/Tabs/PhenTab/PhenTop/PhenPick
@onready var phen_new_id: LineEdit = $Root/Column/Tabs/PhenTab/PhenTop/PhenNewId
@onready var phen_new_btn: Button = $Root/Column/Tabs/PhenTab/PhenTop/PhenNewBtn
@onready var phen_del_btn: Button = $Root/Column/Tabs/PhenTab/PhenTop/PhenDelBtn
@onready var phen_name_edit: LineEdit = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/PhenNameRow/PhenNameEdit
@onready var phen_scale_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/ScaleRow/PhenScaleSpin
@onready var phen_speed_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/ScaleRow/PhenSpeedSpin
@onready var phen_shape_type_pick: OptionButton = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/ShapeRow/PhenShapeTypePick
@onready var phen_axis_a_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/ShapeRow/PhenAxisASpin
@onready var phen_axis_b_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/ShapeRow/PhenAxisBSpin
@onready var phen_th_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/TempRulesRow/PhenTHSpin
@onready var phen_tl_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/TempRulesRow/PhenTLSpin
@onready var phen_rb_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/RainRulesRow/PhenRBSpin
@onready var phen_cd_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/RainRulesRow/PhenCDSpin
@onready var phen_dur_min_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/DurRow/PhenDurMinSpin
@onready var phen_dur_max_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/DurRow/PhenDurMaxSpin
@onready var phen_lat_min_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/OriginSection/OriginRow1/PhenLatMinSpin
@onready var phen_lat_max_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/OriginSection/OriginRow1/PhenLatMaxSpin
@onready var phen_where_pick: OptionButton = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/OriginSection/OriginRow1/PhenWherePick
@onready var phen_season_a_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/OriginSection/OriginRow2/PhenSeasonASpin
@onready var phen_season_b_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/OriginSection/OriginRow2/PhenSeasonBSpin
@onready var phen_p_spin: SpinBox = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/OriginSection/OriginRow2/PhenPSpin
@onready var rel_rows: VBoxContainer = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/RelSection/RelRows
@onready var rel_add_btn: Button = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/RelSection/RelAddBtn
@onready var kf_rows: VBoxContainer = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/KfSection/KfRows
@onready var kf_add_btn: Button = $Root/Column/Tabs/PhenTab/PhenScroll/PhenForm/KfSection/KfAddBtn

var phen_world_id := ""
var phen_data := {}      # Worlds/<id>.phenomena.json 内容
var phen_index := -1


func _ready() -> void:
	SettingsStore.ensure_defaults()
	# 单实例锁（0.0.1 收官批复）：已有别的编辑器进程在跑 → 提示后退出
	if not SettingsStore.acquire_editor_lock():
		_lock_owned = false
		get_window().title = UiText.t("设置编辑器 · 幻想气象局")
		_lock_dialog = AcceptDialog.new()
		_lock_dialog.title = UiText.t("设置编辑器")
		_lock_dialog.dialog_text = UiText.t("设置编辑器已在运行（独立窗口）")
		_lock_dialog.ok_button_text = UiText.t("确定")
		_lock_dialog.confirmed.connect(func() -> void: get_tree().quit(0))
		add_child(_lock_dialog)
		_lock_dialog.popup_centered.call_deferred()
		var auto_quit := get_tree().create_timer(10.0)
		auto_quit.timeout.connect(func() -> void:
			if is_instance_valid(_lock_dialog):
				get_tree().quit(0))
		return
	_lock_owned = true
	# 界面语言跟随软件偏好：先登记场景里的静态文字（必须早于任何代码改写它们），再换成当前语言
	_prefs_ui_lang = str(SettingsStore.load_preferences().get("ui_lang", "zh"))
	UiText.set_language(_prefs_ui_lang)
	UiText.install(self, true)
	SettingsStore.apply_ui_font(_prefs_ui_lang)
	get_window().title = UiText.t("设置编辑器 · 幻想气象局")
	# 关窗口先走 close_requested 的脏检测（有未保存改动时会询问），不由场景树直接退出
	get_tree().auto_accept_quit = false
	_form_syncing = true

	var recovered := _load_recovery()
	# zh 表先就位：世界/城市下拉框的显示名要用它
	if _stash.has("loc:zh"):
		_zh_data = _stash["loc:zh"]
		_stash.erase("loc:zh")
	else:
		var zh := SettingsStore.load_localization()
		_zh_data = zh.data
		for e in zh.errors:
			_set_status(UiText.f("本地化文件警告：%s", [e]))
		_snapshot("loc:zh", _zh_data)
	_refresh_worlds()
	_refresh_cities()
	_select_world(world_ids[0] if not world_ids.is_empty() else "")
	_select_city(city_ids[0] if not city_ids.is_empty() else "")
	_select_loc_lang("zh" if SettingsStore.list_languages().has("zh") else SettingsStore.list_languages()[0])
	_fill_phen_picks()
	_select_phen_world(world_ids[0] if not world_ids.is_empty() else "")
	_build_map_tab()
	_build_dialogs()
	_connect_signals()
	_set_tab_titles()
	# 上次没保存的草稿：把对应的文档切到前台（数据已在暂存区）
	for key in recovered:
		match _kind(str(key)):
			"world":
				_select_world(_id(str(key)))
			"city":
				_select_city(_id(str(key)))
			"phen":
				_select_phen_world(_id(str(key)))
			"loc":
				if _id(str(key)) != "zh":
					_select_loc_lang(_id(str(key)))
	_pending_recovery = recovered
	_form_syncing = false
	_set_status(UiText.t("改动先进内存草稿（切换选择不丢，关闭时询问处理）；「保存当前页」立即落盘"))
	_apply_status()

	# 脏状态指示 + 草稿落盘（每半秒）
	_dirty_timer = Timer.new()
	_dirty_timer.wait_time = 0.5
	_dirty_timer.autostart = true
	_dirty_timer.timeout.connect(_on_dirty_tick)
	add_child(_dirty_timer)

	# 开发辅助：FF_EDITOR_TAB=0/1/2 启动时定位到指定页签
	var env_tab := OS.get_environment("FF_EDITOR_TAB")
	if env_tab.is_valid_int():
		tabs.current_tab = clampi(env_tab.to_int(), 0, tabs.get_tab_count() - 1)
	if not _pending_recovery.is_empty():
		_ask_recovery.call_deferred()


func _connect_signals() -> void:
	# —— 世界页 ——
	world_pick.item_selected.connect(_on_world_picked)
	new_btn.pressed.connect(_on_world_created)
	time_add_btn.pressed.connect(_on_add_base_time)
	date_add_btn.pressed.connect(_on_add_base_date)
	seed_edit.text_changed.connect(_on_seed_changed)
	# 世界参数 SpinBox → current_world 字段（保存时随世界 JSON 落盘）
	w_temp_sigma_spin.value_changed.connect(func(v: float) -> void: _on_world_param_changed("month_temp_sigma", v))
	w_smooth_spin.value_changed.connect(func(v: float) -> void: _on_world_param_changed("month_smoothing", v))
	# [m2.1 隐藏·下版本可能启用] axial_tilt_deg / day_hours
	w_total_spin.value_changed.connect(func(v: float) -> void: _on_world_param_changed("monthly_total_strength", v))
	w_spread_spin.value_changed.connect(func(v: float) -> void: _on_world_param_changed("phenomena_spread_days", v))
	w_comp_spin.value_changed.connect(func(v: float) -> void: _on_world_param_changed("annual_compensation", v))

	# —— 城市页 ——
	city_pick.item_selected.connect(_on_city_picked)
	world_ref_pick.item_selected.connect(_on_city_world_ref)
	times_pick.item_selected.connect(_on_times_picked)
	calendar_pick.item_selected.connect(_on_calendar_picked)
	name_edit.text_changed.connect(_on_city_name_changed)
	long_spin.value_changed.connect(_on_geo_spin_changed)
	lati_spin.value_changed.connect(_on_geo_spin_changed)
	alti_spin.value_changed.connect(func(v: float) -> void:
		if not _form_syncing and not current_city.is_empty():
			current_city["alti"] = v)
	timez_spin.value_changed.connect(func(v: float) -> void:
		if not _form_syncing and not current_city.is_empty():
			current_city["timez"] = int(v))
	anchor_btn.toggled.connect(_on_anchor_toggled)
	wall_add_btn.pressed.connect(_on_add_wallpaper)
	effect_add_btn.pressed.connect(_on_add_effect)

	# —— 现象页 ——
	phen_world_pick.item_selected.connect(_on_phen_world_picked)
	phen_pick.item_selected.connect(_on_phen_picked)
	phen_new_btn.pressed.connect(_on_phen_created)
	phen_del_btn.pressed.connect(_on_phen_deleted)
	phen_name_edit.text_changed.connect(_on_phen_name_changed)
	phen_shape_type_pick.item_selected.connect(_on_shape_type_picked)
	phen_where_pick.item_selected.connect(_on_where_picked)
	phen_scale_spin.value_changed.connect(func(v: float) -> void: _phen_set("scale_km", v))
	phen_speed_spin.value_changed.connect(func(v: float) -> void: _phen_set("speed_kmh", v))
	phen_axis_a_spin.value_changed.connect(func(v: float) -> void: _phen_set_axis(0, v))
	phen_axis_b_spin.value_changed.connect(func(v: float) -> void: _phen_set_axis(1, v))
	phen_th_spin.value_changed.connect(func(v: float) -> void: _phen_set_rule("temp_high", v))
	phen_tl_spin.value_changed.connect(func(v: float) -> void: _phen_set_rule("temp_low", v))
	phen_rb_spin.value_changed.connect(func(v: float) -> void: _phen_set_rule("rain_bias", v))
	phen_cd_spin.value_changed.connect(func(v: float) -> void: _phen_set_rule("cloud", v))
	phen_dur_min_spin.value_changed.connect(func(v: float) -> void: _phen_set_duration(0, v))
	phen_dur_max_spin.value_changed.connect(func(v: float) -> void: _phen_set_duration(1, v))
	phen_lat_min_spin.value_changed.connect(func(v: float) -> void: _phen_set_origin("lat_min", v))
	phen_lat_max_spin.value_changed.connect(func(v: float) -> void: _phen_set_origin("lat_max", v))
	phen_season_a_spin.value_changed.connect(func(v: float) -> void: _phen_set_origin_season(0, int(v)))
	phen_season_b_spin.value_changed.connect(func(v: float) -> void: _phen_set_origin_season(1, int(v)))
	phen_p_spin.value_changed.connect(func(v: float) -> void: _phen_set_origin("p_per_day", v))
	rel_add_btn.pressed.connect(_on_rel_add)
	kf_add_btn.pressed.connect(_on_kf_add)

	# —— 本地化页 ——
	loc_add_btn.pressed.connect(_on_loc_add)
	loc_lang_pick.item_selected.connect(_on_loc_lang_picked)
	loc_new_lang_btn.pressed.connect(_on_lang_created)
	loc_use_btn.pressed.connect(_on_use_lang)
	loc_import_btn.pressed.connect(_on_loc_import)
	loc_name_edit.text_changed.connect(_on_loc_name_changed)
	loc_font_edit.text_changed.connect(_on_loc_font_changed)
	loc_font_btn.pressed.connect(_on_loc_font_browse)

	# —— 地图页 ——
	map_world_pick.item_selected.connect(_on_map_world_picked)
	map_city_pick.item_selected.connect(_on_map_city_picked)
	map_load_btn.pressed.connect(_on_map_load)
	map_proj_pick.item_selected.connect(_on_map_proj_picked)
	map_lat_top_spin.value_changed.connect(_on_map_lat_top_changed)
	map_lat_bottom_spin.value_changed.connect(_on_map_lat_bottom_changed)
	map_center_spin.value_changed.connect(_on_map_center_changed)
	map_span_spin.value_changed.connect(_on_map_span_changed)
	map_aspect_btn.pressed.connect(_on_map_aspect_pressed)
	map_pick_zero_btn.toggled.connect(_on_map_pick_zero_toggled)
	map_equator_btn.toggled.connect(_on_map_pick_equator_toggled)
	map_reset_btn.pressed.connect(_reset_map_view)
	map_view.draw.connect(_draw_map_view)
	map_view.gui_input.connect(_on_map_gui_input)
	map_view.mouse_exited.connect(func() -> void:
		_map_hover_in = false
		_update_map_readout())

	# —— 底部按钮与退出 ——
	save_btn.pressed.connect(_on_save)
	save_all_btn.pressed.connect(_on_save_all)
	revert_btn.pressed.connect(_on_revert)
	get_window().close_requested.connect(_on_close_request)


func _set_tab_titles() -> void:
	tabs.set_tab_title(0, UiText.t("世界"))
	tabs.set_tab_title(1, UiText.t("城市"))
	tabs.set_tab_title(2, UiText.t("现象"))
	tabs.set_tab_title(3, UiText.t("地图"))
	tabs.set_tab_title(4, UiText.t("本地化"))


func _build_dialogs() -> void:
	# 退出时脏检测：未保存改动 → 保存全部 / 放弃 / 取消
	_close_dialog = ConfirmationDialog.new()
	_close_dialog.confirmed.connect(_save_all_then_quit)
	_close_discard_btn = _close_dialog.add_button("", false, "discard")
	_close_dialog.custom_action.connect(func(action: String) -> void:
		if action == "discard":
			_discard_all_then_quit())
	add_child(_close_dialog)
	# 上次未保存的草稿：恢复 / 放弃
	_recover_dialog = ConfirmationDialog.new()
	_recover_dialog.exclusive = true
	_recover_dialog.confirmed.connect(_keep_recovery)
	_recover_discard_btn = _recover_dialog.add_button("", true, "discard")
	_recover_dialog.custom_action.connect(func(action: String) -> void:
		if action == "discard":
			_discard_recovery())
	add_child(_recover_dialog)
	_apply_dialog_texts()


func _apply_dialog_texts() -> void:
	_close_dialog.title = UiText.t("未保存的改动")
	_close_dialog.ok_button_text = UiText.t("保存全部并退出")
	_close_discard_btn.text = UiText.t("不保存退出")
	_close_dialog.get_cancel_button().text = UiText.t("取消")
	_recover_dialog.title = UiText.t("恢复未保存的草稿")
	_recover_dialog.ok_button_text = UiText.t("保留草稿")
	_recover_discard_btn.text = UiText.t("放弃草稿")
	_recover_dialog.get_cancel_button().visible = false


# ———————— 文档模型：key = "种类:ID" ————————
## 种类：world / city / phen / loc。打开着的文档各一份数据引用；不在前台但有未保存改动的在暂存区。

func _kind(key: String) -> String:
	return key.get_slice(":", 0)


func _id(key: String) -> String:
	return key.get_slice(":", 1)


func _open_keys() -> Array:
	var keys := []
	if current_world_id != "":
		keys.append("world:" + current_world_id)
	if current_city_id != "":
		keys.append("city:" + current_city_id)
	if phen_world_id != "":
		keys.append("phen:" + phen_world_id)
	if _loc_lang != "":
		keys.append("loc:" + _loc_lang)
	if not _zh_data.is_empty():
		keys.append("loc:zh")
	return keys


## 文档数据（可写引用）。不在前台的取暂存区；都没有返回空字典。
func _doc_data(key: String) -> Dictionary:
	if key == "world:" + current_world_id:
		return current_world
	if key == "city:" + current_city_id:
		return current_city
	if key == "phen:" + phen_world_id:
		return phen_data
	if key == "loc:" + _loc_lang:
		return _loc_lang_data
	if key == "loc:zh":
		return _zh_data
	var s = _stash.get(key, {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


## 从磁盘读一份文档（与打开文档时同口径：世界的 map 字段补全骨架）。
func _load_doc(key: String) -> Dictionary:
	var id := _id(key)
	if id.is_empty():
		return {}
	match _kind(key):
		"world":
			var w := SettingsStore.load_world(id)
			var m = w.get("map")
			w["map"] = MapProjection.normalized(m if typeof(m) == TYPE_DICTIONARY else {})
			return w
		"city":
			return SettingsStore.load_city(id)
		"phen":
			return SettingsStore.load_phenomena(id)
		"loc":
			return SettingsStore.load_localization_file(SettingsStore.loc_path(id)).data
	return {}


func _doc_write(key: String, data: Dictionary) -> Error:
	var id := _id(key)
	match _kind(key):
		"world":
			return SettingsStore.save_world(id, data)
		"city":
			return SettingsStore.save_city(id, data)
		"phen":
			return SettingsStore.save_phenomena(id, data)
		"loc":
			return SettingsStore.save_localization_file(SettingsStore.loc_path(id), data)
	return ERR_INVALID_PARAMETER


func _doc_exists(key: String) -> bool:
	var id := _id(key)
	if id.is_empty():
		return false
	match _kind(key):
		"world", "phen":
			return SettingsStore.list_world_ids().has(id)
		"city":
			return SettingsStore.list_city_ids().has(id)
		"loc":
			return true
	return false


func _doc_label(key: String) -> String:
	var id := _id(key)
	match _kind(key):
		"world":
			return UiText.f("世界 %s", [id])
		"city":
			var name := _zh_name("cities", id)
			return UiText.f("城市 %s", [UiText.f(FMT_ID_NAME, [id, name]) if not name.is_empty() else id])
		"phen":
			return UiText.f("现象模板 %s", [id])
	return UiText.f("本地化 %s", [SettingsStore.language_display_name(id)])


func _snapshot(key: String, data: Dictionary) -> void:
	_snapshots[key] = data.duplicate(true)


func _is_changed(key: String, data: Dictionary) -> bool:
	if data.is_empty() or not _snapshots.has(key):
		return false
	return hash(JSON.stringify(data)) != hash(JSON.stringify(_snapshots[key]))


## 离开一份文档：有未保存改动就进暂存区。
func _stash_open(key: String, data: Dictionary) -> void:
	if _suspend_stash or key.ends_with(":") or not _is_changed(key, data):
		return
	_stash[key] = data


## 全部未保存的文档 key（前台的 + 暂存区的）。
func _dirty_keys() -> Array:
	var out := []
	var keys := _open_keys()
	for k in _stash:
		if not keys.has(k):
			keys.append(k)
	for key in keys:
		if _is_changed(str(key), _doc_data(str(key))):
			out.append(key)
	return out


## 当前页正在编辑的文档；没有返回空串。
func _tab_doc_key(tab: int) -> String:
	match tab:
		0, 3:
			return "world:" + current_world_id
		1:
			return "city:" + current_city_id
		2:
			return "phen:" + phen_world_id
	return "loc:" + _loc_lang


# ———————— 草稿落盘与恢复 ————————

## 草稿目录：默认 user://editor_drafts；开发辅助 FF_DRAFT_DIR 可重定向（测试不污染真实草稿）。
static func draft_dir() -> String:
	var env := OS.get_environment("FF_DRAFT_DIR")
	return env if not env.is_empty() else "user://editor_drafts"


func _draft_file(key: String) -> String:
	# 文件名取 key 的指纹；真正的 key 存在文件内容里（_draft_file_keys 读它）
	return draft_dir().path_join(key.md5_text() + ".json")


func _write_draft(key: String, data: Dictionary) -> void:
	var text := JSON.stringify(data)
	var h := hash(text)
	if _draft_hash.has(key) and _draft_hash[key] == h and FileAccess.file_exists(_draft_file(key)):
		return
	DirAccess.make_dir_recursive_absolute(draft_dir())
	var f := FileAccess.open(_draft_file(key), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"key": key, "time": Time.get_unix_time_from_system(), "data": data}, "\t") + "\n")
	_draft_hash[key] = h


func _remove_draft(key: String) -> void:
	_draft_hash.erase(key)
	var p := _draft_file(key)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


## 草稿目录里现存的所有文档 key（key 记在文件内容里，文件名是指纹）。
func _draft_file_keys() -> Array:
	var out := []
	var dir := DirAccess.open(draft_dir())
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var file := FileAccess.open(draft_dir().path_join(f), FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
		if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("key", null)) == TYPE_STRING:
			out.append(str(parsed["key"]))
	return out


## 让磁盘上的草稿与内存里的未保存改动保持一致：有改动的写，已不再有改动的删。
func _sync_drafts() -> void:
	var dirty := _dirty_keys()
	for key in dirty:
		_write_draft(str(key), _doc_data(str(key)))
	for key in _draft_file_keys():
		if not dirty.has(key):
			_remove_draft(str(key))


## 启动时把上次的草稿装进暂存区，返回需要用户确认的草稿 key。
func _load_recovery() -> Array:
	var out := []
	for key in _draft_file_keys():
		var f := FileAccess.open(_draft_file(str(key)), FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text()) if f != null else null
		var data = parsed.get("data") if typeof(parsed) == TYPE_DICTIONARY else null
		if typeof(data) != TYPE_DICTIONARY or not _doc_exists(str(key)):
			_remove_draft(str(key))  # 残缺的草稿，或文档已不存在（城市 CSV / 世界文件被删）
			continue
		var disk := _load_doc(str(key))
		if hash(JSON.stringify(data)) == hash(JSON.stringify(disk)):
			_remove_draft(str(key))  # 与磁盘一致：当初保存过，只是没来得及清草稿
			continue
		_stash[key] = data
		_snapshots[key] = disk
		out.append(key)
	return out


func _ask_recovery() -> void:
	if _pending_recovery.is_empty():
		return
	var lines := PackedStringArray()
	for key in _pending_recovery:
		lines.append("· " + _doc_label(str(key)))
	_recover_dialog.dialog_text = UiText.f("上次编辑器没有正常保存就关闭了，留下 %d 份未保存的草稿：",
			[_pending_recovery.size()]) + "\n" + "\n".join(lines) + "\n" \
			+ UiText.t("它们已按原样载入（仍标记为未保存）。要保留吗？")
	_recover_dialog.popup_centered()


func _keep_recovery() -> void:
	var n := _pending_recovery.size()
	_pending_recovery = []
	_set_status(UiText.f("已恢复 %d 份草稿（仍是未保存状态，可继续编辑或用「放弃本页改动」丢弃）", [n]))


func _discard_recovery() -> void:
	_suspend_stash = true
	for key in _pending_recovery:
		_stash.erase(key)
		_remove_draft(str(key))
	_pending_recovery = []
	_refresh_worlds()
	_select_world(current_world_id)
	_select_city(current_city_id)
	_refresh_phen_worlds()
	_select_phen_world(phen_world_id)
	_zh_data = _load_doc("loc:zh")
	_snapshot("loc:zh", _zh_data)
	_refresh_loc_languages()
	_select_loc_lang(_loc_lang)
	_suspend_stash = false
	_set_status(UiText.t("已放弃上次的草稿"))


func _on_dirty_tick() -> void:
	_apply_status()
	_sync_drafts()


# ———————— 世界页 ————————

func _refresh_worlds() -> void:
	world_ids = SettingsStore.list_world_ids()
	world_pick.clear()
	for id in world_ids:
		var disp := _zh_name("worlds", id)
		world_pick.add_item(UiText.f(FMT_ID_NAME, [id, disp]) if not disp.is_empty() else id, 0)
		world_pick.set_item_metadata(world_pick.item_count - 1, id)
	if world_ids.is_empty():
		world_pick.add_item(UiText.t("（Worlds/ 下没有世界文件）"), 0)
		world_pick.set_item_disabled(0, true)
	_refresh_map_worlds()
	_refresh_phen_worlds()


func _select_world(id: String) -> void:
	_stash_open("world:" + current_world_id, current_world)
	current_world_id = id
	var key := "world:" + id
	if id == "":
		current_world = {}
	elif _stash.has(key):
		current_world = _stash[key]
		_stash.erase(key)
	else:
		current_world = _load_doc(key)
		_snapshot(key, current_world)
	var was := _form_syncing
	_form_syncing = true
	for i in world_pick.item_count:
		if str(world_pick.get_item_metadata(i)) == id:
			world_pick.select(i)
			break
	seed_edit.text = str(current_world.get("seed", ""))
	seed_edit.editable = id != ""
	for sp in [w_temp_sigma_spin, w_smooth_spin, w_total_spin, w_spread_spin, w_comp_spin]:
		sp.editable = id != ""
	# [m2.1 隐藏·下版本可能启用] axial_tilt_deg / day_hours 的回填行
	w_temp_sigma_spin.value = float(current_world.get("month_temp_sigma", 2.2))
	w_smooth_spin.value = float(current_world.get("month_smoothing", 0.5))
	w_total_spin.value = float(current_world.get("monthly_total_strength", 0.0))
	w_spread_spin.value = float(current_world.get("phenomena_spread_days", 7.0))
	w_comp_spin.value = float(current_world.get("annual_compensation", 0.0))
	_rebuild_time_rows()
	_rebuild_date_rows()
	_form_syncing = was
	_sync_map_controls()


func _on_world_picked(index: int) -> void:
	_select_world(str(world_pick.get_item_metadata(index)))


func _on_seed_changed(text: String) -> void:
	if not _form_syncing and not current_world.is_empty():
		current_world["seed"] = text.strip_edges()


func _on_world_param_changed(key: String, v: float) -> void:
	if not _form_syncing and not current_world.is_empty():
		current_world[key] = v


func _on_world_created() -> void:
	var id := new_id_edit.text.strip_edges()
	if id.is_empty():
		_set_status(UiText.t("请先在右侧输入新世界 ID"))
		return
	if id.contains("/") or id.contains("\\") or id.contains(":") or id.contains("."):
		_set_status(UiText.t("ID 不能包含斜杠、冒号或句点"))
		return
	if world_ids.has(id):
		_set_status(UiText.f("世界 %s 已存在", [id]))
		return
	var fresh: Dictionary = SettingsStore.WORLD_DEFAULTS.duplicate(true)
	fresh["map"] = MapProjection.normalized({})  # 新世界文件直接带完整的地图骨架
	SettingsStore.save_world(id, fresh)
	_ensure_loc_group("worlds")[id] = id
	_refresh_worlds()
	_select_world(id)
	new_id_edit.text = ""
	_set_status(UiText.f("已创建 Worlds/%s.json（尚未保存本地化改名）", [id]))


func _rebuild_time_rows() -> void:
	_clear_children(time_rows)
	if current_world.is_empty():
		return
	var arr: Array = current_world.get("base_times", [])
	for entry in arr:
		var e: Dictionary = entry
		time_rows.add_child(_make_base_row(e, "offset_minutes", UiText.t("偏差分钟"), -1440, 1440,
				func() -> void:
					current_world["base_times"].erase(e)
					_rebuild_time_rows()))


func _rebuild_date_rows() -> void:
	_clear_children(date_rows)
	if current_world.is_empty():
		return
	var arr: Array = current_world.get("base_dates", [])
	for entry in arr:
		var e: Dictionary = entry
		date_rows.add_child(_make_base_row(e, "offset_days", UiText.t("差天数"), -3650000, 3650000,
				func() -> void:
					current_world["base_dates"].erase(e)
					_rebuild_date_rows()))


func _make_base_row(entry: Dictionary, num_key: String, num_label: String,
		lo: int, hi: int, on_remove: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	var id_edit := LineEdit.new()
	id_edit.text = str(entry.get("id", ""))
	id_edit.placeholder_text = "id"
	id_edit.custom_minimum_size = Vector2(160, 0)
	id_edit.text_changed.connect(func(t: String) -> void: entry["id"] = t)
	var num := SpinBox.new()
	num.min_value = lo
	num.max_value = hi
	num.step = 1
	num.value = float(int(entry.get(num_key, 0)))
	num.custom_minimum_size = Vector2(150, 0)
	num.value_changed.connect(func(v: float) -> void: entry[num_key] = int(v))
	var lab := Label.new()
	lab.text = num_label
	lab.modulate = Color(0.75, 0.8, 0.88)
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(on_remove)
	box.add_child(id_edit)
	box.add_child(lab)
	box.add_child(num)
	box.add_child(del)
	return box


func _on_add_base_time() -> void:
	if current_world.is_empty():
		return
	current_world["base_times"].append({"id": "", "offset_minutes": 0})
	_rebuild_time_rows()


func _on_add_base_date() -> void:
	if current_world.is_empty():
		return
	current_world["base_dates"].append({"id": "", "offset_days": 0})
	_rebuild_date_rows()


# ———————— 城市页 ————————

func _refresh_cities() -> void:
	city_ids = SettingsStore.list_city_ids()
	city_pick.clear()
	for id in city_ids:
		var disp := _zh_name("cities", id)
		city_pick.add_item(UiText.f(FMT_ID_NAME, [id, disp]) if not disp.is_empty() else id, 0)
		city_pick.set_item_metadata(city_pick.item_count - 1, id)
	if city_ids.is_empty():
		city_pick.add_item(UiText.t("（Climate/ 下没有城市 CSV）"), 0)
		city_pick.set_item_disabled(0, true)
	_refresh_map_cities()


func _select_city(id: String) -> void:
	_stash_open("city:" + current_city_id, current_city)
	current_city_id = id
	var key := "city:" + id
	if id == "":
		current_city = {}
	elif _stash.has(key):
		current_city = _stash[key]
		_stash.erase(key)
	else:
		current_city = _load_doc(key)
		_snapshot(key, current_city)
	var was := _form_syncing
	_form_syncing = true
	for i in city_pick.item_count:
		if str(city_pick.get_item_metadata(i)) == id:
			city_pick.select(i)
			break
	var enabled := id != ""
	_set_city_form_enabled(enabled)
	# 名称取内存里的 zh 表：刚改过名还没保存时，切回来不能又显示磁盘上的旧名
	name_edit.text = _zh_name("cities", id)
	alti_spin.value = float(current_city.get("alti", 0.0))
	timez_spin.value = float(int(current_city.get("timez", 0)))
	_refresh_world_ref_pick()
	_rebuild_system_picks()
	_rebuild_dict_rows(wall_rows, "wallpaper", UiText.t("壁纸路径，逗号分隔"))
	_rebuild_dict_rows(effect_rows, "effects", UiText.t("效果标识，逗号分隔"))
	_update_geo_inputs()
	_form_syncing = was
	map_view.queue_redraw()


func _form_controls() -> Array:
	return [world_ref_pick, name_edit, long_spin, lati_spin, alti_spin, timez_spin,
			times_pick, calendar_pick, wall_add_btn, effect_add_btn]


func _set_city_form_enabled(enabled: bool) -> void:
	for c in _form_controls():
		if c is LineEdit or c is SpinBox:
			c.editable = enabled
		else:
			c.disabled = not enabled


## 经纬度输入框与「经纬度锁定」按钮的回填。
## 锁定（anchor = latlong）：输入框可编辑，城市在图上的位置由经纬度决定；
## 未锁定（anchor = map）：输入框只读，显示由图上位置换算出的经纬度。
func _update_geo_inputs() -> void:
	var has := not current_city.is_empty()
	var locked := has and str(current_city.get("anchor", ANCHOR_LATLONG)) == ANCHOR_LATLONG
	anchor_btn.set_pressed_no_signal(locked)
	anchor_btn.disabled = not has
	long_spin.editable = has and locked
	lati_spin.editable = has and locked
	if has and not locked:
		var ll := MapProjection.from_uv(_map_xy(current_city), _map_cfg_for_world(str(current_city.get("world", ""))))
		var was := _form_syncing
		_form_syncing = true
		long_spin.value = _round2(ll.y)
		lati_spin.value = _round2(ll.x)
		_form_syncing = was


## 城市在参考图上的位置（归一化坐标）。
func _map_xy(cd: Dictionary) -> Vector2:
	return Vector2(float(cd.get("map_x", 0.0)), float(cd.get("map_y", 0.0)))


func _on_city_picked(index: int) -> void:
	_select_city(str(city_pick.get_item_metadata(index)))


func _refresh_world_ref_pick() -> void:
	world_ref_pick.clear()
	world_ref_pick.add_item(UiText.t("（未指定）"), 0)
	world_ref_pick.set_item_metadata(0, "")
	for i in world_ids.size():
		var id: String = world_ids[i]
		var disp := _zh_name("worlds", id)
		world_ref_pick.add_item(UiText.f(FMT_ID_NAME, [id, disp]) if not disp.is_empty() else id, 0)
		world_ref_pick.set_item_metadata(i + 1, id)
	var want: String = str(current_city.get("world", ""))
	for i in world_ref_pick.item_count:
		if str(world_ref_pick.get_item_metadata(i)) == want:
			world_ref_pick.select(i)
			break


func _on_city_world_ref(index: int) -> void:
	if current_city.is_empty():
		return
	current_city["world"] = str(world_ref_pick.get_item_metadata(index))
	_rebuild_system_picks()
	_update_geo_inputs()
	_refresh_map_cities()  # 地图页按“所属世界”列城市


func _rebuild_system_picks() -> void:
	var w := {}
	var wid: String = str(current_city.get("world", ""))
	if wid != "" and world_ids.has(wid):
		w = SettingsStore.load_world(wid)
	_fill_system_pick(times_pick, w.get("base_times", []), UiText.t("（未指定 → UTC）"),
			str(current_city.get("times", "")), UiText.t("分钟"))
	_fill_system_pick(calendar_pick, w.get("base_dates", []), UiText.t("（未指定 → 公历）"),
			str(current_city.get("calendar", "")), UiText.t("天"))


func _fill_system_pick(pick: OptionButton, arr: Array, empty_label: String,
		current_id: String, unit: String) -> void:
	pick.clear()
	pick.add_item(empty_label, 0)
	pick.set_item_metadata(0, "")
	for i in arr.size():
		var e: Dictionary = arr[i]
		var eid := str(e.get("id", ""))
		var shown := eid if not eid.is_empty() else UiText.t("（未命名）")
		var offset := "0"
		if e.has("offset_minutes"):
			offset = str(int(e.get("offset_minutes", 0)))
		elif e.has("offset_days"):
			offset = str(int(e.get("offset_days", 0)))
		pick.add_item("%s（%s %s）" % [shown, offset, unit], 0)
		pick.set_item_metadata(i + 1, eid)
	var found := false
	for i in pick.item_count:
		if str(pick.get_item_metadata(i)) == current_id and not current_id.is_empty():
			pick.select(i)
			found = true
			break
	if not found:
		pick.select(0)


func _on_times_picked(index: int) -> void:
	if current_city.is_empty():
		return
	current_city["times"] = str(times_pick.get_item_metadata(index))


func _on_calendar_picked(index: int) -> void:
	if current_city.is_empty():
		return
	current_city["calendar"] = str(calendar_pick.get_item_metadata(index))


func _on_city_name_changed(text: String) -> void:
	if _form_syncing or current_city_id.is_empty():
		return
	_ensure_loc_group("cities")[current_city_id] = text


## 经纬度输入框：只有锁定（以经纬度为准）时才回写；未锁定时输入框是换算结果的只读显示。
func _on_geo_spin_changed(_v: float) -> void:
	if _form_syncing or current_city.is_empty():
		return
	if str(current_city.get("anchor", ANCHOR_LATLONG)) != ANCHOR_MAP:
		current_city["long"] = _round2(long_spin.value)
		current_city["lati"] = _round2(lati_spin.value)
	map_view.queue_redraw()


## 「经纬度锁定」：按下 = 以输入框里的经纬度为准；松开 = 以图上位置为准（按当前经纬度落到图上，不跳位）。
func _on_anchor_toggled(pressed: bool) -> void:
	if _form_syncing or current_city.is_empty():
		return
	var wid := str(current_city.get("world", ""))
	if pressed:
		current_city["anchor"] = ANCHOR_LATLONG
		_set_status(UiText.t("已锁定经纬度：以输入框为准，城市在图上的位置随世界地图配置移动"))
	else:
		var uv := MapProjection.to_uv(float(current_city.get("lati", 0.0)),
				float(current_city.get("long", 0.0)), _map_cfg_for_world(wid))
		current_city["anchor"] = ANCHOR_MAP
		current_city["map_x"] = _round4(uv.x)
		current_city["map_y"] = _round4(uv.y)
		_set_status(UiText.t("已改回图上位置：调整 0° 经线、赤道或投影时城市不跑位，经纬度随之换算"))
	_update_geo_inputs()
	map_view.queue_redraw()


func _rebuild_dict_rows(parent: VBoxContainer, field: String, value_hint: String) -> void:
	_clear_children(parent)
	if current_city.is_empty():
		return
	var dict: Dictionary = current_city.get(field, {})
	for key in dict:
		var state := {"key": str(key)}
		parent.add_child(_make_dict_row(parent, field, state, value_hint))


func _make_dict_row(parent: VBoxContainer, field: String, state: Dictionary,
		value_hint: String) -> HBoxContainer:
	var dict: Dictionary = current_city.get(field, {})
	var box := HBoxContainer.new()
	var id_edit := LineEdit.new()
	id_edit.text = state.key
	id_edit.placeholder_text = "id"
	id_edit.custom_minimum_size = Vector2(120, 0)
	var value_edit := LineEdit.new()
	var value: Variant = dict.get(state.key, [])
	value_edit.text = _join_list(value)
	value_edit.placeholder_text = value_hint
	value_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_edit.text_changed.connect(func(t: String) -> void:
		var old: Variant = dict.get(state.key, [])
		dict.erase(state.key)
		dict[t] = old
		state.key = t)
	value_edit.text_changed.connect(func(t: String) -> void:
		dict[state.key] = _split_list(t))
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(func() -> void:
		dict.erase(state.key)
		_rebuild_dict_rows(parent, field, value_hint))
	box.add_child(id_edit)
	box.add_child(value_edit)
	box.add_child(del)
	return box


func _on_add_wallpaper() -> void:
	if current_city.is_empty():
		return
	_ensure_city_dict("wallpaper")[""] = []
	_rebuild_dict_rows(wall_rows, "wallpaper", UiText.t("壁纸路径，逗号分隔"))


func _on_add_effect() -> void:
	if current_city.is_empty():
		return
	_ensure_city_dict("effects")[""] = []
	_rebuild_dict_rows(effect_rows, "effects", UiText.t("效果标识，逗号分隔"))


func _ensure_city_dict(field: String) -> Dictionary:
	if not current_city.has(field) or typeof(current_city[field]) != TYPE_DICTIONARY:
		current_city[field] = {}
	return current_city[field]


# ———————— 本地化页（每语言一份数据：Localization/<语言>.yaml + 语言定义 .json）———————

func _refresh_loc_languages() -> void:
	loc_lang_pick.clear()
	for lang in SettingsStore.list_languages():
		var disp := SettingsStore.language_display_name(lang)
		loc_lang_pick.add_item(UiText.f(FMT_ID_NAME, [disp, lang]) if disp != lang else lang, 0)
		loc_lang_pick.set_item_metadata(loc_lang_pick.item_count - 1, lang)


func _select_loc_lang(lang: String) -> void:
	if lang == "zh":
		if _loc_lang != "zh":  # 从别的语言切回 zh
			_stash_open("loc:" + _loc_lang, _loc_lang_data)
		_loc_lang = lang
		_loc_lang_data = _zh_data  # zh 是显示名基准表：本地化页编辑 zh 就是编辑这一份
	else:
		if _loc_lang != "zh":
			_stash_open("loc:" + _loc_lang, _loc_lang_data)
		_loc_lang = lang
		var key := "loc:" + lang
		if _stash.has(key):
			_loc_lang_data = _stash[key]
			_stash.erase(key)
		else:
			var res := SettingsStore.load_localization_file(SettingsStore.loc_path(lang))
			_loc_lang_data = res.data
			for e in res.errors:
				_set_status(UiText.f("本地化文件 %s 警告：%s", [lang, e]))
			_snapshot(key, _loc_lang_data)
	for i in loc_lang_pick.item_count:
		if str(loc_lang_pick.get_item_metadata(i)) == lang:
			loc_lang_pick.select(i)
			break
	_loc_def = SettingsStore.load_language_def(lang)
	_sync_loc_def_form()
	_rebuild_loc_rows()


## 语言定义表单（名称 / 字体）回填。语言定义改动即改即存。
func _sync_loc_def_form() -> void:
	var was := _form_syncing
	_form_syncing = true
	loc_name_edit.text = str(_loc_def.get("name", ""))
	loc_font_edit.text = str(_loc_def.get("font", ""))
	_form_syncing = was
	_update_loc_preview()


func _on_loc_lang_picked(index: int) -> void:
	_select_loc_lang(str(loc_lang_pick.get_item_metadata(index)))


func _on_loc_name_changed(text: String) -> void:
	if _form_syncing:
		return
	_loc_def["name"] = text.strip_edges()
	SettingsStore.save_language_def(_loc_lang, _loc_def)
	_refresh_loc_languages()
	for i in loc_lang_pick.item_count:
		if str(loc_lang_pick.get_item_metadata(i)) == _loc_lang:
			loc_lang_pick.select(i)
			break


func _on_loc_font_changed(text: String) -> void:
	if _form_syncing:
		return
	_loc_def["font"] = text.strip_edges()
	SettingsStore.save_language_def(_loc_lang, _loc_def)
	_update_loc_preview()


func _on_loc_font_browse() -> void:
	_font_dialog.popup_centered(Vector2i(820, 560))


## 字体预览：用该语言的字体渲染（字体里没有的字回退到界面默认字体）。
func _update_loc_preview() -> void:
	loc_preview.text = UiText.t("字体预览：0123 ABC 洛沅")
	var path := str(_loc_def.get("font", ""))
	var f := SettingsStore.language_font(_loc_lang)
	if f != null:
		loc_preview.add_theme_font_override("font", f)
	elif path.is_empty():
		loc_preview.remove_theme_font_override("font")
	else:
		loc_preview.remove_theme_font_override("font")
		_set_status(UiText.f("语言字体加载失败：%s", [path]))


func _on_lang_created() -> void:
	var lang := loc_new_lang_edit.text.strip_edges()
	if lang.is_empty():
		_set_status(UiText.t("请先输入新语言代码（如 en / ja）"))
		return
	if lang.contains("/") or lang.contains("\\") or lang.contains(".") or lang.contains(":"):
		_set_status(UiText.t("语言代码不能包含斜杠、冒号或句点"))
		return
	if SettingsStore.list_languages().has(lang):
		_set_status(UiText.f("语言 %s 已存在", [lang]))
		return
	SettingsStore.save_localization_file(SettingsStore.loc_path(lang), {"cities": {}, "worlds": {}})
	_refresh_loc_languages()
	_select_loc_lang(lang)
	loc_new_lang_edit.text = ""
	_set_status(UiText.f("已创建语言 %s（记得保存）", [lang]))


## 把界面语言（软件偏好）设为本地化页当前语言：主界面与编辑器都随之切换。
func _on_use_lang() -> void:
	var p := SettingsStore.load_preferences()
	p["ui_lang"] = _loc_lang
	SettingsStore.save_preferences(p)
	_apply_ui_language(_loc_lang)


## 把程序里的界面中文原文加进当前语言的 ui 组（已有的不动；留空 = 显示中文）。
func _on_loc_import() -> void:
	if _loc_lang == "zh":
		_set_status(UiText.t("中文是界面原文，不需要导入"))
		return
	var srcs: Dictionary = UiText.scan_sources()
	var ui := _ensure_lang_group("ui")
	var added := 0
	for s in srcs:
		if not ui.has(s):
			ui[s] = ""
			added += 1
	_rebuild_loc_rows()
	_set_status(UiText.f("已导入 %d 条界面字符串（键 = 中文原文；留空 = 显示中文）", [added]))


func _rebuild_loc_rows() -> void:
	_clear_children(loc_rows)
	for group in _loc_lang_data:
		var entries: Dictionary = _loc_lang_data[group]
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		var title := Label.new()
		title.text = "%s:" % str(group)
		title.modulate = Color(0.75, 0.8, 0.88)
		section.add_child(title)
		for key in entries:
			section.add_child(_make_loc_row(str(group), str(key)))
		loc_rows.add_child(section)


func _make_loc_row(group: String, key: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	var key_label := Label.new()
	key_label.text = key
	key_label.tooltip_text = key
	if group == UiText.GROUP:
		key_label.custom_minimum_size = Vector2(320, 0)  # 界面原文较长
	else:
		key_label.custom_minimum_size = Vector2(200, 0)
	key_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var value_edit := LineEdit.new()
	value_edit.text = str(_loc_lang_data[group].get(key, ""))
	value_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _loc_lang != "zh":
		# 中文原文作参照：界面译文的键就是原文；显示名取 zh 表
		var ref := key if group == UiText.GROUP else _zh_name(group, key)
		if not ref.is_empty():
			value_edit.placeholder_text = ref
	value_edit.text_changed.connect(func(t: String) -> void:
		_loc_lang_data[group][key] = t)
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(func() -> void:
		_loc_lang_data[group].erase(key)
		_rebuild_loc_rows())
	box.add_child(key_label)
	box.add_child(value_edit)
	box.add_child(del)
	return box


func _on_loc_add() -> void:
	var group := loc_group_edit.text.strip_edges()
	var key := loc_key_edit.text.strip_edges()
	if group.is_empty() or key.is_empty():
		_set_status(UiText.t("添加本地化条目需要组名与键名"))
		return
	_ensure_lang_group(group)[key] = loc_value_edit.text
	loc_key_edit.text = ""
	loc_value_edit.text = ""
	_rebuild_loc_rows()


# ———————— 保存 / 放弃 ————————

func _on_save() -> void:
	match tabs.current_tab:
		0:
			_save_world_tab()
		1:
			_save_city_tab()
		2:
			_save_phen_tab()
		3:
			# 地图配置是当前世界文档的一部分（与「世界」页共用同一份草稿）；城市定点则点击即存
			_save_world_tab()
		4:
			_save_loc_tab()


## 把一份文档落盘：快照更新为已保存状态，清出暂存区。城市靠图上位置定位时先换算经纬度。
func _save_key(key: String) -> bool:
	var data := _doc_data(key)
	if data.is_empty():
		return false
	if _kind(key) == "city":
		_prepare_city_doc(data)
	var err := _doc_write(key, data)
	if err != OK:
		_set_status(UiText.f("保存失败（%d）：%s", [err, _doc_label(key)]))
		return false
	_snapshots[key] = data.duplicate(true)
	_stash.erase(key)
	return true


func _save_world_tab() -> void:
	if current_world_id.is_empty():
		_set_status(UiText.t("没有可保存的世界"))
		return
	var wid := current_world_id
	if not _save_key("world:" + wid):
		return
	_rederive_map_cities(wid)
	_save_zh_names_if_dirty()
	_refresh_worlds()
	_select_world(wid)
	_set_status(UiText.f("已保存 Worlds/%s.json 与本地化", [wid]))


func _save_city_tab() -> void:
	if current_city_id.is_empty():
		_set_status(UiText.t("没有可保存的城市"))
		return
	_ensure_loc_group("cities")[current_city_id] = name_edit.text
	# 城市靠图上位置定位、且所属世界就是当前世界时，经纬度来自地图配置草稿：把地图配置一并落盘
	if str(current_city.get("anchor", ANCHOR_LATLONG)) == ANCHOR_MAP \
			and str(current_city.get("world", "")) == current_world_id:
		_persist_map_config()
	var id := current_city_id
	if not _save_key("city:" + id):
		return
	_save_zh_names_if_dirty()
	_refresh_cities()
	_select_city(id)
	_set_status(UiText.f("已保存 Cities/%s.json 与本地化", [id]))


func _save_phen_tab() -> void:
	if phen_world_id.is_empty():
		_set_status(UiText.t("没有可保存的世界现象"))
		return
	var wid := phen_world_id
	if not _save_key("phen:" + wid):
		return
	_save_zh_names_if_dirty()
	_refresh_phen_worlds()
	_select_phen_world(wid)
	_set_status(UiText.f("已保存 Worlds/%s.phenomena.json 与本地化", [wid]))


func _save_loc_tab() -> void:
	if not _save_key("loc:" + _loc_lang):
		return
	_set_status(UiText.f("已保存 res://Localization/%s.yaml", [_loc_lang]))


## 保存全部未保存的文档（含暂存区）。顺序：世界（地图配置）→ 城市（图上位置换算经纬度）→ zh 名字 → 其余。
func _on_save_all() -> void:
	if _save_all():
		_set_status(UiText.t("已保存全部改动"))


func _save_all() -> bool:
	var ok := true
	var dirty := _dirty_keys()
	var worlds := []
	for key in dirty:
		if _kind(str(key)) == "world":
			worlds.append(str(key))
			ok = _save_key(str(key)) and ok
	for key in dirty:
		if _kind(str(key)) == "city":
			ok = _save_key(str(key)) and ok
	for wid in worlds:
		_rederive_map_cities(wid)
	ok = _save_zh_names_if_dirty() and ok
	for key in dirty:
		var kind := _kind(str(key))
		if kind == "world" or kind == "city":
			continue
		if str(key) == "loc:zh":
			continue
		ok = _save_key(str(key)) and ok
	# 前台文档按已保存的状态重载
	_refresh_worlds()
	_select_world(current_world_id)
	_refresh_cities()
	_select_city(current_city_id)
	_refresh_phen_worlds()
	_select_phen_world(phen_world_id)
	_refresh_loc_languages()
	_select_loc_lang(_loc_lang)
	return ok


func _save_zh_names_if_dirty() -> bool:
	if not _is_changed("loc:zh", _zh_data):
		return true
	return _save_key("loc:zh")


## 城市靠图上位置定位时：由所属世界的地图配置换算经纬度。
func _prepare_city_doc(cd: Dictionary) -> void:
	if str(cd.get("anchor", ANCHOR_LATLONG)) != ANCHOR_MAP:
		return
	var ll := MapProjection.from_uv(_map_xy(cd), _map_cfg_for_world(str(cd.get("world", ""))))
	cd["lati"] = _round2(ll.x)
	cd["long"] = _round2(ll.y)


## 某个世界的地图配置：是当前世界就取草稿（地图页上看到的就是它），否则取磁盘上的。
func _map_cfg_for_world(wid: String) -> Dictionary:
	if wid != "" and wid == current_world_id and not current_world.is_empty():
		return _map_cfg()
	return MapProjection.normalized(SettingsStore.load_world(wid).get("map", {}) if wid != "" else {})


## 只把地图配置写进磁盘上的世界文件（不动世界草稿的其它字段），并把快照里的 map 同步为已保存状态。
## 用于“点击即存”的城市定点：定点结果依赖当前的地图配置，两者必须一起落盘。
func _persist_map_config() -> void:
	if current_world_id.is_empty():
		return
	var key := "world:" + current_world_id
	var snap: Dictionary = _snapshots.get(key, {})
	if snap.has("map") and JSON.stringify(_map_cfg()) == JSON.stringify(snap["map"]):
		return  # 地图配置没有未保存的改动
	var disk := SettingsStore.load_world(current_world_id)
	disk["map"] = _map_cfg().duplicate(true)
	if SettingsStore.save_world(current_world_id, disk) != OK:
		_set_status(UiText.t("地图配置写盘失败"))
		return
	if snap.has("map"):
		snap["map"] = disk["map"]


## 世界的地图配置保存后：把该世界里靠图上位置定位的城市重新换算经纬度并落盘。
func _rederive_map_cities(wid: String) -> void:
	var cfg := _map_cfg_for_world(wid)
	for id in city_ids:
		var cd := SettingsStore.load_city(id)
		if str(cd.get("world", "")) != wid or str(cd.get("anchor", ANCHOR_LATLONG)) != ANCHOR_MAP:
			continue
		var old_lati: float = cd["lati"]
		var old_long: float = cd["long"]
		_prepare_city_doc(cd)
		if is_equal_approx(old_lati, float(cd["lati"])) and is_equal_approx(old_long, float(cd["long"])):
			continue
		if SettingsStore.save_city(id, cd) != OK:
			continue
		if _map_cities.has(id):
			_map_cities[id] = SettingsStore.load_city(id)
		_sync_geo_into_docs(id, cd)
	map_view.queue_redraw()


## 磁盘上的城市坐标变了（定点 / 重新换算）：同步到内存里同一份文档——
## 免得之后在「城市」页保存时把旧坐标盖回去；快照一起改是为了不吞掉那份文档里其它的未保存改动。
func _sync_geo_into_docs(id: String, cd: Dictionary) -> void:
	var key := "city:" + id
	var data := _doc_data(key)
	if data.is_empty() or not _snapshots.has(key):
		return
	for f in ["anchor", "map_x", "map_y", "lati", "long"]:
		data[f] = cd[f]
	var snap: Dictionary = _snapshots[key]
	for f in ["anchor", "map_x", "map_y", "lati", "long"]:
		snap[f] = cd[f]
	if id == current_city_id:
		_update_geo_inputs()


## 「放弃本页改动」：把当前页的文档恢复成磁盘上已保存的状态。
func _on_revert() -> void:
	var key := _tab_doc_key(tabs.current_tab)
	if key.ends_with(":") or not _snapshots.has(key) or not _is_changed(key, _doc_data(key)):
		return
	_suspend_stash = true
	_stash.erase(key)  # 暂存区里的旧版本一并清掉，否则重选文档时又把它捞回来
	match _kind(key):
		"world":
			_select_world(current_world_id)
		"city":
			_select_city(current_city_id)
		"phen":
			_select_phen_world(phen_world_id)
		"loc":
			if _loc_lang == "zh":
				_zh_data = _load_doc("loc:zh")
				_snapshot("loc:zh", _zh_data)
				_refresh_worlds()
				_refresh_cities()
				_refresh_phen_worlds()
				_select_loc_lang("zh")
			else:
				_select_loc_lang(_loc_lang)
	_suspend_stash = false
	_set_status(UiText.t("已放弃本页的改动"))


# ———————— 退出：脏检测 ————————

func _on_close_request() -> void:
	var dirty := _dirty_keys()
	if dirty.is_empty():
		get_tree().quit()
	else:
		_close_dialog.dialog_text = UiText.f("有 %d 处未保存改动。退出前如何处理？", [dirty.size()])
		_close_dialog.popup_centered()


func _save_all_then_quit() -> void:
	if _save_all():
		_clear_all_drafts()
		get_tree().quit()


func _discard_all_then_quit() -> void:
	_clear_all_drafts()
	get_tree().quit()


func _clear_all_drafts() -> void:
	for key in _draft_file_keys():
		_remove_draft(str(key))


# ———————— 界面语言 ————————

func _exit_tree() -> void:
	if _lock_owned:
		SettingsStore.release_editor_lock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_sync_ui_language_from_disk()


## 主界面（或另一个编辑器）可能改过界面语言偏好：回到本窗口时对齐。
func _sync_ui_language_from_disk() -> void:
	var lang := str(SettingsStore.load_preferences().get("ui_lang", "zh"))
	if lang != UiText.language():
		_apply_ui_language(lang)


func _apply_ui_language(lang: String) -> void:
	_prefs_ui_lang = lang
	UiText.set_language(lang)
	SettingsStore.apply_ui_font(lang)
	UiText.install(self)
	get_window().title = UiText.t("设置编辑器 · 幻想气象局")
	_set_tab_titles()
	_fill_map_projection_pick()
	_fill_phen_picks()
	_map_dialog.title = UiText.t("选择世界参考图")
	_font_dialog.title = UiText.t("选择语言字体")
	_apply_dialog_texts()
	# 表单按内存里的文档整体重建（有未保存改动的文档原样保留）
	_refresh_worlds()
	_refresh_cities()
	_select_world(current_world_id)
	_select_city(current_city_id)
	_refresh_phen_worlds()
	_select_phen_world(phen_world_id)
	_refresh_loc_languages()
	_select_loc_lang(_loc_lang)
	_set_status(UiText.t("界面语言已切换"))


# ———————— 现象页 ————————

func _loc_value(group: String, key: String) -> String:
	return _zh_name(group, key)


## zh 名字字典（城市/世界/现象名）——主界面显示名来源。
func _ensure_loc_group(group: String) -> Dictionary:
	if not _zh_data.has(group) or typeof(_zh_data[group]) != TYPE_DICTIONARY:
		_zh_data[group] = {}
	return _zh_data[group]


## zh 表里的一个显示名（没有返回空串）。
func _zh_name(group: String, id: String) -> String:
	var g = _zh_data.get(group, {})
	return str(g.get(id, "")) if typeof(g) == TYPE_DICTIONARY else ""


## 本地化页当前语言字典。
func _ensure_lang_group(group: String) -> Dictionary:
	if not _loc_lang_data.has(group) or typeof(_loc_lang_data[group]) != TYPE_DICTIONARY:
		_loc_lang_data[group] = {}
	return _loc_lang_data[group]


func _fill_phen_picks() -> void:
	phen_shape_type_pick.clear()
	for pair in [["ellipse", "椭圆 ellipse"]]:
		phen_shape_type_pick.add_item(UiText.t(pair[1]), 0)
		phen_shape_type_pick.set_item_metadata(phen_shape_type_pick.item_count - 1, pair[0])
	phen_shape_type_pick.select(0)
	phen_where_pick.clear()
	for pair in [["any", "任意 any"], ["land", "陆地 land"], ["sea", "海洋 sea"], ["coast", "海岸 coast"]]:
		phen_where_pick.add_item(UiText.t(pair[1]), 0)
		phen_where_pick.set_item_metadata(phen_where_pick.item_count - 1, pair[0])
	phen_where_pick.select(0)


func _refresh_phen_worlds() -> void:
	phen_world_pick.clear()
	for id in world_ids:
		var disp := _zh_name("worlds", id)
		phen_world_pick.add_item(UiText.f(FMT_ID_NAME, [id, disp]) if not disp.is_empty() else id, 0)
		phen_world_pick.set_item_metadata(phen_world_pick.item_count - 1, id)
	if world_ids.is_empty():
		phen_world_pick.add_item(UiText.t("（Worlds/ 下没有世界文件）"), 0)
		phen_world_pick.set_item_disabled(0, true)
	for i in phen_world_pick.item_count:
		if str(phen_world_pick.get_item_metadata(i)) == phen_world_id:
			phen_world_pick.select(i)
			break


func _select_phen_world(id: String) -> void:
	_stash_open("phen:" + phen_world_id, phen_data)
	phen_world_id = id
	var key := "phen:" + id
	if id == "":
		phen_data = {}
	elif _stash.has(key):
		phen_data = _stash[key]
		_stash.erase(key)
	else:
		phen_data = _load_doc(key)
		_snapshot(key, phen_data)
	_refresh_phen_pick()


func _on_phen_world_picked(index: int) -> void:
	_select_phen_world(str(phen_world_pick.get_item_metadata(index)))


func _phen_list() -> Array:
	return phen_data.get("phenomena", [])


func _current_phen() -> Dictionary:
	var arr := _phen_list()
	if phen_index >= 0 and phen_index < arr.size():
		return arr[phen_index]
	return {}


func _refresh_phen_pick() -> void:
	phen_pick.clear()
	var arr := _phen_list()
	for i in arr.size():
		var eid := str(arr[i].get("id", ""))
		var disp := _loc_value("phenomena", eid)
		var shown := eid if not eid.is_empty() else UiText.t("（未命名）")
		phen_pick.add_item(UiText.f(FMT_ID_NAME, [shown, disp]) if not disp.is_empty() else shown, 0)
		phen_pick.set_item_metadata(i, i)
	if arr.is_empty():
		phen_pick.add_item(UiText.t("（该世界暂无气候现象）"), 0)
		phen_pick.set_item_disabled(0, true)
		phen_index = -1
	else:
		if phen_index < 0 or phen_index >= arr.size():
			phen_index = 0
		phen_pick.select(phen_index)
	for i in phen_world_pick.item_count:
		if str(phen_world_pick.get_item_metadata(i)) == phen_world_id:
			phen_world_pick.select(i)
			break
	_select_phen_entry()


func _on_phen_picked(index: int) -> void:
	phen_index = index
	_select_phen_entry()


func _select_phen_entry() -> void:
	var e := _current_phen()
	var enabled := not e.is_empty()
	for c in [phen_name_edit, phen_scale_spin, phen_speed_spin, phen_shape_type_pick,
			phen_axis_a_spin, phen_axis_b_spin, phen_th_spin, phen_tl_spin, phen_rb_spin,
			phen_cd_spin, phen_dur_min_spin, phen_dur_max_spin, phen_lat_min_spin,
			phen_lat_max_spin, phen_where_pick, phen_season_a_spin, phen_season_b_spin,
			phen_p_spin, rel_add_btn, kf_add_btn]:
		if c is LineEdit or c is SpinBox:
			c.editable = enabled
		else:
			c.disabled = not enabled
	phen_del_btn.disabled = not enabled
	_clear_children(rel_rows)
	_clear_children(kf_rows)
	if e.is_empty():
		phen_name_edit.text = ""
		return
	var was := _form_syncing
	_form_syncing = true
	phen_name_edit.text = _loc_value("phenomena", str(e.get("id", "")))
	phen_scale_spin.value = float(e.get("scale_km", 1000.0))
	phen_speed_spin.value = float(e.get("speed_kmh", 10.0))
	var shape: Dictionary = e.get("shape", {})
	var stype := str(shape.get("type", "ellipse"))
	for i in phen_shape_type_pick.item_count:
		if str(phen_shape_type_pick.get_item_metadata(i)) == stype:
			phen_shape_type_pick.select(i)
			break
	var axes: Array = shape.get("axes_km", [1000.0, 400.0])
	phen_axis_a_spin.value = float(axes[0]) if axes.size() > 0 else 1000.0
	phen_axis_b_spin.value = float(axes[1]) if axes.size() > 1 else 400.0
	var rules: Dictionary = e.get("rules", {})
	phen_th_spin.value = float(rules.get("temp_high", 0.0))
	phen_tl_spin.value = float(rules.get("temp_low", 0.0))
	phen_rb_spin.value = float(rules.get("rain_bias", 0.0))
	phen_cd_spin.value = float(rules.get("cloud", 0.0))
	var dur: Array = e.get("duration_hours", [48.0, 96.0])
	phen_dur_min_spin.value = float(dur[0]) if dur.size() > 0 else 48.0
	phen_dur_max_spin.value = float(dur[1]) if dur.size() > 1 else 96.0
	var origin: Dictionary = e.get("origin", {})
	phen_lat_min_spin.value = float(origin.get("lat_min", -30.0))
	phen_lat_max_spin.value = float(origin.get("lat_max", 30.0))
	var where := str(origin.get("where", "any"))
	for i in phen_where_pick.item_count:
		if str(phen_where_pick.get_item_metadata(i)) == where:
			phen_where_pick.select(i)
			break
	var season: Array = origin.get("season", [1, 12])
	phen_season_a_spin.value = float(season[0]) if season.size() > 0 else 1.0
	phen_season_b_spin.value = float(season[1]) if season.size() > 1 else 12.0
	phen_p_spin.value = float(origin.get("p_per_day", 0.05))
	_rebuild_rel_rows()
	_rebuild_kf_rows()
	_form_syncing = was


func _phen_set(key: String, v) -> void:
	var e := _current_phen()
	if not _form_syncing and not e.is_empty():
		e[key] = v


func _phen_set_rule(key: String, v) -> void:
	var e := _current_phen()
	if _form_syncing or e.is_empty():
		return
	if not e.has("rules") or typeof(e["rules"]) != TYPE_DICTIONARY:
		e["rules"] = {}
	e["rules"][key] = v


func _phen_set_shape(key: String, v) -> void:
	var e := _current_phen()
	if _form_syncing or e.is_empty():
		return
	if not e.has("shape") or typeof(e["shape"]) != TYPE_DICTIONARY:
		e["shape"] = {"type": "ellipse", "axes_km": [1000.0, 400.0]}
	e["shape"][key] = v


func _phen_set_axis(idx: int, v: float) -> void:
	var e := _current_phen()
	if _form_syncing or e.is_empty():
		return
	_phen_set_shape("axes_km", e.get("shape", {}).get("axes_km", [1000.0, 400.0]))
	var axes: Array = e["shape"]["axes_km"]
	while axes.size() < 2:
		axes.append(1000.0)
	axes[idx] = v


func _phen_set_duration(idx: int, v: float) -> void:
	var e := _current_phen()
	if _form_syncing or e.is_empty():
		return
	if not e.has("duration_hours") or typeof(e["duration_hours"]) != TYPE_ARRAY:
		e["duration_hours"] = [48.0, 96.0]
	while (e["duration_hours"] as Array).size() < 2:
		(e["duration_hours"] as Array).append(0.0)
	e["duration_hours"][idx] = v


func _phen_set_origin(key: String, v) -> void:
	var e := _current_phen()
	if _form_syncing or e.is_empty():
		return
	if not e.has("origin") or typeof(e["origin"]) != TYPE_DICTIONARY:
		e["origin"] = {}
	e["origin"][key] = v


func _phen_set_origin_season(idx: int, v: int) -> void:
	var e := _current_phen()
	if _form_syncing or e.is_empty():
		return
	_phen_set_origin("season", e.get("origin", {}).get("season", [1, 12]))
	var season: Array = e["origin"]["season"]
	while season.size() < 2:
		season.append(1)
	season[idx] = v


func _on_shape_type_picked(index: int) -> void:
	_phen_set_shape("type", str(phen_shape_type_pick.get_item_metadata(index)))


func _on_where_picked(index: int) -> void:
	_phen_set_origin("where", str(phen_where_pick.get_item_metadata(index)))


func _on_phen_name_changed(text: String) -> void:
	var e := _current_phen()
	if _form_syncing or e.is_empty():
		return
	_ensure_loc_group("phenomena")[str(e.get("id", ""))] = text


func _on_phen_created() -> void:
	var id := phen_new_id.text.strip_edges()
	if phen_world_id.is_empty():
		_set_status(UiText.t("请先选择世界"))
		return
	if id.is_empty():
		_set_status(UiText.t("请先输入新现象 ID"))
		return
	if id.contains("/") or id.contains("\\") or id.contains(":") or id.contains("."):
		_set_status(UiText.t("ID 不能包含斜杠、冒号或句点"))
		return
	for e in _phen_list():
		if str(e.get("id", "")) == id:
			_set_status(UiText.f("现象 %s 已存在", [id]))
			return
	if not phen_data.has("phenomena") or typeof(phen_data["phenomena"]) != TYPE_ARRAY:
		phen_data["phenomena"] = []
	phen_data["phenomena"].append({
		"id": id, "scale_km": 1000.0, "speed_kmh": 10.0,
		"shape": {"type": "ellipse", "axes_km": [1000.0, 400.0]},
		"rules": {"temp_high": 0.0, "temp_low": 0.0, "rain_bias": 0.0, "cloud": 0.0},
		"duration_hours": [48.0, 96.0],
		"path_keyframes": [{"t": 0.0, "x": 0.5, "y": 0.5, "strength": 1.0}],
		"origin": {"lat_min": -30.0, "lat_max": 30.0, "where": "any", "season": [1, 12], "p_per_day": 0.05},
		"relations": [],
	})
	phen_index = _phen_list().size() - 1
	_refresh_phen_pick()
	phen_new_id.text = ""
	_set_status(UiText.f("已创建现象 %s（记得保存）", [id]))


func _on_phen_deleted() -> void:
	var arr := _phen_list()
	if phen_index < 0 or phen_index >= arr.size():
		return
	arr.remove_at(phen_index)
	phen_index = -1
	_refresh_phen_pick()


func _rebuild_rel_rows() -> void:
	_clear_children(rel_rows)
	var e := _current_phen()
	if e.is_empty():
		return
	var arr: Array = e.get("relations", [])
	for entry in arr:
		var d: Dictionary = entry
		rel_rows.add_child(_make_rel_row(d, func() -> void:
			(e["relations"] as Array).erase(d)
			_rebuild_rel_rows()))


func _make_rel_row(entry: Dictionary, on_remove: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	var type_pick := OptionButton.new()
	for pair in [["exclusive", "互斥 exclusive"], ["succession", "接续 succession"], ["ally", "促进 ally"]]:
		type_pick.add_item(UiText.t(pair[1]), 0)
		type_pick.set_item_metadata(type_pick.item_count - 1, pair[0])
	var cur := str(entry.get("type", "exclusive"))
	for i in type_pick.item_count:
		if str(type_pick.get_item_metadata(i)) == cur:
			type_pick.select(i)
			break
	type_pick.item_selected.connect(func(idx: int) -> void:
		entry["type"] = str(type_pick.get_item_metadata(idx)))
	var with_edit := LineEdit.new()
	var parts := PackedStringArray()
	for x in entry.get("with", []):
		parts.append(str(x))
	with_edit.text = ", ".join(parts)
	with_edit.placeholder_text = UiText.t("对方现象ID，逗号分隔")
	with_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	with_edit.text_changed.connect(func(t: String) -> void:
		entry["with"] = _split_list(t))
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(on_remove)
	box.add_child(type_pick)
	box.add_child(with_edit)
	box.add_child(del)
	return box


func _on_rel_add() -> void:
	var e := _current_phen()
	if e.is_empty():
		return
	if not e.has("relations") or typeof(e["relations"]) != TYPE_ARRAY:
		e["relations"] = []
	e["relations"].append({"type": "exclusive", "with": []})
	_rebuild_rel_rows()


func _rebuild_kf_rows() -> void:
	_clear_children(kf_rows)
	var e := _current_phen()
	if e.is_empty():
		return
	var arr: Array = e.get("path_keyframes", [])
	for entry in arr:
		var d: Dictionary = entry
		kf_rows.add_child(_make_kf_row(d, func() -> void:
			(e["path_keyframes"] as Array).erase(d)
			_rebuild_kf_rows()))


func _make_kf_row(entry: Dictionary, on_remove: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	var defs := [
		["t", "t", 0.0, 1.0, 0.01],
		["x", "x", 0.0, 1.0, 0.01],
		["y", "y", 0.0, 1.0, 0.01],
		["strength", "强度", 0.0, 3.0, 0.05],
	]
	for d in defs:
		var lab := Label.new()
		lab.text = UiText.t(d[1])
		lab.modulate = Color(0.75, 0.8, 0.88)
		var sp := SpinBox.new()
		sp.min_value = d[2]
		sp.max_value = d[3]
		sp.step = d[4]
		sp.custom_minimum_size = Vector2(90, 0)
		sp.value = float(entry.get(d[0], 0.0))
		var key: String = d[0]
		sp.value_changed.connect(func(v: float) -> void:
			entry[key] = v)
		box.add_child(lab)
		box.add_child(sp)
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(on_remove)
	box.add_child(del)
	return box


func _on_kf_add() -> void:
	var e := _current_phen()
	if e.is_empty():
		return
	if not e.has("path_keyframes") or typeof(e["path_keyframes"]) != TYPE_ARRAY:
		e["path_keyframes"] = []
	var n := (e["path_keyframes"] as Array).size()
	e["path_keyframes"].append({
		"t": clampf(n * 0.25, 0.0, 1.0), "x": 0.5, "y": 0.5, "strength": 1.0,
	})
	_rebuild_kf_rows()


# ———————— 地图页：参考图 + 投影 + 经纬范围；城市定点（点击即存 / 拖动标记）——————
## 地图配置（image / projection / lon_span / lat_top / lat_bottom / center_long）挂在**当前世界文档**上，
## 与「世界」页共用同一份草稿：改动进内存，「保存当前页」落盘。
## 画布：参考图放在一圈经度的世界条带里；图片不覆盖的经度是空位。可拖动平移、滚轮缩放；
## 橙色的 0° 经线与赤道可以直接拖；城市标记可以拖（松手即存）。

## 当前世界的地图配置（可写引用——改它就是改世界草稿）。
func _map_cfg() -> Dictionary:
	if current_world.is_empty():
		return MapProjection.normalized({})
	if typeof(current_world.get("map")) != TYPE_DICTIONARY:
		current_world["map"] = MapProjection.normalized({})
	return current_world["map"]


## 一整圈经度等于几个图片宽度（整圈图 = 1）。
func _map_period() -> float:
	return 360.0 / float(_map_cfg().get("lon_span", 360.0))


func _build_map_tab() -> void:
	_fill_map_projection_pick()
	_sync_map_controls()
	_map_import_copy = bool(SettingsStore.load_preferences().get("map_import_copy", true))
	map_import_check.set_pressed_no_signal(_map_import_copy)
	_map_dialog = FileDialog.new()
	_map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE  # 选已有的图片（默认是保存模式，按钮会变成 Save）
	_map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_map_dialog.title = UiText.t("选择世界参考图")
	_map_dialog.filters = PackedStringArray([UiText.t("*.png ; PNG 图片"),
			UiText.t("*.jpg ; JPEG 图片"), UiText.t("*.webp ; WebP 图片")])
	_map_dialog.file_selected.connect(_on_map_file)
	add_child(_map_dialog)
	map_import_check.toggled.connect(_on_map_import_toggled)
	_font_dialog = FileDialog.new()
	_font_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_font_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_font_dialog.title = UiText.t("选择语言字体")
	_font_dialog.filters = PackedStringArray([UiText.t("*.ttf ; TrueType 字体"), UiText.t("*.otf ; OpenType 字体")])
	_font_dialog.file_selected.connect(func(path: String) -> void:
		loc_font_edit.text = path
		_on_loc_font_changed(path))  # 赋值不触发 text_changed：手动走一次保存
	add_child(_font_dialog)
	# 开发辅助：FF_MAP_IMAGE=<图片路径> 启动时自动加载参考图
	var env_map := OS.get_environment("FF_MAP_IMAGE")
	if not env_map.is_empty():
		_on_map_file(env_map)


func _fill_map_projection_pick() -> void:
	map_proj_pick.clear()
	for pair in [[MapProjection.MERCATOR, "墨卡托 mercator"],
			[MapProjection.EQUIRECTANGULAR, "等距圆柱 equirectangular"]]:
		map_proj_pick.add_item(UiText.t(pair[1]), 0)
		map_proj_pick.set_item_metadata(map_proj_pick.item_count - 1, pair[0])
	for i in map_proj_pick.item_count:
		if str(map_proj_pick.get_item_metadata(i)) == str(_map_cfg().get("projection", MapProjection.MERCATOR)):
			map_proj_pick.select(i)
			break


func _refresh_map_worlds() -> void:
	var was := _map_syncing
	_map_syncing = true
	map_world_pick.clear()
	for id in world_ids:
		var disp := _zh_name("worlds", id)
		map_world_pick.add_item(UiText.f(FMT_ID_NAME, [id, disp]) if not disp.is_empty() else id, 0)
		map_world_pick.set_item_metadata(map_world_pick.item_count - 1, id)
	if world_ids.is_empty():
		map_world_pick.add_item(UiText.t("（Worlds/ 下没有世界文件）"), 0)
		map_world_pick.set_item_disabled(0, true)
	for i in map_world_pick.item_count:
		if str(map_world_pick.get_item_metadata(i)) == current_world_id:
			map_world_pick.select(i)
	_map_syncing = was


func _on_map_world_picked(index: int) -> void:
	var id := str(map_world_pick.get_item_metadata(index))
	_reset_map_view()
	_select_world(id)


## 把世界文档里的地图配置回填到控件（回填期间屏蔽回写），并按需重新加载参考图。
## refresh_cities = false 用于拖动线/滚轮过程中的高频刷新（城市列表没变）。
func _sync_map_controls(refresh_cities: bool = true) -> void:
	var was := _map_syncing
	_map_syncing = true
	var cfg := _map_cfg()
	var has_world := current_world_id != ""
	for i in map_world_pick.item_count:
		if str(map_world_pick.get_item_metadata(i)) == current_world_id:
			map_world_pick.select(i)
	for i in map_proj_pick.item_count:
		if str(map_proj_pick.get_item_metadata(i)) == str(cfg["projection"]):
			map_proj_pick.select(i)
	map_lat_top_spin.value = float(cfg["lat_top"])
	map_lat_bottom_spin.value = float(cfg["lat_bottom"])
	map_center_spin.value = float(cfg["center_long"])
	map_span_spin.value = float(cfg["lon_span"])
	map_proj_pick.disabled = not has_world
	map_lat_top_spin.editable = has_world
	map_lat_bottom_spin.editable = has_world
	map_center_spin.editable = has_world
	map_span_spin.editable = has_world
	map_load_btn.disabled = not has_world
	map_reset_btn.disabled = map_texture == null
	if str(cfg["image"]) != _map_tex_path:
		_load_map_texture(str(cfg["image"]))
		map_reset_btn.disabled = map_texture == null
	map_aspect_btn.disabled = not (map_texture != null and has_world)
	if map_texture == null and _map_pick != "":
		_set_map_pick("")
	map_pick_zero_btn.disabled = map_texture == null
	map_equator_btn.disabled = map_texture == null
	_map_syncing = was
	if refresh_cities:
		_refresh_map_cities()
	_update_map_readout()
	map_view.queue_redraw()


func _load_map_texture(path: String) -> void:
	_map_tex_path = path
	map_texture = null
	if path.is_empty():
		return
	# res:// 相对路径（导入复制的图）也能加载
	var abs_path := ProjectSettings.globalize_path(path) if not path.is_absolute_path() else path
	var img := Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		_set_status(UiText.f("参考图加载失败：%s", [path]))
		return
	map_texture = ImageTexture.create_from_image(img)


## 当前世界下的城市（地图页下拉框 + 画布标记）。
func _refresh_map_cities() -> void:
	map_city_pick.clear()
	_map_cities.clear()
	for id in city_ids:
		var cd := SettingsStore.load_city(id)
		if current_world_id != "" and str(cd.get("world", "")) == current_world_id:
			_map_cities[id] = cd
	for id in _map_cities:
		var disp := _zh_name("cities", str(id))
		map_city_pick.add_item(UiText.f(FMT_ID_NAME, [id, disp]) if not disp.is_empty() else str(id), 0)
		map_city_pick.set_item_metadata(map_city_pick.item_count - 1, str(id))
	if _map_cities.is_empty():
		map_city_pick.add_item(UiText.t("（该世界下暂无城市——先到「城市」页指定所属世界）"), 0)
		map_city_pick.set_item_disabled(0, true)
	if not _map_cities.has(map_city_id):
		map_city_id = str(_map_cities.keys()[0]) if not _map_cities.is_empty() else ""
	_select_map_city_pick()
	map_view.queue_redraw()


func _select_map_city_pick() -> void:
	for i in map_city_pick.item_count:
		if str(map_city_pick.get_item_metadata(i)) == map_city_id:
			map_city_pick.select(i)
			break
	map_view.queue_redraw()


func _on_map_city_picked(index: int) -> void:
	map_city_id = str(map_city_pick.get_item_metadata(index))
	map_view.queue_redraw()


func _on_map_load() -> void:
	_map_dialog.popup_centered(Vector2i(820, 560))


## 「导入时复制到工程」：偏好持久化（随改随存）。
func _on_map_import_toggled(pressed: bool) -> void:
	_map_import_copy = pressed
	var p := SettingsStore.load_preferences()
	p["map_import_copy"] = pressed
	SettingsStore.save_preferences(p)


func _on_map_file(path: String) -> void:
	if current_world_id.is_empty():
		_set_status(UiText.t("请先选择世界——参考图挂在世界上"))
		return
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_set_status(UiText.f("参考图加载失败：%s", [path]))
		return
	# 导入设置（收官批复）：复制一份进工程 Maps/<世界ID>/，存相对路径——世界文件夹整体拷走即可分享
	var stored := path
	if _map_import_copy:
		var dir := ProjectSettings.globalize_path("res://Maps").path_join(current_world_id)
		DirAccess.make_dir_recursive_absolute(dir)
		var dst := dir.path_join(path.get_file())
		if path == dst:
			stored = path  # 选的本来就是工程里的这份
		elif DirAccess.copy_absolute(path, dst) == OK:
			stored = "res://Maps/%s/%s" % [current_world_id, path.get_file()]
		else:
			_set_status(UiText.t("参考图复制到工程失败，改用原路径"))
	_map_cfg()["image"] = stored
	_reset_map_view()
	_sync_map_controls()
	_set_status(UiText.f("参考图已加载（%d×%d）——点击或拖动给选中城市定点；图片路径与经纬范围用「保存当前页」落盘", [
		img.get_width(), img.get_height()]))


func _on_map_proj_picked(index: int) -> void:
	if _map_syncing or current_world_id.is_empty():
		return
	_map_cfg()["projection"] = str(map_proj_pick.get_item_metadata(index))
	_sync_map_controls()


func _on_map_lat_top_changed(v: float) -> void:
	if _map_syncing or current_world_id.is_empty():
		return
	_map_cfg()["lat_top"] = _round2(v)
	if float(_map_cfg()["lat_bottom"]) >= v:
		map_lat_bottom_spin.value = v - MapProjection.MIN_WINDOW
	_update_geo_inputs()
	map_view.queue_redraw()


func _on_map_lat_bottom_changed(v: float) -> void:
	if _map_syncing or current_world_id.is_empty():
		return
	_map_cfg()["lat_bottom"] = _round2(v)
	if float(_map_cfg()["lat_top"]) <= v:
		map_lat_top_spin.value = v + MapProjection.MIN_WINDOW
	_update_geo_inputs()
	map_view.queue_redraw()


func _on_map_center_changed(v: float) -> void:
	if _map_syncing or current_world_id.is_empty():
		return
	_map_cfg()["center_long"] = _round2(v)
	map_view.queue_redraw()


func _on_map_span_changed(v: float) -> void:
	if _map_syncing or current_world_id.is_empty():
		return
	_map_cfg()["lon_span"] = _round2(v)
	map_view.queue_redraw()


## 真墨卡托图纵横比例尺一致：按图片宽高比与覆盖经度反推上下缘纬度（赤道位置保持不动）。
func _on_map_aspect_pressed() -> void:
	if map_texture == null:
		return
	var w := MapProjection.lat_window_from_aspect(map_texture.get_width(), map_texture.get_height(), _map_cfg())
	map_lat_top_spin.value = _round2(float(w["lat_top"]))
	map_lat_bottom_spin.value = _round2(float(w["lat_bottom"]))
	_set_status(UiText.f("按图片比例推算：上缘 %.2f°、下缘 %.2f°（记得保存）", [w["lat_top"], w["lat_bottom"]]))


func _on_map_pick_zero_toggled(pressed: bool) -> void:
	_set_map_pick("prime" if pressed else "")


func _on_map_pick_equator_toggled(pressed: bool) -> void:
	_set_map_pick("equator" if pressed else "")


## 点选模式（0° 经线 / 赤道二选一）：此状态下点击不给城市定点。
func _set_map_pick(pick: String) -> void:
	_map_pick = pick if map_texture != null else ""
	map_pick_zero_btn.set_pressed_no_signal(_map_pick == "prime")
	map_equator_btn.set_pressed_no_signal(_map_pick == "equator")
	_update_map_readout()


func _apply_equator_window(v: float, base: Dictionary) -> void:
	var w := MapProjection.lat_window_for_equator_at(clampf(v, -1.0, 2.0), base)
	var cfg := _map_cfg()
	cfg["lat_top"] = _round2(float(w["lat_top"]))
	cfg["lat_bottom"] = _round2(float(w["lat_bottom"]))
	_sync_map_controls(false)


func _update_map_readout() -> void:
	if _map_pick == "prime":
		map_readout.text = UiText.t("点选 0° 经线：在参考图上点击 0° 经线所在的一列（此状态下点击不会给城市定点）")
	elif _map_pick == "equator":
		map_readout.text = UiText.t("点选赤道：在参考图上点击赤道所在的一行（此状态下点击不会给城市定点）")
	elif _map_drag == "city":
		var ll := MapProjection.from_uv(_map_drag_uv, _map_cfg())
		map_readout.text = UiText.f("拖动中：经度 %.2f°   纬度 %.2f°", [ll.y, ll.x])
	elif _map_hover_in:
		map_readout.text = UiText.f("鼠标处：经度 %.2f°   纬度 %.2f°", [_map_hover_ll.y, _map_hover_ll.x])
	elif _map_tex_path != "" and map_texture != null:
		map_readout.text = UiText.t("点击给选中城市定点（即存，城市锚定在图上这个位置）；拖动橙色的 0° 经线 / 赤道线调整；拖动空白处平移、滚轮缩放、双击复位。投影与经纬范围的改动用「保存当前页」落盘")
	else:
		map_readout.text = UiText.t("参考图挂在当前世界上。加载后可给城市定点、标定 0° 经线与赤道")


func _reset_map_view() -> void:
	_map_pan = Vector2.ZERO
	_map_zoom = 1.0
	map_view.queue_redraw()


# —— 画布几何 ——

## 参考图在 MapView 里的适配矩形（保持纵横比，留 8px 边距；即 pan=0、zoom=1 时的显示）。
func _map_fit_rect() -> Rect2:
	if map_texture == null or map_view.size.x <= 0 or map_view.size.y <= 0:
		return Rect2()
	var ts := Vector2(map_texture.get_width(), map_texture.get_height())
	var avail := map_view.size - Vector2(16, 16)
	var scale := minf(avail.x / ts.x, avail.y / ts.y)
	var size := ts * scale
	return Rect2((map_view.size - size) * 0.5, size)


## 参考图当前在 MapView 里的显示矩形（含平移与缩放）。图片归一化坐标 (u, v) 落在 rect.position + (u, v)·rect.size。
func _map_rect() -> Rect2:
	var fit := _map_fit_rect()
	if fit.size == Vector2.ZERO:
		return Rect2()
	var size := fit.size * _map_zoom
	var center_ref := Vector2(0.5, 0.5) + _map_pan  # 图片上位于视图中心的点
	return Rect2(map_view.size * 0.5 - center_ref * size, size)


## MapView 像素 → 图片归一化坐标（u 可越出 0..1：那是没有参考图的经度）。
func _px_to_uv(px: Vector2, rect: Rect2) -> Vector2:
	return (px - rect.position) / rect.size


## 越出图片的归一化坐标 → MapView 像素（按经度环绕，取离视图中心最近的那一份）。
func _uv_to_px(uv: Vector2, rect: Rect2) -> Vector2:
	var x0 := rect.position.x + uv.x * rect.size.x
	var w := rect.size.x * _map_period()
	if w > 0.5:
		var k := roundf((map_view.size.x * 0.5 - x0) / w)
		x0 += k * w
	return Vector2(x0, rect.position.y + uv.y * rect.size.y)


func _set_pan(p: Vector2) -> void:
	_map_pan = p
	_map_pan.y = clampf(_map_pan.y, -0.5, 0.5)  # 视图中心不跑出参考图的上下缘
	var period := _map_period()
	if is_equal_approx(period, 1.0):
		_map_pan.x = wrapf(_map_pan.x, -0.5, 0.5)  # 整圈图：环绕
	map_view.queue_redraw()


## 经度环绕：视图里能看到图片的第几份拷贝（k = 0 是原图）。
func _visible_tiles(rect: Rect2, view: Rect2) -> Array:
	var w := rect.size.x * _map_period()
	if w <= 0.5:
		return [0]  # 覆盖经度太小：环绕的重复图不到半像素，只画一份
	var out := []
	var kmin := floori((view.position.x - rect.end.x) / w) - 1
	var kmax := mini(ceili((view.end.x - rect.position.x) / w) + 1, kmin + 72)
	for k in range(kmin, kmax + 1):
		out.append(k)
	return out


func _city_data(id: String) -> Dictionary:
	if id == current_city_id and not current_city.is_empty():
		return current_city  # 城市页的当前文档：以内存草稿为准
	return _map_cities.get(id, {})


## 城市在图片归一化坐标里的位置：锚定图上位置的直接取；经纬度锁定的按经纬度映射（纬度越出图外钉在边缘）。
func _city_uv(id: String) -> Vector2:
	var cd := _city_data(id)
	if cd.is_empty():
		return Vector2(-999.0, -999.0)
	if str(cd.get("anchor", ANCHOR_LATLONG)) == ANCHOR_MAP:
		return _map_xy(cd)
	var uv := MapProjection.to_uv(float(cd.get("lati", 0.0)), float(cd.get("long", 0.0)), _map_cfg())
	return Vector2(uv.x, clampf(uv.y, 0.0, 1.0))


func _draw_map_view() -> void:
	var view := Rect2(Vector2.ZERO, map_view.size)
	map_view.draw_rect(view, MAP_BLANK_OUT)
	var rect := _map_rect()
	var font := get_theme_default_font()
	if rect.size == Vector2.ZERO:
		map_view.draw_string(font, Vector2(12, 24), UiText.t("先选择世界并点「加载参考图…」（图片挂在世界上）"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.76, 0.86))
		return
	var cfg := _map_cfg()
	var period := _map_period()
	var tiles := _visible_tiles(rect, view)
	var band := view.intersection(Rect2(0.0, rect.position.y, view.size.x, rect.size.y))
	if band.size.x > 0.0 and band.size.y > 0.0:
		map_view.draw_rect(band, MAP_BLANK_IN)  # 图带里没有参考图的经度 = 空位
	# 先画图、再叠网格——网格压在参考图之上才看得见
	for k in tiles:
		var r := Rect2(rect.position + Vector2(float(k) * period * rect.size.x, 0.0), rect.size)
		if not r.intersects(view):
			continue
		map_view.draw_texture_rect(map_texture, r, false)
		map_view.draw_rect(r, Color(1, 1, 1, 0.45), false, 1.0)
	for lon in range(-180, 180, 30):
		var u := MapProjection.to_uv(0.0, float(lon), cfg).x
		var prime := lon == 0
		for k in tiles:
			var x := rect.position.x + (u + float(k) * period) * rect.size.x
			if x < view.position.x - 1.0 or x > view.end.x + 1.0:
				continue
			map_view.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y),
					MAP_HANDLE if prime else MAP_GRID, 2.5 if prime else 1.0)
			_draw_map_label(font, Vector2(x + 4, clampf(rect.position.y, 0.0, view.end.y - 20.0) + 18.0),
					_lon_label(lon), MAP_HANDLE if prime else Color(1, 1, 1, 0.92))
	for lat in [-60, -30, 0, 30, 60]:
		var v := MapProjection.to_uv(float(lat), 0.0, cfg).y
		var y := rect.position.y + v * rect.size.y
		if y < view.position.y - 4.0 or y > view.end.y + 4.0:
			continue
		var equator: bool = lat == 0
		map_view.draw_line(Vector2(0.0, y), Vector2(view.size.x, y), MAP_HANDLE if equator else MAP_GRID, 2.5 if equator else 1.0)
		_draw_map_label(font, Vector2(6.0, y - 5.0), _lat_label(lat), MAP_HANDLE if equator else Color(1, 1, 1, 0.92))
	# 城市标记（只画当前世界下的城市，即下拉框里那些）
	for id in _map_cities:
		var uv := _map_drag_uv if (_map_drag == "city" and str(id) == _map_drag_city) else _city_uv(str(id))
		if uv.x < -900.0:
			continue
		var pos := _uv_to_px(uv, rect)
		if not view.grow(40.0).has_point(pos):
			continue
		var locked := str(_city_data(str(id)).get("anchor", ANCHOR_LATLONG)) == ANCHOR_LATLONG
		var is_current := str(id) == map_city_id
		var col: Color = MAP_HANDLE if is_current else (MAP_LOCKED if locked else MAP_CITY)
		var r := 6.0 if is_current else 4.5
		map_view.draw_circle(pos, r, col)
		map_view.draw_arc(pos, r + 1.5, 0, TAU, 24, Color(0, 0, 0, 0.7), 1.5)
		if locked:  # 经纬度锁定的城市：外加一个方框
			map_view.draw_rect(Rect2(pos - Vector2(r + 3.5, r + 3.5), Vector2(2.0 * r + 7.0, 2.0 * r + 7.0)), col, false, 1.0)
		if is_current:
			map_view.draw_arc(pos, 11.0, 0, TAU, 24, Color(MAP_HANDLE, 0.95), 2.0)
		var name := _zh_name("cities", str(id))
		_draw_map_label(font, pos + Vector2(11, -7), name if not name.is_empty() else str(id), col)


func _draw_map_label(font: Font, pos: Vector2, text: String, col: Color) -> void:
	map_view.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.85))
	map_view.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _lon_label(lon: int) -> String:
	if lon == 0:
		return "0°"
	if lon > 0:
		return "%d°E" % lon
	if lon == -180:
		return "180°"
	return "%d°W" % -lon


func _lat_label(lat: int) -> String:
	if lat == 0:
		return UiText.t("0° 赤道")
	return "%d°N" % lat if lat > 0 else "%d°S" % -lat


# —— 画布交互：平移 / 缩放 / 拖线 / 拖城市 / 点击定点 / 点选 ——

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_map_motion((event as InputEventMouseMotion).position)
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mb.pressed:
			_map_zoom_at(mb.position, 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_map_press(mb)
	else:
		_map_release(mb)


func _map_motion(pos: Vector2) -> void:
	var rect := _map_rect()
	if rect.size == Vector2.ZERO:
		return
	match _map_drag:
		"pan":
			_map_drag_moved = maxf(_map_drag_moved, (pos - _map_drag_grab).length())
			_set_pan(_map_drag_start - (pos - _map_drag_grab) / _map_drag_base)
		"prime":
			# 0° 经线跟随鼠标：鼠标处原来的经度保持不变
			var lon_now := MapProjection.from_uv(Vector2(_px_to_uv(pos, rect).x, 0.5), _map_cfg()).y
			_map_drag_center = MapProjection.wrap_long(_map_drag_center + MapProjection.wrap_long(_map_drag_lon - lon_now))
			_map_drag_lon = lon_now
			_map_cfg()["center_long"] = _map_drag_center
			_sync_map_controls(false)
		"equator":
			_apply_equator_window((pos.y - rect.position.y) / rect.size.y, _map_drag_window)
		"city":
			_map_drag_uv = _px_to_uv(pos, rect) + _map_drag_offset
			map_view.queue_redraw()
		_:
			var uv := _px_to_uv(pos, rect)
			_map_hover_in = uv.y >= 0.0 and uv.y <= 1.0
			_map_hover_ll = MapProjection.from_uv(uv, _map_cfg())
			map_view.mouse_default_cursor_shape = Control.CURSOR_DRAG if _map_hit(pos, rect) != "" else Control.CURSOR_ARROW
	_update_map_readout()


func _map_press(mb: InputEventMouseButton) -> void:
	var rect := _map_rect()
	var cfg := _map_cfg()
	if mb.double_click:
		_reset_map_view()
		return
	if _map_pick != "":
		var uv := _px_to_uv(mb.position, rect)
		if _map_pick == "prime":
			# 把点中的一列认作 0° 经线 → 换算出图片中点的经度
			var center := _round2(MapProjection.center_long_for_zero_at(uv.x, cfg))
			cfg["center_long"] = center
			_set_map_pick("")
			_sync_map_controls()
			_set_status(UiText.f("已把该位置设为 0° 经线：中央经线 = %.2f°（记得保存）", [center]))
		else:
			if uv.y < 0.0 or uv.y > 1.0:
				_set_status(UiText.t("请点在参考图的上下缘之间"))
				return
			_apply_equator_window(uv.y, cfg)
			_set_map_pick("")
			_sync_map_controls()
			_set_status(UiText.f("已把该行设为赤道：上缘 %.2f°、下缘 %.2f°（记得保存）", [cfg["lat_top"], cfg["lat_bottom"]]))
		return
	var hit := _map_hit(mb.position, rect)
	if hit.begins_with("city:"):
		_map_drag = "city"
		_map_drag_city = hit.substr(5)
		map_city_id = _map_drag_city
		_select_map_city_pick()
		_map_drag_uv = _city_uv(_map_drag_city)
		_map_drag_offset = _map_drag_uv - _px_to_uv(mb.position, rect)
	elif hit == "prime":
		_map_drag = "prime"
		_map_drag_center = float(cfg["center_long"])
		_map_drag_lon = MapProjection.from_uv(Vector2(_px_to_uv(mb.position, rect).x, 0.5), cfg).y
	elif hit == "equator":
		_map_drag = "equator"
		_map_drag_window = {"lat_top": float(cfg["lat_top"]), "lat_bottom": float(cfg["lat_bottom"]),
			"projection": str(cfg["projection"])}
	else:
		_map_drag = "pan"  # 松开时几乎没动 = 点击定点
		_map_drag_grab = mb.position
		_map_drag_start = _map_pan
		_map_drag_base = rect.size
		_map_drag_moved = 0.0
	map_view.mouse_default_cursor_shape = Control.CURSOR_DRAG
	map_view.queue_redraw()


func _map_release(mb: InputEventMouseButton) -> void:
	var was := _map_drag
	_map_drag = ""
	if was == "pan":
		if _map_drag_moved < 4.0:
			_click_place(_px_to_uv(mb.position, _map_rect()))
	elif was == "prime":
		_map_cfg()["center_long"] = _round2(_map_drag_center)  # 拖动过程不取整，落定才取
		_sync_map_controls(false)
	elif was == "city":
		_place_city_at(_map_drag_city, _map_drag_uv)
	map_view.mouse_default_cursor_shape = Control.CURSOR_ARROW
	map_view.queue_redraw()
	_update_map_readout()


## 鼠标按在什么可拖的东西上："city:<ID>" | "prime" | "equator" | ""。
func _map_hit(pos: Vector2, rect: Rect2) -> String:
	var view := Rect2(Vector2.ZERO, map_view.size)
	var period := _map_period()
	for id in _map_cities:
		var uv := _city_uv(str(id))
		if uv.x > -900.0 and _uv_to_px(uv, rect).distance_to(pos) <= MAP_CITY_RADIUS:
			return "city:" + str(id)
	var cfg := _map_cfg()
	var pu := MapProjection.to_uv(0.0, 0.0, cfg).x
	if pos.y >= rect.position.y - 4.0 and pos.y <= rect.end.y + 4.0:
		for k in _visible_tiles(rect, view):
			var x := rect.position.x + (pu + float(k) * period) * rect.size.x
			if x >= view.position.x and x <= view.end.x and absf(x - pos.x) <= MAP_HANDLE_RADIUS:
				return "prime"
	var ey := rect.position.y + MapProjection.equator_v(cfg) * rect.size.y
	if ey >= view.position.y and ey <= view.end.y and absf(ey - pos.y) <= MAP_HANDLE_RADIUS:
		return "equator"
	return ""


func _map_zoom_at(pos: Vector2, factor: float) -> void:
	var rect := _map_rect()
	if rect.size == Vector2.ZERO:
		return
	var before := _px_to_uv(pos, rect)
	_map_zoom = clampf(_map_zoom * factor, 1.0, MAP_ZOOM_MAX)
	# 鼠标下的那个图上点不动：pan += 缩放前 − 缩放后（同一像素下的归一化坐标差）
	_set_pan(_map_pan + (before - _px_to_uv(pos, _map_rect())))


func _click_place(uv: Vector2) -> void:
	if map_city_id.is_empty():
		_set_status(UiText.t("请先在地图页选择要定位的城市"))
		return
	_place_city_at(map_city_id, uv)


## 把城市锚定到参考图上的这个位置：写城市 JSON（经纬度由当前地图配置换算）；
## 定点依赖地图配置，所以地图配置有未保存改动时一并落盘（只写 map 字段）。
func _place_city_at(id: String, uv: Vector2) -> void:
	if uv.y < 0.0 or uv.y > 1.0:
		_set_status(UiText.t("请点在参考图的上下缘之间"))
		return
	var cfg := _map_cfg()
	var cd := SettingsStore.load_city(id)
	cd["anchor"] = ANCHOR_MAP
	cd["map_x"] = _round4(uv.x)
	cd["map_y"] = _round4(uv.y)
	var ll := MapProjection.from_uv(uv, cfg)
	cd["lati"] = _round2(ll.x)
	cd["long"] = _round2(ll.y)
	var err := SettingsStore.save_city(id, cd)
	if err != OK:
		_set_status(UiText.f("写入失败（%d）", [err]))
		return
	var map_saved := _map_config_dirty()
	_persist_map_config()
	_map_cities[id] = SettingsStore.load_city(id)
	_sync_geo_into_docs(id, cd)
	_update_geo_inputs()
	map_view.queue_redraw()
	var status := UiText.f("已将 %s 定位到图上（换算：纬度 %.2f°、经度 %.2f°）", [id, cd["lati"], cd["long"]])
	if map_saved:
		status += "　·　" + UiText.t("地图配置已一并保存")
	_set_status(status)


func _map_config_dirty() -> bool:
	var snap: Dictionary = _snapshots.get("world:" + current_world_id, {})
	return not (snap.has("map") and JSON.stringify(_map_cfg()) == JSON.stringify(snap["map"]))


# ———————— 工具 ————————

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _split_list(text: String) -> Array:
	var out := []
	for part in text.split(","):
		var p := part.strip_edges()
		if not p.is_empty():
			out.append(p)
	return out


func _join_list(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return str(value) if value != null else ""
	var parts := PackedStringArray()
	for x in value:
		parts.append(str(x))
	return ", ".join(parts)


## 保留两位小数：round(x·100)/100——比按步长取整干净，不会把浮点毛刺写进 JSON。
static func _round2(v: float) -> float:
	var r := roundf(v * 100.0) / 100.0
	return 0.0 if r == 0.0 else r  # 避免写出 "-0.0"


## 图上位置保留四位小数（4096px 宽的图上约 0.4px）。
static func _round4(v: float) -> float:
	var r := roundf(v * 10000.0) / 10000.0
	return 0.0 if r == 0.0 else r


func _set_status(text: String) -> void:
	_status_text = text
	_apply_status()


## 状态栏 = 最近一条状态 + 脏标记（草稿快照机制）。
func _apply_status() -> void:
	var n := _dirty_keys().size()
	status_label.text = _status_text + ("　" + UiText.f("●　有 %d 处未保存改动（关闭时会询问处理）", [n]) if n > 0 else "")
