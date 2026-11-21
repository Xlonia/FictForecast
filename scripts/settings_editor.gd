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

	# 页签中文标题（TabContainer 默认用节点名）
	tabs.set_tab_title(0, "世界")
	tabs.set_tab_title(1, "城市")
	tabs.set_tab_title(2, "本地化")
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
			_save_loc_tab()


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
