class_name WeatherEngine
extends RefCounted
## v0.0.1-m3 天气引擎：**月度确定性生成** + 日查询。
##
## —— 生成顺序（批复：所在月份的每天先预生成，评分筛选以此为前置结构）——
## month_report() 一次生成整月：
##   1. 雨日布局：rain_days（raint）锁定雨日数量——发生口径“降水量>0 即雨日”
##   2. 降水量分配：日独立量 与 rmean 总量对账 按 monthly_total_strength 插值
##   3. 温度距平：日种子原始噪声 与 低频平滑项 按 month_smoothing 插值；
##      距平按 monthly_total_strength 做零和收敛——“凑齐月积温”
##   4. 雪：冷期雨日按 snow_days/raint 比例转雪
##   5. 露点中介（已采纳）：月尺度 T+RH→露点；日尺度 RH=f(当日温标, 露点)
## day_report() 从缓存读取当日条目。
##
## —— 种子（WorldRng，三层）——
## 年度种子：年温度距平 ±1℃、年降水比 1±0.15（“每个年份同期会有波动”）
## 月度种子：月温度距平 ±1℃ + 雨日布局（现象分配待现象期接入）
## 日期种子：日噪声原始项、天空分类、雪判定
##
## —— 世界参数消费 ——
## month_temp_sigma / month_smoothing / monthly_total_strength
## （axial_tilt_deg、day_hours、phenomena_spread_days、annual_compensation 暂未消费）
##
## —— 城市图表随机（m3.5 批复：宏观柏林面，城市按经纬度读高度）——
## 温度面 → 站点温度偏置 ±1.5℃；降水比面 → 年降水比偏置 ±0.10。
## 与旧 city_noise（未按面 id 修饰）相比，面种子经十六进制 id 插入，可与现象面区分。
##
## —— 随机评分筛选（硬否决前置→方案一择优）尚未实装，月度预生成即其前置结构。

enum SkyKind { SUNNY, CLOUDY, RAINY }

## 跨月加权窗口（天）：设计文档“两个月之间的 15 天取两个月加权值”。
## 距月初/月末不足半窗时与相邻月份加权平均，月中央保持本月纯值。
const BLEND_DAYS := 15.0

# —— 日照 → 晴/阴标定（雨天由 raint 布局锁定，不在此列）——
const SUNNY_BASE := 2.0   # p(晴) = (日日照 - SUNNY_BASE) / SUNNY_DIV，仅对非雨日
const SUNNY_DIV := 9.0
const SUNNY_MIN := 0.10
const SUNNY_MAX := 0.75

# —— 年度/月度差异幅度（批复：每年每月相比同期有波动）——
const YEAR_TEMP_SIGMA := 1.0      # 年温度距平 σ（℃）
const YEAR_PRECIP_SIGMA := 0.15   # 年降水比 σ（±15%，钳制 0.6..1.5）
const MONTH_TEMP_SIGMA := 1.0     # 月温度距平 σ（℃）
const NOISE_TEMP_SCALE := 1.5     # 城市噪点 → 站点温度偏置（℃）
const SNOW_TEMP_MAX := 1.0        # 日低温低于此值时雨才可能成雪（℃）

var climate: ClimateData
var world_id := ""
var world := {}   # Worlds/<id>.json（缺省字段走骨架默认）
var city := {}    # Cities/<id>.json（lati/long 用于城市噪点）
var _month_cache := {}  # "y-m" -> month_report


func _init(climate_data: ClimateData = null, world_id := "", world := {}, city := {}) -> void:
	climate = climate_data
	self.world_id = world_id
	self.world = world
	self.city = city


## 生成某一天的完整预报（同一天多次调用结果一致；整月共享一次月度生成）。
func day_report(year: int, month: int, day: int) -> Dictionary:
	if climate == null:
		return {
			"sky": SkyKind.SUNNY, "snow": false, "high": NAN, "low": NAN,
			"rain_prob": NAN, "precip_mm": 0.0, "sun_daily": NAN, "humidity": NAN,
			"seed_key": "%04d-%02d-%02d" % [year, month, day],
		}
	var mr := month_report(year, month)
	var idx := clampi(day, 1, mr["days"]) - 1
	var e: Dictionary = mr["day_entries"][idx]
	return {
		"sky": e["sky"],
		"snow": e["snow"],
		"high": e["high"],
		"low": e["low"],
		"rain_prob": mr["rain_prob"],       # 当月雨日占比（0..1）——确定性世界的“降雨可能”口径
		"precip_mm": e["precip_mm"],
		"sun_daily": _blend("sunshine", month, day, year) / float(mr["days"]),
		"humidity": e["rh"],
		"seed_key": "%04d-%02d-%02d" % [year, month, day],
	}


