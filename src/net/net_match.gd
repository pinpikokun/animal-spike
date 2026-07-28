# フェーズ1: ENetで2プロセス対戦する検証シーン。
# 子ノード(InputL/InputR/SimRoot/GameView/HUD)は_readyでコード生成する。
extends Node2D

const SimRootScript := preload("res://src/net/sim_root.gd")
const NetInputScript := preload("res://src/net/net_input_node.gd")
const BootSeedHandshake := preload("res://src/net/boot_seed_handshake.gd")
const GameViewScene := preload("res://src/display/game_view.tscn")
const Chars := preload("res://src/sim/chars.gd")

const PORT := 42424
const RBDEBUG_TICKS := 8
const SERVING_TEAM := 0

signal boot_seed_agreed(seed: int)

# root.gdがadd_child前に設定する。joinのboot_seedは合意完了までnull。
var net_role := ""
var boot_seed: Variant = null

var _sim_root
var _hud: Label
var _handshake
var _is_bot := false
var _rbdebug := false
var _mismatch_count := 0
var _sync_active := false
var _started_at_msec := 0
var _last_report_sec := -1
var _agreed_logged := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_bot = args.has("bot")
	_rbdebug = args.has("rbdebug")

	_handshake = BootSeedHandshake.new()
	_handshake.setup(net_role, -1 if net_role == BootSeedHandshake.ROLE_HOST else 1)
	if _handshake.failed:
		stop_handshake(_handshake.failure_reason)
		return
	if net_role == BootSeedHandshake.ROLE_HOST and boot_seed == null:
		stop_handshake("hostのboot_seedが未取得")
		return
	if net_role == BootSeedHandshake.ROLE_JOIN and boot_seed != null:
		stop_handshake("joinが合意前のboot_seedを所有している")
		return

	_sim_root = SimRootScript.new()
	_sim_root.name = "SimRoot"
	_sim_root.setup()
	_sim_root.state.human_team_mask = _human_team_mask()
	Engine.physics_ticks_per_second = _sim_root.cfg.tick_rate

	var input_l = NetInputScript.new()
	input_l.name = "InputL"
	input_l.team = 0
	input_l.sim_root = _sim_root
	input_l.bot = _is_bot
	var input_r = NetInputScript.new()
	input_r.name = "InputR"
	input_r.team = 1
	input_r.sim_root = _sim_root
	input_r.bot = _is_bot
	add_child(input_l)
	add_child(input_r)
	add_child(_sim_root)

	var view := GameViewScene.instantiate()
	view.attach_external(_sim_root.cfg, _sim_root.state)
	view.local_team = 0 if net_role == BootSeedHandshake.ROLE_HOST else 1
	add_child(view)

	_hud = Label.new()
	_hud.position = Vector2(4, 4)
	var hud_layer := CanvasLayer.new()
	hud_layer.add_child(_hud)
	add_child(hud_layer)

	SyncManager.sync_started.connect(_on_sync_started)
	SyncManager.sync_stopped.connect(_on_sync_stopped)
	SyncManager.sync_error.connect(_on_sync_error)
	SyncManager.remote_state_mismatch.connect(_on_remote_state_mismatch)
	if _rbdebug:
		SyncManager.debug_rollback_ticks = RBDEBUG_TICKS
		print("NET rbdebug ON: forcing %d rollback ticks every tick" % RBDEBUG_TICKS)
	_connect_net()

func _connect_net() -> void:
	var args := OS.get_cmdline_user_args()
	var peer := ENetMultiplayerPeer.new()
	if net_role == BootSeedHandshake.ROLE_HOST:
		var err := peer.create_server(PORT, 1)
		if err != OK:
			stop_handshake("ENetサーバ作成失敗: %d" % err)
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_connected)
		print("NET host listening port=%d bot=%s" % [PORT, _is_bot])
	else:
		var address := "127.0.0.1"
		for arg in args:
			if arg.contains("."):
				address = arg
		var err := peer.create_client(address, PORT)
		if err != OK:
			stop_handshake("ENetクライアント作成失敗: %d" % err)
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(
			func() -> void: stop_handshake("ENet接続失敗"))
		print("NET join address=%s port=%d bot=%s" % [address, PORT, _is_bot])

func _assign_authorities(host_id: int, client_id: int) -> void:
	$InputL.set_multiplayer_authority(host_id)
	$InputR.set_multiplayer_authority(client_id)
	$SimRoot.set_multiplayer_authority(host_id)

func _on_peer_connected(peer_id: int) -> void:
	_assign_authorities(1, peer_id)
	SyncManager.add_peer(peer_id)
	var action: int = _handshake.register_peer(peer_id)
	if action == BootSeedHandshake.Action.STOP:
		stop_handshake(_handshake.failure_reason)
		return

	action = _handshake.prepare_host_start(boot_seed, Chars.ROSTER, SERVING_TEAM)
	if action != BootSeedHandshake.Action.APPLY:
		stop_handshake(_handshake.failure_reason if _handshake.failed
			else "hostの開始情報が適用要求にならなかった")
		return
	var initial_hash: int = _sim_root.apply_agreed_start(
		SERVING_TEAM, Chars.ROSTER, int(boot_seed), _human_team_mask())
	action = _handshake.mark_state_applied(initial_hash)
	if action == BootSeedHandshake.Action.STOP:
		stop_handshake(_handshake.failure_reason)
		return
	_print_agreed_once()
	_receive_start_info.rpc_id(
		peer_id, int(boot_seed), Chars.ROSTER, SERVING_TEAM)

