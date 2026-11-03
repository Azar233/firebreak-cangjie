package firebreak

import std.collection.ArrayList
import std.fs.{File,Directory,exists}
import stdx.encoding.json.*

func densitySummaryCsv(result:DensityResult):String {
    let p=readProjectText(result.source)
    let lines=ArrayList<String>(["probability,samples,spanning_samples,spanning_frequency,wilson95_low,wilson95_high,mean_occupied_cells,mean_largest_cells,mean_largest_grid_fraction"])
    for(point in result.points){lines.add(numberText(point.probability)+",${point.count},${point.hits},"+numberText(point.frequency())+","+numberText(point.interval[0])+","+numberText(point.interval[1])+","+numberText(point.occupied)+","+numberText(point.largest)+","+numberText(point.largest/Float64(p.cells)))}
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func densitySamplesCsv(result:DensityResult):String {
    let lines=ArrayList<String>(["probability,seed,occupied_cells,largest_cells,left_right_spanning"])
    for(row in result.rows){lines.add(numberText(row.probability)+",${row.seed},${row.occupied},${row.largest},${row.spanning}")}
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func interventionCsv(result:InterventionResult):String {
    let lines=ArrayList<String>(["sample,strategy,seed,ignition,original,cleared,burned,remaining,largest,left_right_spanning,ignition_blocked"])
    for(row in result.rows){lines.add("${row.sample},${row.strategy},${row.seed},${row.ignition},${row.original},${row.cleared},${row.burned},${row.remaining},${row.largest},${row.spanning},${row.blocked}")}
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func interventionSummaryCsv(result:InterventionResult):String {
    let lines=ArrayList<String>(["strategy,samples,cleared_cells,mean_burned,mean_remaining,mean_largest,spanning_frequency,wilson95_low,wilson95_high,paired_burn_delta,paired_burn_delta_standard_error"])
    for(strategy in 0..4){
        var hits:Int64=0;for(row in result.rows){if(row.strategy==strategy && row.spanning){hits++}}
        let ci=wilsonInterval(hits,result.samples)
        lines.add("${strategy},${result.samples},"+(if(strategy==0){"0"}else{"${result.dose}"})+","+numberText(result.mean(strategy,0))+","+numberText(result.mean(strategy,1))+","+numberText(result.mean(strategy,2))+","+numberText(result.mean(strategy,3))+","+numberText(ci[0])+","+numberText(ci[1])+","+numberText(result.mean(strategy,0)-result.mean(0,0))+","+numberText(result.burnDeltaSE(strategy)))
    }
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func studySvg(result:DensityResult):String {
    let p=readProjectText(result.source)
    var svg="<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"900\" height=\"520\" viewBox=\"0 0 900 520\"><rect width=\"900\" height=\"520\" fill=\"#222620\"/><g fill=\"#eeeece\" font-family=\"monospace\" font-size=\"16\"><text x=\"65\" y=\"28\">Finite ${p.nx}x${p.nz} open grid / ${result.samples} seeds / 4 neighbors</text><text x=\"65\" y=\"478\">Blue: spanning + pointwise Wilson 95%; Green: largest / grid</text><text x=\"65\" y=\"505\">Sampling probability p (0..1); this is not a confidence interval for pc</text></g>"
    for(i in 0..3){let y=440-i*190;svg+="<path d=\"M65 ${y} H865\" stroke=\"#596052\"/><text x=\"8\" y=\"${y}\" fill=\"white\">${i*50}%</text>"}
    for(i in 0..5){svg+="<text x=\"${55+i*200}\" y=\"460\" fill=\"white\">"+money(Float64(i)/4.0)+"</text>"}
    var blue="";var green=""
    for(point in result.points){
        let x=65.0+800.0*point.probability
        blue+=money(x)+","+money(440.0-380.0*point.frequency())+" "
        green+=money(x)+","+money(440.0-380.0*point.largest/Float64(p.cells))+" "
        svg+="<path d=\"M"+money(x)+" "+money(440.0-380.0*point.interval[0])+" V"+money(440.0-380.0*point.interval[1])+"\" stroke=\"#5fd2f1\"/>"
    }
    return svg+"<polyline fill=\"none\" stroke=\"#5fd2f1\" stroke-width=\"2\" points=\""+blue+"\"/><polyline fill=\"none\" stroke=\"#b3e86a\" stroke-width=\"2\" points=\""+green+"\"/></svg>"
}
func exportStudy(app:App,parent:String):String {
    let result=app.densityResult.getOrThrow();require(result.revision==app.work.revision && app.studyJob.isNone(),"Study inputs changed or task incomplete")
    let temp=Directory.createTemp(parent).toString()
    try{
        File.writeTo(temp+"/source.firebreak",result.source.toArray());File.writeTo(temp+"/density-summary.csv",densitySummaryCsv(result).toArray());File.writeTo(temp+"/density-samples.csv",densitySamplesCsv(result).toArray())
        File.writeTo(temp+"/density.svg",studySvg(result).toArray())
        let p=readProjectText(result.source);let j=JsonObject()
        let preview=app.studyPreview.getOrThrow()
        j.put("selectedDensity",JsonFloat(result.points[app.studyPoint].probability));j.put("selectedSeed",JsonInt(preview.project.seed));j.put("selectedPolicy",JsonInt(app.studyPolicy))
        j.put("format",JsonString("firebreak-density-study"));j.put("version",JsonInt(1));j.put("revision",JsonInt(result.revision));j.put("nx",JsonInt(p.nx));j.put("nz",JsonInt(p.nz));j.put("samplesPerDensity",JsonInt(result.samples));j.put("seedBase",JsonInt(p.seed));j.put("seedStride",JsonInt(104729));j.put("densityStep",JsonFloat(0.05))
        j.put("boundary",JsonString("open"));j.put("neighbors",JsonInt(4));j.put("sampling",JsonString("independent sites on land==1; edgeRandom(seed,${STUDY_OCCUPANCY_STEP},9176,index)<p; nested uniforms across p"))
        j.put("confidence",JsonString("pointwise Wilson 95% for spanning frequency, not a simultaneous band or pc confidence interval"))
        j.put("bracket",JsonString("adjacent tested densities bracketing 50% empirical left-right spanning; not infinite-system pc"))
        if(let Some(plans)<-app.interventionResult){
            File.writeTo(temp+"/interventions.csv",interventionCsv(plans).toArray());File.writeTo(temp+"/intervention-summary.csv",interventionSummaryCsv(plans).toArray());j.put("interventionDensity",JsonFloat(plans.probability));j.put("interventionSamples",JsonInt(plans.samples));j.put("clearedCells",JsonInt(plans.dose))
        }
        j.put("policies",JsonString("0 baseline; 1 random priority; 2 one-pass articulation gain then degree, seeded ties (not global optimum); 3 nearest center column then nearest center row coordinate; random priority key edgeRandom(seed,${STUDY_POLICY_STEP},policy,index)"))
        j.put("ignition",JsonString("floor(edgeRandom(sampleSeed,${STUDY_IGNITION_STEP},193,0)*cells); shared by all four policies, including non-fuel/cleared misses; no resampling"))
        j.put("budget",JsonString("study treatment previews use zero prices and nominal calibration if absent; monetary budget ignored, protected/excluded cells ineligible; apply restores original prices/calibration/budget and validates feasibility"))
        j.put("confidenceReference",JsonString("https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm"))
        File.writeTo(temp+"/parameters.json",j.toJsonString().toArray())
        File.writeTo(temp+"/preview.firebreak",preview.project.text().toArray());saveEvaluationMap(preview.view,preview.project.aspect,temp+"/preview.png")
        let prefix=parent+"/firebreak-density-r${result.revision}";var path=prefix;var suffix:Int64=1
        while(exists(path)){path=prefix+"-${suffix}";suffix++}
        let src=widePath(temp);let dst=widePath(path);let a=unsafe{acquireArrayRawData(src)};let b=unsafe{acquireArrayRawData(dst)}
        let ok=unsafe{MoveFileExW(a.pointer,b.pointer,UInt32(8))};unsafe{releaseArrayRawData(b);releaseArrayRawData(a)}
        require(ok!=0,"Cannot publish study directory; previous exports preserved")
        return path
    }catch(e:Exception){throw Exception(e.message+"; incomplete export retained at "+temp)}
}
