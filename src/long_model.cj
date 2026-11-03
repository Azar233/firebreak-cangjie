package firebreak

import std.collection.ArrayList
import std.math.{ceil,sqrt}
import std.sync.Mutex

class LongSpec {
    let growth:Float64;let lightning:Float64;let warmup:Int64;let drives:Int64;let samples:Int64;let capacity:Int64
    init(growth:Float64,lightning:Float64,warmup:Int64,drives:Int64,samples:Int64,capacity:Int64){
        require(growth>=0.0 && growth<=1.0 && !growth.isNaN() && lightning>=0.0 && lightning<=1.0 && !lightning.isNaN(),"Invalid growth/lightning probability")
        require(warmup>=0 && warmup<=2048 && drives>=1 && drives<=8192 && samples>=1 && samples<=8 && capacity>=0 && capacity<=16384,"Long-study configuration exceeds resource bounds")
        this.growth=growth;this.lightning=lightning;this.warmup=warmup;this.drives=drives;this.samples=samples;this.capacity=capacity
    }
}
// Separate from single-fire step keys and density-study random domains.
func longRandom(seed:Int64,globalDrive:Int64,channel:Int64,cell:Int64):Float64 {edgeRandom(seed,1000000+globalDrive,channel,cell)}
func longCluster(state:Array<UInt8>,nx:Int64,nz:Int64,ignition:Int64,cancelled:()->Bool):Array<Int64> {
    if(state[ignition]!=1){return Array<Int64>()}
    let seen=Array<Bool>(state.size,repeat:false);let queue=ArrayList<Int64>([ignition]);seen[ignition]=true;var at:Int64=0
    while(at<queue.size){
        if(at%256==0){require(!cancelled(),"Long study cancelled")}
        let cell=queue[at];at++;for(n in neighbors(cell,nx,nz)){if(state[n]==1 && !seen[n]){seen[n]=true;queue.add(n)}}
    };return queue.toArray()
}
class LongRow {
    let sample:Int64;let seed:Int64;let policy:Int64;let globalDrive:Int64;let drive:Int64;let measured:Bool
    let grown:Int64;let alive:Int64;let lightning:Bool;let ignition:Int64;let hit:Bool;let suppressed:Bool;let effort:Int64;let burned:Int64
    init(sample:Int64,seed:Int64,policy:Int64,globalDrive:Int64,warmup:Int64,grown:Int64,alive:Int64,lightning:Bool,ignition:Int64,hit:Bool,suppressed:Bool,effort:Int64,burned:Int64){
        this.sample=sample;this.seed=seed;this.policy=policy;this.globalDrive=globalDrive;drive=globalDrive-warmup;measured=drive>0
        this.grown=grown;this.alive=alive;this.lightning=lightning;this.ignition=ignition;this.hit=hit;this.suppressed=suppressed;this.effort=effort;this.burned=burned
    }
}
class LongPairFrame {
    let drive:Int64;let states:Array<Array<UInt8>>;let burned:Array<Array<Int64>>;let rows:Array<LongRow>
    init(drive:Int64,states:Array<Array<UInt8>>,burned:Array<Array<Int64>>,rows:Array<LongRow>){
        this.drive=drive;this.states=Array<Array<UInt8>>(2,{i=>states[i].clone()});this.burned=Array<Array<Int64>>(2,{i=>burned[i].clone()});this.rows=rows.clone()
    }
}
class LongTotals {
    let sample:Int64;let policy:Int64;let density:Float64;let strikes:Int64;let misses:Int64;let fires:Int64;let large:Int64;let maximum:Int64;let burned:Int64;let suppressed:Int64;let effort:Int64
    init(sample:Int64,policy:Int64,rows:Array<LongRow>,spec:LongSpec,cells:Int64){
        this.sample=sample;this.policy=policy;var alive:Float64=0.0;var s:Int64=0;var m:Int64=0;var f:Int64=0;var l:Int64=0;var x:Int64=0;var b:Int64=0;var q:Int64=0;var e:Int64=0;var n:Int64=0
        let threshold=max(1,Int64(ceil(Float64(cells)*0.1)))
        for(r in rows){if(r.sample==sample && r.policy==policy && r.measured){
            n++;alive+=Float64(r.alive);if(r.lightning){s++;if(!r.hit){m++}};if(r.burned>0){f++};if(r.burned>=threshold){l++};x=max(x,r.burned);b+=r.burned;if(r.suppressed){q++};e+=r.effort
        }}
        require(n==spec.drives,"Incomplete measured trajectory")
        density=alive/Float64(n*cells);strikes=s;misses=m;fires=f;large=l;maximum=x;burned=b;suppressed=q;effort=e
    }
}
class LongResult {
    let source:String;let revision:Int64;let spec:LongSpec;let rows:Array<LongRow>;let frames:Array<LongPairFrame>;let totals:Array<LongTotals>
    let trace:Array<Array<Float64>>;let histogram:Array<Array<Int64>>
    init(source:String,revision:Int64,spec:LongSpec,rows:Array<LongRow>,frames:Array<LongPairFrame>){
        this.source=source;this.revision=revision;this.spec=spec;this.rows=rows;this.frames=frames
        let p=readProjectText(source);totals=Array<LongTotals>(spec.samples*2,{i=>LongTotals(i/2,i%2,rows,spec,p.cells)})
        trace=Array<Array<Float64>>(2,{policy=>Array<Float64>(spec.drives,{i=>Float64(rows[(spec.warmup+i)*2+policy].alive)/Float64(p.cells)})})
        var bins:Int64=1;var bound:Int64=2;while(bound<=p.cells){bins++;bound*=2}
        let binCount=bins;histogram=Array<Array<Int64>>(2,{_=>Array<Int64>(binCount,repeat:0)})
        for(row in rows){if(row.measured && row.burned>0){var bin:Int64=0;var n=row.burned;while(n>=2){bin++;n/=2};histogram[row.policy][bin]++}}
    }
    func sum(policy:Int64,metric:Int64):Int64 {
        var n:Int64=0;for(t in totals){if(t.policy==policy){n+=match(metric){case 0=>t.burned;case 1=>t.large;case 2=>t.strikes;case 3=>t.suppressed;case 4=>t.effort;case _=>t.misses}}};return n
    }
    func meanDensity(policy:Int64):Float64 {var value:Float64=0.0;for(t in totals){if(t.policy==policy){value+=t.density}};return value/Float64(spec.samples)}
    func maximum(policy:Int64):Int64 {var n:Int64=0;for(t in totals){if(t.policy==policy){n=max(n,t.maximum)}};return n}
    func pairedLargeSE():Float64 {
        require(spec.samples>1,"At least two seeds are required for standard error")
        var sum:Float64=0.0;var square:Float64=0.0
        for(i in 0..spec.samples){let d=Float64(totals[i*2+1].large-totals[i*2].large)/Float64(spec.drives);sum+=d;square+=d*d}
        return sqrt(max(0.0,(square-sum*sum/Float64(spec.samples))/Float64(spec.samples-1))/Float64(spec.samples))
    }
}
class LongProgress {
    let completed:Int64;let total:Int64;let done:Bool;let cancelled:Bool;let error:String;let result:?LongResult
    init(completed:Int64,total:Int64,done:Bool,cancelled:Bool,error:String,result:?LongResult){this.completed=completed;this.total=total;this.done=done;this.cancelled=cancelled;this.error=error;this.result=result}
}
class LongJob {
    let source:String;let revision:Int64;let spec:LongSpec;let lock=Mutex()
    var completed:Int64=0;var done=false;var cancelled=false;var error="";var result:?LongResult=None
    init(p:Project,revision:Int64,spec:LongSpec){
        p.validate();var eligible:Int64=0;for(i in 0..p.cells){if(p.land[i]==1 && p.treatment[i]==0){eligible++}}
        require(eligible>0,"没有可生长林地，请先建立森林");source=p.text();this.revision=revision;this.spec=spec
    }
    func cancel():Unit {synchronized(lock){cancelled=true}}
    func isCancelled():Bool {synchronized(lock){return cancelled}}
    func progress():LongProgress {synchronized(lock){return LongProgress(completed,(spec.warmup+spec.drives)*spec.samples,done,cancelled,error,result)}}
    func start():Unit {spawn{execute()}}
    func execute():Unit {
        try{
            let p=readProjectText(source);let rows=ArrayList<LongRow>();let frames=ArrayList<LongPairFrame>()
            let eligible=Array<Bool>(p.cells,{i=>p.land[i]==1 && p.treatment[i]==0})
            let stride=max(1,(spec.drives+127)/128)
            for(sample in 0..spec.samples){
                let seed=studySeed(p.seed,sample)
                let states=Array<Array<UInt8>>(2,{_=>Array<UInt8>(p.cells,{i=>if(p.fuel(i,planned:true)>0.0){UInt8(1)}else{UInt8(0)}})})
                let alive=Array<Int64>(2,repeat:0);for(i in 0..p.cells){if(states[0][i]==1){alive[0]++;alive[1]++}}
                let startRows=Array<LongRow>(2,{policy=>LongRow(sample,seed,policy,spec.warmup,spec.warmup,0,alive[policy],false,-1,false,false,0,0)})
                if(sample==0 && spec.warmup==0){frames.add(LongPairFrame(0,states,[Array<Int64>(),Array<Int64>()],startRows))}
                var pending:?LongPairFrame=None
                for(global in 1..spec.warmup+spec.drives+1){
                    require(!isCancelled(),"Long study cancelled")
                    let beforeGrowth0=alive[0];let beforeGrowth1=alive[1]
                    for(i in 0..p.cells){if(eligible[i] && (states[0][i]!=1 || states[1][i]!=1) && longRandom(seed,global,0,i)<spec.growth){for(policy in 0..2){if(states[policy][i]!=1){states[policy][i]=1;alive[policy]++}}}}
                    let grown=[alive[0]-beforeGrowth0,alive[1]-beforeGrowth1]
                    let lightning=longRandom(seed,global,1,0)<spec.lightning
                    let ignition=if(lightning){Int64(longRandom(seed,global,2,0)*Float64(p.cells))}else{-1}
                    let pairRows=ArrayList<LongRow>();let burns=Array<Array<Int64>>(2,{_=>Array<Int64>()})
                    for(policy in 0..2){
                        let cluster=if(lightning){longCluster(states[policy],p.nx,p.nz,ignition,{=>isCancelled()})}else{Array<Int64>()}
                        let suppress=policy==1 && !cluster.isEmpty() && cluster.size<=spec.capacity
                        if(!suppress){burns[policy]=cluster;for(i in cluster){states[policy][i]=2};alive[policy]-=cluster.size}
                        let row=LongRow(sample,seed,policy,global,spec.warmup,grown[policy],alive[policy],lightning,ignition,!cluster.isEmpty(),suppress,if(suppress){cluster.size}else{0},burns[policy].size)
                        pairRows.add(row);rows.add(row)
                    }
                    if(sample==0){
                        let drive=global-spec.warmup
                        if(drive==0){frames.add(LongPairFrame(0,states,[Array<Int64>(),Array<Int64>()],pairRows.toArray()))}
                        if(drive>0){
                            if(lightning){pending=Some(LongPairFrame(drive,states,burns,pairRows.toArray()))}
                            if(drive%stride==0){frames.add(pending ?? LongPairFrame(drive,states,burns,pairRows.toArray()));pending=None}
                            if(drive==spec.drives && frames[frames.size-1].drive!=drive){frames.add(LongPairFrame(drive,states,burns,pairRows.toArray()))}
                        }
                    }
                    synchronized(lock){completed++}
                }
            }
            let completedResult=LongResult(source,revision,spec,rows.toArray(),frames.toArray())
            synchronized(lock){if(!cancelled){result=Some(completedResult)};done=true}
        }catch(e:Exception){synchronized(lock){error=e.message;done=true}}
    }
}
