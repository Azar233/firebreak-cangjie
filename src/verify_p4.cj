package firebreak

import sdl.*
import std.fs.{File,Directory,exists}
import std.convert.*
import stdx.encoding.json.*

func completedSearch(p: Project): PlanSearchResult {
    let job=PlanSearchJob(p,7); job.execute(); let state=job.progress()
    require(state.done && state.error.isEmpty() && state.result.isSome(),"Search failed: "+state.error)
    return state.result.getOrThrow()
}
func planningCamp(): Project {
    let p=Project(demo:false)
    for (z in 3..17) { for (x in 2..23) { if (x<=10 || x>=14) { p.land[z*GRID_X+x]=1 } } }
    for (x in 11..14) { p.land[9*GRID_X+x]=1 }
    p.land[9*GRID_X+23]=4; p.targets[9*GRID_X+23]=1; p.forbidden[3*GRID_X+2]=1
    p.source="双林地连接示例"; p.ignition=9*GRID_X+5; p.spreadProbability=1.0; p.burnSteps=1; return p
}
func verifyP4(app: App,w: SdlWindow): Unit {
    let p=evaluationChain(); let original=p.text(); let generated=generateCandidates(p,{=>false})
    var bridge=false; var perimeter=false
    for (c in generated) { c.project(p).validate(); if (c.kind==3) { bridge=true }; if (c.kind==2) { perimeter=true } }
    pass(bridge && perimeter && generated.size<=14 && p.text()==original,"candidate generation finds target perimeters and articulation cuts without altering the original plan")
    let road=Project(); let roads=generateCandidates(road,{=>false}); var hasRoad=false
    for (c in roads) { if (c.kind==1) { hasRoad=true } }
    pass(hasRoad && roads.size<=14,"road-adjacent family is generated within the finite 14-candidate bound")
    let budget=p.copy(); budget.budget=50.0
    let exact=generateCandidates(budget,{=>false}); require(!exact.isEmpty(),"Exact-budget candidate missing")
    for (c in exact) { require(c.cost<=budget.budget && c.added.size==1,"Budget cap exceeded") }
    budget.budget=49.99
    pass(generateCandidates(budget,{=>false}).isEmpty(),"exact budget boundary accepts one-cell clearing and rejects candidates just above budget")
    let guarded=p.copy(); guarded.targets[2]=1; guarded.forbidden[3]=1
    let targetMask=guarded.treatment.clone(); targetMask[2]=1
    let forbiddenMask=guarded.treatment.clone(); forbiddenMask[3]=1
    pass(rejected({=>PlanCandidate(0,3,guarded,targetMask)}) && rejected({=>PlanCandidate(1,3,guarded,forbiddenMask)}),
        "protected and forbidden cells reject the whole candidate")
    let existing=p.copy(); existing.treatment[1]=1
    for (c in generateCandidates(existing,{=>false})) { require(c.treatment[1]==1,"Existing treatment overwritten") }
    let illegal=existing.treatment.clone(); illegal[1]=2
    pass(rejected({=>PlanCandidate(0,3,existing,illegal)}),"candidate additions preserve existing treatment including its type")
    let uncalibrated=p.copy(); uncalibrated.metersWide=0.0
    pass(rejected({=>PlanSearchJob(uncalibrated,0)}) && rejected({=>PlanSearchJob(Project(demo:false),0)}),"uncalibrated site and no-fuel scenario input fail with explicit errors")
    let search=completedSearch(p)
    pass(search.selected>=0 && search.recommended==search.selected && search.entries[search.selected].verified,
        "deterministic chain produces a training-selected candidate that also improves heldout metrics")
    for (e in search.entries) {
        require(e.training.rows.size==8 && e.review.rows.size==8,"Missing candidate samples")
        for (a in e.training.rows) { for (b in e.review.rows) { require(a.scenario.seed!=b.scenario.seed,"Training and holdout seed leakage") } }
        for (i in 0..8) { require(e.training.rows[i].scenario.ignition==search.current.rows[i].scenario.ignition &&
            e.training.rows[i].scenario.seed==search.current.rows[i].scenario.seed,"Candidates did not share training scenarios") }
    }
    pass(true,"all candidates retain 8 training and 8 holdout outcomes with shared paired inputs and disjoint seed sets")
    let current=search.current; let winner=search.entries[search.selected]
    let failed=PlanEntry(winner.candidate,winner.training,current,current,current)
    let successful=PlanEntry(winner.candidate,winner.training,winner.training,current,current)
    let withheld=PlanSearchResult(search.source,7,current,current,[failed,successful],0)
    pass(failed.eligible && !failed.verified && successful.verified && withheld.recommended== -1,
        "heldout failure rejects the training winner without choosing a different winner on the holdout set")
    let noChange=PlanEntry(winner.candidate,current,current,current,current)
    pass(!noChange.eligible && !noChange.verified,"no improvement is not mislabeled as a recommendation")
    let free=p.copy(); free.clearingPrice=0.0; free.breakPrice=0.0; free.budget=0.0
    let freeResult=completedSearch(free)
    for (e in freeResult.entries) { require(!e.score.isNaN() && !e.score.isInf() && e.candidate.deltaCost==0.0,"Zero-cost division failed") }
    pass(!freeResult.entries.isEmpty(),"zero-cost treatments use explicit one-yuan denominator floor and remain finite")
    let empty=completedSearch(budget)
    pass(empty.entries.isEmpty() && empty.selected== -1 && empty.recommended== -1 && searchReport(empty,true).contains("No feasible"),
        "empty feasible set is reported honestly without a fabricated success")
    let frozen=PlanSearchJob(p,9); p.seed=77; frozen.execute()
    pass(readProjectText(frozen.progress().result.getOrThrow().source).seed==42,"search freezes site and model inputs before later mutations")
    let cancelled=PlanSearchJob(p,10); cancelled.cancel(); cancelled.execute()
    pass(cancelled.progress().done && cancelled.progress().result.isNone(),"pre-cancelled search publishes no partial candidates")
    let slow=Project(); slow.burnSteps=8; slow.spreadProbability=1.0
    let running=PlanSearchJob(slow,11); running.start()
    for (_ in 0..10000) { if (running.progress().completed>0 || running.progress().done) { break }; w.delay(1) }
    running.cancel()
    for (_ in 0..10000) { if (running.progress().done) { break }; w.delay(1) }
    pass(running.progress().done && running.progress().cancelled && running.progress().result.isNone(),"background cancellation reaches the active paired evaluation and withholds partial search results")
    let parent=Directory.createTemp("artifacts").toString(); let path=exportSearch(search,parent,true); let second=exportSearch(search,parent,false)
    pass(path!=second && exists(path+"/report.md") && String.fromUtf8(File.readFrom(path+"/candidates.csv"))==searchCsv(search) &&
        String.fromUtf8(File.readFrom(path+"/samples.csv"))==searchSamplesCsv(search),"candidate export retains all outcomes and never replaces an existing report directory")
    let input=readProjectText(String.fromUtf8(File.readFrom(path+"/site.firebreak")))
    let parameters=JsonValue.fromStr(String.fromUtf8(File.readFrom(path+"/parameters.json"))).asObject()
    let sets=[parameters["training"].asArray(),parameters["holdout"].asArray()]
    let csvRows=String.fromUtf8(File.readFrom(path+"/candidates.csv")).split("\n")
    for (entryIndex in 0..search.entries.size) { let e=search.entries[entryIndex]; let fields=csvRows[entryIndex+1].split(",")
        require(Int64.parse(fields[0])==e.candidate.id,"Candidate id in exported CSV differs")
        for (dataset in 0..2) {
        let ss=sets[dataset]; let scenarios=Array<Scenario>(ss.size(),{i=>let s=ss[i].asObject(); Scenario(s["id"].asInt().getValue(),s["ignitionCell"].asInt().getValue(),s["seed"].asInt().getValue(),Float64.parse(s["weight"].asString().getValue()))})
        let next=input.copy(); next.treatment=parseMask(fields[14]); require(next.cost()==Float64.parse(fields[3]),"Exported candidate cost does not match mask")
        let replay=evaluated(next,scenarios); let expected=if (dataset==0) { e.training } else { e.review }
        for (i in 0..replay.rows.size) { require(replay.rows[i].planned.burned==expected.rows[i].planned.burned &&
            replay.rows[i].planned.contacts==expected.rows[i].planned.contacts && replay.rows[i].planned.remaining==expected.rows[i].planned.remaining,"Export recomputation differs") }
    } }
    pass(true,"exported frozen input, masks and both scenario sets reproduce every candidate's per-sample outcome")
    let camp=readProjectText(String.fromUtf8(File.readFrom("examples/connector-camp.firebreak")))
    pass(camp.text()==planningCamp().text(),"packaged connector-camp example matches the tested planning scenario")
    app.work.acceptLoaded(camp,""); app.syncScene(); app.cancel(); app.menuOpen=false; app.comparePanel=false; app.simPanel=false
    click(app,w,53); menuClick(app,w,99)
    pass(app.suggestPanel && !app.menuOpen,"menu suggestion entry opens the actual planning workflow")
    let before=app.work.project.text(); let revision=app.work.revision; click(app,w,70)
    for (_ in 0..15000) { app.updateExperiment(w.ticks()); if (app.searchJob.isNone()) { break }; w.delay(1) }
    let result=app.searchResult.getOrThrow()
    pass(result.recommended>=0 && app.work.project.text()==before && app.work.revision==revision,"asynchronous candidate search never applies or mutates its proposed winner")
    pass(rejected({=>app.suggestionAction(75)}) && app.work.revision==revision,"candidate cannot be applied before explicit preview")
    click(app,w,74)
    pass(app.candidateVisible && app.work.project.text()==before,"map preview highlights additions without changing document, budget or history")
    app.mapMode=true; app.referenceMode=false; app.preferences.setEnglish(false); app.view.selectedX = -1; app.view.selectedZ = -1
    render(app,w,capture:"artifacts/p4-suggestions.png")
    click(app,w,76)
    for (_ in 0..15000) { app.updateExperiment(w.ticks()); if (app.evalJob.isNone()) { break }; w.delay(1) }
    pass(app.evalResult.getOrThrow().candidatePreview && app.comparePanel && app.work.project.text()==before &&
        evaluationReport(app.evalResult.getOrThrow(),english:true).contains("not applied"),"P3 holdout replay and exported report label candidate preview as unapplied")
    app.openSuggestions(); let expected=app.selectedEntry().candidate.treatment.clone(); let depth=app.work.undo.size
    click(app,w,75)
    pass(app.work.project.treatment==expected && app.work.undo.size==depth+1 && app.searchResult.isNone() && app.evalResult.isNone(),
        "manual apply commits one undo transaction and invalidates candidate and replay results")
    app.activate(14)
    pass(app.work.project.text()==before && app.searchResult.isNone(),"undo restores the full pre-candidate plan without reviving stale recommendations")
    click(app,w,70); let stale=app.searchJob.getOrThrow(); let changed=app.work.project.copy(); changed.seed++
    app.work.commit(changed); app.updateExperiment(w.ticks())
    for (_ in 0..10000) { if (stale.progress().done) { break }; w.delay(1) }
    pass(stale.progress().cancelled && app.searchJob.isNone() && app.searchResult.isNone(),"manual parameter edits cancel old searches and prevent stale publication")
    for (size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]) {
        let l=Layout(size.w,size.h)
        for (id in CONTROLS) { if (l.available(id,false,suggestions:true)) {
            let b=l.control(id); require(b.w>=44.0 && b.h>=44.0 && b.right()<=size.w && b.bottom()<=size.h,"P4 target outside window")
            require(l.hit(b.centerX(),b.centerY(),suggestions:true)==id,"P4 overlapping targets")
        } }
    }
    app.focus=0
    for (_ in 0..CONTROLS.size) { event(app,w,UiEvent.KeyDown(Key.Tab,false)); require(Layout(Float32(w.width),Float32(w.height)).available(CONTROLS[app.focus],false,suggestions:true),"Hidden suggestion focus") }
    let tool=app.tool; event(app,w,UiEvent.KeyDown(Key.Digit(UInt8(54)),false))
    pass(tool==app.tool && app.startCell<0,"suggestion layout fits three desktop sizes and traps tool hotkeys without hiding keyboard navigation")
    app.suggestPanel=false; app.comparePanel=false; app.clearComparison(); app.searchResult=None; app.searchJob=None
    app.work.acceptLoaded(Project(),""); app.refreshReference(); app.syncScene(); app.camera.reset(); app.mapMode=false; app.tool=0; app.focus=0; app.cancel()
    println("P4 candidate generation, paired ranking, holdout, preview/apply, export and cancellation checks completed.")
}
