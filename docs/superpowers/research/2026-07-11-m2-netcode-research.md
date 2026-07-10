# M2ネットコード検証ゲート事前調査 (2026-07-11)

M2実装計画の資料。調査エージェントによるWeb調査の結果(出典URL付き)。
結論: M2計画の技術前提は2026年7月現在ほぼ全て成立している。

## 1. godot-rollback-netcode (Snopek作) の現状

事実:
- 本家がGodot 4対応済み。フォーク不要、名称そのまま。https://gitlab.com/snopek-games/godot-rollback-netcode (MIT)
- ブランチ: main(=Godot 4、デフォルト)、godot-3(2024-05のalpha10で凍結)
- 最新タグ v1.0.0 (2026-06-06、正式版)。リリースノートに「Run the 'Upgrade Project Files...' tool in Godot 4.6.3」とあり、作者自身がGodot 4.6.3で整備している
- 注意: Godot公式アセットライブラリ(asset/2450)は1.0.0-alpha(Godot 4.2向け、2024-05)のまま古い。GitLab本家v1.0.0タグから取得すること
- GDExtension版SyncManagerは公式には無い(全てGDScript実装)。C#ラッパーはFractural/GodotRollbackNetcodeMono(Godot 4.4対応)。Rust製gdrollback(Kethku)は実験段階
- 採用実績: Retro Tank Party、Kronian Titans、Castagne、Rakugaki Rumble、Dueling Dillos
- 「Godot 4.6で30分デシンクゼロ」級の公開検証データは見つからず(不明)

