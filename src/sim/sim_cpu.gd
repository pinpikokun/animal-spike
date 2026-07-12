# CPU入力生成。シミュレーション層の一部なので完全決定論・int演算のみ
# 状態を読むだけで書き換えない(副作用禁止)。
# simulation.gdをpreloadしない(循環防止)。定数はsim_input.gdから取る
#
# v2: CpuProfile方式(調査doc: docs/superpowers/research/2026-07-13-cpu-difficulty-research.md)。
# プレイヤーごとにstate.players[i].cpu(8bit x 7欄)で強さの次元を個別に持つ:
#   能力フラグ(戦略層) + 反応遅延/狙い誤差/ミス率/ジャスト率/予測深度/配球IQ(反応・実行層)
# 憲法: 相手チームの入力・照準は読まない(観測可能な物理状態のみ)。物理性能は強化しない。
# 乱数は逐次PRNG禁止、stateless keyed hash(salt+last_hit_tick+actor)のみ。
# 確率は「タッチ1回につき1抽選」(last_hit_tickがタッチ毎に変わりタッチ間は不変であることを利用)
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")

# 能力フラグ(プロファイルの能力バイト)
const AB_PREDICT := 1    # 落下点予測(弾道積分)。無いと現在のボールxを追う
const AB_ROLES := 2      # 役割分担(落下点に近い方がレシーバー、相方は支援位置)
const AB_ATTACK := 4     # 味方が上げた球へジャンプ会合してアタック
const AB_SWEET := 8      # アタックはジャストミート(スイートスポット)を狙う
const AB_SERVE_VAR := 16 # サーブの角度・威力を決定論的に散らす

# プロファイルの欄(8bitずつ)
const P_AB := 0      # 能力フラグ
const P_DELAY := 8   # 反応遅延tick(相手の打球からこのtick数は動き出さない)
const P_AIM := 16    # 狙い誤差(リーチ比%、タッチ毎に1回抽選)
const P_MISS := 24   # ミス率(0-255。惜しい失敗=半歩ずれる/跳ばない)
const P_SWEET := 32  # ジャスト成功率(0-255)
const P_DEPTH := 40  # 弾道予測の壁反射深度(0=放物線のみ..3=無制限)
const P_TIQ := 48    # 配球知能(0=そのまま返す..3=相手から遠い着弾を選ぶ)

# 乱数のsalt(判定種別の分離)
const SALT_AIM := 1
const SALT_MISS := 2
const SALT_SWEET := 3

# 難易度プリセット(調査docの数値。最強でも遅延6tick=約100msを残し、ミス床3%を保証する)
const PRESET_WEAK := (24 << P_DELAY) | (40 << P_AIM) | (64 << P_MISS) | (26 << P_SWEET)
const PRESET_NORMAL := AB_PREDICT | (14 << P_DELAY) | (25 << P_AIM) | (26 << P_MISS) \
	| (102 << P_SWEET) | (1 << P_DEPTH) | (1 << P_TIQ)
# 強にはアタック(攻撃の上積み)を先に与える。役割分担は最強専用:
# KPI計測でROLES(単独レシーバー制)は攻撃力の裏付けなしでは2人収束の冗長性に
# 劣ると判明したため(普通>強の逆転)、順序を能力の実効値で決めている
const PRESET_STRONG := (AB_PREDICT | AB_ATTACK | AB_SERVE_VAR) | (10 << P_DELAY) | (15 << P_AIM) \
	| (13 << P_MISS) | (153 << P_SWEET) | (2 << P_DEPTH) | (2 << P_TIQ)
const PRESET_MAX := (AB_PREDICT | AB_ROLES | AB_ATTACK | AB_SWEET | AB_SERVE_VAR) \
	| (6 << P_DELAY) | (5 << P_AIM) | (8 << P_MISS) | (191 << P_SWEET) | (3 << P_DEPTH) | (3 << P_TIQ)
const PRESETS: Array[int] = [PRESET_WEAK, PRESET_NORMAL, PRESET_STRONG, PRESET_MAX]

