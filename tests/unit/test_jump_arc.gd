extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const Chars := preload("res://src/sim/chars.gd")
const JumpArc := preload("res://src/sim/jump_arc.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")

func _arc_positions(height_px: int, floor_y: int, release_tick: int = -1) -> Array[int]:
	var result: Array[int] = []
	var y: int = floor_y
	var vy: int = JumpArc.launch_velocity(height_px)
	for tick in 240:
		var held := release_tick < 0 or tick < release_tick
		vy = JumpArc.advance_velocity(vy, held)
		y += vy
		if y >= floor_y and vy > 0:
			y = floor_y
		result.append(y)
		if tick > 0 and y == floor_y:
			break
	return result

func _player_positions(char_id: int) -> Array[int]:
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = St.PHASE_POINT_PAUSE
	s.timer = 1000000
	var p = s.players[0]
	p.char_id = char_id
	var result: Array[int] = []
	for tick in 240:
		Sim.step(s, [SimInput.IN_JUMP, 0, 0, 0], cfg)
		result.append(p.y)
		if tick > 0 and p.on_ground == 1:
			break
	return result

func test_arc_reaches_requested_foot_heights() -> void:
	var floor_y := FP.from_int(320)
	for height_px in [110, 120, 140, 170, 200]:
		var positions := _arc_positions(height_px, floor_y)
		var min_y: int = floor_y
		for y in positions:
			min_y = mini(min_y, y)
		var actual := FP.to_int(floor_y - min_y)
		check(absi(actual - height_px) <= 2,
			"目標%dpxの共通軌道: actual=%d" % [height_px, actual])

func test_ume_keeps_reference_arc_and_rank_airtimes_scale_naturally() -> void:
	var floor_y := FP.from_int(320)
	var ume := _arc_positions(110, floor_y)
	check_eq(ume.size(), 52, "UMEは従来どおり52tickで着地")
	check_eq(JumpArc.ticks(110, true), 25, "UMEの上昇基準は25tick")
	check_eq(JumpArc.ticks(110, false), 27, "UMEの下降基準は27tick")
	var previous_duration := 1000000
	for height_px in [200, 170, 140, 120, 110]:
		var duration: int = _arc_positions(height_px, floor_y).size()
		check(duration < previous_duration,
			"AからEへ高度%dpxの滞空時間は厳密に短くなる" % height_px)
		previous_duration = duration
	var tome := _arc_positions(200, floor_y)
	check(tome.size() < ume.size() * 200 / 110,
		"Aランクの滞空時間は高度への単純比例より短い")

func test_every_height_uses_ume_reference_gravity() -> void:
	check_eq(JumpArc.gravity(true), FP.from_int(220) / (25 * 24),
		"上昇重力はUMEの110pxと25tickから一意に決まる")
	check_eq(JumpArc.gravity(false), FP.from_int(220) / (27 * 28),
		"下降重力はUMEの110pxと27tickから一意に決まる")

func test_releasing_jump_early_reduces_height() -> void:
	var floor_y := FP.from_int(320)
	var full := _arc_positions(200, floor_y)
	var short := _arc_positions(200, floor_y, 1)
	var full_min: int = floor_y
	var short_min: int = floor_y
	for y in full:
		full_min = mini(full_min, y)
	for y in short:
		short_min = mini(short_min, y)
	check(short_min > full_min, "早離しはフルジャンプより足元最高点が低い")

func test_player_movement_uses_exact_shared_arc() -> void:
	var cfg = Cfg.new()
	for cid in [Chars.CHAR_TOME, Chars.CHAR_SEC1, Chars.CHAR_PANDA]:
		var expected := _arc_positions(Chars.jump_height_px(cid), cfg.floor_y)
		check_eq(_player_positions(cid), expected,
			"%sの実動Y列は共通JumpArcと一致" % Chars.NAMES[cid])

func test_air_contact_prediction_matches_production_movement() -> void:
	var cfg = Cfg.new()
	var scenarios: Array[Array] = [
		[Chars.CHAR_HITO, SimInput.IN_ACTION | SimInput.IN_LEFT | SimInput.IN_JUMP,
			-FP.from_int(7), 0, 0, 0],
		[Chars.CHAR_HITO, SimInput.IN_ACTION | SimInput.IN_RIGHT,
			-FP.from_int(7), 0, 3, 2],
		[Chars.CHAR_MARIO, SimInput.IN_ACTION | SimInput.IN_LEFT | SimInput.IN_JUMP,
			FP.from_int(2), 0, 0, 0],
		[Chars.CHAR_MARIO, SimInput.IN_ACTION | SimInput.IN_JUMP,
			-FP.from_int(3), 2, 0, 0],
	]
	for scenario in scenarios:
		var s = St.new()
		var p = s.players[0]
		p.char_id = scenario[0]
		p.on_ground = 0
		p.x = FP.from_int(120)
		p.y = FP.from_int(180)
		p.vy = scenario[2]
		p.hip = scenario[3]
		p.dash = scenario[4]
		p.push = scenario[5]
		var input: int = scenario[1]
		var predicted: Vector2i = PlayerMovement.predict_air_contact_position(
			p, input, cfg, 0)
		PlayerMovement._step_player_unlocked(p, input, cfg, 0)
		check_eq(Vector2i(p.x, p.y), predicted,
			"通常空中移動の接触予測は本番1tick後の座標と一致")
