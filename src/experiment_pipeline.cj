package firebreak

import std.sync.Mutex
import std.math.abs
import stdx.encoding.json.*

let TEACHING_CASES=["examples/forest-sparse.firebreak","examples/forest-transition.firebreak","examples/forest-dense.firebreak"]
func teachingCase(index:Int64):Project {
    require(index>=0 && index<3,"Invalid teaching case")
    let p=densityForest(Project(nx:64,nz:64),[0.4,0.6,0.8][index],42)
    p.ignition=studyIgnition(p);p.source="Teaching forest / independent sites / p="+numberText([0.4,0.6,0.8][index])+" / seed 42; observations are not guaranteed outcomes";return p
}
func openTeachingCase(app:App,index:Int64):Unit {
    app.loadProject(TEACHING_CASES[index]);app.work.path="";app.work.saved="";app.work.unsaved=true
    app.menuOpen=false;app.terminal.open=false;enterWorkflow(app,0);app.mapMode=true;app.camera.resetMap()
    app.message=app.t("64×64教学森林：可手动观察，或在终端输入/experiment完成实验。请另存项目。","64x64 teaching forest: inspect manually or use /experiment. Save As.")
}
class PipelineSpec {
    let preset:String;let samples:Int64;let dose:Int64;let point:Int64;let policy:Int64;let longSpec:LongSpec
    init(preset:String,samples:Int64,dose:Int64,point:Int64,policy:Int64,longSpec:LongSpec){
        require(["current","sparse","transition","dense"].contains(preset),"Unknown experiment preset")
        require([8,16,32].contains(samples) && dose>=1 && dose<=128 && point>= -1 && point<=20 && policy>=0 && policy<=3,"Invalid pipeline parameters")
        require(longSpec.warmup<=512 && longSpec.drives<=2048 && longSpec.samples<=4,"Pipeline exceeds interactive workload bounds")
        this.preset=preset;this.samples=samples;this.dose=dose;this.point=point;this.policy=policy;this.longSpec=longSpec
    }
}
func defaultPipelineSpec():PipelineSpec {PipelineSpec("current",8,16,-1,2,LongSpec(0.01,0.1,128,512,4,64))}
class PipelineResult {
    let id:Int64;let revision:Int64;let workspace:String;let spec:PipelineSpec;let scan:DensityResult;let plans:InterventionResult;let longRun:LongResult;let point:Int64
    init(id:Int64,revision:Int64,workspace:String,spec:PipelineSpec,scan:DensityResult,plans:InterventionResult,longRun:LongResult,point:Int64){this.id=id;this.revision=revision;this.workspace=workspace;this.spec=spec;this.scan=scan;this.plans=plans;this.longRun=longRun;this.point=point}
    func json():String {
        let j=JsonObject();j.put("status",JsonString("completed"));j.put("runId",JsonInt(id));j.put("workspaceRevision",JsonInt(revision));j.put("preset",JsonString(spec.preset));j.put("workspaceChanged",JsonBool(false))
        let p=readProjectText(scan.source);j.put("nx",JsonInt(p.nx));j.put("nz",JsonInt(p.nz));j.put("seed",JsonInt(p.seed));j.put("samplesPerDensity",JsonInt(scan.samples));j.put("density",JsonFloat(plans.probability));j.put("densityIndex",JsonInt(point));j.put("clearedCells",JsonInt(plans.dose));j.put("previewPolicy",JsonInt(spec.policy))
        let bracket=JsonArray();for(v in scan.bracket()){bracket.add(JsonFloat(v))};j.put("empirical50Bracket",bracket)
        j.put("selection",JsonString(if(spec.point>=0){"user-selected tested density"}else{"tested density with spanning frequency closest to 0.5; first index breaks ties, NOT an estimate of exact pc"}))
        let rows=JsonArray();for(policy in 0..4){let row=JsonObject();row.put("policy",JsonInt(policy));row.put("meanBurned",JsonFloat(plans.mean(policy,0)));row.put("meanRemaining",JsonFloat(plans.mean(policy,1)));row.put("meanLargest",JsonFloat(plans.mean(policy,2)));row.put("pairedBurnDeltaSE",JsonFloat(plans.burnDeltaSE(policy)));rows.add(row)};j.put("structuralComparison",rows)
        let long=longParameters(longRun);let policies=JsonArray();for(policy in 0..2){let row=JsonObject();row.put("policy",JsonInt(policy));row.put("meanCover",JsonFloat(longRun.meanDensity(policy)));row.put("maxFire",JsonInt(longRun.maximum(policy)));row.put("largeFires",JsonInt(longRun.sum(policy,1)));row.put("strikes",JsonInt(longRun.sum(policy,2)));row.put("burnedCellEvents",JsonInt(longRun.sum(policy,0)));row.put("suppressionActions",JsonInt(longRun.sum(policy,3)));row.put("effortCellEvents",JsonInt(longRun.sum(policy,4)));policies.add(row)};long.put("policies",policies);j.put("longRun",long)
        j.put("scope",JsonString("Scan and structure use independent-site samples, not a forecast for the workspace. Long run starts from baseline structural sample 0 at the selected density, with NO structural clearing; it separately compares natural versus ideal small-fire suppression. Preview policy is fixed, not a winner selected from these data. All policies and negative results retained. No project edit or file export. Three cards show actual result arrays; chart long trace is first seed, statistics all seeds. Apply remains manual; use density/long export UI to save full raw data."))
        return j.toJsonString()
    }
}
class PipelineProgress {
    let stage:Int64;let completed:Int64;let total:Int64;let done:Bool;let cancelled:Bool;let error:String;let result:?PipelineResult
    init(stage:Int64,completed:Int64,total:Int64,done:Bool,cancelled:Bool,error:String,result:?PipelineResult){this.stage=stage;this.completed=completed;this.total=total;this.done=done;this.cancelled=cancelled;this.error=error;this.result=result}
}
class PipelineJob {
    let id:Int64;let source:String;let revision:Int64;let spec:PipelineSpec;let lock=Mutex()
    var ownerGeneration:Int64= -1;var ownerEpoch:Int64= -1
    var stage:Int64=0;var done=false;var cancelled=false;var error="";var result:?PipelineResult=None;var study:?ForestStudyJob=None;var long:?LongJob=None
    init(id:Int64,p:Project,revision:Int64,spec:PipelineSpec){p.validate();this.id=id;source=p.text();this.revision=revision;this.spec=spec}
    func cancel():Unit {synchronized(lock){cancelled=true;if(let Some(job)<-study){job.cancel()};if(let Some(job)<-long){job.cancel()}}}
    func check():Unit {synchronized(lock){require(!cancelled,"Pipeline cancelled")}}
    func progress():PipelineProgress {
        synchronized(lock){var n:Int64=0;var total:Int64=1;if(let Some(job)<-study){let s=job.progress();n=s.completed;total=s.total};if(let Some(job)<-long){let s=job.progress();n=s.completed;total=s.total};return PipelineProgress(stage,n,total,done,cancelled,error,result)}
    }
    func runStudy(job:ForestStudyJob,stage:Int64):StudyProgress {synchronized(lock){this.stage=stage;study=Some(job);long=None;if(cancelled){job.cancel()}};job.execute();check();let s=job.progress();require(s.done && s.error.isEmpty() && !s.cancelled,"Study stage failed: "+s.error);return s}
    func start():Unit {spawn{execute()}}
    func execute():Unit {
        try{check();let base=if(spec.preset=="current"){readProjectText(source)}else{teachingCase(if(spec.preset=="sparse"){0}else if(spec.preset=="transition"){1}else{2})}
            let scan=runStudy(ForestStudyJob(base,revision,spec.samples),1).density.getOrThrow()
            var point=spec.point
            if(point<0){var best:Float64=2.0;for(i in 0..scan.points.size){let score=abs(scan.points[i].frequency()-0.5);if(score<best){best=score;point=i}}}
            let plans=runStudy(ForestStudyJob(base,revision,spec.samples,mode:1,probability:scan.points[point].probability,dose:spec.dose),2).interventions.getOrThrow()
            let drive=LongJob(plans.preview(0,0),revision,spec.longSpec)
            synchronized(lock){stage=3;study=None;long=Some(drive);if(cancelled){drive.cancel()}}
            drive.execute();check();let s=drive.progress();require(s.done && s.error.isEmpty() && !s.cancelled,"Long-run stage failed: "+s.error)
            let complete=PipelineResult(id,revision,source,spec,scan,plans,s.result.getOrThrow(),point)
            synchronized(lock){if(!cancelled){result=Some(complete)};stage=4;done=true;study=None;long=None}
        }catch(e:Exception){synchronized(lock){error=e.message;done=true;study=None;long=None}}
    }
}
func startPipeline(app:App,spec:PipelineSpec,owner!:?AgentChatJob=None):PipelineJob {
    require(app.pipelineJob.isNone() && app.studyJob.isNone() && app.longJob.isNone() && app.evalJob.isNone() && app.searchJob.isNone(),"Another experiment task is active")
    require(owner.isSome() || app.agentChat.isNone(),"A model request is active; stop it first")
    require(app.startCell<0 && app.activeField<0 && !app.painting && app.dialog.isNone(),"Finish the pending edit/dialog first")
    app.terminal.agentPlan=None
    app.pipelineSerial++;let job=PipelineJob(app.pipelineSerial,app.work.project,app.work.revision,spec);app.pipelineResult=None;app.pipelineLastStage=0;app.pipelineJob=Some(job);if(let Some(parent)<-owner){job.ownerGeneration=parent.generation;job.ownerEpoch=parent.epoch;parent.ownPipeline(job)};job.start();return job
}
func pollPipeline(app:App):Unit {
    if(let Some(old)<-app.pipelineResult){if(old.revision!=app.work.revision){app.pipelineResult=None}}
    if(let Some(job)<-app.pipelineJob){
        if(job.revision!=app.work.revision || (job.ownerGeneration>=0 && (job.ownerGeneration!=app.agentSettings.generation || job.ownerEpoch!=app.terminal.epoch))){job.cancel();app.pipelineJob=None;app.message=app.t("场地已修改，完整实验任务失效。","Inputs changed; pipeline invalidated.");return}
        let state=job.progress()
        if(state.stage!=app.pipelineLastStage){app.pipelineLastStage=state.stage;app.terminal.append("[experiment ${job.id}] "+app.t(["准备","1/3 密度扫描","2/3 等量结构对照","3/3 长期生长/落雷","计算完成"][state.stage],["Preparing","1/3 Density scan","2/3 Equal-clearing comparison","3/3 Growth/lightning","Computation complete"][state.stage]))}
        if(!state.done){return};app.pipelineJob=None
        if(state.cancelled || !state.error.isEmpty()){app.message=app.t("完整实验未发布：","Pipeline not published: ")+state.error;app.terminal.append(app.message);return}
        if(job.source!=app.work.project.text()){app.message=app.t("完整实验输入已过期。","Pipeline inputs stale.");return}
        try{
        let result=state.result.getOrThrow();app.densityResult=Some(result.scan);app.interventionResult=Some(result.plans);app.studyPoint=result.point;app.studySamples=result.spec.samples;app.studyDose=result.spec.dose;app.studySample=0;app.studyPolicy=result.spec.policy;refreshStudyPreview(app)
        clearLong(app);setLongSpec(app,result.longRun.spec);app.longResult=Some(result.longRun);app.longReplay=Some(LongReplay(result.longRun,app.assets));app.longReplay.getOrThrow().seek(0,app.clockNow)
        enterWorkflow(app,1);app.studyPanel=true;app.pipelineResult=Some(result)
        publishPipelineCards(app,result)
        app.message=app.t("完整实验完成；图表来自实际结果，工作台未修改。/preview查看样本。","Experiment complete; actual result cards, workspace unchanged. /preview opens the sample.")
        app.terminal.append(app.message)
        }catch(e:Exception){app.pipelineResult=None;app.message=app.t("实验显示未完成：","Experiment display failed: ")+e.message;app.terminal.append(app.message)}
    }
}
