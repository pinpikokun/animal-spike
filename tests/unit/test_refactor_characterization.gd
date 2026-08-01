extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Chars := preload("res://src/sim/chars.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

const STANDARD_CHAR := 99

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.char_id = STANDARD_CHAR
		p.y = cfg.floor_y
	s.players[0].x = cfg.net_x - FP.from_int(124)
	s.players[1].x = cfg.net_x - FP.from_int(49)
	s.players[2].x = cfg.net_x + FP.from_int(156)
	s.players[3].x = cfg.net_x + FP.from_int(46)
	return [s, cfg]

func _hit_snapshot(on_ground: int, input: int, d2: int, vx: int, vy: int, power: int = 0) -> Array[int]:
	var w: Array = _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = on_ground
	if on_ground == 0:
		p.y = cfg.floor_y - FP.from_int(80)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(10)
	s.ball_vx = vx
	s.ball_vy = vy
	s.ball_power = power
	s.ball_guard_damage = cfg.power_guard_damage_for_rank(
		Chars.Profile.RANK_C) if power == 1 else 0
	s.last_touch_team = 1 if power == 1 else -1
	HitResolver._apply_hit(s, 0, cfg, input | Simulation.IN_ACTION, d2)
	return [p.hit_kind, p.dive, s.ball_vx, s.ball_vy, s.ball_power, p.guard, p.flinch]

func test_intent_classification_table() -> void:
	# 操作原作回帰後の論理ベースライン:
	# 地上は下だけレシーブ、それ以外は横3トス。空中は下=攻撃、なし=トス、上=ブロック。
	var w: Array = _world()
	var cfg = w[1]
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var edge: int = cfg.player_reach * 4 / 5
	var edge_d2: int = edge * edge
	var rows := [
		[1, 0, near_d2, 1, 0],
		[1, Simulation.IN_UP, near_d2, 1, 0],
		[1, Simulation.IN_RIGHT, near_d2, 1, 0],
		[1, Simulation.IN_RIGHT, edge_d2, 1, 0],
		[1, Simulation.IN_UP | Simulation.IN_RIGHT, near_d2, 1, 0],
		[0, Simulation.IN_DOWN, near_d2, 0, 0],
		[0, Simulation.IN_RIGHT, near_d2, 0, 0],
		[0, 0, near_d2, 0, 0],
	]
	for row in rows:
		var out := _hit_snapshot(row[0], row[1], row[2], 0, 0)
		check_eq(out[0], row[3], "意図分類 hit_kind: %s" % [row])
		check_eq(1 if out[1] != 0 else 0, row[4], "意図分類 dive: %s" % [row])

func test_intent_classifier_is_pure_and_complete() -> void:
	# 値はHitResolverの公開意図定数に対応する新体系の確定値。速度スナップショットと
	# 異なり実測不要で、地上ニュートラル=[トス,横なし,上照準なし,diveなし]が正しい。
	var cfg = SimConfig.new()
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var edge: int = cfg.player_reach * 4 / 5
	var edge_d2: int = edge * edge
	var rows := [
		[1, 0, near_d2, false, [1, 0, 0, 0]],
		[1, Simulation.IN_DOWN, near_d2, false, [0, 0, 0, 0]],
		[1, Simulation.IN_UP, near_d2, false, [1, 0, 0, 0]],
		[1, Simulation.IN_RIGHT, near_d2, false, [1, 1, 0, 0]],
		[1, Simulation.IN_RIGHT, edge_d2, false, [1, 1, 0, 0]],
		[1, Simulation.IN_RIGHT, edge_d2, true, [1, 1, 0, 0]],
		[1, Simulation.IN_LEFT | Simulation.IN_UP, near_d2, false, [1, -1, 0, 0]],
		[0, Simulation.IN_DOWN, near_d2, false, [3, 0, 0, 1]],
		[0, Simulation.IN_DOWN | Simulation.IN_RIGHT, near_d2, false, [3, 1, 0, 1]],
		[0, Simulation.IN_UP, near_d2, false, [3, 0, 1, 0]],
		[0, Simulation.IN_RIGHT, near_d2, false, [4, 1, 0, 0]],
		[0, 0, near_d2, false, [4, 0, 0, 0]],
	]
	for row in rows:
		var actual: Array[int] = HitResolver._classify_intent(
			row[0], row[1], row[2], cfg.player_reach, row[3])
		check_eq(actual, row[4], "純粋意図分類: %s" % [row])

func test_output_velocity_snapshot() -> void:
	# 実測待ち: 地上レシーブを含む行は新しい接触位置式により更新が必要。
	# アタック速度の意図的変更(ジャスト150→110%、通常100→80%)。2026-07-20設計会仕様
	# 固定パワー球はPOWER Cの絶対削り25を持つ。2026-07-20設計会仕様
	var w: Array = _world()
	var cfg = w[1]
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var outside_sweet: int = cfg.player_reach * cfg.player_reach
	var cases := [
		_hit_snapshot(1, 0, near_d2, 0, 0),
		_hit_snapshot(1, Simulation.IN_UP, outside_sweet, -FP.from_int(8), FP.from_int(12)),
		_hit_snapshot(1, Simulation.IN_RIGHT, outside_sweet, -FP.from_int(8), FP.from_int(12)),
		_hit_snapshot(0, Simulation.IN_DOWN, near_d2, 0, FP.from_int(8)),
		_hit_snapshot(0, Simulation.IN_DOWN | Simulation.IN_RIGHT, outside_sweet, -FP.from_int(8), -FP.from_int(4)),
		_hit_snapshot(0, 0, outside_sweet, -FP.from_int(8), FP.from_int(12)),
		_hit_snapshot(1, 0, outside_sweet, -FP.from_int(12), FP.from_int(8), 1),
	]
	check_eq(cases, [
		# 2026-07-26 自陣トスの着弾点を原作の値(248/136)へ戻したため、
		# 地上トスの横速度が変化した。敵陣への返球は別キーへ分離済みで不変。実測値。
		# 2026-07-30 味方標準トスを試遊開始値680px/sへ上げ、長い滞空でも同じ
		# 自陣目標へ着地するよう横速度を再計算。低トス再導入時はdocs/tasks/112.mdで再評価する。
		[1, 0, 73962, -742741, 0, 100, 0],
		[1, 0, 231248, -742741, 0, 100, 0],
		# 2026-07-26 敵陣への返球を固定速度式へ変えたため、
		# ネット方向トスの横速度と空中返球の縦速度が変化した。実測値。
		# 2026-07-29 1・2打目の空中トスを自陣前方狙いへ戻した。実測値。
		# 2026-07-26 (第2回) スパイクの横速度を打つ位置からの逆算をやめ、
		# 押した横キーごとの固定値にしたため空中打球の横速度が変化した。実測値。
		[1, 0, 208622, -567978, 0, 100, 0],
		[0, 0, 1018429, 100489, 1, 100, 0],
		[0, 0, 900027, 149640, 0, 100, 0],
		[0, 0, 90830, -513365, 0, 100, 0],
		[1, 0, 808620, -222822, 0, 75, 24],
	], "固定フィクスチャの整数出力速度")

func test_collision_order_hit_move_net_block() -> void:
	var w: Array = _world()
	var s = w[0]
	var cfg = w[1]
	var attacker = s.players[1]
	var blocker = s.players[3]
	attacker.on_ground = 0
	attacker.y = cfg.floor_y - FP.from_int(100)
	attacker.x = cfg.net_x - cfg.net_half_w - FP.from_int(8)
	blocker.on_ground = 0
	# このテストの目的は「ヒット→移動→ネット→ブロック」の同tick順序の検証であり、
	# ブロックの成立境界を測ることではない。以前は57pxとギリギリに置いていたため
	# アタック速度を80%→50%へ下げただけでブロックが不成立になりテストが壊れた。
	# 実測で成立するのは59px以上なので、余裕を見て範囲の中央に置く。
	blocker.y = cfg.floor_y - FP.from_int(65)
	blocker.x = cfg.net_x + FP.from_int(16)
	s.ball_x = attacker.x + FP.from_int(5)
	s.ball_y = attacker.y - FP.from_int(10)
	s.ball_vx = FP.from_int(2)
	s.ball_vy = 0
	Simulation.step(s, [0, Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		0, Simulation.IN_ACTION | Simulation.IN_LEFT], cfg)
	# 2026-07-25: アタック速度をジャスト110→80%、通常80→50%へ引き下げたため座標と
	# 速度が変化した。ブロックの成立自体(last_touch_team=1, touches=1, 両者cd=14)は
	# 変わっていないので、検証している同tick順序は保たれている。実測値。
	check_eq([s.ball_x, s.ball_y, s.ball_vx, s.ball_vy, s.last_touch_team,
		s.touches, attacker.hit_cooldown, blocker.hit_cooldown],
		# 2026-07-26 スパイクの横速度を固定値にしたため打球の速度が変化した。実測値。
		[19669538, 13897090, -926941, 134530, 1, 1, 14, 14],
		"同tickのヒット→移動→ネット→ブロック順")

func _chain_hashes() -> Array[int]:
	var w: Array = _world()
	var s = w[0]
	var cfg = w[1]
	var out: Array[int] = []
	var near_d2 := FP.from_int(2) * FP.from_int(2)
	var miss_d2: int = cfg.player_reach * cfg.player_reach

	# ジャストアタック。
	s.players[0].on_ground = 0
	s.players[0].y = cfg.floor_y - FP.from_int(80)
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, near_d2)
	out.append(s.state_hash())

	# パワーボールを芯外しレシーブし、ガード破壊まで踏む。
	s.players[2].guard = 1
	s.ball_power = 1
	s.last_touch_team = 0
	HitResolver._apply_hit(s, 2, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, miss_d2)
	out.append(s.state_hash())

	# 別のパワーボールをネット際でブロックする。
	s.phase = SimState.PHASE_RALLY
	s.players[3].x = cfg.net_x + FP.from_int(30)
	s.players[3].y = cfg.floor_y - FP.from_int(80)
	s.players[3].on_ground = 0
	s.players[3].hit_cooldown = 0
	s.ball_x = s.players[3].x
	s.ball_y = s.players[3].y - cfg.player_reach_up
	s.ball_vx = FP.from_int(12)
	s.ball_vy = FP.from_int(5)
	s.ball_power = 1
	s.last_touch_team = 0
	HitResolver._ball_vs_block(s, cfg, [0, 0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT])
	out.append(s.state_hash())

	# 帽子投げの溜めから発射まで進める。
	s.players[0].char_id = Chars.CHAR_MARIO
	s.players[0].has_hat = 1
	s.players[0].guard = s.players[0].guard_max
	s.players[0].throw = 0
	s.ball_x = cfg.net_x
	s.ball_y = FP.from_int(20)
	for t in 24:
		Simulation.step(s, [Simulation.IN_ABILITY1, 0, 0, 0], cfg)
		if t in [0, 8, 16, 23]:
			out.append(s.state_hash())
	return out

