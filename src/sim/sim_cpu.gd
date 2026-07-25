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
const Chars := preload("res://src/sim/chars.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")

# 能力フラグ(プロファイルの能力バイト)
const AB_PREDICT := 1    # 落下点予測(弾道積分)。無いと現在のボールxを追う
const AB_ROLES := 2      # 役割分担(落下点に近い方がレシーバー、相方は支援位置)
const AB_ATTACK := 4     # 味方が上げた球へジャンプ会合してアタック
const AB_SWEET := 8      # アタックはジャストミート(スイートスポット)を狙う
const AB_SERVE_VAR := 16 # サーブの角度・威力を決定論的に散らす
const AB_BLOCK := 32     # 相手のネット際アタックに対しネットへ詰めて跳ぶ(ブロック)
const AB_HAT := 64       # 帽子投げ: 敵球がネット際へ落ちる軌道を読み、滞在窓に合わせて投げる

# 帽子ギミックの定数(simulation.gdの鏡)。simulation.gdはsim_cpuをpreloadするため
# こちらから参照できない(循環)。ずれはtest_cpu_hat.gdの番人テストが検出する
const HAT_KIND := 1          # = KIND_CAP(エンティティ種別)
const HAT_WINDUP := 30       # = THROW_TICKS
const HAT_FLY_PX := 3        # = CAP_THROW_PX
const HAT_OUT_TICKS := 24    # = CAP_OUT_TICKS
const HAT_HOVER_TICKS := 90  # = CAP_HOVER_TICKS
const HAT_RADIUS_PX := 12    # = CAP_RADIUS_PX
const HAT_HAND_UP_PX := 6    # = CAP_HAND_UP_PX

static func _hit_reach(char_id: int, base_reach: int, intent_kind: int) -> int:
	return HitResolver.reach_for_intent(char_id, base_reach, intent_kind)

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
const SALT_RECEIVE := 4
const SALT_SUPER := 5
const SALT_ATTACK := 6
const SALT_ROLE := 7

# 難易度プリセット(2026-07-13「人間化」改訂)。方針:
# - 超人反応の撤廃: 最強でも遅延12tick=200ms(人間の上級者並み)。強さは反応でなく
#   読み(予測深度)・技(ブロック/ジャスト)・判断(配球IQ)で出す
# - 味方同士の役割分担は全段共通。予測深度・精度・技術判断の差は各段に残す。
const PRESET_WEAK := AB_ROLES | (24 << P_DELAY) | (40 << P_AIM) \
	| (64 << P_MISS) | (26 << P_SWEET)
const PRESET_NORMAL := (AB_PREDICT | AB_ROLES | AB_ATTACK) \
	| (16 << P_DELAY) | (25 << P_AIM) \
	| (13 << P_MISS) | (0 << P_SWEET) | (1 << P_TIQ)
const PRESET_STRONG := (AB_PREDICT | AB_ROLES | AB_ATTACK | AB_SWEET \
	| AB_SERVE_VAR | AB_BLOCK | AB_HAT) | (13 << P_DELAY) \
	| (15 << P_AIM) | (13 << P_MISS) | (153 << P_SWEET) | (2 << P_DEPTH) | (2 << P_TIQ)
const PRESET_MAX := (AB_PREDICT | AB_ROLES | AB_ATTACK | AB_SWEET | AB_SERVE_VAR | AB_BLOCK | AB_HAT) \
	| (12 << P_DELAY) | (8 << P_AIM) | (8 << P_MISS) | (191 << P_SWEET) | (3 << P_DEPTH) | (3 << P_TIQ)
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

# ラリー番号とチームだけから役を引く。状態には保存せず、同じラリー中は常に同じ役。
static func _is_rally_attacker(s, idx: int) -> bool:
	var team: int = idx / 2
	var slot: int = idx % 2
	var role_roll: int = _noise(SALT_ROLE, s.rally_seq, team) % 9
	match role_roll:
		0, 1, 5, 8:
			return slot == 0
		_:
			return slot == 1

static func _is_rally_blocker(s, idx: int) -> bool:
	var team: int = idx / 2
	var slot: int = idx % 2
	var role_roll: int = _noise(SALT_ROLE, s.rally_seq, team) % 9
	match role_roll:
		0, 2, 5, 8:
			return true
		1, 4, 7:
			return slot == 0
		_:
			return false

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

# 相手の見えているトスには打球後の反応遅延を掛けず、後衛だけが自陣中央を先回りする。
static func _is_pre_attack_receiver(s, idx: int, cfg, team: int) -> bool:
	if s.last_touch_team != 1 - team or s.ball_attack_kind != SimStateScript.BALL_ATTACK_NONE:
		return false
	var ball_on_opponent_side: bool = (s.ball_x < cfg.net_x) != (team == 0)
	if not ball_on_opponent_side or s.ball_vy > 0:
		return false
	var p = s.players[idx]
	var mate = s.players[team * 2 + (1 - idx % 2)]
	var my_net_distance: int = absi(p.x - cfg.net_x)
	var mate_net_distance: int = absi(mate.x - cfg.net_x)
	return my_net_distance > mate_net_distance \
		or (my_net_distance == mate_net_distance and idx % 2 == 0)

static func _pre_attack_cover_x(cfg, team: int) -> int:
	return cfg.net_x / 2 if team == 0 \
		else cfg.net_x + (cfg.court_width - cfg.net_x) / 2

# 非レシーバー時の守備ホーム。自チームの2定位置(後衛/前衛)のうち、相棒(操作キャラ)
# に対して自分が今いる側のホームを選ぶ=相棒とボールを横切らず反対側を埋める。
# 交差しないのでボール落下点へ吸い寄せられて再び相棒へ張り付くのを防ぐ。決定論・読み取りのみ
static func _cover_home(p, mate, idx: int, cfg) -> int:
	var team: int = idx / 2
	var home_a: int = _spawn_x(team * 2, cfg)      # 後衛(壁寄り)
	var home_b: int = _spawn_x(team * 2 + 1, cfg)  # 前衛(ネット寄り)
	var lo: int = mini(home_a, home_b)
	var hi: int = maxi(home_a, home_b)
	return hi if p.x >= mate.x else lo

