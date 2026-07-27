# #82 を足場から隔離して緑の基準点を作る設計

## 1. 目的

この作業の目的は、未完成の #82「CPU の打ち方の選び方を原作の仮想打球テストへ作り直す」を現在の差分から完全に外し、完成済みの変更だけでフルテストが全件緑になる足場を作ることである。

#82 は修正も改良もしない。#82 に帰属する実装とテストを HEAD の状態へ戻すか作業ツリー外へ退避し、#88 完了後に設計から書き直せる状態で封印する。

この設計書は隔離作業だけを扱う。コードの新機能、ゲームプレイ値の再調整、乱数方式の変更、ゴールデンハッシュの更新は扱わない。

## 2. 背景

現在の未コミット差分は 19 ファイル、+907/-163 行であり、フルテスト 456 本中 6 本が赤である。pre-commit はフルテストを実行するため、この赤が残る限り通常のコミットは成立しない。

差分には次の 4 つの仕事が混在している。

1. #102 スパイクの横速度固定化。打つ位置により 2.3 倍変わっていた横速度を、押した横キーだけで決まる固定値へ変更した。変更前はコート奥 1578 px/s、ネット際 678 px/s、変更後は全位置 582 px/s。完成済み。
2. CPU サーブの打点上昇。トスと同時に跳ぶ挙動を、芯で捉えられる最も高い位置まで待つ挙動へ変更した。打点は 137 px から 172 px。完成済み。
3. CPU の反応遅延を原作準拠へ変更。完成済み。
4. #82 CPU の打ち方の選び方を原作の仮想打球テストへ作り直す変更。未完成であり、現在の赤 6 本の原因。近く設計から書き直すことが決定済み。

次の作業順は #86「乱数ハッシュの一本化」、続いて #88「決定論乱数を原作方式のステートフルへ移行」である。#82 の赤を残したまま乱数へ触ると、新しい赤が #82、#86、#88 のどれに由来するか判別できない。フルテストを変更検知の警報器として機能させるため、#86 より前に #82 だけを隔離する。

## 3. 根拠の区分

### 3.1 原作に由来する事実

- CPU 反応遅延の根拠は原作の `0x809E` と `0x0E72` にある停止コマ数 7/6/4/0 である。
- 本作で採用済みの換算は、原作を 30 fps と仮定した 0.30/0.20/0.10/0 秒を、本作 60 fps の 18/12/6/0 コマへ置き換えるものである。
- この隔離作業は原作挙動を新たに解釈しない。上記の採用済み変更を保持するだけである。

### 3.2 このリポジトリで決定済みのこと

- #102、CPU サーブ打点上昇、CPU 反応遅延変更は完成済みとして残す。
- #82 は HEAD へ戻し、#88 の後に設計から書き直す。
- #82 の封印は `git stash` ではなく打ち消し方式で行う。
- 全差分の staged/unstaged 版、`tests/unit/test_cpu_trial_shot.gd` の本体、HEAD 版の `src/sim/sim_cpu.gd` と `tests/unit/test_cpu.gd` は、Claude Code により作業ディレクトリ外へ退避済みである。
- staged にある `docs/superpowers/specs/` から `docs/archive/` への 30 件以上の rename は、そのまま保つ。
- Codex はコミットしない。Claude Code がフルテスト結果を確認してからコミットする。

## 4. 全体契約

### SCOPE-001 隔離の単位

#82 に帰属すると確定した hunk とテストだけを封印する。非 #82 の変更を巻き戻してはならない。

### SCOPE-002 復元の基準

封印対象の実装は HEAD の状態を唯一の復元基準とする。現在の #82 実装を修正、簡略化、部分利用してはならない。

### SCOPE-003 固定小数点

本作は Godot 4.6 と GDScript を使い、ゲームプレイ計算は固定小数点 16.16 である。float は禁止する。ただし本作業では計算式やゲームプレイ値を新設しない。

### SCOPE-004 退避物

復元には Claude Code が確保済みの退避物を使う。退避物または復元対象を一意に識別できない場合は作業を停止し、Claude Code に確認する。代替物を推測して作ってはならない。

### SCOPE-005 staged rename の保全

`docs/superpowers/specs/` から `docs/archive/` への staged rename は変更、解除、再作成しない。rename 検出を崩す操作も行わない。

## 5. ファイル別の帰属と処置

### 5.1 `src/sim/sim_cpu.gd`

このファイルは 24 hunk の外科手術対象である。ファイル全体を HEAD へ戻してはならない。

#### CPU-REMOVE-001 #82 として HEAD へ戻す変更

次の変更だけを HEAD の状態へ戻す。

