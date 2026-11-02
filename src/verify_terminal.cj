package firebreak

import sdl.*
import std.fs.File
import std.fs.remove

func terminalKey(app: App,w: SdlWindow,key: Key,ctrl!:Bool=false,shift!:Bool=false): Unit {
    let flags=UInt16(if(ctrl){64}else{0})|UInt16(if(shift){1}else{0})
    require(app.handle(w,UiEventRecord(UiEvent.KeyDown(key,false),UiEventMetadata(modifiers:EventKeyModifiers(raw:flags)))),"Terminal unexpectedly quit")
}
func verifyTerminal(app: App,w: SdlWindow): Unit {
    verifyAgentSettings(app,w)
    let e=TerminalEditor();e.set("林😀é");e.erase(true)
    pass(e.text=="林😀","Terminal backspace removes an entire combining grapheme")
    e.erase(true);pass(e.text=="林","Terminal backspace removes an entire supplementary character without invalid UTF-8")
    e.selectAll();e.insert("草甸");e.move(false,false);e.erase(false)
    pass(e.text=="草" && e.caret==3,"Terminal selection replacement, grapheme movement and forward deletion preserve Chinese text")
    e.set(String.fromUtf8(Array<UInt8>(8192,repeat:97)));let beforeLimit=e.text
    pass(rejected({=>e.insert("越界")}) && e.text==beforeLimit,"Oversized terminal input fails atomically without deleting the draft")
    for(size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0),Size(3840.0,2160.0)]){
        for(quick in [false,true]){
            let m=TerminalLayout(Layout(size.w,size.h),quick)
            require(m.output.h>=44.0 && m.input.h>=44.0 && m.input.bottom()<m.screen.bottom(),"Terminal text layout is outside its screen")
            for(id in 0..6){let b=m.control(id);require(b.x>=0.0 && b.y>=0.0 && b.right()<=size.w && b.bottom()<=size.h,"Terminal button outside window")}
            for(id in 0..5){let b=m.control(id);require(m.hit(b.centerX(),b.centerY())==id,"Terminal controls overlap")}
        }
    }
    pass(true,"Full and quick terminal layouts fit minimum, normal, large and 4K windows with aligned hit targets")
    pass(app.font.glyph(0x9E93)==0x9E93 && app.font.glyph(0x7FAF)==0x7FAF,"Dynamic Chinese glyphs absent from ordinary UI are available from the full local font pack")
    app.cancel();app.activeField = -1;app.menuOpen=false;app.settings=false;app.preferences.gpuEnabled=true
    let before=app.work.project.text();let revision=app.work.revision;let yaw=app.camera.yaw;let tool=app.tool
    click(app,w,54)
    pass(app.terminal.open && !app.terminal.quick && app.terminal.messages.size==1,"Researcher header entry opens a clearly offline computer terminal")
    event(app,w,UiEvent.TextInput("/site"));terminalKey(app,w,Key.Enter)
    let t=app.terminal
    pass(t.messages.size==3 && t.messages[2].text.contains("24 x 20") && t.editor.text.isEmpty(),"Local site command reports actual project state without a model call")
    event(app,w,UiEvent.TextInput("请在预算内保护营地"));terminalKey(app,w,Key.Enter)
    pass(t.messages[t.messages.size-1].text.contains("API Key"),"Unconfigured natural-language input is explicitly retained locally and never presented as an AI answer")
    terminalKey(app,w,Key.Up);pass(t.editor.text=="请在预算内保护营地","Terminal input history recalls the previous request")
    terminalKey(app,w,Key.Down);pass(t.editor.text.isEmpty(),"Input history restores the pending empty draft")
    event(app,w,UiEvent.TextInput("中文草稿"));event(app,w,UiEvent.TextEditing("拼音",0,2));let count=t.messages.size
    terminalKey(app,w,Key.Enter)
    pass(t.messages.size==count && t.editor.text=="中文草稿","Enter confirms IME composition without prematurely submitting a message")
    event(app,w,UiEvent.TextInput("候选"));terminalKey(app,w,Key.Enter,shift:true)
    pass(t.editor.text=="中文草稿候选\n" && t.editor.composition.isEmpty(),"IME commit and Shift+Enter retain Unicode text and multiline input")
    terminalKey(app,w,Key.Letter(65),ctrl:true);pass(t.editor.selected()==t.editor.text,"Ctrl+A selects the complete multiline draft")
    terminalKey(app,w,Key.Backspace);event(app,w,UiEvent.TextInput("保留草稿"))
    let l=Layout(Float32(w.width),Float32(w.height))
    event(app,w,UiEvent.MouseDown(MouseButton.Left,l.canvas.centerX(),l.canvas.centerY()))
    event(app,w,UiEvent.MouseUp(MouseButton.Left,l.canvas.centerX(),l.canvas.centerY()))
    terminalKey(app,w,Key.Letter(87));terminalKey(app,w,Key.Digit(UInt8(54)))
    pass(app.camera.yaw==yaw && app.tool==tool && app.work.project.text()==before && app.work.revision==revision,"Terminal captures world clicks and shortcuts without changing scene, tools or document revision")
    terminalKey(app,w,Key.Escape)
    pass(!t.open && t.editor.text=="保留草稿" && t.messages.size==count,"Escape hides terminal while retaining draft and conversation")
    terminalKey(app,w,Key.RawScancode(56));event(app,w,UiEvent.TextInput("/"))
    pass(t.open && t.quick && t.editor.text=="保留草稿","Slash opens the same session without inserting an unwanted shortcut character")
    render(app,w,capture:"artifacts/p5-terminal-quick.png")
    terminalKey(app,w,Key.Tab);render(app,w,capture:"artifacts/p5-terminal.png")
    pass(!t.quick && t.editor.text=="保留草稿","Quick and computer views share the same editor and transcript")
    for(i in 0..150){t.append("Bounded local history ${i}")}
    pass(t.messages.size==128,"Terminal transcript evicts oldest entries at its display bound")
    event(app,w,UiEvent.MouseWheel(0.0,10.0,l.canvas.centerX(),l.canvas.centerY()));render(app,w)
    pass(t.scroll>0,"Terminal wheel scrolls retained conversation instead of the world camera")
    t.editor.composition="预编辑";event(app,w,UiEvent.WindowFocusLost)
    pass(t.editor.composition.isEmpty() && t.editor.text=="保留草稿","Focus loss clears transient composition while preserving the draft")
    t.messages.clear();t.revision++;t.editor.set("")
    t.append("FIREBREAK > Offline\n本地终端已就绪。模型尚未连接。\n/help 查看命令；/site 查看当前场地。")
    app.preferences.setEnglish(true);w.setSize(2560,1380);w.refreshSize();render(app,w,capture:"artifacts/p5-terminal-fullscreen.png")
    app.preferences.setEnglish(false);w.setSize(1280,860);w.refreshSize();t.open=false;t.quick=false;t.editor.set("");app.preferences.gpuEnabled=false;app.view.useGpu=false;app.view.dirty=true
    File.writeTo("artifacts/p5-terminal-state.txt",("Checks complete; project revision ${revision}; model not connected.\n").toArray())
}

