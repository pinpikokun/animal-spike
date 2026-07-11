# フェーズ1: ENetで2プロセス対戦する検証シーン。M2ゲートの土台。
# 子ノード(InputL/InputR/SimRoot/GameView/HUD)は全て_readyでコード生成する。
# 起動引数(-- 以降): host | join [address] | bot
#   host        : ENetサーバ。相手の接続を待ってSyncManager.start()
#   join [addr] : ENetクライアント。addr省略時は127.0.0.1
#   bot         : 決定論CPUが自マシンの入力を生成(無人ソーク用。両プロセスに付ける)
extends Node2D

const SimRootScript := preload("res://src/net/sim_root.gd")
const NetInputScript := preload("res://src/net/net_input_node.gd")
const GameViewScene := preload("res://src/display/game_view.tscn")

const PORT := 42424

const RBDEBUG_TICKS := 8  # rbdebug時に毎tick強制するロールバック量(決定論の再シミュ検証)

var _sim_root
var _hud: Label
var _role := "?"
var _is_bot := false
var _rbdebug := false
var _mismatch_count := 0
var _sync_active := false
var _started_at_msec := 0
var _last_report_sec := -1

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_bot = args.has("bot")
	_rbdebug = args.has("rbdebug")
	_role = "host" if args.has("host") else "join"

	_sim_root = SimRootScript.new()
	_sim_root.name = "SimRoot"
	_sim_root.setup()
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
	# postprocess方式のためツリー順は進行の正しさに影響しないが、可読性のため入力2つ→SimRoot
	add_child(input_l)
	add_child(input_r)
	add_child(_sim_root)

	var view := GameViewScene.instantiate()
	view.attach_external(_sim_root.cfg, _sim_root.state)
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
		# 毎tick強制ロールバック+再シミュ。保存stateに含まれない_team_inputsが
		# 入力ノードの再書き込みで正しく再現されるか(=決定論)を最も厳しく検証する
		SyncManager.debug_rollback_ticks = RBDEBUG_TICKS
		print("NET rbdebug ON: forcing %d rollback ticks every tick" % RBDEBUG_TICKS)
	_connect_net()

func _connect_net() -> void:
	var args := OS.get_cmdline_user_args()
	var peer := ENetMultiplayerPeer.new()
	if _role == "host":
		var err := peer.create_server(PORT, 1)
		if err != OK:
			push_error("ENetサーバ作成失敗: %d" % err)
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_connected)
		print("NET host listening port=%d bot=%s" % [PORT, _is_bot])
	else:
		var address := "127.0.0.1"
		for a in args:
			if a.contains("."):
				address = a
		var err := peer.create_client(address, PORT)
		if err != OK:
			push_error("ENetクライアント作成失敗: %d" % err)
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(func() -> void: push_error("接続失敗"))
		print("NET join address=%s port=%d bot=%s" % [address, PORT, _is_bot])

func _assign_authorities(host_id: int, client_id: int) -> void:
	# InputLはホスト、InputRはクライアントが所有。SimRootはホスト所有(進行位置の基準)
	$InputL.set_multiplayer_authority(host_id)
	$InputR.set_multiplayer_authority(client_id)
	$SimRoot.set_multiplayer_authority(host_id)

func _on_peer_connected(peer_id: int) -> void:
	# ホスト側: 相手が来たら権限を割り当てて同期開始
	_assign_authorities(1, peer_id)
	SyncManager.add_peer(peer_id)
	print("NET peer connected id=%d -> SyncManager.start()" % peer_id)
	SyncManager.start()

func _on_connected_to_server() -> void:
	# クライアント側: startはホストが呼ぶ。ここではpeer登録のみ
	_assign_authorities(1, multiplayer.get_unique_id())
	SyncManager.add_peer(1)
	print("NET connected to host, waiting for remote start")

func _on_sync_started() -> void:
	_sync_active = true
	_started_at_msec = Time.get_ticks_msec()
	print("NET SYNC STARTED role=%s" % _role)

func _on_sync_stopped() -> void:
	_sync_active = false
	print("NET SYNC STOPPED role=%s tick=%d" % [_role, _sim_root.state.tick])

func _on_sync_error(msg: String) -> void:
	push_error("NET SYNC ERROR: %s" % msg)
	print("NET SYNC ERROR role=%s: %s" % [_role, msg])

func _on_remote_state_mismatch(tick: int, peer_id: int, local_hash, remote_hash) -> void:
	_mismatch_count += 1
	push_error("NET STATE MISMATCH tick=%d peer=%d local=%d remote=%d (計%d件)" % [tick, peer_id, local_hash, remote_hash, _mismatch_count])

func _process(_delta: float) -> void:
	var elapsed := 0
	if _started_at_msec > 0:
		elapsed = (Time.get_ticks_msec() - _started_at_msec) / 1000
	var tick: int = _sim_root.state.tick if _sim_root != null else 0
	_hud.text = "role=%s  tick=%d  経過=%d秒  mismatch=%d" % [_role, tick, elapsed, _mismatch_count]
	# ヘッドレス検証用に5秒ごとに1行だけ標準出力へ
	if _sync_active and elapsed != _last_report_sec and elapsed % 5 == 0:
		_last_report_sec = elapsed
		print("NET_STATUS role=%s tick=%d elapsed=%ds mismatch=%d" % [_role, tick, elapsed, _mismatch_count])
