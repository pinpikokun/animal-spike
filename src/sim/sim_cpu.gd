# CPU入力生成。シミュレーション層の一部なので完全決定論・int演算のみ
# 状態を読むだけで書き換えない(副作用禁止)。
# simulation.gdをpreloadしない(循環防止)。定数はsim_input.gdから取る
#
# v1: 能力ビットフラグ方式。プレイヤーごとにstate.cpu_skill_bits(8bit x 4人)で
# 付け外しでき、ストーリーモードの段階的な強さ・味方の強さ選択(弱/普通/強/最強)を
# 同じ仕組みで表現する。全能力OFF(=0)がv0相当の最弱(現在ボール位置を追うだけ)
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")

# 能力フラグ(8bitに収める。増やすときはsim_state.cpu_skill_bitsの割当コメントも更新)
const AB_PREDICT := 1    # 落下点予測(弾道積分)。無いと現在のボールxを追う
const AB_ROLES := 2      # 役割分担(落下点に近い方がレシーバー、相方は支援位置)
const AB_ATTACK := 4     # 味方が上げた球へジャンプ会合してアタック
const AB_SWEET := 8      # アタックはジャストミート(スイートスポット)を狙う
const AB_SERVE_VAR := 16 # サーブの角度・威力を決定論的に散らす

# 難易度プリセット(ストーリーモードのステージ進行・味方の強さ選択で使う)
const LEVEL_WEAK := 0
const LEVEL_NORMAL := AB_PREDICT
const LEVEL_STRONG := AB_PREDICT | AB_ROLES | AB_SERVE_VAR
const LEVEL_MAX := AB_PREDICT | AB_ROLES | AB_ATTACK | AB_SWEET | AB_SERVE_VAR

static func skill_of(s, idx: int) -> int:
	return (s.cpu_skill_bits >> (idx * 8)) & 0xFF

# 4人分のマスクを1intへ詰める(設定画面・ストーリーモードが使う)
static func pack_skills(m0: int, m1: int, m2: int, m3: int) -> int:
	return (m0 & 0xFF) | ((m1 & 0xFF) << 8) | ((m2 & 0xFF) << 16) | ((m3 & 0xFF) << 24)

static func _spawn_x(idx: int, cfg) -> int:
	var back: int = FP.from_int(cfg.spawn_back_px)
	var front: int = FP.from_int(cfg.spawn_front_px)
	var positions: Array[int] = [back, front, cfg.court_width - back, cfg.court_width - front]
	return positions[idx]

static func _walk_to(p, target_x: int, deadzone: int) -> int:
	if p.x < target_x - deadzone:
		return SimInput.IN_RIGHT
	elif p.x > target_x + deadzone:
		return SimInput.IN_LEFT
	return 0

# ボールが高さtarget_yへ落ちてくる位置xを弾道積分で予測する(壁反射込み)。
# ネット反射は無視する簡易版(ネット直撃は稀で、外れても追い直すだけ)
static func _predict_landing_x(s, cfg, target_y: int) -> int:
	var x: int = s.ball_x
	var y: int = s.ball_y
	var vx: int = s.ball_vx
	var vy: int = s.ball_vy
	if y >= target_y and vy >= 0:
		return x
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	for t in 240:
		vy += cfg.gravity
		x += vx
		y += vy
		if x < left:
			x = left + (left - x)
			vx = -vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		elif x > right:
			x = right - (x - right)
			vx = -vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		if y >= target_y and vy > 0:
			break
	return x

# 今ジャンプしたらリーチ(半径limit)でボールと会合できるか(双方の弾道を並走積分)。
# 自分の横移動と壁反射は無視する簡易版
static func _jump_will_meet(s, p, cfg, limit: int) -> bool:
	var bx: int = s.ball_x
	var by: int = s.ball_y
	var bvx: int = s.ball_vx
	var bvy: int = s.ball_vy
	var py: int = p.y
	var pvy: int = -cfg.jump_speed
	for t in 48:
		bvy += cfg.gravity
		bx += bvx
		by += bvy
		pvy += cfg.gravity
		py += pvy
		if py >= cfg.floor_y and pvy > 0:
			break
		var dx: int = bx - p.x
		var dy: int = by - py
		var dy_n: int = dy * cfg.player_reach / cfg.player_reach_up
		if dx * dx + dy_n * dy_n <= limit * limit:
			return true
	return false

# サーブの狙い(角度/威力)をスコアから決定論的に散らす。
# 範囲は「必ずネットを越える」安全域に制限する(角度24..40度、威力100..125%)。
# スコアはラリーごとに必ず変わるので毎サーブ違う狙いになる
static func _serve_target(s, idx: int) -> Array[int]:
	var h: int = absi((s.score_l * 73856093) ^ (s.score_r * 19349663) ^ (idx * 83492791))
	var aim: int = 24 + h % 17          # 24..40
	var pow_pct: int = 100 + (h / 97) % 26  # 100..125
	return [aim, pow_pct]

