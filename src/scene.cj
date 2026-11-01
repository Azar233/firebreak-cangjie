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
    func reset(): Unit { yaw=0.64; pitch=0.67; zoom=20.0; panX=0.0; panY=0.0 }
    func rotate(dx: Float64,dy: Float64): Unit {
        yaw += dx*0.008; pitch=clamp(pitch+dy*0.006,0.25,1.5707963267948966)
    }
    func scale(wheel: Float64): Unit { zoom=clamp(zoom*1.12**clamp(wheel,-4.0,4.0),8.0,40.0) }
    func right(): Vec { Vec(cos(yaw),0.0,-sin(yaw)) }
    func up(): Vec { Vec(-sin(yaw)*sin(pitch),cos(pitch),-cos(yaw)*sin(pitch)) }
    func outward(): Vec { Vec(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch)) }
    func target(): Vec { Vec(12.0,1.5,10.0) }
    func project(p: Vec,b: Rect): Point {
        let d=p.sub(target())
        return Point(b.centerX()+Float32(panX+d.dot(right())*zoom),b.centerY()+Float32(panY-d.dot(up())*zoom))
    }
    func ray(x: Float64,y: Float64,b: Rect): Ray {
        let sx=(x-Float64(b.centerX())-panX)/zoom
        let sy=-(y-Float64(b.centerY())-panY)/zoom
        return Ray(target().add(outward().mul(60.0)).add(right().mul(sx)).add(up().mul(sy)),outward().mul(-1.0))
    }
}

// 0 air, 1 grass, 2 dirt, 3 oak log, 4 leaves, 5 stone, 6 planks, 7 brick, 8 path.
class Scene {
    let nx: Int64 = 24
    let ny: Int64 = 14
    let nz: Int64 = 20
    let blocks=Array<Int64>(24*14*20,repeat: 0)
    let heights=Array<Int64>(24*20,repeat: 0)
    let canopyColumns=Array<Bool>(24*20,repeat:true)
    var trees: Int64 = 0
    init() {
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
    func get(x: Int64,y: Int64,z: Int64): Int64 { if (inside(x,y,z)) { blocks[index(x,y,z)] } else { 0 } }
    func set(x: Int64,y: Int64,z: Int64,value: Int64): Unit { if (inside(x,y,z)) { blocks[index(x,y,z)]=value } }
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
    let o=[ray.origin.x,ray.origin.y,ray.origin.z]
    let d=[ray.direction.x,ray.direction.y,ray.direction.z]
    let sizes=[scene.nx,scene.ny,scene.nz]
    var near=0.0; var far=10000.0; var axis: Int64 = 1
    for (a in 0..3) {
        if (abs(d[a])<1.0e-12) {
            if (o[a]<0.0 || o[a]>=Float64(sizes[a])) { return None }
        } else {
            let t1=-o[a]/d[a]; let t2=(Float64(sizes[a])-o[a])/d[a]
            let lo=min(t1,t2); let hi=max(t1,t2)
            if (lo>near) { near=lo; axis=a }; far=min(far,hi)
        }
    }
    if (near>=far || far<0.0) { return None }
    var distance=near+1.0e-7
    let p=ray.origin.add(ray.direction.mul(distance))
    let cell=[Int64(floor(p.x)),Int64(floor(p.y)),Int64(floor(p.z))]
    let step=Array<Int64>(3,{ a => if (d[a]>0.0) { 1 } else { -1 } })
    let next=Array<Float64>(3,{ a => if (abs(d[a])<1.0e-12) { 1.0e30 }
        else { (Float64(cell[a]+(if (step[a]>0) { 1 } else { 0 }))-o[a])/d[a] } })
    let delta=Array<Float64>(3,{ a => if (abs(d[a])<1.0e-12) { 1.0e30 } else { abs(1.0/d[a]) } })
    for (_ in 0..scene.nx+scene.ny+scene.nz+4) {
        let x=cell[0]; let y=cell[1]; let z=cell[2]
        if (!scene.inside(x,y,z) || distance>far) { break }
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
        axis=if (next[0]<next[1] && next[0]<next[2]) { 0 } else if (next[1]<next[2]) { 1 } else { 2 }
        distance=next[axis]+1.0e-7; cell[axis]+=step[axis]; next[axis]+=delta[axis]
    }
    return None
}
