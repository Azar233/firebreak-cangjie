package firebreak

import std.collection.ArrayList
import std.math.sqrt
import std.sync.Mutex

let STUDY_DENSITIES=Array<Float64>(21,{i=>Float64(i)/20.0})
// Separate semantic random domains from every reachable fire step (<= cells*8).
let STUDY_OCCUPANCY_STEP:Int64=2147483647
let STUDY_IGNITION_STEP:Int64=2147483646
let STUDY_POLICY_STEP:Int64=2147483645
func studySeed(base:Int64,index:Int64):Int64 {(base+index*104729)%2147483648}
func studyIgnition(p:Project):Int64 {Int64(edgeRandom(p.seed,STUDY_IGNITION_STEP,193,0)*Float64(p.cells))}
func densityForest(base:Project,probability:Float64,seed:Int64):Project {
    require(probability>=0.0 && probability<=1.0 && !probability.isNaN() && seed>=0 && seed<=2147483647,"Invalid forest sampling parameters")
    let p=base.copy();p.seed=seed;p.ignition = -1
    p.treatment=Array<Int64>(p.cells,repeat:0)
    p.vegetation=Array<Int64>(p.cells,{i=>if(p.land[i]==1 && edgeRandom(seed,STUDY_OCCUPANCY_STEP,9176,i)<probability){1}else{0}})
    p.source="Independent site sampling p="+numberText(probability)+" seed=${seed}; open four-neighbor grid"
    return p
}
func wilsonInterval(hits:Int64,n:Int64):Array<Float64> {
    require(n>0 && hits>=0 && hits<=n,"Invalid binomial counts")
    let z=1.959963984540054;let nn=Float64(n);let q=Float64(hits)/nn;let denominator=1.0+z*z/nn
    let center=(q+z*z/(2.0*nn))/denominator
    let radius=z*sqrt(q*(1.0-q)/nn+z*z/(4.0*nn*nn))/denominator
    return [max(0.0,center-radius),min(1.0,center+radius)]
}
class DensitySample {
    let probability:Float64;let seed:Int64;let occupied:Int64;let largest:Int64;let spanning:Bool
    init(probability:Float64,seed:Int64,graph:Connectivity,nx:Int64,nz:Int64){
        this.probability=probability;this.seed=seed;occupied=graph.total;largest=graph.largest;spanning=graph.spansLeftRight(nx,nz)
    }
}
class DensityPoint {
    let probability:Float64;let count:Int64;let hits:Int64;let occupied:Float64;let largest:Float64;let interval:Array<Float64>
    init(probability:Float64,rows:Array<DensitySample>){
        this.probability=probability;count=rows.size;var h:Int64=0;var o:Float64=0.0;var l:Float64=0.0
        for(r in rows){if(r.spanning){h++};o+=Float64(r.occupied);l+=Float64(r.largest)}
        hits=h;occupied=o/Float64(count);largest=l/Float64(count);interval=wilsonInterval(hits,count)
    }
    func frequency():Float64 {Float64(hits)/Float64(count)}
}
class DensityResult {
    let source:String;let revision:Int64;let samples:Int64;let points:Array<DensityPoint>;let rows:Array<DensitySample>
    init(source:String,revision:Int64,samples:Int64,points:Array<DensityPoint>,rows:Array<DensitySample>){
        this.source=source;this.revision=revision;this.samples=samples;this.points=points;this.rows=rows
    }
    func sample(point:Int64,index:Int64):Project {
        require(point>=0 && point<points.size && index>=0 && index<samples,"Invalid density preview selection")
        let base=readProjectText(source);return densityForest(base,points[point].probability,studySeed(base.seed,index))
    }
    func bracket():Array<Float64> {
        for(i in 1..points.size){if(points[i-1].frequency()<0.5 && points[i].frequency()>=0.5){return [points[i-1].probability,points[i].probability]}}
        return Array<Float64>()
    }
}
class StudyProgress {
    let completed:Int64;let total:Int64;let done:Bool;let cancelled:Bool;let error:String
    let density:?DensityResult;let interventions:?InterventionResult
    init(completed:Int64,total:Int64,done:Bool,cancelled:Bool,error:String,density:?DensityResult,interventions:?InterventionResult){
        this.completed=completed;this.total=total;this.done=done;this.cancelled=cancelled;this.error=error;this.density=density;this.interventions=interventions
    }
}
class ForestStudyJob {
    let source:String;let revision:Int64;let samples:Int64;let dose:Int64;let mode:Int64;let probability:Float64
    let lock=Mutex();var completed:Int64=0;var done=false;var cancelled=false;var error=""
    var density:?DensityResult=None;var interventions:?InterventionResult=None
    init(p:Project,revision:Int64,samples:Int64,mode!:Int64=0,probability!:Float64=0.6,dose!:Int64=16){
        p.validate();require(samples>=2 && samples<=64 && (mode==0 || mode==1),"Invalid study configuration")
        require(probability>=0.0 && probability<=1.0 && !probability.isNaN() && dose>=1 && dose<=128,"Invalid intervention configuration")
        var eligible:Int64=0;for(v in p.land){if(v==1){eligible++}};require(eligible>0,"没有可生长林地，请先建立森林")
        source=p.text();this.revision=revision;this.samples=samples;this.mode=mode;this.probability=probability;this.dose=dose
    }
    func cancel():Unit {synchronized(lock){cancelled=true}}
    func isCancelled():Bool {synchronized(lock){return cancelled}}
    func start():Unit {spawn{execute()}}
    func progress():StudyProgress {synchronized(lock){return StudyProgress(completed,if(mode==0){samples*STUDY_DENSITIES.size}else{samples},done,cancelled,error,density,interventions)}}
    func execute():Unit {
        try{
            let base=readProjectText(source)
            if(mode==0){
                let points=ArrayList<DensityPoint>();let rows=ArrayList<DensitySample>()
                for(probability in STUDY_DENSITIES){
                    let group=ArrayList<DensitySample>()
                    for(index in 0..samples){
                        if(isCancelled()){synchronized(lock){done=true};return}
                        let p=densityForest(base,probability,studySeed(base.seed,index));let graph=Connectivity(fuelMask(p,false),p.nx,p.nz)
                        let sample=DensitySample(probability,p.seed,graph,p.nx,p.nz);group.add(sample);rows.add(sample)
                        synchronized(lock){completed++}
                    }
                    points.add(DensityPoint(probability,group.toArray()))
                }
                synchronized(lock){if(!cancelled){density=Some(DensityResult(source,revision,samples,points.toArray(),rows.toArray()))};done=true}
            }else{
                let rows=ArrayList<InterventionSample>()
                for(index in 0..samples){
                    if(isCancelled()){synchronized(lock){done=true};return}
                    let p=densityForest(base,probability,studySeed(base.seed,index))
                    let ignition=studyIgnition(p)
                    for(strategy in 0..4){
                        if(isCancelled()){synchronized(lock){done=true};return}
                        let candidate=if(strategy==0){p}else{interveneForest(p,dose,strategy,{=>isCancelled()})}
                        let fuel=fuelMask(candidate,true)
                        let run=FireRun(fuel,p.nx,p.nz,ignition,p.spreadProbability,p.burnSteps,p.seed,allowBlockedIgnition:true,keepHistory:false)
                        while(run.current().burning()>0){if(isCancelled()){synchronized(lock){done=true};return};run.advance()}
                        let graph=Connectivity(fuel,p.nx,p.nz)
                        rows.add(InterventionSample(index,strategy,p.seed,ignition,candidate,run,graph))
                    }
                    synchronized(lock){completed++}
                }
                synchronized(lock){if(!cancelled){interventions=Some(InterventionResult(source,revision,probability,samples,dose,rows.toArray()))};done=true}
            }
        }catch(e:Exception){synchronized(lock){error=e.message;done=true}}
    }
}
