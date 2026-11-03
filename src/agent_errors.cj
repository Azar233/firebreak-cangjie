package firebreak

// Never expose response bodies, credentials or arbitrary exception text in UI.
func agentFailureText(detail:String):String {
    match(detail){
        case "DeepSeek HTTP 503"=>"DeepSeek 服务过载（HTTP 503），有限重试后仍失败，请稍后重试。 / Server overloaded; retries exhausted."
        case "DeepSeek HTTP 500"=>"DeepSeek 服务错误（HTTP 500），有限重试后仍失败，请稍后重试。 / Server error; retries exhausted."
        case "DeepSeek HTTP 429"=>"DeepSeek 请求限流（HTTP 429），请稍后重试。 / Rate limited; retry later."
        case "DeepSeek HTTP 401"=>"DeepSeek 身份验证失败（HTTP 401），请检查已保存的 API Key。 / Authentication failed; check saved key."
        case "DeepSeek HTTP 402"=>"DeepSeek 账户余额不足（HTTP 402）。 / Insufficient balance."
        case "DeepSeek HTTP 400" | "DeepSeek HTTP 422"=>"DeepSeek 拒绝请求参数，请检查模型设置（HTTP 400/422）。 / Invalid request/model parameters."
        case "Incomplete model stream"=>"模型流提前结束，本次回答未完成，未自动重放工具。 / Incomplete stream; tools were not replayed."
        case _=>
            if(detail.startsWith("WinHTTP ")){
                return "模型网络连接中断或等待超时，本次回答未完成；未自动重放工具。 / Network interruption or timeout; tools were not replayed."
            }
            return "模型请求未完成，请稍后重试；详细原因未识别。 / Model request incomplete; unclassified failure."
    }
}
func retryableAgentStatus(detail:String):Bool {["DeepSeek HTTP 429","DeepSeek HTTP 500","DeepSeek HTTP 503"].contains(detail)}
// Retry only rejected HTTP requests, never a stream or an entire agent/tool round.
func retryAgentConnect(job:AgentChatJob,connect:()->Unit):Unit {
    var attempt:Int64=0
    while(true){
        job.checkActive()
        try{connect();return}catch(ex:Exception){
            if(attempt>=2 || !retryableAgentStatus(ex.message)){throw ex}
            attempt++;job.retryNotice(attempt)
            for(_ in 0..attempt*10){job.checkActive();sleep(Duration.millisecond*100)}
        }
    }
}
