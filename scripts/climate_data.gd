class_name ClimateData
extends RefCounted
## 逐月气候表（CSV）的读取与查询。
##
## 期望列排布（自动识别，宽容处理）：
##   · 键值在首列：键名, 1月值 … 12月值 [, 注释]
##   · 键值在末列：1月值 … 12月值, 键名 [, 注释]   ← 当前 Climate/*.csv 的排布
## 首行是月份表头（12 个数据恰为 1…12）时自动跳过；注释列自动忽略。
## 数值允许带引号与首尾空白；某行 12 个月值不全时跳过并计数，不中断加载。

## 本地化键名 → 引擎语义键
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
	var data := ClimateData.new()
	data.source_path = path
	data.city_name = path.get_file().get_basename()
	while f.get_position() < f.get_length():
		if not _parse_row(f.get_csv_line(), data):
			data.skipped_rows += 1
	return data


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
	if key.is_empty() or key == "月份" or _looks_like_month_header(vals):
		return false
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