## 整月确定性生成（带缓存）。结构上即未来评分筛选的“月度预生成”层。
func month_report(year: int, month: int) -> Dictionary:
	var key := "%04d-%02d" % [year, month]
	if _month_cache.has(key):
		return _month_cache[key]
	var rep := _generate_month(year, month)
	_month_cache[key] = rep
	return rep


func _generate_month(year: int, month: int) -> Dictionary:
	var days := _days_in_month(year, month)
	var seeds := WorldRng.world_seeds(world_id, year, month, 1)
	var rng_year := WorldRng.rng_from_seed(seeds.year_seed)
	var rng_month := WorldRng.rng_from_seed(seeds.month_seed)

	# —— 年度 / 月度差异（批复：每年每月同期波动）+ 城市图表随机面偏置 ——
	var year_temp_a := rng_year.randfn(0.0, YEAR_TEMP_SIGMA)
	var year_precip := clampf(1.0 + rng_year.randfn(0.0, YEAR_PRECIP_SIGMA)
			+ _city_precip_bias(), 0.6, 1.5)
	var month_temp_a := rng_month.randfn(0.0, MONTH_TEMP_SIGMA)
	var city_offset := _city_temp_offset()

	# —— 世界参数 ——
	var sigma := clampf(_worldf("month_temp_sigma", 2.2), 0.2, 20.0)
	var smoothing := clampf(_worldf("month_smoothing", 0.5), 0.0, 1.0)
	var reconcile := clampf(_worldf("monthly_total_strength", 0.0), 0.0, 1.0)

	# —— 1. 雨日布局（raint 锁定；月度种子洗牌）——
	var rain_target := clampi(roundi(_month_value_or("rain_days", month, 0.0)), 0, days)
	var order := range(days)
	for i in range(days - 1, 0, -1):
		var j := rng_month.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var rain_set := {}
	for i in rain_target:
		rain_set[order[i] + 1] = true

	# —— 月尺度气候目标 ——
	var rmean_total := maxf(_month_value_or("precip", month, 0.0) * year_precip, 0.0)
	var snow_ratio := clampf(
		_month_value_or("snow_days", month, 0.0) / maxf(_month_value_or("rain_days", month, 1.0), 1.0),
		0.0, 1.0)
	var td_month := _dewpoint_from(
		_month_value_or("mean_temp", month,
				(_month_value_or("high_temp", month, 15.0) + _month_value_or("low_temp", month, 5.0)) * 0.5),
		_month_value_or("humidity", month, 70.0))
	var base_offset := year_temp_a + month_temp_a + city_offset

	# —— 2/3. 逐日原始项（第一遍：只掷种子，不组装）——
	var raw_mm := {}
	var raw_a := {}
	var sky_roll := {}
	var snow_roll := {}
	var mod_roll := {}
	for d in range(1, days + 1):
		var rng_d := WorldRng.rng_from_seed(WorldRng.world_seeds(world_id, year, month, d).day_seed)
		raw_mm[d] = rng_d.randf_range(0.2, 8.0) if rain_set.has(d) else 0.0
		raw_a[d] = rng_d.randfn(0.0, sigma)
		sky_roll[d] = rng_d.randf()
		snow_roll[d] = rng_d.randf()
		mod_roll[d] = [rng_d.randf(), rng_d.randf()]

	# —— 平滑 + 零和收敛（凑齐月积温）：先平滑，再对最终距平做零和——
	# 月均值由 base_offset（年度+月度+城市偏置）承担，strength=1 时恰好凑齐
	var final_a := {}
	var mean_a := 0.0
	for d in range(1, days + 1):
		var dn := WorldRng.stable_day_number(year, month, d)
		var a: float = lerpf(raw_a[d], WorldRng.smooth_day_noise(world_id, dn) * sigma * 1.2, smoothing)
		final_a[d] = a
		mean_a += a
	mean_a /= days
	var anomaly_shift := -mean_a * reconcile
	for d in range(1, days + 1):
		final_a[d] += anomaly_shift

	# —— 降水量对账：独立量 → rmean 总量分配，按 reconcile 插值 ——
	if rain_target > 0 and reconcile > 0.0:
		var wsum := 0.0
		var weights := {}
		for d in rain_set:
			var w: float = raw_mm[d] + 0.4
			weights[d] = w
			wsum += w
		for d in rain_set:
			var reconciled: float = weights[d] / wsum * rmean_total
			raw_mm[d] = lerpf(raw_mm[d], reconciled, reconcile)

	# —— 4/5. 逐日组装 ——
	var day_entries := []
	for d in range(1, days + 1):
		var anomaly: float = final_a[d]
		var high := _blend("high_temp", month, d, year) + base_offset + anomaly
		var low := _blend("low_temp", month, d, year) + base_offset + anomaly
		var is_rain: bool = rain_set.has(d)
		var sky := SkyKind.RAINY
		var snow := false
		var precip: float = raw_mm[d]
		if not is_rain:
			var p_sunny := clampf((_blend("sunshine", month, d, year) / float(days)
					- SUNNY_BASE) / SUNNY_DIV, SUNNY_MIN, SUNNY_MAX)
			sky = SkyKind.SUNNY if sky_roll[d] < p_sunny else SkyKind.CLOUDY
		else:
			# 冷期雨日按 snow_days/raint 比例转雪
			if low < SNOW_TEMP_MAX and snow_roll[d] < snow_ratio:
				snow = true
		match sky:
			SkyKind.RAINY:
				high -= 1.8 + mod_roll[d][0] * 1.6
				low += 0.6 + mod_roll[d][1] * 0.6
			SkyKind.CLOUDY:
				high -= 0.8 + mod_roll[d][0] * 0.8
				low += 0.3
			SkyKind.SUNNY:
				high += 0.6
				low -= 0.3
		# 气象记录硬钳制（硬否决层，缺数据跳过）
		var rec_high := _blend("record_high", month, d, year)
		var rec_low := _blend("record_low", month, d, year)
		if not is_nan(rec_high):
			high = minf(high, rec_high)
		if not is_nan(rec_low):
			low = maxf(low, rec_low)
		low = minf(low, high - 1.0)
		# 露点中介：月露点 + 当日温标 → 日湿度
		var rh := _rh_from((high + low) * 0.5, td_month)
		if is_rain:
			rh = maxf(rh, 92.0)
		day_entries.append({
			"day": d, "sky": sky, "snow": snow, "precip_mm": precip,
			"high": high, "low": low, "rh": rh, "anomaly": anomaly,
		})

	return {
		"days": days,
		"rain_target": rain_target,
		"rain_prob": float(rain_target) / float(days) if days > 0 else 0.0,
		"precip_total": rmean_total,
		"year_temp_a": year_temp_a,
		"month_temp_a": month_temp_a,
		"city_offset": city_offset,
		"day_entries": day_entries,
	}


