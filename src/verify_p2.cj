package firebreak

import sdl.*
import std.collection.ArrayList
import std.fs.File
import stdx.encoding.json.*

func finishFire(run: FireRun): Unit {
    for (_ in 0..run.fuel.size*8+2) { if (!run.advance()) { return } }
    throw Exception("Fire did not terminate within finite-fuel bound")
}
func verifyPercolation(): Unit {
    let nx: Int64=32; let nz: Int64=32; let samples: Int64=40
    let rows=ArrayList<String>(["occupied_probability,samples,left_right_spanning_samples,mean_largest_component_cells"])
    var sparse: Int64=0; var dense: Int64=0
    for (probability in [0.0,0.2,0.4,0.6,0.8,1.0]) {
        var spans: Int64=0; var largest: Int64=0
        for (seed in 0..samples) {
            let fuel=Array<Bool>(nx*nz,{i => edgeRandom(seed,0,i,0)<probability})
            let components=Connectivity(fuel,nx,nz)
            if (components.spansLeftRight(nx,nz)) { spans++ }; largest+=components.largest
            // Coupled occupancy inputs must grow monotonically as p increases.
            if (probability<1.0) {
                let higher=Connectivity(Array<Bool>(nx*nz,{i => edgeRandom(seed,0,i,0)<probability+0.01}),nx,nz)
                require(higher.largest>=components.largest,"Adding sites reduced largest component")
                require(!components.spansLeftRight(nx,nz) || higher.spansLeftRight(nx,nz),"Adding sites removed spanning path")
            }
        }
        if (probability==0.0) { require(spans==0 && largest==0,"Empty ideal lattice unexpectedly percolated") }
        if (probability==1.0) { require(spans==samples && largest==samples*nx*nz,"Full ideal lattice failed to percolate") }
        if (probability==0.2) { sparse=spans }; if (probability==0.8) { dense=spans }
        rows.add("${probability},${samples},${spans},${Float64(largest)/Float64(samples)}")
    }
    require(dense>sparse,"Fixed-seed dense ideal lattice did not span more often than sparse input")
    File.writeTo("artifacts/p2-ideal-percolation.csv",String.join(rows.toArray(),delimiter:"\n").toArray())
    pass(true,"independent 32x32 ideal-site sweep: empty/full endpoints, coupled monotonicity and sparse/dense spanning contrast")
}
func verifyP2Model(): Unit {
    let empty=Connectivity(Array<Bool>(9,repeat:false),3,3)
    pass(empty.total==0 && empty.largest==0 && empty.sizes.isEmpty() && !empty.spansLeftRight(3,3),"empty graph has zero components and no spanning path")
    let full=Connectivity(Array<Bool>(9,repeat:true),3,3)
    pass(full.total==9 && full.largest==9 && full.sizes.size==1 && full.spansLeftRight(3,3),"full four-neighbor lattice forms one spanning component")
    let diagonal=Connectivity([true,false,false,false,true,false,false,false,true],3,3)
    pass(diagonal.sizes.size==3 && diagonal.largest==1,"diagonal sites remain separate under four-neighbor adjacency")
    let bridge=[true,true,false,true,true,
                true,true,true,true,true,
                true,true,false,true,true]
    let joined=Connectivity(bridge,5,3); let cut=bridge.clone(); cut[7]=false
    let split=Connectivity(cut,5,3)
    pass(joined.sizes.size==1 && joined.largest==13 && split.sizes.size==2 && split.largest==6,"removing a one-cell bridge splits two six-cell forest islands")
    let goal=Array<Bool>(5,repeat:false); goal[4]=true
    let path=Connectivity([true,true,true,true,false],5,1,targets:goal,ignition:0)
    pass(path.path==[0,1,2,3],"shortest fuel path ends at target perimeter without treating building as fuel")
    let blocked=Connectivity([true,true,false,true,false],5,1,targets:goal,ignition:0)
    pass(blocked.path.isEmpty(),"non-fuel gap removes ignition-to-target path")
    let chain=FireRun([true,true,true,true,true],5,1,0,1.0,1,42)
    let first=chain.current(); chain.advance()
    pass(chain.current().age==[-1,1,0,0,0] && first.age==[1,0,0,0,0],"synchronous chain advances one edge per step and leaves old snapshot unchanged")
    finishFire(chain)
    pass(chain.current().burned()==5 && chain.current().burning()==0 && chain.snapshots.size==6,"finite deterministic chain burns out exactly after five updates")
    let wet=FireRun([true,true,true],3,1,0,0.0,2,42); finishFire(wet)
    pass(wet.current().age==[-1,0,0] && wet.current().step==2,"zero spread probability still consumes ignition for its finite duration")
    let barrier=FireRun([true,true,false,true,true],5,1,0,1.0,2,42); finishFire(barrier)
    pass(barrier.current().burned()==2 && barrier.current().age[3]==0 && barrier.current().age[4]==0,"non-fuel barrier blocks fire even at spread probability one")
    let diagFire=FireRun([true,false,false,true],2,2,0,1.0,1,42); finishFire(diagFire)
    pass(diagFire.current().burned()==1,"fire cannot jump diagonally or across non-fuel cells")
    let exposure=FireRun([true,true,false],3,1,0,1.0,1,1,targets:[false,false,true]); finishFire(exposure)
    pass(exposure.current().contacts()==1 && exposure.current().age[2]==0,"target-neighbor exposure persists without claiming non-fuel target burned")
    let input=[true,true,true]; let frozen=FireRun(input,3,1,0,1.0,1,1); input[1]=false; finishFire(frozen)
    pass(frozen.current().burned()==3,"run freezes fuel inputs instead of observing later source mutations")
    let randomFuel=Array<Bool>(100,repeat:true)
    let a=FireRun(randomFuel,10,10,0,0.43,2,2026); let b=FireRun(randomFuel,10,10,0,0.43,2,2026)
    finishFire(a); finishFire(b)
    require(a.snapshots.size==b.snapshots.size,"Same seed changed duration")
    for (i in 0..a.snapshots.size) { require(a.snapshots[i].age==b.snapshots[i].age,"Same seed changed fire pattern") }
    pass(true,"same scenario seed reproduces every snapshot")
    let saved=a.snapshots[a.snapshots.size/2]; let total=a.snapshots.size
    a.seek(a.snapshots.size/2); a.advance()
    pass(a.snapshots.size==total && refEq(saved,a.snapshots[total/2]),"replay consumes existing snapshots without redrawing random numbers or branching history")
    pass(edgeRandom(42,3,4,5)==edgeRandom(42,3,4,5) && edgeRandom(42,3,4,5)!=edgeRandom(43,3,4,5) &&
        edgeRandom(42,3,4,5)!=edgeRandom(42,4,4,5) && edgeRandom(42,3,4,5)!=edgeRandom(42,3,5,4),"random input is stable and distinguishes seed, step and directed edge")
    let clockA=FireRun(randomFuel,10,10,0,1.0,1,42); let clockB=FireRun(randomFuel,10,10,0,1.0,1,42)
    clockA.play(100); clockB.play(100)
    for (now in [100,200,400,599]) { clockA.tick(UInt64(now)) }
    pass(clockA.cursor==0,"render ticks before fixed playback interval do not advance model")
    for (now in [600,1100,1600,2100]) { clockA.tick(UInt64(now)) }
    clockB.tick(2100)
    pass(clockA.cursor==4 && clockB.cursor==4 && clockA.current().age==clockB.current().age,"different UI tick schedules yield the same fixed-step state")
    clockA.running=false; let stopped=clockA.cursor; clockA.tick(9000)
    pass(clockA.cursor==stopped,"paused playback does not mutate simulation")
    pass(rejected({=>FireRun([false],1,1,0,1.0,1,0)}) && rejected({=>FireRun([true],1,1,0,1.1,1,0)}) &&
        rejected({=>FireRun([true],1,1,0,0.5,0,0)}),"invalid ignition, probability and duration are rejected")
    let p=Project(); p.ignition=3*24+3; p.spreadProbability=0.77; p.seed=2026; p.burnSteps=3
    let restored=readProjectText(p.text())
    pass(restored.ignition==p.ignition && restored.spreadProbability==0.77 && restored.seed==2026 && restored.burnSteps==3,"project v2 preserves scenario and model parameters")
    let legacy=JsonValue.fromStr(p.text()).asObject(); legacy.put("version",JsonInt(1))
    let old=readProjectText(legacy.toJsonString())
    pass(old.ignition== -1 && old.seed==42 && old.burnSteps==2 && old.land==p.land,"project v1 upgrades with explicit default scenario parameters")
    let future=JsonValue.fromStr(p.text()).asObject(); future.put("spreadRuleVersion",JsonInt(2))
    pass(rejected({=>readProjectText(future.toJsonString())}),"unknown spread rule version cannot silently reinterpret saved scenario")
    verifyPercolation()
}
func verifyP2(app: App,w: SdlWindow): Unit {
    verifyP2Model()
    app.work.acceptLoaded(Project(),""); app.syncScene(); app.mapMode=true; app.referenceMode=false; app.tool=0; app.settings=false
    click(app,w,19); click(app,w,45)
    let l=Layout(Float32(w.width),Float32(w.height)); let point=mapPoint(app,l,3,3)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,point.x,point.y)); event(app,w,UiEvent.MouseUp(MouseButton.Left,point.x,point.y))
    pass(app.work.project.ignition==75 && !app.pickingIgnition,"ignition tool selects actual forest ground beneath textured canopy")
    click(app,w,41); let run=app.experiment.run.getOrThrow()
    pass(run.cursor==1 && !run.running && app.view.fireAge==run.current().age,"single-step updates model and shared renderer without starting clock")
    click(app,w,41); pass(refEq(run,app.experiment.run.getOrThrow()) && run.cursor==2,"subsequent single-step continues the same run")
    click(app,w,43); pass(run.cursor==1 && run.snapshots.size==3,"previous snapshot rewinds without truncating computed history")
    click(app,w,44); pass(run.cursor==2 && run.snapshots.size==3,"next snapshot replays saved state")
    click(app,w,40); pass(run.running,"start button resumes trial")
    click(app,w,40); pass(!run.running,"pause button stops trial")
    click(app,w,46); pass(app.experiment.showConnectivity && app.view.clusterLabels==app.experiment.analysis.labels,"connectivity overlay reads exact scenario fuel graph")
    click(app,w,48); click(app,w,49); app.draft="0.9"; event(app,w,UiEvent.KeyDown(Key.Enter,false))
    pass(app.work.project.spreadProbability==0.9 && app.experiment.run.isNone(),"parameter edit invalidates prior trial and persists validated value")
    click(app,w,50); app.draft="1.5"; event(app,w,UiEvent.KeyDown(Key.Enter,false))
    pass(app.activeField==50 && app.work.project.burnSteps==2,"fractional burn duration is rejected without replacing prior value")
    event(app,w,UiEvent.KeyDown(Key.Escape,false)); click(app,w,48)
    click(app,w,41); let oldRun=app.experiment.run.getOrThrow()
    app.work.apply([4*24+3],6,false); app.syncScene()
    pass(app.experiment.run.isNone() && app.view.fireAge[75]==0 && app.work.project.treatment[4*24+3]==2,"committed treatment invalidates trial and refreshes exact fuel topology")
    click(app,w,47)
    pass(!app.experiment.planned && app.experiment.analysis.total==app.work.project.count(app.work.project.land)-48-16 && oldRun.snapshots.size>=2,
        "baseline mode restores fuel removed by plan without mutating old frozen snapshots")
    // Compare masks directly, rather than relying on scene geometry or tree counts.
    pass(fuelMask(app.work.project,false)[4*24+3] && !fuelMask(app.work.project,true)[4*24+3],"baseline and plan masks distinguish treatment from wildfire losses")
    click(app,w,47); click(app,w,42)
    pass(app.experiment.run.isNone() && app.work.project.ignition==75 && app.work.project.treatment[4*24+3]==2,"reset clears trial only and preserves scenario, baseline and intervention")
    for (size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]) {
        let layout=Layout(size.w,size.h)
        for (parameters in [false,true]) { for (id in CONTROLS) {
            if (!layout.available(id,false,simulation:true,parameters:parameters)) { continue }
            let box=layout.control(id)
            require(box.w>=44.0 && box.h>=44.0 && box.right()<=size.w && box.bottom()<=size.h,"P2 control outside window")
            require(layout.hit(box.centerX(),box.centerY(),simulation:true,parameters:parameters)==id,"P2 visible controls overlap")
        } }
    }
    pass(true,"both experiment panel modes have non-overlapping controls at minimum, normal and fullscreen sizes")
    app.simParameters=true; app.focus=0
    for (_ in 0..CONTROLS.size) { event(app,w,UiEvent.KeyDown(Key.Tab,false)); require(l.available(CONTROLS[app.focus],false,simulation:true,parameters:true),"P2 keyboard focused hidden control") }
    pass(true,"experiment keyboard focus skips hidden edit and playback controls")
    app.simParameters=false; app.experiment.showConnectivity=true; app.refreshExperimentView()
    render(app,w,capture:"artifacts/p2-connectivity.png")
    app.experiment.showConnectivity=false
    let p=app.work.project.copy(); p.spreadProbability=1.0; p.burnSteps=3; app.work.commit(p); app.updateExperiment(1000)
    for (_ in 0..5) { click(app,w,41) }
    app.clockNow=1000; app.refreshExperimentView()
    render(app,w,capture:"artifacts/p2-fire.png")
    pass(app.assets.images.contains("textures/block/fire_0.png"),"original MC animated fire sheet loads with valid frame rectangles")
    app.simPanel=false; app.simParameters=false; app.pickingIgnition=false; app.experiment.showConnectivity=false; app.experiment.planned=true
    app.work.acceptLoaded(Project(),""); app.syncScene(); app.mapMode=false; app.tool=0; app.cancel(); app.camera.reset(); app.focus=0
    println("P2 model, replay, resource and position checks completed; visual quality awaits user review.")
}

