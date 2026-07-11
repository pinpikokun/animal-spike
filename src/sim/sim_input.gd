# 入力ビット定数の正本。シミュレーション層の複数ファイルから参照される
extends RefCounted

const IN_LEFT := 1
const IN_RIGHT := 2
const IN_JUMP := 4
const IN_ACTION := 8
const IN_SWITCH := 16
const IN_UP := 32  # トス方向の照準(ジャンプとは別。上向きトスの指定)
