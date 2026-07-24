# ヒット判定と打球解決。int演算のみ
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")
const Chars := preload("res://src/sim/chars.gd")

const IN_LEFT := SimInput.IN_LEFT
const IN_RIGHT := SimInput.IN_RIGHT
const IN_ACTION := SimInput.IN_ACTION
const IN_UP := SimInput.IN_UP
const IN_DOWN := SimInput.IN_DOWN
const IN_ABILITY1 := SimInput.IN_ABILITY1

const NO_HIT := -2
const HIT_NO_POINT := -1
const SALT_MURA := 23
const SALT_TOSS_BAD := 29
# ノックバック/反動(push): 残りtickに比例した速度で滑り、線形減衰する。
# 量は重さ%で伸縮(重いキャラはどっしり、軽いキャラは飛ばされる)
const MANGLE_AIM_PCT := 30   # パワーボールを芯外しで触った時に残る狙い成分%(制御喪失)
const PUSH_ATK_TICKS := 10   # ジャストアタックの反動(重さ100で約14px後退)
const PUSH_BLK_TICKS := 9    # パワーボールをブロックした時の押し込み(約22px)
const PUSH_MAX_TICKS := 16   # 軽量キャラでも吹っ飛びすぎない上限
const PUSH_STUN_TICKS := 30  # 気絶(ガードブレイク)時の吹っ飛び=自陣の壁際まで届く大出力
const FLINCH_TICKS := 24   # ジャストアタック被弾のしりもち(butt-drop)時間
const BURN_TICKS := 60     # 燃えるアタック被弾後の炎上表示時間
const KNOCKBACK_PX := 8    # しりもちで後ろへ滑る初速(px/tick)
const KNOCK_AIR_UP_PX_S := 200  # 空中被弾の浮き上がり(吹っ飛ばされ感の打ち上げ)

const INTENT_GROUND_RECEIVE := 0
const INTENT_GROUND_TOSS := 1
const INTENT_GROUND_FORWARD := 2
const INTENT_AIR_SPIKE := 3
const INTENT_AIR_TOSS := 4
const INTENT_AIR_BLOCK := 5
# 旧名は既存の表示・特性テストとの互換用。同じ空中トス分類へ統合した。
const INTENT_AIR_TOSS_UP := INTENT_AIR_TOSS
const INTENT_AIR_TOSS_SIDE := INTENT_AIR_TOSS
const INTENT_AIR_FEINT := INTENT_AIR_TOSS

static func team_of(i: int) -> int:
	return SimStateScript.team_of(i)

static func _classify_intent(on_ground: int, input: int, d2: int,
		player_reach: int, serve_strike: bool) -> Array[int]:
	var hdir: int = 0
	if input & IN_LEFT:
		hdir -= 1
	if input & IN_RIGHT:
		hdir += 1
	var up: int = 1 if input & IN_UP else 0
	if on_ground == 1:
		if input & IN_DOWN:
			return [INTENT_GROUND_RECEIVE, hdir, 0, 0]
		var dive_dir: int = 0
		var edge: int = player_reach * 3 / 4
		if hdir != 0 and not serve_strike and d2 >= 0 and d2 > edge * edge:
			dive_dir = hdir
		return [INTENT_GROUND_TOSS, hdir, 0, dive_dir]
	if up == 1:
		return [INTENT_AIR_BLOCK, hdir, up, 0]
	if input & IN_DOWN:
		return [INTENT_AIR_SPIKE, hdir, up, 0]
	return [INTENT_AIR_TOSS, hdir, up, 0]

static func _mura_power_pct(s, actor: int, char_id: int) -> int:
	if not Chars.has_trait(char_id, Chars.Profile.TRAIT_MURA):
		return 100
	var roll: int = _trait_roll_pct(s, actor, SALT_MURA)
	if roll < 10:
		return 50
	if roll < 90:
		return 100
	return 150

static func _toss_apex_pct(s, actor: int, char_id: int) -> int:
	if not Chars.has_trait(char_id, Chars.Profile.TRAIT_TOSS_BAD):
		return 100
	return 70 if _trait_roll_pct(s, actor, SALT_TOSS_BAD) < 30 else 100

