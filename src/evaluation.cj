package firebreak

import std.collection.ArrayList
import std.sync.Mutex

class Scenario {
    let id: Int64
    let ignition: Int64
    let seed: Int64
    let weight: Float64
    let wind="none"
    let ruleVersion: Int64=1
    init(id: Int64,ignition: Int64,seed: Int64,weight: Float64) {
        require(id>=0 && ignition>=0 && ignition<16384 && seed>=0 && seed<=2147483647 &&
            weight>0.0 && weight<=1.0 && !weight.isNaN(),"非法评估情景")
        this.id=id; this.ignition=ignition; this.seed=seed; this.weight=weight
    }
}
func makeScenarios(p: Project,count: Int64): Array<Scenario> {
    require(count>=1 && count<=64,"评估样本数须为 1 至 64")
    let fuel=ArrayList<Int64>(); for (i in 0..p.cells) { if (p.fuel(i)>0.0) { fuel.add(i) } }
    require(!fuel.isEmpty(),"原始场地没有可燃林地，无法生成起火情景")
    let sites=ArrayList<Int64>()
    if (p.ignition>=0 && p.fuel(p.ignition)>0.0) { sites.add(p.ignition) }
    for (q in 0..4) {
        let cell=fuel[(fuel.size-1)*q/3]
        if (!sites.contains(cell) && sites.size<4) { sites.add(cell) }
    }
    return Array<Scenario>(count,{i => Scenario(i,sites[i%sites.size],(p.seed+i/sites.size)%2147483648,1.0/Float64(count))})
}
class Outcome {
    let burned: Int64
    let cleared: Int64
    let remaining: Int64
    let contacts: Int64
    let steps: Int64
    let ignitionBlocked: Bool
    init(p: Project,run: FireRun,planned: Bool,ignition: Int64) {
        burned=run.current().burned(); cleared=if (planned) { p.count(p.treatment) } else { 0 }
        var original: Int64=0; for (i in 0..p.cells) { if (p.fuel(i)>0.0) { original++ } }
        remaining=original-cleared-burned; contacts=run.current().contacts(); steps=run.current().step
        ignitionBlocked = !run.fuel[ignition]
        require(remaining>=0 && burned+cleared+remaining==original,"评估指标不守恒")
    }
}
class PairedOutcome {
    let scenario: Scenario
    let baseline: Outcome
    let planned: Outcome
    init(scenario: Scenario,baseline: Outcome,planned: Outcome) { this.scenario=scenario; this.baseline=baseline; this.planned=planned }
}
class EvaluationResult {
    let candidatePreview: Bool
    let projectText: String
    let revision: Int64
    let rows: Array<PairedOutcome>
    let baselineReplay: FireRun
    let plannedReplay: FireRun
    init(projectText: String,revision: Int64,rows: Array<PairedOutcome>,baselineReplay: FireRun,plannedReplay: FireRun,candidatePreview!: Bool=false) {
        this.candidatePreview=candidatePreview
        this.projectText=projectText; this.revision=revision; this.rows=rows
        this.baselineReplay=baselineReplay; this.plannedReplay=plannedReplay
    }
    func mean(planned: Bool,metric: Int64): Float64 {
        var total=0.0; var weights=0.0
        for (row in rows) {
            let value=if (planned) { row.planned } else { row.baseline }
            let n=match(metric) { case 0=>value.burned; case 1=>value.remaining; case 2=>value.contacts; case _=>value.cleared }
            total+=Float64(n)*row.scenario.weight; weights+=row.scenario.weight
        }; return total/weights
    }
    func exposedSamples(planned: Bool): Int64 {
        var n: Int64=0
        for (row in rows) { if ((if (planned) { row.planned.contacts } else { row.baseline.contacts })>0) { n++ } }; return n
    }
    func worseSamples(): Int64 {
        var n: Int64=0; for (r in rows) { if (r.planned.burned>r.baseline.burned || r.planned.contacts>r.baseline.contacts) { n++ } }; return n
    }
}
class EvaluationProgress {
    let completed: Int64
    let total: Int64
    let done: Bool
    let cancelled: Bool
    let error: String
    let result: ?EvaluationResult
    init(completed: Int64,total: Int64,done: Bool,cancelled: Bool,error: String,result: ?EvaluationResult) {
        this.completed=completed; this.total=total; this.done=done; this.cancelled=cancelled; this.error=error; this.result=result
    }
}
class EvaluationJob {
    let keepReplay: Bool
    let candidatePreview: Bool
    let projectText: String
    let revision: Int64
    let scenarios: Array<Scenario>
    let lock=Mutex()
    var completed: Int64=0
    var done=false
    var cancelled=false
    var error=""
    var result: ?EvaluationResult=None
    init(p: Project,revision: Int64,scenarios: Array<Scenario>,keepReplay!: Bool=true,candidatePreview!: Bool=false) {
        this.keepReplay=keepReplay; this.candidatePreview=candidatePreview
        p.validate(); require(scenarios.size>=1 && scenarios.size<=64,"情景集合不能为空或超过 64")
        let ids=ArrayList<Int64>()
        for (s in scenarios) { require(s.ignition<p.cells && p.fuel(s.ignition)>0.0 && !ids.contains(s.id),"情景起火点不可燃或 id 重复"); ids.add(s.id) }
        projectText=p.text(); this.revision=revision; this.scenarios=scenarios.clone()
    }
    func cancel(): Unit { synchronized(lock) { cancelled=true } }
    func isCancelled(): Bool { synchronized(lock) { return cancelled } }
    func progress(): EvaluationProgress {
        synchronized(lock) { return EvaluationProgress(completed,scenarios.size,done,cancelled,error,result) }
    }
    func start(): Unit { spawn { execute() } }
    func execute(): Unit {
        try {
            let p=readProjectText(projectText); let baseFuel=fuelMask(p,false); let planFuel=fuelMask(p,true)
            let targets=Array<Bool>(p.cells,{i => p.targets[i]!=0}); let rows=ArrayList<PairedOutcome>()
            var baselineReplay: ?FireRun=None; var plannedReplay: ?FireRun=None
            for (i in 0..scenarios.size) {
                if (isCancelled()) { break }
                let s=scenarios[i]
                let baseline=FireRun(baseFuel,p.nx,p.nz,s.ignition,p.spreadProbability,p.burnSteps,s.seed,targets:targets,keepHistory:i==0 && keepReplay)
                let planned=FireRun(planFuel,p.nx,p.nz,s.ignition,p.spreadProbability,p.burnSteps,s.seed,targets:targets,allowBlockedIgnition:true,keepHistory:i==0 && keepReplay)
                while (baseline.current().burning()>0 || planned.current().burning()>0) {
                    if (isCancelled()) { break }
                    baseline.advance(); planned.advance()
                }
                if (isCancelled()) { break }
                rows.add(PairedOutcome(s,Outcome(p,baseline,false,s.ignition),Outcome(p,planned,true,s.ignition)))
                if (i==0) { baselineReplay=Some(baseline); plannedReplay=Some(planned) }
                synchronized(lock) { completed=rows.size }
            }
            synchronized(lock) {
                if (!cancelled) { result=Some(EvaluationResult(projectText,revision,rows.toArray(),baselineReplay.getOrThrow(),plannedReplay.getOrThrow(),candidatePreview:candidatePreview)) }
                done=true
            }
        } catch(e: Exception) { synchronized(lock) { error=e.message; done=true } }
    }
}
