package firebreak

import sdl.*
import std.fs.{File,exists}
import std.collection.ArrayList
import magic.core.model.*
import magic.core.message.Conversation

class ScriptedPipelineModel <: ChatModel {
    var turn:Int64=0
    public prop provider:String {get(){"test"}}
    public prop name:String {get(){"scripted-pipeline"}}
    public prop contextLength:Int64 {get(){32768}}
    public mut prop maxTokens:?Int64 {get(){None};set(_) {}}
    public func create(r:ChatRequest):ChatResponse {ChatResponse(name,asyncCreate(r).message)}
    public func asyncCreate(r:ChatRequest):AsyncChatResponse {
        if(turn>0){var complete=false;for(message in r.messageList){if(message.content.contains("empirical50Bracket") && message.content.contains("structuralComparison") && message.content.contains("longRun")){complete=true}};require(complete,"Tool returned before the full pipeline result")}
        let text=if(turn==0){"<action>{\"name\":\"run_experiment\",\"arguments\":{\"preset\":\"transition\",\"samples\":8,\"dose\":4,\"warmup\":16,\"drives\":64,\"long_samples\":2}}</action>"}else{"<answer>已完成密度扫描、等量结构对照与长期对照，生成三张真实图表；未应用森林修改。</answer>"}
        turn++;let chunks=ArrayList<AsyncChatChunk>([firebreakChunk(text),firebreakChunk("",done:true)]);return firebreakStream(name,chunks.iterator())
    }
}
func verifyPipeline(app:App,w:SdlWindow,live!:Bool=false):Unit {
    let gpu=app.preferences.gpuEnabled;let original=app.work.project.text();app.cancel();app.menuOpen=false;app.terminal.open=false;app.terminal.clearMessages();app.terminal.rounds.clear();app.terminal.epoch++
    let expected=[0.4,0.6,0.8];var previous:Int64=0
    for(index in 0..3){let p=readProjectText(String.fromUtf8(File.readFrom(TEACHING_CASES[index])));let generated=teachingCase(index)
        require(p.nx==64 && p.nz==64 && p.vegetation==generated.vegetation && p.ignition==generated.ignition && p.seed==42,"Teaching example differs from generator")
        let graph=Connectivity(fuelMask(p,true),64,64);require(graph.total>previous,"Teaching probabilities are not nested");previous=graph.total
        require(p.count(p.treatment)==0 && p.count(p.targets)==0 && p.count(p.forbidden)==0,"Teaching case inherited legacy annotations")
    };pass(expected.size==3,"Three 64x64 teaching files reproduce exact keyed vegetation with increasing cover and no legacy annotations")
    for(size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]){let m=MenuLayout(Layout(size.w,size.h));for(page in [11,12]){for(id in m.controls(page)){let b=m.box(id,page:page);require(b.w>=44.0 && b.h>=44.0 && b.bottom()<=size.h && m.hit(b.centerX(),b.centerY(),page)==id,"Teaching menu targets overlap or leave window")}}}
    pass(true,"Teaching menu targets fit minimum, normal and fullscreen layouts")
    let spec=PipelineSpec("transition",8,4,-1,2,LongSpec(0.01,0.1,16,64,2,64));let cancelled=PipelineJob(0,app.work.project,app.work.revision,spec);cancelled.cancel();cancelled.execute()
    pass(cancelled.progress().cancelled && cancelled.progress().result.isNone(),"Precancelled pipeline publishes no partial stages")
    let invalid=PipelineJob(0,Project(nx:1,nz:1),0,PipelineSpec("current",8,128,20,2,LongSpec(0.0,0.0,0,1,1,0)));invalid.execute()
    pass(!invalid.progress().error.isEmpty() && invalid.progress().result.isNone(),"A failing structural stage stops the pipeline without a completed result")
    pass(rejected({=>PipelineSpec("unknown",8,4,-1,2,spec.longSpec)}) && rejected({=>PipelineSpec("current",64,4,-1,2,spec.longSpec)}),"Whole-experiment presets and resource bounds reject invalid requests")
    let revision=app.work.revision;let question="用64×64过渡区教学森林，8个seed、清理4格、预热16轮、观测64轮、长期2个seed，安排一整套密度扫描、等量结构干预和长期落雷实验，完成后展示图表并总结；不要修改工作台。"
    app.terminal.append(question,user:true)
    let job=AgentChatJob(app.work.project,revision,app.agentSettings,app.terminal.epoch,question,Conversation());app.agentChat=Some(job);app.terminal.seenEvents=0
    if(live){require(!app.agentSettings.apiKey.isEmpty(),"Live pipeline check needs saved API settings");job.start()}else{job.worker=Some(spawn{job.execute(modelOverride:Some(ScriptedPipelineModel()))})}
    waitAgentLab(app,w,job);let progress=job.progress();require(progress.error.isEmpty(),progress.error)
    let result=app.pipelineResult.getOrThrow()
    pass(progress.events.contains("[tool] run_experiment") && app.terminal.rounds.size==1 && validKnowledgeCitations(progress.answer,job.knowledgeHits()) && result.scan.samples==8 && result.plans.rows.size==32 && result.longRun.spec.drives==64,"One model tool invocation waits for scan, all four structural policies and the long-run experiment")
    pass(app.work.project.text()==original && app.work.revision==revision && result.plans.probability==result.scan.points[result.point].probability && result.longRun.source==result.plans.preview(0,0).text(),"Pipeline uses consistent selected samples while keeping workspace and revision unchanged")
    pass(app.studyPolicy==2 && app.studyPreview.getOrThrow().project.count(app.studyPreview.getOrThrow().project.treatment)==4 && result.json().contains("NOT an estimate of exact pc"),"Fixed connector preview is retained without selecting a winner or claiming exact criticality")
    let studyExport=exportStudy(app,"artifacts");let longExport=exportLong(app,"artifacts")
    pass(exists(studyExport+"/interventions.csv") && exists(longExport+"/drives.csv") && String.fromUtf8(File.readFrom(longExport+"/drives.csv"))==longRowsCsv(result.longRun),"Completed pipeline results reuse the density/long-run exports with exact raw records")
    File.writeTo("artifacts/pipeline-case-results.json",result.json().toArray())
    let cards=ArrayList<ExperimentCard>();for(message in app.terminal.messages){if(let Some(card)<-message.card){cards.add(card)}}
    pass(cards.size==3 && cards[0].revision==revision && cards[1].runId==result.id && !cards[2].isClosed(),"Three owned image cards carry actual run/revision metadata")
    app.preferences.gpuEnabled=true;app.terminal.open=true;app.terminal.quick=false;app.terminal.scroll=0;render(app,w)
    // A real model may append enough explanation/citations to scroll every card offscreen.
    // Find a card in history before testing its visible hit target.
    let lines=app.terminal.cachedLines.size;var offset:Int64=0
    while(app.terminal.cardHits.isEmpty() && offset<lines){offset++;app.terminal.scroll=offset;render(app,w)}
    render(app,w,capture:if(live){"artifacts/pipeline-agent-live.png"}else{"artifacts/pipeline-cards.png"})
    if(live){
        // README proof comes from this authenticated tool run and its exact result arrays.
        let showFps=app.preferences.showFps;app.preferences.showFps=false
        app.terminal.scroll=app.terminal.cachedLines.size;render(app,w,capture:"artifacts/release-terminal.png")
        app.terminal.open=false;app.studyPolicy=0;refreshStudyPreview(app);render(app,w,capture:"artifacts/release-density.png")
        app.studyPolicy=result.spec.policy;refreshStudyPreview(app);render(app,w,capture:"artifacts/release-structure.png")
        app.studyPanel=false;app.simPanel=true;app.longPanel=true;app.longTopDown=false
        let replay=app.longReplay.getOrThrow();let layout=Layout(Float32(w.width),Float32(w.height));replay.camera.fitScene(replay.scenes[0],longSceneBox(layout,0,replay.base.aspect,false))
        var chosen:Int64=0;var largest:Int64= -1
        for(i in 0..result.longRun.frames.size){let size=result.longRun.frames[i].burned[0].size;if(size>largest){chosen=i;largest=size}}
        replay.seek(chosen,app.clockNow);render(app,w,capture:"artifacts/release-long.png")
        app.longPanel=false;app.studyPanel=true;app.terminal.open=true;render(app,w)
        app.terminal.scroll=offset;app.preferences.showFps=showFps;render(app,w)
    }
    require(!app.terminal.cardHits.isEmpty(),"No inline image hit targets after scrolling history")
    let m=TerminalLayout(Layout(Float32(w.width),Float32(w.height)),false);let hit=app.terminal.cardHits[app.terminal.cardHits.size-1];let x=hit[0].centerX();let y=max(m.output.y+2.0,min(m.output.bottom()-2.0,hit[0].centerY()))
    event(app,w,UiEvent.MouseDown(MouseButton.Left,x,y));event(app,w,UiEvent.MouseUp(MouseButton.Left,x,y));pass(app.terminal.expandedCard.isSome(),"Clicking an inline result image opens the enlarged card")
    render(app,w,capture:"artifacts/pipeline-card-expanded.png");event(app,w,UiEvent.KeyDown(Key.Escape,false));pass(app.terminal.expandedCard.isNone() && app.terminal.open,"Escape closes the image before closing the terminal")
    app.terminal.quick=true;render(app,w);app.terminal.quick=false;w.setSize(1100,780);w.refreshSize();render(app,w,capture:"artifacts/pipeline-small.png");w.setSize(1280,860);w.refreshSize()
    let next=app.work.project.copy();next.seed++;app.work.commit(next);pollPipeline(app);render(app,w,capture:"artifacts/pipeline-card-stale.png")
    pass(app.pipelineResult.isNone() && cards[0].revision!=app.work.revision && !cards[0].isClosed(),"Workspace edits invalidate current pipeline results while retaining explicitly historical images")
    let closed=cards[0];app.terminal.clearMessages();pass(closed.isClosed() && app.terminal.cardHits.isEmpty(),"Clearing history releases card textures and cached image targets")
    let tiny=ArrayList<ExperimentCard>();for(i in 0..7){let card=ExperimentCard("bounded card","test",app.work.revision,i,cardTexture(app,Array<Color>(4,repeat:Color.rgb(70,90,40)),2,2));tiny.add(card);app.terminal.appendCard(card)}
    pass(tiny[0].isClosed() && !tiny[6].isClosed(),"History eviction closes the oldest texture when more than six cards are appended")
    app.terminal.clearMessages();pass(tiny[6].isClosed(),"Clearing releases the remaining bounded card history")
    let slowSpec=PipelineSpec("transition",32,16,-1,2,LongSpec(0.01,0.1,128,2048,4,64));let active=PipelineJob(99,app.work.project,app.work.revision,slowSpec);active.start()
    let cancelClock=PerformanceClock();w.delay(2);active.cancel();let cancelStart=cancelClock.ms();while(!active.progress().done && cancelClock.ms()-cancelStart<5000.0){w.delay(2)}
    pass(active.progress().done && active.progress().cancelled && active.progress().result.isNone(),"In-flight cancellation propagates to the active pipeline stage and publishes no result")
    let stale=startPipeline(app,slowSpec);let changed=app.work.project.copy();changed.seed++;app.work.commit(changed);pollPipeline(app)
    pass(stale.progress().cancelled && app.pipelineJob.isNone() && app.pipelineResult.isNone(),"Input revision changes cancel a running pipeline before any result/card publication")
    app.work.acceptLoaded(readProjectText(original),"");app.refreshReference();app.syncScene();app.terminal.open=false;app.preferences.gpuEnabled=gpu;app.view.useGpu=gpu;app.cancel();enterWorkflow(app,0);pollStudy(app);pollLong(app,app.clockNow);app.camera.focusScene(app.scene);app.tool=0
}
