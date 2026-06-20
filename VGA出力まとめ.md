# DE0-CV で VGA 画面出力 — 作業まとめ

DE0-CV(Terasic, Cyclone V `5CEBA4F23C7`)で VGA 640×480@60Hz のカラーバーを
実機モニタに表示するまでの記録。やったこと・わかったこと・再現手順を1ファイルにまとめる。

- 作成物: `Desktop\FPGA-Monitor\vga1\`(Quartus プロジェクト一式)
- 結果: 実機モニタにカラーバー正常表示(初回ハードウェア反復で成功)
- 参考にした既存物: `Desktop\FPGA-kougi`(講義課題・階層設計)、`Desktop\fpga遊び`(asobi1=モグラたたき)

---

## 1. 結論(TL;DR)

- VGA は **外部DACチップ不要**。DE0-CV は FPGA ピンに直結した **4bit/ch 抵抗ラダーDAC**(R/G/B 各4bit=4096色)+ HS/VS の合計14本だけで映る。
- 25MHz ピクセルクロックは **PLLも派生クロックも使わず**、CLOCK_50(50MHz)+「1クロックおきのクロックイネーブル」で作るのが一番堅牢。
- HS / VS / RGB は **1つのclockedプロセスから同一レイテンシで出す**と、同期と色が1pxもずれない。
- 一発で映すコツは **ピン配置を権威ある資料で確定してから実装する**こと。「コンパイルは通るのに映らない」最頻の原因はピン間違い。

---

## 2. 環境

| 項目 | 内容 |
|---|---|
| ボード | Terasic DE0-CV(Cyclone V `5CEBA4F23C7`、FBGA484、speed grade 7) |
| ツール | Quartus Prime **25.1std.0 Lite Edition** |
| CLI パス | `C:\altera_lite\25.1std\quartus\bin64` |
| 書き込み | USB-Blaster(JTAG)。`jtagconfig` で `5CE(BA4\|FA4)` と出れば接続OK |
| モニタ | VGA ケーブルで DE0-CV の VGA 端子に接続 |

主要CLI: `quartus_sh`(コンパイル)、`quartus_pgm`(書き込み)、`jtagconfig`(接続確認)。

---

## 3. プロジェクト構成

```
Desktop\FPGA-Monitor\vga1\
├── vga1.vhd     … VGAコントローラ本体(同期生成＋カラーバー)
├── vga1.qsf     … デバイス指定・ピン割当・I/O標準
├── vga1.qpf     … プロジェクトファイル
├── vga1.sdc     … タイミング制約(50MHzクロック定義)
└── output_files\
    ├── vga1.sof … 書き込み用コンフィグ(これをFPGAへ流す)
    ├── vga1.pin … 実際のピン配置結果(検証に使う)
    └── *.rpt    … 各種レポート(fit/sta など)
