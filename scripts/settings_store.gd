class_name SettingsStore
extends RefCounted
## 城市与世界的配置存取（JSON）+ 本地化（MiniYaml）。
##
## 目录约定（随工程走；导出后迁移到用户目录是后续工作）：
##   res://Worlds/<世界ID>.json   世界设置：seed / base_times / base_dates
##   res://Cities/<城市ID>.json   城市设置：long/lati/alti/times/timez/calendar/wallpaper/effects
##                                （城市ID = Climate/<城市ID>.csv 的文件名；name 走本地化 YAML）
##   res://Localization/zh.yaml   本地化：组 cities / worlds 下的 键 → 显示名
##
## 字段骨架严格对应《幻想气象局.md》的「城市设置」「世界设置」两节。
## 默认值策略（文档口径）：times/calendar 非法或留空 → UTC / 公历；
## world 字段为本次新增的骨架决定（城市归属哪个世界，文档未明列但结构上必需）。

const WORLDS_DIR := "res://Worlds"
const CITIES_DIR := "res://Cities"
const LOC_FILE := "res://Localization/zh.yaml"

const WORLD_DEFAULTS := {
	"seed": "",
	"base_times": [],  # [{ "id": String, "offset_minutes": int }] 基准时间（时区偏差分钟，投射到 0° 经度）
	"base_dates": [],  # [{ "id": String, "offset_days": int }] 基准日期（与现实日期差天数）
}

const CITY_DEFAULTS := {
	"world": "",
	"long": 0.0,
	"lati": 0.0,
	"alti": 0.0,
	"times": "",     # 引用世界 base_times 的 id；非法/空 → UTC
	"timez": 0,      # 时区偏差（分钟）
	"calendar": "",  # 引用世界 base_dates 的 id；非法/空 → 公历
	"wallpaper": {}, # { 系列id: [路径, …] }
	"effects": {},   # { 系列id: [标识, …] }
}

static var _loc_cache := {}  # 本地化文件路径 → 数据（编辑器保存时刷新）


## 创建目录与默认文件（已存在则不覆盖）。
static func ensure_defaults() -> void:
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
	DirAccess.make_dir_recursive_absolute(CITIES_DIR)
	DirAccess.make_dir_recursive_absolute(LOC_FILE.get_base_dir())
	if not FileAccess.file_exists(WORLDS_DIR.path_join("default.json")):
		save_world("default", {
			"seed": "",
			"base_times": [{"id": "utc", "offset_minutes": 0}],
			"base_dates": [{"id": "gregorian", "offset_days": 0}],
		})
	if not FileAccess.file_exists(LOC_FILE):
		var cities := {}
		for id in list_city_ids():
			cities[id] = id.capitalize()
		save_localization({"cities": cities, "worlds": {"default": "现实世界"}})


static func list_city_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open("res://Climate")
	if dir != null:
		for f in dir.get_files():
			if f.get_extension().to_lower() == "csv":
				ids.append(f.get_basename())
	ids.sort()
	return ids


static func list_world_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(WORLDS_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.get_extension().to_lower() == "json":
				ids.append(f.get_basename())
	ids.sort()
	return ids


static func load_world(id: String) -> Dictionary:
	return _load_json(WORLDS_DIR.path_join(id + ".json"), WORLD_DEFAULTS)


static func save_world(id: String, data: Dictionary) -> Error:
	return _save_json(WORLDS_DIR.path_join(id + ".json"), data)


static func load_city(id: String) -> Dictionary:
	return _load_json(CITIES_DIR.path_join(id + ".json"), CITY_DEFAULTS)


static func save_city(id: String, data: Dictionary) -> Error:
	return _save_json(CITIES_DIR.path_join(id + ".json"), data)


static func load_localization() -> Dictionary:
	if _loc_cache.has(LOC_FILE):
		return {"data": _loc_cache[LOC_FILE], "errors": []}
	var text := ""
	if FileAccess.file_exists(LOC_FILE):
		var f := FileAccess.open(LOC_FILE, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
	var res := MiniYaml.parse(text)
	_loc_cache[LOC_FILE] = res.data
	return res


static func save_localization(data: Dictionary) -> Error:
	var f := FileAccess.open(LOC_FILE, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(MiniYaml.dumps(data))
	_loc_cache[LOC_FILE] = data.duplicate(true)
	return OK


static func invalidate_localization_cache() -> void:
	_loc_cache.clear()


## 城市显示名：本地化 cities.<id>，缺失返回 ""（调用方自行回退）。
static func city_display_name(id: String) -> String:
	var res := load_localization()
	var cities: Dictionary = res.data.get("cities", {})
	return str(cities.get(id, ""))


## 世界显示名：本地化 worlds.<id>，缺失返回 ""。
static func world_display_name(id: String) -> String:
	var res := load_localization()
	var worlds: Dictionary = res.data.get("worlds", {})
	return str(worlds.get(id, ""))


static func _load_json(path: String, defaults: Dictionary) -> Dictionary:
	var out := {}
	for k in defaults:
		out[k] = defaults[k]
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for k in defaults:
		if parsed.has(k) and _type_ok(parsed[k], defaults[k]):
			out[k] = parsed[k]
	return out


static func _save_json(path: String, data: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t") + "\n")
	return f.get_error()


static func _type_ok(v, ref) -> bool:
	match typeof(ref):
		TYPE_FLOAT, TYPE_INT:
			return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
		TYPE_STRING:
			return typeof(v) == TYPE_STRING
		TYPE_DICTIONARY:
			return typeof(v) == TYPE_DICTIONARY
		TYPE_ARRAY:
			return typeof(v) == TYPE_ARRAY
	return true
