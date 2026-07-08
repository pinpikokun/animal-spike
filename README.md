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

## 掟

- シミュレーション層にfloatを書かない(SyncTestが検出する)
- 状態フィールドを増やしたら sim_state.gd の to_int_array に必ず追加する
- ゲーム画面にプレースホルダー(四角や丸)を使わない。SIM DEBUG VIEWは開発計器で例外
- .ps1ファイルはASCIIコメントのみ(PowerShell 5.1がBOMなしUTF-8を誤読するため)
