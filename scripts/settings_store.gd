class_name SettingsStore
extends RefCounted
## 城市与世界的配置存取（JSON）+ 本地化（MiniYaml）+ 软件偏好。
##
## 目录约定（随工程走；导出后迁移到用户目录是后续工作）：
##   res://Worlds/<世界ID>.json   世界设置：seed / base_times / base_dates / map（参考图与投影）
##   res://Cities/<城市ID>.json   城市设置：long/lati/alti/anchor/map_x/map_y/times/timez/calendar/wallpaper/effects
##                                （城市ID = Climate/<城市ID>.csv 的文件名；name 走本地化 YAML）
##   res://Localization/<语言>.yaml  本地化：一语言一文件；组 cities / worlds / phenomena 下的 键 → 显示名，
##                                组 ui 下的 中文原文 → 界面译文（见 UiText）
##   res://Localization/<语言>.json  语言定义：name（语言自己的名字）/ font（该语言用的字体，留空不覆盖）
##   user://preferences.json      软件偏好（凌驾于世界/城市设置之上；每台机器每个用户一份）
##
## 字段骨架严格对应《幻想气象局.md》的「城市设置」「世界设置」两节。
## 默认值策略（文档口径）：times/calendar 非法或留空 → UTC / 公历；
## world 字段为本次新增的骨架决定（城市归属哪个世界，文档未明列但结构上必需）。
## zh 是显示名的基准语言：其它语言缺条目时回退到 zh（编辑器里录入的名字）。

const DEFAULT_LANG := "zh"
const THEME_PATH := "res://theme/main_theme.tres"

# ———————— 数据根（m3.11 批复：导出版数据外置）——————
## 运行期解析的数据根目录（Climate/Worlds/Cities/Localization/Maps 都挂在它下面）：
##   1. 命令行 --data-dir=<路径>（最高优先，打包/多存档场景）
##   2. 环境变量 FF_DATA_DIR（开发/测试钩子）
##   3. 开发环境（工程内跑，OS.has_feature("editor")）→ res://，行为与 0.0.1 完全一致
##   4. 导出版 → exe 同级的 data/（package_export.py 把数据复制到那里；pck 里不带数据）
## 注意：代码/场景/主题仍在 pck 里（导出后只读）——可改的只有 data/ 下的数据。
static var _data_root := ""  # 计算缓存（默认根只算一次；env/参数每次都查，方便测试覆盖）


static func data_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-dir="):
			return arg.substr("--data-dir=".length())
	var env := OS.get_environment("FF_DATA_DIR")
	if not env.is_empty():
		return env
	if _data_root.is_empty():
		_data_root = "res://" if OS.has_feature("editor") \
				else OS.get_executable_path().get_base_dir().path_join("data")
	return _data_root


static func worlds_dir() -> String:
	return data_root().path_join("Worlds")


static func cities_dir() -> String:
	return data_root().path_join("Cities")


static func climate_dir() -> String:
	return data_root().path_join("Climate")


static func maps_dir() -> String:
	return data_root().path_join("Maps")


static func loc_dir() -> String:
	return data_root().path_join("Localization")


static func loc_file() -> String:
	return loc_dir().path_join("zh.yaml")


## res:// 开头的数据路径 → 数据根下的真实文件（导出版数据外置后，老配置里的
## "res://Maps/..." 依然指向 data/Maps/...）；其余原样返回。
static func resolve_media_path(path: String) -> String:
	return data_root().path_join(path.substr("res://".length())) if path.begins_with("res://") else path


## 转成操作系统绝对路径（FileAccess/DirAccess/copy 等需要真路径的场景；
## res:// 与 user:// 走引擎翻译，其余原样）。
static func os_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path


