extends SceneTree
## 开发自检（不随游戏运行，headless 执行）：
##   godot --headless --path . --script res://scripts/dev_selftest.gd
## 覆盖：CSV 解析（两种列排布/表头跳过）、全年逐日生成、记录钳制、
## 日期推进（平/闰年）、跨月加权、确定性。

var _fails := 0


func _init() -> void:
	print("== 幻想气象局 dev_selftest ==")

	# —— 1. 真实 CSV 解析 ——
	var cd := ClimateData.load_from_file("res://Climate/myksolonia.csv")
	_check(cd != null, "读取 Climate/myksolonia.csv")
	if cd == null:
		_finish()
		return
	_check(cd.monthly.size() == 11, "10 个语义键 + 1 个原始未映射键（实际 %d）" % cd.monthly.size())
	_check(cd.extra_keys.size() == 1, "未映射键 1 个（气候表现-*，实际 %d）" % cd.extra_keys.size())
	var sun: PackedFloat64Array = cd.monthly.get("sunshine", PackedFloat64Array())
	_check(sun.size() == 12, "sunshine 有 12 个月值（实际 %d）" % sun.size())
	if sun.size() == 12:
		_check(is_equal_approx(sun[7], 275.6), "8 月日照 = 275.6（实际 %.1f）" % sun[7])
	_check(cd.month_value("high_temp", 7) > 30.0,
			"7 月平均日高温 > 30（实际 %.1f）" % cd.month_value("high_temp", 7))
	_check(is_nan(cd.month_value("high_temp", 0)), "month=0 应返回 NAN")
	_check(is_nan(cd.month_value("不存在的键", 7)), "不存在的键应返回 NAN")

	# —— 2. 键在首列的排布 + 表头跳过 ——
	var d2 := ClimateData.new()
	var row_key_first := PackedStringArray(["平均日高温",
			"5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16"])
	var row_header := PackedStringArray(
			["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "月份", ""])
	var row_header_en := PackedStringArray(
			["month", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "月份"])
	_check(ClimateData._parse_row(row_header, d2) == false, "月份表头行应被跳过")
	_check(ClimateData._parse_row(row_header_en, d2) == false, "英文表头行（month 前缀）应被跳过")
	_check(ClimateData._parse_row(row_key_first, d2), "键在首列的行应可解析")
	_check(d2.monthly.has("high_temp"), "键在首列解析出 high_temp")

	# —— 3. 全年逐日生成（2087 平年）——
	# 天气型用数值字面量：0=晴 1=阴 2=雨（与 WeatherEngine.Sky 对齐）
	var eng := WeatherEngine.new(cd)
	var counts := {0: 0, 1: 0, 2: 0}
	var date := {"year": 2087, "month": 1, "day": 1}
	var days_2087 := 0
	while date.year == 2087:
		var rep := eng.day_report(date.year, date.month, date.day)
		_check_day(cd, date, rep)
		counts[rep["sky"]] += 1
		days_2087 += 1
		date = WeatherEngine.next_date(date.year, date.month, date.day)
	_check(days_2087 == 365, "2087 年应推进 365 天（实际 %d）" % days_2087)
	_check(date.year == 2088 and date.month == 1 and date.day == 1, "应推进到 2088-01-01")

	# —— 4. 平/闰年日期推进 ——
	var d229 := WeatherEngine.next_date(2088, 2, 28)
	_check(d229.month == 2 and d229.day == 29, "2088（闰年）2 月 28 日次日为 2 月 29 日")
	var d301 := WeatherEngine.next_date(2087, 2, 28)
	_check(d301.month == 3 and d301.day == 1, "2087（平年）2 月 28 日次日为 3 月 1 日")

	# —— 5. 跨月加权 ——
	var dec_high: float = cd.month_value("high_temp", 12)
	var jan_high: float = cd.month_value("high_temp", 1)
	var b1: float = eng._blend("high_temp", 1, 1, 2087)
	var expect1: float = lerpf(dec_high, jan_high, 0.5 / 7.5)
	_check(is_equal_approx(b1, expect1),
			"月初跨月加权 = lerp(12月, 1月, 1/15)（实际 %.2f vs %.2f）" % [b1, expect1])
	var b15: float = eng._blend("high_temp", 1, 15, 2087)
	_check(is_equal_approx(b15, jan_high), "月中央取本月纯值")

	# —— 6. 确定性 ——
	var a := eng.day_report(2087, 7, 15)
	var b := eng.day_report(2087, 7, 15)
	_check(a == b, "同一天两次生成结果一致")

	# —— 7. 分布合理性（宽松界）+ 样例打印 ——
	_check(counts[2] >= 20 and counts[2] <= 200,
			"全年雨天数量在合理区间（实际 %d）" % counts[2])
	var s := eng.day_report(2087, 7, 15)
	print("样例 2087-07-15：sky=%d high=%.1f low=%.1f rain=%.0f%%" % [
		s["sky"], s["high"], s["low"], s["rain_prob"] * 100.0])
	print("全年分布：晴 %d / 阴 %d / 雨 %d" % [counts[0], counts[1], counts[2]])

	# —— 8. MiniYaml 与设置存取 ——
	var yaml_data := {"cities": {"myksolonia": "瑰流", "quoted": "带\"引号"}, "worlds": {"default": "现实世界"}}
	var yaml_back := MiniYaml.parse(MiniYaml.dumps(yaml_data))
	_check(yaml_back.errors.is_empty(), "MiniYaml 序列化可回读且无错误")
	_check(yaml_back.data.get("cities", {}).get("myksolonia", "") == "瑰流", "MiniYaml 回读中文值")
	var yaml_parse2 := MiniYaml.parse("# 注释行\nworlds:\n  default: 现实世界\n")
	_check(yaml_parse2.errors.is_empty() and yaml_parse2.data.get("worlds", {}).get("default", "") == "现实世界",
			"MiniYaml 解析注释与分组")
	var yaml_bad := MiniYaml.parse("top_value: 1\n")
	_check(not yaml_bad.errors.is_empty(), "MiniYaml 拒绝顶层键值")

	SettingsStore.ensure_defaults()
	_check(SettingsStore.list_city_ids().size() >= 2, "检测到至少两座城市 CSV")
	var w := SettingsStore.load_world("default")
	_check(w.base_times.size() == 1, "默认世界含 1 条基准时间")
	w["base_times"].append({"id": "selftest_only", "offset_minutes": 30})
	_check(SettingsStore.save_world("default", w) == OK, "保存世界 JSON")
	var w2 := SettingsStore.load_world("default")
	_check(w2.base_times.size() == 2, "世界 JSON 回读条目数")
	w2["base_times"].remove_at(1)
	SettingsStore.save_world("default", w2)
	var city := SettingsStore.load_city("myksolonia")
	_check(city.has("long") and city.has("wallpaper") and city.has("effects"),
			"城市默认骨架字段齐全")
	_check(SettingsStore.city_display_name("myksolonia") != "", "城市本地化名可读")

	# —— 9. 世界随机搭台（WorldRng）——
	_check(WorldRng.stable_day_number(1970, 1, 2) == 0, "历法锚点日序为 0")
	_check(WorldRng.stable_day_number(1970, 1, 1) == 1, "锚点前一日镜像为 1（绕锚点折返）")
	var dn_old := WorldRng.stable_day_number(1862, 6, 15)
	_check(dn_old > 0, "锚点前日期镜像为正（%d）" % dn_old)
	_check(WorldRng.stable_day_number(1800, 6, 15) > dn_old, "越早的日期镜像后越大")
	_check(WorldRng.mirror_year(1862) == 2078, "年折返示例：1862 → 1970+(1970-1862) = 2078")
	var nc1 := WorldRng.name_code("default")
	_check(nc1 == WorldRng.name_code("default"), "世界名数字码恒定")
	_check(WorldRng.name_code("earth") != nc1, "不同世界名数字码不同")
	var seeds := WorldRng.world_seeds("default", 10240, 6, 15)
	_check(seeds.year_seed != seeds.month_seed and seeds.month_seed != seeds.day_seed,
			"三层种子互不相同")
	var seeds2 := WorldRng.world_seeds("default", 10240, 6, 16)
	_check(seeds.day_seed != seeds2.day_seed and seeds.year_seed == seeds2.year_seed,
			"跨日：日种子变化而年种子不变")
	var noise_a := WorldRng.city_noise("default", 31.2, 121.5)
	var noise_b := WorldRng.city_noise("default", 31.3, 121.6)
	_check(absf(noise_a - noise_b) < 0.1, "相邻坐标噪点平滑（%.3f vs %.3f）" % [noise_a, noise_b])
	var noise_wrap1 := WorldRng.city_noise("default", 10.0, 179.95)
	var noise_wrap2 := WorldRng.city_noise("default", 10.0, -179.95)
	_check(absf(noise_wrap1 - noise_wrap2) < 0.05, "180° 经线两侧噪点连续")
	_finish()


func _check_day(cd: ClimateData, date: Dictionary, rep: Dictionary) -> void:
	var key := "%04d-%02d-%02d" % [date.year, date.month, date.day]
	_check(is_finite(rep["high"]) and is_finite(rep["low"]), "温度为有限值 @%s" % key)
	_check(rep["low"] < rep["high"], "低温 < 高温 @%s" % key)
	_check(rep["rain_prob"] >= 0.05 - 0.0001 and rep["rain_prob"] <= 0.60 + 0.0001,
			"降雨可能在标定范围内 @%s" % key)
	# 记录钳制用的是跨月加权后的记录，因此断言取当月与两侧邻月记录的较宽界
	var m: int = date.month
	var rh: float = maxf(cd.month_value("record_high", m),
			maxf(cd.month_value("record_high", _adj_month(m, -1)),
					cd.month_value("record_high", _adj_month(m, 1))))
	var rl: float = minf(cd.month_value("record_low", m),
			minf(cd.month_value("record_low", _adj_month(m, -1)),
					cd.month_value("record_low", _adj_month(m, 1))))
	_check(rep["high"] <= rh + 1e-6, "高温 ≤ 当月及邻月记录上限 @%s" % key)
	_check(rep["low"] >= rl - 1e-6, "低温 ≥ 当月及邻月记录下限 @%s" % key)


func _adj_month(month: int, delta: int) -> int:
	return (month - 1 + delta + 12) % 12 + 1


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("[FAIL] " + msg)


func _finish() -> void:
	if _fails == 0:
		print("== 全部通过 ==")
	else:
		printerr("== %d 项失败 ==" % _fails)
	quit(1 if _fails > 0 else 0)
