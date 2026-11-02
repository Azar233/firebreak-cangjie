package firebreak

import std.math.{sin, cos, floor, abs}
import sdl.{Point, Rect}

func require(ok: Bool, message: String): Unit { if (!ok) { throw Exception(message) } }
func clamp(v: Float64, low: Float64, high: Float64): Float64 { max(low,min(high,v)) }

struct Vec {
    let x: Float64
    let y: Float64
    let z: Float64
    init(x: Float64,y: Float64,z: Float64) { this.x=x; this.y=y; this.z=z }
    func add(b: Vec): Vec { Vec(x+b.x,y+b.y,z+b.z) }
    func sub(b: Vec): Vec { Vec(x-b.x,y-b.y,z-b.z) }
    func mul(k: Float64): Vec { Vec(x*k,y*k,z*k) }
    func dot(b: Vec): Float64 { x*b.x+y*b.y+z*b.z }
}
struct Ray {
    let origin: Vec
    let direction: Vec
    init(origin: Vec,direction: Vec) { this.origin=origin; this.direction=direction }
}
// North-up orthographic view. Normalized coordinates also drive map picking.
func overheadRay(scene: Scene,u: Float64,v: Float64): Ray {
    Ray(Vec(u*Float64(scene.nx),Float64(scene.ny)+1.0,v*Float64(scene.nz)),Vec(0.0,-1.0,0.0))
}
class Camera {
    var yaw: Float64 = 0.64
    var pitch: Float64 = 0.67
    var zoom: Float64 = 20.0
    var panX: Float64 = 0.0
    var panY: Float64 = 0.0
    var centerX: Float64 = 12.0
    var centerZ: Float64 = 10.0
    var distance: Float64 = 60.0
    var minimumZoom: Float64 = 8.0
    var maximumZoom: Float64 = 40.0
    func reset(): Unit { yaw=0.64; pitch=0.67; zoom=20.0; panX=0.0; panY=0.0 }
    func rotate(dx: Float64,dy: Float64): Unit {
        yaw += dx*0.008; pitch=clamp(pitch+dy*0.006,0.25,1.5707963267948966)
    }
    func scale(wheel: Float64): Unit { zoom=clamp(zoom*1.12**clamp(wheel,-4.0,4.0),minimumZoom,maximumZoom) }
    func right(): Vec { Vec(cos(yaw),0.0,-sin(yaw)) }
    func up(): Vec { Vec(-sin(yaw)*sin(pitch),cos(pitch),-cos(yaw)*sin(pitch)) }
    func outward(): Vec { Vec(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch)) }
    func target(): Vec { Vec(centerX,1.5,centerZ) }
    func fitScene(scene: Scene,b: Rect): Unit {
        centerX=Float64(scene.nx)/2.0; centerZ=Float64(scene.nz)/2.0
        distance=Float64(max(scene.nx,scene.nz)*2+scene.ny*2)
        yaw=0.64; pitch=0.67; panX=0.0; panY=0.0
        zoom=min(Float64(b.w),Float64(b.h))*0.7/Float64(max(scene.nx,scene.nz))
        minimumZoom=zoom/4.0; maximumZoom=40.0
    }
    func focusScene(scene: Scene): Unit {
        centerX=Float64(scene.nx)/2.0; centerZ=Float64(scene.nz)/2.0; distance=60.0
        minimumZoom=8.0; maximumZoom=40.0; reset()
    }
    func project(p: Vec,b: Rect): Point {
        let d=p.sub(target())
        return Point(b.centerX()+Float32(panX+d.dot(right())*zoom),b.centerY()+Float32(panY-d.dot(up())*zoom))
    }
    func ray(x: Float64,y: Float64,b: Rect): Ray {
        let sx=(x-Float64(b.centerX())-panX)/zoom
        let sy=-(y-Float64(b.centerY())-panY)/zoom
        return Ray(target().add(outward().mul(distance)).add(right().mul(sx)).add(up().mul(sy)),outward().mul(-1.0))
    }
}

