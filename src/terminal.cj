package firebreak

import sdl.*
import sdl.text.graphemeByteBoundaries
import std.collection.ArrayList

// Byte selections always follow grapheme boundaries; UTF-8/IME text is never
// shortened by deleting one byte from a multibyte character.
class TerminalEditor {
    var text=""
    var caret: Int64=0
    var anchor: Int64=0
    var composition=""
    func selectAll(): Unit {anchor=0;caret=text.size}
    func selected(): String {text[min(caret,anchor)..max(caret,anchor)]}
    func set(value: String): Unit {text=value;caret=value.size;anchor=caret;composition=""}
    func insert(value: String): Unit {
        let clean=StringBuilder()
        for(ch in value.runes()){let c=UInt32(ch);if(c>=32 && c!=127 || c==10){clean.append(ch.toString())}}
        let added=clean.toString();let low=min(caret,anchor);let high=max(caret,anchor)
        require(text.size-(high-low)+added.size<=8192,"终端输入最多 8192 字节 / Terminal input limit: 8192 bytes")
        text=text[..low]+added+text[high..];caret=low+added.size;anchor=caret;composition=""
    }
    func move(right: Bool,select: Bool): Unit {
        if(!select && caret!=anchor){caret=if(right){max(caret,anchor)}else{min(caret,anchor)}}
        else {let positions=graphemeByteBoundaries(text);var next: Int64=if(right){text.size}else{0}
            for(p in positions){if(right && p>caret){next=p;break};if(!right && p<caret){next=p}}
            caret=next
        }
        if(!select){anchor=caret}
    }
    func erase(back: Bool): Unit {
        if(caret==anchor){let old=caret;move(!back,true);anchor=old}
        insert("")
    }
}

class TerminalMessage {
    let text: String
    let user: Bool
    init(text: String,user!:Bool=false){this.text=text;this.user=user}
}
class AgentTerminal {
    var epoch:Int64=0
    var seenEvents:Int64=0
    var streamText=""
    var rounds=ArrayList<(String,String)>()
    var agentPlan:?PlanSearchResult=None
    var planSource=""
    var planRevision:Int64= -1
    var open=false
    var quick=false
    let editor=TerminalEditor()
    let messages=ArrayList<TerminalMessage>()
    let history=ArrayList<String>()
    var historyAt: Int64=0
    var savedDraft=""
    var scroll: Int64=0
    var inputFirst: Int64=0
    var revision: Int64=0
    var pressed: Int64= -1
    var suppressSlash=false
    var selecting=false
    var cachedRevision: Int64= -1
    var cachedWidth: Float32=0.0
    var cachedScale: Float32=0.0
    var cachedLines=ArrayList<TerminalRow>()
    func append(text: String,user!:Bool=false): Unit {
        require(text.size<=16384,"Terminal message exceeds display bound")
        messages.add(TerminalMessage(text,user:user))
        var bytes: Int64=0;for(m in messages){bytes+=m.text.size}
        while(messages.size>128 || bytes>65536){bytes-=messages[0].text.size;messages.remove(at:0)}
        revision++;scroll=0
    }
    func recall(previous: Bool): Unit {
        if(historyAt==history.size){savedDraft=editor.text}
        historyAt=max(0,min(history.size,historyAt+if(previous){-1}else{1}))
        editor.set(if(historyAt==history.size){savedDraft}else{history[historyAt]})
    }
    func transcript(): String {
        let lines=ArrayList<String>();for(m in messages){lines.add((if(m.user){"> "}else{"# "})+m.text)}
        String.join(lines.toArray(),delimiter:"\n")
    }
}

class TerminalRow {
    let text: String
    let start: Int64
    let end: Int64
    let user: Bool
    init(text: String,start: Int64,end: Int64,user!:Bool=false){this.text=text;this.start=start;this.end=end;this.user=user}
}
func terminalRows(font: PixelFont,text: String,width: Float32,scale: Float32,user!:Bool=false): Array<TerminalRow> {
    let result=ArrayList<TerminalRow>();var line="";var start: Int64=0;var offset: Int64=0;var used: Float32=0.0
    for(ch in text.runes()){
        let value=ch.toString();let advance=font.advance(Int64(UInt32(ch)),scale)
        if(UInt32(ch)==10){result.add(TerminalRow(line,start,offset,user:user));offset+=value.size;start=offset;line="";used=0.0;continue}
        if(used+advance>width && !line.isEmpty()){result.add(TerminalRow(line,start,offset,user:user));start=offset;line="";used=0.0}
        line+=value;used+=advance;offset+=value.size
    }
    result.add(TerminalRow(line,start,offset,user:user));return result.toArray()
}