# 非レシーバーの守備目標: 相棒と反対側のホームへ回り、最低sep(リーチ1.5倍)離す。
# 相棒(人間)が前に出たら自分は下がる、という追従がこの1関数で決まる
static func _cover_target(p, mate, idx: int, cfg) -> int:
	var tx: int = _cover_home(p, mate, idx, cfg)
	var sep: int = cfg.cpu_mate_spacing
	if absi(tx - mate.x) < sep:
		tx = mate.x + sep if tx >= mate.x else mate.x - sep
	var lo: int = cfg.player_reach
	var hi: int = cfg.court_width - cfg.player_reach
	if tx < lo or tx > hi:
		var opposite: int = mate.x - sep if tx > mate.x else mate.x + sep
		if opposite >= lo and opposite <= hi:
			tx = opposite
	return clampi(tx, lo, hi)

static func _is_cpu_mate_receiver(s, idx: int, team: int, target_x: int) -> bool:
	var mate_idx: int = team * 2 + (1 - idx % 2)
	var my_d: int = absi(s.players[idx].x - target_x)
	var mate_d: int = absi(s.players[mate_idx].x - target_x)
	return my_d < mate_d or (my_d == mate_d and idx < mate_idx)

static func _mate_is_human(s, team: int, mate_slot: int) -> bool:
	var controlled: int = s.controlled_l if team == 0 else s.controlled_r
	return mate_slot == controlled and (s.human_team_mask & (1 << team)) != 0

static func _should_yield_hit_to_cpu_mate(
		s, idx: int, cfg, team: int, prof: int) -> bool:
	if not (prof_byte(prof, P_AB) & AB_ROLES):
		return false
	if s.last_touch_team < 0 or s.last_touch_team == team:
		return false
	var mate_slot: int = 1 - idx % 2
	if _mate_is_human(s, team, mate_slot):
		return false
	var p = s.players[idx]
	var mate = s.players[team * 2 + mate_slot]
	if mate.stun > 0 or mate.hit_cooldown > 0:
		return false
	if absi(p.x - mate.x) > cfg.cpu_mate_spacing / 2:
		return false
	var target_x: int = _receive_target_x(s, cfg, prof)
	return not _is_cpu_mate_receiver(s, idx, team, target_x)

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
			vx = BallPhysics.wall_reflect_vx(vx, cfg)
		elif x > right:
			if bounces >= max_bounce:
				break
			bounces += 1
			x = right - (x - right)
			vx = BallPhysics.wall_reflect_vx(vx, cfg)
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
	# player_movementのランク別・上昇下降別ジャンプ物理と同じ軌道で会合を予測する。
	# 旧cfg.jump_speedでは実際の跳躍と予測がずれ、45%芯へ到達しなかった。
	var jump_rank: int = Chars.rank(p.char_id, Chars.Profile.ABILITY_JUMP)
	var jump_height: int = PlayerMovement._jump_height_px(jump_rank)
	var up_ticks: int = PlayerMovement._jump_ticks(true)
	var up_gravity: int = PlayerMovement._jump_gravity(jump_height, up_ticks, true)
	var down_ticks: int = PlayerMovement._jump_ticks(false)
	var down_gravity: int = PlayerMovement._jump_gravity(
		jump_height, down_ticks, false)
	var pvy: int = -up_gravity * up_ticks
	for t in 48:
		pvy += up_gravity if pvy < 0 else down_gravity
		py += pvy
		if py >= cfg.floor_y and pvy > 0:
			break
		# simulationはプレイヤー移動→ヒット判定→ボール移動の順。
		var dx: int = bx - p.x
		var dy: int = by - py
		var dy_n: int = dy * cfg.player_reach / cfg.player_reach_up
		if dx * dx + dy_n * dy_n <= limit * limit:
			return true
		bvy += cfg.gravity
		bx += bvx
		by += bvy
	return false

# 地上の現在位置から、未来の球位置へ芯距離で会合できる離陸待ちtickと会合xを返す。
# 戻り値[0]が0なら今跳ぶ。-1なら現在の球筋では芯会合を作れない。
static func _sweet_jump_plan(s, p, cfg, sweet_r: int) -> Array[int]:
	var jump_rank: int = Chars.rank(p.char_id, Chars.Profile.ABILITY_JUMP)
	var jump_height: int = PlayerMovement._jump_height_px(jump_rank)
	var up_ticks: int = PlayerMovement._jump_ticks(true)
	var up_gravity: int = PlayerMovement._jump_gravity(jump_height, up_ticks, true)
	var down_ticks: int = PlayerMovement._jump_ticks(false)
	var down_gravity: int = PlayerMovement._jump_gravity(
		jump_height, down_ticks, false)
	var jump_y: Array[int] = []
	var py: int = cfg.floor_y
	var pvy: int = -up_gravity * up_ticks
	for age in 48:
		pvy += up_gravity if pvy < 0 else down_gravity
		py += pvy
		if py >= cfg.floor_y and pvy > 0:
			break
		jump_y.append(py)
	var bx: int = s.ball_x
	var by: int = s.ball_y
	var bvx: int = s.ball_vx
	var bvy: int = s.ball_vy
	var speed: int = cfg.move_speed * Chars.stat(p.char_id, "speed") / 100
	var best_delay: int = 999
	var best_x: int = p.x
	# 高い味方トスは頂点から接触まで80tickを超えるため、着地まで十分に探索する。
	for future in 180:
		var contact_tick: int = future + 1
		for age_index in jump_y.size():
			var jump_age: int = age_index + 1
			if jump_age > contact_tick:
				break
			var launch_delay: int = contact_tick - jump_age
			var dy_n: int = (by - jump_y[age_index]) \
				* cfg.player_reach / cfg.player_reach_up
			if dy_n * dy_n > sweet_r * sweet_r:
				continue
			var remaining_dx: int = maxi(absi(bx - p.x) - speed * launch_delay, 0)
			if remaining_dx * remaining_dx + dy_n * dy_n > sweet_r * sweet_r:
				continue
			if launch_delay < best_delay:
				best_delay = launch_delay
				best_x = bx
		if best_delay == 0:
			break
		bvy += cfg.gravity
		bx += bvx
		by += bvy
		if bx < cfg.ball_radius:
			bx = cfg.ball_radius + (cfg.ball_radius - bx)
			bvx = BallPhysics.wall_reflect_vx(bvx, cfg)
		elif bx > cfg.court_width - cfg.ball_radius:
			var right: int = cfg.court_width - cfg.ball_radius
			bx = right - (bx - right)
			bvx = BallPhysics.wall_reflect_vx(bvx, cfg)
		if by >= cfg.floor_y - cfg.ball_radius:
			break
	if best_delay == 999:
		return [-1, p.x]
	return [best_delay, best_x]

