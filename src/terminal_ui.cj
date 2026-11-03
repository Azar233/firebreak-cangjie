package firebreak

import sdl.*
import sdl.input.Clipboard
import sdl.text.graphemeByteBoundaries
import std.collection.ArrayList

func terminalButton(app: App,b: Rect,label: String,scale: Float32,enabled!:Bool=true): Unit {
    let r=app.assets.r
    r.fill(b,Color.rgb(63,66,37));r.fill(Rect(b.x+2.0*scale,b.y+2.0*scale,b.w-4.0*scale,b.h-4.0*scale),Color.rgb(186,190,102))
    app.font.center(label,b,color:if(enabled){Color.rgb(22,24,17)}else{Color.rgb(111,115,76)},scale:0.85*scale,shadow:false)
}
func terminalInputRows(app: App,m: TerminalLayout): Array<TerminalRow> {terminalRows(app.font,app.terminal.editor.text,m.input.w-26.0*m.scale,m.scale)}
func terminalCaretLine(rows: Array<TerminalRow>,caret: Int64): Int64 {
    var result: Int64=0;for(i in 0..rows.size){if(caret>=rows[i].start){result=i}};return result
}
func terminalPointer(app: App,m: TerminalLayout,x: Float32,y: Float32,selectMore: Bool): Unit {
    let t=app.terminal;let rows=terminalInputRows(app,m)
    let line=rows[max(0,min(rows.size-1,t.inputFirst+Int64((y-m.input.y)/m.lineHeight)))]
    var offset=line.start;var px=m.input.x+24.0*m.scale
    for(ch in line.text.runes()){
        let advance=app.font.advance(Int64(UInt32(ch)),m.scale)
        if(x<px+advance/2.0){break};offset+=ch.toString().size;px+=advance
    }
    // Snap pointer selection to an extended-grapheme boundary, too.
    let positions=graphemeByteBoundaries(t.editor.text);var boundary: Int64=0
    for(p in positions){if(p>offset){break};boundary=p}
    t.editor.caret=boundary;if(!selectMore){t.editor.anchor=boundary}
}
func drawTerminal(app: App,l: Layout,w: SdlWindow): Unit {
    let t=app.terminal;if(!t.open || app.menuOpen){return}
    if(let Some(card)<-t.expandedCard){if(!card.isClosed()){drawExpandedCard(app,l,card);return}else{t.expandedCard=None}}
    let m=TerminalLayout(l,t.quick);let r=app.assets.r;let f=app.font;let s=m.scale
    t.cardHits.clear()
    let ratio=Float32(w.scale)*Float32(w.currentPixelDensity)
    // Pixel bevels rather than a scaled background image: sharp at every size.
    if(!t.quick){r.fill(Rect(0.0,0.0,l.width,l.height),Color.rgba(0,0,0,72))}
    r.fill(Rect(m.body.x+4.0*s,m.body.y+5.0*s,m.body.w,m.body.h),Color.rgba(0,0,0,150))
    r.fill(m.body,Color.rgb(111,117,59))
    r.fill(Rect(m.body.x+3.0*s,m.body.y+3.0*s,m.body.w-6.0*s,m.body.h-6.0*s),Color.rgb(197,201,119))
    r.fill(Rect(m.body.x+4.0*s,m.body.y+4.0*s,m.body.w-8.0*s,3.0*s),Color.rgb(231,234,158))
    r.fill(Rect(m.screen.x-2.0*s,m.screen.y-2.0*s,m.screen.w+4.0*s,m.screen.h+4.0*s),Color.rgb(80,85,43))
    r.fill(m.screen,Color.rgb(15,16,15))
    drawAgentSignal(app.assets,Rect(m.screen.x+12.0*s,m.screen.y+12.0*s,20.0*s,16.0*s),app.agentSettings.connectionState,app.agentSettings.latencyMillis,w.ticks())
    f.draw("FIREBREAK > "+agentConnectionLabel(app),m.screen.x+40.0*s,m.screen.y+12.0*s,color:Color.rgb(223,222,113),scale:s,shadow:false,snap:true,pixelRatio:ratio)
    if(t.cachedRevision!=t.revision || t.cachedWidth!=m.output.w || t.cachedScale!=s){
        t.cachedLines.clear()
        for(message in t.messages){for(row in terminalRows(f,(if(message.user){"> "}else{""})+message.text,m.output.w,s,user:message.user)){t.cachedLines.add(row)}
            if(let Some(card)<-message.card){if(!card.isClosed()){let n=cardRowCount(card,m.output.w,s,m.lineHeight);for(i in 0..n){t.cachedLines.add(TerminalRow("",0,0,card:Some(card),cardRow:i,cardRows:n))}}}
        }
        if(!t.streamText.isEmpty()){for(row in terminalRows(f,t.streamText,m.output.w,s)){t.cachedLines.add(row)}}
        t.cachedRevision=t.revision;t.cachedWidth=m.output.w;t.cachedScale=s
    }
    let visible=max(1,Int64(m.output.h/m.lineHeight));t.scroll=max(0,min(max(0,t.cachedLines.size-visible),t.scroll))
    let first=max(0,t.cachedLines.size-visible-t.scroll)
    r.pushClip(m.output)
    for(i in first..min(t.cachedLines.size,first+visible)){
        let line=t.cachedLines[i]
        if(let Some(card)<-line.card){
            if(!card.isClosed() && (line.cardRow==0 || i==first)){
                let width=min(m.output.w,400.0*s);let box=Rect(m.output.x,m.output.y+Float32(i-first-line.cardRow)*m.lineHeight,width,width*card.texture.height/card.texture.width)
                r.textureStyled(card.texture,box,style:TextureStyle(sampling:TextureScaleMode.Nearest));t.cardHits.add((box,card))
                if(card.revision!=app.work.revision){r.fill(box,Color.rgba(0,0,0,140));f.draw(app.t("已失效 / 历史图","STALE / historical"),box.x+8.0,max(box.y,m.output.y)+8.0,scale:s,color:Color.rgb(255,205,110),shadow:false)}
            }
        }else{f.draw(line.text,m.output.x,m.output.y+Float32(i-first)*m.lineHeight,color:if(line.user){Color.rgb(233,233,224)}else{Color.rgb(205,208,162)},scale:s,shadow:false,snap:true,pixelRatio:ratio)}
    }
    r.popClip()
    if(t.scroll>0){f.draw("^",m.screen.right()-12.0*s,m.output.y,color:Color.rgb(223,222,113),scale:s,shadow:false)}
    r.fill(Rect(m.input.x,m.input.y-7.0*s,m.screen.w-24.0*s,1.0*s),Color.rgb(70,75,49))
    let rows=terminalInputRows(app,m);let caretLine=terminalCaretLine(rows,t.editor.caret)
    let inputVisible=max(1,Int64(m.input.h/m.lineHeight))
    t.inputFirst=max(0,min(t.inputFirst,caretLine));if(caretLine>=t.inputFirst+inputVisible){t.inputFirst=caretLine-inputVisible+1}
    var cursor=Point(m.input.x+24.0*s,m.input.y)
    r.pushClip(m.input)
    for(i in t.inputFirst..min(rows.size,t.inputFirst+inputVisible)){
        let row=rows[i];let y=m.input.y+Float32(i-t.inputFirst)*m.lineHeight;var x=m.input.x+24.0*s;var offset=row.start
        f.draw(if(i==0){">"}else{"."},m.input.x,y,color:Color.rgb(223,222,113),scale:s,shadow:false)
        for(ch in row.text.runes()){
            let glyph=ch.toString();let advance=f.advance(Int64(UInt32(ch)),s)
            if(offset>=min(t.editor.caret,t.editor.anchor) && offset<max(t.editor.caret,t.editor.anchor)){r.fill(Rect(x,y,advance,m.lineHeight),Color.rgb(70,83,66))}
            f.draw(glyph,x,y,color:Color.rgb(237,237,229),scale:s,shadow:false,snap:true,pixelRatio:ratio);x+=advance;offset+=glyph.size
        }
        if(i==caretLine){
            let local=max(row.start,min(row.end,t.editor.caret));cursor=Point(m.input.x+24.0*s+f.measure(t.editor.text[row.start..local],scale:s),y)
            if(!t.editor.composition.isEmpty()){
                f.draw(t.editor.composition,cursor.x,cursor.y,color:Color.rgb(236,221,117),scale:s,shadow:false,snap:true,pixelRatio:ratio)
                r.fill(Rect(cursor.x,cursor.y+18.0*s,f.measure(t.editor.composition,scale:s),1.0*s),Color.rgb(236,221,117))
            }else if((w.ticks()/500)%2==0){r.fill(Rect(cursor.x,cursor.y+16.0*s,10.0*s,2.0*s),Color.rgb(235,235,223))}
        }
    }
    r.popClip();w.setTextInputArea(Rect(min(m.input.right()-2.0*s,cursor.x),cursor.y+20.0*s,2.0*s,m.lineHeight))
    terminalButton(app,m.control(0),"",s);terminalButton(app,m.control(1),if(t.quick){"+"}else{"-"},s)
    terminalButton(app,m.control(2),app.t("复制记录","Copy log"),s)
    terminalButton(app,m.control(3),app.t("设置","Settings"),s)
    terminalButton(app,m.control(4),app.t("发送","Send"),s,enabled:app.agentChat.isNone())
    terminalButton(app,m.control(5),app.t("停止","Stop"),s,enabled:app.agentChat.isSome() || app.pipelineJob.isSome())
    // Power indicator: amber means no configured model, not an active task.
    let power=m.control(0)
    r.strokeRect(Rect(power.x+9.0*s,power.y+10.0*s,14.0*s,14.0*s),Pen(width:2.0*s,color:Color.rgb(132,50,35)))
    r.fill(Rect(power.x+14.0*s,power.y+6.0*s,4.0*s,12.0*s),Color.rgb(132,50,35))
    r.fill(Rect(power.x+4.0*s,power.y+4.0*s,3.0*s,3.0*s),Color.rgb(225,156,49))
}
func terminalAction(app: App,id: Int64): Unit {
    let t=app.terminal
    if((id==5 && app.agentChat.isNone() && app.pipelineJob.isNone()) || (id==4 && app.agentChat.isSome())){return}
    playUiClick(app)
    match(id){
        case 0=>t.open=false;t.editor.composition="";t.selecting=false
        case 1=>t.quick = !t.quick;t.inputFirst=0
        case 2=>Clipboard.setText(t.transcript())
        case 3=>t.editor.composition="";app.openMenu();openAgentSettings(app)
        case 4=>if(t.editor.composition.isEmpty()){submitTerminal(app)}
        case 5=>if(let Some(job)<-app.agentChat){job.cancel()};if(let Some(task)<-app.pipelineJob){task.cancel()}
        case _=>()
    }
}
func handleTerminalInput(app: App,record: UiEventRecord,l: Layout): Bool {
    let t=app.terminal;let e=t.editor;let m=TerminalLayout(l,t.quick);let mods=record.metadata.modifiers
    if(t.expandedCard.isSome()){match(record.event){case UiEvent.KeyDown(Key.Escape,_) | UiEvent.MouseUp(MouseButton.Left,_,_)=>t.expandedCard=None;case _=>()};return true}
    match(record.event){
        case UiEvent.TextInput(value)=>
            if(t.suppressSlash && value=="/"){t.suppressSlash=false;return true}
            t.suppressSlash=false;e.insert(value)
        case UiEvent.TextEditing(text,_,_)=>e.composition=text
        case UiEvent.KeyDown(key,repeat)=>
            t.suppressSlash=false
            if(!e.composition.isEmpty()){
                match(key){case Key.Escape=>e.composition="";case _=>()};return true
            }
            if(mods.ctrl){
                match(key){
                    case Key.Letter(65)=>e.selectAll()
                    case Key.Letter(67)=>if(mods.shift || e.caret!=e.anchor){Clipboard.setText(if(mods.shift){t.transcript()}else{e.selected()})}
                    case Key.Letter(86)=>e.insert(Clipboard.getText())
                    case Key.Letter(88)=>if(e.caret!=e.anchor){Clipboard.setText(e.selected());e.insert("")}
                    case _=>()
                };return true
            }
            match(key){
                case Key.Escape=>t.open=false;t.selecting=false
                case Key.Enter=>if(mods.shift){e.insert("\n")}else if(!repeat){submitTerminal(app)}
                case Key.Backspace=>e.erase(true)
                case Key.Delete=>e.erase(false)
                case Key.Left=>e.move(false,mods.shift)
                case Key.Right=>e.move(true,mods.shift)
                case Key.Home=>e.caret=0;if(!mods.shift){e.anchor=e.caret}
                case Key.End=>e.caret=e.text.size;if(!mods.shift){e.anchor=e.caret}
                case Key.Up=>t.recall(true)
                case Key.Down=>t.recall(false)
                case Key.PageUp=>t.scroll+=max(1,Int64(m.output.h/m.lineHeight))
                case Key.PageDown=>t.scroll=max(0,t.scroll-max(1,Int64(m.output.h/m.lineHeight)))
                case Key.Tab=>if(!repeat){t.quick = !t.quick;t.inputFirst=0}
                case _=>()
            }
        case UiEvent.MouseDown(MouseButton.Left,x,y)=>
            t.pressed=m.hit(x,y);t.pendingCard=None
            if(m.output.contains(x,y)){for((box,card) in t.cardHits){if(box.contains(x,y)){t.pendingCard=Some(card);break}}}
            if(m.input.contains(x,y)){terminalPointer(app,m,x,y,mods.shift);t.selecting=true}
        case UiEvent.MouseMove(x,y)=>if(t.selecting){terminalPointer(app,m,x,y,true)}
        case UiEvent.MouseUp(MouseButton.Left,x,y)=>
            if(let Some(card)<-t.pendingCard){for((box,hit) in t.cardHits){if(refEq(card,hit) && m.output.contains(x,y) && box.contains(x,y)){t.expandedCard=Some(card);break}}};t.pendingCard=None
            t.selecting=false;let id=m.hit(x,y);if(id>=0 && id==t.pressed){terminalAction(app,id)};t.pressed = -1
        case UiEvent.MouseWheel(_,dy,_,_)=>t.scroll=max(0,t.scroll+Int64(dy*3.0))
        case UiEvent.WindowFocusLost=>e.composition="";t.pressed = -1;t.selecting=false
        case _=>()
    }
    return true
}
