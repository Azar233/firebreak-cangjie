package firebreak

import sdl.*
import std.math.abs
import std.fs.exists

func pass(ok: Bool,name: String): Unit { require(ok,"FAIL "+name); println("PASS "+name) }
func event(app: App,w: SdlWindow,e: UiEvent): Unit { require(app.handle(w,UiEventRecord(e)),"Unexpected quit") }
func click(app: App,w: SdlWindow,id: Int64): Unit {
    let b=Layout(Float32(w.width),Float32(w.height)).control(id)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,b.centerX(),b.centerY()))
    event(app,w,UiEvent.MouseUp(MouseButton.Left,b.centerX(),b.centerY()))
}
func flatScene(): Scene {
    let s=Scene()
    for (i in 0..s.blocks.size) { s.blocks[i]=0 }
    for (z in 0..s.nz) { for (x in 0..s.nx) { s.heights[z*s.nx+x]=1; s.set(x,0,z,1) } }
    return s
}
func verifyResolution(app: App,w: SdlWindow): Unit {
    let box=Rect(20.0,108.0,950.0,622.0)
    for (scale in [1.0,1.25,1.5,2.0]) {
        let size=canvasResolution(box,scale)
        require(Float64(size.width)>=Float64(box.w)*scale && Float64(size.height)>=Float64(box.h)*scale,
            "HiDPI native target is undersampled")
    }
    pass(true,"native canvas sizing handles 100/125/150/200 percent DPI")
    let bounded=canvasResolution(Rect(0.0,0.0,20000.0,10000.0),2.0)
    pass(bounded.width<=8192 && bounded.height<=8192 && bounded.width*bounded.height<=16777216,
        "extreme canvas dimensions retain bounded allocation")
    var rejected=false
    try { canvasResolution(box,0.0) } catch (_: Exception) { rejected=true }
    pass(rejected,"invalid pixel scale rejected")
    w.setSize(2560,1380); w.refreshSize()
    let large=Layout(Float32(w.width),Float32(w.height))
    app.view.prepare(app.camera,large.canvas,w,forceFull:true)
    let wanted=canvasResolution(large.canvas,Float64(w.scale)*Float64(w.currentPixelDensity))
    let full=app.view.texture.getOrThrow()
    pass(Int64(full.width)==wanted.width && Int64(full.height)==wanted.height && app.view.nativeReady(),
        "large window settles to actual canvas pixels instead of fixed 480px")
    println("Large canvas target: ${wanted.width} x ${wanted.height}")
    let p=app.camera.project(Vec(3.5,1.0,3.5),large.canvas)
    app.select(p.x,p.y,large)
    pass(app.view.selectedX==3 && app.view.selectedZ==3,"large-window picking uses logical coordinates independently of render pixels")
    app.view.prepare(app.camera,large.canvas,w,forceFull:true)
    pass(!refEq(full,app.view.texture.getOrThrow()) && full.isClosed(),"same-size camera/selection invalidation replaces old native frame")
    app.camera.rotate(8.0,0.0); app.view.dirty=true
    app.view.prepare(app.camera,large.canvas,w,interacting:true)
    pass(app.view.texture.getOrThrow().width==640.0 && !app.view.nativeReady() && app.view.pending.isNone(),
        "interaction publishes preview and defers native refinement")
    app.view.lastChange=0
    app.view.prepare(app.camera,large.canvas,w)
    pass(app.view.pending.isSome() && app.view.nextRow>0 && app.view.nextRow<=32,"idle refinement advances in bounded row batches")
    let oldPending=app.view.pending.getOrThrow()
    app.camera.rotate(8.0,0.0); app.view.dirty=true
    app.view.prepare(app.camera,large.canvas,w,interacting:true)
    pass(oldPending.isClosed() && app.view.pending.isNone(),"camera change cancels stale refinement surface")
    app.view.lastChange=0
    for (_ in 0..wanted.height+1) {
        app.view.prepare(app.camera,large.canvas,w)
        if (app.view.nativeReady()) { break }
    }
    pass(app.view.nativeReady() && app.view.pending.isNone(),"normal idle ticks replace preview with complete native frame")
    render(app,w,capture:"artifacts/p0-fullscreen.png")
    w.setSize(1280,860); w.refreshSize()
    app.camera.reset(); app.view.selectedX = -1; app.view.selectedZ = -1; app.view.dirty=true
}
func verifyP0(app: App,w: SdlWindow): Unit {
    let l=Layout(Float32(w.width),Float32(w.height))
    let flat=flatScene()
    let c=Camera()
    var checks: Int64=0
    for (yaw in [-1.2,0.64,2.4]) { for (pitch in [0.45,0.9,1.5707963267948966]) { for (zoom in [10.0,28.0]) {
        c.yaw=yaw; c.pitch=pitch; c.zoom=zoom; c.panX=37.0; c.panY = -18.0
        for (cell in [[2,2],[8,5],[12,12],[21,17]]) {
            let p=c.project(Vec(Float64(cell[0])+0.5,1.0,Float64(cell[1])+0.5),l.canvas)
            let h=trace(flat,c.ray(Float64(p.x),Float64(p.y),l.canvas),groundOnly:true).getOrThrow()
            require(h.x==cell[0] && h.z==cell[1],"Projection/picking mismatch"); checks++
        }
    } } }
    pass(checks==72,"72 world/screen/ground round trips across rotation, top view, zoom and pan")
    c.reset(); c.scale(10000.0); pass(c.zoom<=40.0,"zoom upper bound")
    c.scale(-10000.0); pass(c.zoom>=8.0,"zoom lower bound")
    c.rotate(0.0,-1.0e6); pass(c.pitch>=0.25,"pitch prevents underground camera")
    pass(trace(flat,Ray(Vec(-2.0,5.0,-2.0),Vec(0.0,-1.0,0.0))).isNone(),"parallel outside ray misses safely")
    pass(trace(flat,Ray(Vec(5.0,4.0,5.0),Vec(0.0,1.0,0.0))).isNone(),"ray pointing away misses")
    // Two independent opaque voxels: the near face wins; remove it and the far one is visible.
    flat.set(5,2,12,5); flat.set(5,2,4,6)
    let ray=Ray(Vec(5.5,2.5,19.5),Vec(0.0,0.0,-1.0))
    let front=trace(flat,ray,leavesOpaque:true).getOrThrow()
    pass(front.z==12 && front.material==5 && abs(front.distance-6.5)<1.0e-5,"near voxel occludes distant voxel")
    flat.set(5,2,12,0)
    pass(trace(flat,ray,leavesOpaque:true).getOrThrow().z==4,"removing near voxel reveals distant voxel")
    var hole: Int64 = -1; var solid: Int64 = -1
    for (i in 0..256) {
        if (app.assets.tiles[5].pixels[i].a<UInt8(128)) { hole=i }
        else { solid=i }
    }
    pass(hole>=0 && solid>=0,"original leaves contain both alpha holes and solid pixels")
    flat.set(5,2,12,4)
    for (pixel in [hole,solid]) {
        let u=(Float64(pixel%16)+0.5)/16.0; let v=(Float64(pixel/16)+0.5)/16.0
        let leafRay=Ray(Vec(5.0+u,3.0-v,19.5),Vec(0.0,0.0,-1.0))
        let h=trace(flat,leafRay,atlas:Some(app.assets)).getOrThrow()
        require(h.z==(if (pixel==hole) { 4 } else { 12 }),"Alpha-tested voxel occlusion mismatch")
    }
    pass(true,"leaf alpha holes reveal background without sorting artifacts")
    let down=Ray(Vec(3.5,13.0,3.5),Vec(0.0,-1.0,0.0))
    let canopy=trace(app.scene,down,leavesOpaque:true).getOrThrow()
    let ground=trace(app.scene,down,groundOnly:true).getOrThrow()
    pass(canopy.material==4 && ground.y==0 && ground.x==3 && ground.z==3,"ground picking ignores tree canopy")
    let gray=app.assets.tiles[5].pixels[solid]
    let tinted=app.assets.sample(Hit(0,0,0,1,0.0,(Float64(solid%16)+0.5)/16.0,(Float64(solid/16)+0.5)/16.0,4))
    pass(tinted.g>tinted.r && tinted.r<=gray.r && tinted.a==gray.a,"foliage tint preserves alpha")
    for (size in [Size(1280.0,860.0),Size(1100.0,780.0),Size(1600.0,1000.0)]) {
        let layout=Layout(size.w,size.h)
        for (id in CONTROLS) { if (!layout.available(id,false)) { continue }
            let b=layout.control(id)
            require(b.w>=44.0 && b.h>=44.0 && b.x>=0.0 && b.right()<=size.w && b.bottom()<=size.h,"Control outside window")
            require(layout.hit(b.centerX(),b.centerY())==id,"Hit target mismatch")
        }
        require(layout.canvas.w>0.0 && layout.canvas.h>0.0 && layout.canvas.right()<layout.panel.x,"Canvas/panel overlap")
    }
    pass(true,"visible control targets and canvas bounds at 3 desktop sizes")
    click(app,w,20+4); pass(app.tool==4,"hotbar selects map through pointer events")
    event(app,w,UiEvent.KeyDown(Key.Digit(UInt8(50)),false)); pass(app.tool==1,"number key selects second tool")
    app.focus=0
    app.handle(w,UiEventRecord(UiEvent.KeyDown(Key.Tab,false),UiEventMetadata(modifiers:EventKeyModifiers(raw:UInt16(1)))))
    pass(CONTROLS[app.focus]==32,"Shift+Tab reverse focus skips hidden numeric fields")
    click(app,w,1); pass(app.camera.pitch>1.57,"top view button")
    click(app,w,2); pass(!app.view.showCanopy,"canopy visibility button")
    click(app,w,0); pass(abs(app.camera.yaw-0.64)<1.0e-12 && app.camera.panX==0.0,"camera reset button")
    click(app,w,20)
    let p=app.camera.project(Vec(3.5,1.0,3.5),l.canvas)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,p.x,p.y))
    pass(app.view.selectedX==3 && app.view.selectedZ==3,"pointer selects ground beneath canopy")
    let oldYaw=app.camera.yaw
    event(app,w,UiEvent.MouseDown(MouseButton.Right,l.canvas.centerX(),l.canvas.centerY()))
    event(app,w,UiEvent.MouseMove(l.canvas.centerX()+20.0,l.canvas.centerY()))
    event(app,w,UiEvent.MouseUp(MouseButton.Right,l.canvas.centerX()+20.0,l.canvas.centerY()))
    pass(app.camera.yaw!=oldYaw && !app.dragging,"right-drag rotates and releases")
    event(app,w,UiEvent.MouseDown(MouseButton.Middle,l.canvas.centerX(),l.canvas.centerY()))
    event(app,w,UiEvent.MouseMove(l.canvas.centerX()+16.0,l.canvas.centerY()+12.0))
    pass(app.camera.panX==16.0 && app.camera.panY==12.0,"middle-drag pans")
    event(app,w,UiEvent.WindowFocusLost); pass(!app.panning && app.pressed<0,"focus loss clears drag state")
    app.camera.reset(); app.view.showCanopy=true; app.view.dirty=true; app.view.selectedX = -1; app.view.selectedZ = -1
    verifyResolution(app,w)
    // One representative screenshot only: basic resource/loading/position handoff, no aesthetic baseline.
    render(app,w,capture:"artifacts/p0-workbench.png")
    println("P0 first scene rasterization: ${app.view.lastRenderMs} ms; cached while camera is unchanged")
    pass(exists("artifacts/p0-workbench.png"),"native SDL screenshot generated")
    pass(app.assets.images.size>TOOL_PATHS.size,"bitmap font pages and UI textures load")
    let cached=app.view.texture.getOrThrow()
    app.view.prepare(app.camera,l.canvas,w)
    pass(refEq(cached,app.view.texture.getOrThrow()),"unchanged camera reuses rendered scene texture")
    app.view.dirty=true
    app.view.prepare(app.camera,l.canvas,w,interacting:true)
    app.view.lastChange=0
    app.view.prepare(app.camera,l.canvas,w)
    let pending=app.view.pending.getOrThrow(); let preview=app.view.texture.getOrThrow()
    app.view.close(); app.view.close()
    pass(app.view.isClosed() && cached.isClosed() && preview.isClosed() && pending.isClosed(),"closing releases cached frame and incomplete refinement safely")
    let widgets=app.assets.image("textures/gui/widgets.png")
    app.assets.close(); app.assets.close()
    pass(app.assets.isClosed() && widgets.isClosed(),"asset textures release safely before window close")
    println("P0 logic/resource/position checks completed. Visual quality awaits user review.")
}
