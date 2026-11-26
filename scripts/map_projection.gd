class_name MapProjection
extends RefCounted
## 经纬度 ↔ 参考图归一化坐标。
##
## 坐标约定：u 向右、v 向下，0..1 是图片本体，(0,0) 为图片左上角。u 允许越出 0..1——
## 图片不覆盖整圈经度（lon_span < 360）时，越出的部分就是“空位”（没有参考图的经度）。
##
## 图片在世界里的位置由四个量决定（都存在 Worlds/<世界ID>.json 的 map 字段，见 DEFAULTS）：
##   · center_long  图片水平中点所在的经度——0° 经线不必落在图片正中
##   · lon_span     图片宽度覆盖的经度范围（默认整圈 360°）
##   · lat_top / lat_bottom  图片上缘 / 下缘的纬度——上下裁剪不对称的图靠这两个量
##     赤道在图上的位置由它们算出（equator_v）；“点选赤道”用 lat_window_for_equator_at 反推
## 两种圆柱投影：
##   · mercator 墨卡托：图上纵向与 y = ln(tan(π/4 + φ/2)) 成正比
##     （与 aiTests/…/纬度高度计算.py 同式：pixel_y = H/2 · (1 − y / y_max) 是上下对称时的特例）
##   · equirectangular 等距圆柱：图上纵向与纬度成正比
##
## 引擎本身只用经纬度、不经过投影——投影服务于编辑器定点，以及日后的现象路径与图层绘制。

const EQUIRECTANGULAR := "equirectangular"
const MERCATOR := "mercator"

const LAT_MAX := 89.9     # 墨卡托在极点发散，纬度取值限制在此范围内
const MIN_WINDOW := 1.0   # 上缘与下缘至少相隔多少度（避免除零）

const DEFAULTS := {
	"image": "",                # 参考图路径
	"projection": MERCATOR,     # mercator | equirectangular
	"lon_span": 360.0,          # 图片宽度覆盖的经度范围（≤ 360）
	"lat_top": 70.0,            # 图片上缘的纬度
	"lat_bottom": -70.0,        # 图片下缘的纬度
	"center_long": 0.0,         # 中央经线：图片水平中点所在的经度
}


