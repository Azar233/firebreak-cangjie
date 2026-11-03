package firebreak

import std.collection.ArrayList
import std.fs.{File,Directory,exists}
import stdx.encoding.json.*

func longRowsCsv(result:LongResult):String {
    let lines=ArrayList<String>(["sample,seed,policy,global_drive,observed_drive,measured,grown,alive,lightning,ignition,hit,suppressed,effort_cell_events,burned_cell_events"])
    for(r in result.rows){lines.add("${r.sample},${r.seed},${r.policy},${r.globalDrive},${r.drive},${r.measured},${r.grown},${r.alive},${r.lightning},${r.ignition},${r.hit},${r.suppressed},${r.effort},${r.burned}")}
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func longSummaryCsv(result:LongResult):String {
    let lines=ArrayList<String>(["sample,policy,mean_cover,strikes,misses,fires,large_fires,max_fire,burned_cell_events,suppression_actions,effort_cell_events"])
    for(t in result.totals){lines.add("${t.sample},${t.policy},"+numberText(t.density)+",${t.strikes},${t.misses},${t.fires},${t.large},${t.maximum},${t.burned},${t.suppressed},${t.effort}")}
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func longHistogramCsv(result:LongResult):String {
    let lines=ArrayList<String>(["policy,size_low,size_high,events,events_per_1000_observed_drives"])
    var low:Int64=1
    for(bin in 0..result.histogram[0].size){for(policy in 0..2){let n=result.histogram[policy][bin];lines.add("${policy},${low},${low*2-1},${n},"+numberText(Float64(n)*1000.0/Float64(result.spec.drives*result.spec.samples)))};low*=2}
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func longParameters(result:LongResult):JsonObject {
    let p=readProjectText(result.source);let s=result.spec;let j=JsonObject()
    j.put("format",JsonString("firebreak-long-run"));j.put("version",JsonInt(1));j.put("rule",JsonString("growth-lightning-v1"))
    j.put("nx",JsonInt(p.nx));j.put("nz",JsonInt(p.nz));j.put("seed",JsonInt(p.seed));j.put("seedStride",JsonInt(104729));j.put("samples",JsonInt(s.samples))
    j.put("growthProbability",JsonFloat(s.growth));j.put("gridLightningProbability",JsonFloat(s.lightning));j.put("warmup",JsonInt(s.warmup));j.put("observedDrives",JsonInt(s.drives));j.put("suppressionCapacity",JsonInt(s.capacity))
    j.put("order",JsonString("Each empty eligible site grows independently; then at most one uniform whole-grid lightning attempt; then the entire hit 4-neighbor component settles before the next drive. Open boundary. Existing fixed treatments never regrow. Single-fire q/duration are unused."))
    j.put("random",JsonString("edgeRandom(seed,1000000+globalDrive,channel,cell); channel 0 growth, 1 lightning coin at cell 0, 2 location at cell 0; independent seed stride 104729; shared external opportunities including misses, no resampling"))
    j.put("policies",JsonString("0 natural; 1 ideal omniscient suppression when hit component size <= capacity, preserving all its trees; effort equals protected cell-events. Not a realistic firefighting simulator."))
    j.put("statistics",JsonString("Warmup excluded. Large fire >= ceil(0.1*full grid cells). Repeated burns count as cell-events. Lightning includes misses. Individual events are temporally correlated; no independent-event confidence interval. Paired large-fire-per-drive SE is across independent seeds only."))
    if(s.samples>1){j.put("pairedLargeFireRateSE",JsonFloat(result.pairedLargeSE()))}
    j.put("replay",JsonString("First seed only, <=130 sampled post-settlement checkpoints retaining the latest lightning per window; final exact endpoint retained. Phase animation is illustrative, not intra-fire time. At most 256 flame sprites per policy. All logical burns retained in raw records."))
    j.put("modelScope",JsonString("DS-inspired extension, not strict original DS scheduling; finite experiment is not proof of self-organized criticality or an estimate of a universal critical value."))
    j.put("reference",JsonString("https://doi.org/10.1103/PhysRevLett.69.1629"));j.put("scalingCaution",JsonString("https://arxiv.org/abs/cond-mat/0201306"))
    return j
}
func longFramesJson(result:LongResult):JsonArray {
    let list=JsonArray()
    for(f in result.frames){let j=JsonObject();j.put("observedDrive",JsonInt(f.drive));let states=JsonArray();let burns=JsonArray()
        for(policy in 0..2){var state="";for(v in f.states[policy]){state+="${v}"};states.add(JsonString(state));let a=JsonArray();for(i in f.burned[policy]){a.add(JsonInt(i))};burns.add(a)}
        j.put("states",states);j.put("burnedIndices",burns);list.add(j)
    };return list
}
func exportLong(app:App,parent:String):String {
    let result=app.longResult.getOrThrow();require(result.revision==app.work.revision && app.longJob.isNone(),"Long-run inputs changed or task incomplete")
    let replay=app.longReplay.getOrThrow();let temp=Directory.createTemp(parent).toString()
    try{
        File.writeTo(temp+"/source.firebreak",result.source.toArray());File.writeTo(temp+"/parameters.json",longParameters(result).toJsonString().toArray())
        File.writeTo(temp+"/drives.csv",longRowsCsv(result).toArray());File.writeTo(temp+"/summary.csv",longSummaryCsv(result).toArray());File.writeTo(temp+"/fire-sizes.csv",longHistogramCsv(result).toArray())
        File.writeTo(temp+"/checkpoints.json",longFramesJson(result).toJsonString().toArray())
        for(policy in 0..2){File.writeTo(temp+"/snapshot-${policy}.firebreak",replay.snapshot(policy).text().toArray());saveEvaluationMap(replay.views[policy],replay.base.aspect,temp+"/snapshot-${policy}.png")}
        let prefix=parent+"/firebreak-long-r${result.revision}";var path=prefix;var suffix:Int64=1
        while(exists(path)){path=prefix+"-${suffix}";suffix++}
        let src=widePath(temp);let dst=widePath(path);let a=unsafe{acquireArrayRawData(src)};let b=unsafe{acquireArrayRawData(dst)}
        let ok=unsafe{MoveFileExW(a.pointer,b.pointer,UInt32(8))};unsafe{releaseArrayRawData(b);releaseArrayRawData(a)}
        require(ok!=0,"Cannot publish long-run export; previous exports preserved");return path
    }catch(e:Exception){throw Exception(e.message+"; incomplete export retained at "+temp)}
}
