package firebreak

import sdl.*
import std.fs.{File,Directory,exists}
import std.convert.*
import stdx.encoding.json.*

func readExample(index:Int64):Project {readProjectText(String.fromUtf8(File.readFrom(CASE_FILES[index])))}
func caseEvaluation(p:Project):EvaluationResult {
    let job=EvaluationJob(p,0,makeScenarios(p,16));job.execute();let state=job.progress()
    require(state.done && !state.cancelled && state.result.isSome(),"Example evaluation failed: "+state.error)
    return state.result.getOrThrow()
}
func verifyExamples(app:App,w:SdlWindow):Unit {
    let base=readExample(0);let cut=readExample(1)
    let original=cut.copy();original.treatment=base.treatment.clone()
    pass(original.text()==base.text() && cut.count(cut.treatment)==1 && cut.cost()==50.0 && cut.budget==50.0,
        "Packaged five-cell cases differ only by one legal CNY 50 treatment")
    let chain=caseEvaluation(cut)
    pass(chain.rows[0].baseline.burned==5 && chain.rows[0].planned.burned==2 && chain.rows[0].planned.remaining==2 && chain.rows[0].planned.contacts==0,
        "Left-side ignition burns five baseline cells but two after the cut, leaving the target untouched")
    // Quantiles select x=7,8,9,11: two left starts, a treated start, a right start.
    pass(chain.rows[3].scenario.ignition==7*24+11 && chain.rows[3].planned.contacts==1 &&
        chain.mean(true,0)==1.5 && chain.mean(true,1)==2.5 && chain.mean(true,2)==0.25 && chain.exposedSamples(true)==4,
        "Sixteen chain scenarios retain right-side target-contact failures rather than claiming universal protection")
    var blocked:Int64=0;for(row in chain.rows){if(row.planned.ignitionBlocked){blocked++}}
    pass(blocked==4 && chain.rows.size==16,"Treated ignition cases remain explicitly recorded among all sixteen paired outcomes")
    let camp=readExample(2);let treatment=readExample(3);let restored=treatment.copy();restored.treatment=camp.treatment.clone()
    pass(restored.text()==camp.text() && camp.budget==100.0 && camp.count(camp.targets)>0 && camp.count(camp.forbidden)>0,
        "Budget camp examples preserve the same site, budget, targets and exclusions")
    let searchJob=PlanSearchJob(camp,0);searchJob.execute();let state=searchJob.progress()
    require(state.done && !state.cancelled && state.result.isSome(),"Case search did not finish: "+state.error)
    let search=state.result.getOrThrow();require(search.recommended>=0,"Budget camp has no verified candidate")
    File.writeTo("artifacts/p6-camp-candidates.csv",searchCsv(search).toArray())
    let winner=search.entries[search.recommended]
    pass(winner.candidate.treatment==treatment.treatment && winner.candidate.cost==50.0 && winner.candidate.cost<=camp.budget,
        "Delivered CNY 50 bridge plan reproduces the training-selected and holdout-verified candidate")
    var trainingContacts:Int64=0;var holdoutContacts:Int64=0
    for(row in winner.training.rows){if(row.planned.contacts>0){trainingContacts++}}
    for(row in winner.review.rows){if(row.planned.contacts>0){holdoutContacts++}}
    pass(trainingContacts==2 && holdoutContacts==4 && winner.training.mean(2)==0.25 && winner.review.mean(2)==0.5 && winner.training.mean(1)==128.0 && winner.review.mean(1)==127.0,
        "Camp retains the gap between training and holdout: some holdout fires still reach the target")
    for(entry in search.entries){
        entry.candidate.project(camp).validate()
        require(entry.training.rows.size==8 && entry.review.rows.size==8,"Candidate scenarios missing")
    }
    pass(camp.cost()==0.0 && treatment.cost()==50.0,"Generating and checking candidates does not apply them to the source case")
    let campResult=caseEvaluation(treatment)
    let summary=JsonObject();summary.put("format",JsonString("firebreak-case-results"));summary.put("version",JsonInt(1))
    summary.put("syntheticSites",JsonBool(true));summary.put("chainSamples",JsonInt(chain.rows.size))
    summary.put("chainPlannedBurned",JsonFloat(chain.mean(true,0)));summary.put("chainPlannedRemaining",JsonFloat(chain.mean(true,1)))
    summary.put("chainTargetContactSamples",JsonInt(chain.exposedSamples(true)));summary.put("campBudget",JsonFloat(camp.budget))
    summary.put("campCost",JsonFloat(treatment.cost()));summary.put("campTrainingRemaining",JsonFloat(winner.training.mean(1)))
    summary.put("campHoldoutRemaining",JsonFloat(winner.review.mean(1)));summary.put("campTrainingContacts",JsonFloat(winner.training.mean(2)))
    summary.put("campHoldoutContacts",JsonFloat(winner.review.mean(2)))
    File.writeTo("artifacts/p6-case-results.json",summary.toJsonString().toArray())
    File.writeTo("artifacts/p6-chain-metrics.csv",evaluationCsv(chain).toArray())
    File.writeTo("artifacts/p6-chain-parameters.json",evaluationParameters(chain).toArray())
    File.writeTo("artifacts/p6-camp-metrics.csv",evaluationCsv(campResult).toArray())
    File.writeTo("artifacts/p6-camp-candidates.csv",searchCsv(search).toArray())
    File.writeTo("artifacts/p6-camp-samples.csv",searchSamplesCsv(search).toArray())
    File.writeTo("artifacts/p6-camp-parameters.json",evaluationParameters(campResult).toArray())
    File.writeTo("artifacts/p6-camp-search-parameters.json",searchParameters(search).toArray())
    let parent=Directory.createTemp("artifacts").toString()
    let reportPath=exportEvaluation(chain,app.assets,parent)
    let campReportPath=exportEvaluation(campResult,app.assets,parent)
    let candidatePath=exportSearch(search,parent,false)
    pass(exists(reportPath+"/report.md") && exists(reportPath+"/baseline.png") && exists(reportPath+"/planned.png") &&
        String.fromUtf8(File.readFrom(reportPath+"/metrics.csv"))==evaluationCsv(chain) &&
        String.fromUtf8(File.readFrom(candidatePath+"/samples.csv"))==searchSamplesCsv(search) &&
        String.fromUtf8(File.readFrom(campReportPath+"/metrics.csv"))==evaluationCsv(campResult),
        "Example exports contain actual paired maps, metrics and complete candidate samples")
    // Re-read exported inputs and scenarios, not a second hand-written simulator.
    let input=readProjectText(String.fromUtf8(File.readFrom(reportPath+"/site.firebreak")))
    let parameters=JsonValue.fromStr(String.fromUtf8(File.readFrom(reportPath+"/parameters.json"))).asObject()["scenarios"].asArray()
    let scenarios=Array<Scenario>(parameters.size(),{i=>let j=parameters[i].asObject();Scenario(j["id"].asInt().getValue(),j["ignitionCell"].asInt().getValue(),j["seed"].asInt().getValue(),Float64.parse(j["weight"].asString().getValue()))})
    let replay=EvaluationJob(input,0,scenarios);replay.execute()
    pass(evaluationCsv(replay.progress().result.getOrThrow())==evaluationCsv(chain),"Exported chain snapshot and exact scenario parameters reproduce every paired metric")
    for(size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]){
        let m=MenuLayout(Layout(size.w,size.h))
        for(page in [0,7]){for(id in m.controls(page)){let b=m.box(id,page:page);require(b.x>=0.0 && b.y>=0.0 && b.right()<=size.w && b.bottom()<=size.h && m.hit(b.centerX(),b.centerY(),page)==id,"Example menu target outside window or overlapping")}}
    }
    pass(true,"Example menu and revised root menu keep aligned hit targets at three desktop sizes")
    app.cancel();app.menuOpen=true;app.menuPage=0;menuClick(app,w,108)
    pass(app.menuPage==7 && app.menuFocus==109,"Esc menu opens a keyboard-accessible synthetic example picker")
    app.preferences.english=false
    render(app,w,capture:"artifacts/p6-example-menu.png")
    for(index in 0..CASE_FILES.size){
        app.work.acceptLoaded(Project(),"");app.openMenu();app.menuPage=7
        let bytes=File.readFrom(CASE_FILES[index]);menuClick(app,w,109+index)
        require(!app.menuOpen && app.mapMode && app.simPanel && app.work.path.isEmpty() && app.work.dirty() && app.work.saved.isEmpty(),"Example was not loaded as an unsaved copy")
        require(app.work.project.text()==readExample(index).text() && File.readFrom(CASE_FILES[index])==bytes,"Loading a case modified its source")
    }
    pass(true,"All menu cases load as fresh projects requiring Save As without modifying bundled source files")
    let protectedBytes=File.readFrom(CASE_FILES[3]);let saved=parent+"/my-camp.firebreak";app.work.save(saved)
    pass(File.readFrom(CASE_FILES[3])==protectedBytes && readProjectText(String.fromUtf8(File.readFrom(saved))).text()==treatment.text(),
        "Saving a loaded example writes a separate project and preserves the original demonstration plan")
    app.clearComparison();app.evalResult=Some(campResult);app.pairView=Some(ComparisonView(campResult,app.assets))
    app.work.revision=campResult.revision;let pair=app.pairView.getOrThrow();pair.seek(pair.maxStep)
    app.simPanel=false;app.comparePanel=true;app.mapMode=true;app.message="合成营地案例：16组配对情景；当前回放情景1，非现实火灾预测。"
    render(app,w,capture:"artifacts/p6-camp-comparison.png")
    pass(pair.baseline.nativeReady() && pair.planned.nativeReady(),"Camp comparison renders both final-state maps through the existing renderer")
    app.clearComparison();app.comparePanel=false;app.simPanel=false;app.menuOpen=false
}