# —— 露点中介（Magnus 公式，a=17.62 b=243.12）——

## 温度（℃）+ 相对湿度（%）→ 露点（℃）
static func _dewpoint_from(t_c: float, rh_pct: float) -> float:
	var rh := clampf(rh_pct, 1.0, 100.0)
	var g := log(rh / 100.0) + 17.62 * t_c / (243.12 + t_c)
	return 243.12 * g / (17.62 - g)


## 温度（℃）+ 露点（℃）→ 相对湿度（%）
static func _rh_from(t_c: float, td_c: float) -> float:
	var g_t := 17.62 * t_c / (243.12 + t_c)
	var g_td := 17.62 * td_c / (243.12 + td_c)
	return clampf(100.0 * exp(g_td - g_t), 1.0, 100.0)


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


func _city_temp_offset() -> float:
	if world_id.is_empty() or city.is_empty():
		return 0.0
	# 图表随机·温度面：城市经纬度读高度 → 站点温度偏置
	return WorldRng.chart_field(world_id, WorldRng.FIELD_TEMPERATURE,
			float(city.get("lati", 0.0)), float(city.get("long", 0.0))) * NOISE_TEMP_SCALE


## 图表随机·降水比面：城市经纬度读高度 → 年降水比偏置（±0.10）
func _city_precip_bias() -> float:
	if world_id.is_empty() or city.is_empty():
		return 0.0
	return WorldRng.chart_field(world_id, WorldRng.FIELD_PRECIPITATION,
			float(city.get("lati", 0.0)), float(city.get("long", 0.0))) * 0.10


func _worldf(key: String, fallback: float) -> float:
	var v = world.get(key, fallback)
	return fallback if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT else float(v)


func _month_value_or(key: String, month: int, fallback: float) -> float:
	var v := climate.month_value(key, month) if climate != null else NAN
	return fallback if is_nan(v) else v
