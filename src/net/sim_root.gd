# ロールバックネットコードと自前決定論simの接続点。
# SyncManagerからは「状態の保存/復元」と「毎tickの進行」だけを受け、
# sim本体(src/sim/)には一切手を入れない薄皮アダプタ。
#
# 進行を_network_processではなく_network_postprocessで行う理由:
# SyncManager.gdは全ノードの_network_process(SyncManager.gd:647-650)を回し切ってから
# 全ノードの_network_postprocess(同:653-656)を回す。入力ノード(net_input_node)は
# _network_processで_team_inputsへ書き込むので、SimRootが_network_postprocessでtickすれば
# ノードのツリー順/グループ順に依存せず必ず両チームの入力が揃った後に進行できる。
# (計画は_network_process+ツリー順を想定していたが、SyncManagerの_network_processは
#  グループ順の逆順で呼ばれる(同:634-644の逆走査)ため順序前提が崩れる。postprocessで回避)
extends Node

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const Chars := preload("res://src/sim/chars.gd")

var cfg
var state
var _team_inputs: Array[int] = [0, 0]

func setup(seed: int = 0) -> void:
	# テストとnet_matchの両方から呼ぶ初期化(表示なし)
	cfg = SimConfig.new()
	state = SimState.new()
	Simulation.reset_match(state, cfg, 0, Chars.ROSTER, seed, seed)

func apply_agreed_start(
		agreed_serving_team: int,
		agreed_roster: Array,
		agreed_seed: int,
		human_team_mask: int
	) -> int:
	var fresh := SimState.new()
	Simulation.reset_match(fresh, cfg, agreed_serving_team, agreed_roster,
		agreed_seed, agreed_seed)
	state.load_int_array(fresh.to_int_array())
	state.human_team_mask = human_team_mask
	_team_inputs = [0, 0]
	return state.state_hash()

func _ready() -> void:
	if cfg == null:
		setup()
	add_to_group("network_sync")

func set_team_input(team: int, bits: int) -> void:
	_team_inputs[team] = bits

func _network_postprocess(_input: Dictionary) -> void:
	Simulation.tick(state, [_team_inputs[0], _team_inputs[1]], cfg)
	# tickごとに0へ戻す。入力ノードは毎tick必ず_network_processで上書きするが、
	# 万一書き込み漏れがあってもステイル入力を持ち越さない安全側の既定
	_team_inputs = [0, 0]

func _save_state() -> Dictionary:
	# to_int_arrayは毎回新規配列を返すのでアドオンの「stateは複製必須」制約を満たす。
	# 自前FNV-1aハッシュを"h"に同梱すればアドオンのデシンク照合が自前ハッシュ比較になる
	return {"s": state.to_int_array(), "h": state.state_hash()}

func _load_state(d: Dictionary) -> void:
	state.load_int_array(d["s"])
