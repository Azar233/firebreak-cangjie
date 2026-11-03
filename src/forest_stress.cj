package firebreak

import sdl.*
import std.collection.ArrayList
import std.fs.{File,remove}

func stressBox(w: SdlWindow,scene: Scene,top: Bool): Rect {
    let canvas=Layout(Float32(w.width),Float32(w.height)).canvas
    return if (top) { fittedMap(canvas,Float64(scene.nx)/Float64(scene.nz)) } else { canvas }
}
func checkBenchmarkEvents(w: SdlWindow): Unit {
    while (let Some(e) <- w.pollEventRecord()) {
        match(e.event) { case UiEvent.Quit | UiEvent.WindowCloseRequested=>throw Exception("Forest benchmark cancelled by user; completed CSV rows are retained"); case _=>() }
    }
}
func stressFrame(w: SdlWindow,view: VoxelView,font: PixelFont,top: Bool,title: String,meter: FrameMeter,capture!:String=""): Unit {
    let l=Layout(Float32(w.width),Float32(w.height)); let b=stressBox(w,view.scene,top); let r=w.renderer
    meter.tick(meter.clock.ms())
    r.beginScene(l.width,l.height,Color.rgb(34,38,32));r.setScale(uiPixelRatio(w))
    frame(r,Rect(12.0,12.0,l.width-24.0,76.0)); font.draw("Firebreak / Forest Stress Lab",30.0,30.0)
    frame(r,l.canvas,dark:true); view.draw(b); frame(r,l.panel,dark:true)
    let x=l.panel.x+16.0; let y=l.panel.y+18.0
    font.draw(title,x,y,scale:0.85)
    font.draw("Grid ${view.scene.nx} x ${view.scene.nz}",x,y+36.0)
    font.draw("Trees ${view.scene.trees}",x,y+68.0)
    font.draw(if (top) { "Top-down voxel texture" } else { "3D voxel ray traversal" },x,y+104.0,scale:0.85)
    font.draw(view.backendName(),x,y+140.0,scale:0.75)
    font.draw("Viewport ${view.targetWidth} x ${view.targetHeight}",x,y+172.0,scale:0.85)
    font.draw("Submit/CPU ${view.lastRenderMs} ms",x,y+204.0,scale:0.75)
    font.draw("Tab: 2D / 3D",x,y+224.0)
    font.draw("C: Largest cluster",x,y+256.0)
    font.draw("Home: Overview / F: Local",x,y+288.0,scale:0.85)
    font.draw("Right drag: Rotate",x,y+320.0)
    font.draw("Middle drag: Pan",x,y+352.0)
    font.draw("Wheel: Zoom / Esc: Exit",x,y+384.0,scale:0.85)
    font.draw("L: MC lighting "+if(view.shadersEnabled){"On"}else{"Off"},x,y+416.0,scale:0.85)
    font.draw("Rendering diagnostic only / No fire evaluation / Not a .firebreak planning project",20.0,l.height-48.0,scale:0.85)
    drawFps(font,meter,l.canvas); r.endScene(); if (!capture.isEmpty()) { saveStressCapture(w,capture) }; r.present()
}
func saveStressCapture(w: SdlWindow,path: String): Unit {
    w.renderer.captureBmp(path+".bmp")
    try (surface=Surface.loadBmp(path+".bmp")) { surface.savePng(path) }; remove(path+".bmp")
}
func runForestLab(w: SdlWindow,assets: Assets,spec: ForestSpec): Unit {
    let clock=PerformanceClock(); let example=ForestExample(spec,clock); let font=PixelFont(assets); let meter=FrameMeter()
    println("Forest loaded: ${example.occupied} fuel cells / ${example.scene.trees} tree instances; field ${example.fieldMs} ms / voxels ${example.voxelMs} ms")
    try (view=VoxelView(example.scene,assets)) {
        view.useGpu=true
        let camera=Camera(); camera.focusScene(example.scene)
        var top=false; var dragging=false; var panning=false; var x0: Float32=0.0; var y0: Float32=0.0
        var running=true; var clusters=false; var labels=Array<Int64>(); var title="Density "+money(spec.density)
        while (running) {
            while (let Some(e) <- w.pollEventRecord()) {
                match(e.event) {
                    case UiEvent.Quit | UiEvent.WindowCloseRequested=>running=false
                    case UiEvent.WindowResized(_,_) | UiEvent.WindowDisplayScaleChanged=>
                        w.refreshSize()
                        if (w.width<1100 || w.height<780) { w.setSize(Int32(max(1100,w.width)),Int32(max(780,w.height))); w.refreshSize() }
                        view.dirty=true
                    case UiEvent.KeyDown(key,repeat)=>if (!repeat) { match(key) {
                        case Key.Escape=>running=false
                        case Key.Tab=>top = !top; view.dirty=true
                        case Key.Letter(76)=>view.shadersEnabled = !view.shadersEnabled;view.dirty=true
                        case Key.Home=>camera.resetMap();camera.fitScene(example.scene,Layout(Float32(w.width),Float32(w.height)).canvas); view.dirty=true
                        case Key.Letter(70)=>camera.focusScene(example.scene); top=false; view.dirty=true
                        case Key.Letter(67)=>
                            if (labels.isEmpty()) { labels=example.largestLabels(clock) }
                            clusters = !clusters
                            view.setClusters(if (clusters) { labels } else { Array<Int64>(spec.size*spec.size,repeat:-1) })
                            title="Largest ${example.largest} cells"; view.dirty=true
                        case _=>()
                    } }
                    case UiEvent.MouseDown(button,x,y)=>
                        x0=x; y0=y
                        let inside=Layout(Float32(w.width),Float32(w.height)).canvas.contains(x,y)
                        match(button) { case MouseButton.Right=>dragging=inside && !top; case MouseButton.Middle=>panning=if(top){stressBox(w,example.scene,true).contains(x,y)}else{inside}; case _=>() }
                    case UiEvent.MouseMove(x,y)=>
                        if (dragging) { camera.rotate(Float64(x-x0),Float64(y-y0)); view.dirty=true }
                        if (panning) { if(top){let b=stressBox(w,example.scene,true);camera.panMap(Float64(x-x0),Float64(y-y0),Float64(b.w),Float64(b.h))}else{camera.panX+=Float64(x-x0); camera.panY+=Float64(y-y0)};view.dirty=true }
                        x0=x; y0=y
                    case UiEvent.MouseUp(MouseButton.Right,_,_)=>dragging=false
                    case UiEvent.MouseUp(MouseButton.Middle,_,_)=>panning=false
                    case UiEvent.MouseWheel(_,dy,x,y)=>
                        if(top){let b=stressBox(w,example.scene,true);if(b.contains(x,y)){camera.scaleMap(Float64(dy),Float64((x-b.x)/b.w),Float64((y-b.y)/b.h));view.dirty=true}}
                        else if(Layout(Float32(w.width),Float32(w.height)).canvas.contains(x,y)){camera.scale(Float64(dy));view.dirty=true}
                    case UiEvent.WindowFocusLost=>dragging=false; panning=false
                    case _=>()
                }
            }
            if (!running) { break }
            view.prepare(camera,stressBox(w,example.scene,top),w,topDown:top,interacting:dragging || panning)
            stressFrame(w,view,font,top,title,meter); w.delay(12)
        }
    }
}
class RenderLoopResult {
    let fps: Float64
    let frames: FrameStats
    init(fps: Float64,frames: FrameStats) { this.fps=fps; this.frames=frames }
}
func measureStressLoop(w: SdlWindow,view: VoxelView,camera: Camera,font: PixelFont,top: Bool,changing: Bool,clock: PerformanceClock,panning!:Bool=false): RenderLoopResult {
    let samples=ArrayList<Float64>(); let meter=FrameMeter(); var wall=0.0
    for (i in 0..27) {
        checkBenchmarkEvents(w)
        if (changing) { if (!top) { if(panning){camera.panX+=2.0; camera.panY+=1.0}else{camera.rotate(2.0,0.0)} }; view.dirty=true }
        let start=clock.ms(); if (i==3) { wall=start }
        view.prepare(camera,stressBox(w,view.scene,top),w,topDown:top,interacting:changing)
        stressFrame(w,view,font,top,if (changing) { "BENCH / Refresh" } else { "BENCH / Cached" },meter)
        if (i>=3) { samples.add(clock.ms()-start) }; w.delay(12)
    }
    return RenderLoopResult(24000.0/(clock.ms()-wall),FrameStats(samples.toArray()))
}
class ForestBenchmark {
    let gpuMode: Bool
    init(gpu!:Bool=false){gpuMode=gpu}
    func outputPath(): String {if(gpuMode){"artifacts/gpu-benchmark.csv"}else{"artifacts/forest-benchmark.csv"}}
    let clock=PerformanceClock()
    let rows=ArrayList<String>(["case,grid_x,grid_z,forest_cells,tree_instances,projection,window_w,window_h,render_w,render_h,field_ms,voxel_ms,connectivity_ms,largest_cluster,raw_voxel_mib,raster_median_ms,settle_ms,cached_loop_fps,cached_render_median_ms,refresh_loop_fps,refresh_render_median_ms,refresh_render_p95_ms,working_set_mib,peak_working_mib,commit_mib,vsync,driver,pan_loop_fps,pan_render_median_ms,backend,completed_gpu_ms,uploads,dispatches,adapter"])
    func measure(w: SdlWindow,assets: Assets,scene: Scene,name: String,occupied: Int64,field: Float64,voxel: Float64,connectivity: Float64,largest: Int64,top: Bool,local!:Bool=false): Unit {
        checkBenchmarkEvents(w); let camera=Camera(); camera.fitScene(scene,Layout(Float32(w.width),Float32(w.height)).canvas)
        if(local){camera.focusScene(scene)}
        let font=PixelFont(assets); let b=stressBox(w,scene,top)
        try (view=VoxelView(scene,assets)) {
            view.useGpu=gpuMode
            let native=canvasResolution(b,Float64(w.scale)*Float64(w.currentPixelDensity)); let samples=ArrayList<Float64>()
            view.topDown=top
            try (surface=Surface.create(Int32(native.width),Int32(native.height))) {
                for (_ in 0..3) { let start=clock.ms(); view.rows(surface,camera,b,native.width,native.height,0,native.height); samples.add(clock.ms()-start) }
            }
            let start=clock.ms(); view.dirty=true; let meter=FrameMeter()
            for (_ in 0..native.height*4+1000) {
                checkBenchmarkEvents(w); view.prepare(camera,b,w,topDown:top)
                stressFrame(w,view,font,top,"BENCH / Refining",meter)
                if (view.nativeReady()) { break }; require(clock.ms()-start<30000.0,"Native refinement exceeded 30 seconds"); w.delay(12)
            }
            require(view.nativeReady(),"Native refinement did not finish"); let settle=clock.ms()-start
            var gpuMs: Float64= -1.0
            if(gpuMode){
                require(view.gpuActive,"GPU benchmark fell back to CPU: "+view.gpuError)
                let engine=view.gpu.getOrThrow().engine;engine.profile=true;let values=Array<Float64>(3,repeat:0.0)
                for(i in 0..3){view.dirty=true;view.prepare(camera,b,w,topDown:top);values[i]=engine.lastGpuMs}
                gpuMs=FrameStats(values).median;engine.profile=false
                println("GPU adapter: "+engine.adapterName+"; completed dispatch/copy ${money(gpuMs)}ms")
            }
            let cached=measureStressLoop(w,view,camera,font,top,false,clock)
            let changing=measureStressLoop(w,view,camera,font,top,true,clock)
            let pan=if(local){measureStressLoop(w,view,camera,font,top,true,clock,panning:true)}else{RenderLoopResult(0.0,FrameStats([0.0]))}
            if (scene.nx==1536 && !top && w.width==1280) { view.prepare(camera,b,w,topDown:false,forceFull:true); stressFrame(w,view,font,false,"1536 / Native frame",FrameMeter(),capture:if(gpuMode){if(local){"artifacts/gpu-forest-local.png"}else{"artifacts/gpu-forest-overview.png"}}else if(local){"artifacts/forest-local-3d.png"}else{"artifacts/forest-stress-3d.png"}) }
            let memory=ProcessMemory(); let raster=FrameStats(samples.toArray())
            rows.add(name+",${scene.nx},${scene.nz},${occupied},${scene.trees},"+(if (top) { "top_down" } else { "3d" })+
                ",${w.width},${w.height},${native.width},${native.height},"+numberText(field)+","+numberText(voxel)+","+numberText(connectivity)+",${largest},"+
                numberText(Float64(scene.blocks.size)/1048576.0)+","+numberText(raster.median)+","+numberText(settle)+","+
                numberText(cached.fps)+","+numberText(cached.frames.median)+","+numberText(changing.fps)+","+numberText(changing.frames.median)+","+numberText(changing.frames.p95)+","+
                numberText(memory.workingMiB)+","+numberText(memory.peakWorkingMiB)+","+numberText(memory.commitMiB)+",${w.renderer.vsync()},"+w.renderer.driverName()+","+numberText(pan.fps)+","+numberText(pan.frames.median)+","+view.backendName()+","+numberText(gpuMs)+","+gpuCounters(view))
            File.writeTo(outputPath(),(String.join(rows.toArray(),delimiter:"\n")+"\n").toArray())
            println("${name} ${scene.nx} ${top}: trees ${scene.trees}; raster ${money(raster.median)}ms; cached ${money(cached.fps)} FPS; refresh ${money(changing.fps)} FPS; WS ${money(memory.workingMiB)} MiB")
        }
    }
    func forestCase(w: SdlWindow,assets: Assets,size: Int64): Unit {
        println("Building forest ${size}...")
        let example=ForestExample(ForestSpec(size,0.74,42),clock)
        example.largestLabels(clock)
        println("Built ${example.occupied} fuel cells, ${example.scene.trees} tree instances; field ${money(example.fieldMs)}ms, voxels ${money(example.voxelMs)}ms, connectivity ${money(example.connectivityMs)}ms")
        for (top in [false,true]) { measure(w,assets,example.scene,"forest",example.occupied,example.fieldMs,example.voxelMs,example.connectivityMs,example.largest,top) }
        if (size==1536) {
            measure(w,assets,example.scene,"forest_local",example.occupied,example.fieldMs,example.voxelMs,example.connectivityMs,example.largest,false,local:true)
            w.setSize(2560,1380); w.refreshSize()
            for (top in [false,true]) { measure(w,assets,example.scene,"forest_fullscreen",example.occupied,example.fieldMs,example.voxelMs,example.connectivityMs,example.largest,top) }
            measure(w,assets,example.scene,"forest_local_fullscreen",example.occupied,example.fieldMs,example.voxelMs,example.connectivityMs,example.largest,false,local:true)
            w.setSize(1280,860); w.refreshSize()
        }
    }
    func run(w: SdlWindow,assets: Assets): Unit {
        File.writeTo(outputPath(),(rows[0]+"\n").toArray())
        measureWorkbench(w,assets,clock,gpu:gpuMode)
        let source=App(assets)
        try {
            var count: Int64=0; for (v in source.scene.canopyColumns) { if (v) { count++ } }
            for (top in [false,true]) { measure(w,assets,source.scene,"original_scene",count,0.0,0.0,0.0,0,top) }
        } finally { source.close() }
        for (size in [128,256,512,1024,1536]) { forestCase(w,assets,size) }
        captureConnectivity(w,assets,clock)
    }
}
func gpuCounters(view: VoxelView): String {
    if(let Some(g)<-view.gpu){return "${g.engine.uploads},${g.engine.dispatches},"+g.engine.adapterName}
    return "0,0,"
}
func measureWorkbench(w: SdlWindow,assets: Assets,clock: PerformanceClock,gpu!:Bool=false): Unit {
    let rows=ArrayList<String>(["window_w,window_h,mode,loop_fps,render_median_ms,render_p95_ms,vsync,driver"])
    let app=App(assets)
    app.preferences.gpuEnabled=gpu
    try {
        for (size in [Size(1280.0,860.0),Size(2560.0,1380.0)]) {
            w.setSize(Int32(size.w),Int32(size.h)); w.refreshSize(); app.camera.reset()
            app.view.prepare(app.camera,Layout(size.w,size.h).canvas,w,forceFull:true)
            for (mode in 0..3) {
                let changing=mode==1
                if (mode==2) {
                    let p=Project(); p.ignition=75; p.spreadProbability=1.0; p.burnSteps=3
                    app.work.acceptLoaded(p,""); app.syncScene(); app.experiment.planned=true
                    let run=app.experiment.create(p); for(_ in 0..12){run.advance()}; app.simPanel=true
                }
                let values=ArrayList<Float64>(); var wall=0.0
                for (i in 0..27) {
                    checkBenchmarkEvents(w)
                    if (changing) { app.camera.rotate(2.0,0.0); app.view.dirty=true }
                    let start=clock.ms(); if (i==3) { wall=start }
                    if(mode==2){let run=app.experiment.run.getOrThrow(); run.seek(1+i%max(1,run.snapshots.size-1)); app.refreshExperimentView(); app.clockNow=UInt64(i*80)}
                    render(app,w)
                    if (i>=3) { values.add(clock.ms()-start) }; w.delay(12)
                }
                let stats=FrameStats(values.toArray()); let fps=24000.0/(clock.ms()-wall)
                if(gpu){require(app.view.gpuActive,"Workbench GPU benchmark fell back: "+app.view.gpuError)}
                let name=if(mode==2){"fire_replay"}else if(changing){"camera_rotation"}else{"cached"}
                rows.add("${w.width},${w.height},"+name+","+numberText(fps)+","+numberText(stats.median)+","+numberText(stats.p95)+",${w.renderer.vsync()},"+w.renderer.driverName())
                File.writeTo(if(gpu){"artifacts/gpu-workbench.csv"}else{"artifacts/forest-workbench.csv"},(String.join(rows.toArray(),delimiter:"\n")+"\n").toArray())
                println("Workbench ${w.width} ${name}: ${money(fps)} FPS, render ${money(stats.median)}ms")
            }
            app.experiment.run=None; app.work.acceptLoaded(Project(),""); app.syncScene(); app.simPanel=false
        }
    } finally { app.close(); w.setSize(1280,860); w.refreshSize() }
}
func captureConnectivity(w: SdlWindow,assets: Assets,clock: PerformanceClock): Unit {
    let r=w.renderer; let font=PixelFont(assets); w.setSize(1280,860); w.refreshSize()
    let textures=ArrayList<Texture>()
    try {
        let labels=ArrayList<String>()
        for (density in [0.42,0.74]) {
            let start=clock.ms(); let field=forestField(ForestSpec(512,density,42)); let graph=Connectivity(field,512,512)
            var count: Int64=0; for (v in field) { if (v) { count++ } }
            try (surface=Surface.create(512,512)) {
                for (i in 0..field.size) {
                    surface.writePixel(Int32(i%512),Int32(i/512),if (!field[i]) { Color.rgb(12,19,16) }
                        else if (graph.labels[i]==graph.largestLabel) { Color.rgb(187,255,99) } else { Color.rgb(43,91,47) })
                }
                textures.add(r.textureFromSurface(surface))
            }
            labels.add("Fuel ${count} / Largest ${graph.largest}")
            println("Connectivity overview p=${density}: largest ${graph.largest}, occupied ${count}, ${money(clock.ms()-start)}ms")
        }
        r.beginScene(1280.0,860.0,Color.rgb(14,19,17))
        font.draw("Forest connectivity / same generator and seed / different occupation settings",30.0,28.0)
        for (i in 0..2) {
            let x=32.0+Float32(i)*624.0
            font.draw(if (i==0) { "Sparse / setting 0.42" } else { "Dense / setting 0.74" },x,100.0)
            r.textureStyled(textures[i],Rect(x,152.0,576.0,576.0),style:TextureStyle(sampling:TextureScaleMode.Nearest))
            font.draw(labels[i],x,752.0,scale:0.85)
        }
        font.draw("512 x 512 fuel cells per map / Bright: largest 4-neighbor component / Not wildfire policy results",30.0,812.0,scale:0.8)
        r.endScene(); saveStressCapture(w,"artifacts/forest-connectivity.png"); r.present()
    } finally { for (texture in textures) { texture.close() } }
}