static func apex_height(launch_vy: int, gravity: int) -> int:
	var vy: int = launch_vy
	var y: int = 0
	var min_y: int = 0
	for tick in 600:
		vy += gravity
		y += vy
		min_y = mini(min_y, y)
		if vy >= 0:
			break
	return -min_y

static func toss_vy_for_apex_pct(normal_vy: int, gravity: int, apex_pct: int) -> int:
	if apex_pct >= 100 or normal_vy >= 0:
		return normal_vy
	var target: int = apex_height(normal_vy, gravity) * apex_pct / 100
	var lo: int = 0
	var hi: int = -normal_vy
	var best: int = 0
	var best_error: int = target
	while lo <= hi:
		var mid: int = (lo + hi) / 2
		var height: int = apex_height(-mid, gravity)
		var error: int = absi(height - target)
		if error < best_error:
			best = mid
			best_error = error
		if height < target:
			lo = mid + 1
		else:
			hi = mid - 1
	return -best

static func toss_target_x(team: int, hdir: int, cfg) -> int:
	var toward_net: int = 1 if team == 0 else -1
	var own_back: int = FP.from_int(cfg.toss_zone_back_px) if team == 0 \
		else cfg.court_width - FP.from_int(cfg.toss_zone_back_px)
	var own_front: int = FP.from_int(cfg.toss_zone_front_px) if team == 0 \
		else cfg.court_width - FP.from_int(cfg.toss_zone_front_px)
	var opponent_front: int = cfg.court_width - FP.from_int(cfg.toss_zone_front_px) \
		if team == 0 else FP.from_int(cfg.toss_zone_front_px)
	if hdir == -toward_net:
		return own_back
	if hdir == toward_net:
		return opponent_front
	return own_front

static func air_target_x(team: int, hdir: int, cfg) -> int:
	var toward_net: int = 1 if team == 0 else -1
	var enemy_front: int = cfg.court_width - FP.from_int(cfg.toss_zone_front_px) \
		if team == 0 else FP.from_int(cfg.toss_zone_front_px)
	var enemy_back: int = cfg.court_width - FP.from_int(cfg.toss_zone_back_px) \
		if team == 0 else FP.from_int(cfg.toss_zone_back_px)
	if hdir == -toward_net:
		return enemy_front
	if hdir == toward_net:
		return enemy_back
	return (enemy_front + enemy_back) / 2

static func _flight_ticks(start_y: int, launch_vy: int, target_y: int, gravity: int) -> int:
	var y: int = start_y
	var vy: int = launch_vy
	for tick in 600:
		vy += gravity
		y += vy
		if y >= target_y and vy > 0:
			return tick + 1
	return 0

static func toss_aim_vx(start_x: int, start_y: int, launch_vy: int,
		target_x: int, cfg) -> int:
	var ticks: int = _flight_ticks(start_y, launch_vy,
		cfg.floor_y - cfg.ball_radius, cfg.gravity)
	return (target_x - start_x) / ticks if ticks > 0 else 0

static func trajectory_x_at_y(start_x: int, start_y: int, vx: int, vy: int,
		target_y: int, cfg) -> int:
	var ticks: int = _flight_ticks(start_y, vy, target_y, cfg.gravity)
	return start_x + vx * ticks

static func reach_for_intent(char_id: int, base_reach: int, intent_kind: int) -> int:
	if intent_kind != INTENT_GROUND_RECEIVE:
		return base_reach
	if Chars.has_trait(char_id, Chars.Profile.TRAIT_RECEIVE_GOOD):
		return base_reach * 115 / 100
	if Chars.has_trait(char_id, Chars.Profile.TRAIT_RECEIVE_BAD):
		return base_reach * 85 / 100
	return base_reach