static func make_profile(ab: int, delay: int, aim: int, miss: int, sweet: int,
		depth: int, tiq: int) -> int:
	return (ab & 0xFF) | ((delay & 0xFF) << P_DELAY) | ((aim & 0xFF) << P_AIM) \
		| ((miss & 0xFF) << P_MISS) | ((sweet & 0xFF) << P_SWEET) \
		| ((depth & 0xFF) << P_DEPTH) | ((tiq & 0xFF) << P_TIQ)

static func prof_byte(profile: int, shift: int) -> int:
	return (profile >> shift) & 0xFF

# stateless keyed hash。キーの主軸はlast_hit_tick(タッチ毎に変わりタッチ間は不変)なので
# 「タッチ1回につき1抽選」が構造的に保証される。負数はマスクで排除
static func _noise(salt: int, key: int, actor: int) -> int:
	var z: int = key + salt * 1000003 + actor * 998244353
	z = (z ^ (z >> 16)) * 2246822519
	z = (z ^ (z >> 13)) * 3266489917
	z = z ^ (z >> 16)
	return z & 0x7FFFFFFFFFFFFFFF

static func _roll(salt: int, s, actor: int) -> int:
	return _noise(salt, s.last_hit_tick, actor)

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

# 任意の初期条件から高さtarget_yへ落ちる位置xを弾道積分で予測する。
# max_bounce=壁反射を読む深さ(0なら放物線のみ=壁で崩せる弱いCPUになる)。
# ネット反射は無視する簡易版(ネット直撃は稀で、外れても追い直すだけ)
static func _land_x_from(x: int, y: int, vx: int, vy: int, cfg, target_y: int, max_bounce: int) -> int:
	if y >= target_y and vy >= 0:
		return x
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	var bounces: int = 0
	for t in 240:
		vy += cfg.gravity
		x += vx
		y += vy
		if x < left:
			if bounces >= max_bounce:
				break
			bounces += 1
			x = left + (left - x)
			vx = -vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		elif x > right:
			if bounces >= max_bounce:
				break
			bounces += 1
			x = right - (x - right)
			vx = -vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		if y >= target_y and vy > 0:
			break
	return clampi(x, left, right)

static func _predict_landing_x(s, cfg, target_y: int, max_bounce: int) -> int:
	return _land_x_from(s.ball_x, s.ball_y, s.ball_vx, s.ball_vy, cfg, target_y, max_bounce)

# 候補弾道がネットを越えられるか(越える瞬間の高さが上端よりball_radius以上上か)。
# _land_x_fromはネットを無視するため、鋭角スパイクのような低い弾道の候補は
# この検査を通してから採用する(ネット直撃=自陣落ちの自滅を配球段階で弾く)
static func _clears_net(x: int, y: int, vx: int, vy: int, cfg) -> bool:
	for t in 240:
		var prev_x: int = x
		vy += cfg.gravity
		x += vx
		y += vy
		if (prev_x < cfg.net_x) != (x < cfg.net_x):
			return y <= cfg.net_top_y - cfg.ball_radius
		if y >= cfg.floor_y and vy > 0:
			return false
	return false

# 今ジャンプしたらリーチ(半径limit)でボールと会合できるか(双方の弾道を並走積分)
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

# サーブの狙い(角度/威力)をスコアから決定論的に散らす(安全域24..40度/100..125%に制限)
static func _serve_target(s, idx: int) -> Array[int]:
	var h: int = absi((s.score_l * 73856093) ^ (s.score_r * 19349663) ^ (idx * 83492791))
	var aim: int = 24 + h % 17
	var pow_pct: int = 100 + (h / 97) % 26
	return [aim, pow_pct]

static func _decide_serve(s, idx: int, cfg, ab: int) -> int:
	# サーブ遅延タイマーはsimulation.gdのstep()が減算する(ここは読むだけ)
	if idx != s.serving_team * 2:
		return 0
	if ab & AB_SERVE_VAR:
		var target := _serve_target(s, idx)
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