static func _receive_target_x(s, cfg, prof: int) -> int:
	var ab: int = prof_byte(prof, P_AB)
	if not (ab & AB_PREDICT):
		return s.ball_x
	var depth: int = prof_byte(prof, P_DEPTH)
	var max_bounce: int = 240 if depth >= 3 else depth
	return _predict_landing_x(
		s, cfg, cfg.floor_y - cfg.player_reach_up / 2, max_bounce)

static func _can_prepare_just_receive(s, p, cfg, receive_reach: int,
		target_x: int, stance_deadzone: int) -> bool:
	var contact_ticks: int = _ticks_until_receive_at(
		s, p, cfg, receive_reach, target_x)
	if contact_ticks > 180:
		return false
	var speed: int = cfg.move_speed * Chars.stat(p.char_id, "speed") / 100
	# 構え経路と同じ狭いデッドゾーンまで移動する時間を見積もる。
	var travel: int = maxi(absi(target_x - p.x) - stance_deadzone, 0)
	var ready_ticks: int = (travel + speed - 1) / speed if travel > 0 else 0
	if travel > 0 or p.vx != 0:
		ready_ticks += 1  # 到着後に入力を離して静止するtick
	if p.receive_stance < 0:
		ready_ticks += 1  # 押しっぱなしラッチを解除して次のエッジを作るtick
	var press_tick: int = maxi(contact_ticks - 5, 0)
	return ready_ticks <= press_tick

static func _air_will_meet_sweet(s, p, cfg, sweet_r: int) -> bool:
	var bx: int = s.ball_x
	var by: int = s.ball_y
	var bvx: int = s.ball_vx
	var bvy: int = s.ball_vy
	var py: int = p.y
	var pvy: int = p.vy
	var jump_rank: int = Chars.rank(p.char_id, Chars.Profile.ABILITY_JUMP)
	var jump_height: int = PlayerMovement._jump_height_px(jump_rank)
	for tick in 48:
		var gravity: int = PlayerMovement._jump_gravity(
			jump_height, PlayerMovement._jump_ticks(pvy < 0), pvy < 0)
		pvy += gravity
		py += pvy
		if py >= cfg.floor_y:
			break
		var dx: int = bx - p.x
		var dy_n: int = (by - py) * cfg.player_reach / cfg.player_reach_up
		if dx * dx + dy_n * dy_n <= sweet_r * sweet_r:
			return true
		bvy += cfg.gravity
		bx += bvx
		by += bvy
	return false

# サーブトスの狙い(角度/高さ)をスコアから決定論的に散らす。
# 2段階サーブでは角度を倒すほどトスが遠くへ飛び、CPUの足(3px/tick)で
# 追いつける限界がある。安全域8..24度/100..125%(24度超は走っても間に合わず
# 同じ狙いの再トスが無限ループする=決定論の膠着、実測で確認済み)
static func _serve_target(s, idx: int) -> Array[int]:
	# 左右チームの同じスロットは鏡像の狙いになるよう、絶対indexではなくslotを使う。
	var slot: int = idx % 2
	var h: int = absi((s.score_l * 73856093) ^ (s.score_r * 19349663) \
		^ (slot * 83492791))
	var aim: int = 8 + h % 17
	var pow_pct: int = 100 + (h / 97) % 26
	return [aim, pow_pct]

