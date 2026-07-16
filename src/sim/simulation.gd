# シミュレーション本体。1tick進める純粋ロジック
# int演算のみ。ここにfloatを書いたらSyncTest以前にレビューで即アウト
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

const IN_LEFT := SimInput.IN_LEFT
const IN_RIGHT := SimInput.IN_RIGHT
const IN_JUMP := SimInput.IN_JUMP
const IN_ACTION := SimInput.IN_ACTION
const IN_SWITCH := SimInput.IN_SWITCH
const IN_UP := SimInput.IN_UP
const IN_DOWN := SimInput.IN_DOWN
const IN_HAT_THROW := SimInput.IN_HAT_THROW

# サーブトス照準。左右キー=着弾距離(0..AIM_MAXの目盛りをserve_toss_rangeへ線形対応)、
# 上下キー=トスの高さ%(POW_MIN..POW_MAX)。距離と高さは完全に独立
# (山なりを目の前に、低く速いのを遠くに、どの組合せも可)
const AIM_MAX := 60
const POW_MIN := 60   # トス高さの下限(%)
const POW_MAX := 130  # トス高さの上限(%)
const BRAKE_TICKS := 8  # 急ブレーキ(スキッド)で旧方向へ滑る長さ(tick)
const SKID_MIN_RUN := 12  # この連続走行tick以上でのみ反転スキッドが出る(細かい追尾は滑らない)
const RUN_CAP := 40       # 走行継続カウンタの上限
const RUN_DECAY := 3      # ニュートラル時の走行カウンタ減衰/tick(離して押し直す反転の猶予)
# 帽子投げ(お邪魔ギミック)。距離・速度はpx/tick、時間はtick
const CAP_THROW_PX := 3    # 前方への飛行速度(px/tick)
const CAP_OUT_TICKS := 24  # 前方へ飛ぶ時間(=飛距離)
const CAP_HOVER_TICKS := 90  # その場で滞在する時間
const CAP_RETURN_PX := 8   # 帰還速度(シュッと速い)
const CAP_RADIUS_PX := 12  # ボールとの当たり判定半径
const CAP_CATCH_PX := 10   # 所有者に届いたと見なす距離
const CAP_HEAD_UP_PX := 20 # キャッチ先の頭の高さ(足元yからの上オフセット)
const CAP_HAND_UP_PX := 6  # 投げ元の手の高さ(頭より低い=手から放つ)
const CAP_HAND_FWD_PX := 9 # 投げ元の手の前方オフセット(向いてる方向へ)
const CAP_BOUNCE_PX := 4   # 反発の最低速度
const THROW_TICKS := 30    # 帽子投げの溜め(windup)時間。この間は硬直し空中でも浮く
const HAT_GUARD_COST := 25 # 帽子投げ1回の耐久(スタミナ)消費=25%。足りずに投げるとスタン
const FLINCH_TICKS := 24   # ジャストアタック被弾のしりもち(butt-drop)時間
const KNOCKBACK_PX := 4    # しりもちで後ろへ滑る初速(px/tick)
const HIP_HOVER_TICKS := 36  # ヒップアタックの空中静止(回転)時間
const HIP_DROP_PX := 12    # ヒップアタック急降下の速度(px/tick)
const CLING_SLIDE_PX := 1  # 壁張り付きのずるずる降下速度(px/tick)

static func team_of(i: int) -> int:
	return i / 2

static func _dir_of_team(team: int) -> int:
	return 1 if team == 0 else -1

# 公開API: チーム単位入力(人間2系統)から各プレイヤー入力を組み立てて1tick進める
# CPU相方の入力はsim_cpu.gdが決定論的に生成する
static func tick(state, team_inputs: Array[int], cfg) -> void:
	var in_l: int = team_inputs[0] if team_inputs.size() > 0 else 0
	var in_r: int = team_inputs[1] if team_inputs.size() > 1 else 0
	_handle_switch(state, in_l, in_r)
	var per_player: Array[int] = [0, 0, 0, 0]
	for team in 2:
		var human: int = in_l if team == 0 else in_r
		var controlled: int = state.controlled_l if team == 0 else state.controlled_r
		for slot in 2:
			var idx: int = team * 2 + slot
			if slot == controlled:
				per_player[idx] = human & ~IN_SWITCH
			else:
				per_player[idx] = _cpu_input(state, idx, cfg)
	step(state, per_player, cfg)

static func _handle_switch(state, in_l: int, in_r: int) -> void:
	var press_l: int = 1 if (in_l & IN_SWITCH) else 0
	if press_l == 1 and state.switch_latch_l == 0:
		state.controlled_l = 1 - state.controlled_l
	state.switch_latch_l = press_l
	var press_r: int = 1 if (in_r & IN_SWITCH) else 0
	if press_r == 1 and state.switch_latch_r == 0:
		state.controlled_r = 1 - state.controlled_r
	state.switch_latch_r = press_r

static func _cpu_input(state, idx: int, cfg) -> int:
	return SimCpu.decide(state, idx, cfg)

