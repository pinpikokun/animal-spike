# 入力ビット定数の正本。シミュレーション層の複数ファイルから参照される
extends RefCounted

const IN_LEFT := 1
const IN_RIGHT := 2
const IN_JUMP := 4
const IN_ACTION := 8
const IN_SWITCH := 16
const IN_UP := 32    # 上入力。地上はジャンプ専用、空中は通常アタック
const IN_DOWN := 64  # 下入力。地上はレシーブ、空中はジャスト可アタック
# 固有技スロット(ネットプロトコルで予約済み。押されたら何が起きるかはキャラ定義が決める。
# 技1=Dキー既定(マリオ=帽子投げ)。2-4は将来の技用で、後からのビット追加は
# ネット互換を壊すため今のうちに確保しておく)
const IN_ABILITY1 := 128
const IN_ABILITY2 := 256
const IN_ABILITY3 := 512
const IN_ABILITY4 := 1024
