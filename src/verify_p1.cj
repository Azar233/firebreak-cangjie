package firebreak

import sdl.*
import std.fs.{File,exists,remove}
import std.math.abs
import stdx.encoding.json.*

func rejected(action: () -> Unit): Bool {
    try { action() } catch(_: Exception) { return true }; return false
}
func mapPoint(app: App,l: Layout,x: Int64,z: Int64): Point {
    let b=app.mapWorldBox(l); return Point(b.x+(Float32(x)+0.5)*b.w/24.0,b.y+(Float32(z)+0.5)*b.h/20.0)
}
func verifyP1(app: App,w: SdlWindow): Unit {
    let model=Workbench()
    pass(readProjectText(model.project.text()).text()==model.project.text(),"P1 versioned project round trip preserves baseline, constraints, plan and prices")
    let baseline=model.project.land.clone()
    model.apply([0,1],5,false)
    pass(model.project.land==baseline && model.project.fuel(0)==1.0 && model.project.fuel(0,planned:true)==0.0,"treatment keeps baseline and changes only planned fuel")
    pass(abs(model.project.cost()-100.0)<1.0e-8,"two 25 square meter cells at 2 yuan cost exactly 100")
    let p=model.project.copy(); p.budget=100.0; model.commit(p)
    let before=model.project.text(); let revision=model.revision; let depth=model.undo.size
    pass(rejected({=>model.apply([2],5,false)}) && model.project.text()==before && model.revision==revision && model.undo.size==depth,"over-budget stroke fails atomically without consuming undo history")
    model.history(true); model.history(true)
    pass(!model.dirty() && model.project.count(model.project.treatment)==0,"undo restores original document and clean state")
    model.history(false)
    pass(model.project.cost()==100.0 && model.dirty(),"redo restores whole stroke and unsaved state")
    model.apply([1],5,true)
    pass(model.redo.isEmpty() && model.project.cost()==50.0,"new edit clears redo and removing treatment refunds cost")
    let forbidden=15*24
    let unchanged=model.project.text()
    pass(rejected({=>model.apply([2,forbidden],6,false)}) && model.project.text()==unchanged,"forbidden cell rejects entire mixed stroke")
    pass(rejected({=>model.apply([3*24+16],6,false)}) && model.project.text()==unchanged,"protected target rejects treatment")
    model.apply([0],7,false)
    pass(model.project.targets[0]==1 && model.project.treatment[0]==0 && model.project.land[0]==1,"adding a protection marker removes conflicting treatment while preserving forest")
    model.apply([1],3,false)
    pass(model.project.land[1]==3 && model.project.treatment[1]==0,"land annotation removes obsolete intervention")
    let unscaled=Project(); unscaled.metersWide=0.0; model.commit(unscaled)
    pass(rejected({=>model.apply([0],5,false)}),"uncalibrated forest cannot produce a priced intervention")
    let scaled=model.project.copy(); scaled.metersWide=240.0; model.commit(scaled); model.apply([0],6,false)
    pass(model.project.cellArea()==100.0 && model.project.cost()==500.0,"width calibration changes cell area quadratically")
    let future=JsonValue.fromStr(model.project.text()).asObject(); future.put("version",JsonInt(99))
    pass(rejected({=>readProjectText(future.toJsonString())}),"unknown project version rejected")
    pass(rejected({=>readProjectText("{}")}) && rejected({=>readProjectText("broken")}),"malformed or incomplete projects rejected")
    let invalid=model.project.copy(); invalid.breakPrice=Float64.NaN
    pass(rejected({=>model.commit(invalid)}),"non-finite price rejected")
    let file="artifacts/P1-保存恢复.firebreak"
    model.save(file); let saved=String.fromUtf8(File.readFrom(file)); model.apply([1],5,false); model.save(file)
    pass(String.fromUtf8(File.readFrom(file))!=saved && !model.dirty() && !exists(file+".writing"),"Unicode path save safely replaces existing project and removes temporary file")
    let restored=Workbench(); restored.load(file)
    pass(restored.project.text()==model.project.text() && !restored.dirty(),"saved project reload restores all state")
    File.writeTo("artifacts/p1-invalid.firebreak","{}".toArray())
    let current=model.project.text(); let savedPath=model.path
    pass(rejected({=>model.load("artifacts/p1-invalid.firebreak")}) && model.project.text()==current && model.path==savedPath,"failed load retains active project and save path")
    File.writeTo(file+".writing","recovery sentinel".toArray())
    pass(rejected({=>model.save(file)}) && String.fromUtf8(File.readFrom(file))==current,"existing recovery file blocks save without overwriting original")
    remove(file+".writing")
    model.apply([2],5,false)
    pass(rejected({=>model.save("artifacts")}) && model.dirty() && model.path==savedPath && exists(file) && !exists("artifacts.writing"),"failed replacement of directory preserves original, unsaved state and path")
    pass(String.fromUtf8(File.readFrom(file))==current,"failed save leaves previously saved bytes intact")

    // Native image codec round trips and embedded references; no screenshot similarity baseline.
    try(s=Surface.create(120,80)) {
        for (y in 0..80) { for (x in 0..120) { s.writePixel(Int32(x),Int32(y),Color.rgb(140,170,110)) } }
        s.savePng("artifacts/p1-source.png"); s.saveJpeg("artifacts/p1-source.jpg")
    }
    app.importImage("artifacts/p1-source.jpg")
    pass(app.reference.isSome() && app.work.project.metersWide==0.0 && app.work.project.aspect==1.5,"JPEG import preserves aspect and starts uncalibrated")
    app.importImage("artifacts/p1-source.png")
    let imported=app.work.project.text(); let reference=app.reference.getOrThrow()
    pass(rejected({=>app.importImage("artifacts/p1-invalid.firebreak")}) && app.work.project.text()==imported && refEq(reference,app.reference.getOrThrow()) && !reference.isClosed(),"bad image import preserves document and live texture")
    let cal=app.work.project.copy(); cal.metersWide=120.0; app.work.commit(cal)
    pass(abs(cal.cellArea()-20.0)<1.0e-9,"aspect-aware calibration gives correct rectangular cell area")
    app.work.save("artifacts/p1-embedded.firebreak"); remove("artifacts/p1-source.png")
    app.loadProject("artifacts/p1-embedded.firebreak")
    pass(app.reference.isSome() && reference.isClosed(),"embedded base map reload works after original image is deleted and releases old texture")
    let loadedText=app.work.project.text(); let loadedTexture=app.reference.getOrThrow()
    pass(rejected({=>app.loadProject("artifacts/p1-invalid.firebreak")}) && app.work.project.text()==loadedText && refEq(loadedTexture,app.reference.getOrThrow()),"application failed open preserves document and renderer reference")

    app.mapMode=true; app.settings=false; app.activate(21)
    let l=Layout(Float32(w.width),Float32(w.height)); let a=mapPoint(app,l,2,2); let b=mapPoint(app,l,4,3)
    let historyDepth=app.work.undo.size
    event(app,w,UiEvent.MouseDown(MouseButton.Left,a.x,a.y)); event(app,w,UiEvent.MouseMove(b.x,b.y)); event(app,w,UiEvent.MouseUp(MouseButton.Left,b.x,b.y))
    pass(app.selection().size==6 && app.work.project.count(app.work.project.land)==0,"drag previews six cells without changing baseline")
    pass(app.previewText().contains("120.00"),"preview reports calibrated rectangle area before commit")
    click(app,w,31)
    pass(app.work.undo.size==historyDepth+1 && app.work.project.count(app.work.project.land)==6 && app.startCell<0,"confirm submits drag as exactly one undo transaction")
    click(app,w,14); pass(app.work.project.count(app.work.project.land)==0,"undo button restores complete stroke")
    click(app,w,15); pass(app.work.project.count(app.work.project.land)==6,"redo button restores complete stroke")
    app.activate(26)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,a.x,a.y)); event(app,w,UiEvent.MouseMove(b.x,b.y)); event(app,w,UiEvent.MouseUp(MouseButton.Left,b.x,b.y))
    event(app,w,UiEvent.KeyDown(Key.Escape,false))
    pass(app.startCell<0 && app.work.project.count(app.work.project.treatment)==0,"Escape cancels preview without modifying plan")
    app.activate(33); app.draft="180"; event(app,w,UiEvent.KeyDown(Key.Enter,false))
    pass(app.work.project.metersWide==180.0 && app.activeField<0,"numeric calibration field commits through keyboard")
    app.activate(34); app.draft="invalid"; let oldBudget=app.work.project.budget
    event(app,w,UiEvent.KeyDown(Key.Enter,false))
    pass(app.work.project.budget==oldBudget && app.activeField==34,"invalid numeric input retains previous budget and editable draft")
    event(app,w,UiEvent.KeyDown(Key.Escape,false))
    for (size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]) {
        let layout=Layout(size.w,size.h)
        for (settings in [false,true]) { for (id in CONTROLS) {
            if (!layout.available(id,settings)) { continue }
            let box=layout.control(id)
            require(box.w>=44.0 && box.h>=44.0 && box.right()<=size.w && box.bottom()<=size.h,"P1 control outside window")
            require(layout.hit(box.centerX(),box.centerY(),settings:settings)==id,"P1 visible controls overlap")
        } }
    }
    pass(true,"both sidebar modes have distinct reachable control targets at minimum, normal and fullscreen sizes")
    app.settings=true; app.focus=0
    for (_ in 0..CONTROLS.size) { event(app,w,UiEvent.KeyDown(Key.Tab,false)); require(l.available(CONTROLS[app.focus],true),"Tab focused hidden field") }
    pass(true,"keyboard focus skips hidden controls in settings mode")
    app.settings=false; app.tool=0; app.mapMode=true
    app.message="底图保持原始宽高比；颜色为人工标注，实际尺度来自宽度校准。"
    render(app,w,capture:"artifacts/p1-map.png")
    app.work.acceptLoaded(Project(),""); app.refreshReference(); app.syncScene(); app.camera.reset(); app.mapMode=false
    app.erase=false; app.cancel(); app.tool=0; app.settings=false; app.view.showCanopy=true
    app.message="P1：场地与方案独立；青色保护 / 红色禁区。拖动后 Enter 应用。"
    render(app,w,capture:"artifacts/p1-workbench.png")
    pass(app.reference.isNone() && loadedTexture.isClosed(),"reference replacement releases final image texture")
    // Same-size document invalidation must cancel a pending frame, just like camera changes.
    app.view.dirty=true; app.view.prepare(app.camera,l.canvas,w,interacting:true); app.view.lastChange=0
    app.view.prepare(app.camera,l.canvas,w); let pending=app.view.pending.getOrThrow()
    app.work.apply([0],5,false); app.syncScene(); app.view.prepare(app.camera,l.canvas,w,interacting:true)
    pass(pending.isClosed() && app.view.pending.isNone(),"committed scene edit cancels stale progressive render")
    app.work.apply([3*24+3],6,false); app.syncScene()
    var clear=true
    for (y in app.scene.heights[3*24+3]..app.scene.ny) { if (app.scene.get(3,y,3)!=0) { clear=false } }
    pass(clear && app.work.project.land[3*24+3]==1,"planned strip removes displayed trunk and overhanging canopy without changing baseline")
    app.font.availablePages[1]=false
    pass(app.font.glyph(256)==63 && app.font.glyph(0x1f600)==63,"unavailable font pages and supplementary characters use safe fallback")
    app.work.acceptLoaded(Project(),""); app.syncScene(); app.cancel(); app.focus=0; app.tool=0
    pass(!app.handle(w,UiEventRecord(UiEvent.Quit)),"clean document quit terminates event loop without discard prompt")
    app.exitReady=false // Continue using the test app after asserting the quit outcome.
    println("P1 logic/resource/position checks completed; visual quality and native dialog interaction await user review.")
}

