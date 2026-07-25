extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const DisplayOptions := preload("res://src/display/display_options.gd")
const OptionsMenu := preload("res://src/display/options_menu.gd")

func _count_checkboxes(node: Node) -> int:
	var count: int = 1 if node is CheckBox else 0
	for child in node.get_children():
		count += _count_checkboxes(child)
	return count

func test_loads_default_rules() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.tick_rate, 60, "tick_rate")
	check_eq(cfg.court_width, FP.from_int(448), "court_width")
	check_eq(cfg.floor_y, FP.from_int(320), "floor_y")
	check_eq(cfg.points_to_win, 11, "11点先取(原作準拠)")
	check_eq(cfg.deuce, true, "デュース有")
	check_eq(cfg.spike_normal_pct, 33, "通常アタック速度33%(A=49%が旧50%相当)")
	check_eq(cfg.spike_power_pct, 53, "ジャストアタック速度53%(A=79%が旧80%相当)")
	check_eq(cfg.spike_sweet_pct, 45, "ジャスト判定はリーチ45%以内")

func test_receive_rules_loaded() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.receive_offset_gain_pct, 100, "レシーブ接触オフセット倍率100%")
	check_eq(cfg.receive_scatter, FP.from_int(12) / cfg.tick_rate,
		"レシーブ散り幅12px/s")
	check_eq(cfg.receive_vx_max, FP.from_int(45) / cfg.tick_rate,
		"レシーブ横速度上限45px/s")
	check_eq(cfg.cpu_mate_spacing, FP.from_int(72),
		"CPU相方の守備間隔72px")

func test_drive_gauge_rules_loaded() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.drive_gauge_stock, 1000, "ドライブゲージ1本の内部単位")
	check_eq(cfg.drive_gauge_max, 6000, "ドライブゲージ6本満タン")
	check_eq(cfg.drive_recovery_ticks_per_stock, 240, "自然回復は1本240tick")
	check_eq(cfg.drive_recovery_delay_ticks, 180, "ゲージ減少後の自然回復停止は180tick")
	check_eq(cfg.just_receive_window_ticks, 10, "ジャストレシーブ入力窓は10tick")
	check_eq(cfg.burnout_recovery_ticks, 600, "バーンアウト復帰は600tick")
	check_eq(cfg.hip_quake_stun_ticks, 6, "ヒップ着地地震の全員硬直は6tick")

func test_absolute_damage_and_stun_mash_rules_loaded() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.guard_max_by_rank, [120, 110, 100, 90, 80],
		"GUARD A-E絶対値")
	check_eq(cfg.power_guard_damage_by_rank, [35, 30, 25, 20, 15],
		"POWER A-Eジャスト削り絶対値")
	check_eq(cfg.stun_ticks, 240, "気絶は4秒=240tick")
	check_eq(cfg.burn_stun_ticks, 90, "炎上行動不能は1.5秒=90tick")
	check_eq(cfg.burn_launch_height_px, 80, "炎上打ち上げ頂点は80px")
	check_eq(cfg.stun_mash_bonus, 3, "気絶中の押下エッジは追加3tick短縮")
	var file := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	check(not raw.has("guard_dmg_power"), "旧固定削りキーは撤去")

func test_guard_heal_just_is_removed() -> void:
	var cfg = SimConfig.new()
	check(not ("guard_heal_just" in cfg), "回復全廃により設定プロパティを残さない")
	var file := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	check(not raw.has("guard_heal_just"), "回復全廃によりrules.jsonキーを残さない")

func test_default_rules_valid() -> void:
	check_eq(SimConfig.new().valid, true, "既定ルールはvalid")

func test_original_wall_is_the_only_configured_rule() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.wall_bounce_num, 50, "壁反射は常時50%")
	check(not ("net_top_original" in cfg), "ネット上端トグルはSimConfigから削除")
	check(not ("toss_aim" in cfg), "トス補正トグルはSimConfigから削除")

func test_removed_physics_settings_are_absent_from_defaults_and_rules() -> void:
	var defaults: Dictionary = DisplayOptions.default_dict()
	for key in ["wall_half", "net_top_original", "toss_assist"]:
		check(not defaults.has(key), "表示設定から削除: %s" % key)
	var file := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	for key in ["net_top_original", "toss_aim"]:
		check(not raw.has(key), "rules.jsonから削除: %s" % key)
	var menu = OptionsMenu.new()
	menu.setup(defaults)
	check_eq(_count_checkboxes(menu), 2,
		"オプションUIのチェック項目はフルスクリーンとCRTのみ")
	menu.free()

func test_obsolete_display_settings_are_erased_on_load() -> void:
	var path := "user://test_batch_c_settings.cfg"
	var legacy := ConfigFile.new()
	legacy.set_value("display", "window_scale", 3)
	legacy.set_value("display", "wall_half", true)
	legacy.set_value("display", "net_top_original", true)
	legacy.set_value("display", "toss_assist", true)
	check_eq(legacy.save(path), OK, "旧設定fixtureを書き込める")
	var loaded: Dictionary = DisplayOptions.load_or_default(path)
	check_eq(loaded.window_scale, 3, "現役設定は維持")
	var migrated := ConfigFile.new()
	check_eq(migrated.load(path), OK, "移行済み設定を再読込")
	for key in ["wall_half", "net_top_original", "toss_assist"]:
		check(not migrated.has_section_key("display", key), "旧キーを消去: %s" % key)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_invalid_rules_detected() -> void:
	# 下のUSER ERROR出力はこのテストが意図的に出させているもの(異常系の検証)
	var cfg = SimConfig.new("res://tests/fixtures/bad_rules.json")
	check_eq(cfg.valid, false, "floatを含むルールはinvalidになる")

func test_m1a_keys_loaded() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.net_x, FP.from_int(224), "net_x")
	check_eq(cfg.max_touches, 3, "max_touches")
	check(cfg.spike_vx > 0, "spike_vxが正")
	check(cfg.serve_vy > 0, "serve_vy(上向き量)が正")
	check(cfg.hit_cooldown_ticks > 0, "hit_cooldownが正")
	check_eq(cfg.spawn_back_px, 56, "spawn_back_px")
	check_eq(cfg.toss_zone_back_px, 56, "トス上手の自陣後方ゾーン")
	check_eq(cfg.toss_zone_front_px, 157, "トス上手の自陣前方ゾーン")

func test_values_are_int() -> void:
	var cfg = SimConfig.new()
	check(typeof(cfg.gravity) == TYPE_INT, "gravityがint")
	check(typeof(cfg.move_speed) == TYPE_INT, "move_speedがint")
	check(typeof(cfg.jump_speed) == TYPE_INT, "jump_speedがint")
	check(cfg.gravity > 0, "gravityが正")
	check(cfg.move_speed > 0, "move_speedが正")
