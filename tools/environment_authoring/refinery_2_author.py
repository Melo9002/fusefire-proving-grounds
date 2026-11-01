"""Offline authoring recipe for the checked-in Refinery 2 scene and custom parts.
Run explicitly from the repository root. Rebuilds generated scene files using
current saved asset calibrations; inspect diffs and rendered captures afterward.
This is an authoring aid, never a runtime generation dependency.
"""
import json,math,pathlib
B=json.load(open('tools/asset_lab/native_bounds.json'));C=json.load(open('tools/asset_lab/asset_calibrations.json'))
ext={};subs=[];nodes=[];counter=0
W,D=96,80
def vec(v):return 'Vector3('+', '.join(f'{x:.6f}' for x in v)+')'
def world(x,y,z):return (x-W/2+.5,y,z-D/2+.5)
def node(name,parent='.',props='',kind='Node3D',instance=None):
 nodes.append(f'[node name="{name}" '+(f'type="{kind}" ' if not instance else '')+f'parent="{parent}"'+(f' instance=ExtResource("{instance}")' if instance else '')+']\n'+props+'\n')
def box(name,x,y,z,size,color,parent='.',solid=False):
 global counter
 counter+=1;k=f'b{counter}';m=f'm{color}'
 if m not in ext:
  ext[m]=True;rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)];subs.append(f'[sub_resource type="StandardMaterial3D" id="{m}"]\nalbedo_color = Color({rgb[0]}, {rgb[1]}, {rgb[2]}, 1)\nroughness = 0.85\n')
 subs.append(f'[sub_resource type="BoxMesh" id="{k}"]\nsize = {vec(size)}\nmaterial = SubResource("{m}")\n')
 node(name,parent,f'position = {vec(world(x,y,z))}\nmesh = SubResource("{k}")'+(f'\nmetadata/solid_size = {vec(size)}' if solid else ''),'MeshInstance3D')
def asset(name,id,x,z,y=0,yaw=0,solid=True,cylinder=False,parent='.'):
 key='asset_'+id.replace('/','_').replace('-','_');ext[key]=id
 p=C['asset_overrides'][id];sc=p['scale'];a=math.radians(yaw+p.get('yaw_degrees',0));co,si=math.cos(a),math.sin(a)
 size=B[id]['size'];pos=B[id]['position'];ctr=[pos[j]+size[j]/2 for j in range(3)]
 off=(-sc*(co*ctr[0]+si*ctr[2]),-sc*pos[1],-sc*(-si*ctr[0]+co*ctr[2]))
 node(name,parent,'position = '+vec(world(x,y,z))+f'\nmetadata/asset_id = "{id}"')
 par=name if parent=='.' else parent+'/'+name
 matrix=[sc*co,0,sc*si,0,sc,0,-sc*si,0,sc*co,*off]
 node('Visual',par,'transform = Transform3D('+', '.join(f'{v:.7f}' for v in matrix)+')',instance=key)
 if solid:
  dims=(sc*(abs(co)*size[0]+abs(si)*size[2]),sc*size[1],sc*(abs(si)*size[0]+abs(co)*size[2]))
  node('TacticalVolume',par,f'position = {vec((0,dims[1]/2,0))}\nmetadata/solid_size = {vec(dims)}\nmetadata/round_volume = '+('true' if cylinder else 'false'))
def socket_asset(name,id,socket,target,yaw=0,pitch=0,roll=0,solid=False):
 # Author-time rigid transform: a measured native pipe inlet meets a world inlet.
 import itertools
 a,b,c=map(math.radians,(yaw,pitch,roll));cy,sy=math.cos(a),math.sin(a);cx,sx=math.cos(b),math.sin(b);cz,sz=math.cos(c),math.sin(c)
 R=[[cy*cz+sy*sx*sz,-cy*sz+sy*sx*cz,sy*cx],[cx*sz,cx*cz,-sx],[-sy*cz+cy*sx*sz,sy*sz+cy*sx*cz,cy*cx]]
 sc=C['asset_overrides'][id]['scale'];key='asset_'+id.replace('/','_').replace('-','_');ext[key]=id
 off=[-sc*sum(R[i][j]*socket[j] for j in range(3)) for i in range(3)]
 node(name,'.','position = '+vec(world(*target))+f'\nmetadata/asset_id = "{id}"')
 # Godot text scene Transform3D serializes basis rows, followed by origin.
 matrix=[sc*R[i][j] for i in range(3) for j in range(3)]+off
 node('Visual',name,'transform = Transform3D('+', '.join(f'{v:.7f}' for v in matrix)+')',instance=key)
 if solid:
  pts=[[sc*sum(R[i][j]*(B[id]['position'][j]+bit[j]*B[id]['size'][j]) for j in range(3))+off[i] for i in range(3)] for bit in itertools.product([0,1],repeat=3)]
  lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
  node('TacticalVolume',name,'position = '+vec([(lo[i]+hi[i])/2 for i in range(3)])+'\nmetadata/solid_size = '+vec([hi[i]-lo[i] for i in range(3)]))