static func _decide_serve(s, idx: int, cfg, prof: int) -> int:
	var ab: int = prof_byte(prof, P_AB)
	# サーブ遅延タイマーはsimulation.gdのstep()が減算する(ここは読むだけ)
	if idx != SimStateScript._server_index(s):
		return 0
	if s.serve_tossed == 1:
		# 2段階サーブの2段目: トスの落下点へ歩き、落ち際に前トス打ちで
		# 確実にネットを越す(トス直後は自分のhit_cooldownが再打撃を防ぐ)
		var p = s.players[idx]
		var reach: int = cfg.player_reach
		var dx: int = s.ball_x - p.x
		var dy: int = s.ball_y - p.y
		var dy_n: int = dy * reach / cfg.player_reach_up
		var fwd: int = SimInput.IN_RIGHT if s.serving_team == 0 else SimInput.IN_LEFT
		var attack_serve: bool = prof_byte(prof, P_TIQ) >= 2 \
			and _attack_ok(s, idx, prof)
		if attack_serve and p.on_ground == 1 and _jump_will_meet(s, p, cfg, reach):
			var attack_land: int = _land_x_from(
				s.ball_x, s.ball_y, s.ball_vx, s.ball_vy, cfg,
				cfg.floor_y - cfg.player_reach_up / 2, 0)
			return _walk_to(p, attack_land, cfg.player_reach / 4) | SimInput.IN_JUMP
		if dx * dx + dy_n * dy_n <= reach * reach:
			if attack_serve and p.on_ground == 0:
				return SimInput.IN_ACTION | SimInput.IN_DOWN | fwd
			return SimInput.IN_ACTION | fwd
		var land: int = _land_x_from(s.ball_x, s.ball_y, s.ball_vx, s.ball_vy, cfg,
			cfg.floor_y - cfg.player_reach_up / 2, 0)
		return _walk_to(p, land, cfg.player_reach / 4)
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
	# 候補: [入力ビット, vx, vy]。後ろ/なし/前を敵陣の前面/中央/後面へ対応させる。
	var cands: Array = []
	var fwd_key: int = SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
	var back_key: int = SimInput.IN_LEFT if team == 0 else SimInput.IN_RIGHT
	if can_spike:
		var rvx: int = s.ball_vx * cfg.hit_inertia_num / cfg.hit_inertia_den
		var rvy: int = s.ball_vy * cfg.hit_inertia_num / cfg.hit_inertia_den
		for row in [[back_key, cfg.spike_steep_vy * cfg.spike_normal_pct / 100], [
			0, (cfg.spike_steep_vy + cfg.spike_vy) * cfg.spike_normal_pct / 200],
			[fwd_key, cfg.spike_vy * cfg.spike_normal_pct / 100]]:
			var spike_vy: int = row[1]
			var relative: int = 1 if row[0] == fwd_key else (-1 if row[0] == back_key else 0)
			var spike_vx: int = HitResolver.toss_aim_vx(
				s.ball_x, s.ball_y, spike_vy,
				HitResolver.air_target_x(team, relative * dir, cfg), cfg)
			cands.append([SimInput.IN_ACTION | SimInput.IN_DOWN | row[0],
				spike_vx - rvx, spike_vy - rvy, true])
	for key in [back_key, 0, fwd_key]:
		var toss_vy: int = -cfg.toss_fwd_vy
		var relative: int = 1 if key == fwd_key else (-1 if key == back_key else 0)
		var toss_vx: int = HitResolver.toss_aim_vx(s.ball_x, s.ball_y, toss_vy,
			HitResolver.air_target_x(team, relative * dir, cfg), cfg)
		cands.append([SimInput.IN_ACTION | key, toss_vx, toss_vy, false])
	var best_input: int = SimInput.IN_ACTION
	var best_score: int = -1
	var best_is_attack := false
	for c in cands:
		if best_is_attack and not c[3]:
			continue
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
			best_is_attack = c[3]
	return best_input

static func decide(s, idx: int, cfg) -> int:
	var team: int = idx / 2
	var p = s.players[idx]
	var prof: int = p.cpu
	var ab: int = prof_byte(prof, P_AB)
	var deadzone: int = cfg.player_reach / 2
	if s.phase == SimStateScript.PHASE_SERVE:
		var serve_in: int = _decide_serve(s, idx, cfg, prof)
		if p.on_ground == 0 and p.vy < 0:
			serve_in |= SimInput.IN_JUMP
		if serve_in != 0:
			return serve_in
		# サーブ準備中でも棒立ちしない: 受け手チームの味方CPUは相棒(人間)と反対側へ
		# 陣取り直す(相棒が前に出れば下がる)。サーブ側は照準/トスに専念=そのまま
		if team != s.serving_team:
			var mslot: int = 1 - idx % 2
			if _mate_is_human(s, team, mslot):
				var m = s.players[team * 2 + mslot]
				return _walk_to(p, _cover_target(p, m, idx, cfg), deadzone / 2)
		return 0
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
	if p.on_ground == 1 and _is_pre_attack_receiver(s, idx, cfg, team):
		# 予備動作へのコートカバーは打球後反応ではないため、frozenより先に処理する。
		return _walk_to(p, _pre_attack_cover_x(cfg, team), deadzone / 2)
	if frozen and on_own_side and p.on_ground == 1 and p.vx == 0 \
			and _plans_just_receive(s, idx, p, team, prof):
		var frozen_receive_reach: int = _hit_reach(
			p.char_id, cfg.player_reach, HitResolver.INTENT_GROUND_RECEIVE)
		var frozen_target: int = _receive_target_x(s, cfg, prof)
		var frozen_contact_ticks: int = _ticks_until_receive_at(
			s, p, cfg, frozen_receive_reach, frozen_target)
		var already_in_receive_position: bool = \
			absi(frozen_target - p.x) <= frozen_receive_reach
		if already_in_receive_position \
				and frozen_contact_ticks <= cfg.just_receive_window_ticks:
			# 反応遅延中も移動はしない。読めていた球への静止押下だけを許可する。
			# 期限切れラッチは1tick離し、次の押下エッジを作る。
			if p.receive_stance < 0:
				return 0
			return SimInput.IN_ACTION | SimInput.IN_DOWN
	if not frozen:
		# 帽子投げ: 敵球がネット際(帽子の滞在位置)へ落ちてくる軌道なら、
		# 溜め+飛行の後に滞在窓へボールが入るタイミングで投げる(妨害ギミックの活用)
		if (ab & AB_HAT) and p.stun == 0:
			var hat_in: int = _decide_hat(s, p, cfg, team)
			if hat_in != 0:
				return hat_in
		if not on_own_side:
			# 相手コートにボール=守備局面。ブロック能力があれば相手アタッカーの
			# ネット際ジャンプに反応してネットへ詰めて跳ぶ。それ以外は構え位置へ
			input = _decide_block(s, idx, p, cfg, team, ab, deadzone)
			if input == 0:
				input = _ready_position(s, idx, p, cfg, team, ab, deadzone)
		else:
			input = _decide_positioning(s, idx, p, cfg, team, prof, deadzone)
	# ヒット判定(simulation.gdの_resolve_hitと同じ楕円)。凍結中も腕は出る
	var dx: int = s.ball_x - p.x
	var hit_y: int = p.y
	if p.on_ground == 0:
		# simulationは入力決定後にプレイヤー移動、それからヒット判定を行う。
		# 上昇中のCPUはIN_JUMPを保持するため失速させず、同じ重力でyだけ先読みする。
		var hit_vy: int = p.vy
		var jump_height: int = PlayerMovement._jump_height_px(
			Chars.rank(p.char_id, Chars.Profile.ABILITY_JUMP))
		var jump_ticks: int = PlayerMovement._jump_ticks(hit_vy < 0)
		hit_vy += PlayerMovement._jump_gravity(
			jump_height, jump_ticks, hit_vy < 0)
		hit_y += hit_vy
	var dy: int = s.ball_y - hit_y
	var planned_hit_input: int = SimInput.IN_ACTION
	if p.on_ground == 1:
		planned_hit_input |= _ground_hit_keys(s, idx, cfg, team, prof)
	var base_dy_n: int = dy * cfg.player_reach / cfg.player_reach_up
	var base_d2: int = dx * dx + base_dy_n * base_dy_n
	var intent: Array[int] = HitResolver._classify_intent(
		p.on_ground, planned_hit_input, base_d2, cfg.player_reach, false)
	reach = _hit_reach(p.char_id, cfg.player_reach, intent[0])
	var dy_n: int = base_dy_n
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
			var receive_target: int = _receive_target_x(s, cfg, prof)
			var receive_aim_margin: int = reach * cfg.spike_sweet_pct / 200
			var timing_receive: bool = not frozen \
				and _plans_just_receive(s, idx, p, team, prof) \
				and _can_prepare_just_receive(
					s, p, cfg, reach, receive_target, receive_aim_margin)
			var timing_chord: bool = (input & SimInput.IN_ACTION) != 0 \
				and (input & SimInput.IN_DOWN) != 0
			if timing_receive and not timing_chord:
				# 精密計画中は位置取り側が作った5tick前エッジだけを採用する。
				input &= ~(SimInput.IN_ACTION | SimInput.IN_DOWN)
			else:
				input |= SimInput.IN_ACTION | _ground_hit_keys(s, idx, cfg, team, prof)
	if p.on_ground == 1 and (input & SimInput.IN_ACTION) \
			and _should_yield_hit_to_cpu_mate(s, idx, cfg, team, prof):
		input &= ~SimInput.IN_ACTION
	# 精密ジャンプは固定xで会合予測しているため、打撃入力を出すまでは空中横移動を止める。
	# 打撃時の横キーは配球方向なので保持する。
	if p.on_ground == 0 and not (input & SimInput.IN_ACTION) \
			and s.last_touch_team == team and (ab & AB_ATTACK) and (ab & AB_SWEET) \
			and _sweet_ok(s, idx, prof):
		input &= ~(SimInput.IN_LEFT | SimInput.IN_RIGHT)
	if (input & SimInput.IN_ACTION) and s.last_touch_team == team \
			and s.ball_attack_kind != SimStateScript.BALL_ATTACK_NONE:
		input &= ~SimInput.IN_ACTION
	# 可変ジャンプ対応: 打撃tickも含め、上昇中はジャンプキーを保持し続ける。
	# 空中では再ジャンプせず、打ち分けもIN_JUMPを読まない。
	if p.on_ground == 0 and p.vy < 0:
		input |= SimInput.IN_JUMP
	return input

