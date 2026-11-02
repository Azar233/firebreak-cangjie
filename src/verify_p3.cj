package firebreak

import sdl.*
import std.fs.{File,Directory,exists}
import stdx.encoding.json.*
import std.convert.*

func evaluated(p: Project,scenarios: Array<Scenario>): EvaluationResult {
    let job=EvaluationJob(p,7,scenarios); job.execute()
    let progress=job.progress(); require(progress.done && progress.error.isEmpty(),"Evaluation failed: "+progress.error)
    return progress.result.getOrThrow()
}
func evaluationChain(): Project {
    let p=Project(demo:false)
    for (i in 0..5) { p.land[i]=1;p.vegetation[i]=1 }; p.land[5]=4; p.targets[5]=1
    p.ignition=0; p.spreadProbability=1.0; p.burnSteps=1; return p
}
func verifyP3(app: App,w: SdlWindow): Unit {
    let original=evaluationChain(); let unchanged=original.text(); let same=evaluated(original,makeScenarios(original,4))
    for (row in same.rows) {
        require(row.baseline.burned==row.planned.burned && row.baseline.remaining==row.planned.remaining &&
            row.baseline.contacts==row.planned.contacts && row.baseline.steps==row.planned.steps,"Untreated paired outcomes differ")
    }
    for (i in 0..same.baselineReplay.snapshots.size) {
        require(same.baselineReplay.snapshots[i].age==same.plannedReplay.snapshots[i].age,"Untreated snapshots differ")
    }
    pass(original.text()==unchanged,"no treatment produces identical paired outcomes and histories without mutating baseline")
    let p=original.copy(); p.treatment[2]=2
    let paired=evaluated(p,[Scenario(0,0,42,0.25),Scenario(1,4,42,0.75)])
    let a=paired.rows[0]; let b=paired.rows[1]
    pass(a.baseline.burned==5 && a.planned.burned==2 && a.baseline.contacts==1 && a.planned.contacts==0 && b.planned.contacts==1,
        "deterministic cut preserves right-side ignition failures and prevents left-side target contact")
    pass(a.planned.cleared==1 && a.planned.remaining==2 && paired.mean(true,0)==2.0 && paired.mean(true,2)==0.75,
        "clearing, burning and remaining conserve baseline forest; unequal sample weights are used")
    let blocked=evaluated(p,[Scenario(0,2,42,1.0)])
    pass(blocked.rows[0].planned.ignitionBlocked && blocked.rows[0].planned.burned==0 && blocked.rows[0].planned.steps==0 &&
        blocked.rows[0].baseline.burned==5,"treated ignition remains in paired sample and is explicitly prevented")
    let stream=FireRun(fuelMask(original,false),GRID_X,GRID_Z,0,0.63,3,42,keepHistory:false)
    let history=FireRun(fuelMask(original,false),GRID_X,GRID_Z,0,0.63,3,42)
    finishFire(stream); finishFire(history)
    pass(stream.snapshots.size==1 && stream.current().age==history.current().age && stream.current().step==history.current().step,
        "history-free batch run has identical final state with one retained snapshot")
    let frozen=EvaluationJob(p,8,makeScenarios(p,4)); p.land[0]=0; frozen.execute()
    pass(readProjectText(frozen.progress().result.getOrThrow().projectText).land[0]==1,"job freezes project inputs before asynchronous evaluation")
    let cancelled=EvaluationJob(original,9,makeScenarios(original,4)); cancelled.cancel(); cancelled.execute()
    pass(cancelled.progress().done && cancelled.progress().result.isNone() && cancelled.progress().completed==0,
        "pre-cancelled job publishes no partial result")
    let live=Project(); live.burnSteps=8; live.spreadProbability=1.0
    let running=EvaluationJob(live,10,makeScenarios(live,64)); running.start()
    for (_ in 0..5000) { if (running.progress().completed>0 || running.progress().done) { break }; w.delay(1) }
    running.cancel()
    for (_ in 0..5000) { if (running.progress().done) { break }; w.delay(1) }
    pass(running.progress().done && running.progress().cancelled && running.progress().result.isNone(),
        "background batch cancels after completed work and withholds partial results")
    var invalid: Int64=0
    try { makeScenarios(Project(demo:false),4) } catch(_: Exception) { invalid++ }
    try { makeScenarios(original,0) } catch(_: Exception) { invalid++ }
    try { Scenario(0,0,42,0.0) } catch(_: Exception) { invalid++ }
    try { EvaluationJob(original,0,[Scenario(0,0,42,1.0),Scenario(0,1,42,1.0)]) } catch(_: Exception) { invalid++ }
    try { EvaluationJob(original,0,[Scenario(0,6,42,1.0)]) } catch(_: Exception) { invalid++ }
    pass(invalid==5,"empty fuel, invalid count/weight, duplicate ids and non-fuel baseline ignition are rejected")
    let precision=original.copy(); precision.aspect=1.2345678901234567; precision.spreadProbability=0.12345678901234567
    pass(readProjectText(precision.text()).aspect==precision.aspect && readProjectText(precision.text()).spreadProbability==precision.spreadProbability,
        "frozen project retains full Float64 precision for reproducible calculations")
    app.simPanel=false; app.settings=false; app.cancel(); app.work.acceptLoaded(original,""); app.syncScene()
    click(app,w,52); app.sampleCount=4; click(app,w,60)
    for (_ in 0..5000) { app.updateExperiment(w.ticks()); if (app.evalJob.isNone()) { break }; w.delay(1) }
    pass(app.comparePanel && app.evalResult.getOrThrow().rows.size==4 && app.pairView.isSome(),"pointer-started asynchronous evaluation publishes complete current-revision comparison")
    let old=app.pairView.getOrThrow(); let prior=app.tool
    event(app,w,UiEvent.KeyDown(Key.Digit(UInt8(54)),false))
    let layout=Layout(Float32(w.width),Float32(w.height))
    event(app,w,UiEvent.MouseDown(MouseButton.Left,layout.canvas.centerX(),layout.canvas.centerY()))
    event(app,w,UiEvent.MouseUp(MouseButton.Left,layout.canvas.centerX(),layout.canvas.centerY()))
    pass(app.tool==prior && app.startCell<0,"comparison canvas and hotkeys cannot accidentally edit the project")
    let next=app.work.project.copy(); next.seed++; app.work.commit(next); app.updateExperiment(w.ticks())
    pass(app.evalResult.isNone() && app.pairView.isNone() && old.isClosed(),"input revision invalidates results and closes comparison graphics")
    click(app,w,60); let stale=app.evalJob.getOrThrow(); let edited=app.work.project.copy(); edited.seed++
    app.work.commit(edited); app.updateExperiment(w.ticks())
    for (_ in 0..5000) { if (stale.progress().done) { break }; w.delay(1) }
    pass(stale.progress().cancelled && app.evalJob.isNone() && app.evalResult.isNone(),"revision change cancels background work and cannot publish stale results")
    for (size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]) {
        let l=Layout(size.w,size.h)
        for (id in CONTROLS) { if (l.available(id,false,comparison:true)) {
            let box=l.control(id)
            require(box.w>=44.0 && box.h>=44.0 && box.right()<=size.w && box.bottom()<=l.height,"Comparison control outside window")
            require(l.hit(box.centerX(),box.centerY(),comparison:true)==id,"Comparison controls overlap")
        } }
        let left=compareBox(l.canvas,false); let right=compareBox(l.canvas,true)
        require(left.right()<right.x && right.right()<=l.canvas.right(),"Comparison panes overlap")
    }
    app.focus=0
    for (_ in 0..CONTROLS.size) { event(app,w,UiEvent.KeyDown(Key.Tab,false)); require(layout.available(CONTROLS[app.focus],false,comparison:true),"Hidden comparison focus") }
    pass(true,"comparison controls and paired panes fit three desktop sizes; keyboard skips hidden controls")
    let demo=Project(); demo.ignition=75; demo.spreadProbability=1.0
    for (z in 0..9) { demo.treatment[z*GRID_X+12]=2 }
    let result=evaluated(demo,makeScenarios(demo,4))
    app.work.acceptLoaded(demo,""); app.syncScene(); app.evalResult=Some(result); app.pairView=Some(ComparisonView(result,app.assets))
    // This fixed test result uses revision 7; match it before testing normal rendering/invalidation.
    app.work.revision=result.revision
    let pair=app.pairView.getOrThrow(); pair.seek(pair.maxStep)
    pass(pair.baseline.fireAge==result.baselineReplay.current().age && pair.planned.fireAge==result.plannedReplay.current().age,
        "synchronized replay holds each side at its own final snapshot")
    pair.play(UInt64(100)); pair.tick(UInt64(599)); require(pair.step==0,"Replay moved too early")
    pair.tick(UInt64(600)); pass(pair.step==1,"paired replay uses shared logical time independent of render cadence")
    pair.seek(pair.maxStep); app.mapMode=true; app.referenceMode=false; app.camera.reset(); app.clockNow=1000
    app.message="同一场地与情景集合；回放情景 1，右侧汇总全部样本。"
    render(app,w,capture:"artifacts/p3-comparison.png")
    pass(pair.baseline.nativeReady() && pair.planned.nativeReady() && pair.baseline.topDown && pair.planned.topDown,
        "both comparison panes render actual voxel textures at native target resolution")
    app.camera.rotate(20.0,0.0); pair.prepare(app.camera,layout.canvas,w,false,true,true,false)
    pass(!pair.baseline.topDown && !pair.planned.topDown && pair.baseline.nativeReady() && pair.planned.nativeReady(),
        "shared camera and projection changes invalidate and redraw both panes")
    let parent=Directory.createTemp("artifacts").toString(); let exported=exportEvaluation(result,app.assets,parent)
    let second=exportEvaluation(result,app.assets,parent)
    let csv=String.fromUtf8(File.readFrom(exported+"/metrics.csv"))
    pass(second!=exported && exists(exported+"/report.md") && csv==evaluationCsv(result) &&
        String.fromUtf8(File.readFrom(exported+"/site.firebreak"))==result.projectText,"exports preserve frozen inputs and exact CSV and never replace existing report directories")
    let parameters=JsonValue.fromStr(String.fromUtf8(File.readFrom(exported+"/parameters.json"))).asObject()
    let ss=parameters["scenarios"].asArray(); let scenarios=Array<Scenario>(ss.size(),{i =>
        let s=ss[i].asObject(); Scenario(s["id"].asInt().getValue(),s["ignitionCell"].asInt().getValue(),s["seed"].asInt().getValue(),Float64.parse(s["weight"].asString().getValue())) })
    let repeated=evaluated(readProjectText(String.fromUtf8(File.readFrom(exported+"/site.firebreak"))),scenarios)
    pass(evaluationCsv(repeated)==csv && parameters["wind"].asString().getValue()=="none","exported project and scenarios reproduce every per-sample metric")
    try (image=Surface.loadPng(exported+"/baseline.png")) {
        try (planned=Surface.loadPng(exported+"/planned.png")) {
            pass(image.size().w==384.0 && image.size().w==planned.size().w && image.size().h==planned.size().h,"exported paired PNG maps decode with identical dimensions")
        }
    }
    let report=String.fromUtf8(File.readFrom(exported+"/report.md"))
    pass(report.contains("不是现实火灾概率") && report.contains("情景 1") && report.contains("全部样本均保留"),"report states sampling, weighted aggregation and first-scenario image limits")
    app.clearComparison(); pass(pair.isClosed(),"comparison textures and pending surfaces close after export")
    app.comparePanel=false; app.simPanel=false; app.settings=false; app.mapMode=false; app.referenceMode=false
    app.work.acceptLoaded(Project(),""); app.refreshReference(); app.syncScene(); app.camera.reset(); app.view.showCanopy=true; app.tool=0; app.focus=0; app.cancel()
    println("P3 logic, background task, replay, export and position checks completed; visual design awaits user review.")
}