def component(name,kind,x,y,z,yaw=0,metadata=''):
 key='component_'+kind;ext[key]=kind
 node(name,'.','position = '+vec(world(x,y,z))+f'\nrotation_degrees = Vector3(0, {yaw}, 0)'+metadata,instance=key)

def save_component(kind,build,extra=''):
 global ext,subs,nodes,counter,W,D
 saved=(ext,subs,nodes,counter,W,D);ext={};subs=[];nodes=[];counter=0;W=D=1
 build()
 folder=pathlib.Path('art/environments/authored/components');folder.mkdir(parents=True,exist_ok=True)
 folder.joinpath(kind+'.tscn').write_text('[gd_scene format=3]\n\n'+'\n'.join(subs)+extra+'\n[node name="'+kind+'" type="Node3D"]\n\n'+'\n'.join(nodes),encoding='utf-8')
 ext,subs,nodes,counter,W,D=saved

def deck_component():
 box('Deck',0,-.11,0,(2,.22,2),'435458')
 node('Body','.',kind='StaticBody3D')
 node('Collision','Body','position = Vector3(0, -0.11, 0)\nshape = SubResource("deck_shape")',kind='CollisionShape3D')

def ladder_component():
 for i,x in enumerate([-.35,.35]):box('Side%d'%i,x,2,0,(.06,4,.06),'dfb64c')
 for j in range(12):box('Rung%d'%j,0,.2+j*.33,0,(.76,.045,.045),'dfb64c')

def rack_component():
 for i,z in enumerate([-2.5,2.5]):box('Post%d'%i,0,3.75,z,(.3,7.5,.3),'435458',solid=True)
 box('Beam',0,7.3,0,(.4,.3,5.7),'435458')

def pier_component():
 for i,x in enumerate([-1,1]):box('Pier%d'%i,x,1.89,0,(.18,3.78,.18),'435458',solid=True)

save_component('catwalk_deck_2x2',deck_component,'[sub_resource type="BoxShape3D" id="deck_shape"]\nsize = Vector3(2, 0.22, 2)\n')
save_component('maintenance_ladder_4m',ladder_component)
save_component('pipe_rack_support',rack_component)
save_component('catwalk_support_2m',pier_component)

# Earth, gravel service roads and concrete equipment islands.
box('RedEarth',47.5,-.10,39.5,(116,.16,100),'865b46')
for name,x,z,w,d in [('WestServiceRoad',7,39,6,70),('EastServiceRoad',88,39,6,70),('NorthServiceRoad',47.5,6,87,6),('SouthServiceRoad',47.5,73,87,6),('CrossSiteServiceRoad',47.5,38,81,6)]:box(name,x,.005,z,(w,.012,d),'a88a6c')
for name,x,z,w,d in [('ProcessHallPad',40,19,63,22),('BoilerPad',77,24,20,31),('TankContainment',25,53,36,27),('LoadingApron',63,62,32,16),('ControlApron',82,55,12,16)]:box(name,x,.02,z,(w,.02,d),'aaa99b')
asset('PrimaryProcessHall','city_kit_industrial/building-a',25,19,yaw=180)
asset('SecondaryProcessHall','city_kit_industrial/building-b',54,19,yaw=180)
asset('BoilerStack','city_kit_industrial/chimney-large',78,18,cylinder=True)
for x in [73,82]:asset('ProcessColumn%d'%x,'city_kit_industrial/chimney-medium',x,33,cylinder=True)
for row,z in enumerate([47,59]):
 for col,x in enumerate([14,25,36]):asset('Tank_%d_%d'%(row,col),'city_kit_industrial/detail-tank-large',x,z,cylinder=True)
# Containment lips: breaks on east and south allow real access into the tank yard.
for x in [9.5,43.5]:box('BundSide'+str(x).replace('.','_'),x,.3,54,(.35,.6,25),'cdc8b3',solid=True)
box('BundNorth',26.5,.3,41.5,(34,.6,.35),'cdc8b3',solid=True)
for x,w in [(15,17),(35,17)]:box('BundSouth%d'%x,x,.3,66.5,(w,.6,.35),'cdc8b3',solid=True)
asset('LoadingWarehouse','city_kit_industrial/building-p',63,52,yaw=0)
asset('ControlBuilding','city_kit_industrial/building-i',82,52,yaw=180)
asset('WaterSupplyTower','city_kit_industrial/water-tower',82,65,cylinder=True)
# Main pipe rack: uniform stock pieces, supports, and a separate crossing header.
for i,x in enumerate(range(13,83,3)):
 for j,z in enumerate([30,33]):asset('Header_%02d_%d'%(i,j),'factory_kit/pipe-large-long',x,z,7.5,solid=False)