# 地上ヒット時の入力選択。相手球は下レシーブ、自チーム球は横3トス。
static func _ground_hit_keys(s, idx: int, cfg, team: int, prof: int) -> int:
	if s.last_touch_team >= 0 and s.last_touch_team != team:
		return SimInput.IN_DOWN
	return _ground_shot_keys(s, idx, cfg, team, prof)

# 地上トスの方向選択(ニュートラル=自陣前方 / ネット方向=敵陣)
static func _ground_shot_keys(s, idx: int, cfg, team: int, prof: int) -> int:
	var mate = s.players[team * 2 + (1 - idx % 2)]
	var team_ab: int = prof_byte(prof, P_AB) | prof_byte(mate.cpu, P_AB)
	var touches_after: int = s.touches + 1 if s.last_touch_team == team else 1
	if (team_ab & AB_ATTACK) and touches_after < cfg.max_touches:
		return 0  # ニュートラルで自陣前方へ上げてアタックを呼ぶ
	return SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT

# 地上での位置取り(レシーブ/支援/ジャンプアタック)。frozenでない時のみ呼ばれる
static func _decide_positioning(s, idx: int, p, cfg, team: int, prof: int, deadzone: int) -> int:
	var ab: int = prof_byte(prof, P_AB)
	var reach: int = cfg.player_reach
	# 落下点予測(能力なしは現在のボールxを追う=最弱挙動)。
	var land_x: int = _receive_target_x(s, cfg, prof)
	var stance_deadzone: int = reach * cfg.spike_sweet_pct / 200
	var receive_reach: int = _hit_reach(
		p.char_id, reach, HitResolver.INTENT_GROUND_RECEIVE)
	# 精密待ちは、反応遅延後の残り時間で「到着→静止→5tick前押下」が
	# 実現できる時だけ選ぶ。間に合わない球は通常レシーブへ即フォールバック。
	var just_receive_plan: bool = _plans_just_receive(s, idx, p, team, prof) \
		and _can_prepare_just_receive(
			s, p, cfg, receive_reach, land_x, stance_deadzone)
	# 狙い誤差: 正確に計算した落下点をタッチ毎に1回だけ汚す(tick毎だと震える)。
	# 「読み違えたが本人は確信している」人間らしさが出る
	var aim_err: int = prof_byte(prof, P_AIM)
	if aim_err > 0 and not just_receive_plan:
		var half: int = reach * aim_err / 100
		if half > 0:
			land_x += _roll(SALT_AIM, s, idx) % (2 * half + 1) - half
	# ミス(惜しい失敗): 相手からの球に対しタッチ毎1抽選で「半歩深めにずれる」。
	# リーチの縁で拾えたり拾えなかったりする=人間くさい崩れ方になる
	var receiving: bool = s.last_touch_team >= 0 and s.last_touch_team != team
	var miss_roll: bool = receiving \
		and _roll(SALT_MISS, s, idx) % 256 < prof_byte(prof, P_MISS)
	if miss_roll and not just_receive_plan:
		land_x += -reach * 3 / 4 if team == 0 else reach * 3 / 4
	var mate_slot: int = 1 - idx % 2
	var mate = s.players[team * 2 + mate_slot]
	var controlled: int = s.controlled_l if team == 0 else s.controlled_r
	var mate_is_human: bool = _mate_is_human(s, team, mate_slot)
	# 役割分担: 落下点に近い方がレシーバー。人間の相方が同じ球を追えるなら譲る
	# (人間とのお見合い衝突は事故なのでCPU側が広めに退く)
	var receiver := true
	if ab & AB_ROLES:
		var my_d: int = absi(p.x - land_x)
		var mate_d: int = absi(mate.x - land_x)
		# 担当の相補分割(margin=リーチ1/4)。操作スロット側は境界を含めて広く取り、
		# 非操作スロット側は狭く譲る。互いの規則が正確に補集合なので
		# 「両者譲り」のデッドロックも「両者突進」のお見合いも構造的に起きない。
		# 人間が操作している時はこの margin が「人間優先の譲り」として働き、
		# 人間がボール方向へ移動中ならさらに広く譲る
		var margin: int = reach / 4
		if not mate_is_human:
			var role_target_x: int = _receive_target_x(s, cfg, prof)
			receiver = _is_cpu_mate_receiver(s, idx, team, role_target_x)
		elif idx % 2 == controlled:
			receiver = my_d <= mate_d + margin
		else:
			# 相方(操作キャラ)がボールへ移動中なら譲るが、止まっているなら
			# 自分が近い時は積極的に取りに行く(譲り過ぎの見送り事故の抑制)
			var mate_moving: bool = (mate.vx > 0 and land_x > mate.x) \
				or (mate.vx < 0 and land_x < mate.x)
			if mate_moving:
				receiver = mate_d > my_d + margin
			else:
				receiver = mate_d > my_d - margin
		# 目の前(リーチ内)のボールは誰の担当だろうと必ず拾いに行く
		if mate_is_human and not receiver and my_d <= reach and my_d < mate_d:
			receiver = true
	var input: int
	if receiver:
		if just_receive_plan:
			# 1) 現在位置から楕円リーチへ入れない間は落下点へ移動。
			if not _can_receive_from_stand_x(s, p, cfg, receive_reach, p.x):
				return _walk_to(p, land_x, stance_deadzone)
			# 2) 到着後は必ず入力を離して静止。移動中の押下ラッチを作らない。
			if p.vx != 0 or p.receive_stance < 0:
				return 0
			var receive_ticks: int = _ticks_until_receive_at(
				s, p, cfg, receive_reach, p.x)
			# 3) 接触予測の5tick前に押下エッジを作り、成立まで保持する。
			if p.receive_stance > 0 \
					or (p.receive_stance == 0 and receive_ticks <= 5):
				return SimInput.IN_ACTION | SimInput.IN_DOWN
			return 0
		# レシーバーは球を取る側=最短で落下点へ(スペーシングは掛けない)
		input = _walk_to(p, land_x, stance_deadzone if just_receive_plan else deadzone)
	elif mate_is_human:
		# 非レシーバー×相棒が人間: 相棒と反対側のホームへ回り、空きコートを埋める。
		# ボールを横切らないので張り付きが起きない(相棒が前へ出れば自分は下がる)
		input = _walk_to(p, _cover_target(p, mate, idx, cfg), deadzone / 2)
	else:
		var support_x: int
		if receiving:
			# CPU同士も相対位置から前衛/後衛の持ち場を毎tick選ぶ。
			return _walk_to(p, _cover_target(p, mate, idx, cfg), deadzone / 2)
		elif ab & AB_ATTACK:
			var off: int = FP.from_int(48)
			support_x = cfg.net_x - off if team == 0 else cfg.net_x + off
		else:
			support_x = _spawn_x(idx, cfg)
		input = _walk_to(p, support_x, deadzone)
	# ジャンプアタック: 自チームの上げ球へ会合できるなら跳ぶ。ミス抽選が出た
	# タッチでは跳ばない(=1拍遅れる、という惜しい失敗)。
	# サーブ打球が飛行中(serve_flight)は「上げ球」ではないので跳ばない
	# (味方がサーブに跳びついてトスし返す誤反応の抑止)
	var attacker_priority: bool = _is_rally_attacker(s, idx)
	if not attacker_priority:
		var attacker_mate_idx: int = team * 2 + mate_slot
		attacker_priority = _is_rally_attacker(s, attacker_mate_idx) \
			and not _jump_will_meet(s, mate, cfg, reach)
	var own_toss_for_human_mate: bool = s.last_touch_idx == idx \
		and s.last_touch_team == team \
		and s.ball_attack_kind == SimStateScript.BALL_ATTACK_NONE \
		and mate_is_human
	if (ab & AB_ATTACK) and _attack_ok(s, idx, prof) \
			and p.on_ground == 1 and p.stun == 0 and not miss_roll \
			and s.serve_flight == 0 \
			and s.last_touch_team == team and s.touches < cfg.max_touches \
			and attacker_priority and not own_toss_for_human_mate:
		var precision_jump: bool = (ab & AB_SWEET) and _sweet_ok(s, idx, prof)
		var precision_committed := false
		if precision_jump:
			var sweet_r: int = reach * cfg.spike_sweet_pct \
				* Chars.stat(p.char_id, "just_window") / (100 * 100)
			var plan: Array[int] = _sweet_jump_plan(s, p, cfg, sweet_r)
			# 実ジャンプの上昇時間内に離陸できる確実な計画は保持する。
			# 旧12tick上限は高いトスの離陸前に通常ジャンプへ落としていた。
			# 高いトスは頂点前から会合を予約する。上昇中だけでなく着地までの
			# ジャンプ弧内なら通常ジャンプへ落とさず、芯会合tickまで地上で待つ。
			var precision_horizon: int = PlayerMovement._jump_ticks(true) \
				+ PlayerMovement._jump_ticks(false)
			if plan[0] >= 0 and plan[0] <= precision_horizon:
				precision_committed = true
				input = _walk_to(p, plan[1], sweet_r / 2)
				if plan[0] == 0:
					# 未来の芯接触tickから逆算した離陸tick。ここで初めて跳ぶ。
					input &= ~(SimInput.IN_LEFT | SimInput.IN_RIGHT)
					input |= SimInput.IN_JUMP
		if not precision_committed and _jump_will_meet(s, p, cfg, reach):
			# 芯会合を作れない球は従来の通常ジャンプへ即フォールバック。
			input &= ~(SimInput.IN_LEFT | SimInput.IN_RIGHT)
			input |= SimInput.IN_JUMP
	return input

