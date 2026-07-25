extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

const TICKS := 3600

# 2段構えの決定論検証:
# (1) 同一入力2回実行のハッシュ一致 = プロセス内の非決定要素(グローバルRNG等)を検出
# (2) ゴールデンハッシュ = 挙動の意図しない変化を検出。マシンをまたげばfloat差異も
#     いずれ露見する。なお同一プロセス内のfloat混入は(1)では捕まらないため、
#     静的スキャン(test_no_float_in_sim.gd)が併走している
# ゴールデンは全チェックポイント(60tickごと+最終)の合成ハッシュで比較する。
# 最終ハッシュのみだとreset_rallyの状態正規化で途中の物理変化を見逃すため
# 物理を意図的に変更した場合はGOLDEN_COMBINED_HASHを新しい値に更新すること

# 2026-07-25 CPU入力列の変化により更新。実測値(代行環境で全スイート実行)。
# 変更の内訳:
#  1. sim_cpu.gd の三項式型エラー解消。_sweet_jump_plan が常に空配列を返して
#     _decide_positioning が中断していたのが、初めて正常動作するようになった
#  2. サーブ経路での IN_JUMP 保持。ジャンプが18pxのホップから135pxへ戻った
#  3. 打撃tickでの IN_JUMP 保持。打つ瞬間に可変ジャンプが失速していたのを止めた
#  4. 空中打撃の芯判定をこのtickの移動後の位置で行う先読み。
#     simulationは 入力→プレイヤー移動→ヒット判定 の順なので、移動前の座標で
#     判断すると常に1tick遅れて芯を通り過ぎていた
#
# 2026-07-25 (第2回) さらに以下の挙動変更を織り込んで再更新。実測値:
#  5. 地上レシーブの横速度を原作準拠の構造へ。前方固定バイアス(dir*40px/s)を廃し、
#     接触オフセット依存 + 決定論散り + 上限クランプにした。左右で打ち合ったときの
#     不動点(57.1px/s)が消え、CPU同士の無限往復ループが死んだ(「普通」得点 0→3)
#  6. CPU味方の役割分担。カバー距離を cpu_mate_spacing_px 化し、全プリセットに
#     AB_ROLES を付け、近すぎる非レシーバーは打撃入力を出さない
#     (「普通」同士で味方が32px以内にいる時間 28%→3%)
#  7. ネット越え判定の枝漏れ修正。below_top の枝が「越えた」判定を飲み込んでおり、
#     ネット上端より低い高さで横切った球が serve_flight=1 のまま残って
#     誰も触れなくなっていた(人間のアタックサーブがサービスエースになる不具合)
#  8. ネット衝突の掃引判定化。移動後の1点でなく1tickの経路が帯を横切るかで
#     判定するため、2040px/s以上の高速球がネットをすり抜けなくなった
#  9. サーブ球を受け手の初接触までブロック不可にする serve_ball フィールドを
#     SimState へ追加。state_hash が全intフィールドを畳むため、値が0でも
#     フィールドが増えれば全ハッシュがずれる
# 10. 壁反射とネット衝突で ball_attack_kind / ball_guard_damage をクリア。
#     勢いを失った球がアタック球の印を持ち続けなくなった
#
# 2026-07-25 (第3回) アタック速度の引き下げで再更新。実測値。
# 通常アタック 80→50%、ジャストアタック 110→80%。着弾点は変わらず(vxは
# 目標xから逆算されるため)、変わるのは球が届くまでの時間だけ。実測で
# ジャストの最速球が0.18秒→0.23秒、通常が0.23秒→0.28秒になった。
# 他の人に遊んでもらったところ「何もできない」状態だったという実プレイの
# フィードバックが根拠。人間の単純反応は0.20〜0.25秒で、旧ジャストの
# 0.18秒は反応不可能な領域にあった。
#
# 2026-07-25 (第4回) パワーランクによる速度差の試遊のため再更新。実測値。
# 基準を 通常50→33%、ジャスト80→53% へ下げ、POWER倍率[150,125,100,75,50]を
# 掛けたときランクAが従来の速度(通常50/ジャスト80相当)に来るようにした。
# あわせて PIYO の POWER を E、UMA の POWER を A へ振った。
#
# 2026-07-25 (第5回) 実プレイの結果さらに減速。実測値。
# パワーC基準を 通常33→25%、ジャスト53→40% へ。ユーザーが遊んで
# 「拾いやすく反応しやすくなって体験が良くなった、もっと遅くてもいい」と
# 判断したため。これでゲーム最速の球(パワーAのジャスト鋭角)が0.23→0.27秒になり、
# 人間が反応できない球がゲームから無くなる。
#
# 2026-07-25 (第6回) CPUの2件の修正で更新。実測値。
#  1. サーブ経路のジャンプキー保持からIN_ACTION条件を外した。打撃tickだけ
#     IN_JUMPが落ちて可変ジャンプが半減し、予測より低い位置で空振りしていた。
#     ラリー経路は既に条件なしで保持しており、そちらだけ直っていた。
#     実測: CARBY(ジャンプB)のサーブ失敗 88回中24回→0回、TOME(A) 3回→0回
#  2. 自チームのアタック球にCPUが打撃入力を出さないようにした。
#     味方のアタックを触ってトスに化けさせる不具合。
# 2026-07-25 (第7回) ジャストレシーブの構えに入る条件を、水平距離ではなく
# 「今立っている位置で楕円リーチにボールが入るか」に変えたためCPUの入力列が変わった。
# 実測: 最強は見送り62/928(6%)→46/928(4%)、16回中8回以上見送る着弾点は
# [344,364,452]→[344]。強いは90/928(9%)→82/928(8%)、同着弾点は
# [344,348,364,452]→[344,348]。
# 2026-07-25 (第8回) SimStateに3フィールド追加(human_team_mask / rally_seq /
# last_touch_idx)。加えて「相方が人間か」の判定を、操作スロット番号だけでなく
# 実際に人間がいるチームかで行うようにした。CPUだけの敵チームでは片方が
# 相方を人間と誤認して非対称な譲り規則を使っていた。実測値。
const GOLDEN_COMBINED_HASH := -184202542501962905