// 0 air, 1 grass, 2 dirt, 3 oak log, 4 leaves, 5 stone, 6 planks, 7 brick, 8 path.
class Scene {
    let nx: Int64
    let ny: Int64
    let nz: Int64
    let blocks: Array<UInt8>
    let chunkCounts: Array<Int64>
    let chunksX: Int64
    let chunksY: Int64
    let heights: Array<Int64>
    let canopyColumns: Array<Bool>
    var trees: Int64 = 0
    init(nx!: Int64=24,nz!: Int64=20,ny!: Int64=14,demo!: Bool=true) {
        require(nx>0 && nx<=2048 && nz>0 && nz<=2048 && ny>=8 && ny<=64 && nx*nz*ny<=67108864,"Scene dimensions exceed stress-test allocation bound")
        require(!demo || (nx==24 && nz==20 && ny==14),"Demo scene requires the original dimensions")
        this.nx=nx; this.ny=ny; this.nz=nz
        chunksX=(nx+7)/8; chunksY=(ny+7)/8
        chunkCounts=Array<Int64>(chunksX*chunksY*((nz+7)/8),repeat:0)
        blocks=Array<UInt8>(nx*ny*nz,repeat:0); heights=Array<Int64>(nx*nz,repeat:0); canopyColumns=Array<Bool>(nx*nz,repeat:true)
        if (!demo) { return }
        for (z in 0..nz) { for (x in 0..nx) {
            let h=if (x>15 && z>12) { 3 } else if (x>12 && z>10) { 2 } else { 1 }
            heights[z*nx+x]=h
            for (y in 0..h) { set(x,y,z,if (y==h-1) { if (z==9 || z==10) { 8 } else { 1 } } else { 2 }) }
        } }
        for (p in [[3,3],[7,3],[11,3],[3,7],[8,7],[12,6],[4,14],[8,15],[12,14],[17,15],[21,15],[18,18],[21,4],[21,8]]) {
            tree(p[0],p[1])
        }
        // Small protected-building stand-in; no planning or fire logic in P0.
        for (z in 3..7) { for (x in 16..20) {
            for (y in 1..4) { set(x,y,z,if (x==16 || x==19 || z==3 || z==6) { 6 } else { 0 }) }
            set(x,4,z,7)
        } }
        set(17,1,6,0); set(17,2,6,0)
    }
    func index(x: Int64,y: Int64,z: Int64): Int64 { (z*ny+y)*nx+x }
    func inside(x: Int64,y: Int64,z: Int64): Bool { x>=0 && x<nx && y>=0 && y<ny && z>=0 && z<nz }
    func get(x: Int64,y: Int64,z: Int64): Int64 { if (inside(x,y,z)) { Int64(blocks[index(x,y,z)]) } else { 0 } }
    func chunkIndex(x: Int64,y: Int64,z: Int64): Int64 { ((z/8)*chunksY+y/8)*chunksX+x/8 }
    func clear(): Unit { for(i in 0..blocks.size) { blocks[i]=0 }; for(i in 0..chunkCounts.size) { chunkCounts[i]=0 }; trees=0 }
    func set(x: Int64,y: Int64,z: Int64,value: Int64): Unit {
        if (inside(x,y,z)) {
            require(value>=0 && value<=255,"Invalid voxel material")
            let i=index(x,y,z); let before=blocks[i]>0; let after=value>0
            if (before!=after) { chunkCounts[chunkIndex(x,y,z)]+=if (after) { 1 } else { -1 } }
            blocks[i]=UInt8(value)
        }
    }
    func ground(x: Int64,z: Int64): Float64 { Float64(heights[z*nx+x]) }
    func tree(x: Int64,z: Int64): Unit {
        let base=heights[z*nx+x]
        for (y in base..base+4) { set(x,y,z,3) }
        for (dy in 2..5) { for (dz in -2..3) { for (dx in -2..3) {
            let radius=if (dy==4) { 1 } else { 2 }
            if (abs(dx)<=radius && abs(dz)<=radius && abs(dx)+abs(dz)<=radius+1 &&
                inside(x+dx,base+dy,z+dz) && canopyColumns[(z+dz)*nx+x+dx] && get(x+dx,base+dy,z+dz)==0) {
                set(x+dx,base+dy,z+dz,4)
            }
        } } }
        trees++
    }
}

struct Hit {
    let x: Int64
    let y: Int64
    let z: Int64
    let axis: Int64
    let distance: Float64
    let u: Float64
    let v: Float64
    let material: Int64
    init(x: Int64,y: Int64,z: Int64,axis: Int64,distance: Float64,u: Float64,v: Float64,material: Int64) {
        this.x=x; this.y=y; this.z=z; this.axis=axis; this.distance=distance
        this.u=u; this.v=v; this.material=material
    }
}
func fraction(v: Float64): Float64 { v-floor(v) }

// Display-only damage: the original voxel array and simulation fuel stay intact.
// 0 intact, 1..3 progressively fewer leaf voxels, 4 ash and one-block stumps.
func burnVisualStage(age: Int64,duration: Int64): Int64 {
    if (age<0) { return 4 }; if (age==0) { return 0 }
    return 1+min(2,max(0,duration-age)*3/max(1,duration))
}
func fireDisplayMaterial(scene: Scene,material: Int64,x: Int64,y: Int64,z: Int64,stage: Int64): Int64 {
    if (stage==0) { return material }
    if (material==4 && (stage==4 || (x*17+y*13+z*7)%4<stage)) { return 0 }
    if (stage==4) {
        if (material==3 && y>scene.heights[z*scene.nx+x]) { return 0 }
        if (material==1 && y==scene.heights[z*scene.nx+x]-1) { return 10 }
    }
    return material
}

