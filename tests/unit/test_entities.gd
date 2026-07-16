extends "res://tests/test_case.gd"

const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")

func test_spawn_uses_first_free_slot() -> void:
	var s = St.new()
	check_eq(Sim.ent_spawn(s, Sim.KIND_CAP), 0, "先頭スロットに生成")
	check_eq(Sim.ent_spawn(s, Sim.KIND_CAP), 1, "次は2番目")
	Sim.ent_free(s.entities[0])
	check_eq(Sim.ent_spawn(s, Sim.KIND_CAP), 0, "解放済みの先頭が再利用される")

func test_spawn_fails_when_full() -> void:
	var s = St.new()
	for i in St.ENT_SLOTS:
		check(Sim.ent_spawn(s, Sim.KIND_CAP) >= 0, "満杯まで生成できる")
	check_eq(Sim.ent_spawn(s, Sim.KIND_CAP), -1, "満杯なら生成失敗(-1)")

func test_free_resets_all_fields_for_hash() -> void:
	# 解放したスロットは未使用スロットとハッシュが完全一致する(ゴミ値を残さない)
	var clean = St.new()
	var s = St.new()
	var j: int = Sim.ent_spawn(s, Sim.KIND_CAP)
	var e = s.entities[j]
	e.phase = 2
	e.x = 12345
	e.timer = 99
	Sim.ent_free(e)
	check_eq(s.state_hash(), clean.state_hash(), "解放後は初期状態とハッシュ一致")

func test_entities_serialize_roundtrip() -> void:
	var a = St.new()
	var j: int = Sim.ent_spawn(a, Sim.KIND_CAP)
	a.entities[j].phase = 3
	a.entities[j].x = 777
	a.entities[j].owner = 2
	var b = St.new()
	b.load_int_array(a.to_int_array())
	check_eq(b.state_hash(), a.state_hash(), "往復でハッシュ一致")
	check_eq(b.entities[j].x, 777, "エンティティ座標の復元")
	check_eq(b.entities[j].owner, 2, "所有者の復元")