func test_hit_chain_physics_state_transition_golden() -> void:
	# _world() は SimState.new() だけを使い Simulation.tick() を通らないため、
	# 全過程で tick=0 / rng=0 / aitick=0 のまま進む。旧tick=0と新aitick=0の
	# 派生値は同一なので、これは物理・状態遷移の固定検査であり乱数源切替は検査対象外。
	# 2026-07-25: serve_ball フィールドを SimState へ追加したため全7値が変化した。
	# state_hash は全 int フィールドを畳むので、値が0でもフィールドが増えれば
	# すべてのハッシュがずれる。挙動の異常ではない。実測値。
	#
	# 2026-07-25 (第2回) 気絶時間を 180tick(3秒) から 240tick(4秒) へ変更したため
	# 2番目以降が変化した。この連鎖は2手目でガード破壊→気絶に入るので、
	# 気絶カウンタの初期値がそのまま state_hash に乗る。1番目(ジャストアタック)は
	# 気絶を通らないため変化していない。実測値。
	#
	# 2026-07-25 (第3回) アタック速度の引き下げ(ジャスト110→80%、通常80→50%)で
	# 1番目(ジャストアタック)と2番目が変化した。3番目以降はブロックと帽子で、
	# アタック速度を通らないため不変。実測値。
	#
	# 2026-07-25 (第4回) SimStateに human_team_mask / rally_seq / last_touch_idx を
	# 追加したため全て変化した。state_hash は全intフィールドを畳むので、
	# 値が0や-1でもフィールドが増えれば全ハッシュがずれる。実測値。
	# 2026-07-26 コート幅を448→576、ネットを224→288へ広げたため全て変化した。
	# 選手・ボールの座標がすべて動くので、物理を変えた場合の正当な更新である。実測値。
	# 2026-07-26 (第2回) 原作の待機位置表を導入し、SimStateへ打球回数カウンタと
	# 役マスクを追加したため全て変化した。実測値。
	check_eq(_chain_hashes(), [
		# 2026-07-26 (第3回) スパイクの横速度を固定値にしたため変化した。実測値。
		# 2026-07-26 (第4回) CPUの反応遅延を原作準拠(18/12/6/0コマ)へ変えたため
		# CPUの入力列が全区間で変わった。実測値。
		# 2026-07-28 (第5回) #88a で SimState へ rng と aitick を追加したため
		# 全7値が変化した。state_hash は全intフィールドを畳むので、状態の形が
		# 変われば必ずずれる。挙動の異常ではない。440本中、状態ハッシュを固定する
		# この検査と test_sync.gd の test_golden_hash_regression の2本だけが赤で、
		# 残り438本は緑。双子検査でseed差がゲームプレイへ漏れていないことも
		# 確認済み。実測値。
		# 2026-07-28 (第6回) #88b-1 で役割抽選を原作方式のステートフル消費へ移した。
		# ラリー開始時にチーム0→チーム1の順で rng を2回進め、%9 を SimState へ保存する
		# (原作 role_assign 0xBB40 の写し)。役割の決まり方が変わるのでCPUの入力列が
		# 動き、全7値が変化した。分岐表は1文字も変えていない。442本中、状態ハッシュを
		# 固定するこの検査と test_sync.gd の2本だけが赤で、残り440本は緑。実測値。
		# 2026-07-30 横っ飛び用のゼロ初期値3欄を全プレイヤーへ追加。物理と入力列は
		# まだ変えず、直列化レイアウトだけが変わったため全7値を実測更新。
		4623648450772278388,
		# 2026-08-01 地上トス・レシーブの防御差とガードブレイク反応を再設計した実測値。
		-7010670360507235728,
		-3873476771839857659,
		408311841621663377,
		9216286066875272257,
		-4267536951168107750,
		3273224963375681733,
	], "ジャスト→芯外し→気絶→ブロック→帽子の第2ゴールデン")
