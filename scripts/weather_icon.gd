class_name WeatherIcon
extends Control
## 矢量绘制的天气图标（晴 / 阴 / 雨），带轻微动画：
## 太阳光线缓慢旋转，云朵轻微漂移，雨滴循环下落。

## 与 WeatherEngine.Sky 数值一致（0=晴 1=阴 2=雨）；GDScript 常量折叠
## 不解析跨类枚举成员，故此处用本地枚举。
enum SkyKind { SUNNY, CLOUDY, RAINY }

var sky: int = SkyKind.SUNNY:
	set(value):
		sky = value
		queue_redraw()

var snow := false:  # 雨（雪）天：画雪花而不是雨滴
	set(value):
		snow = value
		queue_redraw()

var _time := 0.0
var _cloud_light := StyleBoxFlat.new()
var _cloud_dark := StyleBoxFlat.new()


func _ready() -> void:
	_cloud_light.bg_color = Color(0.93, 0.95, 0.97)
	_cloud_light.set_corner_radius_all(64)
	_cloud_dark.bg_color = Color(0.70, 0.76, 0.84)
	_cloud_dark.set_corner_radius_all(64)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var m := minf(w, h)
	match sky:
		SkyKind.SUNNY:
			_draw_sun(Vector2(w * 0.5, h * 0.52), m * 0.22, 1.0)
		SkyKind.CLOUDY:
			_draw_sun(Vector2(w * 0.32, h * 0.36), m * 0.17, 0.6)
			_draw_cloud(Vector2(w * 0.55 + sin(_time * 0.7) * 3.0, h * 0.62), m * 0.30, _cloud_light)
		SkyKind.RAINY:
			_draw_cloud(Vector2(w * 0.50 + sin(_time * 0.7) * 3.0, h * 0.40), m * 0.30, _cloud_dark)
			if snow:
				_draw_snow(w, h)
			else:
				_draw_rain(w, h)


func _draw_sun(center: Vector2, radius: float, strength: float) -> void:
	for i in 8:
		var dir := Vector2.from_angle(TAU * i / 8.0 + _time * 0.35)
		draw_line(center + dir * (radius + 7.0), center + dir * (radius + 17.0),
				Color(1.0, 0.84, 0.31, 0.85 * strength), 3.0, true)
	draw_circle(center, radius, Color(1.0, 0.84, 0.31, strength))
	draw_circle(center, radius * 0.8, Color(1.0, 0.90, 0.55, strength))


func _draw_cloud(center: Vector2, radius: float, style: StyleBoxFlat) -> void:
	draw_circle(center + Vector2(-radius * 0.85, radius * 0.10), radius * 0.60, style.bg_color)
	draw_circle(center + Vector2(0.0, -radius * 0.15), radius * 0.82, style.bg_color)
	draw_circle(center + Vector2(radius * 0.85, radius * 0.12), radius * 0.55, style.bg_color)
	draw_style_box(style, Rect2(
			center.x - radius * 1.30, center.y - radius * 0.05,
			radius * 2.60, radius * 0.72))


func _draw_rain(w: float, h: float) -> void:
	var n := 7
	for i in n:
		var phase := fposmod(_time * 0.45 + float(i) / float(n), 1.0)
		var x := w * (0.25 + 0.50 * float(i) / float(n - 1)) + sin(_time * 2.0 + float(i)) * 2.0
		var y := h * (0.55 + phase * 0.38)
		var alpha := clampf(sin(phase * PI) * 1.4, 0.0, 1.0)
		draw_line(Vector2(x, y), Vector2(x, y + 10.0),
				Color(0.50, 0.70, 0.98, 0.85 * alpha), 2.5, true)


func _draw_snow(w: float, h: float) -> void:
	var n := 7
	for i in n:
		var phase := fposmod(_time * 0.22 + float(i) / float(n), 1.0)
		var x := w * (0.25 + 0.50 * float(i) / float(n - 1)) + sin(_time * 1.2 + float(i) * 1.7) * 7.0
		var y := h * (0.55 + phase * 0.38)
		var alpha := clampf(sin(phase * PI) * 1.4, 0.0, 1.0)
		var center := Vector2(x, y)
		draw_circle(center, 3.0, Color(0.93, 0.96, 1.0, 0.95 * alpha))
		for k in 3:  # 六瓣小星
			var dir := Vector2.from_angle(PI * float(k) / 3.0)
			draw_line(center - dir * 4.5, center + dir * 4.5, Color(0.93, 0.96, 1.0, 0.6 * alpha), 1.2, true)