static func _special_for_input(p, input: int, cfg) -> int:
	if p.burnout_ticks > 0:
		return 0
	if not (input & IN_ABILITY1):
		return 0
	for super_id in Chars.SUPER_CATALOG:
		if not Chars.has_super(p.char_id, super_id):
			continue
		var entry: Dictionary = Chars.super_def(super_id)
		# スト6式使い切り: 1でも残っていれば発動し、コスト超過分は下限0へ丸める。
		if p.drive_gauge <= 0:
			continue
		var condition: int = int(entry.condition)
		if condition == Chars.CONDITION_GROUND_UP_ABILITY \
				and p.on_ground == 1 and (input & IN_UP) and not (input & IN_DOWN):
			return super_id
		if condition == Chars.CONDITION_AIR_DOWN_ABILITY_ABOVE_NET \
				and p.on_ground == 0 and (input & IN_DOWN) and not (input & IN_UP) \
				and p.y < cfg.net_top_y:
			return super_id
	return 0

# 同一tickのヒットは最大1回。リーチ内の候補から最も近い1人を選ぶ。
# 旧実装のインデックス後勝ちはネット際で右チームが常に競り勝ち、
# 負けた側も硬直だけ食らう不公平があった。
# 同距離ならボールがある側のチームを優先、それも同点ならインデックス小。全て整数比較で決定論
static func _resolve_hit(s, inputs: Array[int], cfg) -> int:
	# サーブの2段目(トス済み)はサーバー本人のみ打てる。それ以外のSERVE中は不可
	var serve_strike: bool = s.phase == SimStateScript.PHASE_SERVE and s.serve_tossed == 1
	if s.phase != SimStateScript.PHASE_RALLY and not serve_strike:
		return NO_HIT
	# サーブは一発で相手コートへ入れる(本物のバレー準拠)。打たれたサーブが
	# ネットを越えるまでは誰も触れない(味方の中継も、サーバー自身の2度打ちも不可)。
	# 越えずに自陣へ落ちればサーブミス=床判定で相手の得点になる
	if s.serve_flight == 1:
		return NO_HIT
	var side_team: int = 0 if s.ball_x < cfg.net_x else 1
	var best_i: int = -1
	var best_d2: int = 0
	for i in s.players.size():
		if serve_strike and i != SimStateScript._server_index(s):
			continue
		var input: int = inputs[i] if i < inputs.size() else 0
		var p = s.players[i]
		if not (input & IN_ACTION) and _special_for_input(p, input, cfg) == 0:
			continue
		if _is_block_input(p, input):
			continue
		if _is_active_block(s, i, input, cfg):
			continue
		if p.hit_cooldown > 0 or p.stun > 0 or p.quake_stun > 0:
			continue
		var dx: int = s.ball_x - p.x
		var dy: int = s.ball_y - p.y
		# 楕円判定: 横はreach、縦はreach_up(頭のかなり上で打てる違和感の抑制)。
		# dyをreach/reach_up倍して円判定に正規化する。
		# オーバーフロー検討: dx最大640<<16≈4.2e7、二乗≈1.8e15 < int64上限9.2e18で安全
		var dy_n: int = dy * cfg.player_reach / cfg.player_reach_up
		var d2: int = dx * dx + dy_n * dy_n
		var intent: Array[int] = _classify_intent(
			p.on_ground, input, d2, cfg.player_reach, serve_strike)
		var reach: int = reach_for_intent(p.char_id, cfg.player_reach, intent[0])
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
		return 1 - team_of(best_i) if s.touches > cfg.max_touches else HIT_NO_POINT
	return NO_HIT

static func _is_block_input(p, input: int) -> bool:
	return p.on_ground == 0 and (input & IN_ACTION) != 0 and (input & IN_UP) != 0

static func _is_active_block(s, i: int, input: int, cfg) -> bool:
	if s.phase != SimStateScript.PHASE_RALLY or s.serve_flight == 1:
		return false
	var team: int = team_of(i)
	var p = s.players[i]
	if s.last_touch_team != 1 - team or not _is_block_input(p, input):
		return false
	if absi(p.x - cfg.net_x) > FP.from_int(60):
		return false
	var incoming_dir: int = -1 if team == 0 else 1
	return s.ball_vx != 0 and signi(s.ball_vx) == incoming_dir

static func _drive_damage_for_attack(attack_kind: int, cfg) -> int:
	if attack_kind == SimStateScript.BALL_ATTACK_NORMAL:
		return cfg.drive_gauge_stock
	if attack_kind == SimStateScript.BALL_ATTACK_JUST:
		return cfg.drive_gauge_stock * 2
	return 0

