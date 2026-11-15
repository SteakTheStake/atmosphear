"""Create a fixed plan from the imported terrain, without player or heading data."""
import json
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
data=json.loads((ROOT/'build/forest_authoring.json').read_text(encoding='utf8'))
image=Image.new('RGB',(1200,1200),(18,48,61));draw=ImageDraw.Draw(image)
def point(v):return ((v[0]+2317)/4434*1200,(v[2]+2317)/4434*1200)
faces=[];rivers=[]
for entry in data['meshes']:
    if entry['name'].startswith('Terrain__'):
        for face in entry['triangles']:
            pts=[entry['vertices'][i] for i in face];height=sum(p[1] for p in pts)/3
            if height<118.5:continue
            shade=.72+.28*min(1,(height-118.5)/650)
            color=tuple(int(min(255,(v**(1/2.2))*255*shade)) for v in entry['color'][:3])
            faces.append((height,[point(p) for p in pts],color))
    elif entry['name'].startswith('River__'):
        rivers.extend([[point(entry['vertices'][i]) for i in face] for face in entry['triangles']])
for _,p,c in sorted(faces,key=lambda f:f[0]):draw.polygon(p,fill=c)
for p in rivers:draw.polygon(p,fill=(54,130,153))
for entry in data['meshes']:
    if '__ATMO_' in entry['name'] and 'Trunk' in entry['name']:
        vs=entry['vertices'];p=[sum(v[i] for v in vs)/len(vs) for i in range(3)];x,y=point(p)
        draw.ellipse((x-3,y-3,x+3,y+3),fill=(30,64,28))
path=ROOT/'assets/worlds/forest/plan.png';path.parent.mkdir(parents=True,exist_ok=True);image.save(path)
print(path)