static func step(state, inputs: Array[int], cfg) -> void:
	# matchの定数パターンは識別子束縛の罠があるためif/elifで書く
	state.tick += 1
	# ヒットストップ: パワーボール成立や気絶の瞬間、数tick世界が止まる(重さの演出)。
	# tickは進める(ネットコードの入力消費と1対1を保つ)が物理・入力は凍結
	if state.hit_freeze > 0:
		state.hit_freeze -= 1
		return
	# スローモーション: ジャストスマッシュ成立後、世界を1/3速で流す(スマブラの決めの間)。
	# tickは進めて入力を1:1で消費するが、3tickに1回だけ物理を進める=決定論・ロールバック安全
	if state.slow_ticks > 0:
		state.slow_ticks -= 1
		if state.slow_ticks % 3 != 0:
			return
	if state.phase == SimStateScript.PHASE_SERVE:
		if state.serve_tossed == 0:
			state.timer -= 1
			# 2段階サーブの1段目=照準(バブルボブル式): 横キーで角度、上下キーで
			# トスの高さ(60..130%)。各1刻み/tickでスイープ。
			# サーバーはトスまで移動もジャンプもしない(照準に専念)
			var srv_idx: int = _server_index(state)
			var serve_inputs: Array[int] = inputs.duplicate()
			if srv_idx < serve_inputs.size():
				var raw: int = serve_inputs[srv_idx]
				var to_net: int = IN_RIGHT if state.serving_team == 0 else IN_LEFT
				var away: int = IN_LEFT if state.serving_team == 0 else IN_RIGHT
				if raw & to_net:
					state.serve_aim = mini(state.serve_aim + 1, AIM_MAX)
				elif raw & away:
					state.serve_aim = maxi(state.serve_aim - 1, 0)
				if raw & IN_UP:
					state.serve_pow = mini(state.serve_pow + 1, POW_MAX)
				elif raw & IN_DOWN:
					state.serve_pow = maxi(state.serve_pow - 1, POW_MIN)
				serve_inputs[srv_idx] &= ~(IN_JUMP | IN_LEFT | IN_RIGHT)
			_step_players_and_hits(state, serve_inputs, cfg)
			# サーバーは外線(サービスライン)を越えられない(トスまで)。線の後ろでは動ける。
			# 下限は壁からball_radius: 壁際まで下がると保持ボールが壁反射圏に入り、
			# 前サーブが反転して自陣に落ちる自滅死角ができるため(レビュー指摘)
			var srv = state.players[_server_index(state)]
			var line: int = _serve_x(state, cfg)
			if state.serving_team == 0:
				srv.x = clampi(srv.x, cfg.ball_radius, line)
			else:
				srv.x = clampi(srv.x, line, cfg.court_width - cfg.ball_radius)
			_hold_ball_on_server(state, cfg)
			_try_serve(state, inputs, cfg)
		else:
			# 2段目=トス済み・打撃待ち。サーバーは移動・ジャンプ解禁され、通常の
			# ヒットルールで打つ(地上前トス=安全サーブ/走り込みジャンプ+下=アタック)。
			# 打った瞬間に_resolve_hitがRALLYへ遷移させる
			_step_players_and_hits(state, inputs, cfg)
			_step_ball(state, cfg)
			if state.phase == SimStateScript.PHASE_SERVE \
					and state.ball_y >= cfg.floor_y - cfg.ball_radius:
				# 打ち損ねてトスが床に落ちた: 失点にせず構えからやり直す(再トス)。
				# サーバーごと白線へ戻す(前へ走り込んだ後でも仕切り直しが明快)
				state.serve_tossed = 0
				state.ball_vx = 0
				state.ball_vy = 0
				state.timer = cfg.serve_delay_ticks
				var srv2 = state.players[_server_index(state)]
				srv2.x = _serve_x(state, cfg)
				srv2.y = cfg.floor_y
				srv2.vy = 0
				srv2.on_ground = 1
				_hold_ball_on_server(state, cfg)
	elif state.phase == SimStateScript.PHASE_RALLY:
		_step_players_and_hits(state, inputs, cfg)
		_step_ball(state, cfg)
		_check_floor_point(state, cfg)
	elif state.phase == SimStateScript.PHASE_POINT_PAUSE:
		state.timer -= 1
		# ポーズ中も操作は生かす(ヒットは_try_hitのフェーズ判定で無効)
		_step_players_and_hits(state, inputs, cfg)
		_step_ball_loose(state, cfg)
		if state.timer <= 0:
			reset_rally(state, cfg, state.serving_team)
	elif state.phase == SimStateScript.PHASE_GAME_OVER:
		# 勝敗確定後もキャラの移動・ジャンプは生かす
		_step_players_and_hits(state, inputs, cfg)
		_step_ball_loose(state, cfg)

static func _step_players_and_hits(state, inputs: Array[int], cfg) -> void:
	for i in state.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		_step_player(state.players[i], input, cfg, team_of(i))
	_resolve_hit(state, inputs, cfg)
	_update_hat(state, inputs, cfg)

