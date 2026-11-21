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


## 恒定日历日序号：自锚点（1970-01-02）起算；锚点之前绕锚点镜像折返为正。
## 任何公历日期都得到一个非负整数，接缝处（1970-01-01 → 1，锚点日 → 0）连续单调。
static func stable_day_number(year: int, month: int, day: int) -> int:
	var t := int(Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": 0, "minute": 0, "second": 0,
	}))
	var days_since_epoch := int(floor(float(t) / 86400.0))
	var rel := days_since_epoch - 1  # 锚点是 unix 纪元后第 1 天
	return rel if rel >= 0 else -rel


## （备选）按“年”镜像：批复示例口径（1862 → 1970+(1970-1862) = 2108）。
static func mirror_year(year: int) -> int:
	return year if year >= ANCHOR_YEAR else 2 * ANCHOR_YEAR - year


## 世界名“逆编码 → 十进制化”：倒序后按 Unicode 码点做 Horner 折叠。
## 不同名字几乎必然得到不同数字；同名恒定。
static func name_code(world_id: String) -> int:
	var s := world_id.reverse()
	var code := 0
	for ch in s:
		code = (code * 0x110000 + ch.unicode_at(0)) & INT_MASK
	return code


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
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = name_code(world_id)
	n.frequency = frequency
	var ang := deg_to_rad(long)
	# 圆筒面采样：经度 → 圆周角度，纬度作第三维；半径取 1000 仅为把角度换成长度尺度
	return n.get_noise_3d(cos(ang) * 1000.0, sin(ang) * 1000.0, lati * 10.0)
