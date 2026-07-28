extends RefCounted

const Chars := preload("res://src/sim/chars.gd")
const SimState := preload("res://src/sim/sim_state.gd")

const ROLE_HOST := "host"
const ROLE_JOIN := "join"

enum Action {
	WAIT,
	APPLY,
	ACK,
	REACK,
	START,
	STOP,
}

var role := ""
var expected_peer_id := -1
var peer_registered := false
var start_info_received := false
var apply_requested := false
var state_applied := false
var ack_verified := false
var sync_started := false
var failed := false

var agreed_seed: Variant = null
var agreed_roster: Array = []
var agreed_serving_team := -1
var initial_hash: Variant = null
var failure_reason := ""

func setup(role_in: String, expected_peer_id_in: int) -> void:
	role = role_in
	expected_peer_id = expected_peer_id_in
	if role != ROLE_HOST and role != ROLE_JOIN:
		_fail("invalid role")

func register_peer(peer_id: int) -> int:
	if failed:
		return Action.STOP
	if expected_peer_id < 0:
		expected_peer_id = peer_id
	if peer_id != expected_peer_id:
		return _fail("unexpected peer id")
	peer_registered = true
	return _request_apply_if_ready()

func prepare_host_start(seed: Variant, roster: Variant, serving_team: Variant) -> int:
	if failed:
		return Action.STOP
	if role != ROLE_HOST:
		return _fail("join cannot prepare host start")
	if not peer_registered:
		return _fail("host start prepared before peer registration")
	if not _valid_start_info(seed, roster, serving_team):
		return _fail("invalid host start info")
	if start_info_received:
		return _fail("host start info already prepared")
	_store_start_info(seed, roster, serving_team)
	return _request_apply_if_ready()

func receive_start_info(seed: Variant, roster: Variant, serving_team: Variant) -> int:
	if failed:
		return Action.STOP
	if role != ROLE_JOIN:
		return _fail("host received start info")
	if sync_started:
		return _fail("start info received after sync start")
	if not _valid_start_info(seed, roster, serving_team):
		return _fail("invalid start info")
	if start_info_received:
		if not _same_start_info(seed, roster, serving_team):
			return _fail("different start info received")
		if state_applied:
			return Action.REACK
		return Action.WAIT
	_store_start_info(seed, roster, serving_team)
	return _request_apply_if_ready()

func mark_state_applied(hash_value: int) -> int:
	if failed:
		return Action.STOP
	if sync_started:
		return _fail("state applied after sync start")
	if not peer_registered or not start_info_received or not apply_requested:
		return _fail("state applied before handshake was ready")
	if state_applied:
		return _fail("state applied more than once")
	state_applied = true
	initial_hash = hash_value
	return Action.ACK if role == ROLE_JOIN else Action.WAIT

func receive_ack(sender_id: int, seed: Variant, hash_value: Variant) -> int:
	if failed:
		return Action.STOP
	if role != ROLE_HOST:
		return _fail("join received start ack")
	if not state_applied:
		return _fail("ack received before host state applied")
	if typeof(seed) != TYPE_INT or typeof(hash_value) != TYPE_INT:
		return _fail("start ack type mismatch")
	var matches: bool = sender_id == expected_peer_id \
		and seed == agreed_seed \
		and hash_value == initial_hash
	if not matches:
		return _fail("start ack mismatch")
	if ack_verified:
		return Action.WAIT
	ack_verified = true
	return Action.START

func notify_sync_started() -> int:
	if failed:
		return Action.STOP
	if not state_applied:
		return _fail("sync started before state applied")
	if role == ROLE_HOST and not ack_verified:
		return _fail("host sync started before ack verification")
	sync_started = true
	return Action.WAIT

func stop(reason: String) -> int:
	return _fail(reason)

func _request_apply_if_ready() -> int:
	if peer_registered and start_info_received and not apply_requested:
		apply_requested = true
		return Action.APPLY
	return Action.WAIT

func _store_start_info(seed: Variant, roster: Variant, serving_team: Variant) -> void:
	agreed_seed = int(seed)
	agreed_roster = (roster as Array).duplicate()
	agreed_serving_team = int(serving_team)
	start_info_received = true

func _same_start_info(seed: Variant, roster: Variant, serving_team: Variant) -> bool:
	return int(seed) == agreed_seed \
		and (roster as Array) == agreed_roster \
		and int(serving_team) == agreed_serving_team

func _valid_start_info(seed: Variant, roster: Variant, serving_team: Variant) -> bool:
	if typeof(seed) != TYPE_INT:
		return false
	var seed_value := int(seed)
	if seed_value < 0 or seed_value > 0xFFFF:
		return false
	var hour := seed_value >> 8
	var minute := seed_value & 0xFF
	if hour < 0 or hour >= 24 or minute < 0 or minute >= 60:
		return false
	if typeof(roster) != TYPE_ARRAY:
		return false
	var roster_values := roster as Array
	if roster_values.size() != SimState.PLAYER_COUNT:
		return false
	for char_id in roster_values:
		if typeof(char_id) != TYPE_INT or not Chars.DEFS.has(int(char_id)):
			return false
	if typeof(serving_team) != TYPE_INT:
		return false
	return int(serving_team) == 0 or int(serving_team) == 1

func _fail(reason: String) -> int:
	if not failed:
		failed = true
		failure_reason = reason
	return Action.STOP