func verifyAgentSettings(app: App,w: SdlWindow): Unit {
    verifyAgentSignal(app,w)
    let path="artifacts/agent-config-test.json"
    try{
        let settings=DeepSeekSettings(path);settings.save("deepseek-flash","test-placeholder-not-a-key")
        let restored=DeepSeekSettings(path)
        pass(restored.model=="deepseek-flash" && restored.apiKey=="test-placeholder-not-a-key" && restored.baseUrl=="https://api.deepseek.com","DeepSeek official model and API key persist only in the separate local settings file")
        settings.save(" deepseek-flash\n","\r\n test-placeholder-not-a-key \t")
        pass(settings.model=="deepseek-flash" && settings.apiKey=="test-placeholder-not-a-key","Pasted model/key surrounding whitespace is normalized without changing the credential content")
        settings.connectionState=2;settings.latencyMillis=80;settings.save("deepseek-flash","test-placeholder-not-a-key")
        pass(settings.connectionState==0 && settings.latencyMillis== -1 && restored.connectionState==0,"Saving or reloading a key never claims a verified connection or fabricates ping")
        let bytes=File.readFrom(path)
        pass(rejected({=>settings.save("invalid model","different-placeholder")}) && File.readFrom(path)==bytes && settings.apiKey=="test-placeholder-not-a-key","Invalid connection settings cannot overwrite the existing file or live key")
        File.writeTo(path,"{broken".toArray());let damaged=DeepSeekSettings(path)
        pass(damaged.loadError && damaged.apiKey.isEmpty(),"Malformed agent settings fall back without exposing their content")
    }finally{remove(path)}
    app.menuOpen=true;openAgentSettings(app);let before=app.work.project.text();let revision=app.work.revision
    menuClick(app,w,105);event(app,w,UiEvent.TextInput("test-placeholder-not-a-key"));terminalKey(app,w,Key.Enter)
    pass(agentFieldLabel(app,105).contains("****") && !agentFieldLabel(app,105).contains("placeholder"),"API key is masked in the settings label")
    menuClick(app,w,106)
    pass(app.agentSettings.apiKey=="test-placeholder-not-a-key" && app.message.contains("尚未进行连接验证") && app.work.project.text()==before && app.work.revision==revision,"Saving an API key reports unverified configuration without altering the site or contacting a model")
    render(app,w,capture:"artifacts/p5-agent-settings.png")
    menuClick(app,w,105);terminalKey(app,w,Key.Letter(65),ctrl:true);event(app,w,UiEvent.TextInput("discard-this-draft"));terminalKey(app,w,Key.Escape)
    pass(app.agentKeyEditor.text=="test-placeholder-not-a-key","Escape cancels a secret draft without replacing the saved key")
    menuClick(app,w,105);terminalKey(app,w,Key.Letter(65),ctrl:true);terminalKey(app,w,Key.Backspace);terminalKey(app,w,Key.Enter);menuClick(app,w,106)
    pass(app.agentSettings.apiKey.isEmpty(),"Clearing and saving the API key removes the active local credential")
    let generation=app.agentSettings.generation
    pass(!publishAgentConnection(app,generation-1,AgentConnectionResult(true,true,25,"")) && app.agentSettings.connectionState==0,"A stale connection result cannot verify a newer saved credential")
    pass(publishAgentConnection(app,generation,AgentConnectionResult(true,false,70,"HTTP 401")) && app.agentSettings.connectionState==3 && app.agentSettings.latencyMillis== -1,"Failed probe publishes an unreachable state without pretending to measure usable ping")
    pass(publishAgentConnection(app,generation,AgentConnectionResult(true,true,125,"")) && app.agentSettings.connectionState==2 && app.agentSettings.latencyMillis==125,"A completed current probe publishes actual verified state and transport duration")
    app.agentSettings.connectionState=0;app.agentSettings.latencyMillis = -1
    app.agentConnection=Some(AgentConnectionJob(generation,app.agentSettings.model,""))
    pass(!app.menuEnabled(107),"An active connection probe disables duplicate requests instead of accumulating background jobs")
    app.agentConnection=None
    app.message=app.t("API 连接尚未验证。","API connection has not been verified.")
    app.agentField = -1;app.menuOpen=false
}

