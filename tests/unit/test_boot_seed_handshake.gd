extends "res://tests/test_case.gd"

const Handshake := preload("res://src/net/boot_seed_handshake.gd")

const SEED := 0x173B
const ROSTER := [0, 1, 2, 3]
const SERVING := 0
const HASH := 123456789
const PEER_ID := 2

func test_peer_and_start_info_both_orders_wait_until_both_are_ready() -> void:
	var peer_first = _join_handshake()
	check_eq(peer_first.register_peer(PEER_ID), Handshake.Action.WAIT,
		"peerだけでは適用しない")
	check_eq(peer_first.receive_start_info(SEED, ROSTER, SERVING), Handshake.Action.APPLY,
		"peerの後に開始情報が届けば適用する")

	var info_first = _join_handshake()
	check_eq(info_first.receive_start_info(SEED, ROSTER, SERVING), Handshake.Action.WAIT,
		"開始情報だけでは適用しない")
	check_eq(info_first.register_peer(PEER_ID), Handshake.Action.APPLY,
		"開始情報の後にpeer登録すれば適用する")

func test_identical_start_info_after_apply_requests_reack() -> void:
	var h = _applied_join_handshake()
	check_eq(h.receive_start_info(SEED, ROSTER, SERVING), Handshake.Action.REACK,
		"完全一致する重複は再適用せず再ACK")

func test_changed_seed_roster_or_serving_team_fails() -> void:
	var changed_seed = _applied_join_handshake()
	check_eq(changed_seed.receive_start_info(0x0102, ROSTER, SERVING), Handshake.Action.STOP,
		"seed差異は停止")
	var changed_roster = _applied_join_handshake()
	check_eq(changed_roster.receive_start_info(SEED, [1, 0, 2, 3], SERVING),
		Handshake.Action.STOP, "roster差異は停止")
	var changed_serving = _applied_join_handshake()
	check_eq(changed_serving.receive_start_info(SEED, ROSTER, 1), Handshake.Action.STOP,
		"serving team差異は停止")

func test_start_info_after_sync_started_fails_even_if_identical() -> void:
	var h = _applied_join_handshake()
	check_eq(h.notify_sync_started(), Handshake.Action.WAIT, "同期開始通知を受理する")
	check_eq(h.receive_start_info(SEED, ROSTER, SERVING), Handshake.Action.STOP,
		"同期開始後は同一開始情報でも停止")

func test_matching_ack_from_expected_peer_allows_start_once() -> void:
	var h = _applied_host_handshake()
	check_eq(h.receive_ack(PEER_ID, SEED, HASH), Handshake.Action.START,
		"期待peerの一致ACKだけが開始を許可")
	check_eq(h.receive_ack(PEER_ID, SEED, HASH), Handshake.Action.WAIT,
		"一致ACKの重複で二度目の開始を許可しない")
	var changed_after_start = _applied_host_handshake()
	check_eq(changed_after_start.receive_ack(PEER_ID, SEED, HASH), Handshake.Action.START,
		"前提: 一致ACKで開始許可済み")
	check_eq(changed_after_start.receive_ack(PEER_ID, SEED, HASH + 1),
		Handshake.Action.STOP, "開始許可後でも異なるACKは停止")

func test_ack_sender_seed_and_hash_mismatches_all_fail() -> void:
	var wrong_sender = _applied_host_handshake()
	check_eq(wrong_sender.receive_ack(PEER_ID + 1, SEED, HASH), Handshake.Action.STOP,
		"送信者ID不一致は停止")
	var wrong_seed = _applied_host_handshake()
	check_eq(wrong_seed.receive_ack(PEER_ID, 0x0102, HASH), Handshake.Action.STOP,
		"ACK seed不一致は停止")
	var wrong_hash = _applied_host_handshake()
	check_eq(wrong_hash.receive_ack(PEER_ID, SEED, HASH + 1), Handshake.Action.STOP,
		"ACK hash不一致は停止")

func _join_handshake():
	var h = Handshake.new()
	h.setup(Handshake.ROLE_JOIN, PEER_ID)
	return h

func _applied_join_handshake():
	var h = _join_handshake()
	h.register_peer(PEER_ID)
	h.receive_start_info(SEED, ROSTER, SERVING)
	check_eq(h.mark_state_applied(HASH), Handshake.Action.ACK,
		"joinの適用完了はACK要求")
	return h

func _applied_host_handshake():
	var h = Handshake.new()
	h.setup(Handshake.ROLE_HOST, PEER_ID)
	h.register_peer(PEER_ID)
	check_eq(h.prepare_host_start(SEED, ROSTER, SERVING), Handshake.Action.APPLY,
		"hostの開始情報を検証して適用要求")
	check_eq(h.mark_state_applied(HASH), Handshake.Action.WAIT,
		"hostは適用後ACK待ち")
	return h