## 数据目录可写性（m3.12 批复）：写删一个探针文件实测。不缓存结果——
## 状态栏每次刷新都重测（代价是一次小文件读写，只在低频路径调用）。
static func data_writable() -> bool:
	var probe := data_root().path_join(".write_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(probe)
	return true

const WORLD_DEFAULTS := {
	"seed": "",
	"base_times": [],  # [{ "id": String, "offset_minutes": int }] 基准时间（时区偏差分钟，投射到 0° 经线）
	"base_dates": [],  # [{ "id": String, "offset_days": int }] 基准日期（与现实日期差天数）
	# —— 波动与日照参数（m2 批复：参数摆位，数值先给默认，具体定值后续再调）——
	"axial_tilt_deg": 23.44,     # 地轴倾斜角：日照随纬度/季节分布的基础
	"day_hours": 24.0,           # 一日小时数（自定义世界昼夜基准）
	"month_temp_sigma": 2.2,     # 月内每日温度波动幅度 σ（℃）——“这个月每天正负多少度”
	"month_smoothing": 0.5,      # 月内噪音平滑度 0..1——“让它稳定或者平滑一些”
	"monthly_total_strength": 0.0,   # 月总量对账强度 0..1——“凑齐降水和月积温”
	"phenomena_spread_days": 7.0,    # 现象出现日期离散（正态 σ·天）——“分布系数由用户来调整”
	"annual_compensation": 0.0,      # 年度补偿强度 0..1——异常雨热三步中和的 AB/B 步骤（引擎未实装，先摆位）
	"map": {},  # 世界参考图与投影 { image, projection, lon_span, lat_top, lat_bottom, center_long }——骨架见 MapProjection.DEFAULTS
}

## 软件偏好（《幻想气象局.md》「软件系统设置」）。文件：user://preferences.json。
const PREFS_DEFAULTS := {
	"default_city": "",       # 偏好城市：启动时默认展示的城市 ID；留空 = 上次展示的城市
	"last_city": "",          # 上次展示的城市 ID（程序自动记录，启动时用它回填）
	"ui_lang": "zh",          # 界面语言：读 Localization/<语言>.yaml 的 ui 组，缺译文回退中文原文
	"city_name_lang": "zh",   # 城市名称语言：读 Localization/<语言>.yaml 的 cities 组，缺条目回退 zh
	"city_sub_lang": "en",    # 城市副标题语言：主名旁边的小字；留空 = 不显示（0.0.1 收官批复：默认英语）
	"map_import_copy": true,  # 导入参考图时复制到工程 Maps/<世界>/（世界文件夹整体拷走即可分享）
	"panel_opacity": 0.9,     # 界面背景不透明度 0..1（1 = 完全不透明）
}

const ANCHOR_LATLONG := "latlong"  # 经纬度为准：图上位置随地图配置移动
const ANCHOR_MAP := "map"          # 图上位置为准：经纬度由地图配置换算（新城市默认）

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
	# 坐标锚定方式（m3.8 / 收官批复：新城市默认锚定图上位置——拖到哪就是哪）：
	#   latlong = 经纬度为准（输入框锁定）——在图上的位置随世界地图配置移动
	#   map     = 参考图上的位置为准——调整 0° 经线 / 赤道 / 投影时城市不跑位，经纬度由地图配置换算
	"anchor": "map",
	"map_x": 0.0,    # anchor=map：城市在参考图上的归一化位置（0..1，左上为原点）
	"map_y": 0.0,
}

## 编辑器单实例锁（0.0.1 收官批复）：文件里记 PID；进程死了锁自动作废。
const EDITOR_LOCK_FILE := "user://editor.lock"

# ———————— 标准现实语言与同类文字回退链（m3.10 批复）——————
## 防止自设语言代码混乱、互相不能互通：主要现实语言的预设地名 yaml 随程序发布
## （Localization/<代码>.yaml + <代码>.json），新建城市/世界的地名键自动补进所有标准语言（留空）。
## 留空的键按**同类文字**回退链替补；虚构/自定义语言不在类里，只回退 zh。
const SCRIPT_CLASSES := {
	"hanzi": ["zh", "ja", "ko", "yue"],                     # 汉字类：留空互相替补，优先汉语
	"latin": ["de", "it", "es", "en", "fr", "pt", "nl",     # 拉丁文类（批复优先顺序）：
		"pl", "sv", "ro", "id", "vi", "tl", "tr"],
	"cyrillic": ["ru", "uk", "sr"],                         # 西里尔文类：优先俄语
}
# 注：印地语(hi)、乌尔都语(ur) 两种文字体系独立，批复未归类——不在类链里，只回退 zh。


## 查名顺序：语言自己 → 同类文字（按批复优先序）→ zh（显示名基准）→ 无（调用方回退 id）。
static func fallback_chain(lang: String) -> Array[String]:
	var out: Array[String] = [lang]
	for cls in SCRIPT_CLASSES:
		var arr: Array = SCRIPT_CLASSES[cls]
		if arr.has(lang):
			for code in arr:
				if code != lang and not out.has(code):
					out.append(code)
			break
	if not out.has(DEFAULT_LANG):
		out.append(DEFAULT_LANG)
	return out


