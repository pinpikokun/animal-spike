# 最上位ルート。内部640x360のSubViewportを整数倍拡大して表示し、
# CRTシェーダー・表示オプション・デバッグビュー切替(F1)を管理する
extends Control

const DisplayScale := preload("res://src/display/display_scale.gd")
const DisplayOptions := preload("res://src/display/display_options.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const BootSeed := preload("res://src/app/boot_seed.gd")


const BASE_W := 640
const BASE_H := 360

var _container: SubViewportContainer
var _viewport: SubViewport
var _game: Node
var _debug: Node
var _showing_debug := false
var _menu
var _settings: Dictionary
var _select: Node  # キャラ選択画面(試合開始で破棄)
var _is_net := false  # ネット対戦モード(プロファイル切替の再起動を抑制)
var boot_seed: Variant = null
var _net_role := ""

func _ready() -> void:
	_container = $Container
	_viewport = $Container/Viewport
	# 起動引数 -- 以降に host/join があればネット対戦シーンへ差し替える(M2検証)
	var uargs := OS.get_cmdline_user_args()
	_net_role = "host" if uargs.has("host") else ("join" if uargs.has("join") else "")
	if _net_role != "join":
		boot_seed = BootSeed.read_from_system()
		if boot_seed == null:
			push_error("起動時計の時・分が不正なため実ゲームを開始できない")
			get_tree().quit(1)
			return
	if not _net_role.is_empty():
		_is_net = true
		_game = preload("res://src/net/net_match.tscn").instantiate()
		_game.net_role = _net_role
		_game.boot_seed = boot_seed
		if _net_role == "join":
			_game.boot_seed_agreed.connect(_on_net_boot_seed_agreed)
		_viewport.add_child(_game)
	else:
		# ローカルプレイはキャラ選択画面から(Escスキップで既定編成)
		_select = preload("res://src/display/char_select.gd").new()
		_select.done.connect(_start_local_game)
		_viewport.add_child(_select)
	_settings = DisplayOptions.load_or_default()
	_menu = $OptionsMenu
	_menu.setup(_settings)
	_menu.settings_changed.connect(_apply_settings)
	# メニュー表示中はローカル試合を完全停止(CPUもボールも止まる=ポーズ)。
	# ネット対戦は止めるとデシンクするので対象外
	_menu.visibility_changed.connect(_apply_pause)
	_menu.restart_requested.connect(func() -> void:
		if not _is_net:  # ネット対戦の途中離脱は切断=敗北フローで扱う(M2)
			_restart_to_select())
	get_viewport().size_changed.connect(_layout)
	_apply_settings()

func _start_local_game(roster: Array) -> void:
	if boot_seed == null:
		push_error("boot_seed未取得のためローカル試合を開始できない")
		get_tree().quit(1)
		return
	if _select != null:
		_viewport.remove_child(_select)
		_select.queue_free()
		_select = null
	_game = preload("res://src/display/game_view.tscn").instantiate()
	_game.roster = roster
	_game.boot_seed = boot_seed
	_viewport.add_child(_game)
	_apply_cpu_levels()
	_apply_pause()

func _on_net_boot_seed_agreed(agreed_seed: int) -> void:
	if boot_seed != null:
		var reason := "joinのboot_seedが二度通知された"
		push_error(reason)
		if _game != null and _game.has_method("stop_handshake"):
			_game.stop_handshake(reason)
		else:
			get_tree().quit(1)
		return
	boot_seed = agreed_seed

func _restart_to_select() -> void:
	# 進行中のローカル試合を破棄してキャラ選択からやり直す
	if _showing_debug:
		_toggle_debug()
	if _game != null:
		_viewport.remove_child(_game)
		_game.queue_free()
		_game = null
	if _select == null:
		_select = preload("res://src/display/char_select.gd").new()
		_select.done.connect(_start_local_game)
		_viewport.add_child(_select)

func _apply_pause() -> void:
	if _is_net:
		return
	var paused: bool = _menu.visible
	for node in [_game, _debug]:
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED if paused \
				else Node.PROCESS_MODE_INHERIT

func _apply_settings() -> void:
	DisplayOptions.apply_window(get_window(), int(_settings.window_scale), bool(_settings.fullscreen))
	DisplayOptions.save(_settings)
	_apply_cpu_levels()
	_layout()

func _apply_cpu_levels() -> void:
	# CPUの強さをsim状態へ反映(ローカルプレイのみ)。ネット対戦のstateは
	# SyncManagerが同期しており、片側だけの書き換えはデシンクになるため触らない
	var ally: int = SimCpu.PRESETS[clampi(int(_settings.ally_cpu_level), 0, 3)]
	var enemy: int = SimCpu.PRESETS[clampi(int(_settings.enemy_cpu_level), 0, 3)]
	for node in [_game, _debug]:
		if node == null or not ("state" in node) or node.state == null:
			continue
		if "external_sim" in node and node.external_sim:
			continue
		for i in 4:
			node.state.players[i].cpu = ally if i < 2 else enemy

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
		if event.keycode == KEY_F1 and _select == null:
			_toggle_debug()
		elif event.keycode == KEY_ESCAPE and _select == null:
			# キャラ選択中のEscは選択画面のスキップ操作に譲る
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
