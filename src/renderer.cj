package firebreak

import sdl.*
import std.math.{ceil,floor,sqrt}

struct Resolution {
    let width: Int64
    let height: Int64
    init(width: Int64,height: Int64) { this.width=width; this.height=height }
}
func canvasResolution(b: Rect,physicalScale: Float64): Resolution {
    require(!physicalScale.isNaN() && !physicalScale.isInf() && physicalScale>0.0 && physicalScale<=16.0,
        "Invalid canvas pixel scale")
    require(b.w>0.0 && b.h>0.0 && b.w<=131072.0 && b.h<=131072.0,"Invalid canvas dimensions")
    let w=ceil(Float64(b.w)*physicalScale); let h=ceil(Float64(b.h)*physicalScale)
    // Bound allocation for unusually large/HiDPI windows; ordinary 1440p/4K fits natively.
    let ratio=min(1.0,min(8192.0/max(w,h),sqrt(16777216.0/(w*h))))
    return Resolution(max(1,Int64(floor(w*ratio))),max(1,Int64(floor(h*ratio))))
}

class VoxelView <: Resource {
    let scene: Scene
    let assets: Assets
    var texture: ?Texture=None
    var dirty=true
    var selectedX: Int64 = -1
    var selectedZ: Int64 = -1
    var showCanopy=true
    var closed=false
    var lastRenderMs: UInt64=0
    var pending: ?Surface=None
    var nextRow: Int64=0
    var targetWidth: Int64=0
    var targetHeight: Int64=0
    var lastBox=Rect(0.0,0.0,0.0,0.0)
    var lastChange: UInt64=0
    var needsFull=true
    var topDown=false
    var fireAge: Array<Int64>
    var burnStages: Array<Int64>
    var clusterLabels: Array<Int64>
    var rasterPixels=Array<Color>()
    init(scene: Scene,assets: Assets) {
        this.scene=scene; this.assets=assets
        fireAge=Array<Int64>(scene.nx*scene.nz,repeat:0); burnStages=Array<Int64>(scene.nx*scene.nz,repeat:0)
        clusterLabels=Array<Int64>(scene.nx*scene.nz,repeat:-1)
    }
    func setFireState(age: Array<Int64>,duration: Int64): Unit {
        require(age.size==scene.nx*scene.nz && duration>=1 && duration<=8,"Invalid display fire state")
        fireAge=age; burnStages=Array<Int64>(age.size,{i => burnVisualStage(age[i],duration)}); dirty=true
    }
    func fireAnchor(cell: Int64): Vec {
        let x=cell%scene.nx; let z=cell/scene.nx
        let ray=overheadRay(scene,(Float64(x)+0.5)/Float64(scene.nx),(Float64(z)+0.5)/Float64(scene.nz))
        let hit=trace(scene,ray,leavesOpaque:true,showCanopy:showCanopy,fireStages:Some(burnStages)).getOrThrow()
        return Vec(Float64(x)+0.5,Float64(hit.y)+1.0,Float64(z)+0.5)
    }
    func color(ray: Ray): Color {
        if (let Some(hit) <- trace(scene,ray,atlas:Some(assets),showCanopy:showCanopy,fireStages:Some(burnStages))) {
            let c=assets.sample(hit)
            let shade: Float64=if (hit.axis==1) { 1.0 } else if (hit.axis==0) { 0.76 } else { 0.87 }
            var result=Color.rgb(Int64(Float64(c.r)*shade),Int64(Float64(c.g)*shade),Int64(Float64(c.b)*shade))
            let cell=hit.z*scene.nx+hit.x
            if (clusterLabels[cell]>=0 && hit.material!=10) { result=result.lerp(clusterColor(clusterLabels[cell]),0.48) }
            if (fireAge[cell]>0) { result=result.lerp(Color.rgb(247,110,24),0.6) }
            else if (fireAge[cell]<0 && hit.material!=10) { result=result.lerp(Color.rgb(36,32,29),0.85) }
            if (hit.x==selectedX && hit.z==selectedZ && hit.y==scene.heights[hit.z*scene.nx+hit.x]-1) {
                result=result.lerp(Color.rgb(235,221,110),0.4)
            }
            return result
        }
        return Color.rgb(122,155,169)
    }
    func cancelRefinement(): Unit {
        if (let Some(s) <- pending) { s.close() }; pending=None; nextRow=0
    }
    func rows(surface: Surface,camera: Camera,b: Rect,width: Int64,height: Int64,from: Int64,to: Int64,parallel!: Bool=true): Unit {
        // Orthographic rays share direction and basis; compute trigonometry once per batch.
        let right=camera.right(); let up=camera.up(); let outward=camera.outward()
        let base=camera.target().add(outward.mul(camera.distance)); let direction=outward.mul(-1.0)
        let visible=projectedSceneBounds(scene,camera,b)
        let pixel={x: Int64,y: Int64=>
            if (topDown) {
                return color(overheadRay(scene,(Float64(x)+0.5)/Float64(width),(Float64(y)+0.5)/Float64(height)))
            }
            let sx=Float64(b.x)+(Float64(x)+0.5)/Float64(width)*Float64(b.w)
            let sy=Float64(b.y)+(Float64(y)+0.5)/Float64(height)*Float64(b.h)
            if (!visible.contains(Float32(sx),Float32(sy))) { return Color.rgb(122,155,169) }
            let origin=base.add(right.mul((sx-Float64(b.centerX())-camera.panX)/camera.zoom)).add(up.mul(-(sy-Float64(b.centerY())-camera.panY)/camera.zoom))
            return color(Ray(origin,direction))
        }
        if (!parallel || width*(to-from)<16384) { surface.writeRgbaRows(from,to,pixel); return }
        // Workers read immutable scene/atlas state and fill disjoint managed rows.
        // SDL locking, upload and presentation stay on the owning thread. Join all
        // workers even on failure before callers may close assets or change scenes.
        if (rasterPixels.size<width*(to-from)) { rasterPixels=Array<Color>(width*(to-from),repeat:Color.rgb(0,0,0)) }
        let pixels=rasterPixels
        let fill={part: Int64=>
            let first=from+(to-from)*part/4; let last=from+(to-from)*(part+1)/4
            for(y in first..last){for(x in 0..width){pixels[(y-from)*width+x]=pixel(x,y)}}
        }
        let first=spawn { fill(0) }; let second=spawn { fill(1) }; let third=spawn { fill(2) }
        var failure: ?Exception=None
        try { fill(3) } catch(e: Exception) { failure=Some(e) }
        for (worker in [first,second,third]) { try { worker.get() } catch(e: Exception) { failure=Some(e) } }
        if (let Some(e) <- failure) { throw e }
        surface.writeRgbaRows(from,to,{x,y=>pixels[(y-from)*width+x]})
    }
    func publish(surface: Surface): Unit {
        let replacement=assets.r.textureFromSurface(surface)
        if (let Some(old) <- texture) { old.close() }; texture=Some(replacement)
    }
    func nativeReady(): Bool {
        if (let Some(t) <- texture) { return !dirty && !needsFull && Int64(t.width)==targetWidth && Int64(t.height)==targetHeight }
        return false
    }
    func prepare(camera: Camera,b: Rect,window: SdlWindow,interacting!: Bool=false,forceFull!: Bool=false,topDown!: Bool=false): Unit {
        require(!closed,"Cannot prepare a closed voxel view")
        if (this.topDown!=topDown) { this.topDown=topDown; dirty=true }
        let resolution=canvasResolution(b,Float64(window.scale)*Float64(window.currentPixelDensity))
        if (resolution.width!=targetWidth || resolution.height!=targetHeight ||
            b.x!=lastBox.x || b.y!=lastBox.y || b.w!=lastBox.w || b.h!=lastBox.h) {
            dirty=true; targetWidth=resolution.width; targetHeight=resolution.height; lastBox=b
        }
        if (dirty) {
            cancelRefinement(); lastChange=window.ticks(); needsFull=true
            if (!forceFull) {
                let start=window.ticks()
                let width=min(640,targetWidth)
                let height=max(1,Int64(Float64(width)*Float64(b.h/b.w)))
                try (surface=Surface.create(Int32(width),Int32(height))) {
                    rows(surface,camera,b,width,height,0,height); publish(surface)
                }
                needsFull=width!=targetWidth || height!=targetHeight
                lastRenderMs=window.ticks()-start
            }
            dirty=false
        }
        if (nativeReady()) { return }
        if (!forceFull && (interacting || window.ticks()-lastChange<150)) { return }
        if (pending.isNone()) {
            pending=Some(Surface.create(Int32(targetWidth),Int32(targetHeight)))
            nextRow=0; lastRenderMs=0
        }
        let surface=pending.getOrThrow(); let start=window.ticks()
        // Progressive rows keep the SDL thread responsive without cross-thread native resources.
        if (forceFull) { rows(surface,camera,b,targetWidth,targetHeight,nextRow,targetHeight); nextRow=targetHeight }
        let end=min(targetHeight,nextRow+32)
        while (nextRow<end) {
            let to=min(end,nextRow+4)
            rows(surface,camera,b,targetWidth,targetHeight,nextRow,to); nextRow=to
            if (!forceFull && window.ticks()-start>=8) { break }
        }
        lastRenderMs+=window.ticks()-start
        if (nextRow==targetHeight) { publish(surface); cancelRefinement(); needsFull=false }
    }
    func draw(b: Rect): Unit {
        if (let Some(t) <- texture) {
            assets.r.textureStyled(t,b,style:TextureStyle(sampling:TextureScaleMode.Nearest))
        }
    }
    public func close(): Unit {
        if (closed) { return }; closed=true
        cancelRefinement()
        rasterPixels=Array<Color>()
        if (let Some(t) <- texture) { t.close() }; texture=None
    }
    public func isClosed(): Bool { closed }
}

// Conservative projected AABB intersected with the canvas. Rays outside this
// region cannot touch any voxel; partial/chunk visibility remains handled by DDA.
func projectedSceneBounds(scene: Scene,camera: Camera,b: Rect): Rect {
    var left=b.right(); var top=b.bottom(); var right=b.x; var bottom=b.y
    for(x in [0,scene.nx]){for(y in [0,scene.ny]){for(z in [0,scene.nz]){
        let p=camera.project(Vec(Float64(x),Float64(y),Float64(z)),b)
        left=min(left,p.x); top=min(top,p.y); right=max(right,p.x); bottom=max(bottom,p.y)
    }}}
    left=max(b.x,left-2.0); top=max(b.y,top-2.0); right=min(b.right(),right+2.0); bottom=min(b.bottom(),bottom+2.0)
    return Rect(left,top,max(0.0,right-left),max(0.0,bottom-top))
}
