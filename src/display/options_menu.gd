# 表示オプションメニュー。ウィンドウ倍率/フルスクリーン/CRTを設定する
# ウィンドウ解像度で描く(CanvasLayerはSubViewportの外)
extends CanvasLayer

signal settings_changed
signal restart_requested  # キャラ選択(タイトル)からやり直す(ローカルのみ)

const SCALES := [2, 3, 4]
const CPU_LEVELS := ["弱", "普通", "強", "最強"]

var _settings: Dictionary
var _panel: PanelContainer

func setup(settings: Dictionary) -> void:
	_settings = settings
	_build()
	visible = false

func toggle() -> void:
	visible = not visible

func _build() -> void:
	_panel = PanelContainer.new()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)

	var title := Label.new()
	title.text = "表示設定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var scale_btn := OptionButton.new()
	for s in SCALES:
		scale_btn.add_item("ウィンドウ %d倍 (%dx%d)" % [s, 640 * s, 360 * s])
	var idx := SCALES.find(int(_settings.window_scale))
	scale_btn.selected = idx if idx >= 0 else 0
	scale_btn.item_selected.connect(_on_scale)
	v.add_child(scale_btn)

	var fs := CheckBox.new()
	fs.text = "フルスクリーン(整数倍+黒枠)"
	fs.button_pressed = bool(_settings.fullscreen)
	fs.toggled.connect(_on_fullscreen)
	v.add_child(fs)

	var crt := CheckBox.new()
	crt.text = "CRTスキャンライン"
	crt.button_pressed = bool(_settings.crt_on)
	crt.toggled.connect(_on_crt)
	v.add_child(crt)

	var lbl := Label.new()
	lbl.text = "CRT強度"
	v.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(_settings.crt_intensity)
	slider.value_changed.connect(_on_intensity)
	v.add_child(slider)

	var cpu_lbl := Label.new()
	cpu_lbl.text = "CPUの強さ"
	v.add_child(cpu_lbl)

	var ally := OptionButton.new()
	for name in CPU_LEVELS:
		ally.add_item("味方CPU: " + name)
	ally.selected = clampi(int(_settings.ally_cpu_level), 0, CPU_LEVELS.size() - 1)
	ally.item_selected.connect(_on_ally_cpu)
	v.add_child(ally)

	var enemy := OptionButton.new()
	for name in CPU_LEVELS:
		enemy.add_item("敵CPU: " + name)
	enemy.selected = clampi(int(_settings.enemy_cpu_level), 0, CPU_LEVELS.size() - 1)
	enemy.item_selected.connect(_on_enemy_cpu)
	v.add_child(enemy)

	var phys_lbl := Label.new()
	phys_lbl.text = "物理トグル(次の試合から)"
	v.add_child(phys_lbl)

	var wall := CheckBox.new()
	wall.text = "壁反射を原作式(勢い半減)"
	wall.button_pressed = bool(_settings.wall_half)
	wall.toggled.connect(func(on: bool) -> void:
		_settings.wall_half = on
		settings_changed.emit())
	v.add_child(wall)

	var net_top := CheckBox.new()
	net_top.text = "ネット上端を原作式(当たって落ちる)"
	net_top.button_pressed = bool(_settings.net_top_original)
	net_top.toggled.connect(func(on: bool) -> void:
		_settings.net_top_original = on
		settings_changed.emit())
	v.add_child(net_top)

	var toss := CheckBox.new()
	toss.text = "トス自動補正(定位置へ逆算=いいとこ取り)"
	toss.button_pressed = bool(_settings.toss_assist)
	toss.toggled.connect(func(on: bool) -> void:
		_settings.toss_assist = on
		settings_changed.emit())
	v.add_child(toss)

	var restart := Button.new()
	restart.text = "キャラ選択からやり直す"
	restart.pressed.connect(func() -> void:
		visible = false
		restart_requested.emit())
	v.add_child(restart)

	var close := Button.new()
	close.text = "閉じる (ESC)"
	close.pressed.connect(func() -> void: visible = false)
	v.add_child(close)

	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func _on_scale(idx: int) -> void:
	_settings.window_scale = SCALES[idx]
	settings_changed.emit()

func _on_fullscreen(on: bool) -> void:
	_settings.fullscreen = on
	settings_changed.emit()

func _on_crt(on: bool) -> void:
	_settings.crt_on = on
	settings_changed.emit()

func _on_intensity(v: float) -> void:
	_settings.crt_intensity = v
	settings_changed.emit()

func _on_ally_cpu(idx: int) -> void:
	_settings.ally_cpu_level = idx
	settings_changed.emit()

func _on_enemy_cpu(idx: int) -> void:
	_settings.enemy_cpu_level = idx
	settings_changed.emit()