static func _spend_drive(p, amount: int, cfg) -> void:
	var before: int = p.drive_gauge
	p.drive_gauge = maxi(p.drive_gauge - amount, 0)
	if p.drive_gauge < before:
		p.drive_recovery_delay = cfg.drive_recovery_delay_ticks
	if amount > 0 and p.drive_gauge == 0 and p.burnout_ticks == 0:
		p.burnout_ticks = cfg.burnout_recovery_ticks
		p.drive_recovery_progress = 0

static func _burnout_guard_damage(p, damage: int) -> int:
	return damage * 3 / 2 if p.burnout_ticks > 0 else damage

static func _apply_hit(s, i: int, cfg, input: int, d2: int = -1) -> void:
	var p = s.players[i]
	var team: int = team_of(i)
	var dir: int = SimStateScript._dir_of_team(team)
	var serve_strike: bool = s.phase == SimStateScript.PHASE_SERVE and s.serve_tossed == 1
	var special: int = _special_for_input(p, input, cfg)
	var incoming_flame: bool = s.ball_flame == 1
	var intent: Array[int] = _classify_intent(
		p.on_ground, input, d2, cfg.player_reach, serve_strike)
	var intent_kind: int = intent[0]
	var hdir: int = intent[1]
	var incoming_attack_kind: int = s.ball_attack_kind
	var incoming_guard_damage: int = s.ball_guard_damage
	var incoming_defense_class: int = s.ball_defense_class
	var incoming_unblockable: bool = incoming_defense_class == Chars.DEFENSE_UNBLOCKABLE
	var opposing_attack: bool = s.last_touch_team >= 0 \
		and s.last_touch_team != team \
		and (incoming_attack_kind != SimStateScript.BALL_ATTACK_NONE \
			or incoming_defense_class != Chars.DEFENSE_NONE)
	var opposing_drive_attack: bool = opposing_attack \
		and incoming_attack_kind != SimStateScript.BALL_ATTACK_NONE
	var is_attack_return: bool = opposing_attack \
		and intent_kind == INTENT_AIR_SPIKE
	# 耐久力(ガード)システム: パワーボールを受けると耐久力が削れる。
	# 静止した下レシーブ構えからのジャストレシーブだけが削りを無効化する。
	# 回復はラチェット原則により全廃。通常スパイクはノーダメージ。
	# 耐久力が尽きた瞬間にスタン(倒れて動けない)し、満タンへ戻る(気絶サイクル)。
	# 判定はball_powerを消費する前に読む
	# スイート判定(芯)は全用途共通: 耐久力の回復/削り、スパイクのパワー化、
	# そして「芯で捉えたボールは慣性に流されない」(慣性が30%→10%に落ちる)
	# ジャスト窓の広さ%: 0でそのキャラはジャスト不可(数値で個性を表現)
	var sweet_r: int = cfg.player_reach * cfg.spike_sweet_pct \
		* Chars.stat(p.char_id, "just_window") / (100 * 100)
	var sweet: bool = d2 >= 0 and d2 <= sweet_r * sweet_r
	if special != 0:
		sweet = true  # 必殺技は芯位置によらず、成立すれば常に同じ技になる
	if p.burnout_ticks > 0:
		sweet = false
	var just_receive: bool = opposing_attack \
		and intent_kind == INTENT_GROUND_RECEIVE \
		and p.receive_stance > 0 \
		and p.vx == 0 and (input & (IN_LEFT | IN_RIGHT)) == 0 \
		and p.burnout_ticks == 0 and not incoming_unblockable
	if opposing_drive_attack and intent_kind == INTENT_GROUND_RECEIVE \
			and not just_receive:
		_spend_drive(p, _drive_damage_for_attack(incoming_attack_kind, cfg), cfg)
	if just_receive:
		p.just_receive_flash = 30
		p.just_receive_event += 1
		s.hit_freeze = maxi(s.hit_freeze, 10)
		# タイミング成功は芯受けと同じ制御報酬を得る。
		# 慣性カットに加え、パワー球のmangled化・よろけ・吹き飛びを防ぐ。
		sweet = true
	if intent_kind == INTENT_GROUND_RECEIVE and not just_receive \
			and not incoming_flame:
		sweet = false
	var inertia: int = cfg.hit_inertia_just_num if sweet else cfg.hit_inertia_num
	# 支配権切替: 緩い球(閾値未満)は慣性ゼロ=完全に狙い通り打てる。
	# 強い球だけが「ぎりぎり捕球」で勢いに流される(リアルバレー準拠)
	var in_sp2: int = s.ball_vx * s.ball_vx + s.ball_vy * s.ball_vy
	if in_sp2 < cfg.inertia_min_speed * cfg.inertia_min_speed:
		inertia = 0
	# 反動受け流し%(トス技術・物理面): 高いほど入射の勢いを殺す(200で完全に殺す)。
	# 100=標準(現行の慣性反射のまま)。ジャストの慣性カットは別枠で全キャラ共通
	inertia = maxi(inertia * (200 - Chars.stat(p.char_id, "absorb")) / 100, 0)
	# サーブは自分で上げた球を打つため、相手打球用の入射反発を差し引かない。
	if serve_strike:
		inertia = 0
	# パワーボールを芯を外して触ると返球の制御を失う(狙い30%+全反射)。
	# 「アタックはまともに返せない」原作精神: 対処はジャスト受けかブロックのみ
	var mangled := false
	var flame_received := false
	var flame_spike_return: bool = incoming_unblockable and intent_kind == INTENT_AIR_SPIKE
	var opposing_power: bool = s.last_touch_team >= 0 and s.last_touch_team != team \
		and s.ball_power == 1 and not flame_spike_return
	var unblockable_touch: bool = incoming_unblockable and s.ball_power == 1 \
		and intent_kind != INTENT_AIR_SPIKE
	if opposing_power or unblockable_touch:
		if sweet:
			if incoming_unblockable and intent_kind != INTENT_AIR_SPIKE:
				p.guard -= _burnout_guard_damage(p, incoming_guard_damage)
				if incoming_flame:
					p.burn = BURN_TICKS
				flame_received = true
				if p.guard <= 0:
					p.stun = cfg.stun_ticks
					p.guard = p.guard_max
					s.hit_freeze = 10
					var flame_back: int = -1 if team == 0 else 1
					p.push = flame_back * PUSH_STUN_TICKS
		else:
			mangled = true
			# パワーボールを芯を外して受けたら必ずよろけ(小スタン)。
			# 耐久力まで尽きたら本スタン(長い方が優先)
			var guard_damage: int = incoming_guard_damage
			if incoming_unblockable and intent_kind != INTENT_AIR_SPIKE:
				if incoming_flame:
					p.burn = BURN_TICKS
				flame_received = true
			guard_damage = _burnout_guard_damage(p, guard_damage)
			p.guard -= guard_damage
			# ジャストアタック被弾: 後ろ(自陣側)へノックバックし、しりもち。
			# 後ろ=相手と反対 = チーム0なら左(-1), チーム1なら右(+1)
			var back: int = -1 if team == 0 else 1
			# 重さ%で伸縮: 重量級はどっしり、軽量級は大きく飛ばされる
			p.vx = back * FP.from_int(KNOCKBACK_PX) * 100 / Chars.stat(p.char_id, "weight")
			# 空中被弾は「打ち上げられて吹っ飛ぶ」: 軽い浮きを与え滞空を延ばす
			# (滞空中はしりもち減衰が緩いので後方への飛距離も伸びる)
			if p.on_ground == 0:
				p.vy = mini(p.vy, -FP.from_int(KNOCK_AIR_UP_PX_S) / cfg.tick_rate)
			if p.guard <= 0:
				p.stun = cfg.stun_ticks
				p.guard = p.guard_max
				s.hit_freeze = 10  # 気絶=一番の見せ所。167ms止めて「効いた」を刻む
				# 決着の一撃: 自陣の壁際まで吹っ飛ばされて気絶する(壁クランプで止まる)。
				# 重さ%は掛けない=誰でも壁まで飛ぶフィニッシュ演出(浮きは共通処理が担う)
				p.push = back * PUSH_STUN_TICKS
			else:
				p.flinch = FLINCH_TICKS  # しりもち(耐久が残ってても被弾リアクション)
				s.hit_freeze = maxi(s.hit_freeze, 3)
	s.ball_power = 0
	s.ball_attack_kind = SimStateScript.BALL_ATTACK_NONE
	s.ball_guard_damage = 0
	s.ball_defense_class = Chars.DEFENSE_NONE
	if flame_received:
		s.ball_flame = 0
	if special != 0:
		_spend_drive(p, int(Chars.super_def(special).gauge_cost), cfg)
	# 制御喪失時: 狙い成分を大幅に削り、入射の反発を100%にする(弾かれるだけの絵)
	var aim_pct: int = 100
	if mangled:
		aim_pct = MANGLE_AIM_PCT
		inertia = cfg.hit_inertia_den
	var toss_good: bool = Chars.has_trait(p.char_id, Chars.Profile.TRAIT_TOSS_GOOD)
	var toss_bad: bool = Chars.has_trait(p.char_id, Chars.Profile.TRAIT_TOSS_BAD)
	if p.on_ground == 1:
		# 地上は下+ボタンだけがレシーブ。それ以外は横3種のトス。
		var desired_vx: int = 0
		var desired_vy: int = 0
		if intent_kind == INTENT_GROUND_TOSS:
			desired_vy = -cfg.bump_up_speed
			desired_vx = toss_aim_vx(s.ball_x, s.ball_y, desired_vy,
				toss_target_x(team, hdir, cfg), cfg)
			if intent[3] != 0:
				p.dive = hdir * cfg.hit_cooldown_ticks  # 表示層の飛びつき演出用
			p.hit_kind = 1
		else:
			# 下レシーブは既存どおり制御不能になり得る受け軌道。
			desired_vy = -cfg.bump_up_speed
			desired_vx = dir * cfg.bump_fwd_speed
			p.hit_kind = 0
		var is_ground_toss: bool = intent_kind == INTENT_GROUND_TOSS
		if is_ground_toss:
			if toss_bad:
				desired_vy = toss_vy_for_apex_pct(desired_vy, cfg.gravity,
					_toss_apex_pct(s, i, p.char_id))
			if toss_good:
				desired_vx = toss_aim_vx(s.ball_x, s.ball_y, desired_vy,
					toss_target_x(team, hdir, cfg), cfg)
		if special == Chars.SUPER_GHOST_BALL:
			s.ball_ghost = 1
			var ghost_def: Dictionary = Chars.super_def(special)
			s.ball_guard_damage = int(ghost_def.power)
			s.ball_defense_class = int(ghost_def.defense_class)
		# 慣性反映: 入射ボールの勢いを殺しきれず一部が反発して狙いに乗る。
		# 強い入射ほど狙いから逸れる(真上に受けても前へずれる、強打は高く跳ねる)。
		# 反発なので入射速度を符号反転して加える。RHSは代入前の入射値を読む
		s.ball_vx = desired_vx * aim_pct / 100 \
			if toss_good and is_ground_toss \
			else desired_vx * aim_pct / 100 - s.ball_vx * inertia / cfg.hit_inertia_den
		# トスの高さは入力と技能だけで決める。素レシーブは従来どおり縦の勢いも返す。
		if p.hit_kind == 0:
			s.ball_vy = desired_vy * aim_pct / 100 - s.ball_vy * inertia / cfg.hit_inertia_den
		else:
			s.ball_vy = desired_vy * aim_pct / 100
	elif intent_kind == INTENT_AIR_SPIKE:
		# 空中+下: アタック(叩き下ろす)。ジャストミート(ボールがスイートスポット=
		# リーチのspike_sweet_pct%以内)ならメテオ級: 速度ボーナス+パワーボール化。
		# 原作観察点14「タイミングで玉の威力やスタン値が上がる」の芯。
		# 打ち分け: 下のみ=鋭角(手前に鋭く落ちる。近距離でないと自陣落ちのリスク)、
		# 下+横=緩角(遠くまで届くが軌道が浅く取られやすい)。飛ぶ向きは常にネット方向。
		# 空中アタックにも地上と同じ慣性反射がかかる: 上がり際のボールを叩けば
		# 反発が乗って鋭く速く、落ち際なら浮いて深く飛ぶ=打つタイミングが着弾を変える。
		# ジャストミート(芯)なら慣性が10%に落ち、狙い通りに飛ぶ
		var pct: int = cfg.spike_normal_pct
		var drive_just_attack: bool = sweet and special == 0 and not is_attack_return
		if drive_just_attack:
			_spend_drive(p, cfg.drive_gauge_stock / 2, cfg)
		if sweet:
			# ジャスト報酬%: パワー倍率にキャラ%を掛ける(パワー型の見せ場)
			pct = cfg.spike_power_pct * Chars.stat(p.char_id, "just_reward") / 100
			s.ball_power = 1
			# ジャストスマッシュ=最大の見せ所。短い瞬止(5tick=83ms)で「止め」を作った直後、
			# スローモーション12tick(1/3速)でボールが撃ち出される様をスロー再生する。
			# 18tickは過剰との指摘で12へ短縮(スマブラの決めカットより軽め)
			s.hit_freeze = maxi(s.hit_freeze, 5)
			s.slow_ticks = maxi(s.slow_ticks, 12)
			# 反作用: 撃った本人がネットと逆へ小さく押し返される(威力の説得力+
			# ネット際連発への自然な小さな代償)。量は重さ%で伸縮
			p.push = -dir * mini(PUSH_MAX_TICKS,
				PUSH_ATK_TICKS * 100 / Chars.stat(p.char_id, "weight"))
		else:
			# 通常アタックの瞬止を4tick=67msに強化(2tickでは打感が伝わらないとの指摘)
			s.hit_freeze = maxi(s.hit_freeze, 4)
		pct = pct * Chars.stat(p.char_id, "atk") / 100  # アタック威力%
		pct = pct * _mura_power_pct(s, i, p.char_id) / 100
		var svx: int
		var svy: int
		var relative_hdir: int = hdir * dir
		if relative_hdir < 0:
			svy = cfg.spike_steep_vy * pct / 100
		elif relative_hdir > 0:
			svy = cfg.spike_vy * pct / 100
		else:
			svy = (cfg.spike_steep_vy + cfg.spike_vy) * pct / 200
		svx = toss_aim_vx(s.ball_x, s.ball_y, svy,
			air_target_x(team, hdir, cfg), cfg)
		s.ball_vx = svx * aim_pct / 100 - s.ball_vx * inertia / cfg.hit_inertia_den
		s.ball_vy = svy * aim_pct / 100 - s.ball_vy * inertia / cfg.hit_inertia_den
		if special == Chars.SUPER_FLAME_ATTACK:
			s.ball_flame = 1
		elif incoming_flame:
			# 燃える球をアタックで打ち返した時だけ、効果とパワーを通常球へ戻す。
			s.ball_flame = 0
			s.ball_power = 0
		if special == 0 and not is_attack_return:
			s.ball_attack_kind = SimStateScript.BALL_ATTACK_JUST \
				if drive_just_attack else SimStateScript.BALL_ATTACK_NORMAL
		if special != 0:
			var special_def: Dictionary = Chars.super_def(special)
			s.ball_guard_damage = int(special_def.power)
			s.ball_defense_class = int(special_def.defense_class)
		else:
			s.ball_guard_damage = cfg.power_guard_damage_for_rank(
				Chars.rank(p.char_id, Chars.Profile.ABILITY_POWER)) if sweet else 0
			s.ball_defense_class = Chars.DEFENSE_NONE
	else:
		s.ball_guard_damage = 0
		s.ball_defense_class = Chars.DEFENSE_NONE
		# 空中ニュートラル段は横3種とも敵陣の前面/中央/後面へトスする。
		var avy: int = -cfg.toss_fwd_vy
		var avx: int = toss_aim_vx(s.ball_x, s.ball_y, avy,
			air_target_x(team, hdir, cfg), cfg)
		var is_air_toss := true
		var toss_bad_low: bool = false
		if is_air_toss:
			if toss_bad:
				var apex_pct: int = _toss_apex_pct(s, i, p.char_id)
				toss_bad_low = apex_pct < 100
				if toss_bad_low:
					avy = toss_vy_for_apex_pct(avy, cfg.gravity, apex_pct)
			if toss_good:
				avx = toss_aim_vx(s.ball_x, s.ball_y, avy,
					air_target_x(team, hdir, cfg), cfg)
		s.ball_vx = avx * aim_pct / 100 if toss_good and is_air_toss \
			else avx * aim_pct / 100 - s.ball_vx * inertia / cfg.hit_inertia_den
		s.ball_vy = avy * aim_pct / 100 if is_air_toss and (toss_good or toss_bad_low) \
			else avy * aim_pct / 100 - s.ball_vy * inertia / cfg.hit_inertia_den
	p.hit_cooldown = cfg.hit_cooldown_ticks
	s.last_hit_tick = s.tick
	if s.last_touch_team == team:
		s.touches += 1
	else:
		s.touches = 1
	s.last_touch_team = team

