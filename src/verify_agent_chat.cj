package firebreak

import sdl.*
import magic.core.model.*
import magic.core.message.Conversation
import std.collection.{ArrayList,HashMap}
import std.fs.File
import magic.config.Config
import magic.utils.Importer
import stdx.encoding.json.*

class BrokenAgentChunks <: Iterator<AsyncChatChunk> {
    let job:AgentChatJob
    var initial=true
    init(job:AgentChatJob){this.job=job}
    public func next():?AsyncChatChunk {
        if(initial){initial=false;return Some(firebreakChunk("<answer>尚未完成的回答"))}
        job.transportFailed("Incomplete model stream");throw Exception("Incomplete model stream")
    }
}
class BrokenAgentModel <: ChatModel {
    let job:AgentChatJob
    init(job:AgentChatJob){this.job=job}
    public prop provider:String {get(){"test"}}
    public prop name:String {get(){"broken-stream"}}
    public prop contextLength:Int64 {get(){32768}}
    public mut prop maxTokens:?Int64 {get(){None};set(_) {}}
    public func create(r:ChatRequest):ChatResponse {ChatResponse(name,asyncCreate(r).message)}
    public func asyncCreate(_:ChatRequest):AsyncChatResponse {firebreakStream(name,BrokenAgentChunks(job))}
}
func verifyAgentFailures(app:App):Unit {
    try(api=AgentWinHttp()){
        var count:UInt32=0
        let (ok,code)=unsafe{let value=CFunc<(CPointer<Unit>,CPointer<UInt8>,UInt32,CPointer<UInt32>)->Int32>(api.functions[8])(CPointer<Unit>(),CPointer<UInt8>(),0,inout count);(value,if(value==0){GetLastError()}else{UInt32(0)})}
        // The ordinary Cangjie FFI transition can clear Windows last-error (see local probe).
        // FALSE is still a failure; never reinterpret a lost code as success.
        pass(ok==0 && rejected({=>api.checkCaptured((ok,code))}) && rejected({=>api.checkCaptured((0,0))}),"Native read failures remain failures even when the FFI loses the OS error code")
    }
    let p=Project();let settings=DeepSeekSettings("")
    let make={=>AgentChatJob(p,app.work.revision,settings,app.terminal.epoch,"test",Conversation())}
    pass(agentFailureText("DeepSeek HTTP 503").contains("服务过载") && !agentFailureText("DeepSeek HTTP 503").contains("Key") && agentFailureText("DeepSeek HTTP 401").contains("API Key") && agentFailureText("DeepSeek HTTP 402").contains("余额"),"Service overload, authentication and balance have distinct actionable diagnostics")
    pass(!agentFailureText("secret-key response body").contains("secret-key") && !agentFailureText("WinHTTP 0").contains("WinHTTP 0"),"Unknown transport exceptions expose neither arbitrary text nor a misleading zero error code")
    let retry=make();let count=[Int64(0)]
    retryAgentConnect(retry,{=>count[0]++;if(count[0]<3){throw Exception("DeepSeek HTTP 503")}})
    pass(count[0]==3 && retry.progress().events.size==2,"Transient HTTP rejection retries at most twice before accepting success")
    let exhausted=make();let failures=[Int64(0)]
    let rejectedAll=rejected({=>retryAgentConnect(exhausted,{=>failures[0]++;throw Exception("DeepSeek HTTP 503")})})
    pass(rejectedAll && failures[0]==3,"Repeated overload stops after three total attempts")
    for(detail in ["DeepSeek HTTP 401","DeepSeek HTTP 402","DeepSeek HTTP 422","WinHTTP 12002","Incomplete model stream"]){let n=[Int64(0)];require(rejected({=>retryAgentConnect(make(),{=>n[0]++;throw Exception(detail)})}) && n[0]==1,"Unsafe retry of permanent error or broken stream")}
    pass(true,"Permanent errors, network failures and broken streams never automatically replay a model request")
    let stopped=make();let starts=[Int64(0)]
    pass(rejected({=>retryAgentConnect(stopped,{=>starts[0]++;stopped.cancel();throw Exception("DeepSeek HTTP 503")})}) && starts[0]==1,"Cancellation interrupts retry backoff without another request")
    let failed=make();app.terminal.rounds.clear();app.terminal.clearMessages();app.terminal.seenEvents=0;app.agentChat=Some(failed)
    failed.execute(modelOverride:Some(BrokenAgentModel(failed)));pollAgentChat(app)
    pass(failed.progress().error.contains("模型流提前结束") && app.terminal.rounds.isEmpty() && failed.progress().events.size==1,"A broken answer stream preserves its cause and cannot publish a successful conversation round")
    pass(rejected({=>failed.site()}) && failed.progress().events.size==1,"No tools execute after a terminal transport failure")
}

