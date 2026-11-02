package firebreak

import std.collection.ArrayList
import std.sync.Mutex

class PlanCandidate {
    let id: Int64
    let kind: Int64 // 1 road-adjacent strip, 2 target perimeter, 3 articulation cell
    let treatment: Array<Int64>
    let added: Array<Int64>
    let cost: Float64
    let deltaCost: Float64
    init(id: Int64,kind: Int64,p: Project,mask: Array<Int64>) {
        let next=p.copy(); next.treatment=mask.clone(); next.validate()
        let cells=ArrayList<Int64>()
        for (i in 0..CELL_COUNT) {
            require(p.treatment[i]==0 || p.treatment[i]==mask[i],"候选不能覆盖已有处理方案")
            if (p.treatment[i]==0 && mask[i]!=0) { cells.add(i) }
        }
        require(!cells.isEmpty(),"候选没有新增处理格")
        this.id=id; this.kind=kind; treatment=mask.clone(); added=cells.toArray()
        cost=next.cost(); deltaCost=cost-p.cost()
    }
    func project(p: Project): Project { let next=p.copy(); next.treatment=treatment.clone(); next.validate(); return next }
}
func addCandidate(result: ArrayList<PlanCandidate>,p: Project,cells: Array<Int64>,kind: Int64,typeId: Int64): Unit {
    let mask=p.treatment.clone()
    for (i in cells) { if (p.land[i]==1 && mask[i]==0) { mask[i]=typeId } }
    for (c in result) { if (c.treatment==mask) { return } }
    // Invalid geometric candidates are rejected in full, never silently truncated to fit budget/exclusions.
    try { result.add(PlanCandidate(result.size,kind,p,mask)) } catch(_: Exception) { () }
}
func generateCandidates(p: Project,cancelled: ()->Bool): Array<PlanCandidate> {
    p.validate(); require(p.metersWide>0.0,"请先标定场地宽度再生成建议")
    let result=ArrayList<PlanCandidate>(); var roadCount: Int64=0
    for (axis in 0..2) {
        let count=if (axis==0) { GRID_Z } else { GRID_X }
        for (line in 0..count) {
            if (cancelled()) { return result.toArray() }
            let cells=ArrayList<Int64>()
            for (i in 0..CELL_COUNT) {
                if ((if (axis==0) { i/GRID_X } else { i%GRID_X })!=line || p.fuel(i,planned:true)==0.0) { continue }
                for (n in neighbors(i,GRID_X,GRID_Z)) { if (p.land[n]==2) { cells.add(i); break } }
            }
            let before=result.size
            if (roadCount<8) { addCandidate(result,p,cells.toArray(),1,2) }
            if (result.size>before) { roadCount++ }
        }
    }
    for (radius in 1..3) {
        let cells=ArrayList<Int64>()
        for (i in 0..CELL_COUNT) {
            if (p.targets[i]!=0 || p.fuel(i,planned:true)==0.0) { continue }
            for (j in 0..CELL_COUNT) {
                if (p.targets[j]==0) { continue }
                let dx=if (i%GRID_X>j%GRID_X) { i%GRID_X-j%GRID_X } else { j%GRID_X-i%GRID_X }
                let dz=if (i/GRID_X>j/GRID_X) { i/GRID_X-j/GRID_X } else { j/GRID_X-i/GRID_X }
                if (dx+dz<=radius) { cells.add(i); break }
            }
        }
        addCandidate(result,p,cells.toArray(),2,2)
    }
    let fuel=fuelMask(p,true); let before=Connectivity(fuel,GRID_X,GRID_Z)
    let bridgeCells=ArrayList<Int64>(); let bridgeGains=ArrayList<Int64>()
    for (i in 0..CELL_COUNT) {
        if (cancelled()) { return result.toArray() }
        if (!fuel[i] || p.targets[i]!=0 || p.forbidden[i]!=0) { continue }
        fuel[i]=false; let after=Connectivity(fuel,GRID_X,GRID_Z); fuel[i]=true
        if (after.sizes.size>before.sizes.size) {
            let gain=before.largest-after.largest; var at: Int64=0
            while (at<bridgeGains.size && bridgeGains[at]>=gain) { at++ }
            bridgeCells.add(i,at:at); bridgeGains.add(gain,at:at)
        }
    }
    for (i in 0..min(4,bridgeCells.size)) { addCandidate(result,p,[bridgeCells[i]],3,1) }
    return result.toArray()
}
func reviewScenarios(p: Project,count: Int64): Array<Scenario> {
    require(count>=1 && count<=64,"评估样本数须为 1 至 64")
    let cells=ArrayList<Int64>(); for (i in 0..CELL_COUNT) { if (p.fuel(i)>0.0) { cells.add(i) } }
    require(!cells.isEmpty(),"原始场地没有可燃林地，无法生成起火情景")
    let sites=ArrayList<Int64>()
    for (q in 0..4) { let cell=cells[(2*q+1)*(cells.size-1)/8]; if (!sites.contains(cell)) { sites.add(cell) } }
    return Array<Scenario>(count,{i => Scenario(i,sites[i%sites.size],(p.seed+104729+i/sites.size)%2147483648,1.0/Float64(count))})
}
class PlanAssessment {
    let rows: Array<PairedOutcome>
    init(rows: Array<PairedOutcome>) { require(!rows.isEmpty(),"缺少完整候选评估"); this.rows=rows }
    func mean(metric: Int64): Float64 {
        var total=0.0; var weights=0.0
        for (r in rows) {
            let n=match(metric) { case 0=>r.planned.burned; case 1=>r.planned.remaining; case _=>r.planned.contacts }
            total+=Float64(n)*r.scenario.weight; weights+=r.scenario.weight
        }; return total/weights
    }
}
func planImproves(current: PlanAssessment,next: PlanAssessment): Bool {
    let contacts=current.mean(2)-next.mean(2); let forest=next.mean(1)-current.mean(1)
    return contacts>= -1.0e-9 && forest>= -1.0e-9 && (contacts>1.0e-9 || forest>1.0e-9)
}
class PlanEntry {
    let candidate: PlanCandidate
    let training: PlanAssessment
    let review: PlanAssessment
    let score: Float64
    let eligible: Bool
    let verified: Bool
    init(candidate: PlanCandidate,training: PlanAssessment,review: PlanAssessment,current: PlanAssessment,heldout: PlanAssessment) {
        this.candidate=candidate; this.training=training; this.review=review
        eligible=planImproves(current,training); verified=planImproves(heldout,review)
        score=((current.mean(2)-training.mean(2))*Float64(CELL_COUNT+1)+training.mean(1)-current.mean(1))/max(1.0,candidate.deltaCost)
    }
}
class PlanSearchResult {
    let source: String
    let revision: Int64
    let current: PlanAssessment
    let heldout: PlanAssessment
    let entries: Array<PlanEntry>
    let selected: Int64
    let recommended: Int64
    init(source: String,revision: Int64,current: PlanAssessment,heldout: PlanAssessment,entries: Array<PlanEntry>,selected: Int64) {
        this.source=source; this.revision=revision; this.current=current; this.heldout=heldout; this.entries=entries; this.selected=selected
        // Choose using training only. Holdout may reject that choice, never select a different winner.
        recommended=if (selected>=0 && entries[selected].verified) { selected } else { -1 }
    }
}
class PlanSearchProgress {
    let completed: Int64
    let total: Int64
    let done: Bool
    let cancelled: Bool
    let error: String
    let result: ?PlanSearchResult
    init(completed: Int64,total: Int64,done: Bool,cancelled: Bool,error: String,result: ?PlanSearchResult) {
        this.completed=completed; this.total=total; this.done=done; this.cancelled=cancelled; this.error=error; this.result=result
    }
}
class PlanSearchJob {
    let abort:()->Bool
    let source: String
    let revision: Int64
    let training: Array<Scenario>
    let review: Array<Scenario>
    let lock=Mutex()
    var active: ?EvaluationJob=None
    var completed: Int64=0
    var total: Int64=0
    var done=false
    var cancelled=false
    var error=""
    var result: ?PlanSearchResult=None
    init(p: Project,revision: Int64,abort!:()->Bool={=>false}) {
        this.abort=abort
        p.validate(); require(p.metersWide>0.0,"请先标定场地宽度再生成建议")
        source=p.text(); this.revision=revision; training=makeScenarios(p,8); review=reviewScenarios(p,8)
    }
    func isCancelled(): Bool { synchronized(lock) { return cancelled || abort() } }
    func cancel(): Unit { synchronized(lock) { cancelled=true; if (let Some(job) <- active) { job.cancel() } } }
    func progress(): PlanSearchProgress { synchronized(lock) { return PlanSearchProgress(completed,total,done,cancelled,error,result) } }
    func assess(p: Project,scenarios: Array<Scenario>): PlanAssessment {
        let job=EvaluationJob(p,revision,scenarios,keepReplay:false)
        synchronized(lock) { active=Some(job); if (cancelled) { job.cancel() } }
        job.execute(); let state=job.progress()
        require(!state.cancelled && state.result.isSome(),if (state.error.isEmpty()) { "候选搜索已取消" } else { state.error })
        synchronized(lock) { active=None; completed++ }
        return PlanAssessment(state.result.getOrThrow().rows)
    }
    func start(): Unit { spawn { execute() } }
    func execute(): Unit {
        try {
            let p=readProjectText(source); let candidates=generateCandidates(p,{=>isCancelled()})
            synchronized(lock) { total=2+candidates.size*2 }
            if (isCancelled()) { synchronized(lock) { done=true }; return }
            let current=assess(p,training); let heldout=assess(p,review); let entries=ArrayList<PlanEntry>()
            for (c in candidates) {
                if (isCancelled()) { break }
                let next=c.project(p); let train=assess(next,training); let check=assess(next,review)
                let entry=PlanEntry(c,train,check,current,heldout); var at: Int64=0
                while (at<entries.size && (entries[at].score>entry.score ||
                    (entries[at].score==entry.score && entries[at].candidate.deltaCost<=entry.candidate.deltaCost))) { at++ }
                entries.add(entry,at:at)
            }
            var selected: Int64 = -1
            for (i in 0..entries.size) { if (entries[i].eligible) { selected=i; break } }
            synchronized(lock) {
                if (!cancelled) { result=Some(PlanSearchResult(source,revision,current,heldout,entries.toArray(),selected)) }
                active=None; done=true
            }
        } catch(e: Exception) { synchronized(lock) { active=None; if (!cancelled) { error=e.message }; done=true } }
    }
}
