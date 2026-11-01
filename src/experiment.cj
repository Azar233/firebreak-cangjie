package firebreak

class Experiment {
    var planned=true
    var showConnectivity=false
    var revision: Int64 = -1
    var previousPlanned=true
    var analysis=Connectivity(Array<Bool>(CELL_COUNT,repeat:false),GRID_X,GRID_Z)
    var run: ?FireRun=None
    func sync(p: Project,currentRevision: Int64): Bool {
        if (revision==currentRevision && previousPlanned==planned) { return false }
        run=None; revision=currentRevision; previousPlanned=planned
        analysis=Connectivity(fuelMask(p,planned),GRID_X,GRID_Z,
            targets:Array<Bool>(CELL_COUNT,{i => p.targets[i]!=0}),ignition:p.ignition)
        return true
    }
    func create(p: Project): FireRun {
        let next=FireRun(fuelMask(p,planned),GRID_X,GRID_Z,p.ignition,p.spreadProbability,p.burnSteps,p.seed,
            targets:Array<Bool>(CELL_COUNT,{i => p.targets[i]!=0}))
        run=Some(next); return next
    }
}
