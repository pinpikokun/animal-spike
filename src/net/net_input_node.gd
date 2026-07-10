# 1チーム分の入力担当ノード。所有ピアのマシンでだけ_get_local_inputが呼ばれ、
# 相手側では受信入力/予測入力が_network_processに渡ってくる。
# _network_process(全ノード分)はSimRootの_network_postprocessより前に走るので、
# ここで書いた_team_inputsは同tickの進行に必ず反映される
extends Node

const InputPoll := preload("res://src/display/input_poll.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

var team: int = 0
var sim_root: Node = null
# ソーク自動化用。trueなら決定論CPUが入力を生成する(--bot起動時にnet_matchが立てる)
var bot: bool = false

func _ready() -> void:
	add_to_group("network_sync")

func _get_local_input() -> Dictionary:
	if bot and sim_root != null:
		# SimCpu.decideは状態のみ依存の決定論なのでロールバック安全
		var st = sim_root.state
		var ctrl: int = st.controlled_l if team == 0 else st.controlled_r
		var idx: int = team * 2 + ctrl
		return {"i": SimCpu.decide(st, idx, sim_root.cfg)}
	return {"i": InputPoll.poll()}

func _predict_remote_input(previous_input: Dictionary, _ticks_since_real_input: int) -> Dictionary:
	# 予測は「最後の入力を押しっぱなし」。格闘/スポーツ系の定石
	return previous_input.duplicate()

func _network_process(input: Dictionary) -> void:
	if sim_root != null:
		sim_root.set_team_input(team, input.get("i", 0))
