extends "res://tests/test_case.gd"

const BootSeed := preload("res://src/app/boot_seed.gd")
const GameViewScene := preload("res://src/display/game_view.tscn")
const MainScene := preload("res://src/display/main.tscn")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")

func test_valid_time_dict_uses_hour_and_minute_only() -> void:
	var completion_guard := _begin_completion_guard(
		"test_valid_time_dict_uses_hour_and_minute_only")
	check_eq(BootSeed.from_time_dict({"hour": 0, "minute": 0}), 0x0000,
		"00:00は有効なseed 0")
	check_eq(BootSeed.from_time_dict({"hour": 23, "minute": 59, "second": 0}), 0x173B,
		"23:59の既知ベクタ")
	check_eq(BootSeed.from_time_dict({"hour": 23, "minute": 59, "second": 58}), 0x173B,
		"秒の違いをseedへ混ぜない")
	_end_completion_guard(completion_guard)

func test_invalid_time_dict_is_rejected() -> void:
	var completion_guard := _begin_completion_guard(
		"test_invalid_time_dict_is_rejected")
	var invalid: Array[Dictionary] = [
		{"minute": 10},
		{"hour": 10},
		{"hour": 10.0, "minute": 20},
		{"hour": 10, "minute": "20"},
		{"hour": -1, "minute": 20},
		{"hour": 24, "minute": 20},
		{"hour": 10, "minute": -1},
		{"hour": 10, "minute": 60},
	]
	for clock in invalid:
		check(BootSeed.from_time_dict(clock) == null,
			"不正な時刻辞書を拒否する: %s" % str(clock))
	_end_completion_guard(completion_guard)

func test_game_view_consumes_boot_seed_and_external_state_is_untouched() -> void:
	var completion_guard := _begin_completion_guard(
		"test_game_view_consumes_boot_seed_and_external_state_is_untouched")
	var tree := _scene_tree_or_null()
	if tree == null:
		return

	var local_fixture := Node.new()
	tree.root.add_child(local_fixture)
	var previous_tick_rate := Engine.physics_ticks_per_second
	var local_view = GameViewScene.instantiate()
	local_view.boot_seed = 0x173B
	local_fixture.add_child(local_view)
	check(local_view.state != null, "GameView._ready()がローカルstateを初期化する")
	if local_view.state != null:
		check_eq(local_view.state.aitick, 0x173B,
			"add_child前に設定したboot_seedをローカル初期状態へ使う")
	local_fixture.remove_child(local_view)
	local_view.free()
	Engine.physics_ticks_per_second = previous_tick_rate
	tree.root.remove_child(local_fixture)
	local_fixture.free()

	var external_fixture := Node.new()
	tree.root.add_child(external_fixture)
	previous_tick_rate = Engine.physics_ticks_per_second
	var external_cfg := SimConfig.new()
	var external_state := SimState.new()
	external_state.aitick = 0x1234
	external_state.tick = 77
	var before: Array = external_state.to_int_array()
	var external_view = GameViewScene.instantiate()
	external_view.attach_external(external_cfg, external_state)
	external_fixture.add_child(external_view)
	var external_reference_kept: bool = external_view.state == external_state
	check(external_reference_kept, "external stateの参照を保持する")
	if external_reference_kept:
		check_eq(external_view.state.to_int_array(), before,
			"external_simではローカルresetを通らず内容を保つ")
	external_fixture.remove_child(external_view)
	external_view.free()
	Engine.physics_ticks_per_second = previous_tick_rate
	tree.root.remove_child(external_fixture)
	external_fixture.free()
	_end_completion_guard(completion_guard)

func test_debug_main_keeps_fixed_seed_zero() -> void:
	var completion_guard := _begin_completion_guard(
		"test_debug_main_keeps_fixed_seed_zero")
	var tree := _scene_tree_or_null()
	if tree == null:
		return

	var fixture_root := Node.new()
	tree.root.add_child(fixture_root)
	var previous_tick_rate := Engine.physics_ticks_per_second
	var target = MainScene.instantiate()
	fixture_root.add_child(target)
	check(target.state != null, "main.gdの_ready()がstateを初期化する")
	if target.state != null:
		check_eq(target.state.aitick, 0, "デバッグsimは固定seed 0を維持する")
	fixture_root.remove_child(target)
	target.free()
	Engine.physics_ticks_per_second = previous_tick_rate
	tree.root.remove_child(fixture_root)
	fixture_root.free()
	_end_completion_guard(completion_guard)

func _begin_completion_guard(test_name: String) -> String:
	# 先行check後のランタイム中断でも偽PASSにしない。正常終了時だけ消す。
	var marker := "テストが正常終了しなかった: %s" % test_name
	failures.append(marker)
	return marker

func _end_completion_guard(marker: String) -> void:
	failures.erase(marker)

func _scene_tree_or_null() -> SceneTree:
	var main_loop := Engine.get_main_loop()
	check(main_loop is SceneTree, "main loopがSceneTreeである")
	if not (main_loop is SceneTree):
		return null
	var tree := main_loop as SceneTree
	check(tree.root != null, "SceneTree.rootが存在する")
	if tree.root == null:
		return null
	return tree
