# テスト基底。check系メソッドで失敗を蓄積し、ランナーが回収する
extends RefCounted

var failures: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected=%s actual=%s" % [msg, str(expected), str(actual)])