## 地名查找（城市/世界显示名）：沿回退链找第一个非空的值；全空返回 ""（调用方自行回退 id）。
## 链上每级都读**生效**本地化（散文件 + 内容包键级合并）。
static func _loc_lookup(group: String, key: String, lang: String) -> String:
	for code in fallback_chain(lang):
		var entries: Dictionary = load_language_merged(code).get(group, {})
		var v := str(entries.get(key, ""))
		if not v.is_empty():
			return v
	return ""


## 新建城市/世界的地名键：补进所有标准现实语言的 yaml（留空 = 按回退链替补）。
## zh 不补（实名由调用方写进 zh 表）；幻想/自定义语言不补——不与虚构语言混写。
## 幂等：已有该键（含空值）的语言文件不动。
static func seed_standard_name(group: String, key: String) -> void:
	for cls in SCRIPT_CLASSES:
		for code in SCRIPT_CLASSES[cls]:
			if code == DEFAULT_LANG:
				continue
			var res := load_localization_file(loc_path(code))
			var entries: Dictionary = res.data.get(group, {})
			if entries.has(key):
				continue
			if typeof(res.data.get(group, null)) != TYPE_DICTIONARY:
				res.data[group] = {}
			(res.data[group] as Dictionary)[key] = ""
			save_localization_file(loc_path(code), res.data)

## 语言定义（《幻想气象局.md》「自定义语言」：“一个加载字体的 json”）。文件：Localization/<语言代码>.json。
const LANG_DEF_DEFAULTS := {
	"name": "",   # 语言自己的名字（下拉框显示用；留空显示语言代码）
	"font": "",   # 该语言的字体文件路径；留空 = 不覆盖字体。虚构语言 = Unicode 原文的字体映射
}

static var _loc_cache := {}  # 本地化文件路径 → 数据（编辑器保存时刷新）

static var _prefs_file := ""  # 偏好文件路径缓存；开发辅助 FF_PREFS_FILE 可重定向（测试不污染真实偏好）

static var _font_cache := {}  # 字体路径 → FontFile（加载失败为 null）

static var _base_font: Font   # 主题原本的默认字体（语言字体缺字时的回退）


## 偏好文件路径：默认 user://preferences.json。
static func prefs_path() -> String:
	if _prefs_file.is_empty():
		var env := OS.get_environment("FF_PREFS_FILE")
		_prefs_file = env if not env.is_empty() else "user://preferences.json"
	return _prefs_file


static func load_preferences() -> Dictionary:
	var out := _load_json(prefs_path(), PREFS_DEFAULTS)
	out["panel_opacity"] = clampf(float(out["panel_opacity"]), 0.0, 1.0)
	return out


static func save_preferences(data: Dictionary) -> Error:
	return _save_json(prefs_path(), data)


## 创建目录与默认文件（已存在则不覆盖）。
static func ensure_defaults() -> void:
	DirAccess.make_dir_recursive_absolute(worlds_dir())
	DirAccess.make_dir_recursive_absolute(cities_dir())
	DirAccess.make_dir_recursive_absolute(loc_file().get_base_dir())
	if not FileAccess.file_exists(worlds_dir().path_join("default.json")):
		save_world("default", {
			"seed": "",
			"base_times": [{"id": "utc", "offset_minutes": 0}],
			"base_dates": [{"id": "gregorian", "offset_days": 0}],
		})
	if not FileAccess.file_exists(loc_file()):
		var cities := {}
		for id in list_city_ids():
			cities[id] = id.capitalize()
		save_localization({"cities": cities, "worlds": {"default": "现实世界"}})


static func list_city_ids() -> Array[String]:
	var ids := _dir_csv_ids(climate_dir())
	for p in FfwPacks.pack_paths():
		for e in FfwPacks.entries(p):
			if e.begins_with("Climate/") and e.ends_with(".csv"):
				var id := e.get_file().get_basename()
				if not ids.has(id):
					ids.append(id)
	ids.sort()
	return ids


static func _dir_csv_ids(dir_path: String) -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir != null:
		for f in dir.get_files():
			if f.get_extension().to_lower() == "csv":
				ids.append(f.get_basename())
	return ids


