package firebreak

import std.sync.Mutex
import std.convert.*
import std.collection.HashMap
import stdx.encoding.json.*

// One request crosses from the model worker to the UI owner thread. No App,
// renderer or mutable experiment object is captured by a model tool closure.
class AgentLabCall {
    let arguments:HashMap<String,JsonValue>;let readOnly:Bool;let lock=Mutex()
    var done=false;var response=""
    init(arguments:HashMap<String,JsonValue>,readOnly:Bool){this.arguments=arguments;this.readOnly=readOnly}
    func finish(value:String):Unit {synchronized(lock){response=value;done=true}}
    func result():?String {synchronized(lock){return if(done){Some(response)}else{None}}}
}
func labInt(j:HashMap<String,JsonValue>,key:String,fallback:Int64,low:Int64,high:Int64):Int64 {
    if(!j.contains(key)){return fallback};require(j[key] is JsonInt,"Expected integer: "+key)
    let n=j[key].asInt().getValue();require(n>=low && n<=high,"Out of range: "+key);return n
}
func labFloat(j:HashMap<String,JsonValue>,key:String,fallback:Float64):Float64 {
    if(!j.contains(key)){return fallback};require(j[key] is JsonInt || j[key] is JsonFloat,"Expected number: "+key)
    let n=Float64.parse(j[key].toJsonString());require(!n.isNaN() && n>=0.0 && n<=1.0,"Probability out of range: "+key);return n
}
func labArgs(j:HashMap<String,JsonValue>,allowed:Array<String>):Unit {
    // Reject extras rather than silently coercing model arguments.
    for((key,_) in j){require(allowed.contains(key),"Unknown or inapplicable argument: "+key)}
}
func labProgress(completed:Int64,total:Int64):JsonObject {let j=JsonObject();j.put("status",JsonString("running"));j.put("completed",JsonInt(completed));j.put("total",JsonInt(total));return j}
func readLab(app:App):String {
    pollStudy(app);pollLong(app,app.clockNow);app.syncComparison()
    let p=app.work.project;let graph=Connectivity(fuelMask(p,true),p.nx,p.nz);let j=JsonObject()
    j.put("revision",JsonInt(app.work.revision));j.put("stage",JsonInt(currentWorkflow(app)));j.put("nx",JsonInt(p.nx));j.put("nz",JsonInt(p.nz));j.put("seed",JsonInt(p.seed));j.put("livePlannedCells",JsonInt(graph.total));j.put("largestPlannedCluster",JsonInt(graph.largest));j.put("spansLeftRight",JsonBool(graph.spansLeftRight(p.nx,p.nz)))
    j.put("view",JsonString(if(app.longPanel){"long"}else if(app.studyPanel){"density"}else if(app.comparePanel){"compare"}else{"forest"}))
    j.put("pendingEdit",JsonBool(app.startCell>=0 || app.activeField>=0 || app.painting));j.put("replayBlockedByOverlay",JsonBool(app.terminal.open || app.menuOpen))
    let single=JsonObject();single.put("ignition",JsonInt(p.ignition));single.put("spreadProbability",JsonFloat(p.spreadProbability));single.put("burnSteps",JsonInt(p.burnSteps))
    if(let Some(run)<-app.experiment.run){single.put("step",JsonInt(run.cursor));single.put("playing",JsonBool(run.running));single.put("burning",JsonInt(run.current().burning()));single.put("burned",JsonInt(run.current().burned()))};j.put("single",single)
    if(let Some(job)<-app.studyJob){let state=job.progress();j.put("studyTask",labProgress(state.completed,state.total))}
    if(let Some(result)<-app.densityResult){let d=JsonObject();d.put("samplesPerDensity",JsonInt(result.samples));let points=JsonArray()
        for(point in result.points){let row=JsonObject();row.put("p",JsonFloat(point.probability));row.put("spanningFrequency",JsonFloat(point.frequency()));row.put("largestMean",JsonFloat(point.largest));row.put("wilson95Low",JsonFloat(point.interval[0]));row.put("wilson95High",JsonFloat(point.interval[1]));points.add(row)}
        d.put("points",points);let bracket=JsonArray();for(v in result.bracket()){bracket.add(JsonFloat(v))};d.put("empirical50Bracket",bracket);d.put("selectedIndex",JsonInt(app.studyPoint));d.put("selectedSample",JsonInt(app.studySample));d.put("selectedPolicy",JsonInt(app.studyPolicy));j.put("density",d)
    }
    if(let Some(result)<-app.interventionResult){let d=JsonObject();d.put("density",JsonFloat(result.probability));d.put("samples",JsonInt(result.samples));d.put("clearedCells",JsonInt(result.dose));let rows=JsonArray()
        for(policy in 0..4){let row=JsonObject();row.put("policy",JsonInt(policy));row.put("meanBurned",JsonFloat(result.mean(policy,0)));row.put("meanRemaining",JsonFloat(result.mean(policy,1)));row.put("meanLargest",JsonFloat(result.mean(policy,2)));row.put("spanningFrequency",JsonFloat(result.mean(policy,3)));row.put("pairedBurnDeltaSE",JsonFloat(result.burnDeltaSE(policy)));rows.add(row)};d.put("policies",rows);j.put("structure",d)
    }
    if(let Some(job)<-app.longJob){let state=job.progress();j.put("longTask",labProgress(state.completed,state.total))}
    if(let Some(result)<-app.longResult){let d=longParameters(result);let rows=JsonArray()
        for(policy in 0..2){let row=JsonObject();row.put("policy",JsonInt(policy));row.put("meanCover",JsonFloat(result.meanDensity(policy)));row.put("maxFire",JsonInt(result.maximum(policy)));row.put("burnedCellEvents",JsonInt(result.sum(policy,0)));row.put("largeFires",JsonInt(result.sum(policy,1)));row.put("strikes",JsonInt(result.sum(policy,2)));row.put("misses",JsonInt(result.sum(policy,5)));row.put("suppressionActions",JsonInt(result.sum(policy,3)));row.put("effortCellEvents",JsonInt(result.sum(policy,4)));rows.add(row)}
        d.put("policies",rows);if(let Some(replay)<-app.longReplay){d.put("replayFrame",JsonInt(replay.cursor));d.put("replayObservedDrive",JsonInt(replay.frame().drive));d.put("replayPlaying",JsonBool(replay.playing))};j.put("long",d)
    }
    if(let Some(job)<-app.evalJob){let state=job.progress();j.put("comparisonTask",labProgress(state.completed,state.total))}
    if(let Some(result)<-app.evalResult){let d=JsonObject();d.put("scenarios",JsonInt(result.rows.size));d.put("baselineBurned",JsonFloat(result.mean(false,0)));d.put("plannedBurned",JsonFloat(result.mean(true,0)));d.put("baselineRemaining",JsonFloat(result.mean(false,1)));d.put("plannedRemaining",JsonFloat(result.mean(true,1)));j.put("comparison",d)}
    j.put("scope",JsonString("Current revision only; absent result means not available, never zero. Density: finite-grid empirical bracket and pointwise Wilson CI, not pc CI. Long: first-seed checkpoint replay versus all-seed measured statistics; exclude warmup. No real-fire forecasts. No RAG installed. Apply is manual."))
    return j.toJsonString()
}
func controlLab(app:App,job:AgentChatJob,j:HashMap<String,JsonValue>):String {
    require(j.contains("action") && j["action"] is JsonString,"Expected action string");let action=j["action"].asString().getValue()
    require(!app.menuOpen && app.dialog.isNone() && app.startCell<0 && app.activeField<0 && !app.painting,"Finish pending edit/dialog/menu before changing the experiment")
    pollStudy(app);pollLong(app,app.clockNow);app.syncComparison()
    match(action){
        case "workflow"=>labArgs(j,["action","stage"]);let stage=labInt(j,"stage",-1,0,3);require(stage>=0,"stage required");enterWorkflow(app,stage)
        case "density_scan"=>
            labArgs(j,["action","samples"]);let samples=labInt(j,"samples",32,8,64);require([8,32,64].contains(samples),"samples must be 8,32,64");require(app.longJob.isNone() && app.evalJob.isNone(),"Another experiment task is active")
            startDensityStudy(app,samples);enterWorkflow(app,1);app.studyPanel=true;job.ownStudy(app.studyJob.getOrThrow())
        case "structure_compare"=>
            labArgs(j,["action","samples","density_index","dose"]);let samples=labInt(j,"samples",32,8,64);require([8,32,64].contains(samples),"samples must be 8,32,64")
            let point=labInt(j,"density_index",app.studyPoint,0,20);let dose=labInt(j,"dose",16,1,128);require(app.longJob.isNone() && app.evalJob.isNone(),"Another experiment task is active")
            startStructureStudy(app,samples,point,dose);enterWorkflow(app,1);app.studyPanel=true;job.ownStudy(app.studyJob.getOrThrow())
        case "structure_preview"=>
            labArgs(j,["action","sample","policy","density_index"]);let scan=app.densityResult.getOrThrow();let point=labInt(j,"density_index",app.studyPoint,0,20);let policy=labInt(j,"policy",0,0,3)
            require(app.studyJob.isNone(),"Wait for the study task");let count=if(point==app.studyPoint && app.interventionResult.isSome()){app.interventionResult.getOrThrow().samples}else{scan.samples};let sample=labInt(j,"sample",0,0,count-1)
            if(policy>0){let plans=app.interventionResult.getOrThrow();require(plans.probability==scan.points[point].probability,"Run structure_compare at the selected density first")}
            if(point!=app.studyPoint){app.interventionResult=None};app.studyPoint=point;app.studySample=sample;app.studyPolicy=policy;refreshStudyPreview(app);enterWorkflow(app,1);app.studyPanel=true
        case "long_run"=>
            labArgs(j,["action","growth","lightning","warmup","drives","samples","capacity"])
            let spec=LongSpec(labFloat(j,"growth",app.longGrowth),labFloat(j,"lightning",app.longLightning),labInt(j,"warmup",app.longWarmup,0,2048),labInt(j,"drives",app.longDrives,1,8192),labInt(j,"samples",app.longSamples,1,8),labInt(j,"capacity",app.longCapacity,0,16384))
            require(app.studyJob.isNone() && app.evalJob.isNone(),"Another experiment task is active");startLongStudy(app,spec);enterWorkflow(app,1);app.longPanel=true;job.ownLong(app.longJob.getOrThrow())
        case "compare_run"=>
            labArgs(j,["action","samples"]);let samples=labInt(j,"samples",16,4,32);require([4,16,32].contains(samples),"samples must be 4,16,32");require(app.studyJob.isNone() && app.longJob.isNone() && app.evalJob.isNone(),"Another experiment task is active")
            app.sampleCount=samples;enterWorkflow(app,3);app.comparisonAction(60);job.ownEvaluation(app.evalJob.getOrThrow())
        case "cancel_tasks"=>
            labArgs(j,["action"]);if(let Some(task)<-app.studyJob){task.cancel();app.studyJob=None};if(let Some(task)<-app.longJob){task.cancel();app.longJob=None};app.comparisonAction(61);if(let Some(run)<-app.experiment.run){run.running=false};if(let Some(replay)<-app.longReplay){replay.playing=false};if(let Some(pair)<-app.pairView){pair.playing=false}
        case "single_start" | "single_step" | "single_pause" | "single_reset"=>
            labArgs(j,["action"])
            if(action=="single_start" || action=="single_step"){require(app.work.project.ignition>=0 && app.work.project.fuel(app.work.project.ignition,planned:app.experiment.planned)>0.0,"Choose a valid ignition manually first")}
            enterWorkflow(app,1)
            if(action=="single_step"){app.simulationAction(41)}else if(action=="single_reset"){app.simulationAction(42)}else if(action=="single_pause"){if(let Some(run)<-app.experiment.run){run.running=false}}else{app.simulationAction(40)}
        case "long_play" | "long_pause" | "long_step" | "long_seek"=>
            labArgs(j,if(action=="long_seek"){["action","frame"]}else{["action"]});let replay=app.longReplay.getOrThrow();require(app.longJob.isNone(),"Wait for the long-run task")
            let index=labInt(j,"frame",replay.cursor,0,replay.result.frames.size-1);enterWorkflow(app,1);app.longPanel=true
            if(action=="long_play"){replay.play(app.clockNow)}else if(action=="long_pause"){replay.playing=false}else{replay.seek(if(action=="long_step"){min(replay.cursor+1,replay.result.frames.size-1)}else{index},app.clockNow)}
        case _=>throw Exception("Unsupported action; project edits, Apply, file operations and settings changes are not model tools")
    }
    app.terminal.append("[lab] "+action+app.t(" 已执行；未应用森林修改。"," executed; no forest edits applied."))
    return readLab(app)
}
func pollAgentLab(app:App,job:AgentChatJob):Unit {
    let call=job.takeLabCall();if(call.isNone()){return};let request=call.getOrThrow()
    try{
        job.checkActive();require(job.revision==app.work.revision && job.generation==app.agentSettings.generation && job.epoch==app.terminal.epoch && job.source==app.work.project.text(),"Stale experiment request")
        let events=job.progress().events;let terminal=app.terminal
        while(terminal.seenEvents<events.size){terminal.append(events[terminal.seenEvents]);terminal.seenEvents++}
        let result=if(request.readOnly){readLab(app)}else{controlLab(app,job,request.arguments)}
        request.finish(result)
    }catch(e:Exception){let error=JsonObject();error.put("status",JsonString("rejected"));error.put("error",JsonString(e.message));request.finish(error.toJsonString())}
}