# 帽子投げ(お邪魔ギミック): Dキーで前方へ投げ、飛行→滞在→高速帰還→キャッチ。
# 飛んでる間ボールと当たり判定を持ち、触れると弾く。一度に1個だけ
static func _update_hat(state, inputs: Array[int], cfg) -> void:
	# 溜め(windup)管理: D入力で溜め開始→溜め終了フレームで発射(帽子はそれまで頭上)。
	# _step_playerが溜め中の入力を封じる(投げは強いがリスク=硬直)
	for i in state.players.size():
		var inp: int = inputs[i] if i < inputs.size() else 0
		var p = state.players[i]
		if p.throw == 0 and p.has_hat == 1 and (inp & IN_HAT_THROW) \
				and p.stun == 0 and p.flinch == 0 and state.cap_phase == 0:
			if p.guard >= HAT_GUARD_COST:
				p.guard -= HAT_GUARD_COST  # 帽子はスタミナを消費
				p.throw = THROW_TICKS
			else:
				# スタミナ切れで無理に投げるとスタン→全快で復帰(帽子は出ない)
				p.stun = cfg.stun_ticks
				p.guard = p.guard_max
				state.hit_freeze = maxi(state.hit_freeze, 6)
		if p.throw > 0:
			p.throw -= 1
			if p.throw == 0 and p.has_hat == 1 and state.cap_phase == 0:
				var net_dir: int = 1 if team_of(i) == 0 else -1
				var dir: int = p.face if p.face != 0 else net_dir
				state.cap_phase = 1
				state.cap_owner = i
				# 頭ではなく手から放つ: 向いてる方向へ少し前、高さは手のあたり
				state.cap_x = p.x + dir * FP.from_int(CAP_HAND_FWD_PX)
				state.cap_y = p.y - FP.from_int(CAP_HAND_UP_PX)
				state.cap_vx = dir * FP.from_int(CAP_THROW_PX)
				state.cap_vy = 0
				state.cap_timer = CAP_OUT_TICKS
				p.has_hat = 0
	if state.cap_phase == 0:
		return
	if state.cap_phase == 1:  # 飛行(前方へ)
		state.cap_x += state.cap_vx
		# ネットは越えられない: ネット面に達したら即帰還(自陣ネット際での妨害になる)
		var owner_team: int = team_of(state.cap_owner)
		var hit_net: bool = false
		if owner_team == 0 and state.cap_x >= cfg.net_x - cfg.net_half_w:
			state.cap_x = cfg.net_x - cfg.net_half_w
			hit_net = true
		elif owner_team == 1 and state.cap_x <= cfg.net_x + cfg.net_half_w:
			state.cap_x = cfg.net_x + cfg.net_half_w
			hit_net = true
		state.cap_timer -= 1
		if hit_net or state.cap_timer <= 0:
			state.cap_phase = 2
			state.cap_timer = CAP_HOVER_TICKS
			state.cap_vx = 0
	elif state.cap_phase == 2:  # 滞在(その場で回転)
		state.cap_timer -= 1
		if state.cap_timer <= 0:
			state.cap_phase = 3
	elif state.cap_phase == 3:  # 帰還(所有者の頭へ高速)
		var owner = state.players[state.cap_owner]
		var tx: int = owner.x
		var ty: int = owner.y - FP.from_int(CAP_HEAD_UP_PX)
		var rv: int = FP.from_int(CAP_RETURN_PX)
		state.cap_x += clampi(tx - state.cap_x, -rv, rv)
		state.cap_y += clampi(ty - state.cap_y, -rv, rv)
		if absi(tx - state.cap_x) <= FP.from_int(CAP_CATCH_PX) \
				and absi(ty - state.cap_y) <= FP.from_int(CAP_CATCH_PX):
			state.cap_phase = 0  # キャッチ
			owner.has_hat = 1
			return
	# ボール当たり判定(飛行/滞在/帰還いずれも): 触れたら弾く
	var r: int = FP.from_int(CAP_RADIUS_PX) + cfg.ball_radius
	var dx: int = state.ball_x - state.cap_x
	var dy: int = state.ball_y - state.cap_y
	if absi(dx) < r and absi(dy) < r:
		var bounce: int = FP.from_int(CAP_BOUNCE_PX)
		if absi(dx) >= absi(dy):
			var sx: int = signi(dx) if dx != 0 else 1
			state.ball_vx = sx * maxi(absi(state.ball_vx), bounce)
		else:
			var sy: int = signi(dy) if dy != 0 else -1
			state.ball_vy = sy * maxi(absi(state.ball_vy), bounce)

static func reset_rally(s, cfg, serving_team: int) -> void:
	# ラリーの再開。非サーバーはワープさせない(気持ちよさ優先、ユーザー決定)。
	# 定位置への帰還はポーズ中のCPU歩行が担い、人間は自由に立ち回れる。
	# サーバーだけは原作準拠で白線の後ろに着いてサーブする(位置固定)
	s.phase = SimStateScript.PHASE_SERVE
	s.serving_team = serving_team
	s.touches = 0
	s.last_touch_team = -1
	s.timer = cfg.serve_delay_ticks
	s.ball_vx = 0
	s.ball_vy = 0
	s.ball_spin = 0
	s.ball_power = 0
	s.serve_aim = 25  # 既定は打ちやすい前方トスの角度
	s.serve_pow = 100
	s.serve_tossed = 0
	s.serve_flight = 0
	s.hit_freeze = 0
	s.slow_ticks = 0
	# スタンはラリー終了で解除(新ラリーを硬直で始めさせない)。演出残時間も同様
	for i in s.players.size():
		var p = s.players[i]
		p.stun = 0
		p.dive = 0
		p.brake = 0
		p.run = 0
		p.throw = 0
		p.flinch = 0
		p.hip = 0
		p.cling = 0
		# 投げっぱなしの帽子はラリー再開で戻す(帽子を持たないキャラは持たないまま)
		p.has_hat = HAS_HAT_START[i]
	# 飛んでる帽子も消す
	s.cap_phase = 0
	s.cap_vx = 0
	s.cap_vy = 0
	s.cap_timer = 0
	var srv = s.players[serving_team * 2]
	srv.x = _serve_x(s, cfg)
	srv.y = cfg.floor_y
	srv.vx = 0
	srv.vy = 0
	srv.on_ground = 1
	srv.hit_cooldown = 0
	_hold_ball_on_server(s, cfg)

