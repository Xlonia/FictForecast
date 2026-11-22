class_name MiniYaml
extends RefCounted
## 受限 YAML 子集（仅为本地化等简单配置服务，见《幻想气象局.md》城市设置：“name…本地化走yaml”）。
##
## 支持的语法：
##   · 顶层只能是分组行“键:”（无值）
##   · 组内为两空格缩进的“键: 值”，值一律按文本处理（可选成对引号）
##   · 整行 # 注释与空行
## 不支持：列表、行内注释、多行文本、更深嵌套、Tab 缩进、锚点——遇到会记录错误。
##
## parse() 返回 { "data": {组: {键: 值}}, "errors": [行错误…] }；
## dumps() 把 {组: {键: 值}} 序列化回文本（保留插入顺序）。

const INDENT := "  "


static func parse(text: String) -> Dictionary:
	var data := {}
	var errors: Array[String] = []
	var group := ""
	var lines := text.split("\n")
	for i in lines.size():
		var raw: String = lines[i].rstrip("\r")
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if raw.begins_with("\t"):
			errors.append("第 %d 行：不允许用 Tab 缩进，请用两个空格" % (i + 1))
			continue
		var indented := raw.begins_with(" ")
		var sep := line.find(":")
		if sep < 0:
			errors.append("第 %d 行：缺少冒号 —— %s" % [i + 1, line])
			continue
		var key := line.substr(0, sep).strip_edges()
		var value := ""
		if sep + 1 < line.length():
			value = _clean_value(line.substr(sep + 1).strip_edges())
		if key.is_empty():
			errors.append("第 %d 行：键为空" % (i + 1))
			continue
		if indented:
			if group.is_empty():
				errors.append("第 %d 行：缩进行出现在任何分组之前" % (i + 1))
				continue
			if not data.has(group):
				data[group] = {}
			data[group][key] = value
		else:
			if not value.is_empty():
				errors.append("第 %d 行：顶层不允许直接“键: 值”，请先建分组再缩进" % (i + 1))
				continue
			group = key
			if not data.has(group):
				data[group] = {}
	return {"data": data, "errors": errors}


## 把 {组: {键: 值}} 序列化为受限 YAML 文本。
static func dumps(data: Dictionary) -> String:
	var out := PackedStringArray()
	for group in data:
		var entries: Dictionary = data[group]
		out.append("%s:" % str(group))
		for key in entries:
			out.append("%s%s: %s" % [INDENT, str(key), _fmt_value(str(entries[key]))])
		out.append("")
	return "\n".join(out)


static func _clean_value(v: String) -> String:
	if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
		return v.substr(1, v.length() - 2).replace("\\\"", "\"")
	if v.length() >= 2 and v.begins_with("'") and v.ends_with("'"):
		return v.substr(1, v.length() - 2)
	return v


static func _fmt_value(v: String) -> String:
	if v.is_empty():
		return "\"\""
	if v.begins_with("#") or v.begins_with(" ") or v.begins_with("\"") or v.begins_with("'"):
		return "\"%s\"" % v.replace("\"", "\\\"")
	return v
