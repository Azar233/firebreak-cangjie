package firebreak

import sdl.*
import std.math.abs

func sameTrace(a: ?Hit,b: ?Hit): Bool {
    if (a.isNone() || b.isNone()) { return a.isNone()==b.isNone() }
    let x=a.getOrThrow(); let y=b.getOrThrow()
    return x.x==y.x && x.y==y.y && x.z==y.z && x.axis==y.axis && x.material==y.material &&
        abs(x.distance-y.distance)<0.000001 && abs(x.u-y.u)<0.000001 && abs(x.v-y.v)<0.000001
}
func verifyRenderOptimization(app: App): Unit {
    try (s=Surface.create(7,5)) {
        s.clear(Color.rgb(0,0,0))
        s.writeRgbaRows(1,4,{x,y=>Color.rgba(x*23,y*37,91,123)})
        for (y in 0..5) { for (x in 0..7) {
            let c=s.readPixel(Int32(x),Int32(y))
            require(if(y>=1 && y<4){c.r==UInt8(x*23) && c.g==UInt8(y*37) && c.b==91 && c.a==123}else{c.r==0 && c.g==0},"Batch pixel write changed channels or unselected rows")
        } }
        pass(rejected({=>s.writeRgbaRows(-1,3,{_,_=>Color.rgb(0,0,0)})}),"Batch pixel writer rejects out-of-range rows")
        pass(rejected({=>s.writeRgbaRows(0,2,{_,_=>throw Exception("test callback")})}),"Batch pixel writer propagates callback failure")
        s.writeRgbaRows(0,1,{_,_=>Color.rgb(9,8,7)})
        pass(s.readPixel(0,0).r==9,"Batch pixels preserve RGBA and row boundaries and unlock after exceptions")
    }
    let example=ForestExample(ForestSpec(64,0.74,42),PerformanceClock()); let scene=example.scene
    let sparse=Scene(nx:33,nz:35,demo:false)
    for (z in 0..35) { for(x in 0..33) { sparse.heights[z*33+x]=1; if(x%9==0 && z%7==0){sparse.set(x,0,z,1); sparse.tree(x,z)} } }
    for (s in [scene,sparse]) {
        let stages=Array<Int64>(s.nx*s.nz,{i=>i%5})
        for (mode in 0..4) { for (orientation in 0..3) {
            let c=Camera(); let b=Rect(0.0,0.0,640.0,480.0); c.fitScene(s,b)
            c.yaw=Float64(orientation)*1.72; c.pitch=0.25+Float64(orientation)*0.4
            for(y in 0..36){for(x in 0..48){
                let ray=if(mode==3){overheadRay(s,(Float64(x)+0.5)/48.0,(Float64(y)+0.5)/36.0)}else{c.ray((Float64(x)+0.5)*640.0/48.0,(Float64(y)+0.5)*480.0/36.0,b)}
                let old=traceReference(s,ray,groundOnly:mode==1,atlas:Some(app.assets),showCanopy:mode!=2,fireStages:Some(stages))
                let fresh=trace(s,ray,groundOnly:mode==1,atlas:Some(app.assets),showCanopy:mode!=2,fireStages:Some(stages))
                require(sameTrace(old,fresh),"Optimized traversal differs from reference: mode ${mode} at ${x},${y}, orientation ${orientation}, world ${s.nx}")
            }}
        }}
    }
    pass(true,"41472 rays match original traversal for sparse/dense worlds, alpha leaves, burn stages, hidden canopy, picking and overhead")
    try (view=VoxelView(scene,app.assets)) {
        let c=Camera(); let b=Rect(0.0,0.0,192.0,128.0); c.fitScene(scene,b)
        for(top in [false,true]) {
            view.topDown=top
            try (serial=Surface.create(192,128)) { try (parallel=Surface.create(192,128)) {
                view.rows(serial,c,b,192,128,0,128,parallel:false); view.rows(parallel,c,b,192,128,0,128)
                for(y in 0..128){for(x in 0..192){
                    let a=serial.readPixel(Int32(x),Int32(y)); let d=parallel.readPixel(Int32(x),Int32(y))
                    require(a.r==d.r && a.g==d.g && a.b==d.b && a.a==d.a,"Parallel raster changed pixels")
                }}
            }}
        }
    }
    pass(true,"Parallel CPU rows match serial native pixels for both 3D and overhead; SDL writes remain on owner thread")
    try (view=VoxelView(scene,app.assets)) { try(s=Surface.create(96,64)) {
        let c=Camera(); let b=Rect(0.0,0.0,96.0,64.0); c.fitScene(scene,b)
        for(pan in [0.0,90.0,300.0]) {
            c.panX=pan; c.panY=pan/3.0; view.rows(s,c,b,96,64,0,64)
            for(y in 0..64){for(x in 0..96){
                let a=s.readPixel(Int32(x),Int32(y)); let d=view.color(c.ray(Float64(x)+0.5,Float64(y)+0.5,b))
                require(a.r==d.r && a.g==d.g && a.b==d.b,"Viewport rejection dropped visible geometry")
            }}
        }
        c.focusScene(scene)
        pass(c.zoom==20.0 && c.minimumZoom==8.0 && c.centerX==32.0 && c.distance==60.0,"Large forest local camera retains working scale rather than shrinking the whole world into viewport")
    }}
    pass(true,"Viewport AABB rejection matches uncropped ray colors for visible, partially offscreen and fully offscreen scenes")
    let corner=Scene(nx:32,nz:32,ny:32,demo:false)
    for (position in [[7,7,8],[7,8,8],[8,8,8],[24,24,23]]) {
        corner.clear(); corner.set(position[0],position[1],position[2],5)
        for(ray in [Ray(Vec(0.5,0.5,0.5),Vec(1.0,1.0,1.0)),Ray(Vec(31.5,31.5,31.5),Vec(-1.0,-1.0,-1.0))]) {
            require(sameTrace(traceReference(corner,ray),trace(corner,ray)),"Chunk corner changed reference axis ordering")
        }
    }
    pass(true,"Chunk-edge and corner ties preserve original hit ordering in both ray directions")
    let s=Scene(nx:32,nz:32,demo:false); s.set(9,9,9,3); s.set(9,9,9,4)
    require(s.chunkCounts[s.chunkIndex(9,9,9)]==1,"Replacing a solid voxel changed occupancy")
    s.set(9,9,9,0); require(s.chunkCounts[s.chunkIndex(9,9,9)]==0,"Removing last voxel did not empty chunk")
    s.set(15,7,15,1); s.clear()
    for(n in s.chunkCounts){require(n==0,"Clear left stale occupied chunks")}
    pass(rejected({=>s.set(0,0,0,256)}),"Chunk counts handle replacement/removal/clear and packed voxels reject invalid materials")
}
