# Animal Spike (仮称)

1994年のPC-98フリーソフト「VOLLEY BALL 2on2」の精神的リメイク。
可愛い動物のチビキャラが2対2でバレーボールをする対戦ゲーム。Steam販売予定。

- 設計書: docs/superpowers/specs/2026-07-08-animal-spike-design.md
- 実装計画: docs/superpowers/plans/

## 開発環境の準備

1. Godot 4.6-stable win64 を下記からダウンロードして tools/godot/ に展開する
   https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_win64.exe.zip
2. pre-commitフックを導入する
   powershell -File scripts/install_hooks.ps1

## コマンド

- 全テスト実行: `powershell -File run_tests.ps1`
- ゲーム起動: `tools\godot\Godot_v4.6-stable_win64.exe --path .`
- エディタ起動: `tools\godot\Godot_v4.6-stable_win64.exe --path . --editor`

## アーキテクチャ (2階建て)

- src/sim/ : シミュレーション層。64bit整数の固定小数点(16.16)のみ。float禁止。
  同じ入力なら必ず同じ結果になる(決定論)。オンライン対戦のロールバックの土台
- src/display/ : 表示層。シミュレーション結果を描くだけ。float使用可
- data/rules.json : ゲームルールと物理の調整値。全て整数
- tests/ : ユニットテストとSyncTest(同一入力2回実行の一致検証)
- assets/third_party/ : トラックA仮素材(CC0)。出典は同フォルダのREADME参照

## 表示層 (M1b)

- 内部解像度640x360をSubViewportに描き、整数倍拡大して表示(滲みなし)
- root.tscn が最上位。game_view(本番ビュー)とSIM DEBUG VIEWをF1で切替
- ESCで表示設定: ウィンドウ2/3/4倍、フルスクリーン(整数倍+黒枠)、
  CRTスキャンライン(拡大後の物理ピクセルにドット1行あたり暗線1本)+強度スライダー。
  設定は user://settings.cfg に保存
- 操作: 矢印=移動 Z/スペース=ジャンプ X=サーブ/レシーブ/スパイク C=相方と交代
- 気持ちよさの掟: 世界は止まらない(ポーズ中もボールは慣性で転がり、キャラは動ける)。
  キャラはワープしない(ラリー再開でも位置リセットなし。初期配置は試合開始時のみ)

## ネット対戦 (M2検証)

決定論sim(src/sim/)を godot-rollback-netcode v1.0.0 に薄皮アダプタ(src/net/)で載せている。
rollback対象は3ノード(InputL/InputR/SimRoot)のみ。SimRootが`_network_postprocess`で
`Simulation.tick`を1回回し、SimStateのint配列(41整数)を保存/復元する。

- フェーズ1(同一PC2プロセス、AI検証済み):
  - 無人ソーク(両側CPU): `powershell -File scripts\run_net_test.ps1 -Bot`
  - 手動対戦: `powershell -File scripts\run_net_test.ps1`(前面ウィンドウのキーが効く)
  - 起動引数(`--`以降): `host` | `join [address]` | `bot` | `rbdebug`(毎tick強制ロールバック)
  - localhostでtickロックステップ一致・デシンクゼロを確認済み
- フェーズ2(2台実PC+Steam、ユーザー協働): 本ゲート。GodotSteam導入後に実施。
  前提=2台目Windows PC+Steamアカウント2つ(フレンド登録済み)
- 合否基準と手順: docs/superpowers/plans/2026-07-11-m2-gate-procedure.md

## ライセンス

- 本リポジトリのコード・データは All Rights Reserved(Steam販売予定の商用プロジェクト)。
  LICENSEファイルを意図的に置いていない
- assets/third_party/ のみCC0のサードパーティ素材(開発用仮素材)。出典は同フォルダのREADME参照

## 掟

- シミュレーション層にfloatを書かない(SyncTestが検出する)
- 状態フィールドを増やしたら sim_state.gd の to_int_array に必ず追加する
- ゲーム画面にプレースホルダー(四角や丸)を使わない。SIM DEBUG VIEWは開発計器で例外
- .ps1ファイルはASCIIコメントのみ(PowerShell 5.1がBOMなしUTF-8を誤読するため)