# 帽子の初期所持(キャラ固有の技)。帽子投げ/ヒップアタック(帽子前提)はマリオ専用。
# slot割当は表示層と同じ: 0=パンダ, 1=マリオ, 2=キツネ, 3=カエル。
# キャラ実装(M4)でロスターデータ駆動にする(設計検討中、実装は保留)
const HAS_HAT_START: Array[int] = [0, 1, 0, 0]

static func reset_match(s, cfg, serving_team: int) -> void:
	# 試合開始時のみキャラを初期配置に置く
	var back: int = FP.from_int(cfg.spawn_back_px)
	var front: int = FP.from_int(cfg.spawn_front_px)
	var positions: Array[int] = [back, front, cfg.court_width - back, cfg.court_width - front]
	for i in s.players.size():
		var p = s.players[i]
		p.x = positions[i]
		p.y = cfg.floor_y
		p.vx = 0
		p.vy = 0
		p.on_ground = 1
		p.hit_cooldown = 0
		p.has_hat = HAS_HAT_START[i]
	reset_rally(s, cfg, serving_team)

static func _server_index(s) -> int:
	return s.serving_team * 2

static func _serve_x(s, cfg) -> int:
	# サービスライン(コート端寄りの白線)。サーバーはこの位置からサーブする
	if s.serving_team == 0:
		return cfg.serve_line
	return cfg.court_width - cfg.serve_line

static func _hold_ball_on_server(s, cfg) -> void:
	var server = s.players[_server_index(s)]
	s.ball_x = server.x
	s.ball_y = server.y - cfg.serve_hold_height

static func _try_serve(s, inputs: Array[int], cfg) -> void:
	var idx: int = _server_index(s)
	var input: int = inputs[idx] if idx < inputs.size() else 0
	if not (input & IN_ACTION):
		return
	# 2段階サーブの1段目=セルフトス(本物のバレー式)。距離と高さは完全に独立:
	# 縦: serve_toss_upに高さ%(60..130)を掛けるだけ(高いトスほど滞空が長く
	#     走り込みジャンプアタックの時間が作れる)。
	# 横: 照準値が決めるのは「着弾距離」(0..serve_toss_rangeを線形)。横速度は
	#     滞空時間から逆算するので、どんな高さ・距離でも着弾は自陣内=
	#     トス単体では絶対にネットを越えない。山なりを前面へ、も自由。
	#     トスはタッチ数に数えない
	var net_dir: int = _dir_of_team(s.serving_team)
	var aim: int = clampi(s.serve_aim, 0, AIM_MAX)
	var pow_pct: int = clampi(s.serve_pow, POW_MIN, POW_MAX)
	var vy_mag: int = cfg.serve_toss_up * pow_pct / 100
	var flight: int = maxi(2 * vy_mag / cfg.gravity, 1)
	var dx: int = cfg.serve_toss_range * aim / AIM_MAX
	s.ball_vx = net_dir * (dx / flight)
	s.ball_vy = -vy_mag
	s.players[idx].hit_cooldown = cfg.hit_cooldown_ticks
	s.last_hit_tick = s.tick
	s.serve_tossed = 1

static func _check_floor_point(s, cfg) -> void:
	# 同一tick内でタッチ超過などが先に得点しフェーズが変わっていたら加点しない(1ラリー2点の禁止)
	if s.phase != SimStateScript.PHASE_RALLY:
		return
	if s.ball_y < cfg.floor_y - cfg.ball_radius:
		return
	# 着地したらパワーボールを解除=通常ボールに戻す(レシーブ時と同様)。
	# ポーズ中のバウンドで熱色や残像トレイルが残らないようにする
	s.ball_power = 0
	var landed_left: bool = s.ball_x < cfg.net_x
	_award_point(s, 1 if landed_left else 0, cfg)

static func _award_point(s, team: int, cfg) -> void:
	if team == 0:
		s.score_l += 1
	else:
		s.score_r += 1
	s.serving_team = team
	var lead: int = s.score_l - s.score_r if team == 0 else s.score_r - s.score_l
	var score: int = s.score_l if team == 0 else s.score_r
	var won: bool = score >= cfg.points_to_win and (not cfg.deuce or lead >= 2)
	if won:
		s.winner = team
		s.phase = SimStateScript.PHASE_GAME_OVER
	else:
		s.phase = SimStateScript.PHASE_POINT_PAUSE
		s.timer = cfg.point_pause_ticks

