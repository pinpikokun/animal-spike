# 原作8キャラのジャンプ高度と自然な共通軌道 実装計画

> 実装元契約:
> `docs/superpowers/specs/2026-08-03-original-character-jump-heights-design.md`
> 160行 / SHA-256 `F82E7FEAA3D12B36720ABCC971540A415EE21CABE01FD47C0FE885B4FDC8E543`

**Goal:** 原作8キャラの足元ジャンプ高度を原作資料へ近づけ、実動とCPU予測の標準ジャンプ式を一つへ統合する。

**Architecture:** `character_profile.gd` がキャラ別目標高度、`jump_arc.gd` がUME基準の共通重力と標準ジャンプ軌道の整数式を所有する。`player_movement.gd` と `sim_cpu.gd` は同じ取得APIと1tick更新APIを使い、キャラ分岐や式を持たない。

**Tech Stack:** Godot 4.6 / GDScript / 16.16固定小数点 / PowerShellテストラッパー

## Task 1: 設計版の固定確認

**Files:**
- Read: `docs/superpowers/specs/2026-08-03-original-character-jump-heights-design.md`

1. 実装直前に行数160とSHA-256を再計算する。
2. 一致しなければ実装を開始せず、差分を確認する。
3. 原作画像4枚は入力証拠として読み、gitへ追加しない。

## Task 2: プロフィール正本の失敗テスト

**Files:**
- Modify: `tests/unit/test_character_profile.gd`
- Modify: `tests/unit/test_char_stats.gd`

1. `test_character_profile.gd` に原作8人の目標高度表を独立リテラルで追加する。

```gdscript
var expected := {
	Chars.CHAR_TOME: 260,
	Chars.CHAR_HITO: 194,
	Chars.CHAR_PIYO: 74,
	Chars.CHAR_UME: 110,
	Chars.CHAR_CARBY: 236,
	Chars.CHAR_DUO: 182,
	Chars.CHAR_SEC1: 38,
	Chars.CHAR_SEC2: 150,
}
```

2. `Profile.jump_height_px_for_char(cid)` が表どおりになる検査を書く。
3. 非原作4人が既存A-Eフォールバック値135を保つ検査を書く。
4. `test_char_stats.gd` の実測ヘルパーで、原作8人の最高点が各目標±2pxになる検査を書く。
5. 非原作4人の最高点が変更前の135±2pxである検査を維持・拡張する。
6. `run_tests.ps1` を実行し、新API未定義だけを原因としてREDになることを確認する。

## Task 3: 共通JumpArcの失敗テスト

**Files:**
- Create: `tests/unit/test_jump_arc.gd`

1. `JumpArc` をpreloadするテストを追加する。
2. 高度38、74、110、135、236、260について、離陸初速と1tick更新の積分が目標最高点±2pxへ達する検査を書く。
3. UME基準110pxが上昇25tick、下降27tickを維持する検査を書く。
4. 全高度で上昇・下降重力が共通であり、TOMEとCARBYの滞空時間が高度比例でなく平方根比相当へ伸びる検査を書く。
5. `jump_held=false` の早離しがフルジャンプより低くなる検査を書く。
6. `JumpArc` 積分Y列と `PlayerMovement` を通した同キャラの実動Y列が着地まで一致する検査を書く。
7. `run_tests.ps1` を実行し、旧固定時間実装との差だけを原因としてREDになることを確認する。

## Task 4: プロフィールへ原作高度を追加

**Files:**
- Modify: `src/sim/character_profile.gd`
- Modify: `src/sim/chars.gd`

1. `character_profile.gd` の原作8プロフィールへ `jump_height_px` を追加する。
2. `jump_height_px_for_char(char_id)` を追加し、明示値、ランク値、標準Cの順で解決する。
3. `chars.gd` に薄い公開窓口 `jump_height_px(char_id)` を追加する。
4. A-E表とランク割当は変更しない。
5. プロフィール検査だけがGREENになることを確認する。

