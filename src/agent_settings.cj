package firebreak

import sdl.*
import sdl.input.Clipboard
import std.fs.{File,exists}
import stdx.encoding.json.*

// Kept separate from site documents, UI preferences, conversation and exports.
class DeepSeekSettings {
    let path: String
    let baseUrl="https://api.deepseek.com"
    var model="deepseek-flash"
    var apiKey=""
    var loadError=false
    // 0 unverified, 1 testing, 2 verified, 3 failed; never inferred from a saved key.
    var connectionState: Int64=0
    var latencyMillis: Int64= -1
    var generation: Int64=0
    init(path: String){
        this.path=path
        if(path.isEmpty() || !exists(path)){return}
        try{
            let bytes=File.readFrom(path);require(bytes.size<=4096,"Agent settings too large")
            let j=JsonValue.fromStr(String.fromUtf8(bytes)).asObject()
            let m=j["model"].asString().getValue();let key=j["apiKey"].asString().getValue()
            validate(m,key);model=m;apiKey=key
        }catch(_:Exception){loadError=true}
    }
    func validate(m: String,key: String): Unit {
        require(m.size>0 && m.size<=96,"模型名称格式无效 / Invalid model name")
        for(c in m.toArray()){require(c>=48 && c<=57 || c>=65 && c<=90 || c>=97 && c<=122 || c==45 || c==46 || c==95,"模型名称格式无效 / Invalid model name")}
        require(key.size<=512,"API Key 格式无效 / Invalid API key")
        for(c in key.toArray()){require(c>=33 && c<=126,"API Key 格式无效 / Invalid API key")}
    }
    func save(m: String,key: String): Unit {
        let name=m.trimAscii();let secret=key.trimAscii();validate(name,secret)
        if(!path.isEmpty()){
            let j=JsonObject();j.put("provider",JsonString("deepseek"));j.put("model",JsonString(name));j.put("apiKey",JsonString(secret))
            safeWrite(path,j.toJsonString())
        }
        model=name;apiKey=secret;loadError=false;connectionState=0;latencyMillis = -1;generation++
    }
}
func agentEditor(app: App): TerminalEditor {if(app.agentField==105){app.agentKeyEditor}else{app.agentModelEditor}}
func openAgentSettings(app: App): Unit {
    app.agentModelEditor.set(app.agentSettings.model);app.agentKeyEditor.set(app.agentSettings.apiKey)
    app.agentField = -1;app.menuPage=4;app.menuFocus=104
}
func agentFieldLabel(app: App,id: Int64): String {
    if(id==104){return app.agentModelEditor.text+if(app.agentField==104){"_"}else{""}}
    if(app.agentKeyEditor.text.isEmpty()){return app.t("点击填写 API Key","Click to enter API Key")}
    return "****************"+if(app.agentField==105){"_"}else{""}
}
func handleAgentSettings(app: App,w: SdlWindow,record: UiEventRecord): Bool {
    if(app.menuPage!=4 || app.agentField<0){return false}
    let e=agentEditor(app);let mods=record.metadata.modifiers
    match(record.event){
        case UiEvent.TextInput(text)=>e.insert(text);return true
        case UiEvent.TextEditing(text,_,_)=>e.composition=text;return true
        case UiEvent.WindowFocusLost=>e.composition="";return false
        case UiEvent.KeyDown(key,repeat)=>
            if(!e.composition.isEmpty()) {match(key){case Key.Escape=>e.composition="";case _=>()};return true}
            if(mods.ctrl){
                match(key){
                    case Key.Letter(65)=>e.selectAll()
                    case Key.Letter(86)=>e.insert(Clipboard.getText())
                    case Key.Letter(67)=>if(app.agentField!=105 && e.caret!=e.anchor){Clipboard.setText(e.selected())}
                    case _=>()
                };return true
            }
            match(key){
                case Key.Escape=>e.set(app.agentOriginal);app.agentField = -1
                case Key.Enter=>if(!repeat){e.composition="";app.agentField = -1}
                case Key.Backspace=>e.erase(true)
                case Key.Delete=>e.erase(false)
                case Key.Left=>e.move(false,mods.shift)
                case Key.Right=>e.move(true,mods.shift)
                case Key.Home=>e.caret=0;if(!mods.shift){e.anchor=e.caret}
                case Key.End=>e.caret=e.text.size;if(!mods.shift){e.anchor=e.caret}
                case Key.Tab=>if(!repeat){app.agentField=if(app.agentField==104){105}else{104};app.menuFocus=app.agentField;app.agentOriginal=agentEditor(app).text;uiInputArea(w,MenuLayout(Layout(Float32(w.width),Float32(w.height))).box(app.agentField,page:4))}
                case _=>()
            };return true
        case _=>return false
    }
}
