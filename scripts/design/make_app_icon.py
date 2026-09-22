from PIL import Image, ImageDraw
import math, os
S=1024; BLUE=(0,87,183); YELLOW=(255,213,0)
img=Image.new("RGB",(S,S),BLUE); d=ImageDraw.Draw(img)
def capsule(x0,y0,x1,y1,w,fill=YELLOW):
    r=w/2.0; dx,dy=x1-x0,y1-y0; L=math.hypot(dx,dy)
    nx,ny=-dy/L*r, dx/L*r
    d.polygon([(x0+nx,y0+ny),(x1+nx,y1+ny),(x1-nx,y1-ny),(x0-nx,y0-ny)],fill=fill)
    d.ellipse([x0-r,y0-r,x0+r,y0+r],fill=fill); d.ellipse([x1-r,y1-r,x1+r,y1+r],fill=fill)
CX=460  # колос чуть левее, справа место под волны
capsule(CX,255,CX,860,32)
ANG=55; W=54
for y,L in [(690,170),(578,156),(466,140),(354,122)]:
    a=math.radians(ANG); dx,dy=L*math.cos(a), -L*math.sin(a)
    capsule(CX-13,y,CX-13-dx,y+dy,W); capsule(CX+13,y,CX+13+dx,y+dy,W)
# три дуги звука справа
for i,(rad,wd) in enumerate([(150,34),(240,34),(330,34)]):
    box=[CX+120-rad, 540-rad, CX+120+rad, 540+rad]
    d.arc(box, start=-52, end=52, fill=YELLOW, width=wd)
os.makedirs("/tmp/icon_out",exist_ok=True)
img.save("/tmp/icon_out/v4.png")
img.resize((120,120),Image.LANCZOS).resize((480,480),Image.NEAREST).save("/tmp/icon_out/v4_melkim.png")
print("ок")
