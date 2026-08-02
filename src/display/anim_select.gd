# プレイヤーのsim状態(int)からアニメ名・向きを選ぶ純粋関数。
# 状態を読むだけ(副作用なし)。表示層だがテクスチャ非依存なのでヘッドレステスト可能。
extends RefCounted

const SimStateScript := preload("res://src/sim/sim_state.gd")

# 優先順位: 被弾 > 横っ飛び > 固有動作 > ブロック > 空中打球 > 空中 > 接地実打
#         > レシーブ構え > 移動 > 静止
static func anim_for(p) -> String:
	if p.stun > 0:
		return "stun"
	if p.flinch > 0:
		return "hurt"
	if p.dive != 0:
		return "dive"
	if p.hip != 0:
		return "hipdrop"
	if p.cling != 0:
		return "wallcling"
	if p.hit_cooldown > 0 and p.hit_kind == SimStateScript.HIT_KIND_BLOCK:
		return "block"
	if p.on_ground == 0:
		if p.hit_cooldown > 0:
			if p.hit_kind == SimStateScript.HIT_KIND_ATTACK:
				return "attack"
			return "toss"
		return "jump"
	if p.brake != 0:
		return "brake"
	if p.hit_cooldown > 0:
		match p.hit_kind:
			SimStateScript.HIT_KIND_TOSS:
				return "toss"
			SimStateScript.HIT_KIND_FORWARD:
				return "toss_fwd"
			_:
				return "ground_swing"
	if p.on_ground == 1 and p.receive_stance != 0:
		return "receive_stance"
	if p.vx != 0:
		return "run"
	return "idle"

# 原作セル11,10,7,0の4コマをsim経過から固定選択する。
static func dive_frame_for(p) -> int:
	return clampi(int(p.dive_age_ticks / 2), 0, 3)

# 原作セル3,4,5を2tickずつ進めた後、4,5を交互に出す。
static func attack_frame_for(p, total_ticks: int) -> int:
	var age := maxi(total_ticks - p.hit_cooldown, 0)
	if age < 6:
		return int(age / 2)
	return 1 + int((age - 6) / 2) % 2

# 原作セル9,8,7を2tickずつ進め、最後のセル6を硬直終了まで保つ。
static func ground_swing_frame_for(p, total_ticks: int) -> int:
	var age := maxi(total_ticks - p.hit_cooldown, 0)
	return clampi(int(age / 2), 0, 3)

static func dive_rotation_for(p) -> float:
	return float(signi(p.dive)) * 0.9

# チーム0(左)は右向き=反転なし、チーム1(右)は左向き=反転
static func flip_for_team(team: int) -> bool:
	return team == 1
