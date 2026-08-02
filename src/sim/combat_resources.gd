# 戦闘リソースの整数状態遷移。シミュレーション層以外の状態を読まない。
extends RefCounted

static func available_drive(p) -> int:
	if p.burnout_ticks > 0:
		return 0
	return maxi(p.drive_gauge - p.drive_reserved, 0)

static func can_pay(p, amount: int) -> bool:
	return amount >= 0 and available_drive(p) >= amount

static func special_drive_cost(cfg) -> int:
	return cfg.special_drive_cost_default

static func start_burnout(p, cfg) -> void:
	if p.burnout_ticks > 0:
		return
	stop_attack_recovery(p)
	p.burnout_ticks = cfg.burnout_recovery_ticks

static func tick_burnout(p, active: bool, cfg) -> void:
	if p.burnout_ticks <= 0 or not active:
		return
	stop_attack_recovery(p)
	p.burnout_ticks -= 1
	if p.burnout_ticks == 0:
		p.drive_gauge = cfg.burnout_exit_drive

static func stop_attack_recovery(p) -> void:
	p.attack_recovery_delay_ticks = 0
	p.attack_recovery_window_ticks = 0
	p.attack_recovery_fraction_ticks = 0
	p.attack_recovery_granted = 0

static func start_attack_recovery(p, delay_ticks: int, cfg) -> void:
	stop_attack_recovery(p)
	if p.burnout_ticks > 0:
		return
	p.attack_recovery_delay_ticks = maxi(delay_ticks, 0)
	p.attack_recovery_window_ticks = cfg.attack_recovery_window_ticks

static func tick_attack_recovery(p, active: bool, cfg) -> void:
	var max_grants: int = cfg.attack_recovery_window_ticks \
		/ cfg.attack_recovery_ticks_per_point
	if p.burnout_ticks > 0:
		stop_attack_recovery(p)
		return
	if not active:
		return
	if p.attack_recovery_delay_ticks > 0:
		p.attack_recovery_delay_ticks -= 1
		return
	if p.attack_recovery_window_ticks <= 0 \
			or p.attack_recovery_granted >= max_grants \
			or p.drive_gauge >= cfg.drive_gauge_max:
		stop_attack_recovery(p)
		return
	p.attack_recovery_fraction_ticks += 1
	if p.attack_recovery_fraction_ticks >= cfg.attack_recovery_ticks_per_point:
		p.attack_recovery_fraction_ticks -= cfg.attack_recovery_ticks_per_point
		p.drive_gauge = mini(p.drive_gauge + 1, cfg.drive_gauge_max)
		p.attack_recovery_granted += 1
	p.attack_recovery_window_ticks -= 1
	if p.attack_recovery_window_ticks <= 0 \
			or p.attack_recovery_granted >= max_grants \
			or p.drive_gauge >= cfg.drive_gauge_max:
		stop_attack_recovery(p)

static func spend_committed(p, amount: int, cfg) -> Dictionary:
	if not can_pay(p, amount):
		return {"authorized": false, "spent": 0, "depleted": false}
	p.drive_gauge -= amount
	var depleted: bool = amount > 0 and p.drive_gauge == 0
	if depleted:
		start_burnout(p, cfg)
	return {"authorized": true, "spent": amount, "depleted": depleted}

static func spend_mandatory(p, amount: int, cfg) -> int:
	var spent: int = mini(maxi(amount, 0), available_drive(p))
	p.drive_gauge -= spent
	if spent > 0 and p.drive_gauge == 0:
		start_burnout(p, cfg)
	return spent
