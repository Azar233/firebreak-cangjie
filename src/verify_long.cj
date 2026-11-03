package firebreak

import sdl.*
import std.fs.{File,exists}
import std.collection.ArrayList
import stdx.encoding.json.*

func runLong(p:Project,s:LongSpec):LongResult {let job=LongJob(p,0,s);job.execute();let state=job.progress();require(state.error.isEmpty(),state.error);return state.result.getOrThrow()}
func waitLong(app:App,w:SdlWindow):Unit {
    let clock=PerformanceClock();let start=clock.ms()
    while(app.longJob.isSome() && clock.ms()-start<60000.0){pollLong(app,app.clockNow);w.delay(5)}
    require(app.longJob.isNone() && app.longResult.isSome(),"Long-run job did not complete")
}
func verifyLong(app:App,w:SdlWindow):Unit {
    let p=Project(nx:4,nz:4);let copy=p.copy();copy.vegetation[0]=0
    pass(p.vegetation[0]==1 && p.copy().text()==p.text(),"Direct project copies preserve serialization and own independent arrays")
    let invalid=p.copy();invalid.vegetation[0]=9;pass(rejected({=>invalid.copy()}),"Direct copy still rejects invalid source data")
    let fixed=runLong(p,LongSpec(0.0,0.0,0,4,1,0))
    pass(fixed.rows.size==8 && fixed.sum(0,0)==0 && fixed.meanDensity(0)==1.0,"Zero growth and lightning preserve initial forest without fabricated fires")
    let burn=runLong(p,LongSpec(0.0,1.0,0,4,2,16))
    pass(burn.sum(0,0)==32 && burn.maximum(0)==16 && burn.sum(0,5)==6 && burn.sum(1,0)==0 && burn.sum(1,3)==8 && burn.sum(1,4)==128,"Full forest burns once per natural seed while ideal suppression preserves it and records all effort and misses")
    let warm=runLong(p,LongSpec(0.0,1.0,1,4,1,16))
    pass(warm.rows[0].burned==16 && !warm.rows[0].measured && warm.sum(0,0)==0 && warm.maximum(0)==0 && warm.sum(0,5)==4,"Warmup fires remain in raw records but are excluded from every measured total")
    let empty=p.copy();for(i in 0..empty.cells){empty.vegetation[i]=0};empty.land[0]=3;empty.treatment[1]=2;empty.vegetation[1]=1
    let growing=runLong(empty,LongSpec(1.0,0.0,0,2,1,0))
    pass(growing.rows[0].grown==14 && growing.rows[2].grown==0 && growing.frames[2].states[0][0]==0 && growing.frames[2].states[0][1]==0,"Certain growth fills eligible empty sites once and never regrows water or fixed treatments")
    let forest=densityForest(Project(nx:32,nz:32),0.6,42);let spec=LongSpec(0.01,0.1,16,300,2,0)
    let result=runLong(forest,spec);let repeated=runLong(forest,spec)
    pass(longRowsCsv(result)==longRowsCsv(repeated) && result.pairedLargeSE()==0.0,"Long-run driving is reproducible and zero-capacity paired policies remain identical")
    for(sample in 0..spec.samples){let alive=[forest.count(forest.vegetation),forest.count(forest.vegetation)]
        for(global in 0..spec.warmup+spec.drives){let first=result.rows[(sample*(spec.warmup+spec.drives)+global)*2]
            for(policy in 0..2){let row=result.rows[(sample*(spec.warmup+spec.drives)+global)*2+policy]
                require(row.seed==studySeed(forest.seed,sample) && row.lightning==first.lightning && row.ignition==first.ignition && row.grown==first.grown && row.burned==first.burned && row.alive==alive[policy]+row.grown-row.burned,"Paired external inputs or forest conservation broken");alive[policy]=row.alive
            }
        }
    };pass(true,"Every raw drive shares seed/lightning including misses and conserves alive+grown-burned across policies")
    var last:Int64= -1;for(f in result.frames){require(f.drive>last,"Replay checkpoints are not ordered");last=f.drive}
    pass(result.frames[0].drive==0 && last==spec.drives && result.frames.size<=130,"Bounded checkpoints preserve warmup endpoint and exact final observed drive")
    pass(rejected({=>LongSpec(0.0,1.1,0,4,1,0)}) && rejected({=>LongSpec(0.0,0.0,0,8193,1,0)}),"Probability and resource bounds reject invalid long-run configurations")
    let cancelled=LongJob(p,0,spec);cancelled.cancel();cancelled.execute()
    pass(cancelled.progress().result.isNone() && cancelled.progress().cancelled,"Cancellation never publishes a partial long-run result")
    for(size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]){let l=Layout(size.w,size.h)
        for(id in LONG_CONTROLS){let b=l.control(id);require(b.w>=44.0 && b.h>=44.0 && b.right()<=size.w && b.bottom()<=size.h && l.hit(b.centerX(),b.centerY(),longMode:true)==id,"Long controls overlap or escape the window")}
        require(longArea(l,0).h>0.0 && longArea(l,1).right()<l.panel.x,"Replay panes escape the canvas")
    };pass(true,"Long-run controls and replay panes fit minimum, ordinary and fullscreen windows")
    app.menuOpen=false;app.terminal.open=false;app.cancel();app.work.acceptLoaded(forest,"");app.syncScene();enterWorkflow(app,1)
    app.startCell=0;app.endCell=1;click(app,w,160);pass(!app.longPanel && app.startCell==0,"Pending selections block opening the long-run experiment without discarding edits")
    app.cancel();click(app,w,160);app.longWarmup=16;app.longDrives=256;app.longSamples=2;app.longCapacity=64
    let source=app.work.project.text();let revision=app.work.revision;click(app,w,167);waitLong(app,w)
    pass(app.work.project.text()==source && app.work.revision==revision,"Background long-run controls leave the current project untouched")
    let replay=app.longReplay.getOrThrow();var strike:Int64=0
    for(i in 1..replay.result.frames.size){if(replay.result.frames[i].rows[0].lightning){strike=i;break}}
    app.preferences.gpuEnabled=true;app.clockNow=1000;replay.seek(strike,app.clockNow);render(app,w,capture:"artifacts/r4-long-run.png")
    pass(replay.views[0].gpuActive && replay.views[1].gpuActive && app.assets.image("textures/particle/flash.png").width>0.0,"Both replay policies render on native D3D11 and the original flash resource loads")
    click(app,w,16);render(app,w,capture:"artifacts/r4-lightning-3d.png");pass(!app.longTopDown && replay.views[0].gpuActive,"3D lightning overlay composes with the native voxel pipeline")
    click(app,w,170);app.openMenu();pass(!replay.playing,"Opening Esc menu pauses the checkpoint replay");app.closeMenu()
    app.longHistogram=true;app.preferences.setEnglish(true);w.setSize(1100,780);w.refreshSize();render(app,w,capture:"artifacts/r4-long-en-small.png")
    app.preferences.setEnglish(false);w.setSize(2560,1380);w.refreshSize();render(app,w,capture:"artifacts/r4-long-fullscreen.png");w.setSize(1280,860);w.refreshSize()
    let path=exportLong(app,"artifacts");let again=exportLong(app,"artifacts")
    let params=JsonValue.fromStr(String.fromUtf8(File.readFrom(path+"/parameters.json"))).asObject()
    let frames=JsonValue.fromStr(String.fromUtf8(File.readFrom(path+"/checkpoints.json"))).asArray()
    pass(path!=again && params["observedDrives"].asInt().getValue()==256 && frames.size()==replay.result.frames.size && exists(path+"/snapshot-1.png") && String.fromUtf8(File.readFrom(path+"/drives.csv"))==longRowsCsv(replay.result),"Atomic unique exports preserve all raw drives, exact parameters, sampled states and snapshot images")
    let snapshot=replay.snapshot(1);click(app,w,175)
    pass(!app.longPanel && app.work.project.text()==snapshot.text() && app.work.revision==revision+1,"Applying the selected checkpoint commits exactly one vegetation snapshot")
    click(app,w,14);pass(app.work.project.text()==source,"Undo restores the original forest after checkpoint application")
    app.longResult=Some(result);let stale=LongJob(app.work.project,app.work.revision,spec);app.longJob=Some(stale)
    let change=app.work.project.copy();change.seed++;app.work.commit(change);pollLong(app,app.clockNow);stale.execute()
    pass(app.longResult.isNone() && app.longReplay.isNone() && app.longJob.isNone() && stale.progress().cancelled,"Revision changes invalidate both published results and pending long-run jobs")
    let clock=PerformanceClock();let start=clock.ms();let big=runLong(densityForest(Project(nx:128,nz:128),0.6,42),LongSpec(0.01,0.1,128,512,4,64));let elapsed=clock.ms()-start
    let renderTimes=ArrayList<Float64>();let layout=Layout(1280.0,860.0)
    try(largeReplay=LongReplay(big,app.assets)){
        for(view in largeReplay.views){view.useGpu=true}
        for(index in 0..12){largeReplay.seek(index,UInt64(index*400));let frameStart=clock.ms()
            for(policy in 0..2){let view=largeReplay.views[policy];view.prepare(largeReplay.camera,longSceneBox(layout,policy,1.0,true),w,topDown:true,forceFull:true)}
            app.assets.r.beginScene(1280.0,860.0,Color.rgb(34,38,32));for(policy in 0..2){largeReplay.views[policy].draw(longSceneBox(layout,policy,1.0,true))};app.assets.r.endScene();app.assets.r.present();renderTimes.add(clock.ms()-frameStart)
        }
        pass(largeReplay.views[0].gpuActive && largeReplay.views[1].gpuActive,"128x128 checkpoint changes upload and render on both actual GPU policy views")
    }
    let stats=FrameStats(renderTimes.toArray())
    File.writeTo("artifacts/long-benchmark.csv",("grid,seeds,warmup,observed_drives,model_ms,checkpoints,rows,replay_render_median_ms,replay_render_p95_ms\n128x128,4,128,512,"+money(elapsed)+",${big.frames.size},${big.rows.size},${stats.median},${stats.p95}\n").toArray())
    pass(big.rows.size==5120 && big.frames.size<=130,"128x128 long-run simulation completes four independent seeds with bounded replay storage")
    app.work.acceptLoaded(Project(),"");app.refreshReference();app.syncScene();app.preferences.gpuEnabled=false;app.mapMode=false;app.longHistogram=false;app.longTopDown=true;app.cancel();enterWorkflow(app,0);app.camera.focusScene(app.scene);app.tool=0
}
