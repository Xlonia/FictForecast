class_name WorldRng
extends RefCounted
## 世界随机 · 搭台层（v0.0.1 m2 批复：只搭台，不接入引擎；气候现象实装时由引擎调用）。
##
## —— 批复口径 ——
## · 种子分层：世界一套（主导），城市不用种子、用柏林噪点按坐标平滑安放。
## · 世界三套种子（年/月/日），全部来自恒定锚定日历：公历。
## · 世界文件名“逆编码 → 十进制化”成数字，参与种子混合，让不同世界基底不同。
## · 恒定日历锚点：1970-01-02 00:00 UTC；锚点之前的日期按镜像折返为正，
##   避免负 Unix 时间戳（批复：把溢出的日期反过来，变成顺的）。
##   注意：批复示例是按“年”折返（1862→2108）；这里按时间戳折返（更平滑、无接缝），
##   两者对年度均值无影响（年度种子追究的是平均）。若要年折返可改 mirror_year()。
##
## · 城市噪点：在“经度圆筒面”上采 3D 柏林噪音——经度正负相连，
##   180° 经线两侧不会泾渭分明（批复：地图一节的要求）。海拔的几何打破后续接入。

const ANCHOR_YEAR := 1970
const ANCHOR_MONTH := 1
const ANCHOR_DAY := 2
const INT_MASK := 0x7FFFFFFF  # 名字码折叠上限 2^31，避免 64 位乘法溢出
const NAME_CODE_EMPTY := 0x1E3779B9  # 空世界名兜底常量（确定性，非 0——豆包意见：避免 0 值歧义）

static var _noise_cache := {}   # "world|freq" -> FastNoiseLite（平滑日噪声/城市噪点复用）
static var _field_cache := {}   # "world|field" -> FastNoiseLite（图表随机柏林面复用）

# —— 图表随机柏林面（批复：城市图表随机 = 世界宏观柏林噪音面，城市以经纬度读高度）——
# 与未来的气候现象柏林面相互独立：不同“面”按 id 对种子做修饰（十六进制插入法）。
const FIELD_TEMPERATURE := 0    # 图表随机·温度面
const FIELD_PRECIPITATION := 1  # 图表随机·降水比面


## 函数图种子修饰（批复口径）：种子转十六进制，函数图 id 以两位十六进制插入末尾，
## 再转回十进制。基底取十六进制末 14 位（56 位）+ 2 位 = 64 位，不会溢出。
static func field_seed(base_seed: int, field_id: int) -> int:
	var hex := "%x" % (base_seed & 0x0FFFFFFFFFFFFFFF)
	if hex.length() > 14:
		hex = hex.substr(hex.length() - 14)
	hex += "%02x" % (field_id & 0xFF)
	return hex.hex_to_int()


## 读取图表随机柏林面：城市以经纬度在圆筒面采样（±180° 经线连续），返回约 -1..1。
## 面的种子 = field_seed(世界名数字码, 面id)；绘制柏林面在世界地图上是 m5 的工作，
## v1 的面由种子程序化生成（“半占位半完善”）。
static func chart_field(world_id: String, field_id: int, lati: float, long: float) -> float:
	var ck := "%s|%d" % [world_id, field_id]
	var n: FastNoiseLite
	if _field_cache.has(ck):
		n = _field_cache[ck]
	else:
		n = FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.seed = field_seed(name_code(world_id), field_id)
		n.frequency = 0.02
		_field_cache[ck] = n
	var ang := deg_to_rad(long)
	return n.get_noise_3d(cos(ang) * 1000.0, sin(ang) * 1000.0, lati * 10.0)


## 世界时钟换算（批复口径）：现实 UTC + 时间系统偏差(分) + 历法锚定(天) → 显示日期时间。
## 用于“时间的异质感”——例如 Novera 锚定 +3000277 天 ≈ 公元 10240 年。
static func display_datetime(unix_utc: float, tz_min: int, cal_days: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(unix_utc) + tz_min * 60 + cal_days * 86400)


