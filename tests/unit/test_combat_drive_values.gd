extends "res://tests/test_case.gd"

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")

const EXPECTED_DRIVE_RULES := {
	"drive_gauge_max": 100,
	"normal_attack_drive_gain": 15,
	"attack_recovery_ticks_per_point": 30,
	"attack_recovery_window_ticks": 180,
	"just_attack_drive_cost": 25,
	"just_attack_recovery_delay_ticks": 60,
	"special_drive_cost_default": 35,
	"special_recovery_delay_ticks": 90,
	"passive_return_drive_cost": 10,
	"receive_stance_reserve_cost": 5,
	"receive_stance_exit_recovery_ticks": 9,
	"just_receive_window_ticks": 10,
	"dive_receive_drive_cost": 15,
	"dive_burnout_distance_pct": 80,
	"dive_burnout_recovery_pct": 130,
	"block_start_drive_cost": 5,
	"block_contact_drive_cost": 5,
	"burnout_recovery_ticks": 600,
	"burnout_exit_drive": 30,
}

func _combat_resources():
	return load("res://src/sim/combat_resources.gd")

func test_numeric_drive_contract() -> void:
	var file := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	var cfg = SimConfig.new()
	for key in EXPECTED_DRIVE_RULES:
		var expected: int = EXPECTED_DRIVE_RULES[key]
		check_eq(raw.get(key), expected, "rules.jsonの%s" % key)
		check(key in cfg, "SimConfigに%sを定義" % key)
		if key in cfg:
			check_eq(cfg.get(key), expected, "SimConfigの%s" % key)
	for old_key in ["drive_gauge_stock", "drive_recovery_ticks_per_stock",
			"drive_recovery_delay_ticks"]:
		check(not raw.has(old_key), "旧ドライブ設定を削除: %s" % old_key)
		check(not (old_key in cfg), "旧ドライブプロパティを削除: %s" % old_key)

func test_available_drive_excludes_reservation_and_burnout() -> void:
	var resources = _combat_resources()
	check(resources != null, "戦闘リソース共通APIが存在")
	if resources == null:
		return
	var p := SimState.Player.new()
	p.drive_gauge = 35
	p.drive_reserved = 5
	check_eq(resources.available_drive(p), 30, "予約5を利用可能値から除外")
	check(resources.can_pay(p, 30), "利用可能値ちょうどなら支払える")
	check(not resources.can_pay(p, 31), "予約分へ食い込む支払いは禁止")
	p.burnout_ticks = 1
	check_eq(resources.available_drive(p), 0, "バーンアウト中は実体値があっても利用不可")

func test_committed_cost_requires_full_payment_and_starts_burnout_at_zero() -> void:
	var resources = _combat_resources()
	check(resources != null, "戦闘リソース共通APIが存在")
	if resources == null:
		return
	var cfg = SimConfig.new()
	var p := SimState.Player.new()
	p.drive_gauge = 24
	var denied: Dictionary = resources.spend_committed(p, 25, cfg)
	check_eq(denied, {"authorized": false, "spent": 0, "depleted": false},
		"24では25の行動を部分成立させない")
	check_eq(p.drive_gauge, 24, "不成立時は実体値を変えない")
	check_eq(p.burnout_ticks, 0, "不成立時はバーンアウトしない")
	p.drive_gauge = 25
	var paid: Dictionary = resources.spend_committed(p, 25, cfg)
	check_eq(paid, {"authorized": true, "spent": 25, "depleted": true},
		"25なら全額払いで成立")
	check_eq(p.drive_gauge, 0, "全額消費で0")
	check_eq(p.burnout_ticks, 600, "実体値0到達でバーンアウト")

func test_special_cost_and_mandatory_cost_use_numeric_values() -> void:
	var resources = _combat_resources()
	check(resources != null, "戦闘リソース共通APIが存在")
	if resources == null:
		return
	var cfg = SimConfig.new()
	check_eq(resources.special_drive_cost(cfg), 35, "全必殺技の共通コスト")
	var p := SimState.Player.new()
	p.drive_gauge = 7
	check_eq(resources.spend_mandatory(p, 10, cfg), 7,
		"強制消費は利用可能な実体値だけ払う")
	check_eq(p.drive_gauge, 0, "強制消費も0で止まる")
	check_eq(p.burnout_ticks, 600, "強制消費の0到達もバーンアウト")

func test_reservation_zero_does_not_start_burnout() -> void:
	var resources = _combat_resources()
	check(resources != null, "戦闘リソース共通APIが存在")
	if resources == null:
		return
	var p := SimState.Player.new()
	p.drive_gauge = 5
	p.drive_reserved = 5
	check_eq(resources.available_drive(p), 0, "予約で利用可能値0")
	check_eq(p.drive_gauge, 5, "予約は実体値を減らさない")
	check_eq(p.burnout_ticks, 0, "予約だけではバーンアウトしない")
