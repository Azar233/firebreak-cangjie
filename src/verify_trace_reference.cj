package firebreak

import std.math.{floor,abs}

func traceReference(scene: Scene,ray: Ray,groundOnly!: Bool = false,leavesOpaque!: Bool = false,
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
