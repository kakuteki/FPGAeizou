# FPGAeizou — DE0-CV VGA 映像出力

Terasic DE0-CV(Cyclone V `5CEBA4F23C7`)を使い、FPGA から VGA 640×480@60Hz の映像を実機モニタに出力する一連の作品をまとめたリポジトリです。カラーバーから始め、写真表示、そして遊べるゲームまで段階的に発展させています。すべて実機での表示・動作を確認済みです。

## 環境

| 項目 | 内容 |
|---|---|
| ボード | Terasic DE0-CV(Cyclone V `5CEBA4F23C7`, FBGA484, speed grade 7) |
| ツール | Quartus Prime 25.1std.0 Lite Edition |
| 表示 | VGA(640×480@60Hz)。外部DAC不要、FPGA直結の 4bit/ch 抵抗ラダーDAC(4096色) |
| 書き込み | USB-Blaster(JTAG) |

VGA は 25MHz ピクセルクロックを「CLOCK_50 + 1クロックおきのクロックイネーブル」で生成し、HS/VS/RGB を同一プロセス・同一レイテンシで出力する構成を共通の土台にしています。

## 収録物

| ディレクトリ | 内容 | 操作 |
|---|---|---|
| [`vga1/`](vga1/) | カラーバー表示。VGA 同期生成の基礎。縦8色バー(白/黄/シアン/緑/マゼンタ/赤/青/黒) | — |
| [`img1/`](img1/) | 写真画像表示。320×240×12bit を M10K ROM に格納し表示時に2倍スケール | — |
| [`dino/`](dino/) | ゲーム「Dino」(T-Rex Runner クローン)。透過スプライト+ゲームロジック | KEY0 = ジャンプ/スタート/リスタート |
| [`xstg/`](xstg/) | 縦スクロールシューティング(XEVIOUS 風)。空中敵/地上ターゲット/2系統武器 | KEY3/2=左右, SW1/0=上下, KEY1=ショット, KEY0=ボム |

それぞれ独立した Quartus 一式(`*.vhd` / `*.qsf` / `*.qpf` / `*.sdc`)になっています。

## 設計の要点

- クロックは派生クロックでなくクロックイネーブル方式(単一クロックドメインで堅牢)
- HS/VS/RGB は1プロセスで同一レイテンシに揃える(同期と映像が1pxもずれない)
- ROM は同期読み出し(M10K に推論させる条件)+ レイテンシ整合のための2段パイプライン
- 複雑さは Python 側(画像/スプライト生成)に寄せ、VHDL は単純に保つ(レターボックス・量子化・透過処理は MIF 側で完結)
- ゲーム更新は vblank で1回(60Hz ティック、tearing なし)

詳しい技術記録・再現手順・トラブルシュートは [`VGA出力まとめ.md`](VGA出力まとめ.md) を参照してください。

## ビルド & 書き込み

```bash
# PATH を通す
export PATH="/c/altera_lite/25.1std/quartus/bin64:$PATH"

# 接続確認
jtagconfig

# コンパイル(例: vga1)
cd vga1
quartus_sh --flow compile vga1

# 書き込み(揮発・電源断で消える, テスト向き)
quartus_pgm -c "USB-Blaster" -m JTAG -o "p;output_files/vga1.sof"
```

他の収録物もディレクトリ名・名前を読み替えれば同手順でビルド・書き込みできます。
