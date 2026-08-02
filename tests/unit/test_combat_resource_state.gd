extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")

func test_combat_ids_and_resource_state_roundtrip() -> void:
	var a := SimState.new()
	check_eq(a.alloc_possession_id(), 1, "最初の保持ID")
	check_eq(a.alloc_possession_id(), 2, "保持IDは単調増加")
	check_eq(a.alloc_attack_id(), 1, "最初の攻撃ID")
	check_eq(a.alloc_attack_id(), 2, "攻撃IDは単調増加")
	check_eq(a.alloc_contact_id(), 1, "最初の接触ID")
	check_eq(a.alloc_contact_id(), 2, "接触IDは単調増加")
	check_eq(a.alloc_action_id(), 1, "最初の行動ID")
	check_eq(a.alloc_action_id(), 2, "行動IDは単調増加")

	var p = a.players[1]
	p.drive_reserved = 5
	p.attack_recovery_delay_ticks = 11
	p.attack_recovery_window_ticks = 179
	p.attack_recovery_fraction_ticks = 29
	p.attack_recovery_granted = 4
	p.stunned_this_rally = 1
	p.stance_active = 1
	p.stance_action_id = a.alloc_action_id()
	p.stance_reserved_drive = 5
	p.stance_started_tick = 123
	p.stance_committed_attack_id = 7
	p.stance_pre_read_candidate = 1
	p.stance_cost_resolved = 1
	p.stance_exit_recovery_ticks = 9

	a.possession_id = a.alloc_possession_id()
	a.possession_team = 1
	a.aggressive_action_resolved = 1
	a.passive_return_penalty_applied = 1
	a.ball_attack_id = a.alloc_attack_id()
	a.ball_last_contact_id = a.alloc_contact_id()
	a.ball_attacker_id = 3
	a.ball_attack_commit_tick = 456
	a.ball_normal_gain_granted = 1
	a.ball_original_attack_pressure_consumed = 1
	a.ball_counts_for_pre_read_stance = 1

	var b := SimState.new()
	b.load_int_array(a.to_int_array())
	check_eq(b.to_int_array(), a.to_int_array(), "戦闘リソース状態を完全復元")
	check_eq(b.alloc_possession_id(), a.alloc_possession_id(), "復元後も保持ID列が一致")
	check_eq(b.alloc_attack_id(), a.alloc_attack_id(), "復元後も攻撃ID列が一致")
	check_eq(b.alloc_contact_id(), a.alloc_contact_id(), "復元後も接触ID列が一致")
	check_eq(b.alloc_action_id(), a.alloc_action_id(), "復元後も行動ID列が一致")