static func list_world_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(worlds_dir())
	if dir != null:
		for f in dir.get_files():
			if f.get_extension().to_lower() == "json" and not f.ends_with(".phenomena.json"):
				ids.append(f.get_basename())
	for p in FfwPacks.pack_paths():
		for e in FfwPacks.entries(p):
			if e.begins_with("Worlds/") and e.ends_with(".json") and not e.ends_with(".phenomena.json"):
				var id := e.get_file().get_basename()
				if not ids.has(id):
					ids.append(id)
	ids.sort()
	return ids


## 读取某座城市的气候表：内容包优先（整文件覆盖），回落散文件；都没有返回 null。
## source_path 用于状态栏展示（包来源显示为 “ffw:<包名>!Climate/<id>.csv”）。
static func load_climate(id: String) -> ClimateData:
	var rel := "Climate/%s.csv" % id
	var pack := FfwPacks.winner_for(rel)
	if pack != "":
		return ClimateData.load_from_text(FfwPacks.read_text(pack, rel), id,
				"ffw:%s!%s" % [pack.get_file(), rel])
	var p := climate_dir().path_join(id + ".csv")
	if FileAccess.file_exists(p):
		return ClimateData.load_from_file(p)
	return null


static func load_world(id: String) -> Dictionary:
	var t := FfwPacks.read_data_text("Worlds/%s.json" % id)
	if t != "":
		var parsed = JSON.parse_string(t)
		if typeof(parsed) == TYPE_DICTIONARY:
			return _complete_json(parsed, WORLD_DEFAULTS)
	return _load_json(worlds_dir().path_join(id + ".json"), WORLD_DEFAULTS)


static func save_world(id: String, data: Dictionary) -> Error:
	return _save_json(worlds_dir().path_join(id + ".json"), data)


static func load_city(id: String) -> Dictionary:
	var rel := "Cities/%s.json" % id
	var t := FfwPacks.read_data_text(rel)
	if t != "":
		var parsed = JSON.parse_string(t)
		if typeof(parsed) == TYPE_DICTIONARY:
			return _complete_json(parsed, CITY_DEFAULTS)  # 包来源视为新数据：走新默认（锚定图上位置）
	var path := cities_dir().path_join(id + ".json")
	var out := _load_json(path, CITY_DEFAULTS)
	# 迁移：m3.8 之前的城市文件没有 anchor 字段——**旧文件**按“经纬度为准”理解（用户当年填的
	# 经纬度就是数据本体）；只有**没有文件的新城市**才用新默认（锚定图上位置，收官批复）。
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text()) if f != null else null
		if typeof(parsed) == TYPE_DICTIONARY and not parsed.has("anchor"):
			out["anchor"] = ANCHOR_LATLONG
	return out


static func save_city(id: String, data: Dictionary) -> Error:
	return _save_json(cities_dir().path_join(id + ".json"), data)


# ———————— 编辑器单实例锁 ————————

## 还活着的编辑器实例 PID（没有 / 进程已死返回 0）。
static func editor_lock_pid() -> int:
	if not FileAccess.file_exists(EDITOR_LOCK_FILE):
		return 0
	var f := FileAccess.open(EDITOR_LOCK_FILE, FileAccess.READ)
	var pid := int(f.get_as_text().strip_edges().to_int()) if f != null else 0
	if pid <= 0 or not OS.is_process_running(pid):
		return 0  # 崩溃残留：锁自动作废
	return pid


## 抢锁；已被别的进程持有返回 false（同进程重复实例化——测试场景——放行）。
static func acquire_editor_lock() -> bool:
	var pid := editor_lock_pid()
	if pid == OS.get_process_id():
		return true
	if pid > 0:
		return false
	var f := FileAccess.open(EDITOR_LOCK_FILE, FileAccess.WRITE)
	if f == null:
		return true  # 锁写不了就别挡着人用编辑器
	f.store_string(str(OS.get_process_id()))
	return true


## 释放自己持有的锁（崩溃后残留的锁由下次启动的 editor_lock_pid 作废）。
static func release_editor_lock() -> void:
	if editor_lock_pid() == OS.get_process_id() and FileAccess.file_exists(EDITOR_LOCK_FILE):
		DirAccess.remove_absolute(EDITOR_LOCK_FILE)


## 气候现象模板（挂在世界上；城市只能被影响，不参与现象的种子——批复口径）。
## 文件：Worlds/<世界ID>.phenomena.json；结构见编辑器「现象」页与
## docs/项目路线图-2026-11-22.md 的草案。
const PHENOMENA_DEFAULTS := {"phenomena": []}


