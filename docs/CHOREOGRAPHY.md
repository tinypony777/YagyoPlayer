# 夜行絵巻 振付翻訳帳

この翻訳帳が扱う入力は、再生中に **15 Hz** で取得する `AVAudioPlayer.averagePower` を `0...1` に正規化し、立ち上がりを速く・下がりを緩やかに平滑化した**音量の近似値**だけです。拍、音楽的なアタック、デジタル無音、BPM、サビやセクション、曲の意味は検出していません。ここにある反応は、取得できた音量とその時間変化を、説明可能な視覚状態へ翻訳したものです。

## 入力から振付への対応

| 入力 | 判定 | 通常振付 | Reduce Motion | 実装状態 |
|---|---|---|---|---|
| stopped | 再生していない、または pause / stop 等で明示的に reset された状態 | 行列の移動、歩行フレーム、揺れを止め、中立姿勢に戻す | 同じ中立静止画を保つ | Step 4 feature branchに実装。現行full suite合格。今回のsemantic image setには含めない |
| unavailable | 再生中だが meter 値がない、または値が有限でない状態 | 再生は継続するが音量に根拠のない反応は出さない。提灯 halo を破線にし、CircularWaveform を中立色の破線・位相固定にして low / stopped と区別する | 移動を止めても、同じ破線の提灯 halo と、中立色・破線・位相固定の CircularWaveform を残す。VoiceOver 値は「音量表示を利用できません」 | 実装済み・現行full suite合格。今回のsemantic image setには含めない |
| level | 利用可能な有限値を `0...1` に clamp し、低・中・高の音量帯へ分ける | 通常時は固定 4 fps で歩行フレームを切り替え、level は bob の振幅と提灯 halo の大きさ・濃さへ反映する。歩行周期は BPM ではない | 横移動・bob・連続 scale・フレーム循環を止め、提灯 halo と円形波形の離散形状で音量帯を残す | Normal + KarakasaをPro／17eのsemantic AX testと独立native visual QAで確認済み |
| quietProxy | `level <= 0.08` が `0.70 s` 継続すると進入し、`level >= 0.14` で離脱する | 行進を遅くして bob を抑え、唐傘だけを専用 `hush` 姿勢、他の妖怪を `idle` fallback にする | 唐傘の `hush` と他妖怪の `idle` を静止表示し、低音量帯の提灯 halo・円形波形の離散形状・VoiceOver 値を残す | Quiet + KarakasaをProのsemantic AX testと独立native visual QAで確認済み |
| strongRiseProxy | `level >= 0.55` かつ、更新前の低速基準包絡との差が `>= 0.18` のとき、一度だけ強反応を始める | `anticipate` → `.open` → `recover`。`.open` は互換性のための内部名で、視覚は各妖怪の正面reaction。strong フレームを持つのは唐傘・鬼太鼓・木魚・狐火・天狗だけで、いずれも anticipate → reaction の専用2フレームをフレーム内の二次動作で表示する（鬼太鼓と木魚はバチの打ち込み、狐火は flare、天狗は羽団扇の hit）。旧アートを補っていた rect 変形（持ち上げ・squash 縮小・flare 拡大）と view 側のバチ別描画は撤去し、根拠のない妖怪へ新しい反応は足さない | 位置と scale を変えず、strong が active の間は各妖怪の reaction 静止姿勢と静的な輪郭線を保つ | Karakasa は Strong／Strong + Ushimitsu／Strong + Reduce Motion をProのsemantic AX testと独立native visual QAで確認済み。残り4体の frame-based reaction は feature branch 実装済みで、Mac 側 Simulator 検証待ち |
| resident | 現在トラックの UUID から互換性を保つ固定 roster で一体を割り当てる。聴取回数による選出ではない | resident を重複なく先頭へ移し、先導灯で示す | 同じ先頭位置、先導灯、VoiceOver の「先導は…」で示す | Karakasa選択を座標tapなしのsemantic AX testで確認。履歴による演出は未接続 |
| Ushimitsu | 丑三つ時モードが有効な状態。音量解析の結果ではない | 一つ目小僧を最後尾へ追加する。一つ目小僧も共通の通常・`quietProxy` の速度と bob に参加するが、strong 固有反応は持たない | 同じ最後尾の静止追加と VoiceOver の「丑三つ時」で示し、strong 固有の輪郭線は出さない | Strong + UshimitsuをProのsemantic AX testと独立native visual QAで確認済み |

