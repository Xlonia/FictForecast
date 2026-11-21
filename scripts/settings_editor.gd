extends Window
## 设置编辑器（骨架版）：按《幻想气象局.md》的「世界设置 / 城市设置」骨架，
## 以表单方式修改 JSON（世界/城市）与 YAML（本地化）。
##
## 字段与文件布局已按文档定死；等确切设定给出后，再在此基础上接入引擎
## （时区/历法实际生效、壁纸与气象效果的播放、世界种子进入随机流等）。
## 修改只在点击“保存当前页”时写盘；切换选择会丢弃未保存改动（状态栏有提示）。

var world_ids: Array[String] = []
var city_ids: Array[String] = []
var current_world_id := ""
var current_world := {}
var current_city_id := ""
var current_city := {}
var loc_data := {}

@onready var tabs: TabContainer = $Root/Column/Tabs
@onready var status_label: Label = $Root/Column/Bottom/StatusLabel
@onready var save_btn: Button = $Root/Column/Bottom/SaveBtn

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
@onready var timez_spin: SpinBox = $Root/Column/Tabs/CityTab/Scroll/Form/TimeZoneRow/TimezSpin
@onready var times_pick: OptionButton = $Root/Column/Tabs/CityTab/Scroll/Form/SystemRow/TimesPick
@onready var calendar_pick: OptionButton = $Root/Column/Tabs/CityTab/Scroll/Form/SystemRow/CalendarPick
@onready var wall_rows: VBoxContainer = $Root/Column/Tabs/CityTab/Scroll/Form/WallSection/Rows
@onready var wall_add_btn: Button = $Root/Column/Tabs/CityTab/Scroll/Form/WallSection/AddBtn
@onready var effect_rows: VBoxContainer = $Root/Column/Tabs/CityTab/Scroll/Form/EffectSection/Rows
@onready var effect_add_btn: Button = $Root/Column/Tabs/CityTab/Scroll/Form/EffectSection/AddBtn

# —— 本地化页 ——
@onready var loc_rows: VBoxContainer = $Root/Column/Tabs/LocTab/LocScroll/LocRows
@onready var loc_group_edit: LineEdit = $Root/Column/Tabs/LocTab/LocAdd/LocGroupEdit
@onready var loc_key_edit: LineEdit = $Root/Column/Tabs/LocTab/LocAdd/LocKeyEdit
@onready var loc_value_edit: LineEdit = $Root/Column/Tabs/LocTab/LocAdd/LocValueEdit
@onready var loc_add_btn: Button = $Root/Column/Tabs/LocTab/LocAdd/LocAddBtn