static func phenomena_path(world_id: String) -> String:
	return worlds_dir().path_join(world_id + ".phenomena.json")


static func load_phenomena(world_id: String) -> Dictionary:
	var t := FfwPacks.read_data_text("Worlds/%s.phenomena.json" % world_id)
	if t != "":
		var parsed = JSON.parse_string(t)
		if typeof(parsed) == TYPE_DICTIONARY:
			return _complete_json(parsed, PHENOMENA_DEFAULTS)
	return _load_json(phenomena_path(world_id), PHENOMENA_DEFAULTS)


static func save_phenomena(world_id: String, data: Dictionary) -> Error:
	# 形状防御：现象文件必须含 phenomena 数组；世界骨架（base_times 等）误入时拒绝写盘
	# （m3 曾发生世界数据被写进现象文件的事故，此防御保证两类文件互不污染）
	if not data.has("phenomena") or typeof(data["phenomena"]) != TYPE_ARRAY:
		push_error("save_phenomena 拒绝写入：数据缺少 phenomena 数组（%s）" % phenomena_path(world_id))
		return ERR_INVALID_DATA
	return _save_json(phenomena_path(world_id), data)


static func load_localization() -> Dictionary:
	return load_localization_file(loc_file())


static func save_localization(data: Dictionary) -> Error:
	return save_localization_file(loc_file(), data)


## 多语言支持（m3 批复：本地化界面每语言一个子页签）——
## Localization/<语言代码>.yaml，一个文件一种语言。
## 有文本（.yaml）或有语言定义（.json）都算一种语言。
static func list_languages() -> Array[String]:
	var langs := _dir_lang_codes(loc_dir())
	for p in FfwPacks.pack_paths():
		for e in FfwPacks.entries(p):
			if e.begins_with("Localization/"):
				var ext := e.get_extension().to_lower()
				if ext == "yaml" or ext == "json":
					var code := e.get_file().get_basename()
					if not langs.has(code):
						langs.append(code)
	langs.sort()
	if langs.is_empty():
		langs.append("zh")
	return langs


static func _dir_lang_codes(dir_path: String) -> Array[String]:
	var langs: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir != null:
		for f in dir.get_files():
			var ext := f.get_extension().to_lower()
			if ext == "yaml" or ext == "json":
				var code := f.get_basename()
				if not langs.has(code):
					langs.append(code)
	return langs


static func loc_path(lang: String) -> String:
	return loc_dir().path_join(lang + ".yaml")


static func load_localization_file(path: String) -> Dictionary:
	if _loc_cache.has(path):
		return {"data": _loc_cache[path], "errors": []}
	var text := ""
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
	var res := MiniYaml.parse(text)
	_loc_cache[path] = res.data
	return res


