// Independent GPU implementation of the existing orthographic voxel renderer.
// Two-level 8^3 occupancy traversal, alpha-tested leaves, no CPU frame readback.
ByteAddressBuffer voxels : register(t0);
ByteAddressBuffer columns : register(t1);
ByteAddressBuffer atlas : register(t2);
ByteAddressBuffer chunks : register(t3);
RWTexture2D<float4> outputImage : register(u0);
cbuffer Parameters : register(b0) { float4 P[16]; }
uint voxelAt(uint i) { return (voxels.Load(i & ~3u) >> ((i & 3u)*8)) & 255u; }
uint chunkAt(uint i) { return (chunks.Load(i & ~3u) >> ((i & 3u)*8)) & 255u; }
float3 palette(uint i) {
    if(i==0) return float3(134,216,104); if(i==1) return float3(92,173,222);
    if(i==2) return float3(214,151,224); if(i==3) return float3(232,194,96);
    if(i==4) return float3(102,213,192); return float3(228,133,136);
}
float3 mixColor(float3 a,float3 b,float k) { return floor(lerp(a,b,k)); }
float4 sampleBlock(int material,int axis,float2 uv) {
    if(material==9) return float4(49,114,178,255);
    int tile=9;
    if(material==1) tile=axis==1?0:1; else if(material==2) tile=2;
    else if(material==3) tile=axis==1?4:3; else if(material==4) tile=5;
    else if(material==5 || material==10) tile=6; else if(material==6) tile=7; else if(material==7) tile=8;
    int2 t=clamp(int2(uv*16),0,15); uint rgba=atlas.Load((tile*256+t.y*16+t.x)*4);
    float4 c=float4(rgba&255,(rgba>>8)&255,(rgba>>16)&255,rgba>>24);
    if(material==10) { float gray=floor((c.r+c.g+c.b)/3); return float4(floor(gray*3/4).xxx,255); }
    if(material==4 || (material==1 && axis==1)) c.rgb=floor(c.rgb*float3(91,157,57)/255);
    return c;
}
float3 exitTimes(float3 o,float3 d,int3 cell,int span) {
    int3 group=span==8?(cell>>3):cell;
    float3 boundary=(group+int3(d.x>0,d.y>0,d.z>0))*span;
    return float3(abs(d.x)<1e-12?1e30:(boundary.x-o.x)/d.x,
                  abs(d.y)<1e-12?1e30:(boundary.y-o.y)/d.y,
                  abs(d.z)<1e-12?1e30:(boundary.z-o.z)/d.z);
}
int nextAxis(float3 v) { return v.x<v.y && v.x<v.z?0:(v.y<v.z?1:2); }
[numthreads(8,8,1)]
void main(uint3 id : SV_DispatchThreadID) {
    int2 size=int2(P[1].xy); if(any(id.xy>=uint2(size))) return;
    int3 dims=int3(P[0].xyz); float2 uv=(float2(id.xy)+0.5)/size;
    float3 d=-P[6].xyz;
    float3 o=P[3].xyz+P[6].xyz*P[3].w+P[4].xyz*((uv.x-0.5)*P[2].z-P[4].w)/P[2].y
        +P[5].xyz*(-(uv.y-0.5)*P[2].w+P[5].w)/P[2].y;
    if(P[0].w>0.5) { o=float3(uv.x*dims.x,dims.y+1,uv.y*dims.z); d=float3(0,-1,0); }
    float nearT=0,farT=10000; int axis=1;
    [unroll] for(int a=0;a<3;a++) {
        if(abs(d[a])<1e-12) { if(o[a]<0 || o[a]>=dims[a]) { outputImage[id.xy]=float4(122,155,169,255)/255; return; } }
        else { float ta=-o[a]/d[a],tb=(dims[a]-o[a])/d[a]; float lo=min(ta,tb);
            if(lo>nearT) {nearT=lo; axis=a;} farT=min(farT,max(ta,tb)); }
    }
    float3 result=float3(122,155,169);
    if(nearT>=farT || farT<0) { outputImage[id.xy]=float4(result,255)/255; return; }
    float distance=nearT;
    int3 cell=clamp(int3(floor(o+d*distance)),0,dims-1);
    int3 step=int3(d.x>0?1:-1,d.y>0?1:-1,d.z>0?1:-1);
    float3 next=exitTimes(o,d,cell,1);
    float3 delta=float3(abs(d.x)<1e-12?1e30:abs(1/d.x),abs(d.y)<1e-12?1e30:abs(1/d.y),abs(d.z)<1e-12?1e30:abs(1/d.z));
    for(int iteration=0;iteration<dims.x+dims.y+dims.z+4;iteration++) {
        if(any(cell<0) || any(cell>=dims) || distance>farT) break;
        uint chunk=((uint(cell.z)>>3)*(uint)P[7].y+(uint(cell.y)>>3))*(uint)P[7].x+(uint(cell.x)>>3);
        if(chunkAt(chunk)==0) {
            float3 edge=exitTimes(o,d,cell,8); axis=nextAxis(edge); distance=edge[axis];
            float3 hit=o+d*distance;
            int boundary=((cell[axis]>>3)+(step[axis]>0?1:0))*8;
            cell=int3(floor(hit));
            int entered=boundary-(step[axis]<0?1:0);
            if(axis==0) cell.x=entered; else if(axis==1) cell.y=entered; else cell.z=entered;
            next=exitTimes(o,d,cell,1); continue;
        }
        uint column=cell.z*dims.x+cell.x; uint data=columns.Load(column*4);
        int height=data&255,stage=(data>>8)&15;
        int material=voxelAt((cell.z*dims.y+cell.y)*dims.x+cell.x);
        if(material==4 && (stage==4 || (cell.x*17+cell.y*13+cell.z*7)%4<stage)) material=0;
        if(stage==4) { if(material==3 && cell.y>height) material=0; if(material==1 && cell.y==height-1) material=10; }
        if(material>0 && (P[1].z>0.5 || material!=4)) {
            float3 hitPoint=o+d*distance;
            float2 tex=float2(frac(axis==0?hitPoint.z:hitPoint.x),axis==1?frac(hitPoint.z):1-frac(hitPoint.y));
            float4 c=sampleBlock(material,axis,tex);
            if(material!=4 || c.a>=128) {
                result=floor(c.rgb*(axis==1?1.0:(axis==0?0.76:0.87)));
                if((data&65536)!=0 && material!=10) result=mixColor(result,palette((data>>17)&7),0.48);
                if((data&4096)!=0) result=mixColor(result,float3(247,110,24),0.6);
                else if((data&8192)!=0 && material!=10) result=mixColor(result,float3(36,32,29),0.85);
                if(cell.x==(int)P[1].w && cell.z==(int)P[2].x && cell.y==height-1) result=mixColor(result,float3(235,221,110),0.4);
                break;
            }
        }
        axis=nextAxis(next);
        if(axis==0){distance=next.x;cell.x+=step.x;next.x+=delta.x;}
        else if(axis==1){distance=next.y;cell.y+=step.y;next.y+=delta.y;}
        else{distance=next.z;cell.z+=step.z;next.z+=delta.z;}
    }
    outputImage[id.xy]=float4(result,255)/255;
}
