# 最上位ルート。内部640x360のSubViewportを整数倍拡大して表示し、
# CRTシェーダー・表示オプション・デバッグビュー切替(F1)を管理する
extends Control

const DisplayScale := preload("res://src/display/display_scale.gd")
const DisplayOptions := preload("res://src/display/display_options.gd")

const BASE_W := 640
const BASE_H := 360

var _container: SubViewportContainer
var _viewport: SubViewport
var _game: Node
var _debug: Node
var _showing_debug := false
var _menu
var _settings: Dictionary

func _ready() -> void:
	_container = $Container
	_viewport = $Container/Viewport
	# 起動引数 -- 以降に host/join があればネット対戦シーンへ差し替える(M2検証)
	var uargs := OS.get_cmdline_user_args()
	if uargs.has("host") or uargs.has("join"):
		_game = preload("res://src/net/net_match.tscn").instantiate()
	else:
		_game = preload("res://src/display/game_view.tscn").instantiate()
	_viewport.add_child(_game)
	_settings = DisplayOptions.load_or_default()
	_menu = $OptionsMenu
	_menu.setup(_settings)
	_menu.settings_changed.connect(_apply_settings)
	get_viewport().size_changed.connect(_layout)
	_apply_settings()

func _apply_settings() -> void:
	DisplayOptions.apply_window(get_window(), int(_settings.window_scale), bool(_settings.fullscreen))
	DisplayOptions.save(_settings)
	_layout()

func _layout() -> void:
	var win: Vector2i = get_window().size
	var scale: int = DisplayScale.max_integer_scale(win.x, win.y, BASE_W, BASE_H)
	var size := Vector2(BASE_W * scale, BASE_H * scale)
	_container.stretch_shrink = scale
	_container.size = size
	_container.position = (Vector2(win) - size) / 2.0
	var mat: ShaderMaterial = _container.material
	mat.set_shader_parameter("scale_px", float(scale))
	var strength: float = DisplayScale.clamp_intensity(float(_settings.crt_intensity))
	mat.set_shader_parameter("intensity", strength if bool(_settings.crt_on) else 0.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_toggle_debug()
		elif event.keycode == KEY_ESCAPE:
			_menu.toggle()

func _toggle_debug() -> void:
	# 開発計器(SIM DEBUG VIEW)と本番ビューを入れ替える。
	# remove_childしたノードは処理が止まるのでシムが二重進行しない
	_showing_debug = not _showing_debug
	if _showing_debug:
		_viewport.remove_child(_game)
		if _debug == null:
			_debug = preload("res://src/display/main.tscn").instantiate()
		_viewport.add_child(_debug)
	else:
		_viewport.remove_child(_debug)
		_viewport.add_child(_game)
