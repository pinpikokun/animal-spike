extends "res://tests/test_case.gd"

# SimRootアダプタの純ロジック検証(SyncManager非依存)。
# 進行はtickではなく_network_postprocessで行う(全_network_processの後に走る保証があり
# 入力ノードの書き込み順に依存しないため。SyncManager.gd:647-656参照)

const SimRoot := preload("res://src/net/sim_root.gd")
const SimState := preload("res://src/sim/sim_state.gd")

func _make_root():
	var r = SimRoot.new()
	r.setup()  # cfg/state生成+reset_match(表示なし)
	return r

func test_postprocess_advances_one_tick() -> void:
	var r = _make_root()
	var t0: int = r.state.tick
	r.set_team_input(0, 0)
	r.set_team_input(1, 0)
	r._network_postprocess({})
	check_eq(r.state.tick, t0 + 1, "1回で1tick進む")
	r.free()

func test_save_load_state_roundtrip() -> void:
	var r = _make_root()
	r._network_postprocess({})
	var saved: Dictionary = r._save_state()
	var h0: int = r.state.state_hash()
	for i in 30:
		r.set_team_input(0, 2)  # 右移動で状態を汚す
		r._network_postprocess({})
	check(r.state.state_hash() != h0, "前提: 状態が進んで変わっている")
	r._load_state(saved)
	check_eq(r.state.state_hash(), h0, "ロールバック復元でハッシュが戻る")
	check_eq(saved["h"], h0, "保存辞書のハッシュキーも一致")
	r.free()

func test_team_inputs_reach_sim() -> void:
	var r = _make_root()
	# サーバーは SERVE で位置固定されるため、移動が生きる POINT_PAUSE で入力配線を検証
	r.state.phase = SimState.PHASE_POINT_PAUSE
	r.state.timer = 100000000
	var x0: int = r.state.players[0].x
	r.set_team_input(0, 2)  # IN_RIGHT
	r.set_team_input(1, 0)
	r._network_postprocess({})
	check(r.state.players[0].x > x0, "左チーム入力が操作キャラに届く")
	r.free()

func test_inputs_reset_after_tick() -> void:
	# tick後は_team_inputsが0に戻り、書き込みの無いチームは無入力になる(ステイル入力の混入防止)
	var r = _make_root()
	# サーバー位置固定を避け、移動でステイル入力の有無を判定するため POINT_PAUSE
	r.state.phase = SimState.PHASE_POINT_PAUSE
	r.state.timer = 100000000
	r.set_team_input(0, 2)  # IN_RIGHT
	r._network_postprocess({})
	var x1: int = r.state.players[0].x
	# 今回はどちらも書き込まない -> 左チームは無入力で静止(慣性/重力以外で右移動しない)
	r._network_postprocess({})
	var x2: int = r.state.players[0].x
	check(x2 == x1, "入力を書かなければ前tickの右移動が持ち越されない")
	r.free()
