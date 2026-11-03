package firebreak

import sdl.*
import magic.core.model.*
import magic.core.message.Conversation
import std.collection.{HashMap,ArrayList}
import stdx.encoding.json.*

class ScriptedLabModel <: ChatModel {
    var turn:Int64=0
    public prop provider:String {get(){"test"}}
    public prop name:String {get(){"scripted-lab"}}
    public prop contextLength:Int64 {get(){32768}}
    public mut prop maxTokens:?Int64 {get(){None};set(_) {}}
    public func create(r:ChatRequest):ChatResponse {ChatResponse(name,asyncCreate(r).message)}
    public func asyncCreate(_:ChatRequest):AsyncChatResponse {
        let actions=["<action>{\"name\":\"read_lab\",\"arguments\":{}}</action>","<action>{\"name\":\"control_lab\",\"arguments\":{\"action\":\"density_scan\",\"samples\":8}}</action>","<action>{\"name\":\"read_lab\",\"arguments\":{}}</action>","<answer>已提交密度扫描；完成后读取真实结果，应用仍需手动确认。</answer>"]
        let chunks=ArrayList<AsyncChatChunk>([firebreakChunk(actions[min(turn,3)]),firebreakChunk("",done:true)]);turn++;return firebreakStream(name,chunks.iterator())
    }
}
func labArguments(action:String):HashMap<String,JsonValue> {let j=HashMap<String,JsonValue>();j["action"]=JsonString(action);return j}
func labTestJob(app:App):AgentChatJob {AgentChatJob(app.work.project,app.work.revision,app.agentSettings,app.terminal.epoch,"test",Conversation())}
func waitAgentLab(app:App,w:SdlWindow,job:AgentChatJob):Unit {
    let clock=PerformanceClock();let start=clock.ms()
    while(!job.progress().done && clock.ms()-start<95000.0){pollAgentChat(app);pollStudy(app);pollLong(app,app.clockNow);w.delay(5)}
    require(job.progress().done,"Agent lab deadline exceeded");pollAgentChat(app)
}
func verifyAgentLab(app:App,w:SdlWindow,live!:Bool=false):Unit {
    let gpu=app.preferences.gpuEnabled
    app.menuOpen=false;app.terminal.open=false;app.cancel();app.work.acceptLoaded(densityForest(Project(nx:32,nz:32),0.6,42),"");app.syncScene();enterWorkflow(app,0)
    app.terminal.epoch++;app.terminal.rounds.clear();app.terminal.clearMessages();app.terminal.agentPlan=None;app.terminal.seenEvents=0
    let source=app.work.project.text();let revision=app.work.revision;let initial=readLab(app)
    pass(!initial.contains("\"density\"") && !initial.contains("\"long\"") && initial.contains("\"largestPlannedCluster\""),"Lab reads actual forest structure and leaves unavailable experiment results absent")
    let job=labTestJob(app);let invalid=labArguments("apply");let beforeStage=currentWorkflow(app)
    pass(rejected({=>controlLab(app,job,invalid)}) && app.work.project.text()==source,"The model control surface has no Apply or project-edit action")
    invalid["action"]=JsonString("workflow");invalid["stage"]=JsonString("1")
    pass(rejected({=>controlLab(app,job,invalid)}) && currentWorkflow(app)==beforeStage,"Textual integers are rejected before changing workflow")
    invalid["stage"]=JsonInt(1);invalid["extra"]=JsonInt(2)
    pass(rejected({=>controlLab(app,job,invalid)}),"Unknown model arguments are rejected at the controller boundary")
    app.startCell=0;app.endCell=1
    pass(rejected({=>controlLab(app,job,labArguments("single_reset"))}) && app.startCell==0,"Model commands preserve pending manual selections")
    app.cancel();app.agentChat=Some(job)
    if(live){
        require(!app.agentSettings.apiKey.isEmpty(),"Live lab check needs locally saved API settings")
        let real=AgentChatJob(app.work.project,app.work.revision,app.agentSettings,app.terminal.epoch,"请依次调用read_lab、control_lab(action=density_scan,samples=8)、read_lab。只启动密度扫描，报告真实任务状态，不修改或应用森林。",Conversation());app.agentChat=Some(real);real.start();waitAgentLab(app,w,real)
        require(real.progress().error.isEmpty() && real.progress().events.contains("[tool] control_lab") && real.progress().events.contains("[tool] read_lab"),"Live model did not exercise lab tools")
        pass(app.work.project.text()==source,"Live DeepSeek invokes lab tools without editing the forest")
    }else{spawn{job.execute(modelOverride:Some(ScriptedLabModel()))};waitAgentLab(app,w,job)
        pass(job.progress().error.isEmpty() && job.progress().events.contains("[tool] control_lab") && job.progress().events.contains("[tool] read_lab"),"Real CangjieMagic orchestration marshals model tools to the native UI owner thread")
    }
    waitStudy(app,w);let state=JsonValue.fromStr(readLab(app)).asObject()
    pass(state["density"].asObject()["samplesPerDensity"].asInt().getValue()==8 && app.work.project.text()==source && app.work.revision==revision,"Agent-started density scan publishes eight real replicates without a workspace edit")
    app.preferences.gpuEnabled=true;app.terminal.open=true;render(app,w,capture:if(live){"artifacts/r5-agent-lab-live.png"}else{"artifacts/r5-agent-lab.png"});app.terminal.open=false
    let owner=labTestJob(app);let compare=labArguments("structure_compare");compare["samples"]=JsonInt(8);compare["density_index"]=JsonInt(12);compare["dose"]=JsonInt(4)
    controlLab(app,owner,compare);waitStudy(app,w)
    pass(app.interventionResult.getOrThrow().rows.size==32 && readLab(app).contains("\"pairedBurnDeltaSE\""),"Equal-cell agent comparisons reuse all four actual policies and paired statistics")
    let preview=labArguments("structure_preview");preview["policy"]=JsonInt(2);preview["sample"]=JsonInt(3);controlLab(app,owner,preview)
    app.terminal.open=true;previewAgentPlan(app)
    pass(!app.terminal.open && app.studyPanel && app.studyPolicy==2 && app.studyPreview.getOrThrow().project.count(app.studyPreview.getOrThrow().project.treatment)==4 && app.work.project.text()==source,"Slash preview exposes the exact structural sample while preserving manual Apply")
    app.preferences.gpuEnabled=true;render(app,w,capture:"artifacts/r5-structure-preview.png")
    let longArgs=labArguments("long_run");longArgs["warmup"]=JsonInt(16);longArgs["drives"]=JsonInt(64);longArgs["samples"]=JsonInt(2);longArgs["capacity"]=JsonInt(16)
    controlLab(app,owner,longArgs);waitLong(app,w)
    let actual=app.longResult.getOrThrow();let report=JsonValue.fromStr(readLab(app)).asObject()["long"].asObject()
    pass(app.longDrives==64 && app.longSamples==2 && report["observedDrives"].asInt().getValue()==64 && report["policies"].asArray().getItems()[0].asObject()["burnedCellEvents"].asInt().getValue()==actual.sum(0,0),"Lab reading exposes real long-run totals, exact parameters and warmup semantics")
    let replay=app.longReplay.getOrThrow();controlLab(app,owner,labArguments("long_step"));pass(replay.cursor==1,"Agent replay step uses the same sampled-checkpoint cursor as the GUI")
    controlLab(app,owner,labArguments("long_play"));app.terminal.open=true;pollLong(app,app.clockNow+1000)
    pass(replay.cursor==1 && JsonValue.fromStr(readLab(app)).asObject()["replayBlockedByOverlay"].asBool().getValue(),"Long playback remains blocked by the terminal and reports the overlay explicitly")
    controlLab(app,owner,labArguments("long_pause"));app.terminal.open=false
    pass(!replay.playing && app.work.project.text()==source,"Agent pause preserves both the checkpoint and source forest")
    render(app,w,capture:"artifacts/r5-long-state.png")
    pass(rejected({=>controlLab(app,owner,labArguments("single_step"))}),"Single-fire agent operations require a manually chosen valid ignition")
    let ignited=app.work.project.copy();ignited.ignition=0;ignited.vegetation[0]=1;app.work.acceptLoaded(ignited,"");app.syncScene();let singleOwner=labTestJob(app);let singleSource=app.work.project.text()
    controlLab(app,singleOwner,labArguments("single_step"));let single=app.experiment.run.getOrThrow();pass(single.cursor==1 && !single.running,"Agent single-step advances the existing synchronous fire controller once")
    controlLab(app,singleOwner,labArguments("single_start"));pass(single.running,"Agent starts single-fire playback through the shared controller")
    controlLab(app,singleOwner,labArguments("single_pause"));pass(!single.running && app.work.project.text()==singleSource,"Agent pauses single-fire playback without editing ignition or forest")
    let pairArgs=labArguments("compare_run");pairArgs["samples"]=JsonInt(4);controlLab(app,singleOwner,pairArgs)
    let clock=PerformanceClock();let began=clock.ms();while(app.evalJob.isSome() && clock.ms()-began<30000.0){app.pollEvaluation(app.clockNow);w.delay(5)}
    pass(app.evalResult.isSome() && readLab(app).contains("\"comparison\"") && app.work.project.text()==singleSource,"Agent starts and reads actual matched project evaluation without budget-based candidate selection")
    controlLab(app,singleOwner,labArguments("cancel_tasks"));pass(app.studyJob.isNone() && app.longJob.isNone() && app.evalJob.isNone(),"Cancel command stops outstanding lab tasks through the shared controllers")
    enterWorkflow(app,1)
    let cancelled=labTestJob(app);let task=ForestStudyJob(app.work.project,app.work.revision,8);cancelled.ownStudy(task);cancelled.cancel()
    pass(task.isCancelled(),"Stopping a request cancels the experiment task owned by that request")
    let stale=labTestJob(app);let queued=AgentLabCall(labArguments("workflow"),false);queued.arguments["stage"]=JsonInt(2);stale.pendingLab=Some(queued)
    let changed=app.work.project.copy();changed.seed++;app.work.commit(changed);pollAgentLab(app,stale)
    pass(queued.result().getOrThrow().contains("rejected") && currentWorkflow(app)==1,"A stale queued command is rejected before dispatching UI actions")
    let stopped=labTestJob(app);let pending=AgentLabCall(labArguments("workflow"),false);pending.arguments["stage"]=JsonInt(2);stopped.pendingLab=Some(pending);stopped.cancel();pollAgentLab(app,stopped)
    pass(pending.result().getOrThrow().contains("rejected") && currentWorkflow(app)==1,"A cancelled queued command cannot change the workflow")
    let waiting=labTestJob(app);waiting.worker=Some(spawn{waiting.execute(modelOverride:Some(ScriptedLabModel()))});w.delay(20);waiting.cancel();waiting.wait()
    pass(waiting.progress().done && waiting.progress().cancelled,"Cancellation wakes and joins a model worker waiting for an unserviced UI request")
    let timeout=AgentChatJob(app.work.project,app.work.revision,app.agentSettings,app.terminal.epoch,"test",Conversation(),timeoutMillis:20.0);timeout.worker=Some(spawn{timeout.execute(modelOverride:Some(ScriptedLabModel()))});w.delay(30);timeout.wait()
    pass(timeout.progress().done && timeout.progress().error.contains("超时"),"An unserviced UI request expires without requiring the UI thread to unblock it")
    app.terminal.open=false;app.agentChat=None;app.preferences.gpuEnabled=gpu;app.work.acceptLoaded(Project(),"");app.refreshReference();app.syncScene();app.cancel();enterWorkflow(app,0);pollStudy(app);pollLong(app,app.clockNow);app.camera.focusScene(app.scene);app.tool=0
}