static func _decide_serve(s, idx: int, cfg, mask: int) -> int:
	# サーブ遅延タイマーはsimulation.gdのstep()が減算する(ここは読むだけ)
	if idx != s.serving_team * 2:
		return 0
	if mask & AB_SERVE_VAR:
		var target := _serve_target(s, idx)
		# 照準スイープ(1刻み/tick)。角度→威力の順に合わせ、揃ったら打つ。
		# 方向キーはsimulation.gdのSERVE処理が照準として解釈する
		var to_net: int = SimInput.IN_RIGHT if s.serving_team == 0 else SimInput.IN_LEFT
		var away: int = SimInput.IN_LEFT if s.serving_team == 0 else SimInput.IN_RIGHT
		if s.serve_aim < target[0]:
			return to_net
		elif s.serve_aim > target[0]:
			return away
		elif s.serve_pow < target[1]:
			return SimInput.IN_UP
		elif s.serve_pow > target[1]:
			return SimInput.IN_DOWN
	if s.timer <= 0:
		return SimInput.IN_ACTION
	return 0

static func decide(s, idx: int, cfg) -> int:
	var team: int = idx / 2
	var p = s.players[idx]
	var mask: int = skill_of(s, idx)
	var deadzone: int = cfg.player_reach / 2
	if s.phase == SimStateScript.PHASE_SERVE:
		return _decide_serve(s, idx, cfg, mask)
	if s.phase == SimStateScript.PHASE_POINT_PAUSE:
		# ポーズ中は棒立ちせず持ち場へ歩いて戻る(次ラリーの準備)
		return _walk_to(p, _spawn_x(idx, cfg), deadzone)
	if s.phase != SimStateScript.PHASE_RALLY:
		return 0
	var on_own_side: bool = (s.ball_x < cfg.net_x) == (team == 0)
	if not on_own_side:
		return _walk_to(p, _spawn_x(idx, cfg), deadzone)
	# 落下点予測(能力なしは現在のボールxを追う=v0挙動)
	var land_x: int = s.ball_x
	if mask & AB_PREDICT:
		land_x = _predict_landing_x(s, cfg, cfg.floor_y - cfg.player_reach_up / 2)
	var input: int = 0
	# 役割分担: 落下点に近い方がレシーバー。相方は支援位置へ
	# (アタック可能ならネット際で待ち、そうでなければ持ち場)
	var receiver := true
	if mask & AB_ROLES:
		var mate: int = team * 2 + (1 - idx % 2)
		var my_d: int = absi(p.x - land_x)
		var mate_d: int = absi(s.players[mate].x - land_x)
		receiver = my_d < mate_d or (my_d == mate_d and idx < mate)
	if receiver:
		input = _walk_to(p, land_x, deadzone)
	else:
		var support_x: int
		if mask & AB_ATTACK:
			# ネット際の自陣側でトス待ち(前衛)
			var off: int = FP.from_int(48)
			support_x = cfg.net_x - off if team == 0 else cfg.net_x + off
		else:
			support_x = _spawn_x(idx, cfg)
		input = _walk_to(p, support_x, deadzone)
	# ジャンプアタック: 自チームが上げた球(タッチ数に余裕あり)へ会合できるなら跳ぶ。
	# 狙いはジャストミート能力があればスイートスポット、なければリーチ
	var sweet: int = cfg.player_reach * cfg.spike_sweet_pct / 100
	if (mask & AB_ATTACK) and p.on_ground == 1 and p.stun == 0 \
			and s.last_touch_team == team and s.touches < cfg.max_touches:
		var meet_limit: int = sweet if (mask & AB_SWEET) else cfg.player_reach
		if _jump_will_meet(s, p, cfg, meet_limit):
			input |= SimInput.IN_JUMP
	# ヒット判定(simulation.gdの_resolve_hitと同じ楕円)
	var dx: int = s.ball_x - p.x
	var dy: int = s.ball_y - p.y
	var dy_n: int = dy * cfg.player_reach / cfg.player_reach_up
	var d2: int = dx * dx + dy_n * dy_n
	if d2 <= cfg.player_reach * cfg.player_reach:
		if p.on_ground == 0:
			# 空中: ネットに近ければ叩き下ろすスパイク、遠ければ緩く相手コートへ。
			# 遠距離スパイクは自陣に落ちて自滅するため打たない
			var net_dist: int = absi(p.x - cfg.net_x)
			var can_spike: bool = net_dist < FP.from_int(120)
			# ジャストミート狙い: スイート外でボールがまだ自分より上なら1tick待つ
			# (落ちてくれば必ずスイートを通るか、下に抜けた時点で打つ)
			var hold: bool = (mask & AB_SWEET) and d2 > sweet * sweet and dy < 0
			if not hold:
				input |= SimInput.IN_ACTION
				if can_spike:
					input |= SimInput.IN_DOWN
		else:
			input |= SimInput.IN_ACTION
	return input