# 相手コートにボールがある間の構え。棒立ちのスポーン戻りをやめ、
# 相方が操作キャラなら前後の役割で生きた待機をする:
# 前衛担当(相方が後ろ)=ネット際に張り付いてブロック・速攻に備える、
# 後衛担当(相方が前)=ボールの動きを鏡写しに追って落下に先回りする(人間っぽさの核)
static func _ready_position(s, idx: int, p, cfg, team: int, ab: int, deadzone: int) -> int:
	var mate_slot: int = 1 - idx % 2
	if not _mate_is_human(s, team, mate_slot):
		return _walk_to(p, _spawn_x(idx, cfg), deadzone)
	var mate = s.players[team * 2 + mate_slot]
	var mate_is_front: bool = absi(mate.x - cfg.net_x) < cfg.court_width / 4
	if not mate_is_front and (ab & AB_BLOCK):
		# 前衛担当: ネット際で待つ(ブロックの初動が1歩で済む)
		var post: int = cfg.net_x - FP.from_int(36) if team == 0 \
			else cfg.net_x + FP.from_int(36)
		return _walk_to(p, post, deadzone)
	# 後衛担当(または非ブロック型): 相手コートのボールを鏡写しで追う
	var mirror: int = 2 * cfg.net_x - s.ball_x
	var zmin: int
	var zmax: int
	if team == 0:
		zmin = FP.from_int(30)
		zmax = cfg.net_x - FP.from_int(40)
	else:
		zmin = cfg.net_x + FP.from_int(40)
		zmax = cfg.court_width - FP.from_int(30)
	# 鏡写しで追いつつ、相棒(人間)とは最低sep離す(張り付き防止)
	var mtx: int = clampi(mirror, zmin, zmax)
	var sep: int = cfg.player_reach * 3 / 2
	if absi(mtx - mate.x) < sep:
		mtx = mate.x + sep if mtx >= mate.x else mate.x - sep
	mtx = clampi(mtx, zmin, zmax)
	return _walk_to(p, mtx, deadzone / 2)

