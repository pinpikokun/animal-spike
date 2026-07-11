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
	if state.phase == SimStateScript.PHASE_SERVE:
		state.timer -= 1
		_step_players_and_hits(state, inputs, cfg)
		# サーバーは外線(サービスライン)を越えられない(最初のトスまで)。線の後ろでは動ける。
		# トスするとRALLYへ移りこの制限は外れ、前へ移動/ジャンプしてアタックサーブできる。
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
	var srv = s.players[serving_team * 2]
	srv.x = _serve_x(s, cfg)
	srv.y = cfg.floor_y
	srv.vx = 0
	srv.vy = 0
	srv.on_ground = 1
	srv.hit_cooldown = 0
	_hold_ball_on_server(s, cfg)

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
	# サーブ=セルフトス。方向で打ち分ける。白線後方から打つため前サーブは専用パワー。
	var hdir: int = 0
	if input & IN_LEFT:
		hdir -= 1
	if input & IN_RIGHT:
		hdir += 1
	var up: bool = (input & IN_UP) != 0
	if hdir != 0 and not up:
		# 前サーブ(緩いサーブ): 白線後方からネットを越えて届く専用の強さ
		s.ball_vx = hdir * cfg.serve_vx
		s.ball_vy = -cfg.serve_vy
	else:
		# 真上/中間トス: アタックサーブ用。高く上げてジャンプ+アタックで叩く
		s.ball_vy = -cfg.bump_up_speed
		s.ball_vx = hdir * cfg.toss_mid_vx
	s.players[idx].hit_cooldown = cfg.hit_cooldown_ticks
	s.touches = 1
	s.last_touch_team = s.serving_team
	s.phase = SimStateScript.PHASE_RALLY

static func _check_floor_point(s, cfg) -> void:
	# 同一tick内でタッチ超過などが先に得点しフェーズが変わっていたら加点しない(1ラリー2点の禁止)
	if s.phase != SimStateScript.PHASE_RALLY:
		return
	if s.ball_y < cfg.floor_y - cfg.ball_radius:
		return
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
	if s.phase != SimStateScript.PHASE_RALLY:
		return
	var reach: int = cfg.player_reach
	var side_team: int = 0 if s.ball_x < cfg.net_x else 1
	var best_i: int = -1
	var best_d2: int = 0
	for i in s.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		if not (input & IN_ACTION):
			continue
		var p = s.players[i]
		if p.hit_cooldown > 0:
			continue
		var dx: int = s.ball_x - p.x
		var dy: int = s.ball_y - p.y
		# 両辺ともfp生値の積((fp)^2単位)で比較しスケールを揃える。
		# オーバーフロー検討: dx最大640<<16≈4.2e7、二乗≈1.8e15 < int64上限9.2e18で安全
		var d2: int = dx * dx + dy * dy
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
		_apply_hit(s, best_i, cfg, winner_input)

static func _apply_hit(s, i: int, cfg, input: int) -> void:
	var p = s.players[i]
	var team: int = team_of(i)
	var dir: int = _dir_of_team(team)
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
			# 横のみ: 前へ低く遠く
			desired_vy = -cfg.toss_fwd_vy
			desired_vx = hdir * cfg.toss_fwd_vx
		elif hdir != 0 and up:
			# 上+横: 中間(高く+そこそこ前)
			desired_vy = -cfg.bump_up_speed
			desired_vx = hdir * cfg.toss_mid_vx
		elif up:
			# 上のみ: 真上へ高く
			desired_vy = -cfg.bump_up_speed
			desired_vx = 0
		else:
			# ニュートラル: 少し前へ=素レシーブ
			desired_vy = -cfg.bump_up_speed
			desired_vx = dir * cfg.bump_fwd_speed
		# 慣性反映: 入射ボールの勢いを殺しきれず一部が反発して狙いに乗る。
		# 強い入射ほど狙いから逸れる(真上に受けても前へずれる、強打は高く跳ねる)。
		# 反発なので入射速度を符号反転して加える。RHSは代入前の入射値を読む
		s.ball_vx = desired_vx - s.ball_vx * cfg.hit_inertia_num / cfg.hit_inertia_den
		s.ball_vy = desired_vy - s.ball_vy * cfg.hit_inertia_num / cfg.hit_inertia_den
	elif up:
		# ジャンプトス: 空中でも上入力なら叩き下ろさず上げる(セルフセット/相方へ)。
		# 横入力があればその方向へ、無ければ真上
		s.ball_vy = -cfg.bump_up_speed
		s.ball_vx = hdir * cfg.toss_mid_vx
	else:
		# スパイク: 空中・上入力なしは叩き下ろす
		s.ball_vy = cfg.spike_vy
		s.ball_vx = dir * cfg.spike_vx
	p.hit_cooldown = cfg.hit_cooldown_ticks
	if s.last_touch_team == team:
		s.touches += 1
	else:
		s.touches = 1
	s.last_touch_team = team
	if s.touches > cfg.max_touches:
		_award_point(s, 1 - team, cfg)

static func _step_player(p, input: int, cfg, team: int) -> void:
	p.vx = 0
	if input & IN_LEFT:
		p.vx = -cfg.move_speed
	if input & IN_RIGHT:
		p.vx = cfg.move_speed
	if (input & IN_JUMP) and p.on_ground == 1:
		p.vy = -cfg.jump_speed
		p.on_ground = 0
	if p.on_ground == 0:
		p.vy += cfg.gravity
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1
	var min_x: int = 0
	var max_x: int = cfg.court_width
	if team == 0:
		max_x = cfg.net_x - cfg.net_half_w
	else:
		min_x = cfg.net_x + cfg.net_half_w
	p.x = clampi(p.x + p.vx, min_x, max_x)
	p.y += p.vy
	if p.y >= cfg.floor_y:
		p.y = cfg.floor_y
		p.vy = 0
		p.on_ground = 1

static func _step_ball(s, cfg) -> void:
	var prev_x: int = s.ball_x
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
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
			if was_left:
				s.ball_x = net_left - (s.ball_x - net_left)
				if s.ball_vx > 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
			else:
				s.ball_x = net_right + (net_right - s.ball_x)
				if s.ball_vx < 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	elif was_left != is_left:
		# ネット上空を越えた: 攻守交代なのでタッチ数リセット
		s.touches = 0
