from PIL import Image
import os, json
SRC="/tmp/icon_out/v4.png"
DST=os.path.expanduser("~/aiwork/RHVoiceUkraine_ci/UkrainianVoicesApp/App/Assets.xcassets/AppIcon.appiconset")
master=Image.open(SRC).convert("RGB")
sizes={
 "AppIcon-20@1x.png":20,"AppIcon-20@2x.png":40,"AppIcon-20@2x-ipad.png":40,"AppIcon-20@3x.png":60,
 "AppIcon-29@1x.png":29,"AppIcon-29@2x.png":58,"AppIcon-29@2x-ipad.png":58,"AppIcon-29@3x.png":87,
 "AppIcon-40@1x.png":40,"AppIcon-40@2x.png":80,"AppIcon-40@2x-ipad.png":80,"AppIcon-40@3x.png":120,
 "AppIcon-60@2x.png":120,"AppIcon-60@3x.png":180,
 "AppIcon-76@1x.png":76,"AppIcon-76@2x.png":152,"AppIcon-83.5@2x.png":167,
 "AppIcon-1024.png":1024,
 "AppIcon-mac-16.png":16,"AppIcon-mac-32.png":32,"AppIcon-mac-64.png":64,
 "AppIcon-mac-128.png":128,"AppIcon-mac-256.png":256,"AppIcon-mac-512.png":512,"AppIcon-mac-1024.png":1024,
}
for name,px in sizes.items():
    im = master if px==1024 else master.resize((px,px), Image.LANCZOS)
    im.convert("RGB").save(os.path.join(DST,name))
print("записано файлов:", len(sizes))
# проверка: все ли имена из Contents.json на месте
c=json.load(open(os.path.join(DST,"Contents.json")))
missing=[i["filename"] for i in c["images"] if i.get("filename") and not os.path.exists(os.path.join(DST,i["filename"]))]
print("нет файлов:", missing or "нет, все на месте")
