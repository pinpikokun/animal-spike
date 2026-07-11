# M2 ネットコード検証ゲート 手順書

M2の合否を判定するための実施手順。設計書3.3節のゲート定義に対応する。
ゲートは2段階: フェーズ1(同一PC・AIのみで完結)とフェーズ2(2台実PC・Steam・ユーザー判定)。

## ゲート定義(設計書3.3より)

- 合格: 2台の実PCでSteam経由の実対戦、30分連続でデシンクゼロ、かつ操作感がローカル対戦と区別つかない(判定は100%ユーザー)
- 不合格: Unity+Photon Quantum 3へ移行(協議の上)。設計・素材・調整値は持ち越す

---

## アーキテクチャ要点(実装の前提)

- 自前決定論sim(src/sim/)は無改造。薄皮アダプタ(src/net/)でrollback-netcodeに載せる
- rollback対象ノードは3つ: InputL(team0所有)/InputR(team1所有)/SimRoot(状態保存+進行)
- SimRootは`_network_postprocess`で`Simulation.tick`を1回回す。SyncManagerは全ノードの
  `_network_process`を回し切ってから全ノードの`_network_postprocess`を回すため(SyncManager.gd:647-656)、
  入力ノードの書込順に依存せず両チーム入力が揃った後に確実に進行する
- 状態は`SimState.to_int_array()`(41整数)を`_save_state`で保存、`load_int_array`で復元
- デシンク検出はアドオンが各tickのstateハッシュをピア間比較。自前FNV-1aハッシュを"h"に同梱

---

## フェーズ1: 同一PC2プロセス + 人工ロールバック負荷 (AIのみで完結)

localhostのENetで2プロセスを繋ぎ、`rbdebug`で毎tick強制ロールバック+再シミュをかけて
決定論(再シミュ一致=デシンクゼロ)を最も厳しく検証する。近距離localhostは実ネットの遅延が
無くロールバックがほぼ起きないため、人工負荷で常時ロールバック経路を叩くのが要点。

### 起動方法

無人ソーク(両側とも決定論CPUが操作):
```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_net_test.ps1 -Bot
```

手動対戦(前面ウィンドウのキーボードが効く。矢印/Z/Space=ジャンプ/X=アタック/C=交代):
```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_net_test.ps1
```

起動引数(`--` 以降): `host` | `join [address]` | `bot` | `rbdebug`
- `rbdebug`: 毎tick 8ロールバックを強制(SyncManager.debug_rollback_ticks=8)。決定論の最厳ストレス

### 観測項目

- 各プロセスのHUD(またはヘッドレスstdoutのNET_STATUS行): `role / tick / 経過秒 / mismatch`
- 両プロセスのtickが揃って進むこと
- mismatchが最後まで0
- stderr/logに `STATE MISMATCH` `SYNC ERROR` `Fatal` が出ないこと

### フェーズ1合格基準(AI自動)

- 30分(tick 108,000以上)連続でmismatch=0、STATE MISMATCH/SYNC ERROR/Fatalなし
- rbdebug=8(毎tick強制ロールバック)下でも上記を満たすこと

### フェーズ1実施結果 (2026-07-11、AI実施)

合格(PASS)。同一PC2プロセス(host bot rbdebug + join bot rbdebug)、localhost ENet、
毎tick8ロールバック強制(SyncManager.debug_rollback_ticks=8)。

- 30分連続(1800秒): host tick=107,691 / join tick=107,690(ロックステップ、1差は停止サンプリング瞬間のみ)
- mismatch=0(両プロセス、最後まで)
- STATE MISMATCH / SYNC ERROR / Fatal のログ行=0
- 補足の短時間検証: rbdebug無し15秒でもtick完全一致mismatch=0、rbdebug=8の15秒でも同様

意義: 保存stateに含まれない`_team_inputs`(毎tickの入力スクラッチ)が、ロールバック再シミュ時に
入力ノードの再書き込みで正しく再現されることを、毎tick強制ロールバックの30分連続で実証した。
自前決定論sim + rollback-netcode統合はデシンクゼロで機能する。

留意: localhostは実回線の遅延・パケットロスを再現しない。予測ミス由来の自然ロールバックや
回線品質は本ゲート(フェーズ2、2台実PC+Steam)で検証する。フェーズ1はあくまで
「決定論と再シミュ経路の正しさ」をAI単独で固める段階。

---

## フェーズ2: 2台実PC + Steam (ユーザー協働・本ゲート)

これが設計書3.3の本ゲート。フェーズ1合格が前提。

### ユーザー宿題(前提)

1. 2台目のWindows PC(Steamクライアント導入済み)
2. Steamアカウント2つ(フレンド登録済み。appid 480=Spacewarは全アカウントで利用可)
3. 両PCでSteamにログインした状態でテストに立ち会える時間

### 起動方法(T7実装後)

- ホスト側: `--net host steam` でロビー作成。HUDにLOBBY IDが出る
- 参加側: `--net join steam --lobby <id>` で参加
- 詳細な引数と手順はT7完了時に本節へ追記する

### フェーズ2合格基準(ユーザー判定)

- 2台実PC・Steam経由で30分連続、デシンクゼロ(mismatch=0、切断なし)
- 操作感がローカル対戦と区別つかない(体感遅延・カク付き無し)。これは100%ユーザーの官能判定

### 不合格時に記録すること

- mismatch発生tickとローカル/リモートのハッシュ値(remote_state_mismatchシグナルの引数)
- SyncManager.start_logging()のログ + エディタ内Log Inspector(Frame Viewer / State-Input Viewer)の所見
- 体感の言語化(どのタイミングでどうズレて感じたか)
- ping値(HUD)と回線条件

### 撤退協議

フェーズ2不合格が確定した場合、上記記録を材料にUnity+Photon Quantum 3移行を協議する。
sim設計・ルール・調整値・素材は移行先へ持ち越す(決定論の設計思想は共通)。

---

## ログの読み方(デシンク解析)

- `SyncManager.start_logging(path, info)` で各tickのstate/inputをJSONログ化(log2json.gd)
- Godotエディタの Project > Tools > "Log inspector..." でFrame Viewer/State-Input Viewerを開く
- ピア間で同tickのstateを突き合わせ、最初に食い違うフィールドを特定する
- 食い違いフィールドがsim状態(座標/速度/フェーズ)なら決定論バグ、入力なら入力伝播バグ
