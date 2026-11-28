class_name ClimateData
extends RefCounted
## 逐月气候表（CSV）的读取与查询。
##
## 期望列排布（自动识别，宽容处理）：
##   · 键值在首列：键名, 1月值 … 12月值 [, 注释]   ← m2 起 myksolonia.csv 的排布（英文语义 id + 中文注释）
##   · 键值在末列：1月值 … 12月值, 键名 [, 注释]   ← 旧排布（lioepprosia.csv 等）
## 首行是月份表头（12 个数据恰为 1…12）时自动跳过；注释列自动忽略。
## 空键行（如「气候表现-*」权重）用注释列名称兜底保留。
## 数值允许带引号与首尾空白；某行 12 个月值不全时跳过并计数，不中断加载。

## 键名 → 引擎语义键。两套并列：
## · 中文键（旧版 CSV / 注释列名）
## · 英文语义 id（m2 起 Climate/*.csv 第一列，见《1122Classic0.0.1 m2意见》的数据处理规则）
const KEY_MAP := {
	"平均日均温": "mean_temp",
	"平均降水量": "precip",
	"平均日高温": "high_temp",
	"平均日低温": "low_temp",
	"气象记录高温": "record_high",
	"气象记录低温": "record_low",
	"平均日照时长": "sunshine",
	"平均降水天数": "rain_days",
	"平均降雪天数": "snow_days",
	"平均湿度": "humidity",
	"tmean": "mean_temp",
	"rmean": "precip",
	"thigh": "high_temp",
	"tlow": "low_temp",
	"trecordh": "record_high",
	"trecordl": "record_low",
	"sunlight_h": "sunshine",
	"raint": "rain_days",
	"snowt": "snow_days",
	"humidity": "humidity",
}

var city_name := ""
var source_path := ""
var monthly := {}                      # 语义键 -> PackedFloat64Array(12)
var extra_keys := PackedStringArray()  # 未映射的原始键（如“气候表现-*”权重），原样保留
var skipped_rows := 0


static func load_from_file(path: String) -> ClimateData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return load_from_text(f.get_as_text(), path.get_file().get_basename(), path)


## 从文本解析（m3.13：.ffw 内容包里的气候表没有真实文件路径，走这里）。
static func load_from_text(text: String, city: String, source := "") -> ClimateData:
	var data := ClimateData.new()
	data.source_path = source
	data.city_name = city
	for line in text.split("\n"):
		if line.strip_edges().is_empty():
			continue
		if not _parse_row(f_csv_line(line), data):
			data.skipped_rows += 1
	return data


## 单行 CSV 解析（带引号字段、内嵌逗号安全）——get_csv_line 的行内等价物。
static func f_csv_line(line: String) -> PackedStringArray:
	var cells := PackedStringArray()
	var cur := ""
	var in_quotes := false
	var i := 0
	var n := line.length()
	# 引号字段内的换行：当前行若引号不闭合，续接下一物理行
	while i < n:
		var ch := line[i]
		if ch == "\"":
			if in_quotes and i + 1 < n and line[i + 1] == "\"":
				cur += "\""
				i += 1
			else:
				in_quotes = not in_quotes
		elif ch == "," and not in_quotes:
			cells.append(cur)
			cur = ""
		else:
			cur += ch
		i += 1
	cells.append(cur)
	return cells


static func _parse_row(cells: PackedStringArray, data: ClimateData) -> bool:
	if cells.size() < 13:
		return false
	var cleaned := PackedStringArray()
	for c in cells:
		cleaned.append(c.trim_prefix("\uFEFF").strip_edges())
	var vals := PackedFloat64Array()
	var key := ""
	if is_nan(_to_float(cleaned[0])):
		# 键在首列：键名, 1月…12月, [注释]
		key = cleaned[0]
		for m in range(1, 13):
			vals.append(_to_float(cleaned[m]))
	else:
		# 键在末列：1月…12月, 键名, [注释]
		key = cleaned[12]
		for m in range(12):
			vals.append(_to_float(cleaned[m]))
	if key == "月份" or _looks_like_month_header(vals):
		return false
	if key.is_empty():
		# 空键行（如「气候表现-*」权重行）：用注释列名称兜底保留，无注释才丢弃
		var comment := cleaned[13] if cleaned.size() > 13 else ""
		if comment.is_empty():
			return false
		key = comment
	for v in vals:
		if is_nan(v):
			return false  # 12 个月值必须齐全
	var sem: String = KEY_MAP.get(key, "")
	if sem.is_empty():
		sem = key
		if not data.extra_keys.has(key):
			data.extra_keys.append(key)
	data.monthly[sem] = vals
	return true


static func _looks_like_month_header(vals: PackedFloat64Array) -> bool:
	if vals.size() != 12:
		return false
	for i in 12:
		if not is_equal_approx(vals[i], float(i + 1)):
			return false
	return true


static func _to_float(s: String) -> float:
	return s.to_float() if s.is_valid_float() else NAN


func has_key(key: String) -> bool:
	return monthly.has(key)


## 取某月的数值；month 取 1…12，数据缺失时返回 NAN。
func month_value(key: String, month: int) -> float:
	if month < 1 or month > 12:
		return NAN
	if monthly.has(key):
		return monthly[key][month - 1]
	return NAN