# 同一tickのヒットは最大1回。リーチ内の候補から最も近い1人を選ぶ。
# 旧実装のインデックス後勝ちはネット際で右チームが常に競り勝ち、
# 負けた側も硬直だけ食らう不公平があった。
# 同距離ならボールがある側のチームを優先、それも同点ならインデックス小。全て整数比較で決定論
static func _resolve_hit(s, inputs: Array[int], cfg) -> void:
	# サーブの2段目(トス済み)はサーバー本人のみ打てる。それ以外のSERVE中は不可
	var serve_strike: bool = s.phase == SimStateScript.PHASE_SERVE and s.serve_tossed == 1
	if s.phase != SimStateScript.PHASE_RALLY and not serve_strike:
		return
	# サーブは一発で相手コートへ入れる(本物のバレー準拠)。打たれたサーブが
	# ネットを越えるまでは誰も触れない(味方の中継も、サーバー自身の2度打ちも不可)。
	# 越えずに自陣へ落ちればサーブミス=床判定で相手の得点になる
	if s.serve_flight == 1:
		return
	var reach: int = cfg.player_reach
	var side_team: int = 0 if s.ball_x < cfg.net_x else 1
	var best_i: int = -1
	var best_d2: int = 0
	for i in s.players.size():
		if serve_strike and i != _server_index(s):
			continue
		var input: int = inputs[i] if i < inputs.size() else 0
		if not (input & IN_ACTION):
			continue
		var p = s.players[i]
		if p.hit_cooldown > 0 or p.stun > 0:
			continue
		var dx: int = s.ball_x - p.x
		var dy: int = s.ball_y - p.y
		# 楕円判定: 横はreach、縦はreach_up(頭のかなり上で打てる違和感の抑制)。
		# dyをreach/reach_up倍して円判定に正規化する。
		# オーバーフロー検討: dx最大640<<16≈4.2e7、二乗≈1.8e15 < int64上限9.2e18で安全
		var dy_n: int = dy * reach / cfg.player_reach_up
		var d2: int = dx * dx + dy_n * dy_n
		if d2 > reach * reach:
			continue
		var better: bool = best_i < 0 or d2 < best_d2
		if not better and d2 == best_d2:
			better = team_of(i) == side_team and team_of(best_i) != side_team
		if better:
			best_i = i
			best_d2 = d2
	if best_i >= 0:
		var winner_input: int = inputs[best_i] if best_i < inputs.size() else 0
		_apply_hit(s, best_i, cfg, winner_input, best_d2)
		if serve_strike:
			# サーブの打撃が成立した瞬間にラリー開始。ネットを越えるまでは
			# serve_flightを立て、味方CPUのジャンプアタック誤反応を抑える
			s.phase = SimStateScript.PHASE_RALLY
			s.serve_tossed = 0
			s.serve_flight = 1

