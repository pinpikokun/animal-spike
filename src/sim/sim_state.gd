# シミュレーションの全状態。全フィールドint(fp)。float禁止
# フィールドを増やしたら必ずto_int_arrayにも足すこと(test_state_coverageが強制する)
extends RefCounted

const PLAYER_COUNT := 4

const PHASE_SERVE := 0
const PHASE_RALLY := 1
const PHASE_POINT_PAUSE := 2
const PHASE_GAME_OVER := 3

class Player:
	var x: int = 0
	var y: int = 0
	var vx: int = 0
	var vy: int = 0
	var on_ground: int = 1
	var hit_cooldown: int = 0
	var stun: int = 0  # 耐久力が尽きた硬直(移動・ヒット不可)の残りtick
	var dive: int = 0  # ジャンピングトス演出の残りtick(符号=飛びつき方向)。表示層が読む
	var hit_kind: int = 0  # 直近の地上ヒット種別(0=レシーブ,1=トス,2=前トス)。表示層が読む
	var brake: int = 0  # 急ブレーキ(スキッド)の残り(符号=滑る方向, 絶対値=残りtick)。表示層も読む
	var run: int = 0  # 同方向の連続走行tick。一定以上でのみ反転スキッドが出る(細かい制御は滑らない)
	var has_hat: int = 1  # 帽子をかぶってるか(0=投げ中)。表示層のスプライト選択に使う
	var face: int = 0  # 向き(1=右,-1=左,0=未定)。vxから毎tick更新。帽子投げ方向等に使う
	var hip: int = 0  # ヒップアタック(0=無し, >0=空中静止の残りtick, -1=急降下中)。帽子ありのみ
	var cling: int = 0  # 壁張り付き(0=無し, 1=左壁, -1=右壁)。表示層が読む
	var throw: int = 0  # 帽子投げの溜め(windup)残りtick。>0の間は入力を受け付けず空中でも浮く
	var flinch: int = 0  # ジャストアタック被弾のしりもち(butt-drop)残りtick。後ろへ滑る
	# 耐久力(ガード): アタックをしのぐたびに減り、尽きるとスタン(満タンへ復帰)。
	# ジャストトスで回復。guard_maxはキャラ別ステータスの器(M4で個体差を接続)
	var guard: int = 100
	var guard_max: int = 100
	# CPUプロファイル(8bit x 7欄: 能力/反応遅延/狙い誤差/ミス率/ジャスト率/予測深度/配球IQ)。
	# 欄の割当はsim_cpu.gdのP_*。既定は最強プリセット(sim_cpu.PRESET_MAXと一致、テストで保証)
	var cpu: int = 848543938514047

var tick: int = 0
var players: Array[Player] = []
var ball_x: int = 0
var ball_y: int = 0
var ball_vx: int = 0
var ball_vy: int = 0
var ball_spin: int = 0  # 累積回転量(横移動由来)。表示層が回転フレームの導出に使う
var ball_power: int = 0  # 1=パーフェクトスパイク由来のパワーボール(耐久力を削る+熱色表示)
var last_hit_tick: int = 0  # 最後にヒット/サーブが起きたtick。CPUの反応遅延と乱数キーの主軸
var serve_aim: int = 25  # サーブトスの照準角(垂直から何度ネット側へ倒すか。0=真上..60)
var serve_pow: int = 100  # サーブトスの高さ(%)。上下キーで60..130を選ぶ
var serve_tossed: int = 0  # 2段階サーブ: 0=構え(照準中)、1=トス済み(打撃待ち)
# 1=サーブ打球がまだ最初のネット越えをしていない。物理には影響せず、
# 味方CPUが「上げ球だ」と誤認してサーブにジャンプするのを抑えるためにAIが読む
var serve_flight: int = 0
# ヒットストップの残りtick。パワーボール成立や気絶の瞬間に数tick全員が止まり
# 「重さ」を出す。simが凍るだけなので決定論・ロールバック安全
var hit_freeze: int = 0
# スローモーションの残りtick。ジャストスマッシュ成立時に立ち、スロー中は3tickに
# 1回だけ物理を進める(1/3速)。tick/入力は1:1で消費し続けるので決定論・ロールバック安全
var slow_ticks: int = 0
var phase: int = PHASE_SERVE
var serving_team: int = 0
var score_l: int = 0
var score_r: int = 0
var touches: int = 0
var last_touch_team: int = -1
var timer: int = 0
var controlled_l: int = 0
var controlled_r: int = 0
var switch_latch_l: int = 0
var switch_latch_r: int = 0
var winner: int = -1
# 帽子投げ(お邪魔ギミック)。cap_phase: 0=無し, 1=飛行, 2=滞在, 3=帰還。
# ボールと当たり判定を持ち、触れると弾く。一度に1個だけ存在する
var cap_phase: int = 0
var cap_x: int = 0
var cap_y: int = 0
var cap_vx: int = 0
var cap_vy: int = 0
var cap_owner: int = 0  # 投げた選手のindex(帰還先)
var cap_timer: int = 0  # 現フェーズの残りtick

