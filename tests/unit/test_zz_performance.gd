extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const Chars := preload("res://src/sim/chars.gd")

const SAMPLE_COUNT := 5
const STEP_WARM := 600
const STEP_ITERATIONS := 2000
const STEP_UPPER_NS := 230_000
const ROLLBACK16_UPPER_NS := 8_333_333
const AIR_WARM := 1000
const AIR_ITERATIONS := 5000
const AIR_LOWER_NS := 5000
const AIR_UPPER_NS := 75_000
const POLICY_THREE_AITICK := 15
const STANDARD_CHAR := 99

func _next_rand(value: int) -> int:
	value ^= value << 13
	value ^= value >> 7
	value ^= value << 17
	return value

func _stored_inputs() -> Array:
	var result: Array = []
	var rng := 123456789
	for _i in STEP_WARM + STEP_ITERATIONS:
		rng = _next_rand(rng)
		var left: int = rng & 127
		rng = _next_rand(rng)
		var right: int = rng & 127
		result.append([left, right] as Array[int])
	return result

func _fresh_step_world() -> Array:
	var cfg = SimConfig.new()
	if not cfg.valid:
		return []
	cfg.points_to_win = 999
	var state = SimState.new()
	Simulation.reset_match(state, cfg, 0, Chars.ROSTER, 0, 0)
	for player in state.players:
		player.cpu = SimCpu.PRESET_MAX
	return [state, cfg]

func _measure_step_sample(inputs: Array) -> Dictionary:
	var world := _fresh_step_world()
	if world.is_empty():
		return {"valid": false, "step": -1, "load": -1}
	var state = world[0]
	var cfg = world[1]
	for i in STEP_WARM:
		Simulation.tick(state, inputs[i], cfg)
	var snapshot: Dictionary = {}
	var started_usec := Time.get_ticks_usec()
	for i in STEP_ITERATIONS:
		Simulation.tick(state, inputs[STEP_WARM + i], cfg)
		snapshot = {"s": state.to_int_array(), "h": state.state_hash()}
	var step_ns: int = (Time.get_ticks_usec() - started_usec) * 1000 / STEP_ITERATIONS
	started_usec = Time.get_ticks_usec()
	for _i in STEP_ITERATIONS:
		state.load_int_array(snapshot["s"])
	var load_ns: int = (Time.get_ticks_usec() - started_usec) * 1000 / STEP_ITERATIONS
	return {"valid": not snapshot.is_empty(), "step": step_ns, "load": load_ns}

func _measure_steps() -> Dictionary:
	var inputs := _stored_inputs()
	var steps: Array[int] = []
	var loads: Array[int] = []
	var all_valid := true
	for _sample in SAMPLE_COUNT:
		var measured := _measure_step_sample(inputs)
		all_valid = all_valid and measured["valid"]
		steps.append(measured["step"])
		loads.append(measured["load"])
	steps.sort()
	loads.sort()
	return {
		"valid": all_valid,
		"step_min": steps[0],
		"step_median": steps[steps.size() / 2],
		"load_min": loads[0],
		"load_median": loads[loads.size() / 2],
	}

func _air_fixture() -> Array:
	var cfg = SimConfig.new()
	if not cfg.valid:
		return []
	var state = SimState.new()
	var actor := 0
	var player = state.players[actor]
	player.char_id = STANDARD_CHAR
	player.cpu = SimCpu.make_profile(SimCpu.AB_ATTACK, 0, 0, 0, 0, 3, 3)
	player.on_ground = 0
	player.drive_gauge = cfg.drive_gauge_max
	state.phase = SimState.PHASE_RALLY
	state.ball_x = cfg.net_x - FP.from_int(60)
	state.ball_y = cfg.net_top_y - FP.from_int(100)
	player.x = state.ball_x
	state.ball_vx = 0
	state.ball_vy = 0
	state.players[2].x = cfg.net_x + FP.from_int(20)
	state.players[3].x = cfg.net_x + FP.from_int(40)
	state.aitick = POLICY_THREE_AITICK
	return [state, cfg, actor]

