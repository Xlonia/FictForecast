class_name UiText
extends RefCounted
## 界面语言（m3.8 批复：界面文字走各语言 yaml 的 ui 组，编辑器同样跟随）。
##
## 口径：
##   · 界面文字的**原文是中文**；译文放在 `Localization/<语言代码>.yaml` 的 `ui` 组，
##     **键 = 中文原文，值 = 译文**（用户可在编辑器「本地化」页翻译界面，也可导入界面字符串清单）。
##   · 回退链：当前语言 → zh 的 ui 组（可用来改中文措辞）→ 中文原文。
##   · 代码里的文字：`UiText.t("中文原文")`；带参数的用 `UiText.f("原文 %s / %.2f°", [a, b])`——
##     译文缺占位符或多占位符时不会报错（缺的参数位原样保留）。
##   · 场景文件（.tscn）里的静态文字：启动时由 `install(root, true)` 登记原文并替换；
##     切换界面语言时 `UiText.set_language(语言)` 后再调一次 `install(root)`，然后刷新动态文字。
##   · 约定：可翻译的字符串必须是含中文的字面量（`UiText.scan_sources()` 据此扫描出界面字符串清单，
##     dev_selftest 用它核对各语言文件的翻译覆盖）。开发期消息（push_error / print）不翻译。
##
## 没有用引擎自带的 TranslationServer 自动翻译：实测本版本里控件的 text 不会随语言自动替换，
## 显式翻译的行为可控、可测。

const GROUP := "ui"
const META_PREFIX := "ui_src_"           # 节点元数据键前缀：原文存在 ui_src_text 等键下
const PROPS := ["text", "placeholder_text", "tooltip_text", "title"]

static var _lang := "zh"
static var _base := {}    # zh 的 ui 组
static var _table := {}   # 当前语言生效的译文表（当前语言覆盖 zh）


static func language() -> String:
	return _lang


## 切换界面语言：重建译文表。之后需要对界面根节点调 install() 并刷新动态文字。
static func set_language(lang: String) -> void:
	_lang = lang
	_base = _group_of(SettingsStore.DEFAULT_LANG)
	_table = _base.duplicate()
	if lang != SettingsStore.DEFAULT_LANG:
		var own := _group_of(lang)
		for k in own:
			var v := str(own[k])
			if not v.is_empty():      # 留空 = 未翻译 → 回退
				_table[k] = v


## 取某个语言文件 ui 组的可写副本。
static func _group_of(lang: String) -> Dictionary:
	var res := SettingsStore.load_localization_file(SettingsStore.loc_path(lang))
	var g = res.data.get(GROUP, {})
	return (g as Dictionary).duplicate() if typeof(g) == TYPE_DICTIONARY else {}


## 翻译一句原文；没有译文时返回原文。
static func t(src: String) -> String:
	var v := str(_table.get(src, ""))
	return v if not v.is_empty() else src


## 翻译并套参数。译文与原文的占位符数量不一致时不报错：多出的原文照留，缺的参数位原样保留。
static func f(src: String, args: Array) -> String:
	return format(t(src), args)


## 宽容的 printf：逐个转换说明处理，参数不够时保留说明符原样，类型不符时做安全转换。
static func format(fmt: String, args: Array) -> String:
	var out := ""
	var ai := 0
	var i := 0
	var n := fmt.length()
	while i < n:
		var ch: String = fmt[i]
		if ch != "%":
			out += ch
			i += 1
			continue
		if i + 1 < n and fmt[i + 1] == "%":
			out += "%"
			i += 2
			continue
		var j := i + 1
		while j < n and fmt[j] in "-+ #0":
			j += 1
		while j < n and fmt[j] >= "0" and fmt[j] <= "9":
			j += 1
		if j < n and fmt[j] == ".":
			j += 1
			while j < n and fmt[j] >= "0" and fmt[j] <= "9":
				j += 1
		if j >= n:
			out += fmt.substr(i)
			break
		var spec := fmt.substr(i, j - i + 1)
		var tc: String = fmt[j]
		if ai >= args.size():
			out += spec       # 译文多写了占位符：原样保留，肉眼可发现
		else:
			var v = args[ai]
			match tc:
				"d", "i", "o", "u", "x", "X", "c":
					if typeof(v) == TYPE_STRING:
						v = (v as String).to_int()
					elif typeof(v) == TYPE_FLOAT:
						v = int(v)
				"f", "e", "E", "g", "G":
					if typeof(v) == TYPE_STRING:
						v = (v as String).to_float()
					elif typeof(v) == TYPE_INT:
						v = float(v)
				_:
					v = str(v)
			out += spec % v
		ai += 1
		i = j + 1
	return out


