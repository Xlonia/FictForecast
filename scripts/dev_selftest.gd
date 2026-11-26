extends SceneTree
## 开发自检（不随游戏运行，headless 执行）：
##   godot --headless --path . --script res://scripts/dev_selftest.gd
## 覆盖：CSV 解析（两种列排布/表头跳过）、全年逐日生成、记录钳制、
## 日期推进（平/闰年）、跨月加权、确定性、世界随机、投影（含新经纬范围模型）、
## 界面语言（UiText 翻译/清单/译文覆盖）、语言字体。

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

	# —— 7. 分布合理性（雨日锁定口径）+ 样例打印 ——
	var expected_rain := 0
	for m in range(1, 13):
		expected_rain += clampi(roundi(cd.month_value("rain_days", m)), 0, WeatherEngine._days_in_month(2087, m))
	_check(counts[2] == expected_rain,
			"全年雨日数锁定为 Σ rain_days（实际 %d / 期望 %d）" % [counts[2], expected_rain])
	var s := eng.day_report(2087, 7, 15)
	print("样例 2087-07-15：sky=%d high=%.1f low=%.1f rain=%.0f%%" % [
		s["sky"], s["high"], s["low"], s["rain_prob"] * 100.0])
	print("全年分布：晴 %d / 阴 %d / 雨 %d" % [counts[0], counts[1], counts[2]])

	# —— 8. MiniYaml 与设置存取 ——
	var yaml_data := {"cities": {"myksolonia": "瑰流", "quoted": "带\"引号"},
			"ui": {"关闭": "Close", "res://x": "带冒号的键"}}
	var yaml_back := MiniYaml.parse(MiniYaml.dumps(yaml_data))
	_check(yaml_back.errors.is_empty(), "MiniYaml 序列化可回读且无错误")
	_check(yaml_back.data.get("cities", {}).get("myksolonia", "") == "瑰流", "MiniYaml 回读中文值")
	_check(yaml_back.data.get("ui", {}).get("res://x", "") == "带冒号的键",
			"键里的冒号（后不跟空格）不当作分隔符")
	var yaml_parse2 := MiniYaml.parse("# 注释行\nworlds:\n  default: 现实世界\n")
	_check(yaml_parse2.errors.is_empty() and yaml_parse2.data.get("worlds", {}).get("default", "") == "现实世界",
			"MiniYaml 解析注释与分组")
	var yaml_bad := MiniYaml.parse("top_value: 1\n")
	_check(not yaml_bad.errors.is_empty(), "MiniYaml 拒绝顶层键值")

	SettingsStore.ensure_defaults()
	_check(SettingsStore.list_city_ids().size() >= 2, "检测到至少两座城市 CSV")
	_check(not SettingsStore.list_world_ids().has("default.phenomena"),
			"世界列表不含现象文件（list_world_ids 排除 *.phenomena.json）")
	var city_defaults := SettingsStore.CITY_DEFAULTS.duplicate(true)
	_check(city_defaults.has("anchor") and city_defaults.has("map_x") and city_defaults.has("map_y"),
			"城市骨架含锚定字段（anchor / map_x / map_y）")
	_check(str(SettingsStore.PREFS_DEFAULTS.get("ui_lang", "")) == "zh", "偏好骨架含界面语言 ui_lang")
	# 世界 JSON 回写测试：只写**临时世界文件**，用后即删——自检不得改写用户的真实数据
	var tw := "__selftest_world__"
	var tw_path := SettingsStore.WORLDS_DIR.path_join(tw + ".json")
	_check(not FileAccess.file_exists(tw_path), "测试世界文件事先不存在（否则上次自检中途失败）")
	var w: Dictionary = SettingsStore.load_world("__no_such_world__")
	w["seed"] = "selftest"
	w["base_times"] = [{"id": "selftest_only", "offset_minutes": 30}]
	w["map"] = MapProjection.normalized({"center_long": 90.0})
	_check(SettingsStore.save_world(tw, w) == OK, "保存世界 JSON（临时世界）")
	var w2 := SettingsStore.load_world(tw)
	_check(w2.base_times.size() == 1 and str(w2.base_times[0].get("id", "")) == "selftest_only",
			"世界 JSON 回读：基准时间")
	_check(str(w2["seed"]) == "selftest", "世界 JSON 回读：种子字段")
	var w2_map: Dictionary = w2["map"]
	_check(is_equal_approx(float(w2_map.get("center_long", 0.0)), 90.0), "map 字段随世界 JSON 往返")
	_check(w2_map.has("lat_top") and w2_map.has("lat_bottom") and w2_map.has("lon_span"),
			"map 字段补全新骨架（lat_top / lat_bottom / lon_span）")
	DirAccess.remove_absolute(tw_path)
	_check(not FileAccess.file_exists(tw_path), "测试世界文件已删除")
	var city := SettingsStore.load_city("myksolonia")
	_check(city.has("long") and city.has("wallpaper") and city.has("effects"),
			"城市默认骨架字段齐全")
	_check(SettingsStore.city_display_name("myksolonia") != "", "城市本地化名可读")

	# —— 9. 世界随机搭台（WorldRng）——
	_check(WorldRng.stable_day_number(1970, 1, 2) == 0, "历法锚点日序为 0")
	_check(WorldRng.stable_day_number(1970, 1, 1) == 1, "锚点前一日镜像为 1（绕锚点折返）")
	_check(WorldRng.mirror_minutes(-90) == 90 and WorldRng.mirror_minutes(30) == 30,
			"时间轨分钟镜像（双轨：与日期轨无关）")
	var dn_old := WorldRng.stable_day_number(1862, 6, 15)
	_check(dn_old > 0, "锚点前日期镜像为正（%d）" % dn_old)
	_check(WorldRng.stable_day_number(1800, 6, 15) > dn_old, "越早的日期镜像后越大")
	_check(WorldRng.mirror_year(1862) == 2078, "年折返示例：1862 → 1970+(1970-1862) = 2078")
	var nc1 := WorldRng.name_code("default")
	_check(nc1 == WorldRng.name_code("default"), "世界名数字码恒定")
	_check(WorldRng.name_code("earth") != nc1, "不同世界名数字码不同")
	_check(WorldRng.name_code("") == WorldRng.NAME_CODE_EMPTY, "空世界名给确定性兜底码")
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
	_check(absf(noise_wrap1 - noise_wrap2) < 0.1,
			"180° 经线两侧噪点连续（±0.1，实测 %.3f）" % absf(noise_wrap1 - noise_wrap2))

	# —— 10. m3：月度确定性生成（雨日锁定/降水对账/距平零和/露点）——
	var world_data := SettingsStore.load_world("Novera")
	world_data["monthly_total_strength"] = 1.0
	var eng3 := WeatherEngine.new(cd, "Novera", world_data, {"lati": 31.2, "long": 121.5})
	var mr := eng3.month_report(2087, 7)
	_check(mr.rain_target == 26,
			"7 月雨日锁定 26 天（raint=25.6，实际 %d）" % mr.rain_target)
	var precip_sum := 0.0
	for e in mr.day_entries:
		precip_sum += e.precip_mm
	_check(absf(precip_sum - mr.precip_total) < 0.05,
			"降水量对账：月总和 = rmean × 年降水比（%.1f vs %.1f）" % [precip_sum, mr.precip_total])
	var mean_a := 0.0
	for e in mr.day_entries:
		mean_a += e.anomaly
	mean_a /= mr.day_entries.size()
	_check(absf(mean_a) < 0.001, "温度距平零和（月积温凑齐，均值残差 %.6f）" % mean_a)
	var mr2 := eng3.month_report(2087, 7)
	_check(mr == mr2, "月度生成确定性（两次一致）")
	var mr_next_year := eng3.month_report(2088, 7)
	_check(mr != mr_next_year, "年度种子生效：跨年同月结果不同")
	for t in [-10.0, 0.0, 20.0, 35.0]:
		for rh in [20.0, 50.0, 80.0]:
			var td: float = WeatherEngine._dewpoint_from(t, rh)
			var back: float = WeatherEngine._rh_from(t, td)
			_check(absf(back - rh) < 0.5, "露点往返 t=%.0f rh=%.0f → %.1f%%" % [t, rh, back])

	# —— 11. 图表随机柏林面 + 世界时钟换算 ——
	var fs0 := WorldRng.field_seed(12345, 0)
	var fs1 := WorldRng.field_seed(12345, 1)
	_check(fs0 == WorldRng.field_seed(12345, 0), "函数图种子恒定（十六进制插入法）")
	_check(fs0 != fs1, "不同函数图 id 种子不同")
	var ft := WorldRng.chart_field("Novera", WorldRng.FIELD_TEMPERATURE, 31.2, 121.5)
	var ft2 := WorldRng.chart_field("Novera", WorldRng.FIELD_TEMPERATURE, 31.3, 121.6)
	_check(absf(ft - ft2) < 0.1, "温度面相邻坐标平滑（%.3f vs %.3f）" % [ft, ft2])
	var fc := WorldRng.chart_field("Novera", WorldRng.FIELD_CLOUD, 31.2, 121.5)
	var fw := WorldRng.chart_field("Novera", WorldRng.FIELD_WIND, 31.2, 121.5)
	_check(fc != fw, "云量面与风面互相独立")
	var ft_time := WorldRng.chart_field("Novera", WorldRng.FIELD_TEMPERATURE, 31.2, 121.5, 6.0)
	_check(ft != ft_time, "时间轴调试参数生效（4D 面可选演进）")
	_check(absf(WorldRng.chart_field("Novera", WorldRng.FIELD_TEMPERATURE, 31.2, 121.5, 0.0) - ft) < 1e-9,
			"时间轴 0 = 静态面（默认行为不变）")
	var dt0 := WorldRng.display_datetime(0.0, 0, 0)
	_check(dt0.year == 1970 and dt0.month == 1 and dt0.day == 1 and dt0.hour == 0, "历法零点换算")
	var dt_tz := WorldRng.display_datetime(0.0, 420, 0)
	_check(dt_tz.hour == 7, "时区叠加 +420 分 → 07:00")
	var dt_cal := WorldRng.display_datetime(0.0, 0, 3000277)
	_check(dt_cal.year > 10000, "历法锚定 +3000277 天 → 万年历（%d 年）" % dt_cal.year)

	# —— 12. 地图投影（新经纬范围模型；对账《纬度高度计算.py》：画布 2048、±70°）——
	var mcfg := MapProjection.normalized({"projection": "mercator", "lat_limit": 70.0, "center_long": 0.0})
	_check(mcfg["projection"] == "mercator" and mcfg["image"] == "", "地图配置补全骨架")
	_check(is_equal_approx(float(mcfg["lat_top"]), 70.0) and is_equal_approx(float(mcfg["lat_bottom"]), -70.0),
			"旧字段 lat_limit 迁移为上下缘纬度（±70）")
	_check(is_equal_approx(float(mcfg["lon_span"]), 360.0), "默认覆盖整圈经度")
	_check(not mcfg.is_read_only(), "地图配置可写（常量容器须深拷贝）")
	_check(absf(MapProjection.mercator_y(70.0) - 1.735415162669) < 1e-9, "墨卡托 y(70°) = 1.735415")
	# 期望值由《纬度高度计算.py》原式算出：pixel_y = (H/2)·(1 − y/y_max)，H = 2048
	var ref := {
		66.57: 95.667211, 45.0: 503.936229, 35.5: 632.481461, 0.0: 1024.0,
		-30.0: 1348.123878, -66.57: 1952.332789, -70.0: 2048.0, 70.0: 0.0,
	}
	for lat in ref:
		var py := MapProjection.to_uv(float(lat), 0.0, mcfg).y * 2048.0
		_check(absf(py - float(ref[lat])) < 1e-4,
				"墨卡托对账 Python 工具：纬度 %.2f° → %.6f（期望 %.6f）" % [float(lat), py, float(ref[lat])])
	# 往返：Vector2 分量是 32 位浮点，u/v 过一遍有 ~1e-6° 的舍入噪声，
	# 断言取 1e-4°（≈11 米，远小于城市坐标 0.01° 的取整精度）
	for lat in [-65.0, -45.5, -12.3, 0.0, 0.7, 33.3, 59.9, 65.0]:
		for lon in [-180.0, -179.0, -90.0, -0.5, 0.0, 0.5, 121.47, 179.9]:
			var back := MapProjection.from_uv(MapProjection.to_uv(float(lat), float(lon), mcfg), mcfg)
			var dlon := MapProjection.wrap_long(back.y - float(lon))
			_check(absf(back.x - float(lat)) < 1e-4 and absf(dlon) < 1e-4,
					"墨卡托往返 lat=%.1f lon=%.2f" % [float(lat), float(lon)])
	var c150 := MapProjection.normalized({"center_long": 150.0})
	_check(is_equal_approx(MapProjection.to_uv(0.0, 150.0, c150).x, 0.5), "中央经线 150°：150° 落在图片正中")
	_check(is_equal_approx(MapProjection.to_uv(0.0, 0.0, c150).x, 0.5 - 150.0 / 360.0),
			"中央经线 150°：0° 经线在 1/12 处")
	_check(is_equal_approx(MapProjection.to_uv(0.0, 180.0, c150).x, MapProjection.to_uv(0.0, -180.0, c150).x),
			"±180° 映射到同一处（经度环绕）")
	_check(is_equal_approx(MapProjection.center_long_for_zero_at(0.25, mcfg), 90.0), "0° 经线点在 1/4 处 → 中央经线 90°")
	_check(is_equal_approx(MapProjection.center_long_for_zero_at(0.75, mcfg), -90.0), "0° 经线点在 3/4 处 → 中央经线 −90°")
	# 非整圈经度：span 120、中央 60 → u=0.25 处经度 30；u 越出 0..1 = 空位
	var s120 := MapProjection.normalized({"center_long": 60.0, "lon_span": 120.0})
	_check(is_equal_approx(MapProjection.from_uv(Vector2(0.25, 0.5), s120).y, 30.0),
			"覆盖 120°：u=0.25 → 经度 30°")
	_check(MapProjection.to_uv(0.0, 180.0, s120).x > 1.0, "覆盖 120°：圈外经度的 u 越出 1（空位）")
	_check(is_equal_approx(MapProjection.center_long_for_zero_at(0.25, s120), 30.0),
			"覆盖 120°：点选 0° 经线按 span 换算")
	# 上下不对称 + 点选赤道：赤道挪到 v=0.25 时比例尺（窗口差）不变
	var asym := MapProjection.normalized({"lat_top": 60.0, "lat_bottom": -40.0})
	var d_before := MapProjection.mercator_y(60.0) - MapProjection.mercator_y(-40.0)
	var moved := MapProjection.lat_window_for_equator_at(0.25, asym)
	var d_after := MapProjection.mercator_y(float(moved["lat_top"])) - MapProjection.mercator_y(float(moved["lat_bottom"]))
	_check(absf(d_after - d_before) < 1e-6, "点选赤道保持比例尺（窗口差 %.6f → %.6f）" % [d_before, d_after])
	_check(absf(MapProjection.equator_v(moved) - 0.25) < 1e-4, "赤道落在点选的位置（v=0.25）")
	# 按图片比例推算（真墨卡托图纵横比例尺一致）
	var sq := MapProjection.lat_window_from_aspect(2048, 2048, MapProjection.normalized({}))
	_check(absf(float(sq["lat_top"]) - 85.051129) < 1e-3 and absf(float(sq["lat_bottom"]) + 85.051129) < 1e-3,
			"方图整圈 → ±85.051°（实际 +%.3f / −%.3f）" % [float(sq["lat_top"]), float(sq["lat_bottom"])])
	var half := MapProjection.lat_window_from_aspect(4096, 2048, MapProjection.normalized({}))
	_check(absf(float(half["lat_top"]) - 66.513) < 0.01,
			"4096×2048 整圈 → ±66.51°（实际 %.3f，用户的参考图口径）" % float(half["lat_top"]))
	var ec120 := MapProjection.normalized({"projection": "equirectangular", "center_long": 60.0, "lon_span": 120.0})
	var half_span := MapProjection.lat_window_from_aspect(2048, 2048, ec120)
	_check(absf(float(half_span["lat_top"]) - 60.0) < 0.01 and absf(float(half_span["lat_bottom"]) + 60.0) < 0.01,
			"等距圆柱 span 120 方图 → ±60°（实际 +%.3f / −%.3f）" % [float(half_span["lat_top"]), float(half_span["lat_bottom"])])
	var ecfg := MapProjection.normalized({"projection": "equirectangular"})
	_check(is_equal_approx(float(ecfg["lat_top"]), 90.0) and is_equal_approx(float(ecfg["lat_bottom"]), -90.0),
			"等距圆柱默认图高 ±90°（与旧版行为一致）")
	_check(MapProjection.to_uv(90.0, 0.0, ecfg).y == 0.0 and MapProjection.to_uv(-90.0, 0.0, ecfg).y == 1.0,
			"等距圆柱：±90° 铺满图高")
	_check(is_equal_approx(MapProjection.to_uv(45.0, 0.0, ecfg).y, 0.25), "等距圆柱：45°N 在 1/4 高")

	# —— 13. 设置存取：缺键的默认值必须可写且互不共享 ——
	var wa := SettingsStore.load_world("__no_such_world__")
	var wb := SettingsStore.load_world("__no_such_world__")
	_check(not (wa["base_times"] as Array).is_read_only(), "缺键的数组默认值可写")
	(wa["base_times"] as Array).append({"id": "probe"})
	_check((wa["base_times"] as Array).size() == 1 and (wb["base_times"] as Array).is_empty(),
			"默认值深拷贝：两次加载互不共享")
	var wa_map: Dictionary = wa["map"]
	wa_map["lat_top"] = 33.0
	var wb_map: Dictionary = wb["map"]
	_check(wb_map.is_empty() and not wa_map.is_empty(), "map 默认值互不共享（另一份仍是空骨架）")
	_check(is_equal_approx(float(MapProjection.normalized(wb_map)["lat_top"]), 70.0),
			"空 map 经 normalized 补全后 lat_top 为默认 70")
	_check(SettingsStore.WORLD_DEFAULTS.has("map"), "世界骨架含 map 字段")

	# —— 14. 偏好文件（临时文件，用后即删）——
	var pp := "user://ff_selftest_prefs.json"
	SettingsStore._save_json(pp, {"default_city": "myksolonia", "panel_opacity": 2.0, "ui_lang": "en"})
	var pr := SettingsStore._load_json(pp, SettingsStore.PREFS_DEFAULTS)
	_check(pr["default_city"] == "myksolonia" and pr["last_city"] == ""
			and typeof(pr["city_name_lang"]) == TYPE_STRING and str(pr["ui_lang"]) == "en",
			"偏好加载：文件值与默认骨架合并（含 ui_lang）")
	_check(is_equal_approx(float(pr["panel_opacity"]), 2.0), "偏好原始值读回（钳制在 load_preferences）")
	DirAccess.remove_absolute(pp)

	# —— 15. 界面语言（UiText：翻译 / 回退 / 宽容格式化 / 清单 / 译文覆盖）——
	var srcs: Dictionary = UiText.scan_sources()
	_check(srcs.size() > 200, "界面字符串清单扫出 %d 条（>200）" % srcs.size())
	var bad_keys := 0
	for k in srcs:
		var ks := str(k)
		if ks != ks.strip_edges() or ks.contains(": ") or ks.contains("\n"):
			bad_keys += 1
	_check(bad_keys == 0, "清单键都可作为受限 YAML 的键（无首尾空格/冒号空格/换行）")
	for lang in ["en", "ja"]:
		var aud: Dictionary = UiText.audit(lang)
		var miss: int = (aud["missing"] as Dictionary).size()
		var stale: int = (aud["stale"] as Dictionary).size()
		_check(miss == 0, "%s 译文覆盖：缺 %d 条（清单 %d 条）" % [lang, miss, int(aud["sources"])])
		_check(stale == 0, "%s 译文无失效键（清单里已不存在的）" % lang)
	# 临时语言文件：翻译生效、缺条目回退原文、zh 的 ui 组可改中文措辞
	var tmp_lang_path := SettingsStore.loc_path("__selftest__")
	SettingsStore.save_localization_file(tmp_lang_path, {"ui": {"关闭": "CLOSED", "没有这句": "NOPE"}})
	UiText.set_language("__selftest__")
	_check(UiText.t("关闭") == "CLOSED", "界面译文生效（临时语言）")
	_check(UiText.t("偏好设置") == "偏好设置", "缺译文回退中文原文")
	_check(UiText.f("城市：%s", ["X"]) == "城市：X", "未翻译的格式串原样套参数")
	_check(UiText.format("%d 只 = %.1f 只", [3, 3]) == "3 只 = 3.0 只", "类型不匹配时安全转换")
	_check(UiText.format("%s-%s", ["a"]) == "a-%s", "参数不够时占位符原样保留")
	_check(UiText.format("100%% %s", ["ok"]) == "100% ok", "%% 转义")
	SettingsStore._loc_cache.erase(tmp_lang_path)
	DirAccess.remove_absolute(tmp_lang_path)
	var zh_ui: Dictionary = SettingsStore.load_localization().data.get("ui", {})
	UiText.set_language("zh")
	_check(UiText.t("关闭") == "关闭", "回退 zh：无 ui 组时返回原文")

	# —— 16. 语言定义与字体（临时定义，用后即删；Xnidnise 字体覆盖格鲁吉亚文区）——
	var tl := "__selftest__"
	var def_path := SettingsStore.language_def_path(tl)
	SettingsStore.save_language_def(tl, {"name": "自检语", "font": "res://fictlanguages/fonts/Xnidnise_italic-Regular.ttf"})
	_check(SettingsStore.language_display_name(tl) == "自检语", "语言定义 name 生效")
	var f := SettingsStore.language_font(tl)
	_check(f != null, "语言字体加载成功")
	if f != null:
		_check(f.has_char(0x10E5), "字体覆盖格鲁吉亚文 U+10E5（Unicode 原文映射）")
		_check((f.fallbacks as Array).size() == 1, "字体回退链挂在界面默认字体上")
	SettingsStore._font_cache.clear()
	SettingsStore.save_language_def(tl, {"name": "", "font": ""})
	_check(SettingsStore.language_display_name(tl) == tl, "name 留空显示语言代码")
	SettingsStore._font_cache.clear()
	DirAccess.remove_absolute(def_path)
	SettingsStore.invalidate_localization_cache()
	_finish()


func _check_day(cd: ClimateData, date: Dictionary, rep: Dictionary) -> void:
	var key := "%04d-%02d-%02d" % [date.year, date.month, date.day]
	_check(is_finite(rep["high"]) and is_finite(rep["low"]), "温度为有限值 @%s" % key)
	_check(rep["low"] < rep["high"], "低温 < 高温 @%s" % key)
	_check(rep["rain_prob"] >= 0.0 and rep["rain_prob"] <= 1.0,
			"降雨可能为当月雨日占比 0..1 @%s" % key)
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
