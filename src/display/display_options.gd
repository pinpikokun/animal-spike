# 表示設定の適用と永続化。表示層
extends RefCounted

const BASE_W := 640
const BASE_H := 360
const PATH := "user://settings.cfg"

static func apply_window(win: Window, scale: int, fullscreen: bool) -> void:
	if fullscreen:
		win.mode = Window.MODE_FULLSCREEN
	else:
		win.mode = Window.MODE_WINDOWED
		win.size = Vector2i(BASE_W * scale, BASE_H * scale)

static func default_dict() -> Dictionary:
	return {"window_scale": 2, "fullscreen": false, "crt_on": false, "crt_intensity": 0.35}

static func save(d: Dictionary) -> void:
	var cf := ConfigFile.new()
	for k in d.keys():
		cf.set_value("display", k, d[k])
	cf.save(PATH)

static func load_or_default() -> Dictionary:
	var cf := ConfigFile.new()
	var d := default_dict()
	if cf.load(PATH) != OK:
		return d
	for k in d.keys():
		d[k] = cf.get_value("display", k, d[k])
	return d