# 空中の配球(TARGET_IQ>=2): スパイク/緩い返し/遠い山なりの3候補の着弾点を計算し、
# 相手2人から最も遠い所へ落ちる打ち方を選ぶ。「反応でなく判断で強い」の芯
static func _pick_air_shot(s, p, cfg, team: int, can_spike: bool) -> int:
	var dir: int = 1 if team == 0 else -1
	var target_y: int = cfg.floor_y - cfg.ball_radius
	# 候補: [入力ビット, vx, vy](速度はsimulation._apply_hitの空中各分岐と同じ式)
	var cands: Array = []
	var fwd_key: int = SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
	if can_spike:
		# 鋭角(下のみ)=前面へ鋭く、緩角(下+横)=後面へ低く。着弾比較で選ばれる
		cands.append([SimInput.IN_ACTION | SimInput.IN_DOWN,
			dir * cfg.spike_steep_vx, cfg.spike_steep_vy])
		cands.append([SimInput.IN_ACTION | SimInput.IN_DOWN | fwd_key,
			dir * cfg.spike_vx, cfg.spike_vy])
	cands.append([SimInput.IN_ACTION, dir * cfg.serve_soft_vx, -cfg.serve_soft_vy])
	cands.append([SimInput.IN_ACTION | fwd_key, dir * cfg.toss_fwd_vx, -cfg.toss_fwd_vy])
	var best_input: int = SimInput.IN_ACTION
	var best_score: int = -1
	for c in cands:
		var land: int = _land_x_from(s.ball_x, s.ball_y, c[1], c[2], cfg, target_y, 3)
		# 相手コートに落ちない打ち方・ネットに掛かる打ち方は選ばない
		var in_opp: bool = land > cfg.net_x if team == 0 else land < cfg.net_x
		if not in_opp:
			continue
		if not _clears_net(s.ball_x, s.ball_y, c[1], c[2], cfg):
			continue
		var score: int = 0x7FFFFFFFFFFFFFFF
		for i in 2:
			var opp = s.players[(1 - team) * 2 + i]
			# スタン中の相手は追えない=その分遠いのと同義(メテオ後の追い打ちが賢くなる)
			var d: int = absi(land - opp.x) + opp.stun * cfg.move_speed
			score = mini(score, d)
		if score > best_score:
			best_score = score
			best_input = c[0]
	return best_input

static func decide(s, idx: int, cfg) -> int:
	var team: int = idx / 2
	var p = s.players[idx]
	var prof: int = p.cpu
	var ab: int = prof_byte(prof, P_AB)
	var deadzone: int = cfg.player_reach / 2
	if s.phase == SimStateScript.PHASE_SERVE:
		return _decide_serve(s, idx, cfg, ab)
	if s.phase == SimStateScript.PHASE_POINT_PAUSE:
		# ポーズ中は棒立ちせず持ち場へ歩いて戻る(次ラリーの準備)
		return _walk_to(p, _spawn_x(idx, cfg), deadzone)
	if s.phase != SimStateScript.PHASE_RALLY:
		return 0
	var reach: int = cfg.player_reach
	# 反応遅延: 相手チームの打球からdelay tickの間は「まだ気づいていない」=
	# 移動・ジャンプを凍結する(その場で固まる)。腕は出る(リーチ内のヒットは可)。
	# 0tick超反応は「ずるい」の主因なので最強でも遅延を残す(調査docの憲法)
	var delay: int = prof_byte(prof, P_DELAY)
	var frozen: bool = s.last_touch_team >= 0 and s.last_touch_team != team \
		and s.tick - s.last_hit_tick < delay
	var on_own_side: bool = (s.ball_x < cfg.net_x) == (team == 0)
	var input: int = 0
	if not frozen:
		if not on_own_side:
			input = _walk_to(p, _spawn_x(idx, cfg), deadzone)
		else:
			input = _decide_positioning(s, idx, p, cfg, team, prof, deadzone)
	# ヒット判定(simulation.gdの_resolve_hitと同じ楕円)。凍結中も腕は出る
	var dx: int = s.ball_x - p.x
	var dy: int = s.ball_y - p.y
	var dy_n: int = dy * reach / cfg.player_reach_up
	var d2: int = dx * dx + dy_n * dy_n
	# ミス抽選が出たタッチでは振りも一拍遅れる(ボールが体の中心を過ぎるまで
	# 打たない=接触窓が狭まり、位置ずれと合わさって「惜しい後逸」になる)
	var late_swing: bool = s.last_touch_team >= 0 and s.last_touch_team != team \
		and _roll(SALT_MISS, s, idx) % 256 < prof_byte(prof, P_MISS) and dy < 0
	if d2 <= reach * reach and not late_swing:
		if p.on_ground == 0:
			input |= _decide_air_hit(s, idx, p, cfg, team, prof, d2, dy)
		else:
			# 地上ヒットの組み立て: 素のバンプは真上に上がるだけでネットを越えない。
			# チームにアタッカーがいてタッチ数に余裕があれば真上に上げて呼び込み、
			# そうでなければ(=これが最後のタッチ)ネット方向キーで前トスして越す
			# JUMPも落とす: アクション+上ジャンプは小ホップ化(トス用)のため、
			# 位置取りで立てたジャンプ意図が地上ヒットと混ざると跳躍が化ける
			input &= ~(SimInput.IN_LEFT | SimInput.IN_RIGHT | SimInput.IN_JUMP)
			input |= SimInput.IN_ACTION | _ground_shot_keys(s, idx, cfg, team, prof)
	return input

