# -*- coding: utf-8 -*-
# XEVIOUS風STG用のオリジナル・ドット絵を手続き生成し、
# 13bit透過スプライトROM sprite.mif を出力する。
#   word = opaque(bit12) | R4(11:8) | G4(7:4) | B4(3:0)
# ROM配置: [player 28x28][enemy 24x24][expl 20x20]
# 期待ゲーム画面 expected_xstg.png も生成(焼く前の確認用)。
from PIL import Image, ImageDraw

PW,PH = 28,28
EW,EH = 24,24
XW,XH = 20,20

def newimg(w,h): return Image.new("RGBA",(w,h),(0,0,0,0))

# --- 自機(上向きジェット, オリジナル) ---
player = newimg(PW,PH); d=ImageDraw.Draw(player)
body=(200,228,255,255); cock=(40,90,210,255); wing=(120,160,225,255); fin=(70,110,200,255)
d.polygon([(14,1),(17,9),(11,9)], fill=body)                 # ノーズ
d.rectangle([11,8,16,24], fill=body)                          # 胴体
d.polygon([(2,22),(11,12),(11,22)], fill=wing)               # 左主翼
d.polygon([(25,22),(16,12),(16,22)], fill=wing)              # 右主翼
d.polygon([(7,26),(11,21),(11,26)], fill=fin)                # 左尾翼
d.polygon([(20,26),(16,21),(16,26)], fill=fin)               # 右尾翼
d.rectangle([12,11,15,16], fill=cock)                         # コックピット

# --- 空中敵(回転体ディスク, オリジナル) ---
enemy=newimg(EW,EH); d=ImageDraw.Draw(enemy)
d.ellipse([1,5,22,18], fill=(190,40,40,255))                 # 外殻(赤)
d.ellipse([4,7,19,16], fill=(235,90,40,255))                 # 中(橙)
d.ellipse([8,9,15,14], fill=(255,200,70,255))                # コア(黄)
d.polygon([(0,11),(5,9),(5,14)], fill=(150,30,30,255))       # 左ウイング
d.polygon([(23,11),(18,9),(18,14)], fill=(150,30,30,255))    # 右ウイング

# --- 爆発(放射, オリジナル) ---
expl=newimg(XW,XH); d=ImageDraw.Draw(expl)
cx,cy=10,10
for (dx,dy) in [(0,-9),(0,9),(-9,0),(9,0),(6,6),(-6,6),(6,-6),(-6,-6)]:
    d.line([cx,cy,cx+dx,cy+dy], fill=(255,210,60,255), width=2)
d.ellipse([5,5,14,14], fill=(255,140,30,255))
d.ellipse([7,7,12,12], fill=(255,240,160,255))

def q4(v): return min(15,max(0,round(v/255*15)))

frames=[("player",player,PW,PH),("enemy",enemy,EW,EH),("expl",expl,XW,XH)]
addr=0; bases={}
lines=[]
for name,img,w,h in frames:
    bases[name]=addr
    px=img.load()
    for y in range(h):
        for x in range(w):
            r,g,b,a=px[x,y]
            op=1 if a>127 else 0
            data=(op<<12)|(q4(r)<<8)|(q4(g)<<4)|q4(b) if op else 0
            lines.append(f"    {addr} : {data:04X};\n"); addr+=1
DEPTH=addr
with open("sprite.mif","w",encoding="ascii") as f:
    f.write(f"-- xstg sprites player/enemy/expl, 13bit opaque|R4G4B4\n")
    f.write(f"DEPTH = {DEPTH};\nWIDTH = 13;\nADDRESS_RADIX = DEC;\nDATA_RADIX = HEX;\n\nCONTENT\nBEGIN\n")
    f.writelines(lines); f.write("END;\n")
print("bases:",bases,"DEPTH:",DEPTH)
print(f"PW={PW} PH={PH} EW={EW} EH={EH} XW={XW} XH={XH}")
print(f"BASE_PLAYER={bases['player']} BASE_ENEMY={bases['enemy']} BASE_EXPL={bases['expl']}")

# ---- 期待ゲーム画面 ----
W,H=640,480
def terrain(x,yy):
    bx=x//32; by=yy//32; sel=(bx*7+by*13)%4
    return [(34,72,34),(44,86,40),(30,80,52),(50,96,40)][sel]
scr=Image.new("RGB",(W,H))
sp=scr.load()
scroll=120
for y in range(H):
    for x in range(W):
        sp[x,y]=terrain(x,y+scroll)
sd=ImageDraw.Draw(scr)
# 地上ターゲット(基地, 四角)
for (tx,ty) in [(180,150),(430,300)]:
    sd.rectangle([tx,ty,tx+24,ty+24], fill=(120,120,140)); sd.rectangle([tx+8,ty+8,tx+15,ty+15], fill=(200,60,60))
def paste(img,ox,oy):
    pl=img.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r,g,b,a=pl[x,y]
            if a>127: sp[ox+x,oy+y]=(q4(r)*17,q4(g)*17,q4(b)*17)
# 敵3
for (ex,ey) in [(150,90),(330,140),(480,70)]: paste(enemy,ex,ey)
# 自機
shipx,shipy=306,400; paste(player,shipx,shipy)
# レティクル(照準)
rx,ry=shipx+PW//2, shipy-96
sd.line([rx-8,ry,rx+8,ry], fill=(255,255,255), width=2); sd.line([rx,ry-8,rx,ry+8], fill=(255,255,255), width=2)
sd.rectangle([rx-9,ry-9,rx+9,ry+9], outline=(255,255,0))
# ザッパー弾
for by in [350,300]: sd.rectangle([shipx+PW//2-1, by, shipx+PW//2+2, by+10], fill=(255,240,60))
# 爆発(ターゲット上)
paste(expl,430+2,300+2)
scr.save("expected_xstg.png"); print("wrote expected_xstg.png")