for x in range(13,84,9):component('RackSupport%d'%x,'pipe_rack_support',x,0,31.5)
for i,z in enumerate(range(18,64,3)):asset('CrossingHeader%02d'%i,'factory_kit/pipe-large-long',46,z,7.5,90,solid=False)
for z in range(19,65,9):
 for x in [44.5,47.5]:box('CrossPost_%s_%d'%(str(x).replace('.','_'),z),x,3.75,z,(.3,7.5,.3),'435458',solid=True)
 box('CrossBeam%d'%z,46,7.3,z,(3.6,.3,.4),'435458')
for i,(x,z) in enumerate([(16,28),(25,28),(34,28),(52,28),(61,28),(70,42),(49,60)]):asset('PumpSkid%02d'%i,'factory_kit/machine-connection-pipe',x,z,yaw=90)
for i,x in enumerate([53,60,67]):asset('DispatchContainer%d'%i,'city_kit_industrial/shipping-container-'+['a','b','c'][i],x,63,yaw=90)
for i,(x,z) in enumerate([(52,68),(63,68),(77,68)]):asset('ServiceVehicle%d'%i,'car_kit/delivery' if i==0 else 'car_kit/truck' if i==1 else 'car_kit/van',x,z,yaw=90)
asset('LoadingCrane','factory_kit/crane',49,52,yaw=90)
for i,(x,z) in enumerate([(51,59),(55,59),(68,58),(70,65),(11,42),(39,60),(68,28),(18,30)]):asset('CargoPallet%d'%i,'factory_kit/box-large',x,z)
# Feed lines terminate inside the process halls and tank shells, rather than
# presenting disconnected decorative pipe runs. Low tank pipes are vaultable.
for x in [25,54]:
 for z in [25,28]:asset('HallFeed%d_%d'%(x,z),'factory_kit/pipe-large-long',x,z,7.5,90,solid=False)
for row,z in enumerate([47,59]):
 for col,x in enumerate([19.5,30.5]):

  for k,dx in enumerate([-.5,.5]):asset('TankLink%d_%d_%d'%(row,col,k),'factory_kit/pipe-large-long',x+dx,z,.1,solid=True)
# Two pump manifolds make the storage yard's service edge legible.
for i,z in enumerate([47,59]):asset('TankPump%d'%i,'factory_kit/machine-connection-pipe',40,z,yaw=90)
for i,z in enumerate([30,33]):
 socket_asset('HeaderReturnElbow%d'%i,'factory_kit/pipe-large-bend',(1,.5,0),(11.5,8.25,z),pitch=-90)
 for j,h in enumerate([6.15,3.15]):socket_asset('HeaderReturnDrop%d_%d'%(i,j),'factory_kit/pipe-large-long',(1,.5,0),(9.4,h,z),roll=90,solid=True)
 asset('HeaderReturnPump%d'%i,'factory_kit/machine-connection-pipe',9.4,z,yaw=90)
socket_asset('BoilerReturnElbow','factory_kit/pipe-large-bend',(1,.5,0),(83.5,8.25,30),yaw=180,pitch=-90)
for j,h in enumerate([6.15,3.15]):socket_asset('BoilerReturnDrop%d'%j,'factory_kit/pipe-large-long',(1,.5,0),(85.6,h,30),roll=90,solid=True)
asset('BoilerReturnPump','factory_kit/machine-connection-pipe',85.6,30,yaw=90)
socket_asset('DispatchReturnElbow','factory_kit/pipe-large-bend',(1,.5,0),(46,8.25,64.5),yaw=90,pitch=-90)
for j,h in enumerate([6.15,3.15]):socket_asset('DispatchReturnDrop%d'%j,'factory_kit/pipe-large-long',(1,.5,0),(46,h,66.6),roll=90,solid=True)
asset('DispatchReturnPump','factory_kit/machine-connection-pipe',46,66.6)
# Connected maintenance network; local grid footprints and four-metre support.
decks=[('ProcessGallery',15,27,58,2),('MaintenanceDeck',41,29,2,28),('LoadingBridge',43,43,28,2),('TankBridge',11,52,30,2)]
walkcells=set()
for name,x,z,w,d in decks:
 node(name,'.','metadata/deck_rect = Rect2i(%d, %d, %d, %d)\nmetadata/deck_level = 4\n'%(x,z,w,d))
 for xx in range(x,x+w,2):
  for zz in range(z,z+d,2):component('%sTile%d_%d'%(name,xx,zz),'catwalk_deck_2x2',xx+.5,4,zz+.5)
 walkcells.update((xx,zz) for xx in range(x,x+w) for zz in range(z,z+d))
 # Support columns sit on edges, leaving the centre of the walkway usable below.
 if w>d:
  for xx in range(x+2,x+w-1,6):
   component('Pier%s_%d'%(name,xx),'catwalk_support_2m',xx,0,z+.5,90)
 else:
  for zz in range(z+2,z+d-1,6):
   component('Pier%s_%d'%(name,zz),'catwalk_support_2m',x+.5,0,zz)