static func _apply_hit(s, i: int, cfg, input: int, d2: int = -1) -> void:
	var p = s.players[i]
	var team: int = team_of(i)
	var dir: int = _dir_of_team(team)
	# 耐久力(ガード)システム: パワーボール(ジャストミート由来)を受けると
	# 耐久力が削れる。ただしスイートスポットで受け切った「ジャストトス」なら
	# 逆に回復する(完璧な防御へのご褒美)。通常スパイクはノーダメージ。
	# 耐久力が尽きた瞬間にスタン(倒れて動けない)し、満タンへ戻る(気絶サイクル)。
	# 判定はball_powerを消費する前に読む
	# スイート判定(芯)は全用途共通: 耐久力の回復/削り、スパイクのパワー化、
	# そして「芯で捉えたボールは慣性に流されない」(慣性が30%→10%に落ちる)
	var sweet_r: int = cfg.player_reach * cfg.spike_sweet_pct / 100
	var sweet: bool = d2 >= 0 and d2 <= sweet_r * sweet_r
	var inertia: int = cfg.hit_inertia_just_num if sweet else cfg.hit_inertia_num
	if s.last_touch_team >= 0 and s.last_touch_team != team and s.ball_power == 1:
		if sweet:
			p.guard = mini(p.guard + cfg.guard_heal_just, p.guard_max)
		else:
			# パワーボールを芯を外して受けたら必ずよろけ(小スタン)。
			# 耐久力まで尽きたら本スタン(長い方が優先)
			p.guard -= cfg.guard_dmg_power
			# ジャストアタック被弾: 後ろ(自陣側)へノックバックし、しりもち。
			# 後ろ=相手と反対 = チーム0なら左(-1), チーム1なら右(+1)
			var back: int = -1 if team == 0 else 1
			p.vx = back * FP.from_int(KNOCKBACK_PX)
			if p.guard <= 0:
				p.stun = cfg.stun_ticks
				p.guard = p.guard_max
				s.hit_freeze = 10  # 気絶=一番の見せ所。167ms止めて「効いた」を刻む
			else:
				p.flinch = FLINCH_TICKS  # しりもち(耐久が残ってても被弾リアクション)
				s.hit_freeze = maxi(s.hit_freeze, 3)
	s.ball_power = 0
	# 押している方向(横=入力方向、上=IN_UP)。地上/空中どちらの打ち分けにも使う
	var hdir: int = 0
	if input & IN_LEFT:
		hdir -= 1
	if input & IN_RIGHT:
		hdir += 1
	var up: bool = (input & IN_UP) != 0
	if p.on_ground == 1:
		# 地上ヒット=トス/レシーブ。押している方向で狙いを打ち分ける。
		# 横成分は入力方向(相方へ返す後ろ向きも可)、無ければ真上。
		var desired_vx: int = 0
		var desired_vy: int = 0
		if hdir != 0 and not up:
			# 横のみ: 前へ低く遠く。ただしボールがリーチの縁ギリギリなら
			# ジャンピングトス(飛びついて片手で拾う救済)になり、緩めの軌道に化ける。
			# 入力は同じで状況が挙動を変える(演出は表示層がヒット距離から導出する)
			var edge: int = cfg.player_reach * 3 / 4
			if d2 >= 0 and d2 > edge * edge:
				desired_vy = -cfg.bump_up_speed
				desired_vx = hdir * cfg.toss_mid_vx
				p.dive = hdir * cfg.hit_cooldown_ticks  # 表示層の飛びつき演出用
			else:
				desired_vy = -cfg.toss_fwd_vy
				desired_vx = hdir * cfg.toss_fwd_vx
			p.hit_kind = 2  # 前トス(横のみ)
		elif hdir != 0 and up:
			# 上+横: 中間(高く+そこそこ前)
			desired_vy = -cfg.bump_up_speed
			desired_vx = hdir * cfg.toss_mid_vx
			p.hit_kind = 1  # トス
		elif up:
			# 上のみ: 真上へ高く
			desired_vy = -cfg.bump_up_speed
			desired_vx = 0
			p.hit_kind = 1  # トス
		else:
			# ニュートラル: 少し前へ=素レシーブ
			desired_vy = -cfg.bump_up_speed
			desired_vx = dir * cfg.bump_fwd_speed
			p.hit_kind = 0  # レシーブ
		# 慣性反映: 入射ボールの勢いを殺しきれず一部が反発して狙いに乗る。
		# 強い入射ほど狙いから逸れる(真上に受けても前へずれる、強打は高く跳ねる)。
		# 反発なので入射速度を符号反転して加える。RHSは代入前の入射値を読む
		s.ball_vx = desired_vx - s.ball_vx * inertia / cfg.hit_inertia_den
		s.ball_vy = desired_vy - s.ball_vy * inertia / cfg.hit_inertia_den
	elif input & IN_DOWN:
		# 空中+下: アタック(叩き下ろす)。ジャストミート(ボールがスイートスポット=
		# リーチのspike_sweet_pct%以内)ならメテオ級: 速度ボーナス+パワーボール化。
		# 原作観察点14「タイミングで玉の威力やスタン値が上がる」の芯。
		# 打ち分け: 下のみ=鋭角(手前に鋭く落ちる。近距離でないと自陣落ちのリスク)、
		# 下+横=緩角(遠くまで届くが軌道が浅く取られやすい)。飛ぶ向きは常にネット方向。
		# 空中アタックにも地上と同じ慣性反射がかかる: 上がり際のボールを叩けば
		# 反発が乗って鋭く速く、落ち際なら浮いて深く飛ぶ=打つタイミングが着弾を変える。
		# ジャストミート(芯)なら慣性が10%に落ち、狙い通りに飛ぶ
		var pct: int = 100
		if sweet:
			pct = cfg.spike_power_pct
			s.ball_power = 1
			# ジャストスマッシュ=最大の見せ所。短い瞬止(5tick=83ms)で「止め」を作った直後、
			# スローモーション12tick(1/3速)でボールが撃ち出される様をスロー再生する。
			# 18tickは過剰との指摘で12へ短縮(スマブラの決めカットより軽め)
			s.hit_freeze = maxi(s.hit_freeze, 5)
			s.slow_ticks = maxi(s.slow_ticks, 12)
		else:
			# 通常アタックの瞬止を4tick=67msに強化(2tickでは打感が伝わらないとの指摘)
			s.hit_freeze = maxi(s.hit_freeze, 4)
		var svx: int
		var svy: int
		if hdir != 0:
			svy = cfg.spike_vy * pct / 100
			svx = dir * cfg.spike_vx * pct / 100
		else:
			svy = cfg.spike_steep_vy * pct / 100
			svx = dir * cfg.spike_steep_vx * pct / 100
		s.ball_vx = svx - s.ball_vx * inertia / cfg.hit_inertia_den
		s.ball_vy = svy - s.ball_vy * inertia / cfg.hit_inertia_den
	elif up:
		# 空中+上: 斜め上へトス(セルフセット/相方へ)。横入力方向、無ければ真上
		s.ball_vy = -cfg.bump_up_speed
		s.ball_vx = hdir * cfg.toss_mid_vx
	elif hdir != 0:
		# 空中+横: きつめの角度の山なりで遠くへトス
		s.ball_vy = -cfg.toss_fwd_vy
		s.ball_vx = hdir * cfg.toss_fwd_vx
	else:
		# 空中ニュートラル: 軟攻(フェイント)。ふわっとネット越しにポトリと落とす
		# チョン当て。強打(下)との読み合いを作る。ネット際でないと自陣に落ちる
		s.ball_vy = -cfg.feint_vy
		s.ball_vx = dir * cfg.feint_vx
	p.hit_cooldown = cfg.hit_cooldown_ticks
	s.last_hit_tick = s.tick
	if s.last_touch_team == team:
		s.touches += 1
	else:
		s.touches = 1
	s.last_touch_team = team
	if s.touches > cfg.max_touches:
		_award_point(s, 1 - team, cfg)

