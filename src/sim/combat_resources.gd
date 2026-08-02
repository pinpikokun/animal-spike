# 戦闘リソースの整数状態遷移。シミュレーション層以外の状態を読まない。
extends RefCounted

const SimStateScript := preload("res://src/sim/sim_state.gd")

static func available_drive(p) -> int:
	if p.burnout_ticks > 0:
		return 0
	return maxi(p.drive_gauge - p.drive_reserved, 0)

static func can_pay(p, amount: int) -> bool:
	return amount >= 0 and available_drive(p) >= amount

static func special_drive_cost(cfg) -> int:
	return cfg.special_drive_cost_default

static func start_dive(p, cfg) -> int:
	if p.burnout_ticks > 0 or available_drive(p) == 0:
		if p.burnout_ticks == 0:
			start_burnout(p, cfg)
		return SimStateScript.DIVE_WEAK
	if can_pay(p, cfg.dive_receive_drive_cost):
		spend_committed(p, cfg.dive_receive_drive_cost, cfg)
		return SimStateScript.DIVE_NORMAL
	spend_mandatory(p, available_drive(p), cfg)
	return SimStateScript.DIVE_WEAK

static func start_block(p, cfg) -> int:
	stop_attack_recovery(p)
	if p.burnout_ticks > 0 or available_drive(p) == 0:
		if p.burnout_ticks == 0:
			start_burnout(p, cfg)
		return SimStateScript.BLOCK_BURNOUT
	if can_pay(p, cfg.block_start_drive_cost):
		spend_committed(p, cfg.block_start_drive_cost, cfg)
		return SimStateScript.BLOCK_NORMAL
	spend_mandatory(p, available_drive(p), cfg)
	return SimStateScript.BLOCK_BURNOUT

static func resolve_block_contact(p, cfg) -> void:
	if p.current_block_mode == SimStateScript.BLOCK_NORMAL:
		spend_mandatory(p, cfg.block_contact_drive_cost, cfg)

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

static func reserve_stance(p, action_id: int, tick: int, cfg) -> bool:
	if p.stance_active != 0 or p.stance_exit_recovery_ticks > 0 \
			or not can_pay(p, cfg.receive_stance_reserve_cost):
		return false
	p.drive_reserved += cfg.receive_stance_reserve_cost
	p.stance_active = 1
	p.stance_action_id = action_id
	p.stance_reserved_drive = cfg.receive_stance_reserve_cost
	p.stance_started_tick = tick
	p.stance_committed_attack_id = 0
	p.stance_pre_read_candidate = 0
	p.stance_cost_resolved = 0
	return true

static func release_stance_reservation(p) -> void:
	if p.stance_cost_resolved != 0:
		return
	p.drive_reserved = maxi(p.drive_reserved - p.stance_reserved_drive, 0)
	p.stance_reserved_drive = 0
	p.stance_cost_resolved = 1

static func commit_stance_reservation(p, cfg) -> void:
	if p.stance_cost_resolved != 0:
		return
	var cost: int = p.stance_reserved_drive
	p.drive_reserved = maxi(p.drive_reserved - cost, 0)
	p.stance_reserved_drive = 0
	p.stance_cost_resolved = 1
	if p.burnout_ticks > 0:
		return
	spend_mandatory(p, cost, cfg)

static func finish_stance(p, cfg, release_cost: bool) -> void:
	if release_cost:
		release_stance_reservation(p)
	else:
		commit_stance_reservation(p, cfg)
	p.stance_active = 0
	p.receive_stance = 0
	p.stance_exit_recovery_ticks = cfg.receive_stance_exit_recovery_ticks
	p.stance_committed_attack_id = 0
	p.stance_pre_read_candidate = 0

static func resolve_stance_contact(p, attack_id: int,
		attack_commit_tick: int, cfg) -> int:
	if p.stance_active == 0:
		return 0
	var pre_read: bool = attack_id > 0 \
		and p.stance_committed_attack_id == attack_id \
		and p.stance_pre_read_candidate != 0 \
		and p.stance_started_tick <= attack_commit_tick
	finish_stance(p, cfg, pre_read)
	return 1 if pre_read else 2

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
