package firebreak

import magic.agent.base.BaseAgent
import magic.agent_executor.react.ReactExecutor
import magic.core.agent.{AgentRequest,AgentResponseStatus}
import magic.core.model.*
import magic.core.message.{Message,Conversation}

import magic.tool.{NativeFuncTool,SimpleToolManager}
import magic.config.Config
import magic.jsonable.TypeSchema
import std.sync.Mutex
import std.collection.{ArrayList,HashMap}
import std.convert.*
import stdx.encoding.json.*

class NativeChatChunks <: Iterator<AsyncChatChunk> {
    let stream:AgentSse
    var done=false
    init(stream:AgentSse){this.stream=stream}
    public func next():?AsyncChatChunk {
        if(done){return None}
        if(let Some(text)<-stream.nextText()){return Some(firebreakChunk(text))}
        done=true;return Some(firebreakChunk("",done:true))
    }
}
class DeepSeekModel <: ChatModel {
    let job:AgentChatJob
    var active:?AgentSse=None
    var limit:?Int64=Some(2048)
    init(job:AgentChatJob){this.job=job}
    public prop provider:String {get(){"deepseek"}}
    public prop name:String {get(){job.model}}
    public prop contextLength:Int64 {get(){32768}}
    public mut prop maxTokens:?Int64 {get(){limit};set(v){limit=v}}
    public func create(request:ChatRequest):ChatResponse {
        let response=asyncCreate(request);return ChatResponse(name,response.message)
    }
    public func asyncCreate(request:ChatRequest):AsyncChatResponse {
        close();job.checkActive()
        let messages=JsonArray()
        for(m in request.messageList){let j=JsonObject();j.put("role",JsonString(m.role.toString()));j.put("content",JsonString(m.content));messages.add(j)}
        let body=JsonObject();body.put("model",JsonString(name));body.put("messages",messages);body.put("stream",JsonBool(true));body.put("max_tokens",JsonInt(2048))
        let thinking=JsonObject();thinking.put("type",JsonString("disabled"));body.put("thinking",thinking)
        if(let Some(stops)<-request.stop){let a=JsonArray();for(s in stops){a.add(JsonString(s))};body.put("stop",a)}
        let stream=AgentSse(job.credential(),body.toJsonString(),{=>job.isCancelled()},{=>job.expired()})
        active=Some(stream);return firebreakStream(name,NativeChatChunks(stream))
    }
    func close():Unit {if(let Some(s)<-active){s.close()};active=None}
}
class AgentChatState {
    let done:Bool;let cancelled:Bool;let answer:String;let error:String;let events:Array<String>;let plan:?PlanSearchResult
    init(done:Bool,cancelled:Bool,answer:String,error:String,events:Array<String>,plan:?PlanSearchResult){this.done=done;this.cancelled=cancelled;this.answer=answer;this.error=error;this.events=events;this.plan=plan}
}
class AgentChatJob {
    let source:String;let revision:Int64;let generation:Int64;let epoch:Int64
    let model:String;private let key:String;let question:String;let conversation:Conversation
    let lock=Mutex();let clock=PerformanceClock();let began:Float64
    var done=false;var cancelled=false;var answer="";var error="";var events=ArrayList<String>();var plan:?PlanSearchResult=None
    var search:?PlanSearchJob=None
    var worker:?Future<Unit>=None
    let timeoutMillis:Float64
    var toolCalls:Int64=0
    var usedCap:Float64= -1.0
    var pendingLab:?AgentLabCall=None
    var ownedStudy:?ForestStudyJob=None;var ownedLong:?LongJob=None;var ownedEvaluation:?EvaluationJob=None
    func ownStudy(task:ForestStudyJob):Unit {synchronized(lock){ownedStudy=Some(task);if(cancelled){task.cancel()}}}
    func ownLong(task:LongJob):Unit {synchronized(lock){ownedLong=Some(task);if(cancelled){task.cancel()}}}
    func ownEvaluation(task:EvaluationJob):Unit {synchronized(lock){ownedEvaluation=Some(task);if(cancelled){task.cancel()}}}
    func takeLabCall():?AgentLabCall {synchronized(lock){let call=pendingLab;pendingLab=None;return call}}
    func lab(args:HashMap<String,JsonValue>,readOnly:Bool):String {
        require(!readOnly || args.isEmpty(),"read_lab accepts no arguments");event(if(readOnly){"read_lab"}else{"control_lab"})
        let frozen=HashMap<String,JsonValue>();for((k,v) in args){frozen[k]=v};let call=AgentLabCall(frozen,readOnly)
        synchronized(lock){require(pendingLab.isNone(),"Another UI request is pending");pendingLab=Some(call)}
        var response:?String=None
        while(response.isNone()){checkActive();response=call.result();if(response.isNone()){sleep(Duration.millisecond*5)}}
        checkActive();return response.getOrThrow()
    }
    init(p:Project,revision:Int64,settings:DeepSeekSettings,epoch:Int64,question:String,conversation:Conversation,timeoutMillis!:Float64=90000.0){
        require(timeoutMillis>0.0 && timeoutMillis<=90000.0,"Invalid agent deadline");this.timeoutMillis=timeoutMillis
        p.validate();source=p.text();this.revision=revision;generation=settings.generation;model=settings.model;key=settings.apiKey
        this.epoch=epoch;this.question=question;this.conversation=conversation;began=clock.ms()
    }
    func credential():String {key}
    func isCancelled():Bool {synchronized(lock){return cancelled}}
    func expired():Bool {clock.ms()-began>timeoutMillis}
    func checkActive():Unit {require(!isCancelled(),"Cancelled");require(!expired(),"Deadline exceeded")}
    func cancel():Unit {synchronized(lock){cancelled=true;if(let Some(s)<-search){s.cancel()};if(let Some(s)<-ownedStudy){s.cancel()};if(let Some(s)<-ownedLong){s.cancel()};if(let Some(s)<-ownedEvaluation){s.cancel()}}}
    func progress():AgentChatState {synchronized(lock){return AgentChatState(done,cancelled,answer,error,events.toArray(),plan)}}
    func event(name:String):Unit {checkActive();synchronized(lock){toolCalls++;require(toolCalls<=8,"Tool limit exceeded");events.add("[tool] "+name)}}
    func site():String {
        event("read_site");let p=readProjectText(source);var forest:Int64=0;var protected:Int64=0;var forbidden:Int64=0
        for(i in 0..p.cells){if(p.fuel(i)>0.0){forest++};if(p.targets[i]!=0){protected++};if(p.forbidden[i]!=0){forbidden++}}
        return "revision=${revision}; grid=${p.nx}x${p.nz}; forest=${forest}; protected=${protected}; forbidden=${forbidden}; metersWide=${p.metersWide}; budget=${p.budget}; currentCost=${p.cost()}; ignition=${p.ignition}; spreadProbability=${p.spreadProbability}; burnSteps=${p.burnSteps}; seed=${p.seed}. Area units are m2. Model scenario metrics are not real wildfire probabilities."
    }
    func candidates(cap:Float64):String {
        let p=readProjectText(source);require(cap>=0.0 && cap<=max(0.0,p.budget-p.cost()),"Additional cost must be within the current remaining budget")
        require(usedCap<0.0 || usedCap==cap,"Use a new request to change the cost limit");usedCap=cap
        event("evaluate_candidates")
        var cached:?PlanSearchResult=None;synchronized(lock){cached=plan}
        if(cached.isNone()){
            let limited=p.copy();limited.budget=p.cost()+cap
            let s=PlanSearchJob(limited,revision,abort:{=>expired()})
            synchronized(lock){search=Some(s);if(cancelled){s.cancel()}}
            s.execute();checkActive();let result=s.progress();require(result.result.isSome(),"No complete planning result")
            synchronized(lock){search=None;let r=result.result.getOrThrow();plan=Some(PlanSearchResult(source,revision,r.current,r.heldout,r.entries,r.selected))}
            synchronized(lock){cached=plan}
        }
        let r=cached.getOrThrow();let lines=ArrayList<String>()
        lines.add("Training 8 paired scenarios; holdout 8. Finite candidate family, not global optimum. selected=${r.selected}; recommended=${r.recommended}; -1 means none. No scene edits have been applied. Baseline training remaining=${r.current.mean(1)}, contacts=${r.current.mean(2)}; holdout remaining=${r.heldout.mean(1)}, contacts=${r.heldout.mean(2)}.")
        for(i in 0..r.entries.size){let e=r.entries[i];lines.add("id=${i}; deltaCost=${e.candidate.deltaCost}; train remaining=${e.training.mean(1)}, contacts=${e.training.mean(2)}; holdout remaining=${e.review.mean(1)}, contacts=${e.review.mean(2)}; eligible=${e.eligible}; verified=${e.verified}")}
        return String.join(lines.toArray(),delimiter:"\n")
    }
    func tools():SimpleToolManager {
        let a=NativeFuncTool(name:"read_site",description:"Read frozen current site, budget, exclusions and fire parameters. Call for all factual questions about this site.",execFn:Some({args=>require(args.isEmpty(),"No arguments accepted");site()}))
        let b=NativeFuncTool(
            name:"evaluate_candidates",
            description:"Evaluate finite legal firebreak candidates, preserving protected/excluded cells. Optional max_additional_cost limits added cost in CNY, within remaining project budget. Returns stable ids and training/holdout metrics. Read-only; one cost limit per request.",
            parameters:[("max_additional_cost","Maximum ADDITIONAL cost in CNY, no higher than remaining project budget",TypeSchema.Float,false)],
            execFn:Some({args=>evaluateTool(args)}))
        let c=NativeFuncTool(name:"read_lab",description:"Read LIVE revision-checked forest/workflow/task progress and available R3 density/structure, R4 long-run, single-fire and paired-comparison metrics. Missing fields mean unavailable, not zero. Always call for current experiment facts; historical chat facts may be stale.",execFn:Some({args=>lab(args,true)}))
        let d=NativeFuncTool(name:"control_lab",description:"Operate existing lab controls on the UI thread without editing project data. Actions: workflow(stage 0..3), density_scan(samples 8/32/64), structure_compare(samples,density_index 0..20,dose 1..128), structure_preview(density_index,sample,policy 0 baseline/1 random/2 connector/3 center strip), long_run(growth,lightning,warmup,drives,samples,capacity), compare_run(samples 4/16/32), single_start/single_pause/single_step/single_reset, long_play/long_pause/long_step/long_seek(frame), cancel_tasks. Other arguments must be omitted. Run returns task started/progress, not completed results: read_lab later. Previews never Apply; user uses /preview then manually applies. No project/ignition/settings edits or files. Long replay remains blocked while terminal/menu open. Only act when user asks to operate.",parameters:[
            ("action","One supported action",TypeSchema.Str,true),("stage","0 Build Forest, 1 Observe Forest, 2 Intervene, 3 Compare",TypeSchema.Int,false),("samples","Independent replicate count",TypeSchema.Int,false),("density_index","Tested p index 0..20, p=index*0.05",TypeSchema.Int,false),("dose","Equal clearing count 1..128",TypeSchema.Int,false),("policy","Preview policy 0..3",TypeSchema.Int,false),("sample","Zero-based preview sample",TypeSchema.Int,false),("growth","Per-empty-site growth probability",TypeSchema.Float,false),("lightning","Whole-grid strike probability per round",TypeSchema.Float,false),("warmup","Excluded warmup rounds 0..2048",TypeSchema.Int,false),("drives","Measured rounds 1..8192",TypeSchema.Int,false),("capacity","Ideal suppression size 0..16384",TypeSchema.Int,false),("frame","Zero-based sampled checkpoint",TypeSchema.Int,false)],execFn:Some({args=>lab(args,false)}))
        return SimpleToolManager([a,b,c,d])
    }
    func evaluateTool(args:HashMap<String,JsonValue>):String {
        require(args.size<=1 && (args.isEmpty() || args.contains("max_additional_cost")),"Unknown arguments")
        let p=readProjectText(source)
        let cap=if(args.isEmpty()){max(0.0,p.budget-p.cost())}else{
            let value=args["max_additional_cost"]
            require(value is JsonInt || value is JsonFloat,"Expected number")
            Float64.parse(value.toJsonString())
        }
        return candidates(cap)
    }
    func start():Unit {worker=Some(spawn{execute()})}
    func wait():Unit {if(let Some(task)<-worker){task.get()}}