現在候補はXcode 27.0のgeneric iOS buildに成功し、checked projectをiOS 27のiPhone 17 Pro destinationでfocused QA **11 / 11**、full suite **65 / 65**、いずれもskip 0で合格しました。semantic AX validationは座標tapなしで、iPhone 17 ProのNormal／Quiet／Strong／Strong + Ushimitsuのstate matrix **4 / 4**、Strong + Reduce Motion stability **1 / 1**、最小幅iPhone 17eのdefault Normal + Karakasa **1 / 1**を通過しました。Reduce Motionの`t0`／`t+2 s` full PNGは同一SHA-256で、canvas cropのdiffering bytesは0です。最初の17e menu試行失敗とauto diagnostics終了は正本結果から除外し、follow-up GREENだけを採用します。[証跡ledger](evidence/step4-karakasa/README.md)はcontact sheet／GIFとSimulator画像7枚のすべてを2名の独立native reviewerがAPPROVEDし、BLOCKER／MAJOR／MINORはいずれも0です。Pro Strongの右端寄りは切断なしのINFOだけでした。binary evidence commit `150219fea8a13ed95ea65885f5e7b46101cff9e5`で9 binary hashとlinkも確認済みです。旧32件／57件と紫色・横向き・横に開いた旧画像はsupersededで、ユーザー見た目承認だけが未完了です。

## 判定定数

実装の正本は `ParadeSignalConfiguration.production` です。初期値は次のとおりです。

- `quietProxy` 進入: `level <= 0.08` が `0.70 s` 継続。離脱: `level >= 0.14`。
- `strongRiseProxy` 候補: `level >= 0.55` かつ、低速基準包絡との差が `>= 0.18`。
- 低速基準包絡: 時定数 `0.80 s` の時間補正 EMA。候補判定には現在サンプルを取り込む前の基準値を使う。
- 再発火 cooldown: `0.45 s`。
- 再武装: cooldown 終了後、`level <= 0.32` または基準包絡との差が `<= 0.06` を一度満たしたとき。
- 強反応の各段階: anticipate `0.07 s`、`.open` `0.27 s`、recover `0.20 s`。`.open` は互換性名で、唐傘の視覚は正面reaction。
- reset 後の warm-up: `0.30 s`。
- サンプル時刻が逆行するか、間隔が `> 0.50 s` のときは時間依存状態を reseed し、そのサンプルでは強反応を発火しない。

低速基準包絡は `alpha = 1 - exp(-dt / 0.80)`、`baseline += alpha * (level - baseline)` で更新します。一定の大音量だけでは強反応を繰り返さず、いったん再武装条件を満たしてから再上昇したときだけ次の反応を許します。曲頭が大音量の場合も、seed と warm-up により強反応を出しません。

## 状態の境界

`pause`、`stop`、`seek`、track load 開始（次曲を含む）、load failure、play failure では視覚 reducer を reset します。再開後は最初の有限サンプルで基準値を seed し、warm-up が終わるまで `strongRiseProxy` を抑止します。meter timer の張り直しだけは意味上の reset ではありません。

`stopped`、`unavailable`、`quietProxy` は別の状態です。停止を「曲中の静けさ」と解釈せず、meter が読めない状態も低レベルとみなしません。視覚信号が利用できなくても、再生経路そのものは継続します。

## アートと公開のゲート

SNES 相当の基準体は唐傘（40×48 px、2倍整数表示 80×96 pt、透明を除き最大12色、`idle 1 + walk 4 + hush 1 + strong 2`）です。唐傘の8枚は、赤〜珊瑚色の正面円錐形、茶色の頭頂と金帯、中央の一つ目、笑い口と桃色の舌、淡色の一本足、一足の下駄を共有するcoherent familyです。紫、横顔、長い柄、横へ開いた傘や裏面は不採用です。

残り7体と一つ目小僧は、[残り行列妖怪・frame matrix 仕様](superpowers/specs/2026-07-12-remaining-yokai-frame-matrix.md)に基づき同じ行列用契約（40×48 px、最大12色、共通の墨 `k = 0x24160f`、`anchorX = 20`、`baselineY = 45`）で feature branch に描き直し済みです。`hush` 専用姿勢は唐傘だけが持ち、他は `idle` へ fallback します。strong 2 フレームを持つのは鬼太鼓・木魚・狐火・天狗（と唐傘）だけです。旧8bitアートと3倍表示は撤去し、行列は全体で2倍整数表示になりました。証跡は[残り妖怪の証跡ledger](evidence/step4-remaining-yokai/README.md)を正本とします。

唐傘のsemantic Simulator state、Reduce Motion静止、保存済みSimulator画像の独立native目視QAは完了しています。残り8体は構造検証・独立視覚QA・ユーザーMac(iOS 26.5)でのSimulator 7状態の取得と検収を経て、2026-07-12にPR #14のレビューでユーザー本人が見た目を承認しました。`main` 統合は引き続き唐傘(Draft PR #13)の承認とセットで行います。
