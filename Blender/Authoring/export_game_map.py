"""Read-only export of the approved authored snapshot, never the user's working map."""
import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/forest_authoring.json'
bpy.context.view_layer.update()
def xyz(v):return [round(v.x,5),round(v.z,5),round(-v.y,5)]
def props(o):
    result={}
    for k in o.keys():
        if not k.startswith('atmo_'):continue
        value=o[k]
        if isinstance(value,str) and value[:1] in ['[','{']:
            try:value=json.loads(value)
            except ValueError:pass
        result[k[5:]]=value if isinstance(value,(str,int,float,bool,list,dict)) else list(value)
    return result
meshes=[]
def export_mesh(o,matrix=None,name=None):
    m=matrix if matrix is not None else o.matrix_world
    o.data.calc_loop_triangles()
    kind=o.get('atmo_surface_type','bark' if 'Trunk' in o.name else 'forest_litter')
    material=o.data.materials[0] if o.data.materials else None
    meshes.append({'name':name or o.name,'surface':kind,'color':list(material.diffuse_color) if material else [.3,.3,.3,1],
      'vertices':[xyz(m@v.co) for v in o.data.vertices],
      'triangles':[list(t.vertices) for t in o.data.loop_triangles],
      'collision':o.get('atmo_collision_intent')!='world_boundary' and 'Leaves' not in o.name,
      'water':kind in ['water','deep_water'],'absorption':list(material.get('absorption_bands',[.1,.3,.6])) if material else [.1,.3,.6]})
for col in ['ATMO_01_Terrain_Materials','ATMO_02_Water_Surfaces']:
    for o in bpy.data.collections[col].all_objects:
        if o.type=='MESH' and o.get('atmo_collision_intent')!='world_boundary':export_mesh(o)
for o in bpy.data.collections['ATMO_03_Existing_Trees'].all_objects:
    if o.instance_collection:
        for part in o.instance_collection.objects:
            export_mesh(part,o.matrix_world@part.matrix_basis,o.name+'__'+part.name)
terrain=bpy.data.objects['Island-Mountain-Terrain']
tv=[terrain.matrix_basis@v.co for v in terrain.data.vertices]
tf=[list(p.vertices) for p in terrain.data.polygons]
bvh=BVHTree.FromPolygons(tv,tf)
def ground(x,y):
    hit,_,_,_=bvh.ray_cast(Vector((x,y,1800)),Vector((0,0,-1)),2400)
    return hit.z if hit else 118.56
paths=[]
for o in bpy.data.collections['ATMO_04_Bird_Flight_Paths'].objects:
    if o.type!='CURVE':continue
    spline=o.data.splines[0]
    paths.append({'name':o.name,**props(o),'points':[{'co':xyz(p.co),'in':xyz(p.handle_left-p.co),'out':xyz(p.handle_right-p.co)} for p in spline.bezier_points]})
markers=[]
for col in ['ATMO_04_Bird_Flight_Paths','ATMO_06_Environment_Audio']:
    for o in bpy.data.collections[col].objects:
        if o.type!='SPEAKER':continue
        pos=o.matrix_world.translation.copy()
        if o.get('atmo_event_type')=='individual_tree_wind':pos.z=ground(pos.x,pos.y)+8
        markers.append({'name':o.name,'position':xyz(pos),**props(o)})
triggers=[]
for o in bpy.data.collections['ATMO_05_Takeoff_Triggers'].objects:
    triggers.append({'name':o.name,'position':xyz(o.location),**props(o)})
zones=[]
for o in bpy.data.collections['ATMO_07_Habitat_Zones'].objects:
    p=o.location;h=ground(p.x,p.y)
    zones.append({'name':o.name,'position':xyz(Vector((p.x,p.y,h))),**props(o)})
samples={}
for poly,face in zip(terrain.data.polygons,tf):
    c=sum((tv[i] for i in face),Vector())/len(face)
    if c.z<118.7:continue
    # Read surface classification from saved authoring chunks, not a new heuristic.
    samples[poly.index]=xyz(c)
surface_samples={}
for o in bpy.data.collections['ATMO_01_Terrain_Materials'].all_objects:
    if o.type!='MESH' or 'source_face_index' not in o.data.attributes:continue
    for d in o.data.attributes['source_face_index'].data:
        p=samples.get(d.value)
        if p is not None:surface_samples.setdefault(o['atmo_surface_type'],[]).append(p)
spawn=Vector((-370,80,ground(-370,80)+1.1))
result={'schema':1,'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
 'sea_level':118.560516,'meshes':meshes,'paths':paths,'markers':markers,'triggers':triggers,'zones':zones,
 'spawn':xyz(spawn),'surface_samples':surface_samples}
OUT.parent.mkdir(exist_ok=True)
OUT.write_text(json.dumps(result,separators=(',',':')),encoding='utf8')
print('EXPORTED',OUT,'meshes',len(meshes),'paths',len(paths),'markers',len(markers),'triggers',len(triggers))
