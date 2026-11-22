class_name WeatherEngine
extends RefCounted
## v1 天气引擎：月份数据插值 + 日期种子确定性随机。
##
## —— 当前机制（刻意保持简单）——
## · 随机种子来自日期（设计文档：全年 365/366 个种子），同一天任何时候
##   生成都会得到同一份天气；未来的“随机评分筛选”尚未实装。
## · 天气型只有 晴/阴/雨 三种，权重只由「平均日照时长」折算。
## · 气温在月均值（跨月加权）上叠加确定性扰动，并被当月气象记录钳制。
##
## —— 为评分筛选预留的结构 ——
## day_report() 已经把“一天”封装成一个自包含的候选结果 Dictionary；
## 未来只需把这里的“单次抽样”重复 N 次生成候选，再用评分函数择优即可。

enum SkyKind { SUNNY, CLOUDY, RAINY }

## 跨月加权窗口（天）：设计文档“两个月之间的 15 天取两个月加权值”。
## 距月初/月末不足半窗时与相邻月份加权平均，月中央保持本月纯值。
const BLEND_DAYS := 15.0

# —— 日照 → 天气权重标定（v1 唯一输入：平均日照时长，单位：小时/日）——
const RAIN_BASE := 0.55   # p(雨) = RAIN_BASE - 日日照 * RAIN_SLOPE
const RAIN_SLOPE := 0.055
const RAIN_MIN := 0.05
const RAIN_MAX := 0.60
const SUNNY_BASE := 2.0   # p(晴) = (日日照 - SUNNY_BASE) / SUNNY_DIV
const SUNNY_DIV := 9.0
const SUNNY_MIN := 0.10
const SUNNY_MAX := 0.75

const ANOMALY_SIGMA := 2.2   # 当日整体冷暖距平 σ（℃）
const SPREAD_SIGMA := 0.8    # 高低温独立噪声 σ（℃）

var climate: ClimateData


func _init(climate_data: ClimateData = null) -> void:
	climate = climate_data


## 生成某一天的完整预报（同一天多次调用结果一致）。
func day_report(year: int, month: int, day: int) -> Dictionary:
	if climate == null:
		return {
			"sky": SkyKind.SUNNY, "high": NAN, "low": NAN,
			"rain_prob": NAN, "sun_daily": NAN, "humidity": NAN,
			"seed_key": "%04d-%02d-%02d" % [year, month, day],
		}

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%04d-%02d-%02d" % [year, month, day])

	var days := _days_in_month(year, month)
	var sun_daily := _blend("sunshine", month, day, year) / days

	var p_rain := clampf(RAIN_BASE - sun_daily * RAIN_SLOPE, RAIN_MIN, RAIN_MAX)
	var p_sunny := clampf((sun_daily - SUNNY_BASE) / SUNNY_DIV, SUNNY_MIN, SUNNY_MAX)
	var p_cloudy := maxf(1.0 - p_rain - p_sunny, 0.0)

	var roll := rng.randf()
	var sky := SkyKind.SUNNY
	if roll >= p_sunny + p_cloudy:
		sky = SkyKind.RAINY
	elif roll >= p_sunny:
		sky = SkyKind.CLOUDY

	var high := _blend("high_temp", month, day, year)
	var low := _blend("low_temp", month, day, year)
	var anomaly := rng.randfn(0.0, ANOMALY_SIGMA)
	var spread := rng.randfn(0.0, SPREAD_SIGMA)

	# 天气型对日较差的修正：雨天压制最高温、托高最低温；晴天反之
	match sky:
		SkyKind.RAINY:
			high -= 1.8 + rng.randf() * 1.6
			low += 0.6 + rng.randf() * 0.6
		SkyKind.CLOUDY:
			high -= 0.8 + rng.randf() * 0.8
			low += 0.3
		SkyKind.SUNNY:
			high += 0.6
			low -= 0.3

	high += anomaly + spread
	low += anomaly - spread

	# 气象记录硬钳制（缺数据时跳过）
	var rec_high := _blend("record_high", month, day, year)
	var rec_low := _blend("record_low", month, day, year)
	if not is_nan(rec_high):
		high = minf(high, rec_high)
	if not is_nan(rec_low):
		low = maxf(low, rec_low)
	low = minf(low, high - 1.0)

	return {
		"sky": sky,
		"high": high,
		"low": low,
		"rain_prob": p_rain,
		"sun_daily": sun_daily,
		"humidity": _blend("humidity", month, day, year),
		"seed_key": "%04d-%02d-%02d" % [year, month, day],
	}


## 按公历推进一天，返回 {"year","month","day"}。
static func next_date(year: int, month: int, day: int) -> Dictionary:
	var d := day + 1
	var m := month
	var y := year
	if d > _days_in_month(y, m):
		d = 1
		m += 1
		if m > 12:
			m = 1
			y += 1
	return {"year": y, "month": m, "day": d}


static func _days_in_month(year: int, month: int) -> int:
	const LENGTHS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var d: int = LENGTHS[month - 1]
	if month == 2 and _is_leap_year(year):
		d = 29
	return d


static func _is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


static func _prev_month(month: int) -> int:
	return 12 if month == 1 else month - 1


static func _next_month(month: int) -> int:
	return 1 if month == 12 else month + 1


## 气候值插值：月中央取本月纯值，靠近月初/月末时与相邻月份按窗口加权。
func _blend(key: String, month: int, day: int, year: int) -> float:
	if climate == null:
		return NAN
	var days := _days_in_month(year, month)
	var own := climate.month_value(key, month)
	var from_start := day - 0.5
	var from_end := days - day + 0.5
	var w_own := clampf(minf(from_start, from_end) / (BLEND_DAYS * 0.5), 0.0, 1.0)
	var neighbor := climate.month_value(
			key, (_prev_month(month) if from_start <= from_end else _next_month(month)))
	if is_nan(own):
		return neighbor
	if is_nan(neighbor):
		return own
	return lerpf(neighbor, own, w_own)
