# シミュレーション本体。1tick進める純粋ロジック
# int演算のみ。ここにfloatを書いたらSyncTest以前にレビューで即アウト
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const Chars := preload("res://src/sim/chars.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

const IN_LEFT := SimInput.IN_LEFT
const IN_RIGHT := SimInput.IN_RIGHT
const IN_JUMP := SimInput.IN_JUMP
const IN_ACTION := SimInput.IN_ACTION
const IN_SWITCH := SimInput.IN_SWITCH
const IN_UP := SimInput.IN_UP
const IN_DOWN := SimInput.IN_DOWN
const IN_ABILITY1 := SimInput.IN_ABILITY1

# サーブトス照準。左右キー=着弾距離(0..AIM_MAXの目盛りをserve_toss_rangeへ線形対応)、
# 上下キー=トスの高さ%(POW_MIN..POW_MAX)。距離と高さは完全に独立
# (山なりを目の前に、低く速いのを遠くに、どの組合せも可)
const AIM_MAX := 60
const POW_MIN := 60   # トス高さの下限(%)
const POW_MAX := 130  # トス高さの上限(%)
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

# エンティティ種別(sim_state.entitiesのkind)。0=空きスロット
const KIND_CAP := 1  # 帽子(お邪魔ギミック)

# 指定kindの最初のエンティティslotを返す(無ければ-1)。線形走査で決定論
static func ent_find(s, kind: int) -> int:
	for j in s.entities.size():
		if s.entities[j].kind == kind:
			return j
	return -1

# 先頭の空きスロットに生成して番号を返す。満杯なら-1(生成失敗=安全側)
static func ent_spawn(s, kind: int) -> int:
	for j in s.entities.size():
		var e = s.entities[j]
		if e.kind == 0:
			e.kind = kind
			e.phase = 0
			e.x = 0
			e.y = 0
			e.vx = 0
			e.vy = 0
			e.owner = 0
			e.timer = 0
			return j
	return -1

# スロットを解放(全欄ゼロ=ハッシュが空きスロットと完全一致するように)
static func ent_free(e) -> void:
	e.kind = 0
	e.phase = 0
	e.x = 0
	e.y = 0
	e.vx = 0
	e.vy = 0
	e.owner = 0
	e.timer = 0

static func team_of(i: int) -> int:
	return SimStateScript.team_of(i)

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
	_update_drive_recovery(state, cfg)
	var burnout_before: Array[int] = []
	for p in state.players:
		burnout_before.append(p.burnout_ticks)
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
			var srv_idx: int = SimStateScript._server_index(state)
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
			var srv = state.players[SimStateScript._server_index(state)]
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
			BallPhysics._step_ball(state, cfg, inputs)
			HitResolver._ball_vs_block(state, cfg, inputs)
			if state.phase == SimStateScript.PHASE_SERVE \
					and state.ball_y >= cfg.floor_y - cfg.ball_radius:
				# サーブトス空振りは相手得点となり、次のサーブ権も相手へ移る。
				_award_point(state, 1 - state.serving_team, cfg)
	elif state.phase == SimStateScript.PHASE_RALLY:
		_step_players_and_hits(state, inputs, cfg)
		BallPhysics._step_ball(state, cfg, inputs)
		HitResolver._ball_vs_block(state, cfg, inputs)
		_check_floor_point(state, cfg)
	elif state.phase == SimStateScript.PHASE_POINT_PAUSE:
		state.timer -= 1
		# ポーズ中も操作は生かす(ヒットは_try_hitのフェーズ判定で無効)
		_step_players_and_hits(state, inputs, cfg)
		BallPhysics._step_ball_loose(state, cfg)
		if state.timer <= 0:
			reset_rally(state, cfg, state.serving_team)
	elif state.phase == SimStateScript.PHASE_GAME_OVER:
		# 勝敗確定後もキャラの移動・ジャンプは生かす
		_step_players_and_hits(state, inputs, cfg)
		BallPhysics._step_ball_loose(state, cfg)
	_apply_burnout_entry_feedback(state, burnout_before)

static func _apply_burnout_entry_feedback(state, burnout_before: Array[int]) -> void:
	for i in state.players.size():
		if burnout_before[i] == 0 and state.players[i].burnout_ticks > 0:
			state.hit_freeze = maxi(state.hit_freeze, 4)

static func _update_drive_recovery(state, cfg) -> void:
	for p in state.players:
		if p.just_receive_flash > 0:
			p.just_receive_flash -= 1
	if state.phase != SimStateScript.PHASE_RALLY:
		return
	for p in state.players:
		if p.burnout_ticks > 0:
			p.burnout_ticks -= 1
			if p.burnout_ticks == 0:
				p.drive_gauge = cfg.drive_gauge_max
				p.drive_recovery_progress = 0
				p.drive_recovery_delay = 0
			continue
		if p.drive_recovery_delay > 0:
			p.drive_recovery_delay -= 1
			continue
		if p.drive_gauge >= cfg.drive_gauge_max:
			p.drive_gauge = cfg.drive_gauge_max
			p.drive_recovery_progress = 0
			continue
		p.drive_recovery_progress += cfg.drive_gauge_stock
		var recovered: int = p.drive_recovery_progress \
			/ cfg.drive_recovery_ticks_per_stock
		p.drive_recovery_progress = p.drive_recovery_progress \
			% cfg.drive_recovery_ticks_per_stock
		p.drive_gauge = mini(p.drive_gauge + recovered, cfg.drive_gauge_max)
		if p.drive_gauge == cfg.drive_gauge_max:
			p.drive_recovery_progress = 0

static func _step_players_and_hits(state, inputs: Array[int], cfg) -> void:
	var hip_landed: bool = false
	for i in state.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		var p = state.players[i]
		var was_hip_drop: bool = p.hip == -1
		PlayerMovement._step_player(p, input, cfg, team_of(i))
		if was_hip_drop and p.on_ground == 1 and p.hip == 0:
			hip_landed = true
	if hip_landed:
		state.hip_quake_event += 1
		for p in state.players:
			p.quake_stun = cfg.hip_quake_stun_ticks
	var was_serve_strike: bool = state.phase == SimStateScript.PHASE_SERVE \
		and state.serve_tossed == 1
	var hit_result: int = HitResolver._resolve_hit(state, inputs, cfg)
	if hit_result == 0 or hit_result == 1:
		_award_point(state, hit_result, cfg)
	if was_serve_strike and hit_result != HitResolver.NO_HIT:
		# 得点授与より後に遷移する現行順序をmax_touches=0でも維持する。
		state.phase = SimStateScript.PHASE_RALLY
		state.serve_tossed = 0
		state.serve_flight = 1
	_update_receive_stances(state, inputs)
	_update_hat(state, inputs, cfg)

static func _update_receive_stances(state, inputs: Array[int]) -> void:
	for i in state.players.size():
		var p = state.players[i]
		var input: int = inputs[i] if i < inputs.size() else 0
		var holding: bool = state.phase == SimStateScript.PHASE_RALLY \
			and p.on_ground == 1 and p.vx == 0 and p.stun == 0 and p.quake_stun == 0 \
			and (input & IN_ACTION) != 0 and (input & IN_DOWN) != 0 \
			and (input & (IN_LEFT | IN_RIGHT)) == 0
		p.receive_stance = mini(p.receive_stance + 1, 2) if holding else 0

# 帽子投げ(お邪魔ギミック): Dキーで前方へ投げ、飛行→滞在→高速帰還→キャッチ。
# 飛んでる間ボールと当たり判定を持ち、触れると弾く。一度に1個だけ
static func _update_hat(state, inputs: Array[int], cfg) -> void:
	# 溜め(windup)管理: D入力で溜め開始→溜め終了フレームで発射(帽子はそれまで頭上)。
	# _step_playerが溜め中の入力を封じる(投げは強いがリスク=硬直)。
	# 帽子は同時に1個だけ(ent_findで存在確認)
	for i in state.players.size():
		var inp: int = inputs[i] if i < inputs.size() else 0
		var p = state.players[i]
		if p.throw == 0 and p.has_hat == 1 and (inp & IN_ABILITY1) \
				and Chars.has_ability(p.char_id, Chars.CA_HAT) \
				and p.stun == 0 and p.flinch == 0 and p.burnout_ticks == 0 \
				and p.hip == 0 and p.quake_stun == 0 \
				and ent_find(state, KIND_CAP) < 0:
			if p.drive_gauge > 0:
				p.drive_gauge = maxi(p.drive_gauge - cfg.drive_gauge_stock, 0)
				p.drive_recovery_delay = cfg.drive_recovery_delay_ticks
				if p.drive_gauge == 0:
					p.burnout_ticks = cfg.burnout_recovery_ticks
					p.drive_recovery_progress = 0
				p.throw = THROW_TICKS
		if p.throw > 0:
			p.throw -= 1
			if p.throw == 0 and p.has_hat == 1 and ent_find(state, KIND_CAP) < 0:
				var slot: int = ent_spawn(state, KIND_CAP)
				if slot >= 0:  # 満杯なら発射失敗(帽子は頭に残る=安全側)
					var e = state.entities[slot]
					var net_dir: int = 1 if team_of(i) == 0 else -1
					var dir: int = p.face if p.face != 0 else net_dir
					e.phase = 1
					e.owner = i
					# 頭ではなく手から放つ: 向いてる方向へ少し前、高さは手のあたり
					e.x = p.x + dir * FP.from_int(CAP_HAND_FWD_PX)
					e.y = p.y - FP.from_int(CAP_HAND_UP_PX)
					e.vx = dir * FP.from_int(CAP_THROW_PX)
					e.vy = 0
					e.timer = CAP_OUT_TICKS
					p.has_hat = 0
	var idx: int = ent_find(state, KIND_CAP)
	if idx < 0:
		return
	var cap = state.entities[idx]
	if cap.phase == 1:  # 飛行(前方へ)
		cap.x += cap.vx
		# ネットは越えられない: ネット面に達したら即滞在(自陣ネット際での妨害になる)
		var owner_team: int = team_of(cap.owner)
		var hit_net: bool = false
		if owner_team == 0 and cap.x >= cfg.net_x - cfg.net_half_w:
			cap.x = cfg.net_x - cfg.net_half_w
			hit_net = true
		elif owner_team == 1 and cap.x <= cfg.net_x + cfg.net_half_w:
			cap.x = cfg.net_x + cfg.net_half_w
			hit_net = true
		cap.timer -= 1
		if hit_net or cap.timer <= 0:
			cap.phase = 2
			cap.timer = CAP_HOVER_TICKS
			cap.vx = 0
	elif cap.phase == 2:  # 滞在(その場で回転)
		cap.timer -= 1
		if cap.timer <= 0:
			cap.phase = 3
	elif cap.phase == 3:  # 帰還(所有者の頭へ高速)
		var owner = state.players[cap.owner]
		var tx: int = owner.x
		var ty: int = owner.y - FP.from_int(CAP_HEAD_UP_PX)
		var rv: int = FP.from_int(CAP_RETURN_PX)
		cap.x += clampi(tx - cap.x, -rv, rv)
		cap.y += clampi(ty - cap.y, -rv, rv)
		if absi(tx - cap.x) <= FP.from_int(CAP_CATCH_PX) \
				and absi(ty - cap.y) <= FP.from_int(CAP_CATCH_PX):
			owner.has_hat = 1
			ent_free(cap)  # キャッチ=スロット解放
			return
	# ボール当たり判定(飛行/滞在/帰還いずれも): 触れたら弾く
	var r: int = FP.from_int(CAP_RADIUS_PX) + cfg.ball_radius
	var dx: int = state.ball_x - cap.x
	var dy: int = state.ball_y - cap.y
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
	s.ball_attack_kind = SimStateScript.BALL_ATTACK_NONE
	s.ball_guard_damage = 0
	s.ball_defense_class = Chars.DEFENSE_NONE
	s.ball_ghost = 0
	s.ball_flame = 0
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
		p.stun_action_held = 0
		p.burn = 0
		p.dive = 0
		p.brake = 0
		p.run = 0
		p.throw = 0
		p.flinch = 0
		p.hip = 0
		p.cling = 0
		p.receive_stance = 0
		p.just_receive_flash = 0
		p.quake_stun = 0
		# 投げっぱなしの帽子はラリー再開で戻す(帽子を持たないキャラは持たないまま)
		p.has_hat = 1 if Chars.has_ability(p.char_id, Chars.CA_HAT) else 0
	# 飛んでるエンティティ(帽子等)は全て消す(ラリーをまたぐ置き物は今後kind別に判断)
	for e in s.entities:
		ent_free(e)
	var srv = s.players[SimStateScript._server_index(s)]
	srv.x = _serve_x(s, cfg)
	srv.y = cfg.floor_y
	srv.vx = 0
	srv.vy = 0
	srv.on_ground = 1
	srv.hit_cooldown = 0
	_hold_ball_on_server(s, cfg)

static func reset_match(s, cfg, serving_team: int, roster: Array = Chars.ROSTER) -> void:
	# 試合開始時のみキャラを初期配置に置く。rosterは試合セットアップの一部
	# (ネット対戦では開始時に両者で同じ配列を渡すこと=決定論安全)
	var back: int = FP.from_int(cfg.spawn_back_px)
	var front: int = FP.from_int(cfg.spawn_front_px)
	var positions: Array[int] = [back, front, cfg.court_width - back, cfg.court_width - front]
	for i in s.players.size():
		var p = s.players[i]
		p.char_id = roster[i]  # slotとキャラを結ぶのはここだけ
		p.x = positions[i]
		p.y = cfg.floor_y
		p.vx = 0
		p.vy = 0
		p.on_ground = 1
		p.hit_cooldown = 0
		p.has_hat = 1 if Chars.has_ability(p.char_id, Chars.CA_HAT) else 0
		# GUARDランクをrules.jsonの絶対値表へ直接写像する。
		p.guard_max = cfg.guard_max_for_rank(
			Chars.rank(p.char_id, Chars.Profile.ABILITY_GUARD))
		p.guard = p.guard_max
		p.drive_gauge = cfg.drive_gauge_max
		p.drive_recovery_progress = 0
		p.drive_recovery_delay = 0
		p.receive_stance = 0
		p.just_receive_flash = 0
		p.just_receive_event = 0
		p.burnout_ticks = 0
		p.quake_stun = 0
		p.stun_action_held = 0
		p.stun_mash_event = 0
	s.hip_quake_event = 0
	s.ball_guard_damage = 0
	s.ball_defense_class = Chars.DEFENSE_NONE
	reset_rally(s, cfg, serving_team)

static func _serve_x(s, cfg) -> int:
	# サービスライン(コート端寄りの白線)。サーバーはこの位置からサーブする
	if s.serving_team == 0:
		return cfg.serve_line
	return cfg.court_width - cfg.serve_line

static func _hold_ball_on_server(s, cfg) -> void:
	var server = s.players[SimStateScript._server_index(s)]
	s.ball_x = server.x
	s.ball_y = server.y - cfg.serve_hold_height

static func _try_serve(s, inputs: Array[int], cfg) -> void:
	var idx: int = SimStateScript._server_index(s)
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
	var net_dir: int = SimStateScript._dir_of_team(s.serving_team)
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
	s.ball_attack_kind = SimStateScript.BALL_ATTACK_NONE
	s.ball_guard_damage = 0
	s.ball_defense_class = Chars.DEFENSE_NONE
	s.ball_flame = 0
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