    func execute(modelOverride!:?ChatModel=None):Unit {
        let native=DeepSeekModel(this)
        try{
            checkActive();Config.enableParallelToolCall=false;Config.enableAgentLog=false;Config.saveModelRequest=false;Config.importPaths=[];Config.logLevel="error"
            let agent=BaseAgent(model:modelOverride ?? native,name:"Firebreak researcher",executor:Some(ReactExecutor(loop:6)),toolManager:tools(),systemPrompt:"You are Firebreak's forest experiment assistant. Use read_lab for current experiment facts and control_lab only for user-requested operations. A started asynchronous task is not a completed result. Do not invent missing metrics or keep polling in a loop; report running status and let the user ask later. Fixed-cell structure comparison uses control_lab structure_compare, never monetary evaluate_candidates. Critically distinguish density p from single-fire spread q and whole-grid lightning probability. Long runs are DS-inspired idealizations, not SOC proof. RAG is not installed. Manual Apply remains mandatory for every forest change. Answer in the user's language, concise plain text. Use real tools for site facts and planning; never invent tool results or claim scene edits. Tool snapshots are the ONLY current site truth; conversation site facts can be stale. Budget/land constraints cannot be changed by you. For a lower spending cap, pass max_additional_cost as a validated numeric tool argument, subtracting existing cost if the user means total cost. Higher budgets require changing project settings first. Never claim optimality or real-world wildfire forecasts. Monetary-budget recommendations require evaluate_candidates; forest structure comparisons use structure_compare and read_lab. Explain training versus holdout; no verified recommendation if recommended=-1. Results are read-only, user must /preview then manually Apply in the map. No filesystem, shell, networking, other agents or external tools are available. Follow the framework action/answer protocol; do not include private reasoning in your final answer.")
            let response=agent.asyncChat(AgentRequest(question,conversation:Some(conversation)))
            while(let Some(chunk)<-response.next()){
                checkActive();synchronized(lock){require(answer.size+chunk.size<=16384,"Answer exceeds display bound");answer+=chunk}
            }
            checkActive();require(response.status==AgentResponseStatus.Success,"Model response failed")
            synchronized(lock){require(!answer.trimAscii().isEmpty(),"Empty model answer")}
        }catch(_:Exception){synchronized(lock){if(!cancelled){error=if(expired()){"请求超时 / Request timed out"}else{"模型请求失败，请检查网络、余额、模型名称或 API 设置 / Model request failed; check network, balance, model or API settings"}};if(let Some(task)<-ownedStudy){task.cancel()};if(let Some(task)<-ownedLong){task.cancel()};if(let Some(task)<-ownedEvaluation){task.cancel()}}}
        finally{native.close();synchronized(lock){search=None;done=true}}
    }
}
func pollAgentChat(app:App):Unit {
    if(let Some(job)<-app.agentChat){
        let t=app.terminal
        if(job.revision!=app.work.revision || job.generation!=app.agentSettings.generation || job.epoch!=t.epoch){job.cancel()}
        if(!job.isCancelled()){pollAgentLab(app,job)}
        var state=job.progress()
        if(state.done && job.source!=app.work.project.text()){job.cancel();state=job.progress()}
        if(!state.cancelled){
            while(t.seenEvents<state.events.size){t.append(state.events[t.seenEvents]);t.seenEvents++}
            if(state.answer!=t.streamText){t.streamText=state.answer;t.revision++}
        }
        if(state.done){
            app.agentChat=None;t.streamText="";t.revision++
            if(state.cancelled){t.append(app.t("请求已取消；旧结果不再发布。","Request cancelled; stale results are not published."))}
            else if(!state.error.isEmpty()){t.append(state.error)}
            else{
                t.append(state.answer);t.rounds.add((job.question,state.answer))
                var bytes:Int64=0;for(round in t.rounds){bytes+=round[0].size+round[1].size}
                while(t.rounds.size>8 || bytes>49152){bytes-=t.rounds[0][0].size+t.rounds[0][1].size;t.rounds.remove(at:0)}
                if(let Some(result)<-state.plan){t.agentPlan=Some(result);t.planSource=job.source;t.planRevision=job.revision;t.append(app.t("候选已就绪：输入 /preview 查看地图，再手动应用。","Candidates ready: /preview opens the map; apply manually."))}
                app.agentSettings.connectionState=2
            }
        }
    }
}
func startAgentChat(app:App,text:String):Unit {
    require(app.agentChat.isNone(),app.t("请求仍在执行，请先停止。","A request is active; stop it first."))
    if(app.agentSettings.apiKey.isEmpty()){app.terminal.append(app.t("请先在菜单 → 智能体设置填写并保存 API Key。","Save an API key in Menu > Agent Settings first."));return}
    let t=app.terminal;let c=Conversation()
    for(round in t.rounds){c.addChatRound(Message.user(round[0]),Message.assistant(round[1]))}
    let job=AgentChatJob(app.work.project,app.work.revision,app.agentSettings,t.epoch,text,c)
    t.seenEvents=0;t.streamText="";t.agentPlan=None;app.agentChat=Some(job);t.append(app.t("正在连接 DeepSeek…","Connecting to DeepSeek…"));job.start()
}
func previewAgentPlan(app:App):Unit {
    let t=app.terminal
    if(t.agentPlan.isNone()){
        pollStudy(app);pollLong(app,app.clockNow)
        require((app.studyPanel && app.studyPreview.isSome()) || (app.longPanel && app.longReplay.isSome()),app.t("暂无有效预览，请先运行实验并选择样本。","No current preview; run an experiment and select a sample first."))
        t.open=false;return
    }
    let r=t.agentPlan.getOrThrow()
    require(t.planRevision==app.work.revision && t.planSource==app.work.project.text(),app.t("场地已修改，请重新请求建议。","Site changed; request new suggestions."))
    if(let Some(old)<-app.searchJob){old.cancel();app.searchJob=None}
    app.openSuggestions();app.searchResult=Some(r);app.candidateIndex=max(0,r.selected);app.candidateVisible = !r.entries.isEmpty();t.open=false
}