func _init() -> void:
	for i in PLAYER_COUNT:
		players.append(Player.new())

func to_int_array() -> Array[int]:
	var out: Array[int] = [tick]
	for p in players:
		out.append(p.x)
		out.append(p.y)
		out.append(p.vx)
		out.append(p.vy)
		out.append(p.on_ground)
		out.append(p.hit_cooldown)
		out.append(p.stun)
		out.append(p.dive)
		out.append(p.hit_kind)
		out.append(p.brake)
		out.append(p.run)
		out.append(p.has_hat)
		out.append(p.face)
		out.append(p.hip)
		out.append(p.cling)
		out.append(p.throw)
		out.append(p.flinch)
		out.append(p.guard)
		out.append(p.guard_max)
		out.append(p.cpu)
	out.append(ball_x)
	out.append(ball_y)
	out.append(ball_vx)
	out.append(ball_vy)
	out.append(ball_spin)
	out.append(ball_power)
	out.append(last_hit_tick)
	out.append(serve_aim)
	out.append(serve_pow)
	out.append(serve_tossed)
	out.append(serve_flight)
	out.append(hit_freeze)
	out.append(slow_ticks)
	out.append(phase)
	out.append(serving_team)
	out.append(score_l)
	out.append(score_r)
	out.append(touches)
	out.append(last_touch_team)
	out.append(timer)
	out.append(controlled_l)
	out.append(controlled_r)
	out.append(switch_latch_l)
	out.append(switch_latch_r)
	out.append(winner)
	out.append(cap_phase)
	out.append(cap_x)
	out.append(cap_y)
	out.append(cap_vx)
	out.append(cap_vy)
	out.append(cap_owner)
	out.append(cap_timer)
	return out

func load_int_array(arr: Array) -> void:
	# to_int_arrayの逆。順序を変えるときは必ず両方同時に変える
	var k := 0
	tick = arr[k]; k += 1
	for p in players:
		p.x = arr[k]; k += 1
		p.y = arr[k]; k += 1
		p.vx = arr[k]; k += 1
		p.vy = arr[k]; k += 1
		p.on_ground = arr[k]; k += 1
		p.hit_cooldown = arr[k]; k += 1
		p.stun = arr[k]; k += 1
		p.dive = arr[k]; k += 1
		p.hit_kind = arr[k]; k += 1
		p.brake = arr[k]; k += 1
		p.run = arr[k]; k += 1
		p.has_hat = arr[k]; k += 1
		p.face = arr[k]; k += 1
		p.hip = arr[k]; k += 1
		p.cling = arr[k]; k += 1
		p.throw = arr[k]; k += 1
		p.flinch = arr[k]; k += 1
		p.guard = arr[k]; k += 1
		p.guard_max = arr[k]; k += 1
		p.cpu = arr[k]; k += 1
	ball_x = arr[k]; k += 1
	ball_y = arr[k]; k += 1
	ball_vx = arr[k]; k += 1
	ball_vy = arr[k]; k += 1
	ball_spin = arr[k]; k += 1
	ball_power = arr[k]; k += 1
	last_hit_tick = arr[k]; k += 1
	serve_aim = arr[k]; k += 1
	serve_pow = arr[k]; k += 1
	serve_tossed = arr[k]; k += 1
	serve_flight = arr[k]; k += 1
	hit_freeze = arr[k]; k += 1
	slow_ticks = arr[k]; k += 1
	phase = arr[k]; k += 1
	serving_team = arr[k]; k += 1
	score_l = arr[k]; k += 1
	score_r = arr[k]; k += 1
	touches = arr[k]; k += 1
	last_touch_team = arr[k]; k += 1
	timer = arr[k]; k += 1
	controlled_l = arr[k]; k += 1
	controlled_r = arr[k]; k += 1
	switch_latch_l = arr[k]; k += 1
	switch_latch_r = arr[k]; k += 1
	winner = arr[k]; k += 1
	cap_phase = arr[k]; k += 1
	cap_x = arr[k]; k += 1
	cap_y = arr[k]; k += 1
	cap_vx = arr[k]; k += 1
	cap_vy = arr[k]; k += 1
	cap_owner = arr[k]; k += 1
	cap_timer = arr[k]; k += 1

func state_hash() -> int:
	# FNV-1a 64bit。オフセット値はint64符号付き表現
	# GDScriptのint64はオーバーフロー時にラップするのでそのまま使える
	var h := -3750763034362895579
	for v in to_int_array():
		for i in 8:
			h ^= (v >> (i * 8)) & 0xFF
			h *= 1099511628211
	return h
