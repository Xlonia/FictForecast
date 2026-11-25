extends Window
## 偏好设置——嵌在主窗口内的子窗口（非独立窗口：随主程序关闭，拖不出主窗口）。
## 容纳《幻想气象局.md》「软件系统设置」里本批落地的三项：偏好城市、城市名称语言、
## 界面背景不透明度。偏好数据由主界面持有并负责写盘，本窗口只改数据、发信号。
## 关闭（标题栏 ✕ / 关闭按钮 / Esc）只是隐藏，再打开回到原位。
## [待定，0.0.2] 界面语言：界面字符串还没外置成可翻译资源，方案定了再加选择器。

signal preference_changed(key: String)

var prefs: Dictionary = {}  # 主界面传入的偏好字典（引用）

@onready var city_pick: OptionButton = $Panel/Column/CityRow/CityPick
@onready var lang_pick: OptionButton = $Panel/Column/LangRow/LangPick
@onready var opacity_slider: HSlider = $Panel/Column/OpacityRow/OpacitySlider
@onready var opacity_value: Label = $Panel/Column/OpacityRow/OpacityValue
@onready var close_btn: Button = $Panel/Column/Buttons/CloseBtn


func _ready() -> void:
	close_btn.pressed.connect(hide)
	city_pick.item_selected.connect(_on_city_picked)
	lang_pick.item_selected.connect(_on_lang_picked)
	opacity_slider.value_changed.connect(_on_opacity_changed)


## Esc 关闭（偏好窗口自己持有焦点时才收得到）。
func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()


func open() -> void:
	_sync()
	if visible:
		grab_focus()  # 已打开：提到前面（标题栏在内容区上方，嵌入窗口靠 popup_centered 摆位）
	else:
		popup_centered()


## 把偏好回填到控件（每次打开都重新读一遍：城市与语言文件可能被编辑器改过）。
func _sync() -> void:
	city_pick.clear()
	city_pick.add_item("（留空：启动时显示上次查看的城市）", 0)
	city_pick.set_item_metadata(0, "")
	for id in SettingsStore.list_city_ids():
		city_pick.add_item(_city_text(id), 0)
		city_pick.set_item_metadata(city_pick.item_count - 1, id)
	_select(city_pick, str(prefs.get("default_city", "")))

	var current_lang := str(prefs.get("city_name_lang", "zh"))
	var langs := SettingsStore.list_languages()
	lang_pick.clear()
	if not langs.has(current_lang):
		langs.append(current_lang)  # 文件已被删：仍列出当前值，免得下拉框显示成别的语言
	langs.sort()
	for lang in langs:
		lang_pick.add_item(lang, 0)
		lang_pick.set_item_metadata(lang_pick.item_count - 1, lang)
	_select(lang_pick, current_lang)

	opacity_slider.set_value_no_signal(float(prefs.get("panel_opacity", 0.9)))
	_show_opacity()


func _select(pick: OptionButton, meta: String) -> void:
	for i in pick.item_count:
		if str(pick.get_item_metadata(i)) == meta:
			pick.select(i)
			return


func _city_text(id: String) -> String:
	var name := SettingsStore.city_display_name(id, str(prefs.get("city_name_lang", "zh")))
	return id if name.is_empty() else "%s（%s）" % [id, name]


func _on_city_picked(index: int) -> void:
	prefs["default_city"] = str(city_pick.get_item_metadata(index))
	preference_changed.emit("default_city")


func _on_lang_picked(index: int) -> void:
	prefs["city_name_lang"] = str(lang_pick.get_item_metadata(index))
	preference_changed.emit("city_name_lang")
	_sync()  # 偏好城市下拉框里的名字要换成新语言


func _on_opacity_changed(v: float) -> void:
	prefs["panel_opacity"] = v
	_show_opacity()
	preference_changed.emit("panel_opacity")


func _show_opacity() -> void:
	opacity_value.text = "%d%%" % roundi(float(prefs.get("panel_opacity", 0.9)) * 100.0)
