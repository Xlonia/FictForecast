class_name MapProjection
extends RefCounted
## 经纬度 ↔ 参考图归一化坐标（u 向右 0..1，v 向下 0..1，(0,0) 为图片左上角）。
##
## 两种圆柱投影，都假设参考图横向铺满整圈 360° 经度：
##   · equirectangular 等距圆柱：纬度线性铺满图高（90° 在上缘，−90° 在下缘）
##   · mercator 墨卡托：y = ln(tan(π/4 + φ/2))，裁剪到 ±lat_limit 后线性缩放铺满图高。
##     与 aiTests/…/纬度高度计算.py 同式：pixel_y = H/2 · (1 − y / y_max)。
## 中央经线 center_long = 图片水平中点所在的经度——0° 经线不必落在图片正中
## （现实地图常以别的经线为中心裁开）。经度在 ±180° 处环绕。
##
## 配置来自 Worlds/<世界ID>.json 的 map 字段（见 DEFAULTS）。
## 引擎本身只用经纬度、不经过投影——投影服务于编辑器定点，以及日后的现象路径与图层绘制。

const EQUIRECTANGULAR := "equirectangular"
const MERCATOR := "mercator"

const DEFAULTS := {
	"image": "",                # 参考图路径
	"projection": MERCATOR,     # mercator | equirectangular
	"lat_limit": 70.0,          # 墨卡托裁剪纬度上限 ±°
	"center_long": 0.0,         # 中央经线：图片水平中点所在的经度
}


## 补全并校验配置，返回**可写**副本（常量容器在运行期只读，不能直接改）。
static func normalized(cfg: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if cfg.get("projection") == EQUIRECTANGULAR or cfg.get("projection") == MERCATOR:
		out["projection"] = str(cfg["projection"])
	if _is_number(cfg.get("lat_limit")):
		out["lat_limit"] = clampf(float(cfg["lat_limit"]), 1.0, 89.9)
	if _is_number(cfg.get("center_long")):
		out["center_long"] = wrap_long(float(cfg["center_long"]))
	if typeof(cfg.get("image")) == TYPE_STRING:
		out["image"] = str(cfg["image"])
	return out


## 经度归一到 [−180°, 180°)——±180° 经线两侧是同一处。
static func wrap_long(lon: float) -> float:
	return wrapf(lon, -180.0, 180.0)


## 墨卡托纵坐标（R=1）：ln(tan(π/4 + φ/2))。
static func mercator_y(lat_deg: float) -> float:
	return log(tan(PI / 4.0 + deg_to_rad(lat_deg) / 2.0))


## 经纬度 → 归一化坐标。超出墨卡托纬度上限的纬度钉在图的上/下缘。
static func to_uv(lati: float, lon: float, cfg: Dictionary) -> Vector2:
	var u := wrap_long(lon - float(cfg.get("center_long", 0.0))) / 360.0 + 0.5
	var v: float
	if str(cfg.get("projection", MERCATOR)) == EQUIRECTANGULAR:
		v = (90.0 - clampf(lati, -90.0, 90.0)) / 180.0
	else:
		var lim := float(cfg.get("lat_limit", 70.0))
		v = 0.5 * (1.0 - mercator_y(clampf(lati, -lim, lim)) / mercator_y(lim))
	return Vector2(u, v)


## 归一化坐标 → 经纬度。返回 Vector2(x = 纬度, y = 经度)。
static func from_uv(uv: Vector2, cfg: Dictionary) -> Vector2:
	var lon := wrap_long(float(cfg.get("center_long", 0.0)) + (uv.x - 0.5) * 360.0)
	var lat: float
	if str(cfg.get("projection", MERCATOR)) == EQUIRECTANGULAR:
		lat = 90.0 - uv.y * 180.0
	else:
		var y_max := mercator_y(float(cfg.get("lat_limit", 70.0)))
		lat = rad_to_deg(2.0 * atan(exp((1.0 - 2.0 * uv.y) * y_max)) - PI / 2.0)
	return Vector2(lat, lon)


## 整圈 360° 宽的真墨卡托图，由图片纵横比反推纬度上限（宽:高 = 2π : 2·y_max）。
## 方图 → ±85.05°；不是整圈宽的图推出来没有意义。
static func lat_limit_from_aspect(width: int, height: int) -> float:
	if width <= 0 or height <= 0:
		return float(DEFAULTS["lat_limit"])
	var y_max := PI * float(height) / float(width)
	return clampf(rad_to_deg(2.0 * atan(exp(y_max)) - PI / 2.0), 1.0, 89.9)


## 若 0° 经线落在图片横向比例 u 处，中央经线应取多少。
static func center_long_for_zero_at(u: float) -> float:
	return wrap_long(-(u - 0.5) * 360.0)


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
