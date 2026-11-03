package firebreak

import sdl.*

// Keep the default 1280x860 proportions; extra aspect-ratio space goes to the canvas.
func uiScale(width:Float32,height:Float32):Float32 {max(1.0,min(3.0,min(width/1280.0,height/860.0)))}
func uiPixelRatio(w:SdlWindow):Float32 {Float32(w.scale)*Float32(w.currentPixelDensity)*uiScale(Float32(w.width),Float32(w.height))}
func uiEventCoordinates(e:UiEvent,divisor:Float32):UiEvent {
    return match(e){
        case UiEvent.MouseMove(x,y)=>UiEvent.MouseMove(x/divisor,y/divisor)
        case UiEvent.MouseDown(b,x,y)=>UiEvent.MouseDown(b,x/divisor,y/divisor)
        case UiEvent.MouseUp(b,x,y)=>UiEvent.MouseUp(b,x/divisor,y/divisor)
        case UiEvent.MouseWheel(dx,dy,x,y)=>UiEvent.MouseWheel(dx,dy,x/divisor,y/divisor)
        case UiEvent.DropFile(path,x,y)=>UiEvent.DropFile(path,x/divisor,y/divisor)
        case UiEvent.DropText(text,x,y)=>UiEvent.DropText(text,x/divisor,y/divisor)
        case UiEvent.DropPosition(x,y)=>UiEvent.DropPosition(x/divisor,y/divisor)
        case _=>e
    }
}
func uiInputArea(w:SdlWindow,b:Rect):Unit {
    let s=uiScale(Float32(w.width),Float32(w.height));w.setTextInputArea(Rect(b.x*s,b.y*s,b.w*s,b.h*s))
}
