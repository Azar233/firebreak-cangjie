package firebreak

import std.collection.ArrayList

// Version 1: isotropic four-neighbor synchronous spread. A draw is keyed by a
// directed edge and step, so evaluating a different plan cannot shift a stream.
// UInt64 products of two 32-bit factors fit before the explicit 32-bit mask.
func edgeRandom(seed: Int64,step: Int64,from: Int64,to: Int64): Float64 {
    var h=(UInt64(seed)^UInt64(0x9e3779b9))&UInt64(0xffffffff)
    for (key in [step,from,to]) {
        h=h^UInt64(key+1)
        h=((h^(h>>16))*UInt64(0x85ebca6b))&UInt64(0xffffffff)
        h=((h^(h>>13))*UInt64(0xc2b2ae35))&UInt64(0xffffffff)
        h=(h^(h>>16))&UInt64(0xffffffff)
    }
    return Float64(h)/4294967296.0
}
class FireSnapshot {
    // 0 unburned/non-fuel (see frozen fuel mask); positive remaining burn steps;
    // -1 burned out. Exposure is cumulative contact with a target's 4-neighborhood.
    let age: Array<Int64>
    let exposed: Array<Bool>
    let step: Int64
    init(age: Array<Int64>,exposed: Array<Bool>,step: Int64) { this.age=age; this.exposed=exposed; this.step=step }
    func burning(): Int64 { var n: Int64=0; for (v in age) { if (v>0) { n++ } }; return n }
    func burned(): Int64 { var n: Int64=0; for (v in age) { if (v<0) { n++ } }; return n }
    func contacts(): Int64 { var n: Int64=0; for (v in exposed) { if (v) { n++ } }; return n }
}
class FireRun {
    let fuel: Array<Bool>
    let targets: Array<Bool>
    let nx: Int64
    let nz: Int64
    let probability: Float64
    let duration: Int64
    let seed: Int64
    let keepHistory: Bool
    let snapshots=ArrayList<FireSnapshot>()
    var cursor: Int64=0
    var running=false
    var nextTick: UInt64=0
    init(fuel: Array<Bool>,nx: Int64,nz: Int64,ignition: Int64,probability: Float64,duration: Int64,seed: Int64,
        targets!: Array<Bool>=Array<Bool>(),allowBlockedIgnition!: Bool=false,keepHistory!: Bool=true) {
        require(nx>0 && nz>0 && fuel.size==nx*nz,"非法传播网格")
        require(ignition>=0 && ignition<fuel.size && (fuel[ignition] || allowBlockedIgnition),"请在当前模式的可燃林地上设置起火点")
        require(probability>=0.0 && probability<=1.0 && !probability.isNaN(),"传播概率须在 0 至 1 之间")
        require(duration>=1 && duration<=8 && seed>=0 && seed<=2147483647,"燃烧持续步或 seed 超出范围")
        require(targets.isEmpty() || targets.size==fuel.size,"保护目标尺寸不匹配")
        this.fuel=fuel.clone(); this.nx=nx; this.nz=nz; this.probability=probability; this.duration=duration; this.seed=seed
        this.keepHistory=keepHistory
        this.targets=if (targets.isEmpty()) { Array<Bool>(fuel.size,repeat:false) } else { targets.clone() }
        let age=Array<Int64>(fuel.size,repeat:0); if (fuel[ignition]) { age[ignition]=duration }
        let exposed=Array<Bool>(fuel.size,repeat:false); markExposure(age,exposed)
        snapshots.add(FireSnapshot(age,exposed,0))
    }
    func current(): FireSnapshot { snapshots[cursor] }
    func markExposure(age: Array<Int64>,exposed: Array<Bool>): Unit {
        for (i in 0..age.size) { if (age[i]>0) {
            if (targets[i]) { exposed[i]=true }
            for (n in neighbors(i,nx,nz)) { if (targets[n]) { exposed[n]=true } }
        } }
    }
    func advance(): Bool {
        if (cursor+1<snapshots.size) {
            cursor++; if (cursor==snapshots.size-1 && current().burning()==0) { running=false }; return true
        }
        let old=current(); if (old.burning()==0) { running=false; return false }
        let next=old.age.clone(); let exposed=old.exposed.clone()
        for (i in 0..fuel.size) { if (old.age[i]>0) {
            next[i]=if (old.age[i]==1) { -1 } else { old.age[i]-1 }
            for (n in neighbors(i,nx,nz)) {
                if (fuel[n] && old.age[n]==0 && edgeRandom(seed,old.step,i,n)<probability) { next[n]=duration }
            }
        } }
        markExposure(next,exposed)
        if (!keepHistory) { snapshots.clear(); cursor=0 }
        snapshots.add(FireSnapshot(next,exposed,old.step+1)); if (keepHistory) { cursor++ }
        if (current().burning()==0) { running=false }
        return true
    }
    func seek(step: Int64): Unit { require(step>=0 && step<snapshots.size,"回放位置超出已有快照"); cursor=step; running=false }
    func play(now: UInt64): Unit { running=cursor+1<snapshots.size || current().burning()>0; nextTick=now+500 }
    func tick(now: UInt64): Bool {
        var changed=false
        // Catch up at most four logical steps per UI tick, retaining any backlog.
        // No random draw or model step is tied to a rendered frame.
        for (_ in 0..4) {
            if (!running || now<nextTick) { break }
            changed=advance() || changed; nextTick+=500
        }; return changed
    }
}
