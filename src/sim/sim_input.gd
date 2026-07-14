# 入力ビット定数の正本。シミュレーション層の複数ファイルから参照される
extends RefCounted

const IN_LEFT := 1
const IN_RIGHT := 2
const IN_JUMP := 4
const IN_ACTION := 8
const IN_SWITCH := 16
const IN_UP := 32    # 上方向の照準(上キー。ジャンプと同じキーから立つ)
const IN_DOWN := 64  # 下方向の照準(空中で下+アクション=アタック)
const IN_HAT_THROW := 128  # 帽子投げ(Dキー)。地上/空中どちらでも
