package firebreak

import sdl.*
import std.collection.ArrayList
import std.fs.File
import stdx.encoding.json.*

func verifyGrid(app:App,w:SdlWindow):Unit {
    let clock=PerformanceClock();let rows=ArrayList<String>(["nx,nz,load_ms,evaluation_ms,candidates_ms,gpu_frame_ms,fire_loop_fps,fire_render_median_ms,fire_render_p95_ms"])
    for(mask in 0..512){
        let fuel=Array<Bool>(9,{i=>(mask&(Int64(1)<<i))!=0});let graph=Connectivity(fuel,3,3)
        let gains=articulationGains(fuel,3,3,graph,{=>false})
        for(i in 0..9){if(fuel[i]){
            fuel[i]=false;let after=Connectivity(fuel,3,3);fuel[i]=true
            let expected=if(after.sizes.size>graph.sizes.size){graph.largest-after.largest}else{-1}
            require(gains[i]==expected,"Low-link candidate gain differs from brute-force removal")
        }}
    }
    pass(true,"All 512 three-by-three forests give exactly the same articulation gains as brute-force connectivity")
    pass(rejected({=>Project(nx:129,nz:64)}) && rejected({=>Project(nx:0,nz:64)}),"Invalid grid dimensions are rejected before allocation")
    let bad=JsonValue.fromStr(Project(nx:64,nz:64).text()).asObject();bad.put("vegetation",JsonString("1"))
    pass(rejected({=>readProjectText(bad.toJsonString())}),"Version 3 rejects vegetation masks that disagree with the grid dimensions")
    let bounded=FireRun(Array<Bool>(16384,repeat:true),128,128,0,1.0,1,42)
    for(_ in 1..512){bounded.snapshots.add(bounded.current())};bounded.cursor=bounded.snapshots.size-1
    pass(rejected({=>bounded.advance()}) && bounded.current().step==0,"Large replay history refuses another allocation at its memory bound without altering the snapshot")
    let legacy=readProjectText(String.fromUtf8(File.readFrom("examples/budget-camp.firebreak")))
    pass(legacy.nx==24 && legacy.nz==20 && legacy.count(legacy.targets)>0 && legacy.count(legacy.forbidden)>0 && readProjectText(legacy.text()).land==legacy.land,"Legacy v2 camps retain roads, buildings and constraints when migrated to v3")
    let rectangular=Project(nx:31,nz:17);pass(readProjectText(rectangular.text()).cells==527,"Rectangular project dimensions round-trip without global grid state")
    for(n in [64,128]){
        app.menuOpen=false;app.cancel();app.terminal.open=false;app.work.acceptLoaded(Project(),"");app.syncScene();enterWorkflow(app,0)
        click(app,w,116);pass(app.menuPage==11,"New Forest opens the grid-size chooser")
        let began=clock.ms();menuClick(app,w,if(n==64){121}else{122});let loaded=clock.ms()-began
        pass(app.work.project.nx==n && app.work.project.nz==n && app.scene.nx==n && app.view.fireAge.size==n*n,"Grid chooser replaces the project, renderer and dynamic column state together")
        let p=app.work.project;let roundTrip=readProjectText(p.text())
        pass(roundTrip.nx==n && roundTrip.vegetation==p.vegetation && roundTrip.cellArea()==25.0,"Large forest project preserves vegetation and calibrated cell area through serialization")
        app.work.apply([n*n-1],1,true);app.syncScene()
        pass(app.work.project.land[n*n-1]==1 && app.work.project.vegetation[n*n-1]==0 && app.work.project.fuel(n*n-1)==0.0,"Erasing vegetation preserves the growable land domain")
        app.work.history(true);app.syncScene();pass(app.work.project.fuel(n*n-1)==1.0,"Undo restores vegetation state on the enlarged grid")
        let beforeImport=app.work.project;app.importImage("assets/readme/oak-sapling.png")
        pass(app.work.project.nx==n && app.work.project.nz==n && app.work.project.metersWide==0.0,"Reference import preserves the selected grid size while requiring fresh scale calibration")
        app.work.acceptLoaded(beforeImport,"");app.refreshReference();app.syncScene()
        let geometry=app.scene.revision;let setting=app.work.project.copy();setting.seed=43;app.work.commit(setting);app.syncScene()
        pass(app.scene.revision==geometry,"Changing only scenario parameters reuses static voxel geometry")
        app.mapMode=true;app.camera.resetMap();let layout=Layout(Float32(w.width),Float32(w.height));let box=app.mapWorldBox(layout)
        for(cell in [0,n-1,n*(n-1),n*n-1,n*(n/2)+n/2]){
            let point=Point(box.x+(Float32(cell%n)+0.5)*box.w/Float32(n),box.y+(Float32(cell/n)+0.5)*box.h/Float32(n))
            require(app.cellAt(point.x,point.y,layout)==cell,"Large map picks the wrong logical cell")
        }
        pass(true,"Large map picks all corners and center using project dimensions")
        let paired=app.work.project.copy();paired.ignition=0;paired.spreadProbability=1.0;paired.burnSteps=1
        for(z in 0..n){paired.treatment[z*n+n/2]=2}
        let start=clock.ms();let job=EvaluationJob(paired,app.work.revision,makeScenarios(paired,1));job.execute();let evaluated=clock.ms()-start
        let state=job.progress();require(state.done && state.error.isEmpty() && state.result.isSome(),"Large paired evaluation failed: "+state.error)
        let result=state.result.getOrThrow();let row=result.rows[0]
        pass(row.baseline.burned==n*n && row.planned.burned==n*n/2 && row.planned.cleared==n && row.planned.remaining==n*(n/2-1),"Large deterministic firebreak preserves exact paired burn/clear/remaining conservation")
        let candidateStart=clock.ms();let candidates=generateCandidates(paired,{=>false});let candidateTime=clock.ms()-candidateStart
        pass(candidates.size<=14,"Large candidate search completes within the existing finite candidate contract")
        var gpuTime:Float64=0.0
        try(pair=ComparisonView(result,app.assets)){
            pair.baseline.useGpu=true;pair.planned.useGpu=true;let gpuStart=clock.ms()
            pair.prepare(app.camera,Rect(20.0,152.0,700.0,500.0),w,true,true,true,false)
            gpuTime=clock.ms()-gpuStart
            pass(pair.baseline.gpuActive && pair.planned.gpuActive && pair.baselineScene.nx==n && pair.planned.fireAge.size==n*n,"Actual D3D11 renders both enlarged paired scenes with matching dynamic state")
            pair.seek(pair.maxStep);pair.prepare(app.camera,Rect(20.0,152.0,700.0,500.0),w,true,true,true,false)
        }
        let cancelled=EvaluationJob(paired,app.work.revision,makeScenarios(paired,1));cancelled.cancel();cancelled.execute()
        pass(cancelled.progress().result.isNone(),"Cancelled large evaluation publishes no partial result")
        app.work.acceptLoaded(paired,"");app.syncScene();app.preferences.gpuEnabled=true;app.mapMode=false;app.camera.fitScene(app.scene,layout.canvas);enterWorkflow(app,1)
        let run=app.experiment.create(paired);for(_ in 0..n/2){run.advance()};app.refreshExperimentView();render(app,w)
        let uploads=app.view.gpu.getOrThrow().engine.uploads;let frameTimes=ArrayList<Float64>();let loopStart=clock.ms()
        for(frame in 0..12){
            run.advance();app.refreshExperimentView();app.clockNow=UInt64(frame*80);let frameStart=clock.ms();render(app,w);frameTimes.add(clock.ms()-frameStart);w.delay(12)
        }
        let fps=12000.0/(clock.ms()-loopStart);let frames=FrameStats(frameTimes.toArray())
        pass(app.view.gpuActive && app.view.gpu.getOrThrow().engine.uploads==uploads+12,"Large burning frames update compact state without reuploading static geometry")
        rows.add("${n},${n},${loaded},${evaluated},${candidateTime},${gpuTime},${fps},${frames.median},${frames.p95}")
        render(app,w,capture:"artifacts/grid-${n}-forest.png")
    }
    File.writeTo("artifacts/grid-benchmark.csv",String.join(rows.toArray(),delimiter:"\n").toArray())
    app.preferences.gpuEnabled=false;app.view.useGpu=false;app.mapMode=false;app.work.acceptLoaded(Project(),"");app.syncScene();app.camera.focusScene(app.scene);app.cancel();enterWorkflow(app,0);app.tool=0
}
