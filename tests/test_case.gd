# テスト基底。check系メソッドで失敗を蓄積し、ランナーが回収する
# checks_runはランタイムエラーによる偽PASS検出用(1回もcheckせず戻ったテストはFAIL)
extends RefCounted

var failures: Array[String] = []
var checks_run: int = 0

func check(cond: bool, msg: String) -> void:
	checks_run += 1
	if not cond:
		failures.append(msg)

func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	checks_run += 1
	if actual != expected:
		failures.append("%s: expected=%s actual=%s" % [msg, str(expected), str(actual)])
