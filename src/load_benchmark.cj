package firebreak

import sdl.*
import std.collection.ArrayList
import std.fs.File

// Offline native workload: no saved settings/key, network request or user project.
// Replays are deliberately accelerated; this is a stress test, not normal playback FPS.
class LoadBenchmark {
    let clock=PerformanceClock()
    let fireFrames=ArrayList<Int64>()
    let growthFrames=ArrayList<Int64>()
    let rows=ArrayList<String>(["case,block,shader,window_w,window_h,frames,cold_frame_ms,update_median_ms,update_p95_ms,render_median_ms,render_p95_ms,work_median_ms,work_p95_ms,work_p99_ms,work_max_ms,frames_over_33ms,frames_over_100ms,loop_fps,gpu_sum_median_ms,gpu_sum_p95_ms,uploads,dispatches,working_mib,commit_mib,peak_working_mib,vsync,adapter,long_fire_frames,long_growth_frames"])
    let raw=ArrayList<String>(["case,block,frame,update_ms,render_ms,work_ms,loop_ms"])
    let memory=ArrayList<String>(["stage,working_mib,commit_mib,peak_working_mib"])
    func save():Unit {
        File.writeTo("artifacts/load-benchmark.csv",(String.join(rows.toArray(),delimiter:"\n")+"\n").toArray())
        File.writeTo("artifacts/load-frames.csv",(String.join(raw.toArray(),delimiter:"\n")+"\n").toArray())
        File.writeTo("artifacts/load-memory.csv",(String.join(memory.toArray(),delimiter:"\n")+"\n").toArray())
    }
    func mark(stage:String):Unit {let m=ProcessMemory();memory.add(stage+",${m.workingMiB},${m.commitMiB},${m.peakWorkingMiB}");save()}
    func views(app:App,mode:Int64):Array<VoxelView> {
        if(mode==2){return app.longReplay.getOrThrow().views}
        if(mode==1 || mode==3){let p=app.pairView.getOrThrow();return [p.baseline,p.planned]}
        return [app.view]
    }
    func update(app:App,mode:Int64,i:Int64):Unit {
        app.clockNow=UInt64(i*40)
        let angle=0.55+Float64(i%72)*0.004
        if(mode==2){
            let replay=app.longReplay.getOrThrow()
            // One checkpoint rebuild every 12 frames exposes geometry-upload spikes.
            if(i%12==0){let candidates=if((i/12)%2==0){growthFrames}else{fireFrames};replay.seek(candidates[(i/24)%candidates.size],app.clockNow)}
            replay.camera.yaw=angle;for(view in replay.views){view.dirty=true}
        }else if(mode==0){
            let run=app.experiment.run.getOrThrow();run.seek(1+i%max(1,run.snapshots.size-2));app.refreshExperimentView();app.camera.yaw=angle
        }else{
            let pair=app.pairView.getOrThrow();pair.seek(1+i%max(1,pair.maxStep-1));app.camera.yaw=angle
        }
        if(mode==3){
            let t=app.terminal
            // Explicitly synthetic LOCAL text delivery, never a claimed live model test.
            t.streamText="[local synthetic stream / no API] "+String.join(Array<String>(1+i%40,repeat:"森林实验结果流式文字与图卡组合负载。"),delimiter:"");t.revision++
            // Alternate output regions so both actual cards and text are exercised.
            t.scroll=if(i%24<12){0}else{18}
        }
    }
    func measure(app:App,w:SdlWindow,mode:Int64):Unit {
        let names=["single-fire","paired-fire","growth-lightning","paired-terminal-cards"]
        let name=names[mode];let targets=views(app,mode)
        for(block in 0..4){
            let enabled=block==1 || block==2;app.preferences.shadersEnabled=enabled
            let updates=ArrayList<Float64>();let renders=ArrayList<Float64>();let work=ArrayList<Float64>();var wall:Float64=0.0;var cold:Float64=0.0
            var uploads:Int64=0;var dispatches:Int64=0;var seenFire:Int64=0;var seenGrowth:Int64=0
            for(i in 0..80){
                checkBenchmarkEvents(w)
                let began=clock.ms();if(i==8){wall=began;for(v in targets){let e=v.gpu.getOrThrow().engine;uploads+=e.uploads;dispatches+=e.dispatches}}
                update(app,mode,i);let updated=clock.ms();render(app,w);let end=clock.ms()
                for(v in targets){require(v.gpuActive,"Load benchmark fell back to CPU: "+v.gpuError)}
                if(i==0){cold=end-began}
                w.delay(12)
                if(i>=8 && mode==2){let f=app.longReplay.getOrThrow().frame();if(!f.burned[0].isEmpty() || !f.burned[1].isEmpty()){seenFire++};if(f.rows[0].grown>0 || f.rows[1].grown>0){seenGrowth++}}
                if(i>=8){updates.add(updated-began);renders.add(end-updated);work.add(end-began);raw.add(name+"-${w.width},${block},${i-8},${updated-began},${end-updated},${end-began},"+numberText(clock.ms()-began))}
            }
            if(mode==2){require(seenFire>0 && seenGrowth>0,"Measured long replay omitted fire or growth")}
            let fps=72000.0/(clock.ms()-wall);var u:Int64=0;var d:Int64=0
            for(v in targets){let e=v.gpu.getOrThrow().engine;u+=e.uploads;d+=e.dispatches}
            let gpu=ArrayList<Float64>()
            for(v in targets){v.gpu.getOrThrow().engine.profile=true}
            try{
                for(i in 0..10){checkBenchmarkEvents(w);update(app,mode,84+i);render(app,w);var ms:Float64=0.0;for(v in targets){ms+=v.gpu.getOrThrow().engine.lastGpuMs};if(i>=2){gpu.add(ms)}}
            }finally{for(v in targets){v.gpu.getOrThrow().engine.profile=false}}
            let a=FrameStats(updates.toArray());let b=FrameStats(renders.toArray());let c=FrameStats(work.toArray());let g=FrameStats(gpu.toArray())
            var slow:Int64=0;var stall:Int64=0;for(v in work){if(v>33.333){slow++};if(v>100.0){stall++}}
            // 72 samples: nearest-rank p99 is the maximum; publish both explicitly.
            let m=ProcessMemory();let adapter=targets[0].gpu.getOrThrow().engine.adapterName
            rows.add(name+",${block},${enabled},${w.width},${w.height},72,${cold},${a.median},${a.p95},${b.median},${b.p95},${c.median},${c.p95},${c.maximum},${c.maximum},${slow},${stall},${fps},${g.median},${g.p95},${u-uploads},${d-dispatches},${m.workingMiB},${m.commitMiB},${m.peakWorkingMiB},${w.renderer.vsync()},"+adapter+",${seenFire},${seenGrowth}")
            save();println("${name} ${w.width} block ${block} shader=${enabled}: loop ${money(fps)} FPS; work ${money(c.median)}/${money(c.p95)}/${money(c.maximum)} ms; GPU ${money(g.median)} ms; commit ${money(m.commitMiB)} MiB")
            if(block==1){render(app,w,capture:"artifacts/load-${name}-${w.width}.png")}
        }
    }
    func run(w:SdlWindow,assets:Assets):Unit {
        save();mark("before-fixtures")
        let p=densityForest(Project(nx:128,nz:128),1.0,42);p.ignition=64*128+64;p.spreadProbability=1.0;p.burnSteps=3
        for(z in 0..128){p.treatment[z*128+96]=2}
        let eval=EvaluationJob(p,1,makeScenarios(p,1));eval.execute();let paired=eval.progress().result.getOrThrow()
        let pipeline=PipelineJob(1,p,1,PipelineSpec("current",8,16,-1,2,LongSpec(0.02,0.25,0,256,1,64)));pipeline.execute();let actual=pipeline.progress().result.getOrThrow()
        for(i in 0..actual.longRun.frames.size){let f=actual.longRun.frames[i];if(!f.burned[0].isEmpty() || !f.burned[1].isEmpty()){fireFrames.add(i)};if(f.rows[0].grown>0 || f.rows[1].grown>0){growthFrames.add(i)}}
        require(!fireFrames.isEmpty() && !growthFrames.isEmpty(),"Long fixture needs both fire and regrowth checkpoints")
        mark("fixtures-ready")
        for(size in [Size(1280.0,860.0),Size(2560.0,1380.0)]){
            w.setSize(Int32(size.w),Int32(size.h));w.refreshSize()
            let app=App(assets,preferencesPath:"",audioEnabled:false)
            try{
                app.work.acceptLoaded(p,"");require(app.work.revision==actual.revision,"Benchmark fixture revision mismatch");app.syncScene();app.preferences.gpuEnabled=true;app.preferences.showFps=true;app.mapMode=false
                app.camera.fitScene(app.scene,Layout(Float32(w.width),Float32(w.height)).canvas)
                let fire=app.experiment.create(p);for(_ in 0..140){fire.advance()};app.simPanel=true
                measure(app,w,0)
                app.experiment.run=None;app.simPanel=false;app.comparePanel=true;app.evalResult=Some(paired);app.pairView=Some(ComparisonView(paired,assets));measure(app,w,1)
                app.comparePanel=false;app.longPanel=true;app.longTopDown=false;app.longResult=Some(actual.longRun);app.longReplay=Some(LongReplay(actual.longRun,assets));setLongSpec(app,actual.longRun.spec);let replay=app.longReplay.getOrThrow();replay.camera.fitScene(replay.scenes[0],longSceneBox(Layout(Float32(w.width),Float32(w.height)),0,1.0,false));measure(app,w,2)
                app.longPanel=false;app.comparePanel=true;publishPipelineCards(app,actual);app.terminal.open=true;measure(app,w,3)
                // UI contract: opening the terminal blocks automatic long replay advancement.
                app.longPanel=true;let paused=app.longReplay.getOrThrow();let cursor=paused.cursor;paused.play(0);pollLong(app,10000);require(paused.cursor==cursor,"Terminal overlay did not pause long replay")
            }finally{app.close()}
            mark("closed-${w.width}")
        }
        // Repeated real native view/card allocation and release; report allocator retention,
        // not an invented leak/no-leak threshold or process working-set-only claim.
        for(cycle in 0..4){
            let app=App(assets,preferencesPath:"",audioEnabled:false)
            try{
                app.work.acceptLoaded(p,"");require(app.work.revision==actual.revision,"Benchmark fixture revision mismatch");app.syncScene();app.preferences.gpuEnabled=true;app.preferences.shadersEnabled=true
                app.comparePanel=true;app.evalResult=Some(paired);app.pairView=Some(ComparisonView(paired,assets));publishPipelineCards(app,actual);app.terminal.open=true
                render(app,w);for(v in views(app,1)){require(v.gpuActive,"Allocation-cycle GPU fallback")};mark("cycle-${cycle}-open")
            }finally{app.close()}
            w.delay(50);mark("cycle-${cycle}-closed")
        }
        println("PASS 128x128 offline native load matrix and four allocation/close cycles completed; no saved API settings loaded.")
        println("Frame CSV excludes screenshot/profiling work; loop FPS includes 12ms pacing. GPU timestamps cover compute only, not full UI/present; process memory excludes dedicated GPU VRAM.")
    }
}