```

---

## 4. VGA の理屈(640×480@60Hz)

ブラウン管時代の名残で、画面は「表示領域＋見えない余白(ポーチ)＋同期パルス」を
一定タイミングで繰り返す。下の数を**1ピクセルもズラさず**カウンタで刻めば映る。

### タイミング定数

| 方向 | 表示 | フロントポーチ | 同期パルス | バックポーチ | 合計 |
|---|---|---|---|---|---|
| 水平(px) | 640 | 16 | 96 | 48 | **800** |
| 垂直(line) | 480 | 10 | 2 | 33 | **525** |

- ピクセルクロック理想値 = 800 × 525 × 60Hz ≒ **25.175MHz**。**25.0MHz でも実用上問題なく映る**(リフレッシュ ≒ 59.5Hz)。
- **HS / VS は両方とも負論理(active-low)**。同期区間だけ `'0'`、それ以外 `'1'`。
- **表示領域外(ブランキング)は RGB を必ず黒(0)** にする。さもないと同期を見失う/ノイズが出る。

### 同期区間の計算(このプロジェクトの値)
- HS = `'0'` は hcount ∈ [656, 752)（= 640+16 〜 +96、ちょうど96px）
- VS = `'0'` は vcount ∈ [490, 492)（= 480+10 〜 +2、ちょうど2line）

---

## 5. DE0-CV の VGA ピン配置(超重要)

DE0-CV User Manual Table 3-10 準拠。**複数ソースで照合済み**。I/O標準は全て **3.3-V LVTTL**。

```tcl
# クロック
set_location_assignment PIN_M9  -to CLOCK_50
# 赤 R[3:0]（[3]がMSB, [0]がLSB）
set_location_assignment PIN_A9  -to VGA_R[0]
set_location_assignment PIN_B10 -to VGA_R[1]
set_location_assignment PIN_C9  -to VGA_R[2]
set_location_assignment PIN_A5  -to VGA_R[3]
# 緑 G[3:0]
set_location_assignment PIN_L7  -to VGA_G[0]
set_location_assignment PIN_K7  -to VGA_G[1]
set_location_assignment PIN_J7  -to VGA_G[2]
set_location_assignment PIN_J8  -to VGA_G[3]
# 青 B[3:0]
set_location_assignment PIN_B6  -to VGA_B[0]
set_location_assignment PIN_B7  -to VGA_B[1]
set_location_assignment PIN_A8  -to VGA_B[2]
set_location_assignment PIN_A7  -to VGA_B[3]
# 同期
set_location_assignment PIN_H8  -to VGA_HS
set_location_assignment PIN_G8  -to VGA_VS
```

> 注意: DE0-Nano など別ボードは `VGA_HSYNC` 等で名前もピンも違う。**DE0-CV 用の表だけを使う**こと。

---

## 6. 設計のポイント（局所解にハマらないための判断）

### (1) クロックは「派生クロック」でなく「クロックイネーブル」
`pix_clk <= not pix_clk;` で作った25MHz信号を**そのままクロックとして使う**のは罠。
非グローバル配線になりタイミング解析が不安定。代わりに全部 CLOCK_50 で動かし、
`pix_en`(1クロックおきに'1')が立った時だけ処理する。**単一クロックドメイン**で堅牢。

```vhdl
process(CLOCK_50) begin
  if rising_edge(CLOCK_50) then
    pix_en <= not pix_en;            -- 50→25MHzイネーブル
    if pix_en = '1' then
      ... カウンタ更新・HS/VS・色 ...
    end if;
  end if;