## 把界面语言应用到 root 及其全部子节点。
## record = true：把节点上现有的文字登记为原文（**只在界面刚实例化、还没被代码改写之前调一次**）；
## record = false：只替换已登记过的节点。
static func install(root: Node, record: bool = false) -> void:
	if root == null or not is_instance_valid(root):
		return
	_apply_node(root, record)
	for c in root.get_children():
		install(c, record)


static func _apply_node(node: Node, record: bool) -> void:
	for prop in PROPS:
		if not (prop in node):
			continue
		var meta: String = META_PREFIX + prop
		if node.has_meta(meta):
			node.set(prop, t(str(node.get_meta(meta))))
		elif record:
			var src := str(node.get(prop))
			if src.is_empty():
				continue
			node.set_meta(meta, src)
			if src != t(src):
				node.set(prop, t(src))


# ———————— 界面字符串清单（供编辑器导入、自检核对覆盖）———————

## 扫描 scripts/*.gd 与 scenes/*.tscn，返回 { 中文原文: "文件名:行号" }。
## 规则：含中文的字符串字面量（脚本里跳过注释行与 push_error / push_warning / print / printerr 行；
## 场景里只取 text / placeholder_text / tooltip_text / dialog_text / title 属性）。可能略多不少。
## 跳过 dev_selftest（自检文案）与 climate_data（CSV 键名是数据标识，不是界面文字）。
static func scan_sources() -> Dictionary:
	var out := {}
	for fname in _files_in("res://scripts", "gd"):
		if fname.begins_with("dev_") or fname == "climate_data.gd":
			continue
		_scan_script(_read("res://scripts".path_join(fname)), fname, out)
	for fname in _files_in("res://scenes", "tscn"):
		_scan_scene(_read("res://scenes".path_join(fname)), fname, out)
	return out


static func _files_in(dir_path: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == ext:
			out.append(f)
	out.sort()
	return out


static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


static func _has_cjk(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) >= 0x4E00 and s.unicode_at(i) <= 0x9FFF:
			return true
	return false


static func _scan_script(text: String, fname: String, out: Dictionary) -> void:
	var lines := text.split("\n")
	for ln in lines.size():
		var line: String = lines[ln]
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("push_error(") or stripped.contains("push_warning(") \
				or stripped.contains("print(") or stripped.contains("printerr("):
			continue
		var i := 0
		var n := line.length()
		while i < n:
			if line[i] != "\"":
				i += 1
				continue
			# 字符串字面量：走到未转义的收尾引号（转义序列先原样保留，稍后还原）
			var j := i + 1
			var lit := ""
			while j < n and line[j] != "\"":
				if line[j] == "\\" and j + 1 < n:
					lit += line.substr(j, 2)
					j += 2
				else:
					lit += line[j]
					j += 1
			if j >= n:
				break  # 没有收尾引号：扫描器只处理单行字面量
			if _has_cjk(lit):
				_add_source(out, _unescape(lit), "%s:%d" % [fname, ln + 1])
			i = j + 1


static func _scan_scene(text: String, fname: String, out: Dictionary) -> void:
	var lines := text.split("\n")
	for ln in lines.size():
		var line: String = lines[ln]
		if line.begins_with(";"):
			continue
		for prop in PROPS:
			var prefix: String = prop + " = \""
			if line.begins_with(prefix) and line.ends_with("\"") and line.length() > prefix.length() + 1:
				var lit := line.substr(prefix.length(), line.length() - prefix.length() - 1)
				if _has_cjk(lit):
					_add_source(out, _unescape(lit), "%s:%d" % [fname, ln + 1])


static func _add_source(out: Dictionary, src: String, where: String) -> void:
	if not out.has(src):
		out[src] = where


## 字符串字面量的转义还原（Godot 文本场景与 GDScript 共用的几种：引号、换行、反斜杠）。
static func _unescape(s: String) -> String:
	return s.replace("\\\"", "\"").replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


## 译文覆盖率自检：返回 { "missing": {原文: 语言}, "stale": {键: 语言} }——
## missing = 清单里有而语言文件 ui 组没有（或为空）的；stale = 语言文件 ui 组里有、清单里没有的。
static func audit(lang: String) -> Dictionary:
	var srcs := scan_sources()
	var own := _group_of(lang)
	var missing := {}
	var stale := {}
	for s in srcs:
		if str(own.get(s, "")).is_empty():
			missing[s] = lang
	for k in own:
		# 只报含中文的键：不含中文的（如 “%s（%s）” 这类格式串）扫描器不收录，由各语言文件自行决定要不要改写
		if not srcs.has(k) and _has_cjk(str(k)):
			stale[str(k)] = lang
	return {"missing": missing, "stale": stale, "sources": srcs.size()}
