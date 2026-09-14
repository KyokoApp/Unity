// One world unit is one metre. All terrain/roads are deterministic and sampled in world space.
export const WORLD_SIZE=3000;    // 24 km -> 12 km -> 6 km -> 3 km
export const WORLD_LIMIT=WORLD_SIZE/2-32;
export const CHUNK_SIZE=256;
export const WATER_LEVEL=0;
export const ROAD_SPACING=750;   // ikut dunia: 1500 m hanya menyisakan lajur 0 & 1 di dunia 3 km
const clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v));
const smooth=(a,b,v)=>{const t=clamp((v-a)/(b-a));return t*t*(3-2*t);};
export function roadX(z,lane=0){return lane*ROAD_SPACING+70*Math.sin(z/850);}
export function roadZ(x,lane=0){return lane*ROAD_SPACING+60*Math.sin(x/600);}
export function roadInfo(x,z){
 const laneX=Math.round((x-roadX(z))/ROAD_SPACING),laneZ=Math.round((z-roadZ(x))/ROAD_SPACING);
 const dx=Math.abs(x-roadX(z,laneX)),dz=Math.abs(z-roadZ(x,laneZ));
 const wx=Math.abs(laneX)%2===0?8:4,wz=Math.abs(laneZ)%2===0?8:4;
 return dx-wx<dz-wz?{edge:dx-wx,distance:dx,halfWidth:wx,along:z,lane:laneX,axis:'z'}:{edge:dz-wz,distance:dz,halfWidth:wz,along:x,lane:laneZ,axis:'x'};
}
export function roadHeight(x,z){return 28+14*Math.sin(x*.0014)*Math.cos(z*.0012)+6*Math.sin((x+z)*.002);}
export function terrainH(x,z){
 const base=roadHeight(x,z);
 const north=smooth(250,1750,-z);   // diskala dari (1000,7000): dunia 1/4 luasnya
 const ridge=Math.sin(x*.0028+Math.cos(z*.002))*.5+.5;
 let h=base+12*Math.sin(x*.012)*Math.cos(z*.01)+7*Math.sin((x-z)*.004);
 h+=north*(45+180*ridge*ridge)+18*Math.sin(x*.0024)*Math.sin(z*.0034);
 // A continuous river and two broad lakes. Raised road causeways remain above water.
 const river=Math.abs(x-(400+70*Math.sin(z*.002)));
 const lakeA=Math.hypot((x+1150)*.8,z-1150),lakeB=Math.hypot(x-1150,(z+1150)*.8);
 const wet=1-smooth(30,65,Math.min(river,Math.min(lakeA-145,lakeB-162.5)));
 h=h*(1-wet)-5*wet;
 const road=1-smooth(4,42,roadInfo(x,z).edge);
 return h*(1-road)+base*road;
}
export const REGIONS=[
 {id:'heartlands',name:'Aurelia Heartlands',subtitle:'Padang hijau & gerbang kerajaan',x:0,z:0,color:[.42,.56,.28],foliage:0x729b53},
 {id:'frost',name:'Frostspire Reach',subtitle:'Puncak es & menara penjaga',x:-750,z:-750,color:[.68,.76,.77],foliage:0x8eafb0},
 {id:'highlands',name:'Crownfall Highlands',subtitle:'Pegunungan & reruntuhan kuno',x:0,z:-750,color:[.43,.49,.42],foliage:0x58705b},
 {id:'amber',name:'Amber Wastes',subtitle:'Bukit keemasan & kuil matahari',x:750,z:-750,color:[.72,.56,.33],foliage:0xb88d4b},
 {id:'forest',name:'Elderwood Wilds',subtitle:'Hutan tua & batu bercahaya',x:-750,z:750,color:[.25,.43,.33],foliage:0x3c7963},
 {id:'bloom',name:'Roseveil Expanse',subtitle:'Dataran bunga & pohon merah muda',x:0,z:750,color:[.49,.48,.39],foliage:0xba7993},
 {id:'coast',name:'Azure Coast',subtitle:'Lembah sungai & kristal biru',x:750,z:750,color:[.46,.60,.47],foliage:0x6faca1}
];
export function regionAt(x,z){let result=REGIONS[0],best=Infinity;for(const r of REGIONS){const d=(x-r.x)**2+(z-r.z)**2;if(d<best){best=d;result=r;}}return result;}
export function terrainColor(x,z){
 let first=null,second=null,d1=Infinity,d2=Infinity;
 for(const r of REGIONS){const d=Math.hypot(x-r.x,z-r.z);if(d<d1){second=first;d2=d1;first=r;d1=d;}else if(d<d2){second=r;d2=d;}}
 const blend=.5*(1-smooth(0,450,d2-d1));
 return first.color.map((v,i)=>v*(1-blend)+second.color[i]*blend);
}
export function intersection(laneX,laneZ){let x=laneX*ROAD_SPACING,z=laneZ*ROAD_SPACING;for(let i=0;i<12;i++){x=roadX(z,laneX);z=roadZ(x,laneZ);}return {x,z};}
export const WAYPOINTS=REGIONS.map(r=>({...r,...intersection(Math.round(r.x/ROAD_SPACING),Math.round(r.z/ROAD_SPACING))}));
export function randomForChunk(cx,cz){let n=(Math.imul(cx,73856093)^Math.imul(cz,19349663)^0x51f15e)>>>0;return ()=>{n+=0x6D2B79F5;let t=n;t=Math.imul(t^(t>>>15),t|1);t^=t+Math.imul(t^(t>>>7),t|61);return ((t^(t>>>14))>>>0)/4294967296;};}
export function chunkPlan(x,z,radius=3){
 const cx=Math.floor(x/CHUNK_SIZE),cz=Math.floor(z/CHUNK_SIZE),out=[];
 for(let dz=-radius;dz<=radius;dz++)for(let dx=-radius;dx<=radius;dx++){
  const tx=cx+dx,tz=cz+dz;if(tx*CHUNK_SIZE>=WORLD_SIZE/2||(tx+1)*CHUNK_SIZE<=-WORLD_SIZE/2||tz*CHUNK_SIZE>=WORLD_SIZE/2||(tz+1)*CHUNK_SIZE<=-WORLD_SIZE/2)continue;
  out.push({cx:tx,cz:tz,key:`${tx},${tz}`,near:Math.max(Math.abs(dx),Math.abs(dz))<=1,distance:dx*dx+dz*dz});
 }
 return out.sort((a,b)=>a.distance-b.distance);
}
// Same equations as above, shared by streamed terrain, grass and butterflies.
export const TERRAIN_GLSL=`
float roadX(float z){return 70.0*sin(z/850.0);}
float roadZ(float x){return 60.0*sin(x/600.0);}
vec3 roadData(vec2 p){
 float lx=floor((p.x-roadX(p.y))/750.0+0.5),lz=floor((p.y-roadZ(p.x))/750.0+0.5);
 float dx=abs(p.x-roadX(p.y)-lx*750.0),dz=abs(p.y-roadZ(p.x)-lz*750.0);
 float wx=mod(abs(lx),2.0)<0.5?8.0:4.0,wz=mod(abs(lz),2.0)<0.5?8.0:4.0;
 return dx-wx<dz-wz?vec3(dx-wx,p.y,wx):vec3(dz-wz,p.x,wz);
}
float terrainH(vec2 p){
 float x=p.x,z=p.y;
 float base=28.0+14.0*sin(x*.0014)*cos(z*.0012)+6.0*sin((x+z)*.002);
 float north=smoothstep(250.0,1750.0,-z),ridge=sin(x*.0028+cos(z*.002))*.5+.5;
 float h=base+12.0*sin(x*.012)*cos(z*.01)+7.0*sin((x-z)*.004)+north*(45.0+180.0*ridge*ridge)+18.0*sin(x*.0024)*sin(z*.0034);
 float river=abs(x-(400.0+70.0*sin(z*.002)));
 float lakeA=length(vec2((x+1150.0)*.8,z-1150.0)),lakeB=length(vec2(x-1150.0,(z+1150.0)*.8));
 float wet=1.0-smoothstep(30.0,65.0,min(river,min(lakeA-145.0,lakeB-162.5)));
 h=h*(1.0-wet)-5.0*wet;
 float road=1.0-smoothstep(4.0,42.0,roadData(p).x);
 return mix(h,base,road);
}`;
