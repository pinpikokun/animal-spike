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
	# ally/enemy_cpu_level: 0=弱 1=普通 2=強 3=最強(sim_cpu.gdのプリセットに対応)。
	# 開発中の既定は敵=最強・味方=最強。リリース時はストーリーモードが敵を上書きする
	return {"window_scale": 2, "fullscreen": false, "crt_on": false, "crt_intensity": 0.35,
		"ally_cpu_level": 3, "enemy_cpu_level": 3}

static func save(d: Dictionary) -> void:
	var cf := ConfigFile.new()
	for k in d.keys():
		cf.set_value("display", k, d[k])
	cf.save(PATH)

static func load_or_default(path: String = PATH) -> Dictionary:
	var cf := ConfigFile.new()
	var d := default_dict()
	if cf.load(path) != OK:
		return d
	var migrated: bool = false
	for key in ["wall_half", "net_top_original", "toss_assist"]:
		if cf.has_section_key("display", key):
			cf.erase_section_key("display", key)
			migrated = true
	if migrated:
		cf.save(path)
	for k in d.keys():
		d[k] = cf.get_value("display", k, d[k])
	return d