# 地上ヒット時の方向キー選択(上=セットアップ / ネット方向=前トスで越す)
static func _ground_shot_keys(s, idx: int, cfg, team: int, prof: int) -> int:
	var mate = s.players[team * 2 + (1 - idx % 2)]
	var team_ab: int = prof_byte(prof, P_AB) | prof_byte(mate.cpu, P_AB)
	var touches_after: int = s.touches + 1 if s.last_touch_team == team else 1
	if (team_ab & AB_ATTACK) and touches_after < cfg.max_touches:
		return SimInput.IN_UP  # 真上へ高く上げてアタックを呼ぶ(セルフトスも可)
	return SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT

# 地上での位置取り(レシーブ/支援/ジャンプアタック)。frozenでない時のみ呼ばれる
static func _decide_positioning(s, idx: int, p, cfg, team: int, prof: int, deadzone: int) -> int:
	var ab: int = prof_byte(prof, P_AB)
	var reach: int = cfg.player_reach
	# 落下点予測(能力なしは現在のボールxを追う=最弱挙動)。深度=壁反射を読む数
	var land_x: int = s.ball_x
	if ab & AB_PREDICT:
		var depth: int = prof_byte(prof, P_DEPTH)
		var max_bounce: int = 240 if depth >= 3 else depth
		land_x = _predict_landing_x(s, cfg, cfg.floor_y - cfg.player_reach_up / 2, max_bounce)
	# 狙い誤差: 正確に計算した落下点をタッチ毎に1回だけ汚す(tick毎だと震える)。
	# 「読み違えたが本人は確信している」人間らしさが出る
	var aim_err: int = prof_byte(prof, P_AIM)
	if aim_err > 0:
		var half: int = reach * aim_err / 100
		if half > 0:
			land_x += _roll(SALT_AIM, s, idx) % (2 * half + 1) - half
	# ミス(惜しい失敗): 相手からの球に対しタッチ毎1抽選で「半歩深めにずれる」。
	# リーチの縁で拾えたり拾えなかったりする=人間くさい崩れ方になる
	var receiving: bool = s.last_touch_team >= 0 and s.last_touch_team != team
	var miss_roll: bool = receiving \
		and _roll(SALT_MISS, s, idx) % 256 < prof_byte(prof, P_MISS)
	if miss_roll:
		land_x += -reach * 3 / 4 if team == 0 else reach * 3 / 4
	# 役割分担: 落下点に近い方がレシーバー。人間の相方が同じ球を追えるなら譲る
	# (人間とのお見合い衝突は事故なのでCPU側が広めに退く)
	var receiver := true
	if ab & AB_ROLES:
		var mate_slot: int = 1 - idx % 2
		var mate = s.players[team * 2 + mate_slot]
		var my_d: int = absi(p.x - land_x)
		var mate_d: int = absi(mate.x - land_x)
		# 担当の相補分割(margin=リーチ1/4)。操作スロット側は境界を含めて広く取り、
		# 非操作スロット側は狭く譲る。互いの規則が正確に補集合なので
		# 「両者譲り」のデッドロックも「両者突進」のお見合いも構造的に起きない。
		# 人間が操作している時はこの margin が「人間優先の譲り」として働き、
		# 人間がボール方向へ移動中ならさらに広く譲る
		var controlled: int = s.controlled_l if team == 0 else s.controlled_r
		var margin: int = reach / 4
		if idx % 2 == controlled:
			receiver = my_d <= mate_d + margin
		else:
			var mate_moving: bool = (mate.vx > 0 and land_x > mate.x) \
				or (mate.vx < 0 and land_x < mate.x)
			receiver = not mate_moving and mate_d > my_d + margin
	var input: int
	if receiver:
		input = _walk_to(p, land_x, deadzone)
	else:
		var support_x: int
		if receiving:
			# 守備時のカバー: レシーバーのネット寄り24pxに詰めて並び、後逸・ミスを拾う。
			# 単独レシーバー制は相方のミス1回が即失点になる(役割分担が冗長性を壊す)
			# ため、受けの局面は必ず2人で狭く挟む。カバーの立ち位置は精密に
			# (deadzone半分)取らないと網の外に立ってしまう
			var toward_net: int = 1 if team == 0 else -1
			return _walk_to(p, land_x + toward_net * FP.from_int(24), deadzone / 2)
		elif ab & AB_ATTACK:
			var off: int = FP.from_int(48)
			support_x = cfg.net_x - off if team == 0 else cfg.net_x + off
		else:
			support_x = _spawn_x(idx, cfg)
		input = _walk_to(p, support_x, deadzone)
	# ジャンプアタック: 自チームの上げ球へ会合できるなら跳ぶ。ミス抽選が出た
	# タッチでは跳ばない(=1拍遅れる、という惜しい失敗)
	if (ab & AB_ATTACK) and p.on_ground == 1 and p.stun == 0 and not miss_roll \
			and s.last_touch_team == team and s.touches < cfg.max_touches:
		var meet_limit: int = reach
		if (ab & AB_SWEET) and _sweet_ok(s, idx, prof):
			meet_limit = reach * cfg.spike_sweet_pct / 100
		if _jump_will_meet(s, p, cfg, meet_limit):
			input |= SimInput.IN_JUMP
	return input