static func save_localization_file(path: String, data: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(MiniYaml.dumps(data))
	_loc_cache[path] = data.duplicate(true)
	return OK


static func invalidate_localization_cache() -> void:
	_loc_cache.clear()
	FfwPacks.invalidate()  # 内容包缓存一并失效（「重新加载」等场景）


static var _ffw_loc := {}  # lang -> [签名, 合并后的字典]（键级覆盖缓存）


## 界面语言缓存失效（由 FfwPacks.invalidate 调用）。
static func invalidate_ffw_loc() -> void:
	_ffw_loc.clear()


## 某语言的**生效**本地化：data/ 散文件为基线，逐包把 ffw 的同路径文件按“组→键”合并覆盖。
## 这是显示名与界面译文的唯一读取口径（内容包的“不同表达文本”补丁由此生效）。
static func load_language_merged(lang: String) -> Dictionary:
	var packs := FfwPacks.pack_paths()
	var hit := {}
	var sig := ""
	for p in packs:
		if FfwPacks.entries(p).has("Localization/%s.yaml" % lang):
			hit[p] = true
			sig += p + "@" + str(FfwPacks._mtime(p)) + ";"
	if _ffw_loc.has(lang) and _ffw_loc[lang][0] == sig:
		return _ffw_loc[lang][1]
	var merged: Dictionary = load_localization_file(loc_path(lang)).data
	for p in packs:
		if not hit.has(p):
			continue
		var over: Dictionary = MiniYaml.parse(FfwPacks.read_text(p, "Localization/%s.yaml" % lang)).data
		for group in over:
			if not merged.has(group) or typeof(merged[group]) != TYPE_DICTIONARY:
				merged[group] = {}
			for key in over[group]:
				merged[group][key] = over[group][key]
	_ffw_loc[lang] = [sig, merged]
	return merged


# ———————— 语言定义（Localization/<语言代码>.json：名字 + 字体）———————

static func language_def_path(lang: String) -> String:
	return loc_dir().path_join(lang + ".json")


static func load_language_def(lang: String) -> Dictionary:
	return _load_json(language_def_path(lang), LANG_DEF_DEFAULTS)


static func save_language_def(lang: String, data: Dictionary) -> Error:
	return _save_json(language_def_path(lang), data)


## 下拉框里显示的语言名：语言定义里的 name，留空显示语言代码。
static func language_display_name(lang: String) -> String:
	var name := str(load_language_def(lang).get("name", ""))
	return name if not name.is_empty() else lang


## 主题原本的默认字体。
static func default_font() -> Font:
	if _base_font == null:
		var theme: Theme = load(THEME_PATH)
		if theme != null:
			_base_font = theme.default_font
	if _base_font == null:
		_base_font = ThemeDB.fallback_font
	return _base_font


## 某语言的字体（《幻想气象局.md》：使用该语言时自动应用该字体；留空不覆盖）。没有则返回 null。
## 虚构语言走“Unicode 原文的字体映射”：文字按 Unicode 录入，字形由字体的 cmap 决定；
## 字体里没有的字（数字、汉字等）回退到界面默认字体。
static func language_font(lang: String) -> Font:
	var path := str(load_language_def(lang).get("font", "")).strip_edges()
	if path.is_empty():
		return null
	var res_path := path if path.begins_with("res://") else ("res://" + path if not path.is_absolute_path() else path)
	# res:// 的字体走资源系统（pck 里的导入字体，开发与导出都能 load）；
	# duplicate 后挂回退链——导入资源是全局共享的，不能就地改它；
	# 绝对路径/数据根下的散字体走文件加载（load_dynamic_font 需要真实 OS 路径）。
	if res_path.begins_with("res://"):
		var loaded := load(res_path)
		if loaded is Font:
			var inst: FontFile = (loaded as FontFile).duplicate()
			inst.fallbacks = [default_font()]
			_font_cache[path] = inst
			return inst
	var abs_path := os_path(resolve_media_path(path))
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		_font_cache[path] = null
		return null
	var f := FontFile.new()
	var err := f.load_dynamic_font(abs_path)
	if err != OK:
		push_warning("语言 %s 的字体加载失败：%s" % [lang, path])
		_font_cache[path] = null
		return null
	f.fallbacks = [default_font()]
	_font_cache[path] = f
	return f


## 把界面语言的字体应用到主题（主界面与设置编辑器各自调用一次；没有字体则恢复默认）。
static func apply_ui_font(lang: String) -> void:
	var theme: Theme = load(THEME_PATH)
	if theme == null:
		return
	var f := language_font(lang)
	var base := default_font()
	theme.default_font = f if f != null else base
	theme.set_font("title_font", "Window", f if f != null else base)


# ———————— 显示名 ————————

## 城市显示名：所选语言的 cities.<id>，缺失回退 zh，仍缺失返回 ""（调用方自行回退）。
static func city_display_name(id: String, lang: String = DEFAULT_LANG) -> String:
	return _loc_lookup("cities", id, lang)


## 世界显示名：所选语言的 worlds.<id>，缺失回退 zh，仍缺失返回 ""。
static func world_display_name(id: String, lang: String = DEFAULT_LANG) -> String:
	return _loc_lookup("worlds", id, lang)


## 读 JSON 并与默认骨架合并。文件里缺的键取默认值——**容器类默认值必须深拷贝**：
## 常量容器在运行期是只读的，直接引用会让缺键字段改不动（改写被静默拒绝并报错）。
static func _load_json(path: String, defaults: Dictionary) -> Dictionary:
	var out := {}
	for k in defaults:
		out[k] = _writable(defaults[k])
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	return _complete_json(parsed, defaults, out)


## 解析结果 + 默认骨架 → 补全的可写字典（内容包来源的文件同样补全）。
static func _complete_json(parsed: Dictionary, defaults: Dictionary, out := {}) -> Dictionary:
	if out.is_empty():
		for k in defaults:
			out[k] = _writable(defaults[k])
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


## 常量容器 → 可写的深拷贝；标量原样返回。
static func _writable(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return v.duplicate(true)
	return v