func _on_connected_to_server() -> void:
	_assign_authorities(1, multiplayer.get_unique_id())
	SyncManager.add_peer(1)
	var action: int = _handshake.register_peer(1)
	if action == BootSeedHandshake.Action.APPLY:
		_apply_client_start()
	elif action == BootSeedHandshake.Action.STOP:
		stop_handshake(_handshake.failure_reason)
	else:
		print("NET connected to host, waiting for agreed start")

@rpc("authority", "call_remote", "reliable")
func _receive_start_info(seed: Variant, roster: Variant, serving_team: Variant) -> void:
	var action: int = _handshake.receive_start_info(seed, roster, serving_team)
	if action == BootSeedHandshake.Action.APPLY:
		_apply_client_start()
	elif action == BootSeedHandshake.Action.REACK:
		_send_start_ack()
	elif action == BootSeedHandshake.Action.STOP:
		stop_handshake(_handshake.failure_reason)

func _apply_client_start() -> void:
	var initial_hash: int = _sim_root.apply_agreed_start(
		_handshake.agreed_serving_team,
		_handshake.agreed_roster,
		int(_handshake.agreed_seed),
		_human_team_mask())
	var action: int = _handshake.mark_state_applied(initial_hash)
	if action != BootSeedHandshake.Action.ACK:
		stop_handshake(_handshake.failure_reason if _handshake.failed
			else "joinの状態適用がACK要求にならなかった")
		return
	boot_seed = int(_handshake.agreed_seed)
	_print_agreed_once()
	boot_seed_agreed.emit(int(boot_seed))
	_send_start_ack()

func _send_start_ack() -> void:
	_receive_start_ack.rpc_id(
		1, int(_handshake.agreed_seed), int(_handshake.initial_hash))

@rpc("any_peer", "call_remote", "reliable")
func _receive_start_ack(seed: Variant, initial_hash: Variant) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	var action: int = _handshake.receive_ack(sender_id, seed, initial_hash)
	if action == BootSeedHandshake.Action.START:
		print("NET_ACK_VERIFIED peer=%d seed=%d hash=%d" % [
			sender_id, int(seed), int(initial_hash)])
		SyncManager.start()
	elif action == BootSeedHandshake.Action.STOP:
		stop_handshake(_handshake.failure_reason)

func _print_agreed_once() -> void:
	if _agreed_logged:
		return
	_agreed_logged = true
	print("NET_AGREED role=%s seed=%d roster=%s serving=%d hash=%d" % [
		net_role,
		int(_handshake.agreed_seed),
		_roster_text(_handshake.agreed_roster),
		_handshake.agreed_serving_team,
		int(_handshake.initial_hash),
	])

func _roster_text(roster: Array) -> String:
	var values := PackedStringArray()
	for char_id in roster:
		values.append(str(char_id))
	return ",".join(values)

func _human_team_mask() -> int:
	return 0 if _is_bot else 3

func stop_handshake(reason: String) -> void:
	if _handshake != null:
		_handshake.stop(reason)
	push_error("NET HANDSHAKE ERROR: %s" % reason)
	if _sync_active:
		SyncManager.stop()
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()

func _on_sync_started() -> void:
	var action: int = _handshake.notify_sync_started()
	if action == BootSeedHandshake.Action.STOP:
		_sync_active = true
		stop_handshake(_handshake.failure_reason)
		return
	_sync_active = true
	_started_at_msec = Time.get_ticks_msec()
	print("NET SYNC STARTED role=%s" % net_role)

func _on_sync_stopped() -> void:
	_sync_active = false
	print("NET SYNC STOPPED role=%s tick=%d" % [net_role, _sim_root.state.tick])

func _on_sync_error(msg: String) -> void:
	push_error("NET SYNC ERROR: %s" % msg)
	print("NET SYNC ERROR role=%s: %s" % [net_role, msg])

func _on_remote_state_mismatch(
		tick: int, peer_id: int, local_hash, remote_hash
	) -> void:
	_mismatch_count += 1
	push_error("NET STATE MISMATCH tick=%d peer=%d local=%d remote=%d (計%d件)" % [
		tick, peer_id, local_hash, remote_hash, _mismatch_count])

func _process(_delta: float) -> void:
	var elapsed := 0
	if _started_at_msec > 0:
		elapsed = (Time.get_ticks_msec() - _started_at_msec) / 1000
	var tick: int = _sim_root.state.tick if _sim_root != null else 0
	_hud.text = "role=%s  tick=%d  経過=%d秒  mismatch=%d" % [
		net_role, tick, elapsed, _mismatch_count]
	if _sync_active and elapsed != _last_report_sec and elapsed % 5 == 0:
		_last_report_sec = elapsed
		print("NET_STATUS role=%s tick=%d elapsed=%ds mismatch=%d" % [
			net_role, tick, elapsed, _mismatch_count])