static func _sweet_ok(s, idx: int, prof: int) -> bool:
	return _roll(SALT_SWEET, s, idx) % 256 < prof_byte(prof, P_SWEET)

# 空中ヒットの打ち分け。ネット遠方のスパイクは自陣に落ちて自滅するため打たない
static func _decide_air_hit(s, idx: int, p, cfg, team: int, prof: int, d2: int, dy: int) -> int:
	var ab: int = prof_byte(prof, P_AB)
	var can_spike: bool = absi(p.x - cfg.net_x) < FP.from_int(120)
	var sweet_r: int = cfg.player_reach * cfg.spike_sweet_pct / 100
	var use_sweet: bool = (ab & AB_SWEET) and _sweet_ok(s, idx, prof)
	# ジャストミート狙い: スイート外でボールがまだ上にある間は1tick待つ
	if use_sweet and d2 > sweet_r * sweet_r and dy < 0:
		return 0
	if prof_byte(prof, P_TIQ) >= 2:
		return _pick_air_shot(s, p, cfg, team, can_spike)
	var input: int = SimInput.IN_ACTION
	if can_spike:
		# 配球IQなしは緩角スパイク(下+横)固定。鋭角はネット至近でないと
		# 自陣落ちするため、着弾を計算しない頭脳には持たせない
		input |= SimInput.IN_DOWN
		input |= SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
	return input
