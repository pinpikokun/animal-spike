extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")

# SimStateの「フィールドを足したらto_int_arrayにも足す」規約を強制する。
# 全intフィールドを1ずつ摂動してハッシュが変わることと、
# intフィールド総数==シリアライズ長を検証する(足し忘れは数が合わなくなる)

func _int_props(obj: Object) -> Array[String]:
	var out: Array[String] = []
	for p in obj.get_property_list():
		if (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and p["type"] == TYPE_INT:
			out.append(p["name"])
	return out

func test_every_int_field_affects_hash() -> void:
	var s = SimState.new()
	var base: int = s.state_hash()
	var field_count := 0
	for prop in _int_props(s):
		field_count += 1
		var orig: int = s.get(prop)
		s.set(prop, orig + 1)
		check(s.state_hash() != base, "state." + prop + " がハッシュに反映されていない")
		s.set(prop, orig)
	for i in s.players.size():
		var p = s.players[i]
		for prop in _int_props(p):
			field_count += 1
			var orig: int = p.get(prop)
			p.set(prop, orig + 1)
			check(s.state_hash() != base, "players[%d].%s がハッシュに反映されていない" % [i, prop])
			p.set(prop, orig)
	check_eq(field_count, s.to_int_array().size(), "int項目数とシリアライズ長の一致(足し忘れ検出)")
	check_eq(s.state_hash(), base, "摂動の復元漏れなし")

func test_all_state_fields_are_int() -> void:
	# 上の摂動チェックはintフィールドしか見ないため、bool/無型/float等で
	# フィールドを足すと直列化漏れが素通りする。型そのものをintに強制して塞ぐ
	var s = SimState.new()
	for p in s.get_property_list():
		if (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and p["name"] != "players":
			check_eq(p["type"], TYPE_INT, "state." + str(p["name"]) + " はintで宣言する(直列化規約)")
	for pl in s.players:
		for p in pl.get_property_list():
			if (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				check_eq(p["type"], TYPE_INT, "player." + str(p["name"]) + " はintで宣言する(直列化規約)")