含意: 入手はGitLab本家v1.0.0から。中央集権stateの自前simはノード大量登録型より構造的に有利。性能問題時の逃げ道(C#ラッパー/gdrollback)はあるが追加リスク、まず本家GDScript版で計測。

## 2. 統合方法 (インターフェース仕様とアダプタ設計)

事実(README/ソース原文より):
- ノードに実装する仮想メソッド: `_save_state() -> Dictionary` / `_load_state(state)` / `_interpolate_state(old, new, weight)` / `_get_local_input() -> Dictionary` / `_predict_remote_input(prev, ticks_since_real)` / `_network_process(input)` / `_network_preprocess` / `_network_postprocess` / `_network_spawn` / `_network_despawn`
- state型制約の原文: "Don't put any References, Objects, Arrays or Dictionarys into state, unless you can duplicate them first"、"NEVER put Nodes in state"。プリミティブ(int, bool, String)推奨
- デシンク検出: HashSerializerがstate/inputをハッシュ化しピア間比較、不一致でstate mismatch通知
- 入力はDictionaryで返す。intビットマスク1個でOK。デフォルトMessageSerializerはvar_to_bytes()で、READMEが「ほぼ必ず自作せよ(ALMOST ALWAYS)」と明言
- メッセージ構造: {次に欲しい入力tick(u32), 入力{tick→bytes}, 次に欲しいハッシュtick(u32), stateハッシュ{tick→u32}}。入力再送とハッシュ照合はプロトコル組み込み済み

含意(アダプタ設計の推奨案):
1. SimRoot 1ノードだけをrollback対象に登録。`_save_state()`は`{"s": state.to_int_array()}`(毎回新規配列を返すこと)
2. `_load_state()`でint配列から復元
3. `_network_process()`内で自前tick()を1回だけ。`_process`/`_physics_process`ではsimを進めない
4. `_get_local_input()`は`{"i": ボタンビットマスクint}`の最小Dictionary
5. MessageSerializer自作で入力を2〜4バイトに圧縮
6. 自前FNV-1aハッシュをstateに"h"として含めれば、アドオンのハッシュ照合が自前ハッシュ比較になる(推奨・推測)

## 3. GodotSteamの現状

事実:
- 最新 GodotSteam 4.20 (2026-06-24、Steamworks SDK 1.64)。4.19.1 (2026-05-29) が「Godot 4.6.3」向けビルドと明記。各リリースにGDExtension版(-gde)同梱
- リポジトリはGitHub→Codebergへ移行済み: https://codeberg.org/godotsteam/godotsteam (GitHub側は2026-06-30アーカイブ)
- 導入: zipを`addons/`に展開 + `steam_appid.txt`を実行ファイル横に置く。AssetLib「GodotSteam GDExtension 4.4+」(asset/2445)
- SteamMultiplayerPeerはGodotSteam 4.16 (2025-09-22)で本体にマージ済み。現行GodotSteamだけでGodot高レベルマルチプレイヤーAPI(RPC)をSteam経由で使える
- SDR: NetworkingMessages API(sendMessageToUser/receiveMessagesOnChannel)がGodotSteamに露出。Steamworks公式が「SDRの恩恵を受ける」と明言
- Spacewar(appid 480)テストは定番。ただし「1PC=1Steamクライアント=1アカウント」制約で同一PC2プロセスのSteam P2P不可。メンテナ回答「別マシンかVM」

含意: Godot 4.6なら GodotSteam 4.19.1-gde が直球。GDExtensionなのでエンジン再ビルド不要。

## 4. rollback-netcode × GodotSteam の組み合わせ

事実:
- 公式のSteam用NetworkAdaptorは同梱されていない(RPC/NakamaWebRTC/Dummyの3種のみ)。ただしREADMEが「Steam P2P等への差し替え」をまさに想定
- カスタムアダプタのAPI: attach/detach/start/stop_network_adaptor、send_ping(_back)、send_remote_start/stop、send_input_tick(peer_id, PackedByteArray)、is_network_host()、is_network_master_for_node()、get_unique_id()、poll()。受信はシグナルreceived_*をemit
- デフォルトRPCNetworkAdaptor: 入力とpingは@rpc("any_peer","unreliable")、start/stopのみreliable
- Snopek公式教材は無料11パート(Godot 3ベース、Steam統合は扱わない): https://www.snopekgames.com/course/rollback-netcode-godot/
- 両者を直結した公開実例は発見できず(不明)。ここがM2最大の未知数

含意(接続経路の二段構え):
- 経路A(最小工数): SteamMultiplayerPeerをmultiplayer.multiplayer_peerに挿し、デフォルトRPCNetworkAdaptorを無改造で使う。unreliable RPCがSteamソケットにマップされる想定(M2初日の検証ポイント)
- 経路B(確実・低依存): NetworkingMessagesを直接叩く自作SteamNetworkAdaptor。send_input_tickをsendMessageToUser(unreliable)へ素通し、poll()でreceiveMessagesOnChannel。実装規模は1〜2百行と推測
- 注意: SyncManagerのpeer_idはint。SteamID64はint64に収まるが、高レベルAPIのpeer_id(1=ホスト等)との整合はアダプタ内で対応表を持つのが安全

## 5. 代替案の現状

- netfox: 状態同期系(CSP+ラグ補償)。決定論ロールバックではない
- Delta Rollback(BimDav): Snopek版のGodot 4向け最適化フォークとの言及あり。M2-T2で再確認(2026-07-11)も https://gitlab.com/BimDav/delta_rollback は403で不可視。仮に入手できても本作のstateは41int(約328バイト)と極小で、デルタ圧縮の帯域メリットは無視できる。採用しない(本家v1.0.0で確定)
- Klotho(xpTURN): C#製決定論フレームワーク(FP64固定小数点、ECS)。Unity & Godotを謳う新顔、成熟度不明
- Photon Quantum 3: 3.0.11 (2026-04-27)。Unity専用のまま=撤退計画の前提は有効
- 新事実: Photon FusionがGodot対応を発表(状態同期系、Quantumとは別製品)。撤退判断時に「Godot継続+非決定論」の中間選択肢として一度だけ再評価の価値あり

## 6. 既知の罠

- stateにReference/Object/Array/Dictionaryを入れるなら複製必須、Node絶対禁止
- デフォルトMessageSerializerはMTU超過しがち→ほぼ必ず自作
- ロールバック発生時、巻き戻したtick数ぶんの_network_processを1フレーム内で連続再実行する
- 設定: max_buffer_size(最大ロールバック量)、input_delay、interpolation、max_ticks_to_regain_sync等
- デバッグ装備: debug/rollback_ticks(毎tick強制ロールバック数)で常時ロールバック負荷を人工的にかけられる。debug/physics_process_msecs/message_bytesで警告
- SyncManager.start_logging()→log2json.gd→エディタ内Log Inspector(Frame Viewer/State-Input Viewer)でピア間比較。v1.0.0でLogger→SyncLoggerに改名(古いチュートリアルと名前が違う)
- 境界の注意: 入力収集でfloat持ち込み禁止(量子化してint化)、Dictionary構築は同一コードパス、乱数はsim内決定論RNGのみ、進行は全て_network_processへ

## 総括 (M2実装計画への直言)

1. アドオンはGitLab本家v1.0.0を使え(AssetLibの古いalpha10を掴むな)
2. GodotSteamは4.19.1-gde、入手はCodeberg
3. 統合は「SimRoot 1ノード+int配列state+自作MessageSerializer」の薄皮アダプタ方式
4. 検証は二段階: フェーズ1=同一PC2プロセス+ENet(デフォルトRPCアダプタ)でロールバック品質と30分デシンクゼロを確立→フェーズ2=2台実PC+Spacewar 480+Steam経路(A→ダメならB)で本番ゲート
5. 性能の事前試験: debug/rollback_ticksを8〜10に固定して30分ソーク(30tps=54,000tick)。to_int_array()保存/復元コストがボトルネック候補、先に計測
6. 撤退先Quantum 3の前提は有効。組み合わせ前例は無いが必要APIは全て確認済み

## 主要出典

- https://gitlab.com/snopek-games/godot-rollback-netcode (README/tags/releases/ソース)
- https://godotengine.org/asset-library/asset/2450 (stale注意)
- https://github.com/Fractural/GodotRollbackNetcodeMono / https://github.com/Kethku/gdrollback
- https://codeberg.org/godotsteam/godotsteam/releases / https://godotsteam.com
- https://godotengine.org/asset-library/asset/2445
- https://godotsteam.com/blog/2025/09/22/godotsteam-416-is-finally-here/
- https://godotsteam.com/classes/networking_messages/ / https://partner.steamgames.com/doc/api/ISteamnetworkingMessages
- https://github.com/GodotSteam/GodotSteam/discussions/881 (Spacewarテスト)
- https://www.snopekgames.com/course/rollback-netcode-godot/
- https://godotengine.org/asset-library/asset/2375 (netfox)
- https://doc.photonengine.com/quantum/current/quantum-intro
- https://forum.godotengine.org/t/gdscript-determinism/108246