- 冒頭コメント 2 行。「仮想打球だけは実打球処理を一時適用し、同じ関数内で全状態を復元する」という内容。
- `SALT_AIR_SHOT` 定数。
- `AIR_SHOT_FIRST`、`AIR_SHOT_DEEP_ONLY`、`AIR_SHOT_FARTHEST`、`AIR_SHOT_TOSS`、`AIR_SHOT_NONE` 定数。
- `_pick_air_shot` 一式の全面書き換え。+186 行の変更であり、`_pick_air_shot_result`、`_select_air_shot`、`_search_air_shot_candidates`、`_trial_spike_candidate`、`_evaluate_air_candidate`、`_air_shot_outcome`、`_air_shot_input`、`_pick_serve_spike` などの新設一式を含む。
- `decide()` 内の「位置取りが立てた左右・上下を消してから打ち方を確定する」入力マスク処理。
- `_decide_block()` から `absi(o.x - cfg.net_x) > FP.from_int(120)` 条件を撤去した 2 行と、その直上のコメント変更。条件とコメントを HEAD の状態へ戻す。
- `_decide_air_hit()` の `can_spike` から `and absi(p.x - cfg.net_x) < FP.from_int(120)` を外した変更。条件を HEAD の状態へ戻す。
- `_decide_air_hit()` で `P_TIQ >= 2` の分岐を捨て、`_pick_air_shot` に一本化した変更。分岐を HEAD の状態へ戻す。
- `_decide_serve()` 内の 1 行だけを戻す。`return _pick_serve_spike(s, p, cfg, s.serving_team, idx, dx * dx + dy_n * dy_n)` を、HEAD の `return SimInput.IN_ACTION | SimInput.IN_DOWN | fwd` へ戻す。

#### CPU-KEEP-001 仕事 3 として残す変更

- `PRESET_WEAK`、`PRESET_NORMAL`、`PRESET_STRONG`、`PRESET_MAX` の `P_DELAY` を 24/16/13/12 から 18/12/6/0 へ変更した内容。
- 上記変更の根拠コメント。

値の根拠はこの設計書へ複製して再実装せず、`src/sim/sim_cpu.gd` のプリセットを保持する。

#### CPU-KEEP-002 仕事 2 として残す変更

- `_sweet_jump_plan()` への `prefer_highest` 引数追加。
- `best_y` 変数追加。
- `better_plan` の比較ロジック。
- `if not prefer_highest and best_delay == 0: break` への変更。
- `_decide_serve()` が `_sweet_jump_plan(s, p, cfg, sweet_r, true)` を呼び、最も高い打点へ離陸を合わせる変更。
- 上記変更のコメント。

#### CPU-PRIORITY-001 hunk が重なる場合

HEAD への復元と保持対象が同じ関数内で接近または重複する場合、行単位の一括復元をしてはならない。CPU-REMOVE-001 に列挙した #82 の変更だけを HEAD へ戻し、CPU-KEEP-001 と CPU-KEEP-002 を残す。両立できないように見える場合は作業を停止し、Claude Code に確認する。

### 5.2 `tests/unit/test_cpu_trial_shot.gd`

#### TRIAL-REMOVE-001 全体を封印

652 行の staged ファイル全体が #82 のテスト本体である。

- `git rm --cached -- tests/unit/test_cpu_trial_shot.gd` によりインデックスから外す。
- ファイル本体は削除せず、Claude Code が確保済みの作業ディレクトリ外の退避先へ置く。
- 退避先を一意に確認できない場合は停止する。リポジトリ内へ別名コピーを残してはならない。
- 最終状態では、ファイルがインデックスにも作業ツリーにも存在しないこと。

### 5.3 `tests/unit/test_cpu.gd`

#### CPU-TEST-KEEP-001 残す変更

- ヘルパー `_cpu_jump_serve_result`。
- `test_cpu_jump_serve_strikes_in_upper_reach`。仕事 2 の検証である。
- `test_profile_pack_roundtrip` の期待値を 13 から 6 へ変更した内容。仕事 3 の検証である。

#### CPU-TEST-REMOVE-001 封印する変更

`test_cpu_jump_serve_reaches_front_and_back_court` 全体を封印する。このテストは、相手コートの手前半分と奥半分の両方へ落ちることを要求し、#82 の出目による打ち分けを検証している。現在赤であり、HEAD には存在しない状態へ戻す。

#### CPU-TEST-CONDITIONAL-001 初回は残す変更

`test_cpu_jump_serve_all_variations_clear_net` は初回のフルテストまで残す。全得点、全配置でネットを越える担保は仕事 2 に属する一方、`formation` 3 種を回す部分には #82 由来の可能性があるためである。

初回フルテストでこのテストが赤になった場合に限り、テスト関数全体を封印し、その事実を実装報告へ記録してから、フルテストを再実行する。緑なら残す。赤になる前に予防的に封印してはならない。

### 5.4 丸ごと残すファイル

次のファイルと変更は #102 由来または書類であり、すべて残す。#82 の隔離を理由に内容、staged 状態、移動状態を巻き戻してはならない。

- `tests/unit/test_hit.gd`
- `tests/unit/test_config.gd`
- `tests/unit/test_return_over_net.gd`
- `tests/unit/test_refactor_characterization.gd`
- `tests/unit/test_sync.gd`
- `data/rules.json`
- `src/sim/sim_config.gd`
- `src/sim/hit_resolver.gd`
- `src/sim/sim_state.gd`
- `AGENTS.md`
- `CLAUDE.md`
- `docs/` 配下の全変更と全移動

## 6. 実施順序

### STEP-001 承認済み設計書の同一性確認