func _air_decide(world: Array) -> int:
	var state = world[0]
	var cfg = world[1]
	var actor: int = world[2]
	var player = state.players[actor]
	return SimCpu._decide_air_hit(
		state, actor, player, cfg, 0, player.cpu,
		cfg.player_reach * cfg.player_reach, 0)

func _measure_air_sample() -> Dictionary:
	var world := _air_fixture()
	if world.is_empty():
		return {"valid": false, "ns": -1, "accumulator": 0}
	for _i in AIR_WARM:
		_air_decide(world)
	var accumulator := 0
	var started_usec := Time.get_ticks_usec()
	for _i in AIR_ITERATIONS:
		accumulator += _air_decide(world)
	var sample_ns: int = (Time.get_ticks_usec() - started_usec) * 1000 / AIR_ITERATIONS
	return {"valid": true, "ns": sample_ns, "accumulator": accumulator}

func _measure_air() -> Dictionary:
	var samples: Array[int] = []
	var accumulator := 0
	var all_valid := true
	for _sample in SAMPLE_COUNT:
		var measured := _measure_air_sample()
		all_valid = all_valid and measured["valid"]
		samples.append(measured["ns"])
		accumulator += measured["accumulator"]
	samples.sort()
	return {
		"valid": all_valid,
		"min": samples[0],
		"median": samples[samples.size() / 2],
		"accumulator": accumulator,
	}

func _air_fixture_facts() -> Dictionary:
	var world := _air_fixture()
	if world.is_empty():
		return {"valid": false, "policy": -1, "candidate_count": 0, "decided": -1}
	var state = world[0]
	var cfg = world[1]
	var actor: int = world[2]
	var candidate_count := 0
	for input in [
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
	]:
		if not SimCpu._air_spike_candidate(state, actor, cfg, 0, input).is_empty():
			candidate_count += 1
	for _i in AIR_WARM:
		_air_decide(world)
	return {
		"valid": true,
		"policy": SimCpu._air_shot_policy(state),
		"candidate_count": candidate_count,
		"decided": _air_decide(world),
	}

func test_rollback_and_air_trial_cost_stay_within_limits() -> void:
	var step := _measure_steps()
	var air_facts := _air_fixture_facts()
	var air := _measure_air()
	var rollback16_ns: int = step["load_min"] + 16 * step["step_min"]
	print("PERF_GATE step_min_ns=%d step_median_ns=%d load_min_ns=%d load_median_ns=%d rollback16_ns=%d air_trial_min_ns=%d air_trial_median_ns=%d" % [
		step["step_min"], step["step_median"], step["load_min"], step["load_median"],
		rollback16_ns, air["min"], air["median"]])
	check(step["valid"], "step fixtureの既定ルールとsnapshotが有効")
	check(step["step_min"] > 0, "step計測値が正")
	check(step["step_min"] <= STEP_UPPER_NS,
		"step実測%d nsが上限%d ns以内" % [step["step_min"], STEP_UPPER_NS])
	check(rollback16_ns <= ROLLBACK16_UPPER_NS,
		"16コマ下限見積り%d nsが上限%d ns以内" % [rollback16_ns, ROLLBACK16_UPPER_NS])
	check(air_facts["valid"] and air["valid"], "air fixtureの既定ルールが有効")
	check_eq(air_facts["policy"], 2, "air fixtureは政策3")
	check_eq(air_facts["candidate_count"], 3, "production判定で3候補すべて有効")
	check_eq(air_facts["decided"],
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		"3候補走査後に奥候補を選ぶ")
	check(air["accumulator"] > 0, "air trialの全戻り値を使用")
	check(air["min"] >= AIR_LOWER_NS,
		"air trial実測%d nsが下限%d ns以上" % [air["min"], AIR_LOWER_NS])
	check(air["min"] <= AIR_UPPER_NS,
		"air trial実測%d nsが上限%d ns以内" % [air["min"], AIR_UPPER_NS])
