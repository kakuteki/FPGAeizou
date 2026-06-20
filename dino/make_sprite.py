# -*- coding: utf-8 -*-
# スプライトシート(447x447, 4x4)のrow3=右向き走り4フレームを抽出し
# 透過(クロマキー)付き 13bit スプライトROM sprite.mif を生成する。
#   word = opaque(bit12) | R4(11:8) | G4(7:4) | B4(3:0)
#   addr = frame*DW*DH + y*DW + x   (frame=0..3)
# 期待ゲーム画面 expected_game.png も出力(白背景+地面+サボテン+キャラ)。
from PIL import Image
import numpy as np

SRC = r"C:\Users\kaga\Downloads\images (1).jpg"
COLS = [(0,71),(114,189),(228,300),(343,418)]
ROW3 = (340,441)
BG = np.array([176,186,255]); THR = 60
DW, DH = 56, 72            # 画面上のスプライトサイズ
NFR = 4

im = Image.open(SRC).convert("RGB")
a = np.asarray(im).astype(int)

# 共通bbox(row3の4フレームを通した前景の和)
y0,y1 = ROW3
xs0=xs1=ys0=ys1=None
for (x0,x1) in COLS:
    sub = a[y0:y1+1, x0:x1+1]
    fg = (np.abs(sub-BG).sum(2) > THR)
    ys,xs = np.where(fg)
    if len(xs)==0: continue
    xs0 = xs.min() if xs0 is None else min(xs0, xs.min())
    xs1 = xs.max() if xs1 is None else max(xs1, xs.max())
    ys0 = ys.min() if ys0 is None else min(ys0, ys.min())
    ys1 = ys.max() if ys1 is None else max(ys1, ys.max())
bw, bh = xs1-xs0+1, ys1-ys0+1
# 高さ基準でアスペクト保持縮小→DW×DH透過キャンバスに中央配置
sh = DH; sw = max(1, round(bw * DH / bh))
if sw > DW: sw = DW; sh = max(1, round(bh * DW / bw))
ox = (DW - sw)//2; oy = DH - sh   # 足元を下端に揃える

frames = []
for (x0,x1) in COLS:
    cell = im.crop((x0+xs0, y0+ys0, x0+xs1+1, y0+ys1+1))
    ca = np.asarray(cell).astype(int)
    alpha = (np.abs(ca-BG).sum(2) > THR).astype(np.uint8)*255
    rgba = np.dstack([np.asarray(cell), alpha]).astype(np.uint8)
    spr = Image.fromarray(rgba, "RGBA").resize((sw,sh), Image.NEAREST)
    canvas = Image.new("RGBA",(DW,DH),(0,0,0,0)); canvas.paste(spr,(ox,oy),spr)
    frames.append(canvas)
print(f"bbox {bw}x{bh} -> sprite {sw}x{sh} on {DW}x{DH} @({ox},{oy}); frames={len(frames)}")

def q4(v): return min(15, max(0, round(v/255*15)))

with open("sprite.mif","w",encoding="ascii") as f:
    f.write(f"-- dino sprite: {NFR} frames, {DW}x{DH}, 13bit opaque|R4G4B4\n")
    f.write(f"DEPTH = {NFR*DW*DH};\nWIDTH = 13;\nADDRESS_RADIX = DEC;\nDATA_RADIX = HEX;\n\nCONTENT\nBEGIN\n")
    addr=0
    for fr in frames:
        px = fr.load()
        for y in range(DH):
            for x in range(DW):
                r,g,b,al = px[x,y]
                op = 1 if al>127 else 0
                data = (op<<12) | (q4(r)<<8) | (q4(g)<<4) | q4(b) if op else 0
                f.write(f"    {addr} : {data:04X};\n"); addr+=1
    f.write("END;\n")
print(f"wrote sprite.mif ({addr} words), DW={DW} DH={DH} NFR={NFR}")

# 期待ゲーム画面プレビュー(4bit量子化を反映)
W,H = 640,480; GROUND=400
scr = Image.new("RGB",(W,H),(255,255,255))
d = scr.load()
for x in range(W):
    for t in range(3): scr.putpixel((x,GROUND+t),(40,40,40))     # 地面ライン
# サボテン(濃い緑の矩形)
for (cx,cw,chh) in [(360,26,52),(520,18,38)]:
    for yy in range(GROUND-chh,GROUND):
        for xx in range(cx,cx+cw): scr.putpixel((xx,yy),(34,102,34))
# キャラ(frame0)を足元GROUNDに
fr0 = frames[0].load()
dino_x = 80; dino_top = GROUND-DH
for y in range(DH):
    for x in range(DW):
        r,g,b,al = fr0[x,y]
        if al>127: scr.putpixel((dino_x+x,dino_top+y),(q4(r)*17,q4(g)*17,q4(b)*17))
scr.save("expected_game.png"); print("wrote expected_game.png")
