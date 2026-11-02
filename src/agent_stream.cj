package firebreak

import std.collection.ArrayList
import stdx.encoding.json.*

// A single worker owns all handles. Cancellation is checked between native
// operations; each blocking operation has a five-second OS timeout.
class AgentSse <: Resource {
    let api=AgentWinHttp()
    var session=CPointer<Unit>()
    var connection=CPointer<Unit>()
    var request=CPointer<Unit>()
    let cancelled: ()->Bool
    let deadline: ()->Bool
    let decoder=AgentSseDecoder()
    var received: Int64=0
    var finished=false
    var closed=false
    init(key: String,body: String,cancelled: ()->Bool,deadline: ()->Bool){
        this.cancelled=cancelled;this.deadline=deadline
        try{connect(key,body)}catch(ex:Exception){close();throw ex}
    }
    func checkActive(): Unit {require(!cancelled(),"Request cancelled");require(!deadline(),"Request deadline exceeded")}
    func connect(key: String,body: String): Unit {
        checkActive()
        try(agent=AgentWide("Firebreak/0.5")){
            session=unsafe{CFunc<(CPointer<UInt16>,UInt32,CPointer<UInt16>,CPointer<UInt16>,UInt32)->CPointer<Unit>>(api.functions[0])(agent.pointer,4,CPointer<UInt16>(),CPointer<UInt16>(),0)}
        }
        require(session.isNotNull(),"HTTPS session failed")
        api.check(unsafe{CFunc<(CPointer<Unit>,Int32,Int32,Int32,Int32)->Int32>(api.functions[1])(session,5000,5000,5000,5000)})
        try(host=AgentWide("api.deepseek.com")){
            connection=unsafe{CFunc<(CPointer<Unit>,CPointer<UInt16>,UInt16,UInt32)->CPointer<Unit>>(api.functions[2])(session,host.pointer,443,0)}
        }
        require(connection.isNotNull(),"HTTPS connection failed");checkActive()
        try(verb=AgentWide("POST")){try(path=AgentWide("/chat/completions")){
            request=unsafe{CFunc<(CPointer<Unit>,CPointer<UInt16>,CPointer<UInt16>,CPointer<UInt16>,CPointer<UInt16>,CPointer<CPointer<UInt16>>,UInt32)->CPointer<Unit>>(api.functions[3])(connection,verb.pointer,path.pointer,CPointer<UInt16>(),CPointer<UInt16>(),CPointer<CPointer<UInt16>>(),0x800000)}
        }}
        require(request.isNotNull(),"HTTPS request failed")
        var policy:UInt32=0
        api.check(unsafe{CFunc<(CPointer<Unit>,UInt32,CPointer<UInt32>,UInt32)->Int32>(api.functions[4])(request,88,inout policy,4)})
        let data=body.toArray();require(data.size<=131072,"Request too large")
        let raw=unsafe{acquireArrayRawData(data)}
        try{
            try(headers=AgentWide("Content-Type: application/json\r\nAccept: text/event-stream\r\nAuthorization: Bearer "+key+"\r\n")){
                api.check(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt16>,UInt32,CPointer<UInt8>,UInt32,UInt32,UIntNative)->Int32>(api.functions[5])(request,headers.pointer,UInt32(0xffffffff),raw.pointer,UInt32(data.size),UInt32(data.size),0)})
            }
        }finally{unsafe{releaseArrayRawData(raw)}}
        checkActive();api.check(unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>)->Int32>(api.functions[6])(request,CPointer<Unit>())})
        var status:UInt32=0;var length:UInt32=4
        api.check(unsafe{CFunc<(CPointer<Unit>,UInt32,CPointer<UInt16>,CPointer<UInt32>,CPointer<UInt32>,CPointer<UInt32>)->Int32>(api.functions[7])(request,0x20000013,CPointer<UInt16>(),inout status,inout length,CPointer<UInt32>())})
        require(status==200,"DeepSeek HTTP ${status}")
    }
    func nextText(): ?String {
        try{
            while(!finished){
                checkActive()
                if(let Some(text)<-decoder.take()){return Some(text)}
                if(decoder.finished){finished=true;close();return None}
                let buffer=Array<UInt8>(4096,repeat:0);let raw=unsafe{acquireArrayRawData(buffer)};var count:UInt32=0
                try{api.check(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt8>,UInt32,CPointer<UInt32>)->Int32>(api.functions[8])(request,raw.pointer,4096,inout count)})}finally{unsafe{releaseArrayRawData(raw)}}
                require(count>0,"Incomplete model stream")
                received+=Int64(count);require(received<=262144 && decoder.pending.size+Int64(count)<=65536,"Model stream exceeds bound")
                for(i in 0..Int64(count)){decoder.pending.add(buffer[i])}
            };return None
        }catch(ex:Exception){close();throw ex}
    }
    public func isClosed():Bool {closed}
    public func close():Unit {if(!closed){api.release(request);api.release(connection);api.release(session);api.close();closed=true}}
}

// Decode complete UTF-8 lines only: network reads can split a code point.
class AgentSseDecoder {
    var pending=ArrayList<UInt8>()
    var finished=false
    func take():?String {
        while(!finished){
            var lineEnd:Int64= -1;for(i in 0..pending.size){if(pending[i]==10){lineEnd=i;break}}
            if(lineEnd<0){return None}
            let bytes=pending.toArray();let line=String.fromUtf8(bytes[..lineEnd]).trimAscii()
            pending=ArrayList<UInt8>(bytes[lineEnd+1..])
            if(line=="data: [DONE]"){finished=true;return None}
            if(line.startsWith("data:")){
                let j=JsonValue.fromStr(line[5..].trimAscii()).asObject()
                let choices=j["choices"].asArray()
                if(choices.size()>0){let delta=choices[0].asObject()["delta"].asObject()
                    if(delta.containsKey("content") && delta["content"] is JsonString){return Some(delta["content"].asString().getValue())}
                }
            }
        };return None
    }
}