# —— 世界页参数（m2：波动/日照/现象分布）——
@onready var w_axial_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WAxialSpin
@onready var w_day_hours_spin: SpinBox = $Root/Column/Tabs/WorldTab/Form/ParamSection/Grid/WDayHoursSpin
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
	_refresh_worlds()
	_refresh_cities()
	var loc := SettingsStore.load_localization()
	loc_data = loc.data
	for e in loc.errors:
		_set_status("本地化文件警告：%s" % e)
	_select_world(world_ids[0] if not world_ids.is_empty() else "")
	_select_city(city_ids[0] if not city_ids.is_empty() else "")
	_rebuild_loc_rows()

	world_pick.item_selected.connect(_on_world_picked)
	new_btn.pressed.connect(_on_world_created)
	time_add_btn.pressed.connect(_on_add_base_time)
	date_add_btn.pressed.connect(_on_add_base_date)
	city_pick.item_selected.connect(_on_city_picked)
	world_ref_pick.item_selected.connect(_on_city_world_ref)
	times_pick.item_selected.connect(_on_times_picked)
	calendar_pick.item_selected.connect(_on_calendar_picked)
	name_edit.text_changed.connect(_on_city_name_changed)
	wall_add_btn.pressed.connect(_on_add_wallpaper)
	effect_add_btn.pressed.connect(_on_add_effect)
	loc_add_btn.pressed.connect(_on_loc_add)
	save_btn.pressed.connect(_on_save)

	# 世界参数 SpinBox → current_world 字段实时写入（保存时随世界 JSON 落盘）
	for pair in [[w_axial_spin, "axial_tilt_deg"], [w_day_hours_spin, "day_hours"],
			[w_temp_sigma_spin, "month_temp_sigma"], [w_smooth_spin, "month_smoothing"],
			[w_total_spin, "monthly_total_strength"], [w_spread_spin, "phenomena_spread_days"],
			[w_comp_spin, "annual_compensation"]]:
		var spin: SpinBox = pair[0]
		var key: String = pair[1]
		spin.value_changed.connect(func(v: float) -> void: current_world[key] = v)

	phen_shape_type_pick.add_item("椭圆 ellipse", 0)
	phen_shape_type_pick.set_item_metadata(0, "ellipse")
	phen_shape_type_pick.select(0)
	for pair in [["any", "任意 any"], ["land", "陆地 land"], ["sea", "海洋 sea"], ["coast", "海岸 coast"]]:
		phen_where_pick.add_item(pair[1], 0)
		phen_where_pick.set_item_metadata(phen_where_pick.item_count - 1, pair[0])
	phen_where_pick.select(0)

	_refresh_phen_worlds()
	_select_phen_world(world_ids[0] if not world_ids.is_empty() else "")

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

	# 可关闭的系统窗口：从主程序打开 → 真关闭并释放；独立打开（批处理）→ 退出
	close_requested.connect(_on_close_requested)

	# 页签中文标题（TabContainer 默认用节点名）
	tabs.set_tab_title(0, "世界")
	tabs.set_tab_title(1, "城市")
	tabs.set_tab_title(2, "现象")
	tabs.set_tab_title(3, "本地化")
	# 开发辅助：FF_EDITOR_TAB=0/1/2 启动时定位到指定页签
	var env_tab := OS.get_environment("FF_EDITOR_TAB")
	if env_tab.is_valid_int():
		tabs.current_tab = clampi(env_tab.to_int(), 0, tabs.get_tab_count() - 1)


# ———————— 世界页 ————————

func _refresh_worlds() -> void:
	world_ids = SettingsStore.list_world_ids()
	world_pick.clear()
	for id in world_ids:
		var disp := SettingsStore.world_display_name(id)
		world_pick.add_item(id if disp.is_empty() else "%s（%s）" % [id, disp], 0)
		world_pick.set_item_metadata(world_pick.item_count - 1, id)
	if world_ids.is_empty():
		world_pick.add_item("（Worlds/ 下没有世界文件）", 0)
		world_pick.set_item_disabled(0, true)


func _select_world(id: String) -> void:
	current_world_id = id
	current_world = SettingsStore.load_world(id) if id != "" else {}
	for i in world_pick.item_count:
		if str(world_pick.get_item_metadata(i)) == id:
			world_pick.select(i)
			break
	seed_edit.text = str(current_world.get("seed", ""))
	seed_edit.editable = id != ""
	for sp in [w_axial_spin, w_day_hours_spin, w_temp_sigma_spin, w_smooth_spin,
			w_total_spin, w_spread_spin, w_comp_spin]:
		sp.editable = id != ""
	w_axial_spin.value = float(current_world.get("axial_tilt_deg", 23.44))
	w_day_hours_spin.value = float(current_world.get("day_hours", 24.0))
	w_temp_sigma_spin.value = float(current_world.get("month_temp_sigma", 2.2))
	w_smooth_spin.value = float(current_world.get("month_smoothing", 0.5))
	w_total_spin.value = float(current_world.get("monthly_total_strength", 0.0))
	w_spread_spin.value = float(current_world.get("phenomena_spread_days", 7.0))
	w_comp_spin.value = float(current_world.get("annual_compensation", 0.0))
	_rebuild_time_rows()
	_rebuild_date_rows()


func _on_world_picked(index: int) -> void:
	_select_world(str(world_pick.get_item_metadata(index)))


func _on_world_created() -> void:
	var id := new_id_edit.text.strip_edges()
	if id.is_empty():
		_set_status("请先在右侧输入新世界 ID")
		return
	if id.contains("/") or id.contains("\\") or id.contains(":") or id.contains("."):
		_set_status("ID 不能包含 / \\ : .")
		return
	if world_ids.has(id):
		_set_status("世界 %s 已存在" % id)
		return
	SettingsStore.save_world(id, SettingsStore.WORLD_DEFAULTS.duplicate(true))
	_ensure_loc_group("worlds")[id] = id
	_refresh_worlds()
	_select_world(id)
	new_id_edit.text = ""
	_set_status("已创建 Worlds/%s.json（尚未保存本地化改名）" % id)