class TerminalLayout {
    let scale: Float32
    let body: Rect
    let screen: Rect
    let output: Rect
    let input: Rect
    let lineHeight: Float32
    let quick: Bool
    init(l: Layout,quick: Bool){
        this.quick=quick
        scale=if(quick){1.0}else{max(1.0,min(2.0,Float32(Int64(min(l.width/1280.0,l.height/860.0)*4.0))/4.0))}
        let w=min(l.width-120.0,960.0*scale);let h=min(l.height-150.0,570.0*scale)
        body=if(quick){Rect(l.canvas.x,l.canvas.bottom()-232.0,l.canvas.w,232.0)}else{Rect((l.width-w)/2.0,(l.height-h)/2.0,w,h)}
        screen=Rect(body.x+18.0*scale,body.y+18.0*scale,body.w-36.0*scale,body.h-36.0*scale)
        lineHeight=22.0*scale
        input=Rect(screen.x+12.0*scale,screen.bottom()-82.0*scale,screen.w-114.0*scale,68.0*scale)
        output=Rect(screen.x+12.0*scale,screen.y+48.0*scale,screen.w-24.0*scale,input.y-screen.y-60.0*scale)
    }
    func control(id: Int64): Rect {
        match(id){
            case 0 | 1=>if(quick){Rect(body.x+Float32(id)*38.0,body.y-36.0,32.0,32.0)}else{Rect(body.x-34.0*scale,body.y+(24.0+Float32(id)*38.0)*scale,32.0*scale,32.0*scale)}
            case 2 | 3=>Rect(screen.right()-(180.0-Float32(id-2)*86.0)*scale,screen.y+8.0*scale,78.0*scale,28.0*scale)
            case _=>Rect(screen.right()-90.0*scale,input.y+Float32(id-4)*36.0*scale,78.0*scale,30.0*scale)
        }
    }
    func hit(x: Float32,y: Float32): Int64 {for(id in 0..6){if(control(id).contains(x,y)){return id}};return -1}
}

func openTerminal(app: App,quick: Bool): Unit {
    require(app.startCell<0 && app.activeField<0,app.t("请先完成或取消当前编辑","Finish or cancel the current edit first"))
    let t=app.terminal;t.open=true;t.quick=quick;t.pressed = -1;t.editor.composition=""
    app.painting=false;app.dragging=false;app.panning=false;app.pressed = -1;app.hover = -1
    if(let Some(run)<-app.experiment.run){run.running=false};if(let Some(pair)<-app.pairView){pair.playing=false}
    if(t.messages.isEmpty()){t.append(app.t("断火线研究员终端\n/help 查看命令；/site 读取场地；/preview 预览建议。","Firebreak researcher terminal\n/help for commands; /site reads the site; /preview opens suggestions."))}
}
func submitTerminal(app: App): Unit {
    let t=app.terminal;let text=t.editor.text
    if(text!="/stop" && text!="/clear" && app.agentChat.isSome()){return}
    var meaningful=false;for(ch in text.runes()){if(UInt32(ch)>32){meaningful=true}}
    if(!meaningful){return}
    t.history.add(text);while(t.history.size>64){t.history.remove(at:0)};t.historyAt=t.history.size;t.savedDraft=""
    t.append(text,user:true);t.editor.set("");t.inputFirst=0
    match(text){
        case "/help"=>t.append(app.t("本地命令：/site 当前场地；/clear 清空记录。\nEnter 发送；Shift+Enter 换行；↑↓ 历史；Ctrl+A/C/V 编辑；Ctrl+Shift+C 复制记录。\n填写 API Key 后可用自然语言对话；/stop 停止；/preview 预览候选。","Local commands: /site, /clear.\nEnter sends; Shift+Enter inserts a line; Up/Down history; Ctrl+A/C/V edit; Ctrl+Shift+C copies the transcript.\nWith a saved API key, chat naturally; /stop cancels; /preview opens candidates."))
        case "/site"=>
            let p=app.work.project;var forest: Int64=0;var targets: Int64=0;var forbidden: Int64=0
            for(i in 0..p.cells){if(p.fuel(i)>0.0){forest++};if(p.targets[i]!=0){targets++};if(p.forbidden[i]!=0){forbidden++}}
            t.append(app.t("本地场地数据（非模型回答）","Local site data (not a model response)")+"\n${p.nx} x ${p.nz} | revision ${app.work.revision}\n"+
                app.t("林地 / 保护 / 禁区：","Forest / protected / excluded: ")+"${forest} / ${targets} / ${forbidden}\n"+
                app.t("预算 / 当前费用：","Budget / treatment cost: ")+money(p.budget)+" / "+money(p.cost()))
        case "/stop"=>if(let Some(job)<-app.agentChat){job.cancel()}
        case "/preview"=>previewAgentPlan(app)
        case "/clear"=>if(let Some(job)<-app.agentChat){job.cancel()};t.epoch++;t.rounds.clear();t.agentPlan=None;t.streamText="";t.messages.clear();t.revision++;t.append(app.t("会话已清空。","Conversation cleared."))
        case _=>startAgentChat(app,text)
    }
}