// Amanatides-Woo style voxel traversal; opaque/alpha-tested surfaces stop the ray.
// groundOnly ignores canopy/buildings and finds the actual terrain under the pointer.
func trace(scene: Scene,ray: Ray,groundOnly!: Bool = false,leavesOpaque!: Bool = false,
    atlas!: ?Assets = None,showCanopy!: Bool = true,fireStages!: ?Array<Int64> = None): ?Hit {
    var near=0.0; var far=10000.0; var axis: Int64 = 1
    for (a in 0..3) {
        let o=component(ray.origin,a); let d=component(ray.direction,a)
        let size=Float64(if (a==0) { scene.nx } else if (a==1) { scene.ny } else { scene.nz })
        if (abs(d)<1.0e-12) {
            if (o<0.0 || o>=size) { return None }
        } else {
            let t1=-o/d; let t2=(size-o)/d
            let lo=min(t1,t2); let hi=max(t1,t2)
            if (lo>near) { near=lo; axis=a }; far=min(far,hi)
        }
    }
    if (near>=far || far<0.0) { return None }
    var distance=near+1.0e-7
    let p=ray.origin.add(ray.direction.mul(distance))
    var x=Int64(floor(p.x)); var y=Int64(floor(p.y)); var z=Int64(floor(p.z))
    let dx=ray.direction.x; let dy=ray.direction.y; let dz=ray.direction.z
    let stepX: Int64=if(dx>0.0){1}else{-1}; let stepY: Int64=if(dy>0.0){1}else{-1}; let stepZ: Int64=if(dz>0.0){1}else{-1}
    var tx=voxelExit(ray.origin.x,dx,x,1); var ty=voxelExit(ray.origin.y,dy,y,1); var tz=voxelExit(ray.origin.z,dz,z,1)
    let deltaX=voxelDelta(dx); let deltaY=voxelDelta(dy); let deltaZ=voxelDelta(dz)
    for (_ in 0..scene.nx+scene.ny+scene.nz+4) {
        if (!scene.inside(x,y,z) || distance>far) { break }
        // Two-level traversal: skip only chunks with no base voxel at all.
        // Burn filtering only removes geometry, so this remains conservative.
        if (scene.chunkCounts[scene.chunkIndex(x,y,z)]==0) {
            let bx=voxelExit(ray.origin.x,dx,x,8); let by=voxelExit(ray.origin.y,dy,y,8); let bz=voxelExit(ray.origin.z,dz,z,8)
            let exit=min(bx,min(by,bz))
            let tied=(if(abs(bx-exit)<1.0e-9){1}else{0})+(if(abs(by-exit)<1.0e-9){1}else{0})+(if(abs(bz-exit)<1.0e-9){1}else{0})
            // Preserve the reference's axis ordering at exact edges/corners.
            if (tied==1) {
                axis=if (bx<by && bx<bz) { 0 } else if (by<bz) { 1 } else { 2 }
                distance=exit+1.0e-7
                let q=ray.origin.add(ray.direction.mul(distance))
                x=Int64(floor(q.x)); y=Int64(floor(q.y)); z=Int64(floor(q.z))
                tx=voxelExit(ray.origin.x,dx,x,1); ty=voxelExit(ray.origin.y,dy,y,1); tz=voxelExit(ray.origin.z,dz,z,1)
                continue
            }
        }
        var mat=scene.get(x,y,z)
        if (!groundOnly) {
            if (let Some(stages) <- fireStages) { mat=fireDisplayMaterial(scene,mat,x,y,z,stages[z*scene.nx+x]) }
        }
        let isGround=y==scene.heights[z*scene.nx+x]-1
        if (mat>0 && (if (groundOnly) { isGround } else { showCanopy || mat!=4 })) {
            let q=ray.origin.add(ray.direction.mul(distance))
            let uu=if (axis==0) { fraction(q.z) } else { fraction(q.x) }
            let vv=if (axis==1) { fraction(q.z) } else { 1.0-fraction(q.y) }
            let hit=Hit(x,y,z,axis,distance,uu,vv,mat)
            if (mat!=4 || leavesOpaque || groundOnly) { return Some(hit) }
            if (let Some(a) <- atlas) { if (a.sample(hit).a>=UInt8(128)) { return Some(hit) } }
        }
        axis=if (tx<ty && tx<tz) { 0 } else if (ty<tz) { 1 } else { 2 }
        if (axis==0) { distance=tx+1.0e-7; x+=stepX; tx+=deltaX }
        else if (axis==1) { distance=ty+1.0e-7; y+=stepY; ty+=deltaY }
        else { distance=tz+1.0e-7; z+=stepZ; tz+=deltaZ }
    }
    return None
}

func component(v: Vec,axis: Int64): Float64 { if(axis==0){v.x}else if(axis==1){v.y}else{v.z} }
func voxelDelta(d: Float64): Float64 { if(abs(d)<1.0e-12){1.0e30}else{abs(1.0/d)} }
func voxelExit(o: Float64,d: Float64,cell: Int64,span: Int64): Float64 {
    if (abs(d)<1.0e-12) { return 1.0e30 }
    let boundary=(cell/span+(if(d>0.0){1}else{0}))*span
    return (Float64(boundary)-o)/d
}
