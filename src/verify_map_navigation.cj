package firebreak

import sdl.*
import std.math.abs
import std.fs.remove

func verifyMapNavigation(app: App,w: SdlWindow): Unit {
    app.work.acceptLoaded(Project(),"");app.refreshReference();app.syncScene();app.cancel()
    app.mapMode=true;app.referenceMode=false;app.comparePanel=false;app.suggestPanel=false;app.menuOpen=false
    app.camera.resetMap();let l=Layout(Float32(w.width),Float32(w.height));let b=app.mapBox(l);let paper=app.mapPaperBox(l)
    let before=app.work.project.text();let revision=app.work.revision
    let yaw=app.camera.yaw;let pitch=app.camera.pitch;let zoom=app.camera.zoom;let panX=app.camera.panX;let panY=app.camera.panY
    let x=b.x+b.w*0.57;let y=b.y+b.h*0.43;let cell=app.cellAt(x,y,l)
    let u=app.camera.mapU(Float64((x-b.x)/b.w));let v=app.camera.mapV(Float64((y-b.y)/b.h))
    event(app,w,UiEvent.MouseWheel(0.0,4.0,x,y))
    pass(app.camera.mapZoom>1.0 && abs(app.camera.mapU(Float64((x-b.x)/b.w))-u)<1e-9 && abs(app.camera.mapV(Float64((y-b.y)/b.h))-v)<1e-9 && app.cellAt(x,y,l)==cell,
        "2D wheel zoom anchors the same world position and picked cell under the pointer")
    let after=app.mapPaperBox(l)
    pass(after.x==paper.x && after.y==paper.y && after.w==paper.w && after.h==paper.h && app.mapWorldBox(l).w>b.w,
        "2D zoom enlarges map content while keeping viewport and parchment frame fixed")
    let centerU=app.camera.mapU(0.5);let centerV=app.camera.mapV(0.5)
    event(app,w,UiEvent.MouseDown(MouseButton.Middle,b.centerX(),b.centerY()))
    event(app,w,UiEvent.MouseMove(b.centerX()+20.0,b.centerY()+14.0))
    event(app,w,UiEvent.MouseUp(MouseButton.Middle,b.centerX()+20.0,b.centerY()+14.0))
    pass(!app.panning && abs(app.camera.mapU(Float64((b.centerX()+20.0-b.x)/b.w))-centerU)<1e-6 && abs(app.camera.mapV(Float64((b.centerY()+14.0-b.y)/b.h))-centerV)<1e-6,
        "2D middle drag follows the pointer and releases without changing the 3D pan")
    let currentZoom=app.camera.mapZoom
    event(app,w,UiEvent.MouseWheel(0.0,4.0,paper.x+8.0,paper.centerY()))
    event(app,w,UiEvent.MouseDown(MouseButton.Middle,paper.x+8.0,paper.centerY()))
    pass(app.camera.mapZoom==currentZoom && !app.panning && app.cellAt(paper.x+8.0,paper.centerY(),l)<0,"Paper margin cannot zoom, pan or select terrain")
    var checked: Int64=0
    for(aspect in [0.6,1.2,2.0]){
        app.work.project.aspect=aspect
        for(z in 0..GRID_Z){for(xCell in 0..GRID_X){
            let p=mapPoint(app,l,xCell,z)
            if(app.mapBox(l).contains(p.x,p.y)){require(app.cellAt(p.x,p.y,l)==z*GRID_X+xCell,"Zoomed map picking lost alignment");checked++}
        }}
    }
    app.work.project.aspect=1.2
    pass(checked>300,"Zoomed/panned overlay cell centers round-trip through ground picking for three aspect ratios")
    app.startCell=0;app.endCell=0
    event(app,w,UiEvent.MouseWheel(0.0,4.0,b.centerX(),b.centerY()))
    pass(app.camera.mapZoom==currentZoom,"Pending edit selection blocks map zoom until apply or cancel")
    app.cancel();app.menuOpen=true;app.menuPage=0
    event(app,w,UiEvent.MouseWheel(0.0,4.0,b.centerX(),b.centerY()))
    pass(app.camera.mapZoom==currentZoom,"Modal menu blocks map navigation")
    app.menuOpen=false
    pass(app.work.project.text()==before && app.work.revision==revision && app.camera.yaw==yaw && app.camera.pitch==pitch && app.camera.zoom==zoom && app.camera.panX==panX && app.camera.panY==panY,
        "2D navigation leaves planning, evaluation revision and oblique camera unchanged")
    app.activate(5);pass(app.camera.mapZoom>currentZoom,"Sidebar plus button zooms the actual 2D map")
    app.activate(0);pass(app.camera.mapZoom==1.0 && app.camera.mapCenterU==0.5 && app.camera.mapCenterV==0.5,"Contextual reset restores the entire 2D map")
    for(_ in 0..60){app.camera.scaleMap(4.0,0.5,0.5)}
    require(app.camera.mapZoom==16.0,"Map zoom upper bound changed")
    app.camera.panMap(1e9,-1e9,Float64(b.w),Float64(b.h))
    let edge=0.5/app.camera.mapZoom
    require(app.camera.mapCenterU==edge && app.camera.mapCenterV==1.0-edge,"Map panning escaped world extent")
    for(_ in 0..60){app.camera.scaleMap(-4.0,0.5,0.5)}
    pass(app.camera.mapZoom==1.0 && app.camera.mapCenterU==0.5 && app.camera.mapCenterV==0.5,"Map zoom and panning are bounded from whole-map fit to 16x without blank margins")
    verifyMapRaster(app,w)
    app.camera.scaleMap(4.0,0.5,0.5);app.camera.scaleMap(4.0,0.5,0.5)
    app.preferences.gpuEnabled=true;render(app,w,capture:"artifacts/map-navigation.png")
    verifyMapReference(app,w);verifyMapComparison(app,w)
    app.preferences.gpuEnabled=false;app.view.useGpu=false;app.camera.resetMap();app.mapMode=false;app.cancel();app.view.dirty=true
}
func verifyMapReference(app: App,w: SdlWindow): Unit {
    let path="artifacts/map-navigation-source.bmp"
    try(s=Surface.create(64,64)){s.writeRgbaRows(0,64,{x,y=>Color.rgb(x*3,y*3,70)});s.saveBmp(path)}
    try{app.importImage(path)}finally{remove(path)}
    pass(app.referenceMode && app.camera.mapZoom==1.0,"Importing a new reference resets map navigation without depending on the source file afterward")
    let l=Layout(Float32(w.width),Float32(w.height));let b=app.mapBox(l)
    event(app,w,UiEvent.MouseWheel(0.0,4.0,b.centerX(),b.centerY()));event(app,w,UiEvent.MouseWheel(0.0,4.0,b.centerX(),b.centerY()))
    app.activate(21);let before=app.work.project.text()
    let a=mapPoint(app,l,11,9);let end=mapPoint(app,l,12,10)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,a.x,a.y));event(app,w,UiEvent.MouseMove(end.x,end.y));event(app,w,UiEvent.MouseUp(MouseButton.Left,end.x,end.y))
    pass(app.selection()==[227,228,251,252] && app.work.project.text()==before,"Zoomed reference drag selects the intended four cells without editing during preview")
    event(app,w,UiEvent.KeyDown(Key.Enter,false))
    for(i in [227,228,251,252]){require(app.work.project.land[i]==1,"Zoomed reference edit hit another cell")}
    app.work.history(true);app.syncScene()
    pass(app.work.project.text()==before && app.camera.mapZoom>2.0,"Reference edit commits and undoes one stroke without resetting map zoom")
    render(app,w,capture:"artifacts/map-reference-navigation.png")
    app.work.acceptLoaded(Project(),"");app.refreshReference();app.syncScene();app.settings=false;app.referenceMode=false;app.tool=0;app.camera.resetMap();app.cancel()
}
func verifyMapComparison(app: App,w: SdlWindow): Unit {
    let p=Project();p.ignition=75;p.treatment[300]=2
    let result=evaluated(p,makeScenarios(p,4));let pair=ComparisonView(result,app.assets)
    app.work.acceptLoaded(p,"");app.syncScene();app.work.revision=result.revision
    app.evalResult=Some(result);app.pairView=Some(pair);app.comparePanel=true;app.mapMode=true
    let l=Layout(Float32(w.width),Float32(w.height));let left=fittedMap(compareBox(l.canvas,false),pair.aspect)
    event(app,w,UiEvent.MouseWheel(0.0,4.0,left.centerX(),left.centerY()))
    event(app,w,UiEvent.MouseDown(MouseButton.Middle,left.centerX(),left.centerY()))
    event(app,w,UiEvent.MouseMove(left.centerX()+14.0,left.centerY()-8.0));event(app,w,UiEvent.MouseUp(MouseButton.Middle,left.centerX()+14.0,left.centerY()-8.0))
    render(app,w,capture:"artifacts/map-comparison-navigation.png")
    pass(pair.baseline.gpuActive && pair.planned.gpuActive && pair.baseline.lastMapZoom==app.camera.mapZoom && pair.planned.lastMapU==app.camera.mapCenterU &&
        pair.baseline.gpu.getOrThrow().engine.readback()!=pair.planned.gpu.getOrThrow().engine.readback(),"Paired GPU maps share zoom/pan while retaining independent baseline and treatment images")
    let zoom=app.camera.mapZoom;let gap=compareBox(l.canvas,false).right()+8.0
    event(app,w,UiEvent.MouseWheel(0.0,4.0,gap,left.centerY()))
    pass(app.camera.mapZoom==zoom,"Comparison gap and paper margins cannot navigate either map")
    app.clearComparison();app.comparePanel=false;app.camera.resetMap();app.work.acceptLoaded(Project(),"");app.refreshReference();app.syncScene()
}
func verifyMapRaster(app: App,w: SdlWindow): Unit {
    let scene=Scene(nx:32,nz:32,demo:false)
    for(z in 0..32){for(x in 0..32){scene.heights[z*32+x]=1;scene.set(x,0,z,if((x/4+z/4)%3==0){9}else if((x/4+z/4)%3==1){7}else{1})}}
    let camera=Camera();camera.mapZoom=4.0;camera.mapCenterU=0.5625;camera.mapCenterV=0.4375
    let b=Rect(0.0,0.0,128.0,128.0)
    try(view=VoxelView(scene,app.assets)){
        view.useGpu=true;var previous=Array<UInt8>()
        for(state in 0..2){
            if(state==1){camera.mapCenterU+=0.0625}
            view.prepare(camera,b,w,topDown:true,forceFull:true)
            require(view.gpuActive && view.nativeReady(),"Map GPU raster silently fell back")
            let bytes=view.gpu.getOrThrow().engine.readback()
            try(cpu=Surface.create(128,128)){
                view.rows(cpu,camera,b,128,128,0,128,parallel:false)
                for(y in 0..128){for(x in 0..128){let c=cpu.readPixel(Int32(x),Int32(y));let i=(y*128+x)*4
                    require(abs(Int64(c.r)-Int64(bytes[i]))<=1 && abs(Int64(c.g)-Int64(bytes[i+1]))<=1 && abs(Int64(c.b)-Int64(bytes[i+2]))<=1,"GPU and CPU map transform disagree")
                }}
            }
            if(state==1){require(bytes!=previous,"Panning did not change the GPU map")};previous=bytes
        }
        pass(view.targetWidth==128 && view.targetHeight==128 && view.gpu.getOrThrow().engine.uploads==4,
            "32768 zoomed/panned GPU pixels match CPU; map changes invalidate frame while reusing geometry and native-sized targets")
    }
}