func verifyAgentSignal(app: App,w: SdlWindow): Unit {
    let wide=AgentWide("Firebreak");pass(unsafe{wide.pointer.read()}==UInt16(70),"Native HTTPS strings preserve the ASCII request data as UTF-16")
    wide.close();wide.close();pass(wide.isClosed(),"Native HTTPS string storage closes idempotently")
    let native=AgentWinHttp();require(native.functions[9].isNotNull(),"WinHTTP close function missing");native.close();native.close()
    pass(native.isClosed(),"Native Windows HTTPS functions resolve from System32 and release the module safely")
    try(s=Surface.loadPng("assets/minecraft/textures/gui/icons.png")){
        require(s.size().w==256.0 && s.size().h==256.0,"Unexpected server icon atlas dimensions")
        let positions=[176,176,216]
        for(i in 0..3){
            var count: Int64=0
            for(y in 0..8){for(x in 0..10){let c=s.readPixel(Int32(x+if(i==1){10}else{0}),Int32(y+positions[i]))
                if(c.a>0 && (if(i==0){c.g>150 && c.r<100}else if(i==1){c.b>150 && c.r<100}else{c.r>150 && c.g<100})){count++}
            }}
            require(count>0,"Expected green, blue or red server signal pixels are missing")
        }
        pass(true,"Original Minecraft icons atlas contains green ping, blue pending and red unreachable regions")
        for(ms in [0,149,150,299,300,599,600,999,1000]){let b=agentSignalRegion(2,ms,0);require(b.x==0.0 && b.y>=176.0 && b.y<=208.0,"Ping level outside source atlas")}
        for(tick in 0..16){let b=agentSignalRegion(1,0,UInt64(tick*150));require(b.x==10.0 && b.y>=176.0 && b.y<=208.0,"Pending animation outside source atlas")}
        pass(agentSignalRegion(3,0,0).y==216.0 && agentSignalRegion(2,149,0).y==176.0 && agentSignalRegion(2,1000,0).y==208.0,"Signal state mapping preserves ping thresholds, pending frame bounds and unreachable cross")
    }
    let r=w.renderer;r.beginScene(Float32(w.width),Float32(w.height),Color.rgb(15,16,15))
    app.font.draw("Signal atlas diagnostic / not a real connection test",30.0,26.0,shadow:false)
    let names=["Unverified","Checking","Verified","Unreachable"]
    for(i in 0..4){drawAgentSignal(app.assets,Rect(50.0+Float32(i)*220.0,86.0,60.0,48.0),i,80,150);app.font.draw(names[i],50.0+Float32(i)*220.0,156.0,shadow:false)}
    r.endScene();saveStressCapture(w,"artifacts/p5-agent-signals.png");r.present()
}