Claude Code の承認時にピン留めされた本設計書の行数と SHA-256 を、実装開始直前に実ファイルと照合する。一致しなければ停止する。変更後の設計書から実装してはならない。

### STEP-002 退避物の識別

Claude Code が作業ディレクトリ外へ確保済みの staged/unstaged 差分、テストファイル本体、HEAD 版 `sim_cpu.gd`、HEAD 版 `test_cpu.gd` を識別する。不足または曖昧さがあれば停止する。

### STEP-003 `sim_cpu.gd` の外科手術

CPU-REMOVE-001 だけを HEAD へ戻し、CPU-KEEP-001 と CPU-KEEP-002 を保持する。ファイル全体の置換は禁止する。

### STEP-004 #82 テストの封印

TRIAL-REMOVE-001 と CPU-TEST-REMOVE-001 を実施する。CPU-TEST-KEEP-001 と CPU-TEST-CONDITIONAL-001 は保持する。

### STEP-005 保持対象と staged rename の保全確認

5.4 の全ファイルを保持し、staged rename が変化していないことを確認する。`data/rules.json` は未ステージのまま取りこぼしてはならない。`src/sim/sim_config.gd` が新キー `spike_mid_vx_px_s` を必須で読むため、Claude Code がコミットする際は `data/rules.json` を必ず同じコミットへ含める。

### STEP-006 初回フルテスト

次を実行する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1
```

`test_cpu_jump_serve_all_variations_clear_net` が赤なら CPU-TEST-CONDITIONAL-001 に従って封印し、事実を記録する。それ以外の赤はテストやゴールデン値を合わせて解消せず、#82 の剥離漏れまたは保持対象の破損として原因を特定する。

### STEP-007 条件付き再実行

CPU-TEST-CONDITIONAL-001 を封印した場合は、同じコマンドでフルテストを再実行する。封印しなかった場合は不要である。

### STEP-008 引き渡し

Codex はコミットしない。Claude Code へ、最終 `git diff`、フルテストの全出力、`test_cpu_jump_serve_all_variations_clear_net` を残したか封印したか、ビルドまたは実行結果が必要な場合はその結果、未確認事項を引き渡す。Claude Code が実結果を確認した後にコミットする。

## 7. 合格条件

### ACCEPT-001 フルテスト

`powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1` が全件緑で完了すること。初回で条件付きテストを封印した場合は、封印後の再実行結果を合否判定に使う。

### ACCEPT-002 合成ゴールデンハッシュ

`tests/unit/test_sync.gd` の `GOLDEN_COMBINED_HASH` を一切変更せず、値 `1173764543217565771` のままで同期テストが緑になること。

この条件は外科手術の完全性を機械的に判定する核心である。この値には #102 と CPU 反応遅延の変更が、すでに「第5回」「第6回」として反映済みである。現在の赤で得られる `actual=3859907212180814244` は #82 の実装が乗っているために生じている。#82 を完全に剥がせば、ゴールデン値を張り替えずに `1173764543217565771` へ戻ることが期待される。

張り替えが必要になった場合、それは期待値の問題ではなく、#82 の剥離漏れまたは保持対象の破損を示す。値を実装へ合わせてはならない。原因を特定するまで作業を止める。

### ACCEPT-003 条件付きテスト

`test_cpu_jump_serve_all_variations_clear_net` が初回フルテストで赤になった場合だけ、そのテストを封印し、その事実を記録したうえで再実行したフルテストが全件緑になること。

### ACCEPT-004 差分の帰属

最終差分に #82 の実装および無条件封印対象テストが残らず、仕事 1、仕事 2、仕事 3、書類整理が残っていること。

### ACCEPT-005 起動データの一体性

コミット候補に `src/sim/sim_config.gd` と、新キー `spike_mid_vx_px_s` を持つ `data/rules.json` の両方が含まれること。片方だけの状態を合格としてはならない。

## 8. 禁止事項

- `git stash` を使わない。
- staged の `docs/superpowers/specs/` から `docs/archive/` への rename に触らない。
- pre-commit をスキップしない。`--no-verify` を使わない。
- #82 を直さない、改良しない、別方式へ置換しない。HEAD の状態へ戻すだけにする。
- `GOLDEN_COMBINED_HASH` を変更しない。
- テスト期待値を現在の #82 実装へ合わせない。
- `data/rules.json` をコミット候補から漏らさない。
- Codex はコミットしない。
- 帰属表にない改善、リファクタリング、書類変更を同時に行わない。
- float を導入しない。

## 9. 停止条件

次のいずれかに該当したら、推測で続けず Claude Code に確認する。

- 承認時にピン留めされた本設計書の行数または SHA-256 が一致しない。
- 退避物の所在、版、対応する staged/unstaged 区分を一意に確認できない。
- CPU-REMOVE-001 と CPU-KEEP-001 または CPU-KEEP-002 が両立しない。
- 帰属表にない hunk を戻す必要がある。
- フルテストの赤を解消するために #82 以外の実装変更が必要に見える。
- `GOLDEN_COMBINED_HASH` の変更が必要に見える。
- 作業範囲が #82 の隔離を越える。
