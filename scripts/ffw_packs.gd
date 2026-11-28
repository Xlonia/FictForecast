class_name FfwPacks
extends RefCounted
## .ffw 内容包（m3.13 批复）：单文件分发的内容包 = zip，内部目录与数据根完全同构
## （Climate/ Cities/ Worlds/ Localization/ Maps/——手动解压进 data/ 也能用）。
##
## 优先级：data/ffmods/*.ffw（文件名升序，**靠后者赢**，可用 99_修复.ffw 排序）
##          > data/ 散文件（编辑器写的就是这里）> 内置基线。
## 覆盖规则：
##   · Climate/ Worlds/ Cities/ Maps/ 的文件 = **整文件覆盖**（包里有就以包为准）；
##   · Localization/<语言>.yaml = **键级合并**（包的条目逐键覆盖基线，其余保留）——
##     正好命中“同一座城市、不同的表达文本”的补丁场景：包可以只带一个键。
##
## 缓存：条目与字节按包 mtime 校验；invalidate() 供「重新加载」与导入新包时调用。

const DIR_NAME := "ffmods"

static var _entries := {}   # pack_path -> [mtime, PackedStringArray]
static var _bytes := {}     # pack_path + "!" + internal -> [mtime, PackedByteArray]


static func dir() -> String:
	return SettingsStore.data_root().path_join(DIR_NAME)


static func invalidate() -> void:
	_entries.clear()
	_bytes.clear()
	SettingsStore.invalidate_ffw_loc()


## 数据根下现存的内容包，按文件名升序（读取优先级：越靠后越高）。
static func pack_paths() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(SettingsStore.os_path(dir()))
	if d == null:
		return out
	var names := PackedStringArray()
	for f in d.get_files():
		if f.get_extension().to_lower() == "ffw":
			names.append(f)
	names.sort()
	for n in names:
		out.append(dir().path_join(n))
	return out


## 包内条目清单（跳过目录项；统一为 “目录/文件” 相对路径）。
static func entries(pack_path: String) -> PackedStringArray:
	var mtime := _mtime(pack_path)
	if _entries.has(pack_path) and _entries[pack_path][0] == mtime:
		return _entries[pack_path][1]
	var out := PackedStringArray()
	var z := ZIPReader.new()
	if z.open(SettingsStore.os_path(pack_path)) != OK:
		return out
	for e in z.get_files():
		var rel := str(e).replace("\\", "/")
		if rel.ends_with("/") or rel.begins_with("./"):
			rel = rel.trim_prefix("./")
		if rel.is_empty() or rel.ends_with("/"):
			continue
		out.append(rel)
	z.close()
	_entries[pack_path] = [mtime, out]
	return out


static func read_bytes(pack_path: String, internal: String) -> PackedByteArray:
	var mtime := _mtime(pack_path)
	var ck := pack_path + "!" + internal
	if _bytes.has(ck) and _bytes[ck][0] == mtime:
		return _bytes[ck][1]
	var z := ZIPReader.new()
	if z.open(SettingsStore.os_path(pack_path)) != OK:
		return PackedByteArray()
	var data := z.read_file(internal) if z.file_exists(internal) else PackedByteArray()
	z.close()
	_bytes[ck] = [mtime, data]
	return data


static func read_text(pack_path: String, internal: String) -> String:
	var b := read_bytes(pack_path, internal)
	return b.get_string_from_utf8() if b.size() > 0 else ""


## 某个数据根相对路径（如 "Worlds/Novera.json"）被哪个包覆盖：返回**优先级最高**的包路径；
## 没有任何包覆盖返回 ""。
static func winner_for(rel_path: String) -> String:
	var rel := rel_path.replace("\\", "/")
	var hit := ""
	for p in pack_paths():
		if entries(p).has(rel):
			hit = p
	return hit


## 整文件覆盖口径的读取：包优先；没有任何包带这个文件时返回 ""（调用方回落散文件）。
static func read_data_text(rel_path: String) -> String:
	var p := winner_for(rel_path)
	return read_text(p, rel_path.replace("\\", "/")) if p != "" else ""


static func _mtime(path: String) -> int:
	var os_path := SettingsStore.os_path(path)
	return FileAccess.get_modified_time(os_path) if FileAccess.file_exists(os_path) else 0
