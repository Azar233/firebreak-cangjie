package firebreak

import sdl.*
import std.math.round

func audioLevel(app:App,id:Int64):Int64 {
    if(app.audioDrag==id){return app.audioDraft}
    return if(id==114){app.preferences.soundVolume}else{app.preferences.musicVolume}
}
func playUiClick(app:App):Unit {app.audio.click(app.preferences.soundVolume)}
func applyAudioPreview(app:App):Unit {app.audio.setLevels(audioLevel(app,114),audioLevel(app,115))}
func saveAudioLevel(app:App,id:Int64,value:Int64):Unit {
    let sound=if(id==114){value}else{app.preferences.soundVolume}
    let music=if(id==115){value}else{app.preferences.musicVolume}
    try{app.preferences.setAudio(sound,music)}finally{app.audioDrag = -1;app.audio.setLevels(app.preferences.soundVolume,app.preferences.musicVolume)}
}
func pointerAudioLevel(b:Rect,x:Float32):Int64 {
    Int64(round(Float64(max(0.0,min(1.0,(x-b.x-8.0)/(b.w-16.0))))*100.0))
}
func drawAudioSlider(app:App,m:MenuLayout,id:Int64,pixelRatio:Float32):Unit {
    let b=m.box(id,page:8);let value=audioLevel(app,id);let s=m.scale
    mcButtonAt(app,b,id,"",app.menuFocus==id,textScale:s,pixelRatio:pixelRatio,snapText:true)
    let knob=Rect(b.x+4.0*s+(b.w-22.0*s)*Float32(value)/100.0,b.y+4.0*s,14.0*s,b.h-8.0*s)
    app.assets.r.fill(knob,Color.rgb(39,39,39));app.assets.r.fill(Rect(knob.x+2.0*s,knob.y+2.0*s,knob.w-4.0*s,knob.h-4.0*s),Color.rgb(195,195,195))
    app.font.center(menuLabel(app,id),b,scale:s,snap:true,pixelRatio:pixelRatio)
}
func handleAudioSettings(app:App,record:UiEventRecord,l:Layout):Bool {
    if(app.menuPage!=8){return false}
    let m=MenuLayout(l)
    match(record.event){
        case UiEvent.MouseDown(MouseButton.Left,x,y)=>
            let id=m.hit(x,y,8)
            if(id==114 || id==115){app.audioDrag=id;app.menuFocus=id;app.audioDraft=pointerAudioLevel(m.box(id,page:8),x);applyAudioPreview(app);return true}
        case UiEvent.MouseMove(x,_)=>if(app.audioDrag>=0){app.audioDraft=pointerAudioLevel(m.box(app.audioDrag,page:8),x);applyAudioPreview(app);return true}
        case UiEvent.MouseUp(MouseButton.Left,x,_)=>if(app.audioDrag>=0){let id=app.audioDrag;saveAudioLevel(app,id,pointerAudioLevel(m.box(id,page:8),x));playUiClick(app);return true}
        case UiEvent.WindowFocusLost=>if(app.audioDrag>=0){app.audioDrag = -1;applyAudioPreview(app);return true}
        case UiEvent.KeyDown(key,_)=>
            if(app.audioDrag>=0){match(key){case Key.Escape=>app.audioDrag = -1;applyAudioPreview(app);case _=>()};return true}
            let id=app.menuFocus
            if(id==114 || id==115){
                var next=audioLevel(app,id)
                match(key){case Key.Left=>next=max(0,next-5);case Key.Right=>next=min(100,next+5);case Key.Home=>next=0;case Key.End=>next=100;case _=>return false}
                saveAudioLevel(app,id,next);if(id==114){playUiClick(app)};return true
            }
        case _=>()
    };return false
}