ladders=[((15,0,26),(15,4,27)),((70,0,26),(70,4,27)),((42,0,57),(42,4,56)),((70,0,45),(70,4,44)),((11,0,51),(11,4,52))]
open_edges={(top[0],top[2],bottom[0]-top[0],bottom[2]-top[2]) for bottom,top in ladders}
# Boundary-only rails: connected bridges never have a rail across their junction.
edges={}
for x,z in sorted(walkcells):
 for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
  if (x+dx,z+dz) in walkcells or (x,z,dx,dz) in open_edges:continue
  key=('z',x+dx*.5) if dx else ('x',z+dz*.5)
  edges.setdefault(key,[]).append(z if dx else x)
for n,((axis,fixed),values) in enumerate(sorted(edges.items())):
 values=sorted(set(values));runs=[];start=prev=values[0]
 for v in values[1:]:
  if v!=prev+1:runs.append((start,prev));start=v
  prev=v
 runs.append((start,prev))
 for j,(lo,hi) in enumerate(runs):
  x,z=(fixed,(lo+hi)/2) if axis=='z' else ((lo+hi)/2,fixed)
  dims=(.06,.06,hi-lo+1) if axis=='z' else (hi-lo+1,.06,.06)
  for k,y in enumerate([4.45,4.9]):box('Handrail%d_%d_%d'%(n,j,k),x,y,z,dims,'dfb64c')
  for v in range(lo,hi+1,3):
   xx,zz=(fixed,v) if axis=='z' else (v,fixed)
   box('RailPost%d_%d_%d'%(n,j,v),xx,4.45,zz,(.06,.9,.06),'dfb64c')
for i,(bottom,top) in enumerate(ladders):
 component('Ladder%d'%i,'maintenance_ladder_4m',bottom[0],0,(bottom[2]+top[2])/2,metadata='\nmetadata/ladder_bottom = Vector3i'+str(bottom)+'\nmetadata/ladder_top = Vector3i'+str(top))
# Contextual yard furniture and green perimeter, outside the play area.
for i,x in enumerate(range(8,90,8)):
 for z in [-6,86]:asset('Tree_%d_%d'%(i,z),'city_kit_suburban/tree-large',x,z,solid=False)
for i,z in enumerate(range(3,79,8)):
 for x in [-6,102]:asset('EdgeTree_%d_%d'%(i,x),'city_kit_suburban/tree-small',x,z,solid=False)
for i,x in enumerate([18,25,32]):asset('SolarUtility%d'%i,'city_kit_industrial/solar-panel-landscape-group',x,83,solid=False)
for i,x in enumerate([13,29,53,69,85]):asset('ServiceLight%d'%i,'city_kit_roads/light-curved',x,36,solid=True)
for faction,x,z in [(0,8,35),(1,87,40),(2,7,42)]:
 node('Deployment%d'%faction,'.',f'metadata/faction = {faction}\nmetadata/grid_origin = Vector3i({x}, 0, {z})')
# Root metadata and explicit scene references.
resources=[]
for key,id in ext.items():
 if key.startswith('asset_'):resources.append(f'[ext_resource type="PackedScene" path="res://art/environments/kenney/{id.split("/")[0]}/models/{id.split("/")[1]}.glb" id="{key}"]\n')
for key,id in ext.items():
 if key.startswith('component_'):resources.append(f'[ext_resource type="PackedScene" path="res://art/environments/authored/components/{id}.tscn" id="{key}"]\n')
root='[node name="Refinery2" type="Node3D"]\nmetadata/map_size = Vector2i(96, 80)\nmetadata/revision = 1\n'
path=pathlib.Path('art/environments/authored/refinery_2.tscn');path.write_text('[gd_scene load_steps=%d format=3]\n\n'%(len(resources)+len(subs)+1)+'\n'.join(resources+subs+[root]+nodes),encoding='utf-8')
print('Authored scene:',len(nodes),'nodes,',len(resources),'asset/component scene references')
