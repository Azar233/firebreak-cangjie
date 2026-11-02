package firebreak

import sdl.*

// Vanilla GUI atlas: five 10x8 green levels, five blue pending frames,
// and the red unreachable cross. State 0 remains neutral until a real test.
func agentSignalRegion(state: Int64,latency: Int64,ticks: UInt64): Rect {
    if(state==1){let phase=Int64((ticks/150)%8);let frame=if(phase<5){phase}else{8-phase};return Rect(10.0,176.0+Float32(frame)*8.0,10.0,8.0)}
    if(state==2){let level: Int64=if(latency<150){0}else if(latency<300){1}else if(latency<600){2}else if(latency<1000){3}else{4};return Rect(0.0,176.0+Float32(level)*8.0,10.0,8.0)}
    return Rect(0.0,216.0,10.0,8.0)
}
func agentConnectionLabel(app: App): String {
    match(app.agentSettings.connectionState){
        case 1=>app.t("正在检测连接","CHECKING")
        case 2=>app.t("API 已连接","API CONNECTED")
        case 3=>app.t("连接失败","UNREACHABLE")
        case _=>app.t("未验证 / 未连接","UNVERIFIED / OFFLINE")
    }
}
func drawAgentSignal(assets: Assets,b: Rect,state: Int64,latency: Int64,ticks: UInt64): Unit {
    if(state!=0){assets.blit("textures/gui/icons.png",b,source:Some(agentSignalRegion(state,latency,ticks)));return}
    let name="internal/agent-signal-unverified"
    if(!assets.images.contains(name)){
        try(source=Surface.loadPng("assets/minecraft/textures/gui/icons.png")){
            try(neutral=Surface.create(10,8)){
                for(y in 0..8){for(x in 0..10){let c=source.readPixel(Int32(x),Int32(y+176));let gray=Int64(max(c.r,max(c.g,c.b)))*100/255;neutral.writePixel(Int32(x),Int32(y),Color.rgba(gray,gray,gray,Int64(c.a)))}}
                assets.images[name]=assets.r.textureFromSurface(neutral)
            }
        }
    }
    assets.r.textureStyled(assets.images[name],b,style:TextureStyle(sampling:TextureScaleMode.Nearest))
}
