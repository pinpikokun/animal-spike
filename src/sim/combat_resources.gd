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
	p.burnout_ticks = cfg.burnout_recovery_ticks

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