## 补全并校验配置，返回**可写**副本（常量容器在运行期只读，不能直接改）。
## 旧世界文件只有 lat_limit（上下对称裁剪）时自动换算成上缘 / 下缘纬度。
static func normalized(cfg: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var c: Dictionary = cfg if typeof(cfg) == TYPE_DICTIONARY else {}
	var proj: String = str(c.get("projection", ""))
	if proj == EQUIRECTANGULAR or proj == MERCATOR:
		out["projection"] = proj
	if _is_number(c.get("lon_span")):
		out["lon_span"] = clampf(float(c["lon_span"]), 1.0, 360.0)
	if _is_number(c.get("lat_top")) and _is_number(c.get("lat_bottom")):
		out["lat_top"] = float(c["lat_top"])
		out["lat_bottom"] = float(c["lat_bottom"])
	elif _is_number(c.get("lat_limit")):
		# 旧字段：墨卡托取 ±lat_limit；等距圆柱当初不消费这个字段（图高恒为 ±90°），保持原行为
		if str(out["projection"]) == MERCATOR:
			out["lat_top"] = float(c["lat_limit"])
			out["lat_bottom"] = -float(c["lat_limit"])
		else:
			out["lat_top"] = 90.0
			out["lat_bottom"] = -90.0
	elif str(out["projection"]) == EQUIRECTANGULAR:
		out["lat_top"] = 90.0     # 等距圆柱的默认图高仍是 ±90°（与 m3.7 的行为一致）
		out["lat_bottom"] = -90.0
	var lat_cap := 90.0 if str(out["projection"]) == EQUIRECTANGULAR else LAT_MAX
	out["lat_top"] = clampf(float(out["lat_top"]), -lat_cap, lat_cap)
	out["lat_bottom"] = clampf(float(out["lat_bottom"]), -lat_cap, lat_cap)
	if float(out["lat_top"]) - float(out["lat_bottom"]) < MIN_WINDOW:
		out["lat_bottom"] = float(out["lat_top"]) - MIN_WINDOW
	if _is_number(c.get("center_long")):
		out["center_long"] = wrap_long(float(c["center_long"]))
	if typeof(c.get("image")) == TYPE_STRING:
		out["image"] = str(c["image"])
	return out


## 经度归一到 [−180°, 180°)——±180° 经线两侧是同一处。
static func wrap_long(lon: float) -> float:
	return wrapf(lon, -180.0, 180.0)


## 墨卡托纵坐标（R=1）：ln(tan(π/4 + φ/2))。
static func mercator_y(lat_deg: float) -> float:
	return log(tan(PI / 4.0 + deg_to_rad(lat_deg) / 2.0))


## 墨卡托纵坐标 → 纬度。
static func lat_from_mercator_y(y: float) -> float:
	return rad_to_deg(2.0 * atan(exp(y)) - PI / 2.0)


## 图片纵向位置的换算基准：等距圆柱用纬度，墨卡托用 y。返回 [上缘值, 下缘值]。
static func _v_axis(cfg: Dictionary) -> Vector2:
	if str(cfg.get("projection", MERCATOR)) == EQUIRECTANGULAR:
		return Vector2(float(cfg.get("lat_top", 70.0)), float(cfg.get("lat_bottom", -70.0)))
	return Vector2(mercator_y(float(cfg.get("lat_top", 70.0))),
			mercator_y(float(cfg.get("lat_bottom", -70.0))))


## 经纬度 → 归一化坐标。越出图片范围的经纬度不做钳制（u 越出 = 空位，v 越出 = 图外），由调用方决定。
static func to_uv(lati: float, lon: float, cfg: Dictionary) -> Vector2:
	var u := wrap_long(lon - float(cfg.get("center_long", 0.0))) / float(cfg.get("lon_span", 360.0)) + 0.5
	var axis := _v_axis(cfg)
	var top := clampf(lati, -90.0, 90.0) if str(cfg.get("projection", MERCATOR)) == EQUIRECTANGULAR \
			else mercator_y(clampf(lati, -LAT_MAX, LAT_MAX))
	var v := (axis.x - top) / (axis.x - axis.y)
	return Vector2(u, v)


## 归一化坐标 → 经纬度。返回 Vector2(x = 纬度, y = 经度)。
static func from_uv(uv: Vector2, cfg: Dictionary) -> Vector2:
	var lon := wrap_long(float(cfg.get("center_long", 0.0))
			+ (uv.x - 0.5) * float(cfg.get("lon_span", 360.0)))
	var axis := _v_axis(cfg)
	var val := axis.x - uv.y * (axis.x - axis.y)
	var lat: float
	if str(cfg.get("projection", MERCATOR)) == EQUIRECTANGULAR:
		lat = clampf(val, -90.0, 90.0)
	else:
		lat = lat_from_mercator_y(val)
	return Vector2(lat, lon)


## 赤道落在图片纵向的什么位置（0 = 上缘，1 = 下缘；可越出 0..1 = 图里没有赤道）。
static func equator_v(cfg: Dictionary) -> float:
	return to_uv(0.0, 0.0, cfg).y


## 把赤道挪到图片纵向比例 v_eq 处——图片内容不动、比例尺不变，返回新的 {lat_top, lat_bottom}。
## 上下裁剪不对称的图：点一下赤道所在的那一行即可。
static func lat_window_for_equator_at(v_eq: float, cfg: Dictionary) -> Dictionary:
	var axis := _v_axis(cfg)
	var d := axis.x - axis.y
	var top_new := v_eq * d
	var bottom_new := top_new - d
	if str(cfg.get("projection", MERCATOR)) == EQUIRECTANGULAR:
		return {"lat_top": clampf(top_new, -90.0, 90.0), "lat_bottom": clampf(bottom_new, -90.0, 90.0)}
	return {"lat_top": clampf(lat_from_mercator_y(top_new), -LAT_MAX, LAT_MAX),
		"lat_bottom": clampf(lat_from_mercator_y(bottom_new), -LAT_MAX, LAT_MAX)}


## 真墨卡托图纵横比例尺一致：由图片宽高比、覆盖经度与当前赤道位置反推上下缘纬度。
## 方图整圈 → ±85.05°（赤道在正中时）。等距圆柱同理（每像素度数相同）。
static func lat_window_from_aspect(width: int, height: int, cfg: Dictionary) -> Dictionary:
	if width <= 0 or height <= 0:
		return {"lat_top": float(cfg.get("lat_top", 70.0)), "lat_bottom": float(cfg.get("lat_bottom", -70.0))}
	var v_eq := equator_v(cfg)
	var deg_per_px := float(cfg.get("lon_span", 360.0)) / float(width)
	if str(cfg.get("projection", MERCATOR)) == EQUIRECTANGULAR:
		return {"lat_top": clampf(v_eq * height * deg_per_px, -90.0, 90.0),
			"lat_bottom": clampf(-(1.0 - v_eq) * height * deg_per_px, -90.0, 90.0)}
	var y_per_px := deg_to_rad(deg_per_px)
	return {"lat_top": clampf(lat_from_mercator_y(v_eq * height * y_per_px), -LAT_MAX, LAT_MAX),
		"lat_bottom": clampf(lat_from_mercator_y(-(1.0 - v_eq) * height * y_per_px), -LAT_MAX, LAT_MAX)}


## 若 0° 经线落在图片横向比例 u 处，中央经线应取多少。
static func center_long_for_zero_at(u: float, cfg: Dictionary) -> float:
	return wrap_long(-(u - 0.5) * float(cfg.get("lon_span", 360.0)))


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
