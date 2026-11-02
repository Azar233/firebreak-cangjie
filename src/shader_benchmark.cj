package firebreak

import sdl.*
import std.collection.ArrayList
import std.fs.File

// ABBA order reduces GPU clock/thermal drift; timestamp sampling is separate
// from the ordinary render/present/delay loop so its blocking queries do not
// artificially lower the measured application FPS.
class ShaderBenchmark {
    let clock=PerformanceClock()
    let rows=ArrayList<String>(["case,block,shader,grid,trees,projection,window_w,window_h,render_w,render_h,frames,loop_fps,render_median_ms,render_p95_ms,gpu_median_ms,gpu_p95_ms,uploads,adapter"])
    func measure(w: SdlWindow,assets: Assets,view: VoxelView,camera: Camera,name: String,top: Bool,app!:?App=None): Unit {
        let font=PixelFont(assets);let meter=FrameMeter();let b=stressBox(w,view.scene,top);let baseYaw=camera.yaw
        view.useGpu=true
        for(block in 0..4){
            let enabled=block==1 || block==2;view.shadersEnabled=enabled
            if(let Some(a)<-app){a.preferences.gpuEnabled=true;a.preferences.shadersEnabled=enabled}
            let samples=ArrayList<Float64>();var wall=0.0
            for(i in 0..64){
                checkBenchmarkEvents(w);camera.yaw=baseYaw+Float64(i)*0.008;view.dirty=true
                if(let Some(a)<-app){
                    if(let Some(run)<-a.experiment.run){run.seek(1+i%max(1,run.snapshots.size-1));a.refreshExperimentView();a.clockNow=UInt64(i*80)}
                }
                let start=clock.ms();if(i==16){wall=start}
                if(let Some(a)<-app){render(a,w)}else{view.prepare(camera,b,w,topDown:top);stressFrame(w,view,font,top,"Shader A/B",meter)}
                require(view.gpuActive,"Shader benchmark fell back to CPU: "+view.gpuError)
                if(i>=16){samples.add(clock.ms()-start)};w.delay(12)
            }
            let fps=48000.0/(clock.ms()-wall);let stats=FrameStats(samples.toArray());let engine=view.gpu.getOrThrow().engine
            let uploads=engine.uploads;let timings=ArrayList<Float64>();engine.profile=true
            try{
                for(i in 0..12){checkBenchmarkEvents(w);camera.yaw=baseYaw+Float64(i)*0.008;view.dirty=true;view.prepare(camera,b,w,topDown:top);if(i>=4){timings.add(engine.lastGpuMs)}}
            }finally{engine.profile=false}
            let gpu=FrameStats(timings.toArray())
            require(engine.uploads==uploads,"Lighting/camera-only measurements reuploaded geometry")
            rows.add(name+",${block},"+(if(enabled){"on"}else{"off"})+",${view.scene.nx},${view.scene.trees},"+(if(top){"top"}else{"3d"})+
                ",${w.width},${w.height},${view.targetWidth},${view.targetHeight},48,"+numberText(fps)+","+numberText(stats.median)+","+numberText(stats.p95)+","+numberText(gpu.median)+","+numberText(gpu.p95)+",${engine.uploads},"+engine.adapterName)
            File.writeTo("artifacts/shader-benchmark.csv",(String.join(rows.toArray(),delimiter:"\n")+"\n").toArray())
            println("${name} block ${block} FX ${enabled}: ${money(fps)} FPS; GPU ${money(gpu.median)} ms / p95 ${money(gpu.p95)}; "+engine.adapterName)
            if(block<2){
                camera.yaw=baseYaw;view.dirty=true
                let path="artifacts/shader-"+name+"-"+(if(enabled){"on"}else{"off"})+".png"
                if(let Some(a)<-app){if(let Some(run)<-a.experiment.run){run.seek(2);a.refreshExperimentView();a.clockNow=160};render(a,w,capture:path)}
                else{view.prepare(camera,b,w,topDown:top);stressFrame(w,view,font,top,"Shader A/B",meter,capture:path)}
            }
        }
        camera.yaw=baseYaw
    }
    func run(w: SdlWindow,assets: Assets): Unit {
        File.writeTo("artifacts/shader-benchmark.csv",(rows[0]+"\n").toArray())
        let app=App(assets)
        try{
            for(size in [Size(1280.0,860.0),Size(2560.0,1380.0)]){
                w.setSize(Int32(size.w),Int32(size.h));w.refreshSize();app.camera.reset()
                measure(w,assets,app.view,app.camera,"workbench-${w.width}",false,app:Some(app))
                let p=Project();p.ignition=75;p.spreadProbability=1.0;p.burnSteps=3
                app.work.acceptLoaded(p,"");app.syncScene();app.experiment.planned=true
                let run=app.experiment.create(p);for(_ in 0..12){run.advance()};app.simPanel=true
                measure(w,assets,app.view,app.camera,"fire-${w.width}",false,app:Some(app))
                app.experiment.run=None;app.work.acceptLoaded(Project(),"");app.syncScene();app.simPanel=false
            }
        }finally{app.close()}
        println("Generating 1536 x 1536 forest, density 0.74, seed 42...")
        let example=ForestExample(ForestSpec(1536,0.74,42),clock)
        try(view=VoxelView(example.scene,assets)){
            let camera=Camera();camera.fitScene(example.scene,Layout(Float32(w.width),Float32(w.height)).canvas)
            measure(w,assets,view,camera,"forest-overview",false)
            camera.focusScene(example.scene);measure(w,assets,view,camera,"forest-local",false)
            camera.resetMap();measure(w,assets,view,camera,"forest-map",true)
        }
        w.setSize(1280,860);w.refreshSize()
    }
}
