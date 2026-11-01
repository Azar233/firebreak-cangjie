package firebreak

import sdl.*

func visibleLeafCount(scene: Scene,stage: Int64): Int64 {
    var count: Int64=0
    for (z in 0..scene.nz) { for (y in 0..scene.ny) { for (x in 0..scene.nx) {
        if (fireDisplayMaterial(scene,scene.get(x,y,z),x,y,z,stage)==4) { count++ }
    } } }; return count
}
func verifyBurnDisplay(app: App,w: SdlWindow): Unit {
    let s=flatScene(); s.tree(6,6); let original=s.blocks.clone()
    var previous=visibleLeafCount(s,0)
    for (stage in 1..4) {
        let count=visibleLeafCount(s,stage)
        require(count>0 && count<previous,"Burning canopy did not progressively thin"); previous=count
    }
    pass(visibleLeafCount(s,4)==0,"burnout hides every leaf while burning phases progressively thin canopy")
    var logs: Int64=0
    for (y in 0..s.ny) { if (fireDisplayMaterial(s,s.get(6,y,6),6,y,6,4)==3) { logs++ } }
    pass(logs==1 && fireDisplayMaterial(s,s.get(6,1,6),6,1,6,4)==3,"burnout removes upper trunk and preserves exactly one block of stump")
    let stages=Array<Int64>(CELL_COUNT,repeat:4)
    let crownRay=overheadRay(s,7.5/24.0,6.5/20.0)
    let before=trace(s,crownRay,leavesOpaque:true).getOrThrow()
    let after=trace(s,crownRay,leavesOpaque:true,fireStages:Some(stages)).getOrThrow()
    let stump=trace(s,overheadRay(s,6.5/24.0,6.5/20.0),fireStages:Some(stages)).getOrThrow()
    pass(before.material==4 && after.material==10 && after.y==0 && stump.material==3 && stump.y==1,
        "actual ray traversal reveals ash beneath removed canopy and hits shortened stump")
    let pick=trace(s,crownRay,groundOnly:true,fireStages:Some(stages)).getOrThrow()
    pass(pick.x==7 && pick.z==6 && pick.y==0 && pick.material==1,"burnout appearance leaves ground picking on original terrain coordinates")
    let ash=app.assets.sample(after)
    pass(ash.r==ash.g && ash.g==ash.b && ash.r>UInt8(0),"ash samples a visible neutral texture instead of green grass")
    pass(s.blocks==original && visibleLeafCount(s,0)>0,"display filtering does not destroy base voxels and intact geometry remains recoverable")
    for (duration in [1,2,8]) {
        var last: Int64=0
        for (elapsed in 0..duration) {
            let stage=burnVisualStage(duration-elapsed,duration)
            require(stage>=last && stage>=1 && stage<=3,"Burn display phases moved backwards"); last=stage
        }
        require(burnVisualStage(-1,duration)==4 && burnVisualStage(0,duration)==0,"Burnout/reset phase mismatch")
    }
    pass(true,"display phases cover short and long burn durations without adding model steps")

    let p=Project(); p.ignition=75; p.spreadProbability=1.0; p.burnSteps=3
    app.work.acceptLoaded(p,""); app.experiment.planned=true; app.experiment.showConnectivity=false; app.syncScene()
    let run=app.experiment.create(p)
    for (_ in 0..10) { run.advance() }
    let savedScene=app.scene.blocks.clone(); let savedProject=app.work.project.text(); let savedState=run.current().age.clone()
    let total=run.snapshots.size; let burned=run.current().burned(); let burning=run.current().burning()
    app.refreshExperimentView()
    pass(app.view.burnStages[75]==4,"current snapshot publishes burnout geometry to shared renderer")
    pass(app.view.fireAnchor(75).y==app.scene.ground(3,3)+1.0 && app.view.fireAnchor(0).y==app.scene.ground(0,0),
        "fire sprite anchor follows shortened stump or exposed ground instead of floating at old canopy height")
    run.seek(0); app.refreshExperimentView()
    pass(app.view.burnStages[75]==1 && app.view.burnStages[3*24+7]==0,"rewinding snapshot restores unburned neighbors and early burning canopy")
    run.seek(total-1); app.refreshExperimentView()
    pass(app.view.burnStages[75]==4 && run.current().age==savedState && run.snapshots.size==total,
        "replaying burnout restores the same appearance without recomputing fire history")
    app.mapMode=false; app.referenceMode=false; app.simPanel=true; app.simParameters=false; app.camera.reset()
    app.view.selectedX = -1; app.view.selectedZ = -1; app.clockNow=1000
    render(app,w,capture:"artifacts/p2-burnout-3d.png")
    pass(app.scene.blocks==savedScene && app.work.project.text()==savedProject && run.current().age==savedState &&
        run.current().burned()==burned && run.current().burning()==burning,"native burnout render preserves baseline, snapshots and propagation metrics")
    app.simulationAction(42)
    pass(app.experiment.run.isNone() && app.view.burnStages[75]==0 && app.scene.blocks==savedScene &&
        trace(app.scene,overheadRay(app.scene,3.5/24.0,3.5/20.0),leavesOpaque:true,fireStages:Some(app.view.burnStages)).getOrThrow().material==4,
        "reset restores full forest geometry without rebuilding or losing original scene")
    app.work.acceptLoaded(Project(),""); app.syncScene(); app.simPanel=false; app.mapMode=false; app.tool=0; app.focus=0; app.cancel()
}
