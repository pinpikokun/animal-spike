# プレイヤーのsim状態(int)からアニメ名・向きを選ぶ純粋関数。
# 状態を読むだけ(副作用なし)。表示層だがテクスチャ非依存なのでヘッドレステスト可能。
extends RefCounted

# 優先順位: スタン=hurt(倒れ) > 空中=jump > 接地ヒット硬直=crouch > 移動=run > 静止=idle
static func anim_for(p) -> String:
	if p.stun > 0:
		return "hurt"
	if p.on_ground == 0:
		return "jump"
	if p.hit_cooldown > 0:
		return "crouch"
	if p.vx != 0:
		return "run"
	return "idle"

# チーム0(左)は右向き=反転なし、チーム1(右)は左向き=反転
static func flip_for_team(team: int) -> bool:
	return team == 1