end process;
```

### (2) HS / VS / RGB は1プロセスで同一レイテンシに
最初、カウンタ／同期／色を**別々のprocessに分けた**ら、各段でレジスタ遅延が変わり
**同期が色より1px先に出る**(=画像が1pxずれ、端の列が化ける)不具合になった。
→ **全出力を1つのclockedプロセス**で同じ hcount から叩き出して解決。

### (3) ブランキングは黒を強制
表示領域判定 `if (hcount<640) and (vcount<480)` が偽の時は RGB=0 を**必ず**出す。

### (4) `hcount / 80` の定数除算
バー番号 `bar := hcount / 80` は除算だが、80は定数なので Quartus が固定乗算に最適化。
リソース些少(全体で38レジスタ)・実害なし。気になるなら閾値比較に置換可。

---

## 7. 再現手順(ビルド→書き込み)

PowerShell でも Git Bash でも可。CLI に PATH を通すか、フルパスで叩く。

### 7-1. 接続確認
```bash
export PATH="/c/altera_lite/25.1std/quartus/bin64:$PATH"
jtagconfig          # → "1) USB-Blaster [USB-0]  ... 5CE(BA4|FA4)" が出ればOK
```

### 7-2. コンパイル(約3〜4分)
```bash
cd "/c/Users/kaga/Desktop/FPGA-Monitor/vga1"
quartus_sh --flow compile vga1
# 成功すると output_files/vga1.sof が生成される
```

### 7-3. 書き込み(揮発SRAM・電源切ると消える=テスト向き)
```bash
quartus_pgm -c "USB-Blaster" -m JTAG -o "p;output_files/vga1.sof"
# "Configuration succeeded -- 1 device(s) configured" が出れば成功
```

> 電源を切っても残したい場合は .jic を作って EPCS/コンフィグデバイスへ書く(今回は未使用)。

### 7-4. 期待される表示
640×480 全面に縦カラーバー(各80px):
**白 → 黄 → シアン → 緑 → マゼンタ → 赤 → 青 → 黒**(右端80pxは黒)。

---

## 8. 検証で見るべきレポート

| 確認項目 | 場所 / コマンド | 合格基準 |
|---|---|---|
| エラー0 | コンパイルログ末尾 | `0 errors` |
| ピンが正しい位置か | `output_files/vga1.pin` | R/G/B/HS/VS が§5の表通り |
| タイミング達成 | `output_files/vga1.sta.rpt` の Fmax | 50MHz超(本件 **104.89MHz**) |
| フィッタ成功 | `output_files/vga1.fit.summary` | `Fitter Status : Successful` |

無害な警告(無視可): NUM_PARALLEL_PROCESSORS未指定 / LogicLockライセンス / 未使用ピンのI/O割当。

---

## 9. トラブルシュート(症状→原因の当たり)

| 症状 | 第一に疑う原因 | 対処 |
|---|---|---|
| 真っ暗・信号なし | ピン間違い / ケーブル / モニタ入力切替 | `vga1.pin` を§5と照合、ケーブル確認 |
| 画面が流れる・同期しない | HS/VS の極性、ポーチ値、ピクセルクロック | 負論理か、§4の数値か確認 |
| 色が違う/出ない色がある | RGB のビット順(MSB/LSB)・配線 | `VGA_R[3]`がMSBか確認 |
| 端の列だけ化ける | 同期と色のレイテンシ差 | §6-(2)、1プロセス化 |
| 画面全体がうっすら/暗い | I/O標準が3.3-V LVTTLでない | qsf の IO_STANDARD 確認 |

---

## 10. やってわかったこと(教訓)

1. **ピンの裏取りが最重要**。映らない事故の大半はピン。実装前に権威資料＋独立ソースで照合すると一発で映る。
2. クロックは**イネーブル方式が定石**。派生クロックは避ける。
3. 同期と映像は**同一プロセス・同一レイテンシ**で出す。分けると微妙にずれる。
4. **カラーバーは最高の診断パターン**。RGB各chの配線正否・同期の安定が一目で分かる。
5. 揮発書き込み(`p;*.sof`)は**数秒**で試せる。素早く回せる=反復が速い。
6. Cyclone V のこの規模なら Fmax は楽勝(104MHz/要求50MHz)。タイミングは心配無用。

---

## 11. 次の発展アイデア

- スイッチ(SW)でパターン切替(カラーバー / 単色 / 市松 / グラデーション)
- 文字・図形描画(フォントROM、ライン/矩形)
- フレームバッファ(オンチップRAM)＋簡単な描画
- `fpga遊び/asobi1` のモグラたたきを**VGA画面表示版**に移植(LED→画面のモグラ)
- 25.175MHz を PLL で正確に作る(現状25.0MHzでも可)

---

## 12. 応用: 写真画像の表示(img1)

カラーバー(vga1)の次のステップとして、**実写画像(千葉工大 正門)を VGA 表示**した記録。
プロジェクト: `Desktop\FPGA-Monitor\img1\`。**実機表示成功**。

### 12-1. 最大の論点 = オンチップメモリ容量
- 640×480×12bit ≒ **3.7Mbit** は 5CEBA4 の M10K(**308ブロック=3,080Kbit**)に**収まらない**。
- 解 = **低解像度ストア + 表示時スケールアップ**。本件は **320×240×12bit(921,600bit=29%)** を M10K ROM に置き、表示時に**2倍**して640×480化。
  - M10K は12bit幅だと512×16詰めになり約150ブロック使用(幅方向に4bit余るのは正常)。

### 12-2. 画像 → MIF(`make_mif.py`、Pillow)
1. JPEGを**アスペクト保持**で320×240に収め、黒キャンバスに貼って**レターボックスを焼き込む**(上下黒帯)。
2. 各ch 8bit → 4bit(`round(v/255*15)`)。
3. `data = R4<<8 | G4<<4 | B4`、`addr = y*320 + x` で **76,800語の .mif** を出力。
4. 確認用に4bit量子化を反映した `expected_preview.png` も出力 → **焼く前に見て faithful か検証**。

> 重要: VHDL を単純2倍スケールに保つため、**レターボックスや量子化は画像(MIF)側に全部寄せる**。ハードのバグ表面積を最小化できる。

### 12-3. M10K ROM の VHDL 推論(要点)
```vhdl
type rom_t is array (0 to 76799) of std_logic_vector(11 downto 0);
signal rom : rom_t;                                   -- constantでなくsignal
attribute ram_init_file : string;
attribute ram_init_file of rom : signal is "image.mif";   -- MIFで初期化
attribute ramstyle : string;
attribute ramstyle of rom : signal is "M10K";         -- M10Kへ誘導
...
if rising_edge(CLOCK_50) then
  if pix_en='1' then
    rom_q <= rom(addr);   -- 同期読み出し(これがM10K化の条件)。レイテンシ1。
  end if;