func _next_rand(s: int) -> int:
	# xorshift64。乱数も整数のみで作る
	s ^= s << 13
	s ^= s >> 7
	s ^= s << 17
	return s

func _run_once() -> Array[int]:
	# フルゲーム(サーブ→ラリー→得点→再サーブ)を人間2系統のランダム入力で回す。
	# 全入力ビット(0-127)を含み、切替・ヒット・トス照準・CPU相方も検証対象に入る
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	var hashes: Array[int] = []
	var rng := 123456789
	for t in TICKS:
		var inputs: Array[int] = []
		for i in 2:
			rng = _next_rand(rng)
			inputs.append(rng & 127)
		Simulation.tick(s, inputs, cfg)
		if t % 60 == 0:
			hashes.append(s.state_hash())
	hashes.append(s.state_hash())
	return hashes

func test_synctest_60_seconds() -> void:
	var a := _run_once()
	var b := _run_once()
	check_eq(a.size(), b.size(), "チェックポイント数が一致")
	var mismatch := -1
	for i in a.size():
		if a[i] != b[i]:
			mismatch = i
			break
	check_eq(mismatch, -1, "デシンクなし(検出indexは-1)")

func _combined(hashes: Array[int]) -> int:
	# チェックポイント群をFNV-1a 64bitで1本に畳む(state_hashと同じ方式)
	var h := -3750763034362895579
	for v in hashes:
		for i in 8:
			h ^= (v >> (i * 8)) & 0xFF
			h *= 1099511628211
	return h

func test_golden_hash_regression() -> void:
	var a := _run_once()
	check_eq(a.size(), 61, "チェックポイント数(60tickごと+最終)")
	check_eq(_combined(a), GOLDEN_COMBINED_HASH,
		"合成ゴールデンハッシュ一致(物理を意図的に変えた場合のみ更新する)")

func _run_endgame() -> Array[int]:
	# 3600tickの主走行はGAME_OVERに到達しないため、勝敗決定(デュース2点差)と
	# GAME_OVERフェーズの決定論はこの終盤戦シナリオで別途検証する
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	# 14-0開始: CPU同士は点の取り合いが交互に近く、僅差デュースだと決着しないため
	# 大差から確実に勝利遷移へ到達させる(左の1点で15点・2点差以上が確定する)
	s.score_l = cfg.points_to_win - 1
	var out: Array[int] = []
	var rng := 987654321
	for t in 3600:
		var inputs: Array[int] = []
		for i in 2:
			rng = _next_rand(rng)
			inputs.append(rng & 127)
		Simulation.tick(s, inputs, cfg)
		if t % 60 == 0:
			out.append(s.state_hash())
	out.append(s.state_hash())
	out.append(s.phase)
	out.append(s.winner)
	return out

func test_endgame_reaches_game_over_deterministically() -> void:
	var a := _run_endgame()
	check_eq(a[a.size() - 2], SimState.PHASE_GAME_OVER, "3600tick以内に勝敗が付く")
	check(a[a.size() - 1] >= 0, "勝者が確定している")
	var b := _run_endgame()
	var mismatch := -1
	for i in a.size():
		if a[i] != b[i]:
			mismatch = i
			break
	check_eq(mismatch, -1, "終盤戦デシンクなし(検出indexは-1)")
