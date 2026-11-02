package firebreak

import std.collection.ArrayList

foreign {
    func LoadLibraryExA(name: CString,file: CPointer<Unit>,flags: UInt32): CPointer<Unit>
    func GetProcAddress(handle: CPointer<Unit>,name: CString): CPointer<Unit>
    func FreeLibrary(handle: CPointer<Unit>): Int32
    func GetLastError(): UInt32
}
class AgentWide <: Resource {
    let pointer: CPointer<UInt16>
    private var closed=false
    init(text: String){
        pointer=unsafe{LibC.malloc<UInt16>(count:text.size+1)}
        require(pointer.isNotNull(),"Wide string allocation failed")
        let bytes=text.toArray();for(i in 0..bytes.size){unsafe{pointer.write(i,UInt16(bytes[i]))}}
        unsafe{pointer.write(bytes.size,UInt16(0))}
    }
    public func isClosed(): Bool {closed}
    public func close(): Unit {if(!closed){unsafe{LibC.free(pointer)};closed=true}}
}
class AgentWinHttp <: Resource {
    let module: CPointer<Unit>
    let functions=Array<CPointer<Unit>>(10,repeat:CPointer<Unit>())
    private var closed=false
    init(){
        let library=unsafe{LibC.mallocCString("winhttp.dll")};var handle=CPointer<Unit>()
        try(name=library.asResource()){handle=unsafe{LoadLibraryExA(name.value,CPointer<Unit>(),0x800)}}
        require(handle.isNotNull(),"System WinHTTP is unavailable");module=handle
        let names=["WinHttpOpen","WinHttpSetTimeouts","WinHttpConnect","WinHttpOpenRequest","WinHttpSetOption","WinHttpSendRequest","WinHttpReceiveResponse","WinHttpQueryHeaders","WinHttpReadData","WinHttpCloseHandle"]
        try{
            for(i in 0..names.size){let text=unsafe{LibC.mallocCString(names[i])};try(name=text.asResource()){functions[i]=unsafe{GetProcAddress(module,name.value)}};require(functions[i].isNotNull(),"WinHTTP function unavailable")}
        }catch(ex:Exception){let _=unsafe{FreeLibrary(module)};throw ex}
    }
    func check(result: Int32): Unit {if(result==0){let code=unsafe{GetLastError()};throw Exception("WinHTTP ${code}")}}
    func release(handle: CPointer<Unit>): Unit {if(handle.isNotNull()){let _=unsafe{CFunc<(CPointer<Unit>)->Int32>(functions[9])(handle)}}}
    public func isClosed(): Bool {closed}
    public func close(): Unit {if(!closed){let _=unsafe{FreeLibrary(module)};closed=true}}
}
class AgentHttpResult {
    let status: Int64
    let body: String
    init(status: Int64,body: String){this.status=status;this.body=body}
}
// Native Windows HTTPS retains OS certificate/hostname verification. It does
// not use TrustAll, export local certificates, or launch another runtime.
func deepSeekModelMetadata(key: String): AgentHttpResult {
    var result=AgentHttpResult(0,"")
    try(api=AgentWinHttp()){result=sendAgentMetadata(api,key)}
    return result
}
func sendAgentMetadata(api: AgentWinHttp,key: String): AgentHttpResult {
        var session=CPointer<Unit>();var connection=CPointer<Unit>();var request=CPointer<Unit>()
        try{
            try(agent=AgentWide("Firebreak/0.4.7")){
                session=unsafe{CFunc<(CPointer<UInt16>,UInt32,CPointer<UInt16>,CPointer<UInt16>,UInt32)->CPointer<Unit>>(api.functions[0])(agent.pointer,4,CPointer<UInt16>(),CPointer<UInt16>(),0)}
            }
            require(session.isNotNull(),"WinHTTP session failed")
            api.check(unsafe{CFunc<(CPointer<Unit>,Int32,Int32,Int32,Int32)->Int32>(api.functions[1])(session,5000,5000,5000,5000)})
            try(host=AgentWide("api.deepseek.com")){
                connection=unsafe{CFunc<(CPointer<Unit>,CPointer<UInt16>,UInt16,UInt32)->CPointer<Unit>>(api.functions[2])(session,host.pointer,443,0)}
            }
            require(connection.isNotNull(),"WinHTTP connection failed")
            try(verb=AgentWide("GET")){try(path=AgentWide("/models")){
                request=unsafe{CFunc<(CPointer<Unit>,CPointer<UInt16>,CPointer<UInt16>,CPointer<UInt16>,CPointer<UInt16>,CPointer<CPointer<UInt16>>,UInt32)->CPointer<Unit>>(api.functions[3])(connection,verb.pointer,path.pointer,CPointer<UInt16>(),CPointer<UInt16>(),CPointer<CPointer<UInt16>>(),0x800000)}
            }}
            require(request.isNotNull(),"WinHTTP request failed")
            var redirectPolicy: UInt32=0 // NEVER: credentials cannot follow redirects.
            api.check(unsafe{CFunc<(CPointer<Unit>,UInt32,CPointer<UInt32>,UInt32)->Int32>(api.functions[4])(request,88,inout redirectPolicy,4)})
            try(headers=AgentWide(if(key.isEmpty()){"Accept: application/json\r\n"}else{"Accept: application/json\r\nAuthorization: Bearer "+key+"\r\n"})){
                api.check(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt16>,UInt32,CPointer<Unit>,UInt32,UInt32,UIntNative)->Int32>(api.functions[5])(request,headers.pointer,UInt32(0xffffffff),CPointer<Unit>(),0,0,0)})
            }
            api.check(unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>)->Int32>(api.functions[6])(request,CPointer<Unit>())})
            var status: UInt32=0;var length: UInt32=4
            api.check(unsafe{CFunc<(CPointer<Unit>,UInt32,CPointer<UInt16>,CPointer<UInt32>,CPointer<UInt32>,CPointer<UInt32>)->Int32>(api.functions[7])(request,0x20000013,CPointer<UInt16>(),inout status,inout length,CPointer<UInt32>())})
            if(status!=200){return AgentHttpResult(Int64(status),"")}
            let buffer=Array<UInt8>(4096,repeat:0);let raw=unsafe{acquireArrayRawData(buffer)};let bytes=ArrayList<UInt8>()
            let clock=PerformanceClock();let start=clock.ms()
            try{
                while(true){
                    require(clock.ms()-start<15000.0,"Metadata transfer deadline exceeded")
                    var count: UInt32=0
                    api.check(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt8>,UInt32,CPointer<UInt32>)->Int32>(api.functions[8])(request,raw.pointer,4096,inout count)})
                    if(count==0){break};require(bytes.size+Int64(count)<=131072,"Oversized model metadata")
                    for(i in 0..Int64(count)){bytes.add(buffer[i])}
                }
            }finally{unsafe{releaseArrayRawData(raw)}}
            return AgentHttpResult(Int64(status),String.fromUtf8(bytes.toArray()))
        }finally{api.release(request);api.release(connection);api.release(session)}
}