// Deterministic real framework orchestration; this model never accesses a key.
class ScriptedAgentModel <: ChatModel {
    var turn:Int64=0
    public prop provider:String {get(){"test"}}
    public prop name:String {get(){"scripted"}}
    public prop contextLength:Int64 {get(){32768}}
    public mut prop maxTokens:?Int64 {get(){None};set(_) {}}
    public func create(r:ChatRequest):ChatResponse {ChatResponse(name,asyncCreate(r).message)}
    public func asyncCreate(_:ChatRequest):AsyncChatResponse {
        let texts=["<action>{\"name\":\"read_site\",\"arguments\":{}}</action>","<action>{\"name\":\"evaluate_candidates\",\"arguments\":{}}</action>","<answer>实际工具评估已完成；","请预览后手动应用。</answer>"]
        let pieces=ArrayList<AsyncChatChunk>()
        if(turn<2){pieces.add(firebreakChunk(texts[turn]))}else{pieces.add(firebreakChunk(texts[2]));pieces.add(firebreakChunk(texts[3]))}
        turn++;pieces.add(firebreakChunk("",done:true));return firebreakStream(name,pieces.iterator())
    }
}
func verifyAgentChat(app:App,w:SdlWindow,live!:Bool=false):Unit {
    if(live){
        require(app.agentConnection.isSome() && app.agentSettings.connectionState==1,"Saved credentials did not start background verification")
        let connection=app.agentConnection.getOrThrow();let startupClock=PerformanceClock();let startupStart=startupClock.ms()
        while(!connection.progress().done && startupClock.ms()-startupStart<30000.0){w.delay(10)}
        pollAgentConnection(app)
        require(app.agentConnection.isNone() && app.agentSettings.connectionState==2,"Startup connection check: "+connection.progress().error)
        pass(app.agentConnection.isNone() && app.agentSettings.connectionState==2,"Startup automatically verifies the saved API key/model without a menu action")
    }
    let decoder=AgentSseDecoder();var decoded=""
    let wire=": heartbeat\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"林😀\"}}]}\r\n\ndata: {\"choices\":[]}\n\ndata: [DONE]\n\n"
    for(byte in wire.toArray()){decoder.pending.add(byte);while(let Some(text)<-decoder.take()){decoded+=text}}
    pass(decoded=="林😀" && decoder.finished,"SSE decoding preserves split Chinese/emoji, CRLF, heartbeats, usage-only chunks and DONE")
    let malformed=AgentSseDecoder();malformed.pending=ArrayList<UInt8>("data: {broken}\n".toArray())
    pass(rejected({=>malformed.take()}),"Malformed SSE fails instead of becoming a model answer")
    verifyAgentFailures(app)
    let p=planningCamp();app.cancel();app.work.commit(p);let original=app.work.project.text();let rev=app.work.revision
    let settings=if(live){DeepSeekSettings("agent.local.json")}else{DeepSeekSettings("")}
    require(!live || (!settings.loadError && !settings.apiKey.isEmpty()),"Live check needs a saved local API key")
    let t=app.terminal;t.open=true;t.clearMessages();t.rounds.clear();t.revision++;t.epoch++;t.seenEvents=0
    app.agentSettings.model=settings.model;app.agentSettings.apiKey=settings.apiKey
    let prompt=(if(live){"新增处理费用最多100元。"}else{""})+"请先调用 read_site，再调用 evaluate_candidates，简要说明当前预算、推荐候选编号、费用与留出复核结果。不要修改场地。"
    let job=AgentChatJob(p,rev,app.agentSettings,t.epoch,prompt,Conversation())
    app.agentChat=Some(job)
    if(live){job.start()}else{spawn{job.execute(modelOverride:Some(ScriptedAgentModel()))}}
    let clock=PerformanceClock();let start=clock.ms();var observed=false
    while(!job.progress().done){
        if(clock.ms()-start>100000.0){job.cancel();throw Exception("Live verification deadline exceeded")}
        let state=job.progress();if(!state.answer.isEmpty()){observed=true}
        pollAgentChat(app);w.delay(10)
    }
    pollAgentChat(app);let result=job.progress()
    require(result.done && !result.cancelled && result.error.isEmpty(),"Agent check failed: "+result.error)
    pass(result.events.contains("[tool] read_site") && result.events.contains("[tool] evaluate_candidates"),"Agent invokes real registered CangjieMagic site and planning tools")
    pass(result.plan.isSome() && !result.answer.isEmpty() && t.rounds.size==1,"Successful agent answer retains complete evaluated candidates and conversation")
    pass(Config.importPaths.isEmpty() && Importer(Config.importPaths).importFiles("@agent.local.json").isEmpty(),"Framework file imports are disabled, including the local API configuration")
    pass(app.work.project.text()==original && app.work.revision==rev,"Model and planning tools cannot alter the source project")
    if(live){pass(job.usedCap==100.0,"Live natural-language spending cap becomes a validated numeric planning constraint");pass(observed,"Live DeepSeek answer arrives incrementally before worker completion")}
    render(app,w,capture:if(live){"artifacts/p5-agent-live.png"}else{"artifacts/p5-agent-offline.png"})
    previewAgentPlan(app)
    pass(app.suggestPanel && app.candidateVisible && app.work.project.text()==original,"Agent candidate map preview preserves the scene until manual apply")
    app.suggestionAction(75);pass(app.work.revision==rev+1,"Manual apply commits agent candidate as one undoable edit")
    app.work.history(true);app.syncScene();pass(app.work.project.text()==original,"Undo restores the original scene after manual agent candidate apply")
    pass(rejected({=>previewAgentPlan(app)}),"Revision changes invalidate old agent previews even after undo")
    let cancelled=AgentChatJob(p,app.work.revision,settings,0,"test",Conversation());cancelled.cancel();cancelled.execute(modelOverride:Some(ScriptedAgentModel()))
    pass(cancelled.progress().cancelled && cancelled.progress().events.isEmpty() && cancelled.progress().plan.isNone(),"Cancelled agent cannot begin tools or publish partial candidates")
    let stale=AgentChatJob(p,app.work.revision,app.agentSettings,t.epoch,"test",Conversation());app.agentChat=Some(stale)
    app.agentSettings.generation++;pollAgentChat(app);pass(stale.isCancelled(),"Changing API settings invalidates the active agent request")
    stale.execute(modelOverride:Some(ScriptedAgentModel()));pollAgentChat(app)
    let timed=AgentChatJob(p,app.work.revision,settings,0,"test",Conversation(),timeoutMillis:1.0);w.delay(5);timed.execute(modelOverride:Some(ScriptedAgentModel()))
    pass(timed.progress().done && timed.progress().error.contains("超时") && timed.progress().events.isEmpty(),"Expired agent requests cannot call tools and report a timeout")
    let bounded=AgentChatJob(p,app.work.revision,settings,0,"test",Conversation())
    pass(rejected({=>bounded.candidates(-1.0)}) && rejected({=>bounded.candidates(p.budget+1.0)}) && bounded.progress().plan.isNone(),"Structured spending limits reject negative and over-budget requests before evaluation")
    let invalid=HashMap<String,JsonValue>();invalid["max_additional_cost"]=JsonString("100")
    pass(rejected({=>bounded.evaluateTool(invalid)}),"Planning tool rejects textual spending values instead of silently coercing arguments")
    invalid.clear();invalid["unknown"]=JsonInt(100)
    pass(rejected({=>bounded.evaluateTool(invalid)}),"Planning tool rejects unknown parameters at its executable boundary")
    bounded.candidates(0.0);pass(bounded.progress().plan.getOrThrow().entries.isEmpty(),"A zero additional spending cap yields no paid candidates without changing the project")
    if(live){
        let stopping=AgentChatJob(p,app.work.revision,settings,0,"请写一篇至少1500字的中文渗流相变介绍，不需要调用工具。",Conversation())
        stopping.start();let waitStart=clock.ms()
        while(stopping.progress().answer.isEmpty() && !stopping.progress().done && clock.ms()-waitStart<20000.0){w.delay(10)}
        let inFlight = !stopping.progress().done && !stopping.progress().answer.isEmpty()
        let cancelStart=clock.ms();stopping.cancel();stopping.wait()
        pass(inFlight && stopping.progress().cancelled && clock.ms()-cancelStart<15000.0,"Stopping a live streaming request joins its worker and closes native HTTP resources promptly")
    }
    if(live){File.writeTo("artifacts/p5-agent-live.txt",("Authenticated DeepSeek streaming + real CangjieMagic tools: PASS\nTools: read_site, evaluate_candidates\nFrozen synthetic planningCamp fixture; no user images or credentials exported.\nPreview, manual apply, undo and stale revision checks: PASS\n").toArray())}
    t.open=false;app.suggestPanel=false;app.candidateVisible=false;app.agentSettings.apiKey=""
}