## 恒定日历日序号（**日期轨**）：自锚点（1970-01-02）起算；锚点之前绕锚点镜像折返为正。
## 任何公历日期都得到一个非负整数，接缝处（1970-01-01 → 1，锚点日 → 0）连续单调。
## m2.1 批复：时间戳**双轨**——日期与时间分开。日期轨只处理“日”，
## 日种子直接对应日期，不会把纯分钟换算进日期；分钟走时间轨（见 mirror_minutes）。
static func stable_day_number(year: int, month: int, day: int) -> int:
	var t := int(Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": 0, "minute": 0, "second": 0,
	}))
	var days_since_epoch := int(floor(float(t) / 86400.0))
	var rel := days_since_epoch - 1  # 锚点是 unix 纪元后第 1 天
	return rel if rel >= 0 else -rel


## 时间轨（**当日分钟**）：锚点为当日 00:00，负分钟镜像折返为正。
## 与日期轨独立——跨 00:00 的镜像不会把分钟换成日期（m2.1 批复“去掉纯分钟换算日期”）。
## 供后续时间系统/分钟级种子使用；当前引擎尚未消费。
static func mirror_minutes(minute_of_day: int) -> int:
	return minute_of_day if minute_of_day >= 0 else -minute_of_day


## （备选）按“年”镜像：批复示例口径（1862 → 1970+(1970-1862) = 2108）。
static func mirror_year(year: int) -> int:
	return year if year >= ANCHOR_YEAR else 2 * ANCHOR_YEAR - year


## 世界名“逆编码 → 十进制化”：倒序后按 UTF-8 字节展开，交由引擎 64 位混合哈希
## （m3 采纳豆包意见：Unicode 码点/字节展开不限 ASCII——支持虚构语言名；
##  混合本身完成分异，不需要额外校验字符；空名给确定性常量，非 0）。
static func name_code(world_id: String) -> int:
	if world_id.is_empty():
		return NAME_CODE_EMPTY
	return hash(world_id.reverse().to_utf8_buffer())


## 三层种子：年度 / 月度 / 日期（批复：世界随机构思）。
## 年度种子：气候现象对地区的总体影响 + 每月补偿/削弱系数的来源；
## 月度种子：现象的分配数量与出现日期；
## 日期种子：现象状态运行的波动。
static func world_seeds(world_id: String, year: int, month: int, day: int) -> Dictionary:
	var nc := name_code(world_id)
	var year_seed := hash("%d|%d|%d" % [nc, stable_day_number(year, 7, 1), 1])
	var month_seed := hash("%d|%d|%d" % [nc, stable_day_number(year, month, 1), 2])
	var day_seed := hash("%d|%d|%d" % [nc, stable_day_number(year, month, day), 3])
	return {
		"name_code": nc,
		"year_seed": year_seed,
		"month_seed": month_seed,
		"day_seed": day_seed,
	}


static func rng_from_seed(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


## 城市噪点：相近经纬度 → 相近数值（批复：城市随机构思——“用柏林噪音自带的平滑安放城市”）。
## 在经度圆筒面上采 3D 柏林噪音，保证 ±180° 经线连续。返回约 -1..1。
## 海拔不进噪音本体——批复要求海拔做“特定时刻各日间同期的随机差异”，由引擎层使用。
static func city_noise(world_id: String, lati: float, long: float, frequency := 0.02) -> float:
	var n := _noise_for(world_id, frequency)
	var ang := deg_to_rad(long)
	# 圆筒面采样：经度 → 圆周角度，纬度作第三维；半径取 1000 仅为把角度换成长度尺度
	return n.get_noise_3d(cos(ang) * 1000.0, sin(ang) * 1000.0, lati * 10.0)


## 平滑日噪声（月内平滑轨道）：按恒定日序采 2D 柏林噪音，相邻日期平滑连续。
## 返回约 -1..1。天气引擎用它做“低频平滑项”，与日种子原始噪声按 month_smoothing 插值。
## frequency 0.15 ≈ 相邻两天部分相关、一周尺度上有起伏。
static func smooth_day_noise(world_id: String, day_number: int, frequency := 0.15) -> float:
	var n := _noise_for(world_id, frequency)
	return n.get_noise_2d(float(day_number), float((name_code(world_id) >> 8) & 0xFFFF))


static func _noise_for(world_id: String, frequency: float) -> FastNoiseLite:
	var cache_key := "%s|%f" % [world_id, frequency]
	if _noise_cache.has(cache_key):
		return _noise_cache[cache_key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = name_code(world_id)
	n.frequency = frequency
	_noise_cache[cache_key] = n
	return n