## Task 5: JumpArcを実装して人間実動を移行

**Files:**
- Create: `src/sim/jump_arc.gd`
- Modify: `src/sim/player_movement.gd`

1. UMEの110px、上昇25tick、下降27tickから共通上昇・下降重力を定義する。
2. 目標高度へ最も近い時間を整数二分探索で選び、同誤差なら長い側を選ぶ。
3. 丸め後の時間でも目標高度へ届く初速補正式を `launch_velocity()` に実装する。
4. `advance_velocity()` は高度引数を廃止し、早離し後の速度符号だけで共通重力を選ぶ。
5. `player_movement.gd` の標準空中更新と副作用なし予測を新APIへ移す。
6. 飛びつき、状態異常、固有技の縦速度には触れない。
7. JumpArc検査と実軌道検査がGREENになることを確認する。

## Task 6: CPU予測を同じJumpArcへ移行

**Files:**
- Modify: `src/sim/sim_cpu.gd`
- Modify: `tests/unit/test_cpu.gd`

1. preloadを `PlayerMovement` から `JumpArc` へ切り替える。`PlayerMovement` の別用途があれば残す。
2. `_jump_will_meet()` の離陸と縦更新を共通APIへ置換する。
3. `_sweet_jump_plan()` のY列生成を共通APIへ置換する。
4. `_air_will_meet_sweet()` の空中縦更新を共通APIへ置換する。
5. 次tickヒット位置予測を共通APIへ置換する。
6. `precision_horizon` をキャラ高度込みの `JumpArc.ticks(height, true) + JumpArc.ticks(height, false)` へ置換する。
7. 空中打球候補は `PlayerMovement` の副作用なし予測APIで同tick移動後座標を得る。
8. 候補入力の予測座標と本番1tick後座標の一致を検査する。
9. CPU発火条件、難易度、役割、乱数は変更しない。
10. `rg` で旧3ヘルパー名が `player_movement.gd` と `sim_cpu.gd` に0件であることを確認する。
11. 既存CPU検査と原作8キャラ実サーブ検査を実行する。

## Task 7: 回帰と試遊可能性の検証

**Files:**
- Modify if needed: `tests/unit/test_char_stats.gd`
- Modify if needed: `tests/unit/test_cpu.gd`

1. 原作8人のフルジャンプ高度を実測ログで確認する。
2. 最低高度SEC1でもネット上の接触可能領域へ足元+上リーチが届くことを検査する。
3. TOME最高点で足元Yが0未満にならないことを検査する。
4. 非原作4人は目標高度を維持しつつ自然時間へ移行し、飛びつき開始速度、炎上・被弾専用速度に差分がないことを既存検査で確認する。
5. 同期ゴールデンが変化した場合、原作キャラ高度が到達原因であることを追跡してから期待値を更新する。原因不明なら停止する。

## Task 8: 全件検証とClaude Code実差分レビュー

1. `git diff --check` を実行する。
2. `run_tests.ps1` を実行する。
3. 機能失敗、SCRIPT ERROR、同期失敗を0にする。
4. 空中候補性能は独立5プロセスの再承認式で得た75,000ns以内を確認する。
5. Claude Codeへ実差分、設計書、テスト結果を渡し、次を査読させる。
   - 性能値の正本がプロフィールだけか
   - 軌道式の正本がJumpArcだけか
   - 5箇所のCPU利用が漏れなく移行したか
   - 専用アクションと非原作を巻き込んでいないか
   - 暫定4人を確定値と誤記していないか
6. CriticalとImportantを0にする。

## Task 9: 報告とコミット

1. 変更全件、実差分、高度実測、全件検証、未検証事項をまとめる。
2. `vb2211/` をstageしない。
3. 設計書、計画、コード、テストだけをstageする。
4. `git diff --cached --check` とstage対象を確認する。
5. 日本語コミットメッセージでコミットする。
6. ユーザーから指示がないためpushはしない。
