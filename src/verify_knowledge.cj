package firebreak

import sdl.*
import std.fs.{File,exists}
import std.collection.{ArrayList,HashMap}
import stdx.encoding.json.*
import magic.core.model.*
import magic.core.message.Conversation

class ScriptedKnowledgeModel <: ChatModel {
    var turn:Int64=0;let bad:Bool
    init(bad!:Bool=false){this.bad=bad}
    public prop provider:String {get(){"test"}}
    public prop name:String {get(){"scripted-knowledge"}}
    public prop contextLength:Int64 {get(){32768}}
    public mut prop maxTokens:?Int64 {get(){None};set(_) {}}
    public func create(r:ChatRequest):ChatResponse {ChatResponse(name,asyncCreate(r).message)}
    public func asyncCreate(_:ChatRequest):AsyncChatResponse {
        let text=if(turn==0){"<action>{\"name\":\"search_knowledge\",\"arguments\":{\"query\":\"Wilson\",\"kind\":\"math\"}}</action>"}else if(bad){"<answer>参见[MA-999]。</answer>"}else{"<answer>Wilson给出逐点贯通频次区间，不是pc区间。[MA-030]</answer>"}
        turn++;let chunks=ArrayList<AsyncChatChunk>([firebreakChunk(text),firebreakChunk("",done:true)]);return firebreakStream(name,chunks.iterator())
    }
}
func hasKnowledge(chunks:Array<KnowledgeChunk>,id:String):Bool {for(c in chunks){if(c.id==id){return true}};return false}
func verifyKnowledge(app:App,w:SdlWindow,live!:Bool=false):Unit {
    let store=loadKnowledge();let text=String.fromUtf8(File.readFrom("assets/knowledge/zh-CN.json"))
    pass(store.error.isEmpty() && store.chunks.size==32,"Curated version-matched knowledge loads exactly 32 operation/math chunks")
    for(c in store.chunks){for(source in c.sources){if(source.startsWith("src/")){require(exists(source),"Missing knowledge source: "+source)}}}
    pass(String.fromUtf8(File.readFrom("cjpm.toml")).contains("version = \""+KNOWLEDGE_VERSION+"\""),"Knowledge metadata matches product version and every local source exists")
    pass(rejected({=>KnowledgeStore(text.replace("\"productVersion\": \"0.12.0\"","\"productVersion\": \"0.11.0\""))}) && rejected({=>KnowledgeStore("{broken")}),"Incompatible and malformed bundles are rejected instead of serving stale content")
    pass(rejected({=>store.search("")}) && rejected({=>store.search("Wilson",kind:"private")}) && rejected({=>store.search("Wilson",limit:4)}),"Knowledge query scope, nonempty text and retrieval bounds are enforced")
    let questions=[("落雷素材怎么做，为什么没有雷声","OP-220"),("落雷和生长的长期对照怎么操作","OP-210"),("如何缩放和旋转相机","OP-040"),("Wilson置信区间是不是临界值的区间","MA-030"),("DS和SOC有什么区别","MA-050"),("幂律火灾分布能证明什么","MA-070"),("配对比较标准误SE怎么算","MA-040"),("连接优先清理是否最优","MA-060"),("风向飞火和多树种支持吗","MA-080"),("检索帮助怎么核对出处","OP-250")]
    for((question,id) in questions){require(hasKnowledge(store.search(question),id),"Retrieval missed "+id+": "+question)}
    pass(true,"Ten user questions retrieve their relevant operation, statistical, DS and unsupported-feature passages")
    pass(store.search("quantum entanglement xyzzy terraform").isEmpty(),"Unrelated questions return no match rather than fabricated context")
    pass(hasKnowledge(store.search("WILSON",kind:"math"),"MA-030") && hasKnowledge(store.search("OP-060"),"OP-060"),"English terms are case-insensitive and stable passage ids are searchable")
    for(c in store.search("Wilson",kind:"math")){require(c.kind=="math","Scope filter leaked operations")}
    pass(true,"Explicit mathematical scope excludes operation passages")
    let served=store.search("Wilson",kind:"math")
    pass(validKnowledgeCitations("公式[0,1]、[中文]与[🙂]，出处[MA-030]。",served) && !validKnowledgeCitations("[MA-999]",served) && !validKnowledgeCitations("[OP-060]",served) && !validKnowledgeCitations("[MA-030",served),"Citation checking handles Unicode text and rejects unknown, unserved and incomplete ids")
    pass(!text.contains("agent.local.json\":") && !text.contains("OP-200") && !text.contains("API Key ="),"Published knowledge excludes local maintenance entries and credential values")
    app.menuOpen=false;app.terminal.open=true;app.cancel();app.terminal.messages.clear();app.terminal.rounds.clear();app.terminal.epoch++;app.terminal.agentPlan=None
    let source=app.work.project.text();let rev=app.work.revision
    app.terminal.editor.set("/help 落雷素材");submitTerminal(app)
    pass(app.agentChat.isNone() && app.terminal.messages[app.terminal.messages.size-1].text.contains("[OP-220]"),"Local terminal help retrieves passage text without starting any API request")
    let before=app.terminal.rounds.size;let question="Wilson置信区间是不是临界值的区间？请检索数学知识，引用MA-030。"
    let job=AgentChatJob(app.work.project,app.work.revision,app.agentSettings,app.terminal.epoch,question,Conversation());app.terminal.seenEvents=0;app.agentChat=Some(job)
    if(live){require(!app.agentSettings.apiKey.isEmpty(),"Live knowledge check requires local API settings");job.start()}else{job.worker=Some(spawn{job.execute(modelOverride:Some(ScriptedKnowledgeModel()))})}
    waitAgentLab(app,w,job)
    pass(job.progress().error.isEmpty() && job.progress().events.contains("[tool] search_knowledge") && hasKnowledge(job.knowledgeHits(),"MA-030") && app.terminal.rounds.size==before+1,"Real agent orchestration retrieves mathematical passages and publishes a served citation")
    pass(validKnowledgeCitations(job.progress().answer,job.knowledgeHits()) && job.progress().answer.contains("MA-030"),"Model answer cites an actual returned reference rather than an invented source")
    var displayed=false;for(m in app.terminal.messages){if(m.text.contains("Retrieved sources") && m.text.contains("MA-030")){displayed=true}}
    pass(displayed && app.work.project.text()==source && app.work.revision==rev,"Program-generated source/version labels accompany the answer without modifying the forest")
    let gpu=app.preferences.gpuEnabled;app.preferences.gpuEnabled=true;render(app,w,capture:if(live){"artifacts/rag-agent-live.png"}else{"artifacts/rag-help.png"});app.preferences.gpuEnabled=gpu
    let bad=AgentChatJob(app.work.project,app.work.revision,app.agentSettings,app.terminal.epoch,question,Conversation());app.terminal.seenEvents=0;app.agentChat=Some(bad);let rounds=app.terminal.rounds.size
    bad.worker=Some(spawn{bad.execute(modelOverride:Some(ScriptedKnowledgeModel(bad:true)))});waitAgentLab(app,w,bad)
    pass(app.terminal.rounds.size==rounds && app.terminal.messages[app.terminal.messages.size-1].text.contains(app.t("已拒收","rejected")),"Fabricated citation answers are rejected and never enter conversation history")
    let args=HashMap<String,JsonValue>();args["query"]=JsonString("Wilson");args["path"]=JsonString("agent.local.json")
    pass(rejected({=>bad.retrieve(args)}),"Knowledge tool cannot accept arbitrary file paths or search private local data")
    app.terminal.open=false;app.terminal.rounds.clear();app.terminal.messages.clear();app.agentChat=None;app.view.useGpu=app.preferences.gpuEnabled
}