func _rebuild_time_rows() -> void:
	_clear_children(time_rows)
	if current_world.is_empty():
		return
	var arr: Array = current_world.get("base_times", [])
	for entry in arr:
		var e: Dictionary = entry
		time_rows.add_child(_make_base_row(e, "offset_minutes", "偏差分钟", -1440, 1440,
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
		date_rows.add_child(_make_base_row(e, "offset_days", "差天数", -3650000, 3650000,
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
		var disp := SettingsStore.city_display_name(id)
		city_pick.add_item(id if disp.is_empty() else "%s（%s）" % [id, disp], 0)
		city_pick.set_item_metadata(city_pick.item_count - 1, id)
	if city_ids.is_empty():
		city_pick.add_item("（Climate/ 下没有城市 CSV）", 0)
		city_pick.set_item_disabled(0, true)


func _select_city(id: String) -> void:
	current_city_id = id
	current_city = SettingsStore.load_city(id) if id != "" else {}
	for i in city_pick.item_count:
		if str(city_pick.get_item_metadata(i)) == id:
			city_pick.select(i)
			break
	var enabled := id != ""
	_set_city_form_enabled(enabled)
	name_edit.text = SettingsStore.city_display_name(id)
	long_spin.value = float(current_city.get("long", 0.0))
	lati_spin.value = float(current_city.get("lati", 0.0))
	alti_spin.value = float(current_city.get("alti", 0.0))
	timez_spin.value = float(int(current_city.get("timez", 0)))
	_refresh_world_ref_pick()
	_rebuild_system_picks()
	_rebuild_dict_rows(wall_rows, "wallpaper", "壁纸路径，逗号分隔")
	_rebuild_dict_rows(effect_rows, "effects", "效果标识，逗号分隔")


func _form_controls() -> Array:
	return [world_ref_pick, name_edit, long_spin, lati_spin, alti_spin, timez_spin,
			times_pick, calendar_pick, wall_add_btn, effect_add_btn]


func _set_city_form_enabled(enabled: bool) -> void:
	for c in _form_controls():
		if c is LineEdit or c is SpinBox:
			c.editable = enabled
		else:
			c.disabled = not enabled


func _on_city_picked(index: int) -> void:
	_select_city(str(city_pick.get_item_metadata(index)))


func _refresh_world_ref_pick() -> void:
	world_ref_pick.clear()
	world_ref_pick.add_item("（未指定）", 0)
	world_ref_pick.set_item_metadata(0, "")
	for i in world_ids.size():
		var id: String = world_ids[i]
		var disp := SettingsStore.world_display_name(id)
		world_ref_pick.add_item(id if disp.is_empty() else "%s（%s）" % [id, disp], 0)
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


func _rebuild_system_picks() -> void:
	var w := {}
	var wid: String = str(current_city.get("world", ""))
	if wid != "" and world_ids.has(wid):
		w = SettingsStore.load_world(wid)
	_fill_system_pick(times_pick, w.get("base_times", []), "（未指定 → UTC）",
			str(current_city.get("times", "")), "分钟")
	_fill_system_pick(calendar_pick, w.get("base_dates", []), "（未指定 → 公历）",
			str(current_city.get("calendar", "")), "天")


func _fill_system_pick(pick: OptionButton, arr: Array, empty_label: String,
		current_id: String, unit: String) -> void:
	pick.clear()
	pick.add_item(empty_label, 0)
	pick.set_item_metadata(0, "")
	for i in arr.size():
		var e: Dictionary = arr[i]
		var eid := str(e.get("id", ""))
		var shown := eid if not eid.is_empty() else "（未命名）"
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
	if current_city_id.is_empty():
		return
	_ensure_loc_group("cities")[current_city_id] = text


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
	_rebuild_dict_rows(wall_rows, "wallpaper", "壁纸路径，逗号分隔")


func _on_add_effect() -> void:
	if current_city.is_empty():
		return
	_ensure_city_dict("effects")[""] = []
	_rebuild_dict_rows(effect_rows, "effects", "效果标识，逗号分隔")


func _ensure_city_dict(field: String) -> Dictionary:
	if not current_city.has(field) or typeof(current_city[field]) != TYPE_DICTIONARY:
		current_city[field] = {}
	return current_city[field]


# ———————— 本地化页 ————————

func _rebuild_loc_rows() -> void:
	_clear_children(loc_rows)
	for group in loc_data:
		var entries: Dictionary = loc_data[group]
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		var title := Label.new()
		title.text = "%s:" % str(group)
		title.modulate = Color(0.75, 0.8, 0.88)
		section.add_child(title)
		for key in entries:
			section.add_child(_make_loc_row(group, str(key)))
		loc_rows.add_child(section)


func _make_loc_row(group: String, key: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(200, 0)
	key_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var value_edit := LineEdit.new()
	value_edit.text = str(loc_data[group].get(key, ""))
	value_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_edit.text_changed.connect(func(t: String) -> void:
		loc_data[group][key] = t)
	var del := Button.new()
	del.text = "✕"
	del.pressed.connect(func() -> void:
		loc_data[group].erase(key)
		_rebuild_loc_rows())
	box.add_child(key_label)
	box.add_child(value_edit)
	box.add_child(del)
	return box


func _on_loc_add() -> void:
	var group := loc_group_edit.text.strip_edges()
	var key := loc_key_edit.text.strip_edges()
	if group.is_empty() or key.is_empty():
		_set_status("添加本地化条目需要组名与键名")
		return
	_ensure_loc_group(group)[key] = loc_value_edit.text
	loc_key_edit.text = ""
	loc_value_edit.text = ""
	_rebuild_loc_rows()


# ———————— 保存 ————————

func _on_save() -> void:
	match tabs.current_tab:
		0:
			_save_world_tab()
		1:
			_save_city_tab()
		2:
			_save_phen_tab()
		3:
			_save_loc_tab()


func _save_phen_tab() -> void:
	if phen_world_id.is_empty():
		_set_status("没有可保存的世界现象")
		return
	var err := SettingsStore.save_phenomena(phen_world_id, phen_data)
	if err == OK:
		SettingsStore.save_localization(loc_data)
		_refresh_phen_worlds()
		_set_status("已保存 Worlds/%s.phenomena.json 与本地化" % phen_world_id)
	else:
		_set_status("保存失败（%d）" % err)


## 可关闭的系统窗口：独立打开（批处理/主场景）→ 退出；从主程序打开 → 真关闭并释放。
func _on_close_requested() -> void:
	if get_parent() == get_tree().root:
		get_tree().quit()
	else:
		queue_free()


func _save_world_tab() -> void:
	if current_world_id.is_empty():
		_set_status("没有可保存的世界")
		return
	current_world["seed"] = seed_edit.text.strip_edges()
	var err := SettingsStore.save_world(current_world_id, current_world)
	if err == OK:
		SettingsStore.save_localization(loc_data)
		_refresh_worlds()
		_select_world(current_world_id)
		_set_status("已保存 Worlds/%s.json 与本地化" % current_world_id)
	else:
		_set_status("保存失败（%d）" % err)


func _save_city_tab() -> void:
	if current_city_id.is_empty():
		_set_status("没有可保存的城市")
		return
	current_city["long"] = long_spin.value
	current_city["lati"] = lati_spin.value
	current_city["alti"] = alti_spin.value
	current_city["timez"] = int(timez_spin.value)
	_ensure_loc_group("cities")[current_city_id] = name_edit.text
	var err := SettingsStore.save_city(current_city_id, current_city)
	if err == OK:
		SettingsStore.save_localization(loc_data)
		_refresh_cities()
		_select_city(current_city_id)
		_set_status("已保存 Cities/%s.json 与本地化" % current_city_id)
	else:
		_set_status("保存失败（%d）" % err)


func _save_loc_tab() -> void:
	var err := SettingsStore.save_localization(loc_data)
	if err == OK:
		_set_status("已保存 res://Localization/zh.yaml")
	else:
		_set_status("保存失败（%d）" % err)


# ———————— 现象页 ————————

func _loc_value(group: String, key: String) -> String:
	if loc_data.has(group) and typeof(loc_data[group]) == TYPE_DICTIONARY:
		return str(loc_data[group].get(key, ""))
	return ""


func _refresh_phen_worlds() -> void:
	phen_world_pick.clear()
	for id in world_ids:
		var disp := SettingsStore.world_display_name(id)
		phen_world_pick.add_item(id if disp.is_empty() else "%s（%s）" % [id, disp], 0)
		phen_world_pick.set_item_metadata(phen_world_pick.item_count - 1, id)
	if world_ids.is_empty():
		phen_world_pick.add_item("（Worlds/ 下没有世界文件）", 0)
		phen_world_pick.set_item_disabled(0, true)


func _select_phen_world(id: String) -> void:
	phen_world_id = id
	phen_data = SettingsStore.load_phenomena(id) if id != "" else {}
	for i in phen_world_pick.item_count:
		if str(phen_world_pick.get_item_metadata(i)) == id:
			phen_world_pick.select(i)
			break
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
		var shown := eid if not eid.is_empty() else "（未命名）"
		phen_pick.add_item(shown if disp.is_empty() else "%s（%s）" % [shown, disp], 0)
		phen_pick.set_item_metadata(i, i)
	if arr.is_empty():
		phen_pick.add_item("（该世界暂无气候现象）", 0)
		phen_pick.set_item_disabled(0, true)
		phen_index = -1
	else:
		if phen_index < 0 or phen_index >= arr.size():
			phen_index = 0
		phen_pick.select(phen_index)
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


func _phen_set(key: String, v) -> void:
	var e := _current_phen()
	if not e.is_empty():
		e[key] = v


func _phen_set_rule(key: String, v) -> void:
	var e := _current_phen()
	if e.is_empty():
		return
	if not e.has("rules") or typeof(e["rules"]) != TYPE_DICTIONARY:
		e["rules"] = {}
	e["rules"][key] = v


func _phen_set_shape(key: String, v) -> void:
	var e := _current_phen()
	if e.is_empty():
		return
	if not e.has("shape") or typeof(e["shape"]) != TYPE_DICTIONARY:
		e["shape"] = {"type": "ellipse", "axes_km": [1000.0, 400.0]}
	e["shape"][key] = v


func _phen_set_axis(idx: int, v: float) -> void:
	var e := _current_phen()
	if e.is_empty():
		return
	_phen_set_shape("axes_km", e.get("shape", {}).get("axes_km", [1000.0, 400.0]))
	var axes: Array = e["shape"]["axes_km"]
	while axes.size() < 2:
		axes.append(1000.0)
	axes[idx] = v


func _phen_set_duration(idx: int, v: float) -> void:
	var e := _current_phen()
	if e.is_empty():
		return
	if not e.has("duration_hours") or typeof(e["duration_hours"]) != TYPE_ARRAY:
		e["duration_hours"] = [48.0, 96.0]
	while (e["duration_hours"] as Array).size() < 2:
		(e["duration_hours"] as Array).append(0.0)
	e["duration_hours"][idx] = v


func _phen_set_origin(key: String, v) -> void:
	var e := _current_phen()
	if e.is_empty():
		return
	if not e.has("origin") or typeof(e["origin"]) != TYPE_DICTIONARY:
		e["origin"] = {}
	e["origin"][key] = v


func _phen_set_origin_season(idx: int, v: int) -> void:
	var e := _current_phen()
	if e.is_empty():
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
	if e.is_empty():
		return
	_ensure_loc_group("phenomena")[str(e.get("id", ""))] = text


func _on_phen_created() -> void:
	var id := phen_new_id.text.strip_edges()
	if phen_world_id.is_empty():
		_set_status("请先选择世界")
		return
	if id.is_empty():
		_set_status("请先输入新现象 ID")
		return
	if id.contains("/") or id.contains("\\") or id.contains(":") or id.contains("."):
		_set_status("ID 不能包含 / \\ : .")
		return
	for e in _phen_list():
		if str(e.get("id", "")) == id:
			_set_status("现象 %s 已存在" % id)
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
	_set_status("已创建现象 %s（记得保存）" % id)


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
		type_pick.add_item(pair[1], 0)
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
	with_edit.placeholder_text = "对方现象ID，逗号分隔"
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
		lab.text = d[1]
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


# ———————— 工具 ————————

func _ensure_loc_group(group: String) -> Dictionary:
	if not loc_data.has(group) or typeof(loc_data[group]) != TYPE_DICTIONARY:
		loc_data[group] = {}
	return loc_data[group]


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


func _set_status(text: String) -> void:
	status_label.text = text