# ばらつき用の決定論乱数: stateless keyed hash(sim_cpuと同方式)。-100..100を返す。
# キーはヒット確定tick+actor+salt=1ヒットにつき1抽選、両ピア同値、ロールバック再現
static func _keyed_hash(s, actor: int, salt: int) -> int:
	var z: int = s.tick + salt * 1000003 + (actor + 1) * 998244353
	z = (z ^ (z >> 16)) * 2246822519
	z = (z ^ (z >> 13)) * 3266489917
	return (z ^ (z >> 16)) & 0x7FFFFFFFFFFFFFFF

static func _scatter(s, actor: int, salt: int) -> int:
	return _keyed_hash(s, actor, salt) % 201 - 100

static func _trait_roll_pct(s, actor: int, salt: int) -> int:
	return _keyed_hash(s, actor, salt) % 100

# ブロック: ネット際の空中で上+アクションを押した時だけ成立する。
# 横方向は問わず、位置取りに加えて明示入力のタイミングを要求する。
# 反射は物理的に単純: 横速度を反転減衰(最低でもネット反発分は押し返す)、
# 縦はそのまま=強打は下向きのままアタッカー側へ突き刺さる(キルブロック)。
# サーブは飛行中ブロック不可(バレーのルール準拠)。ボールのパワーは
# ブロックでは消費されない(自分のメテオが跳ね返ってくるスリルは残す)
static func _ball_vs_block(s, cfg, inputs: Array[int]) -> void:
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
		var input: int = inputs[i] if i < inputs.size() else 0
		if not _is_active_block(s, i, input, cfg):
			continue
		if p.stun > 0 or p.hit_cooldown > 0 or p.quake_stun > 0:
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
		var incoming_guard_damage: int = s.ball_guard_damage
		var incoming_defense_class: int = s.ball_defense_class
		_spend_drive(p, _drive_damage_for_attack(s.ball_attack_kind, cfg), cfg)
		s.ball_attack_kind = SimStateScript.BALL_ATTACK_NONE
		s.ball_guard_damage = 0
		s.ball_defense_class = Chars.DEFENSE_NONE
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		if team == 0:
			s.ball_vx = maxi(s.ball_vx, cfg.net_repel)
		else:
			s.ball_vx = mini(s.ball_vx, -cfg.net_repel)
		# パワーボールを止めた時は腕越しに体が押し込まれる(小さな後退)。
		# 通常球のブロックは無反動=ブロックの強さは保つ
		if s.ball_power == 1:
			var back_dir: int = -1 if team == 0 else 1
			p.push = back_dir * mini(PUSH_MAX_TICKS,
				PUSH_BLK_TICKS * 100 / Chars.stat(p.char_id, "weight"))
			if incoming_defense_class == Chars.DEFENSE_UNBLOCKABLE:
				p.guard -= _burnout_guard_damage(p, incoming_guard_damage)
				if s.ball_flame == 1:
					p.burn = BURN_TICKS
				s.ball_flame = 0
				if p.guard <= 0:
					p.stun = cfg.stun_ticks
					p.guard = p.guard_max
					p.push = back_dir * PUSH_STUN_TICKS
					s.hit_freeze = maxi(s.hit_freeze, 10)
		s.last_touch_team = team
		s.touches = 1  # 原作どおりブロックもチームの1タッチに数える
		s.last_hit_tick = s.tick
		p.hit_cooldown = cfg.hit_cooldown_ticks
		s.hit_freeze = maxi(s.hit_freeze, 2)
		return
