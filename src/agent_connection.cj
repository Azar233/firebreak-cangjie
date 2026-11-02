package firebreak

import std.sync.Mutex
import stdx.encoding.json.JsonValue

class AgentConnectionResult {
    let done: Bool
    let ok: Bool
    let elapsed: Int64
    let error: String
    init(done: Bool,ok: Bool,elapsed: Int64,error: String){this.done=done;this.ok=ok;this.elapsed=elapsed;this.error=error}
}
// A bounded authenticated metadata request, not a model generation request.
// No response body, Authorization header or credential is written to logs.
class AgentConnectionJob {
    let generation: Int64
    let model: String
    private let key: String
    private let lock=Mutex()
    private var done=false
    private var ok=false
    private var elapsed: Int64= -1
    private var error=""
    init(generation: Int64,model: String,key: String){this.generation=generation;this.model=model;this.key=key}
    func progress(): AgentConnectionResult {synchronized(lock){return AgentConnectionResult(done,ok,elapsed,error)}}
    func start(): Unit {spawn{execute()}}
    func execute(): Unit {
        let clock=PerformanceClock();let start=clock.ms();var success=false;var problem="";var phase="HTTPS"
        try{
            let response=deepSeekModelMetadata(key)
                if(response.status==200){
                    phase="Model metadata"
                    let data=JsonValue.fromStr(response.body).asObject()["data"].asArray()
                    for(i in 0..data.size()){if(data[i].asObject()["id"].asString().getValue()==model){success=true}}
                    if(!success){problem="模型不在当前可用列表 / Model is not available"}
                }else{problem="HTTP ${response.status}"}
        }catch(ex:Exception){if(key.isEmpty()){eprintln("Public TLS probe detail: "+ex.message)};problem="连接检测失败 / Connection check failed ("+phase+")";if(ex.message.startsWith("WinHTTP ")){problem+=" "+ex.message}}
        synchronized(lock){ok=success;error=problem;elapsed=Int64(clock.ms()-start);done=true}
    }
}
func startAgentConnection(app: App): Bool {
    if(app.agentSettings.loadError || app.agentSettings.apiKey.isEmpty() || app.agentConnection.isSome()){return false}
    let job=AgentConnectionJob(app.agentSettings.generation,app.agentSettings.model,app.agentSettings.apiKey)
    app.agentConnection=Some(job);app.agentSettings.connectionState=1;job.start()
    return true
}
func pollAgentConnection(app: App): Unit {
    if(let Some(job)<-app.agentConnection){
        let result=job.progress()
        if(result.done){
            app.agentConnection=None;publishAgentConnection(app,job.generation,result)
        }
    }
}
func publishAgentConnection(app: App,generation: Int64,result: AgentConnectionResult): Bool {
    if(generation!=app.agentSettings.generation || !result.done){return false}
    app.agentSettings.connectionState=if(result.ok){2}else{3}
    app.agentSettings.latencyMillis=if(result.ok){result.elapsed}else{ -1}
    app.message=if(result.ok){app.t("DeepSeek API 与模型可用，检测耗时 ","DeepSeek API/model available; probe ")+"${result.elapsed} ms"}else{app.t("DeepSeek 连接测试失败：","DeepSeek connection check failed: ")+result.error}
    return true
}
