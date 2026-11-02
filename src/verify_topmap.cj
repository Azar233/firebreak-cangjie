package firebreak

import sdl.*

func verifyTopMap(app: App,w: SdlWindow): Unit {
    // Exercise legacy imported materials explicitly; new forests have no road or house.
    let annotated=Project();annotated.land[9*GRID_X+2]=2;annotated.land[4*GRID_X+17]=4
    app.work.acceptLoaded(annotated,"");app.syncScene()
    let l=Layout(Float32(w.width),Float32(w.height))
    app.mapMode=true; app.referenceMode=false; app.camera.yaw=2.3; app.camera.pitch=0.4
    app.view.selectedX = -1; app.view.selectedZ = -1
    var count: Int64=0
    for (aspect in [0.6,1.2,2.0]) {
        app.work.project.aspect=aspect
        for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
            let p=mapPoint(app,l,x,z)
            require(app.cellAt(p.x,p.y,l)==z*GRID_X+x,"Overhead cell picking changed with aspect or 3D camera")
            count++
        } }
    }
    pass(count==1440,"1440 overhead map picks preserve cell coordinates across aspect ratios independently of 3D camera")
    app.work.project.aspect=1.2
    let box=app.mapBox(l)
    let paper=app.mapPaperBox(l)
    pass(paper.x>=l.canvas.x && paper.y>=l.canvas.y && paper.right()<=l.canvas.right() && paper.bottom()<=l.canvas.bottom() &&
        box.x-paper.x==32.0 && box.y-paper.y==32.0 && app.cellAt(paper.x+12.0,paper.centerY(),l)<0,
        "original-map parchment fits viewport and paper margin is not editable terrain")
    pass(app.cellAt(box.x-1.0,box.y,l)<0 && app.cellAt(box.right()+1.0,box.y,l)<0,"overhead letterbox margins do not pick terrain")
    app.view.showCanopy=false; app.view.dirty=true
    app.view.prepare(app.camera,box,w,forceFull:true,topDown:true)
    try (s=Surface.create(384,320)) {
        app.view.rows(s,app.camera,box,384,320,0,320)
        for (cell in [[2,2,1],[2,9,8],[17,4,7]]) {
            let x=cell[0]; let z=cell[1]; let material=cell[2]
            let actual=s.readPixel(Int32(x*16+8),Int32(z*16+8))
            let expected=app.assets.sample(Hit(x,0,z,1,0.0,8.5/16.0,8.5/16.0,material))
            require(actual.r==expected.r && actual.g==expected.g && actual.b==expected.b,"Overhead surface differs from MC grass, path or roof texture")
        }
    }
    pass(true,"overhead pixels use actual MC grass, road and topmost roof textures")
    let top=trace(app.scene,overheadRay(app.scene,3.5/24.0,3.5/20.0),leavesOpaque:true).getOrThrow()
    let ground=trace(app.scene,overheadRay(app.scene,3.5/24.0,3.5/20.0),groundOnly:true).getOrThrow()
    pass(top.material==4 && ground.material==1 && top.y>ground.y,"overhead scene keeps canopy occlusion while picking the ground beneath")
    let frame=app.view.texture.getOrThrow()
    app.view.prepare(app.camera,box,w,forceFull:true)
    pass(frame.isClosed() && !app.view.topDown,"projection change invalidates cached overhead texture even for the same viewport")
    // A paper margin can make the normal map smaller than the preview cap.
    // Exercise cancellation with a target that actually requires progressive refinement.
    let progressive=Rect(box.x,box.y,box.w*2.0,box.h*2.0)
    app.view.dirty=true; app.view.prepare(app.camera,progressive,w,interacting:true); app.view.lastChange=0
    app.view.prepare(app.camera,progressive,w)
    let pending=app.view.pending.getOrThrow()
    app.view.prepare(app.camera,progressive,w,interacting:true,topDown:true)
    pass(pending.isClosed() && app.view.pending.isNone(),"switching to overhead cancels unfinished oblique render")
    let oldYaw=app.camera.yaw; let oldPitch=app.camera.pitch
    click(app,w,16); click(app,w,16)
    pass(app.mapMode && app.camera.yaw==oldYaw && app.camera.pitch==oldPitch,"map switching preserves oblique camera orientation")
    app.view.showCanopy=true; app.view.dirty=true; app.tool=0; app.focus=0
    render(app,w,capture:"artifacts/p1-topmap.png")
    app.mapMode=false; app.camera.reset(); app.view.dirty=true
    app.work.saved=app.work.project.text(); app.work.unsaved=false
}
