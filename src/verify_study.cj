package firebreak

import sdl.*
import std.fs.{File,exists}
import std.math.abs
import stdx.encoding.json.*

func waitStudy(app:App,w:SdlWindow):Unit {
    let clock=PerformanceClock();let start=clock.ms()
    while(app.studyJob.isSome() && clock.ms()-start<30000.0){pollStudy(app);w.delay(5)}
    require(app.studyJob.isNone(),"Study did not finish within 30 seconds")
}
func verifyStudy(app:App,w:SdlWindow):Unit {
    let base=Project(nx:16,nz:16);base.spreadProbability=1.0;base.burnSteps=1
    let original=base.text();let sparse=densityForest(base,0.4,42);let dense=densityForest(base,0.7,42)
    pass(STUDY_POLICY_STEP>128*128*8 && STUDY_OCCUPANCY_STEP!=STUDY_POLICY_STEP && STUDY_IGNITION_STEP!=STUDY_POLICY_STEP && STUDY_IGNITION_STEP!=STUDY_OCCUPANCY_STEP,"Occupation, ignition and policy random keys cannot reuse a reachable fire-step key")
    for(i in 0..base.cells){require(sparse.fuel(i)<=dense.fuel(i),"Coupled density samples are not nested")}
    pass(sparse.text()==densityForest(base,0.4,42).text() && base.text()==original,"Density sampling is deterministic, nested across probability and does not mutate its source")
    let half=wilsonInterval(5,10);let zero=wilsonInterval(0,10);let full=wilsonInterval(10,10)
    pass(abs(half[0]-0.23659309)<0.000001 && abs(half[1]-0.76340691)<0.000001 && zero[0]<0.000001 && abs(zero[1]-0.2775328)<0.000001 && full[1]>0.999999,"Wilson 95% intervals match known central and endpoint binomial cases")
    let job=ForestStudyJob(base,7,4);base.seed=999;job.execute();let scan=job.progress().density.getOrThrow()
    pass(scan.source==original && scan.rows.size==84 && scan.points[0].hits==0 && scan.points[0].largest==0.0 && scan.points[20].hits==4 && scan.points[20].largest==256.0,"Frozen scan retains inputs and records exact empty/full endpoints")
    var previous:Float64= -1.0
    for(point in scan.points){var hits:Int64=0;var largest:Float64=0.0
        for(row in scan.rows){if(row.probability==point.probability){if(row.spanning){hits++};largest+=Float64(row.largest)}}
        require(hits==point.hits && largest/4.0==point.largest && point.frequency()>=previous,"Summary differs from raw samples or coupled monotonicity")
        previous=point.frequency()
    }
    pass(!scan.bracket().isEmpty(),"Raw seed-level samples reconstruct every plotted point and the empirical 50% bracket")
    let blocked=Project(nx:16,nz:16);for(z in 0..16){blocked.land[z*16+8]=3;blocked.vegetation[z*16+8]=0}
    let blockedJob=ForestStudyJob(blocked,0,2);blockedJob.execute()
    pass(blockedJob.progress().density.getOrThrow().bracket().isEmpty(),"An ineligible separating domain does not fabricate a critical bracket even at p=1")
    let chain=Project(nx:7,nz:1);let cut=interveneForest(chain,1,2,{=>false})
    pass(cut.treatment[3]==1 && Connectivity(fuelMask(cut,true),7,1).largest==3,"Connector priority removes the actual articulation bridge on a chain")
    let guarded=Project(nx:7,nz:5);guarded.targets[3]=1;guarded.forbidden[31]=1;let before=guarded.text()
    for(policy in 1..4){let p=interveneForest(guarded,5,policy,{=>false});require(p.count(p.treatment)==5 && p.treatment[3]==0 && p.treatment[31]==0,"Equal clearing or eligibility violated")}
    pass(guarded.text()==before && rejected({=>interveneForest(guarded,128,1,{=>false})}),"All policies clear exactly the requested count, preserve constraints and reject insufficient eligible fuel")
    let unpriced=Project(nx:7,nz:5);unpriced.metersWide=0.0;unpriced.budget=0.0;unpriced.clearingPrice=1.0e9
    pass(interveneForest(unpriced,5,1,{=>false}).count(interveneForest(unpriced,5,1,{=>false}).treatment)==5,"Cell-dose studies remain independent of missing physical calibration and monetary limits")
    let plansJob=ForestStudyJob(chain,0,4,mode:1,probability:1.0,dose:1);plansJob.execute();let plans=plansJob.progress().interventions.getOrThrow()
    for(index in 0..4){let first=plans.rows[index*4];for(policy in 0..4){let row=plans.rows[index*4+policy]
        require(row.seed==first.seed && row.ignition==first.ignition && row.original==row.cleared+row.burned+row.remaining && row.cleared==if(policy==0){0}else{1},"Policies did not share external inputs or conserve forest")
        let p=plans.preview(index,policy);let run=FireRun(fuelMask(p,true),p.nx,p.nz,row.ignition,p.spreadProbability,p.burnSteps,p.seed,allowBlockedIgnition:true,keepHistory:false);finishFire(run)
        require(run.current().burned()==row.burned,"Policy preview cannot reproduce its raw outcome")
    }}
    pass(true,"Every policy uses shared ignition/seed, retains blocked ignitions, conserves forest and reproduces its raw outcome")
    pass(plans.burnDeltaSE(0)==0.0 && plans.burnDeltaSE(1)>=0.0 && plans.burnDeltaSE(2)>=0.0,"Paired burn-difference uncertainty retains the shared-sample baseline")
    let one=ForestStudyJob(Project(nx:1,nz:1),0,2,mode:1,probability:1.0,dose:1);one.execute()
    for(row in one.progress().interventions.getOrThrow().rows){if(row.strategy>0){require(row.blocked && row.burned==0 && row.cleared==1,"A cleared ignition was resampled or omitted")}}
    pass(true,"Cleared ignitions stay in paired records as blocked events rather than being resampled")
    let largeJob=ForestStudyJob(Project(nx:128,nz:128),0,2);largeJob.execute()
    pass(largeJob.progress().density.getOrThrow().rows.size==42 && largeJob.progress().density.getOrThrow().points[20].largest==16384.0,"Density scans also complete on the full supported 128-by-128 grid")
    let cancelled=ForestStudyJob(chain,0,4);cancelled.cancel();cancelled.execute()
    pass(cancelled.progress().cancelled && cancelled.progress().density.isNone(),"Cancelled density studies publish no partial chart")
    for(size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]){let l=Layout(size.w,size.h)
        for(id in STUDY_CONTROLS){let b=l.control(id);require(b.w>=44.0 && b.h>=44.0 && b.right()<=size.w && b.bottom()<=size.h && l.hit(b.centerX(),b.centerY(),study:true)==id,"Study controls overlap or fall outside the window")}
    }
    pass(true,"Study controls have distinct 44px targets at minimum, ordinary and fullscreen sizes")
    app.menuOpen=false;app.terminal.open=false;app.cancel();app.work.acceptLoaded(Project(nx:64,nz:64),"");app.syncScene();enterWorkflow(app,1)
    app.startCell=0;app.endCell=1;click(app,w,140)
    pass(!app.studyPanel && app.startCell==0,"Pending edits block opening the study without losing their selection")
    app.cancel();click(app,w,140);app.studySamples=32;app.studyDose=4;let source=app.work.project.text();let revision=app.work.revision
    click(app,w,141);waitStudy(app,w)
    pass(app.densityResult.isSome() && app.work.project.text()==source && app.work.revision==revision,"Native scan controls publish a frozen result without editing the workspace")
    app.preferences.gpuEnabled=true;render(app,w,capture:"artifacts/r3-density.png")
    let preview=app.studyPreview.getOrThrow();let result=app.densityResult.getOrThrow()
    pass(preview.view.gpuActive && preview.project.vegetation==result.sample(app.studyPoint,app.studySample).vegetation,"Actual GPU map displays the exact sampled vegetation underlying the plot")
    let l=Layout(Float32(w.width),Float32(w.height));let chart=studyChart(l)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,chart.x+chart.w*0.65,chart.centerY()));event(app,w,UiEvent.MouseUp(MouseButton.Left,chart.x+chart.w*0.65,chart.centerY()))
    pass(app.studyPoint==13 && app.work.project.text()==source,"Clicking the plot selects an actual density sample without applying it")
    app.studySample=31;refreshStudyPreview(app);app.studySamples=8;click(app,w,147);waitStudy(app,w)
    pass(app.interventionResult.isSome() && app.interventionResult.getOrThrow().rows.size==32,"Native equal-clearing controls evaluate all four policies over the same eight seeds")
    click(app,w,145);pass(app.studySample==0 && app.studyPreview.getOrThrow().project.seed==42,"A smaller policy batch clamps the preview seed and cycles only through available paired samples")
    click(app,w,152);pass(app.studyPolicy==1 && app.studyPreview.getOrThrow().project.count(app.studyPreview.getOrThrow().project.treatment)==4,"Policy selector previews the real four-cell clearing mask")
    render(app,w,capture:"artifacts/r3-interventions.png")
    app.preferences.setEnglish(true);app.message="Study complete; preview before applying.";w.setSize(1100,780);w.refreshSize();render(app,w,capture:"artifacts/r3-study-en-small.png")
    app.preferences.setEnglish(false);w.setSize(2560,1380);w.refreshSize();render(app,w,capture:"artifacts/r3-study-fullscreen.png")
    w.setSize(1280,860);w.refreshSize()
    let exported=exportStudy(app,"artifacts");let exportedAgain=exportStudy(app,"artifacts")
    let parameters=JsonValue.fromStr(String.fromUtf8(File.readFrom(exported+"/parameters.json"))).asObject()
    pass(exported!=exportedAgain && exists(exported+"/preview.png") && exists(exported+"/density.svg") && exists(exported+"/intervention-summary.csv") && String.fromUtf8(File.readFrom(exported+"/density-summary.csv"))==densitySummaryCsv(result) && parameters["samplesPerDensity"].asInt().getValue()==32,"Study export preserves raw data, plot, sample map and parameters without overwriting earlier exports")
    pass(rejected({=>app.loadProject("artifacts/nonexistent-density-project.firebreak")}) && app.studyPanel && app.densityResult.isSome(),"A failed file load preserves the active study and published results")
    click(app,w,148)
    pass(!app.studyPanel && app.work.project.count(app.work.project.treatment)==4 && app.work.project.cost()==200.0 && app.work.revision==revision+1,"Applying the preview restores real prices and commits one undoable edit before exiting the chart")
    click(app,w,14);pass(app.work.project.text()==source,"Undo restores the original workspace after applying a sampled intervention")
    app.densityResult=Some(result);let stale=ForestStudyJob(app.work.project,app.work.revision,8);app.studyJob=Some(stale)
    let changed=app.work.project.copy();changed.seed++;app.work.commit(changed);pollStudy(app);stale.execute()
    pass(app.densityResult.isNone() && app.studyPreview.isNone() && app.studyJob.isNone() && stale.progress().cancelled,"A workspace revision rejects both stale published study data and pending results")
    app.work.acceptLoaded(Project(),"");app.refreshReference();app.syncScene();app.preferences.gpuEnabled=false;app.view.useGpu=false;app.mapMode=false;app.cancel();enterWorkflow(app,0);app.camera.focusScene(app.scene);app.tool=0
}
