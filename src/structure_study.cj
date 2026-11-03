package firebreak

import std.math.{abs,sqrt}

func interveneForest(base:Project,dose:Int64,strategy:Int64,cancelled:()->Bool):Project {
    require(strategy>=1 && strategy<=3 && dose>=1 && dose<=128,"Invalid clearing policy")
    let p=base.copy()
    // The study controls effort in cells, independent of physical prices/calibration.
    // Applying a preview restores and validates the workspace's financial fields.
    p.clearingPrice=0.0;p.breakPrice=0.0;p.budget=1.0e9
    if(p.metersWide==0.0){p.metersWide=Float64(p.nx)*5.0}
    let fuel=fuelMask(p,true);let score=Array<Float64>(p.cells,repeat:-1.0e30)
    let gains=if(strategy==2){articulationGains(fuel,p.nx,p.nz,Connectivity(fuel,p.nx,p.nz),cancelled)}else{Array<Int64>()}
    var eligible:Int64=0
    for(i in 0..p.cells){if(fuel[i] && p.targets[i]==0 && p.forbidden[i]==0){
        eligible++;let tie=edgeRandom(p.seed,STUDY_POLICY_STEP,strategy,i)
        if(strategy==1){score[i]=tie}
        else if(strategy==2){
            var degree:Int64=0;for(n in neighbors(i,p.nx,p.nz)){if(fuel[n]){degree++}}
            score[i]=Float64(if(gains[i]>=0){gains[i]*8+8+degree}else{degree})+tie*0.01
        }else{score[i]= -Float64(abs(i%p.nx-p.nx/2)*(p.cells+1)+abs(i/p.nx-p.nz/2))+tie*0.01}
    }}
    require(eligible>=dose,"可处理植被不足，无法执行相同清理格数；请降低清理量或提高密度")
    for(_ in 0..dose){
        require(!cancelled(),"Study cancelled")
        var best:Int64 = -1;var value:Float64= -1.0e30
        for(i in 0..p.cells){if(score[i]>value){value=score[i];best=i}}
        require(best>=0,"No eligible clearing cell");p.treatment[best]=1;score[best]= -1.0e30
    }
    p.validate();return p
}
class InterventionSample {
    let sample:Int64;let strategy:Int64;let seed:Int64;let ignition:Int64;let original:Int64;let cleared:Int64;let burned:Int64;let remaining:Int64;let largest:Int64;let spanning:Bool;let blocked:Bool
    init(sample:Int64,strategy:Int64,seed:Int64,ignition:Int64,p:Project,run:FireRun,graph:Connectivity){
        this.sample=sample;this.strategy=strategy;this.seed=seed;this.ignition=ignition
        var n:Int64=0;for(i in 0..p.cells){if(p.fuel(i)>0.0){n++}};original=n
        cleared=p.count(p.treatment);burned=run.current().burned();remaining=original-cleared-burned
        require(remaining>=0 && original==cleared+burned+remaining,"Study metrics do not conserve forest")
        largest=graph.largest;spanning=graph.spansLeftRight(p.nx,p.nz);blocked = !run.fuel[ignition]
    }
}
class InterventionResult {
    let source:String;let revision:Int64;let probability:Float64;let samples:Int64;let dose:Int64;let rows:Array<InterventionSample>
    init(source:String,revision:Int64,probability:Float64,samples:Int64,dose:Int64,rows:Array<InterventionSample>){
        this.source=source;this.revision=revision;this.probability=probability;this.samples=samples;this.dose=dose;this.rows=rows
    }
    func mean(strategy:Int64,metric:Int64):Float64 {
        var total:Float64=0.0;var count:Int64=0
        for(r in rows){if(r.strategy==strategy){count++;total+=Float64(match(metric){case 0=>r.burned;case 1=>r.remaining;case 2=>r.largest;case _=>if(r.spanning){1}else{0}})}}
        require(count==samples,"Incomplete policy results");return total/Float64(count)
    }
    func preview(index:Int64,strategy:Int64):Project {
        require(index>=0 && index<samples && strategy>=0 && strategy<=3,"Invalid policy preview")
        let base=readProjectText(source);let p=densityForest(base,probability,studySeed(base.seed,index))
        p.ignition=studyIgnition(p)
        return if(strategy==0){p}else{interveneForest(p,dose,strategy,{=>false})}
    }
    func burnDeltaSE(strategy:Int64):Float64 {
        var sum:Float64=0.0;var square:Float64=0.0
        for(index in 0..samples){let delta=Float64(rows[index*4+strategy].burned-rows[index*4].burned);sum+=delta;square+=delta*delta}
        return sqrt(max(0.0,(square-sum*sum/Float64(samples))/Float64(samples-1))/Float64(samples))
    }
}