end if;
```
- **同期読み出し(クロック内read)が必須**。非同期readだとM10Kにならずロジックに落ちる。
- ROM配列は**signal**で、RTLで代入しない(初期値はMIF由来)→ `Warning(10541) implicit default` は**正常**。
- アドレスは `to_integer(unsigned(...))` か integer。範囲外参照を避けるため**ブランキング時は addr:=0**。

### 12-4. レイテンシ整合(今回の肝)
ROM読出に1サイクル遅延があるので、**HS/VS/RGB を全部 stage-2 レジスタに揃える2段パイプライン**にする。
- 同期は「**インクリメント前**の hcount」から計算 → アドレスと同じ index を共有。
- stage-1: `rom_q / hs1 / vs1 / von1` を同時ラッチ。
- stage-2: `VGA_HS/VS` と `RGB(=von1? rom_q : 黒)` を同時確定。
- → 全出力が同一 index・同一遅延=**画像と同期が1pxもズレない**。

### 12-5. 検証ポイント(画像特有)
| 確認 | 場所 | 合格 |
|---|---|---|
| ROMがM10Kに載ったか | `fit.summary` の Total block memory bits | 921,600 bit(ロジック化していない) |
| MIFを読んだか | コンパイルログ | `INIT_FILE = image.mif` |
| タイミング | sta.rpt Fmax | 本件 **121MHz**(要求50) |
| 色順・向き | 実機目視 | 色正常・上下左右正・レターボックス対称 |

### 12-6. 教訓(画像表示)
1. **容量が全ての制約**。まず「載るか」を datasheet で確認 → 解像度/色深度/スケール比を決める。
2. **複雑さは画像生成(Python)側に寄せ、VHDLは単純に保つ**(レターボックス・量子化・並べ替えは全部MIFで)。
3. **同期読み出し＋レイテンシ整合**がROM表示の2大ポイント。fitレポートでM10K化を必ず確認。
4. 焼く前に **expected_preview.png で「あるべき絵」を自分の目で確認**しておくと、実機の不具合切り分けが速い。

### 次の発展(画像)
- SDRAM(64MB)コントローラで**フル解像度640×480フレームバッファ**。
- スイッチで複数画像切替、スクロール/ズーム。
- パレット(インデックスカラー)で容量を更に圧縮し高解像度化。

---

_最終更新: 2026-06-19 / vga1(カラーバー)・img1(写真画像) ともに実機表示まで確認済み_

---

## 13. 応用2: VGAゲーム「Dino」(T-Rex Runner クローン, dino)

img1の画像表示を発展させ、**キャラスプライト＋ゲームロジックで遊べるゲーム**を実装。
プロジェクト: `Desktop\FPGA-Monitor\dino\`。**実機で完全プレイ可能**(タクトスイッチKEY0で操作)。

### 13-1. 仕様
- キャラ(提供スプライト, 56×72, 4フレーム透過)が固定x=80で走り、KEY0でジャンプ。
- 白背景・地面ライン・サボテン(矩形)が右→左にスクロール。衝突でGameOver、KEY0でリスタート。
- スコアは7セグ HEX0-3、進むほど加速。FSM = READY / RUN / OVER。
- **操作は全てタクトスイッチ KEY0**(スタート/ジャンプ/リスタート)。

### 13-2. スプライト(透過)の作り方 — `make_sprite.py`
- 4×4シートを**背景色のギャップで自動セグメント**して16フレーム検出 → 右向き走りの1行(4枚)を採用。
- 背景色 `(176,186,255)` を**クロマキー透過**。pixel art なので**NEAREST**で縮小(エッジを保つ)。
- 13bit ワード `opaque(bit12) | R4 | G4 | B4` で `sprite.mif` 出力。`addr = frame*DW*DH + y*DW + x`。
- 焼く前に `expected_game.png`(白背景+地面+サボテン+キャラ合成)で**透過とレイアウトを目視確認**。

### 13-3. 描画 = race-the-beam の多層合成
フレームバッファを持たず、各ピクセルで**レイヤ優先度**で色を決める:
```
キャラ(透過ROM, 不透明画素のみ) > サボテン(矩形) > 地面ライン > 白背景
```
- スプライトROMは**同期読み出し(レイテンシ1)**。img1と同様、HS/VS/RGB と各レイヤ選択ビット
  (sin1/obs1/grd1/von1)を**全てstage-1で同時ラッチ→stage-2で合成**し、画像と同期を完全整合。
- スプライトアドレスは領域外で `0` に固定(範囲外参照を防止)。

### 13-4. ゲームロジック = 毎フレーム1回更新(tearing無し)
- **ゲーム更新は vblank 先頭(`hcount=0 and vcount=480`)で1回 = 60Hzティック**。
  表示中はゲーム状態が変わらないので**画面の途中で値が変わらない=ちらつかない**。
- ジャンプ物理: 整数 `dino_y/vy`、`JUMP_V=13, GRAV=1` → 山高さ≈91px・滞空≈26tick。
- 障害物: LFSR乱数で間隔/高さ、**待ち行列(maxox+gap)で間隔を保証**。
- 衝突: x重なり AND `dino_y < 障害物高` の AABB。
- KEY エッジはティック間で検出(フレーム単位デバウンス)。

### 13-5. ここでハマった/学んだこと
1. **整数の `range` はハード幅を決める=実質的な型**。
   `range -64 to 900` に対しリスポーン式が最大~1635 → **コンパイルは通るが実機で座標が化ける**
   オーバーフロー。敵対的レビューで発見、`range -64 to 4095` に拡張して解消。
   → **「コンパイル成功」≠「正しい」。式が取り得る最大値が range に収まるか必ず確認**。
2. レビューで**パイプライン整合・tick発火回数・アドレス範囲・同期極性**を事前検証し、
   焼く前に重大バグ1件を潰せた(初回ハードで完動)。
3. 複雑さは**スプライト生成(Python)側**に寄せ、VHDLはROM参照＋合成に集中(img1の教訓を踏襲)。
4. **vblankでゲーム更新**はソフトのVSync待ちと同じ発想。tearing無しの定石。

### 次の発展(ゲーム)
- 障害物を矩形→サボテン/鳥スプライト化、昼夜切替、効果音(基板のブザー/PWM)。
- スコアを画面内にフォントROMで表示、ハイスコア保持。
- 二段ジャンプ/しゃがみ、難易度カーブ調整。

---

_最終更新: 2026-06-19 / vga1・img1・dino いずれも実機で確認済み(dinoはプレイ可能)_