static func _step_player(p, input: int, cfg, team: int) -> void:
	# 帽子投げの溜め中: 入力を一切受け付けず、その場で凍結(空中なら浮いたまま)。
	# 投げは強いがリスク=硬直を負う。溜め終了で_update_hatが帽子を発射する
	if p.throw > 0:
		p.vx = 0
		if p.on_ground == 0:
			p.vy = 0
		return
	# しりもち(butt-drop)中: 入力無効。ノックバックのvxを摩擦で減衰させ後ろへ滑る。
	# 空中なら落下し着地する。スタンより短い被弾リアクション
	if p.flinch > 0:
		p.flinch -= 1
		p.vx = p.vx * 3 / 4
		if p.on_ground == 0:
			if p.vy < 0:
				p.vy = p.vy / 2
			p.vy += cfg.gravity
		var fmin: int = 0
		var fmax: int = cfg.court_width
		if team == 0:
			fmax = cfg.net_x - cfg.net_half_w
		else:
			fmin = cfg.net_x + cfg.net_half_w
		p.x = clampi(p.x + p.vx, fmin, fmax)
		p.y += p.vy
		if p.y >= cfg.floor_y:
			p.y = cfg.floor_y
			p.vy = 0
			p.on_ground = 1
		if p.hit_cooldown > 0:
			p.hit_cooldown -= 1
		return
	# スタン中は入力無効(移動もジャンプも不可)。物理(重力・着地)は生きる
	if p.stun > 0:
		p.stun -= 1
		input = 0
	# トス構え(上+アクション): その場で小ホップして手を伸ばす。横キーは
	# トスの方向指定専用になり移動には使わない(「トスだけする」ユーザー指定)
	var toss_stance: bool = (input & IN_ACTION) != 0 and (input & IN_JUMP) != 0
	var in_dir: int = 0
	if not toss_stance:
		if input & IN_LEFT:
			in_dir -= 1
		if input & IN_RIGHT:
			in_dir += 1
	# 急ブレーキ(スキッド): 一定時間"走り続けた"後に逆方向を入れたときだけ、すぐ反転せず
	# 数tick旧方向へ滑って減速してから向きが変わる(マリオの"キキーッ"の間)。
	# 追尾の細かい左右振り(オシレーション)ではrunが溜まらず発動しない=制御を壊さない。
	# p.brake: 符号=滑る方向, 絶対値=残りtick(diveと同じ「表示層も読むヒント」方式)
	# 走行方向と継続を符号付きp.runで管理(符号=方向, 絶対値=継続tick)。
	# ニュートラルでは即0にせず徐々に減衰させる=「離して押し直す」反転も拾う猶予。
	var prev_run: int = p.run
	if p.on_ground == 0:
		p.run = 0
	elif in_dir == 0:
		p.run = signi(prev_run) * maxi(absi(prev_run) - RUN_DECAY, 0)
	elif signi(prev_run) == in_dir:
		p.run = in_dir * mini(absi(prev_run) + 1, RUN_CAP)
	elif p.brake == 0 and absi(prev_run) >= SKID_MIN_RUN:
		# 十分走った後の逆方向入力 → 急ブレーキ(旧方向へ滑ってから反転)
		p.brake = BRAKE_TICKS * signi(prev_run)
		p.run = 0
	else:
		p.run = in_dir  # 走り始め
	if p.brake != 0 and p.on_ground == 1:
		var sdir: int = signi(p.brake)
		var rem: int = absi(p.brake)
		p.vx = sdir * cfg.move_speed * rem / BRAKE_TICKS  # 線形減速で滑る
		rem -= 1
		p.brake = sdir * rem  # 残りゼロで自動的にbrake=0=反転解禁
	else:
		p.brake = 0  # 空中やニュートラルではスキッド解除
		p.vx = in_dir * cfg.move_speed
	# 向き(face)をvxから更新。動いていない間は直前の向きを保持
	if p.vx > 0:
		p.face = 1
	elif p.vx < 0:
		p.face = -1
	if (input & IN_JUMP) and p.on_ground == 1:
		if toss_stance:
			p.vy = -cfg.hop_speed
		else:
			p.vy = -cfg.jump_speed
		p.on_ground = 0
	if p.on_ground == 0:
		# 可変ジャンプ: 上昇中に上キーを離すとその場で失速して落下に転じる
		# (毎tick半減の減衰。intの/2はゼロ方向切り捨てで決定論)
		if p.vy < 0 and not (input & IN_JUMP):
			p.vy = p.vy / 2
		p.vy += cfg.gravity
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1
	# ジャンピングトス演出の残時間(符号=方向)。ゼロへ向かって減る
	if p.dive > 0:
		p.dive -= 1
	elif p.dive < 0:
		p.dive += 1
	var min_x: int = 0
	var max_x: int = cfg.court_width
	if team == 0:
		max_x = cfg.net_x - cfg.net_half_w
	else:
		min_x = cfg.net_x + cfg.net_half_w
	# ヒップアタック(帽子ありのみ): 空中+下(スペース無し)で発動。空中で静止して回転し、
	# その後まっすぐ急降下。専用アニメが帽子ありのみなのでhas_hatを要求する
	var want_hip: bool = p.on_ground == 0 and (input & IN_DOWN) != 0 \
			and not (input & IN_ACTION) and p.has_hat == 1
	if p.hip == 0 and want_hip:
		p.hip = HIP_HOVER_TICKS
	if p.hip > 0:
		p.vx = 0
		p.vy = 0
		p.hip -= 1
		if p.hip == 0:
			p.hip = -1  # 静止終了→急降下へ
	elif p.hip == -1:
		p.vx = 0
		p.vy = FP.from_int(HIP_DROP_PX)
	# 壁張り付き: 空中で外壁側へ押し付けると、壁を背にずるずる低速降下する
	p.cling = 0
	if p.hip == 0 and p.on_ground == 0:
		var at_left: bool = team == 0 and (input & IN_LEFT) != 0 and p.x <= min_x
		var at_right: bool = team == 1 and (input & IN_RIGHT) != 0 and p.x >= max_x
		if at_left or at_right:
			p.vx = 0
			p.vy = FP.from_int(CLING_SLIDE_PX)
			p.cling = 1 if at_left else -1
	p.x = clampi(p.x + p.vx, min_x, max_x)
	p.y += p.vy
	if p.y >= cfg.floor_y:
		p.y = cfg.floor_y
		p.vy = 0
		p.on_ground = 1
		p.hip = 0
		p.cling = 0