# ブロック迎撃: 相手アタッカーがネット際で空中+ボールが打点圏なら、
# 自陣ネット際へ走り、着いていれば跳ぶ(体が壁になるのはsimulation._ball_vs_block)。
# 0を返したら通常の持ち場戻りにフォールバック
static func _decide_block(
		s, idx: int, p, cfg, team: int, ab: int, deadzone: int) -> int:
	if not (ab & AB_BLOCK) or p.stun > 0:
		return 0
	var reach: int = cfg.player_reach
	for j in 2:
		var o = s.players[(1 - team) * 2 + j]
		if o.on_ground == 1:
			continue
		if absi(o.x - cfg.net_x) > FP.from_int(120):
			continue
		var bdx: int = s.ball_x - o.x
		var bdy: int = s.ball_y - o.y
		if bdx * bdx + bdy * bdy > reach * reach * 4:
			continue  # ボールがアタッカーの打点圏にない=まだ跳ぶ局面ではない
		var post: int = cfg.net_x - FP.from_int(20) if team == 0 \
			else cfg.net_x + FP.from_int(20)
		if absi(p.x - post) <= FP.from_int(24):
			var blocker_priority: bool = _is_rally_blocker(s, idx)
			if not blocker_priority:
				var mate_idx: int = team * 2 + (1 - idx % 2)
				blocker_priority = _is_rally_blocker(s, mate_idx) \
					and not _jump_will_meet(
						s, s.players[mate_idx], cfg, reach)
			if not blocker_priority:
				return 0
			if p.on_ground == 1:
				return SimInput.IN_JUMP | SimInput.IN_UP
			return SimInput.IN_ACTION | SimInput.IN_UP
		return _walk_to(p, post, deadzone / 2)
	return 0

# 帽子投げの判断: 敵が敵陣で攻撃を組み立てている間にネット面へ帽子を先置きし、
# ネット際の通り道(速攻・フェイント・低い弾道)を滞在90tickで塞ぐ。
# 投げると溜め30tick硬直するため、「ボールがすぐ自陣へ来ない」局面だけ投げる。
# 0を返したら投げない
# 帽子エンティティが場に出ているか(エンティティ枠の線形走査、決定論)
static func _cap_exists(s) -> bool:
	for e in s.entities:
		if e.kind == HAT_KIND:
			return true
	return false

static func _decide_hat(s, p, cfg, team: int) -> int:
	# can(キャラ定義) AND wants(プロファイルAB_HAT)の二段ゲート。canはここで見る
	if not Chars.has_ability(p.char_id, Chars.CA_HAT):
		return 0
	if p.has_hat != 1 or p.throw != 0 or _cap_exists(s) or p.on_ground != 1 \
			or p.burnout_ticks > 0:
		return 0
	# スト6式使い切り: CPUも残量1以上なら最後の一手として発動できる。
	if p.drive_gauge <= 0:
		return 0
	# サーブ打球の飛行中は場が動く前=無駄撃ちになるので投げない
	if s.serve_flight != 0:
		return 0
	# 敵がタッチした球でなければ「組み立て中」ではない
	if s.last_touch_team != 1 - team:
		return 0
	# ボールが敵陣にあり、かつそのまま敵陣に落ちる(=敵がもう1タッチしてから
	# 攻撃が来る)ことを確認。自陣へ向かう球へ投げると溜め硬直30tickで受けが崩れる
	var on_enemy_side: bool = (s.ball_x > cfg.net_x) == (team == 0)
	if not on_enemy_side:
		return 0
	var land_x: int = _land_x_from(s.ball_x, s.ball_y, s.ball_vx, s.ball_vy, cfg,
		cfg.floor_y - cfg.ball_radius, 1)
	var lands_enemy: bool = (land_x > cfg.net_x) == (team == 0)
	if not lands_enemy:
		return 0
	# 帽子は手から最大72px(3px/tick x 24tick)しか飛ばない。ネット面に届かない
	# 位置から投げても妨害にならないので、届く時だけ投げる
	var net_face: int = cfg.net_x - cfg.net_half_w if team == 0 \
		else cfg.net_x + cfg.net_half_w
	if absi(p.x - net_face) > FP.from_int(HAT_FLY_PX * HAT_OUT_TICKS):
		return 0
	# ネット方向キーを添えて投げ=帽子が確実に前(ネット)へ飛ぶ
	var fwd: int = SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
	return SimInput.IN_ABILITY1 | fwd

