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

# サーブ照準用の整数三角関数(fpスケール65536)。角度0..60度、1度刻み。
# 表示層の軌跡プレビューも同じテーブルを参照する(sim/表示の弾道一致)
const AIM_MAX := 60
const POW_MIN := 60   # サーブ威力の下限(%)
const POW_MAX := 130  # サーブ威力の上限(%)
const AIM_SIN: Array[int] = [0, 1144, 2287, 3430, 4572, 5712, 6850, 7987, 9121, 10252, 11380, 12505, 13626, 14742, 15855, 16962, 18064, 19161, 20252, 21336, 22415, 23486, 24550, 25607, 26656, 27697, 28729, 29753, 30767, 31772, 32768, 33754, 34729, 35693, 36647, 37590, 38521, 39441, 40348, 41243, 42126, 42995, 43852, 44695, 45525, 46341, 47143, 47930, 48703, 49461, 50203, 50931, 51643, 52339, 53020, 53684, 54332, 54963, 55578, 56175, 56756]
const AIM_COS: Array[int] = [65536, 65526, 65496, 65446, 65376, 65287, 65177, 65048, 64898, 64729, 64540, 64332, 64104, 63856, 63589, 63303, 62997, 62672, 62328, 61966, 61584, 61183, 60764, 60326, 59870, 59396, 58903, 58393, 57865, 57319, 56756, 56175, 55578, 54963, 54332, 53684, 53020, 52339, 51643, 50931, 50203, 49461, 48703, 47930, 47143, 46341, 45525, 44695, 43852, 42995, 42126, 41243, 40348, 39441, 38521, 37590, 36647, 35693, 34729, 33754, 32768]

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
		# サーブ照準(バブルボブル式): 横キーで角度(ネット方向=倒す/逆=立てる)、
		# 上下キーで威力(60..130%)。各1刻み/tickでスイープ。
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
	s.ball_spin = 0
	s.ball_power = 0
	s.serve_aim = 25  # 既定は気持ちよく相手コート前方へ入る角度
	s.serve_pow = 100
	# スタンはラリー終了で解除(新ラリーを硬直で始めさせない)
	for p in s.players:
		p.stun = 0
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
	# サーブ=照準角(serve_aim)に沿ったセルフトス(バブルボブル式)。
	# 0度=真上のトス(アタックサーブの起点)、角度を倒すほど低く速い弾道でネットへ
	var net_dir: int = _dir_of_team(s.serving_team)
	var aim: int = clampi(s.serve_aim, 0, AIM_MAX)
	var power: int = cfg.serve_power * clampi(s.serve_pow, POW_MIN, POW_MAX) / 100
	s.ball_vx = net_dir * (power * AIM_SIN[aim] / 65536)
	s.ball_vy = -(power * AIM_COS[aim] / 65536)
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

static func _apply_hit(s, i: int, cfg, input: int, d2: int = -1) -> void:
	var p = s.players[i]
	var team: int = team_of(i)
	var dir: int = _dir_of_team(team)
	# パワーボール(パーフェクトスパイク由来)を相手チームが受けるとスタン。
	# ヒット自体は成立する(慣性で大きく浮く)が、その後しばらく動けない。
	# 判定はball_powerを消費する前に読む
	if s.ball_power == 1 and s.last_touch_team != team:
		p.stun = cfg.stun_ticks
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
	elif input & IN_DOWN:
		# 空中+下: アタック(叩き下ろす)。ジャストミート(ボールがスイートスポット=
		# リーチのspike_sweet_pct%以内)ならメテオ級: 速度ボーナス+パワーボール化。
		# 原作観察点14「タイミングで玉の威力やスタン値が上がる」の芯
		var sweet: int = cfg.player_reach * cfg.spike_sweet_pct / 100
		var pct: int = 100
		if d2 >= 0 and d2 <= sweet * sweet:
			pct = cfg.spike_power_pct
			s.ball_power = 1
		s.ball_vy = cfg.spike_vy * pct / 100
		s.ball_vx = dir * cfg.spike_vx * pct / 100
	elif up:
		# 空中+上: 斜め上へトス(セルフセット/相方へ)。横入力方向、無ければ真上
		s.ball_vy = -cfg.bump_up_speed
		s.ball_vx = hdir * cfg.toss_mid_vx
	elif hdir != 0:
		# 空中+横: きつめの角度の山なりで遠くへトス
		s.ball_vy = -cfg.toss_fwd_vy
		s.ball_vx = hdir * cfg.toss_fwd_vx
	else:
		# 空中ニュートラル: 緩やかに相手コート方向へ送る
		s.ball_vy = -cfg.serve_soft_vy
		s.ball_vx = dir * cfg.serve_soft_vx
	p.hit_cooldown = cfg.hit_cooldown_ticks
	if s.last_touch_team == team:
		s.touches += 1
	else:
		s.touches = 1
	s.last_touch_team = team
	if s.touches > cfg.max_touches:
		_award_point(s, 1 - team, cfg)

static func _step_player(p, input: int, cfg, team: int) -> void:
	# スタン中は入力無効(移動もジャンプも不可)。物理(重力・着地)は生きる
	if p.stun > 0:
		p.stun -= 1
		input = 0
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
		# ネット上空を越えた: 攻守交代なのでタッチ数リセット
		s.touches = 0