static func _step_ball(s, cfg) -> void:
	var prev_x: int = s.ball_x
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
	# 回転は横の勢いに比例して累積する(真上のトスはほぼ無回転、前へ飛ぶほど回る)
	s.ball_spin += s.ball_vx
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	if s.ball_x < left:
		s.ball_x = left + (left - s.ball_x)
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	elif s.ball_x > right:
		s.ball_x = right - (s.ball_x - right)
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	# 床の反射はしない。RALLY中の床接触は_check_floor_pointが得点として処理する。
	# 天井の反射もしない(原作準拠): ボールは画面上端を突き抜けて出てよい。重力で必ず
	# 戻るため見失わない。跳ね返るのは左右の壁だけ。
	_ball_vs_net(s, cfg, prev_x)
	_ball_vs_block(s, cfg)

# ブロック: ネット際(60px圏)で空中にいる体は相手の打球に対して壁になる。
# 入力不要=ジャンプそのものが防御になる(スパイクvsブロックの読み合いの核)。
# 反射は物理的に単純: 横速度を反転減衰(最低でもネット反発分は押し返す)、
# 縦はそのまま=強打は下向きのままアタッカー側へ突き刺さる(キルブロック)。
# サーブは飛行中ブロック不可(バレーのルール準拠)。ボールのパワーは
# ブロックでは消費されない(自分のメテオが跳ね返ってくるスリルは残す)
static func _ball_vs_block(s, cfg) -> void:
	if s.phase != SimStateScript.PHASE_RALLY or s.serve_flight == 1:
		return
	if s.last_touch_team < 0:
		return
	var zone: int = FP.from_int(60)
	for i in s.players.size():
		var team: int = team_of(i)
		if team == s.last_touch_team:
			continue  # 自チームの打球は自分たちの体に当たらない(空中戦の自滅防止)
		var p = s.players[i]
		if p.on_ground == 1 or p.stun > 0 or p.hit_cooldown > 0:
			continue
		if absi(p.x - cfg.net_x) > zone:
			continue
		# ボールが自陣へ向かって飛んでいる時だけ(離れる球に壁は要らない)
		var dir_in: int = -1 if team == 0 else 1
		if s.ball_vx == 0 or signi(s.ball_vx) != dir_in:
			continue
		# 手のひらゾーン: 頭上(reach_up)中心の小さい楕円(横reach/2、縦reach_up/2)
		var cx: int = p.x
		var cy: int = p.y - cfg.player_reach_up
		var rx: int = cfg.player_reach / 2
		var ry: int = cfg.player_reach_up / 2
		var dx: int = s.ball_x - cx
		var dy_n: int = (s.ball_y - cy) * rx / ry
		if dx * dx + dy_n * dy_n > rx * rx:
			continue
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		if team == 0:
			s.ball_vx = maxi(s.ball_vx, cfg.net_repel)
		else:
			s.ball_vx = mini(s.ball_vx, -cfg.net_repel)
		s.last_touch_team = team
		s.touches = 0  # ブロックはタッチ数に数えない(バレー準拠)
		s.last_hit_tick = s.tick
		p.hit_cooldown = cfg.hit_cooldown_ticks
		s.hit_freeze = maxi(s.hit_freeze, 2)
		return

static func _step_ball_loose(s, cfg) -> void:
	# ポーズ中・勝敗確定後のボール。得点処理はせず、床で減衰バウンドして転がる
	_step_ball(s, cfg)
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	if s.ball_y > floor_limit:
		s.ball_y = floor_limit - (s.ball_y - floor_limit)
		if s.ball_vy > 0:
			s.ball_vy = -s.ball_vy * cfg.ball_bounce_num / cfg.ball_bounce_den
			# 乗算減衰だけだと閾値近傍で微小バウンドが長く続く速度帯がある(共振、
			# レビュー指摘: 特定入射で数千tick跳ね続けた)。反発のたびに固定量も
			# 減衰させ、有限バウンド回数で必ず閾値を割らせる
			s.ball_vy = mini(s.ball_vy + cfg.ball_rest_speed / 4, 0)
		# 床接触のたびに横速度も減衰(転がって自然に止まる)
		s.ball_vx = s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		# 微小な跳ね/転がりは静止させ床にスナップ(小刻みな跳ねの継続を断つ)
		if absi(s.ball_vy) < cfg.ball_rest_speed:
			s.ball_vy = 0
			s.ball_y = floor_limit
		if absi(s.ball_vx) < cfg.ball_rest_speed:
			s.ball_vx = 0

static func _ball_vs_net(s, cfg, prev_x: int) -> void:
	var net_left: int = cfg.net_x - cfg.net_half_w - cfg.ball_radius
	var net_right: int = cfg.net_x + cfg.net_half_w + cfg.ball_radius
	var below_top: bool = s.ball_y > cfg.net_top_y
	var was_left: bool = prev_x < cfg.net_x
	var is_left: bool = s.ball_x < cfg.net_x
	if below_top:
		# ネット下部は壁。来た側へ押し返す
		if s.ball_x >= net_left and s.ball_x <= net_right:
			# 減衰反射しつつ最低反発速度を保証(ネットに当たったら必ず少し跳ね返る)
			if was_left:
				s.ball_x = net_left - (s.ball_x - net_left)
				if s.ball_vx > 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
				s.ball_vx = mini(s.ball_vx, -cfg.net_repel)
			else:
				s.ball_x = net_right + (net_right - s.ball_x)
				if s.ball_vx < 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
				s.ball_vx = maxi(s.ball_vx, cfg.net_repel)
	elif was_left != is_left:
		# ネット上空を越えた: 攻守交代なのでタッチ数リセット。サーブ打球も渡り切り
		s.touches = 0
		s.serve_flight = 0