static func _sweet_ok(s, idx: int, prof: int) -> bool:
	# 最強(TIQ3)は精密行動を確実に選ぶ。確率ゲートで一試合すべて通常化するのを防ぐ。
	if prof_byte(prof, P_TIQ) >= 3:
		return true
	return _roll(SALT_SWEET, s, idx) % 256 < prof_byte(prof, P_SWEET)

static func _attack_ok(s, idx: int, prof: int) -> bool:
	if not (prof_byte(prof, P_AB) & AB_ATTACK):
		return false
	var tiq: int = prof_byte(prof, P_TIQ)
	if tiq >= 3:
		return true
	return _roll(SALT_ATTACK, s, idx) % 256 < tiq * 64

static func _plans_just_receive(s, idx: int, p, team: int, prof: int) -> bool:
	var ab: int = prof_byte(prof, P_AB)
	if not (ab & AB_SWEET) or p.on_ground == 0 or p.burnout_ticks > 0:
		return false
	if s.last_touch_team < 0 or s.last_touch_team == team \
			or s.ball_attack_kind == SimStateScript.BALL_ATTACK_NONE:
		return false
	return _sweet_ok(s, idx, prof)

static func _can_receive_from_stand_x(
		s, p, cfg, receive_reach: int, stand_x: int) -> bool:
	return _ticks_until_receive_at(s, p, cfg, receive_reach, stand_x) < 181

static func _ticks_until_receive_at(s, p, cfg, receive_reach: int,
		target_x: int) -> int:
	var x: int = s.ball_x
	var y: int = s.ball_y
	var vx: int = s.ball_vx
	var vy: int = s.ball_vy
	for tick in 180:
		var dx: int = x - target_x
		var dy_n: int = (y - p.y) * cfg.player_reach / cfg.player_reach_up
		if dx * dx + dy_n * dy_n <= receive_reach * receive_reach:
			return tick
		vy += cfg.gravity
		x += vx
		y += vy
		if x < cfg.ball_radius:
			x = cfg.ball_radius + (cfg.ball_radius - x)
			vx = BallPhysics.wall_reflect_vx(vx, cfg)
		elif x > cfg.court_width - cfg.ball_radius:
			var right: int = cfg.court_width - cfg.ball_radius
			x = right - (x - right)
			vx = BallPhysics.wall_reflect_vx(vx, cfg)
		# 高速の下降球は1tickでリーチ境界から床まで進む。
		# 床breakより先に移動後の最後の位置を検査しないと、落下点上でも181になる。
		dx = x - target_x
		dy_n = (y - p.y) * cfg.player_reach / cfg.player_reach_up
		if dx * dx + dy_n * dy_n <= receive_reach * receive_reach:
			return tick + 1
		if y >= cfg.floor_y - cfg.ball_radius:
			break
	return 181

static func _should_use_flame(s, idx: int, p, cfg, prof: int) -> bool:
	var ab: int = prof_byte(prof, P_AB)
	if not (ab & AB_ATTACK) or not (ab & AB_SWEET):
		return false
	if not Chars.has_super(p.char_id, Chars.SUPER_FLAME_ATTACK):
		return false
	var flame: Dictionary = Chars.super_def(Chars.SUPER_FLAME_ATTACK)
	if p.drive_gauge < int(flame.gauge_cost) or p.burnout_ticks > 0:
		return false
	if p.on_ground == 1 or p.y >= cfg.net_top_y:
		return false
	return prof_byte(prof, P_TIQ) >= 3 \
		or _roll(SALT_SUPER, s, idx) % 256 < prof_byte(prof, P_SWEET)

# 空中ヒットの打ち分け。ネット遠方のスパイクは自陣に落ちて自滅するため打たない
static func _decide_air_hit(s, idx: int, p, cfg, team: int, prof: int, d2: int, dy: int) -> int:
	var ab: int = prof_byte(prof, P_AB)
	var can_spike: bool = _attack_ok(s, idx, prof) \
		and absi(p.x - cfg.net_x) < FP.from_int(120)
	if can_spike and _should_use_flame(s, idx, p, cfg, prof):
		return SimInput.IN_ABILITY1 | SimInput.IN_DOWN
	var sweet_r: int = cfg.player_reach * cfg.spike_sweet_pct \
		* Chars.stat(p.char_id, "just_window") / (100 * 100)
	var use_sweet: bool = (ab & AB_SWEET) and _sweet_ok(s, idx, prof)
	# 芯へ入る見込みが残る時だけ待つ。見込みが消えた球は通常打撃して強さを保つ。
	if use_sweet and d2 > sweet_r * sweet_r \
			and _air_will_meet_sweet(s, p, cfg, sweet_r):
		return 0
	if prof_byte(prof, P_TIQ) >= 2:
		return _pick_air_shot(s, p, cfg, team, can_spike)
	var input: int = SimInput.IN_ACTION
	if can_spike:
		# 配球IQなしは下+前で敵陣後面へのアタック固定。
		input |= SimInput.IN_DOWN
		input |= SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
	return input
