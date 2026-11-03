package firebreak

import sdl.*
import std.math.floor

class MenuLayout {
    let scale: Float32
    let width: Float32
    let top: Float32
    let book: Rect
    let left: Float32
    init(l: Layout) {
        // Quarter steps grow the whole modal together; reserve room for book controls and hints.
        scale=max(1.0,min(3.0,Float32(floor(Float64(min((l.width-64.0)/448.0,(l.height-80.0)/634.0))*4.0))/4.0))
        width=448.0*scale; left=(l.width-width)/2.0; top=(l.height-464.0*scale)/2.0
        book=Rect((l.width-438.0*scale)/2.0,(l.height-634.0*scale)/2.0,438.0*scale,546.0*scale)
    }
    func at(x: Float32,y: Float32,w: Float32,h: Float32): Rect { Rect(left+x*scale,top+y*scale,w*scale,h*scale) }
    func bookAt(x: Float32,y: Float32,w: Float32,h: Float32): Rect { Rect(book.x+x*scale,book.y+y*scale,w*scale,h*scale) }
    func bookBodyBox(): Rect { bookAt(44.0,76.0,350.0,394.0) }
    func controls(page: Int64): Array<Int64> {
        match(page) {
            case 0=>[80,81,82,83,84,85,98,86,99,103,108,87]
            case 1=>[33,34,35,36,88]
            case 2=>[90,91,92,100,101,102,88]
            case 3=>[49,50,51,88]
            case 4=>[104,105,106,107,88]
            case 6=>[96,97,88]
            case 7=>[109,110,111,112,88]
            case 8=>[114,115,88]
            case 9=>[10,11,12,13,14,15,108,117,118,119,88]
            case 10=>[20,21,22,23,24,25,26,27,28,88]
            case 11=>[130,131,120,121,122,132,88]
            case 12=>[133,134,135,136,137,88]
            case _=>[93,94,95]
        }
    }
    func box(id: Int64,page!: Int64=0): Rect {
        if(page==12 && id>=133 && id<=137){return at(0.0,72.0+Float32(id-133)*52.0,448.0,44.0)}
        if(page==11){
            if(id==132){return at(0.0,332.0,448.0,44.0)}
            if(id==130 || id==131){return at(0.0,72.0+Float32(id-130)*52.0,448.0,44.0)}
            if(id>=120 && id<=122){return at(0.0,176.0+Float32(id-120)*52.0,448.0,44.0)}
        }
        if(page==9){
            if(id>=10 && id<=15){return at(Float32((id-10)%2)*228.0,72.0+Float32((id-10)/2)*52.0,220.0,44.0)}
            if(id==108 || id==117){return at(0.0,if(id==108){228.0}else{280.0},448.0,44.0)}
            if(id==118 || id==119){return at(Float32(id-118)*228.0,332.0,220.0,44.0)}
        }
        if(page==10 && id>=20 && id<=28){return at(Float32((id-20)%3)*152.0,88.0+Float32((id-20)/3)*72.0,144.0,52.0)}
        if(page==7 && id>=109 && id<=112){return at(0.0,72.0+Float32(id-109)*60.0,448.0,44.0)}
        if(page==0 && (id==103 || id==108)){return at(if(id==103){0.0}else{228.0},348.0,220.0,44.0)}
        if(page==0 && id==87){return at(0.0,400.0,448.0,44.0)}
        if(page==8 && (id==114 || id==115)){return at(0.0,104.0+Float32(id-114)*104.0,448.0,44.0)}
        if(page==4){
            if(id==104 || id==105){return at(0.0,104.0+Float32(id-104)*88.0,448.0,44.0)}
            if(id==106 || id==107){return at(Float32(id-106)*228.0,260.0,220.0,44.0)}
        }
        if(page==2){
            let ids=[90,91,92,100,101,102]
            for(i in 0..ids.size){if(id==ids[i]){return at(0.0,72.0+Float32(i)*52.0,448.0,44.0)}}
        }
        if (page==6) {
            if (id==88) { return bookAt(0.0,558.0,438.0,44.0) }
            return bookAt(if (id==96) { 48.0 } else { 342.0 },482.0,48.0,44.0)
        }
        if (id==100) { return at(0.0,274.0,448.0,44.0) }
        if (id==101) { return at(0.0,334.0,448.0,44.0) }
        if (id==86 || id==99) { return at(if (id==99) { 228.0 } else { 0.0 },296.0,220.0,44.0) }
        if (id==85 || id==98) { return at(if (id==98) { 228.0 } else { 0.0 },244.0,220.0,44.0) }
        if (id>=33 && id<=36) { return at(0.0,94.0+Float32(id-33)*76.0,448.0,44.0) }
        if (id>=49 && id<=51) { return at(0.0,94.0+Float32(id-49)*76.0,448.0,44.0) }
        if (id==88) { return at(0.0,388.0,448.0,44.0) }
        if (id>=90 && id<=92) { return at(0.0,94.0+Float32(id-90)*60.0,448.0,44.0) }
        if (id>=93) { return at(0.0,164.0+Float32(id-93)*60.0,448.0,44.0) }
        if (id==80) { return at(0.0,72.0,448.0,44.0) }
        if (id>=81 && id<=84) { return at(Float32((id-81)%2)*228.0,124.0+Float32((id-81)/2)*52.0,220.0,44.0) }
        return at(0.0,244.0+Float32(id-85)*52.0,448.0,44.0)
    }
    func hit(x: Float32,y: Float32,page: Int64): Int64 {
        for (id in controls(page)) { if (box(id,page:page).contains(x,y)) { return id } }; return -1
    }
}
func menuTitle(app: App): String {
    match(app.menuPage) {
        case 1=>app.t("项目设置","Project Settings")
        case 2=>app.t("显示选项","Display Options")
        case 3=>app.t("实验参数","Experiment Settings")
        case 4=>app.t("智能体设置","Agent Settings")
        case 5=>app.t("退出前保存？","Save before quitting?")
        case 7=>app.t("旧版小案例（合成场地）","Legacy Examples (Synthetic)")
        case 8=>app.t("声音设置","Sound Settings")
        case 9=>app.t("文件与项目","Files & Project")
        case 10=>app.t("高级标注工具","Advanced Annotation")
        case 11=>app.t("新建平坦森林","New Flat Forest")
        case 12=>app.t("森林教学案例与完整实验","Forest cases & complete experiment")
        case _=>app.t("工作台菜单","Workbench Menu")
    }
}
func menuLabel(app: App,id: Int64): String {
    match(id) {
        case 132=>app.t("教学森林 / 完整实验…","Teaching forest / Full experiment...")
        case 133=>app.t("64×64 稀疏森林 / p=0.40","64x64 sparse / p=0.40")
        case 134=>app.t("64×64 过渡区候选 / p=0.60","64x64 transition candidate / p=0.60")
        case 135=>app.t("64×64 高密度森林 / p=0.80","64x64 dense / p=0.80")
        case 136=>app.t("对当前森林运行完整实验","Run full experiment on current forest")
        case 137=>app.t("取消完整实验","Cancel full experiment")
        case 130=>app.t("下次植被概率：${app.forestDensity}% →","Next site probability: ${app.forestDensity}% ->")
        case 131=>app.t("下次生成seed：${app.forestSeed} →","Next forest seed: ${app.forestSeed} ->")
        case 120=>app.t("24×20 / 小型网格","24x20 / Small")
        case 121=>app.t("64×64 / 标准网格","64x64 / Standard")
        case 122=>app.t("128×128 / 大型网格","128x128 / Large")
        case 80=>app.t("回到工作台","Back to Workbench")
        case 81=>app.t("文件与项目…","Files & Project...")
        case 82=>app.t("显示选项…","Display Options...")
        case 83=>app.t("实验参数…","Experiment Settings...")
        case 84=>app.t("智能体设置…","Agent Settings...")
        case 85=>app.t("语言 / Language: 中文","Language / 语言: English")
        case 99=>app.t("方案建议…","Plan Suggestions...")
        case 98=>app.t("项目手册…","Project Handbook...")
        case 86=>app.t("保存项目","Save Project")
        case 87=>app.t("退出软件","Quit to Desktop")
        case 88=>app.t("完成","Done")
        case 100=>app.t("右上角显示帧率：","Top-right FPS: ")+app.t(if (app.preferences.showFps) { "开" } else { "关" },if (app.preferences.showFps) { "On" } else { "Off" })
        case 101=>app.t("场景渲染：","Scene renderer: ")+(if(app.preferences.gpuEnabled){"GPU / Auto"}else{"CPU"})
        case 102=>app.t("光影 / Shader：","Lighting / Shader: ")+(if(app.preferences.shadersEnabled){app.t("开","On")}else{app.t("关","Off")})+" (GPU)"
        case 104 | 105=>agentFieldLabel(app,id)
        case 106=>app.t("保存 DeepSeek 配置","Save DeepSeek Settings")
        case 107=>app.t("保存并测试连接","Save & Test Connection")
        case 108=>app.t("旧版小案例…","Legacy Examples...")
        case 103=>app.t("声音设置…","Sound Settings...")
        case 114=>app.t("按键音效：","UI Sounds: ")+"${audioLevel(app,114)}%"
        case 115=>app.t("背景音乐：","Music: ")+"${audioLevel(app,115)}%"
        case 10=>app.t("新建场景","New Scene")
        case 11=>app.t("打开项目","Open Project")
        case 12=>app.t("另存为…","Save As...")
        case 13=>app.t("导入底图…","Import Image...")
        case 14=>app.t("撤销","Undo")
        case 15=>app.t("重做","Redo")
        case 117=>app.t("高级：标定与预算…","Advanced: Scale & Budget...")
        case 118=>app.t("参照底图","Reference Image")
        case 119=>app.t("高级标注…","Advanced Tools...")
        case 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28=>app.toolName(id-20)
        case 109 | 110 | 111 | 112=>caseLabel(app,id-109)
        case 90=>app.t("树冠：","Canopy: ")+app.t(if (app.view.showCanopy) { "显示" } else { "隐藏" },if (app.view.showCanopy) { "Shown" } else { "Hidden" })
        case 91=>app.t("视图：","View: ")+app.t(if (app.mapMode) { "二维地图" } else { "三维场景" },if (app.mapMode) { "Top-down Map" } else { "3D Scene" })
        case 92=>app.t("相机复位","Reset Camera")
        case 93=>app.t("保存并退出","Save and Quit")
        case 94=>app.t("放弃未保存更改并退出","Discard Changes and Quit")
        case 95=>app.t("取消，回到菜单","Cancel, Back to Menu")
        case _=>if (app.activeField==id) { app.draft+"_" } else { money(app.fieldValue(id)) }
    }
}
func drawMenu(app: App,l: Layout,pixelRatio!: Float32=1.0): Unit {
    let r=app.assets.r; let f=app.font; let m=MenuLayout(l)
    r.fill(Rect(0.0,0.0,l.width,l.height),Color.rgba(0,0,0,185))
    if (app.menuPage==6) { drawHandbook(app,m,pixelRatio); return }
    f.center(menuTitle(app),m.at(0.0,12.0,448.0,30.0),scale:m.scale,snap:true,pixelRatio:pixelRatio)
    if (app.menuPage==1 || app.menuPage==3) {
        let labels=if (app.menuPage==1) {
            [app.t("场地宽度（米，0 为未标定）","Site width (m; 0 = uncalibrated)"),app.t("预算上限（元）","Budget limit (CNY)"),
             app.t("清理单价（元/平方米）","Clearing cost (CNY / m2)"),app.t("隔离带单价（元/平方米）","Firebreak cost (CNY / m2)")]
        } else { [app.t("每步每条边传播概率（0–1）","Spread chance per edge / step (0-1)"),app.t("燃烧持续步数（1–8）","Burn duration (1-8 steps)"),app.t("随机种子（0–2147483647）","Random seed (0-2147483647)")] }
        for (i in 0..labels.size) { f.draw(labels[i],m.left,m.top+(72.0+Float32(i)*76.0)*m.scale,scale:m.scale,snap:true,pixelRatio:pixelRatio) }
    }
    if (app.menuPage==3) { f.draw(app.t("四邻接 / 无风；修改后旧评估失效","Four neighbors / no wind; edits invalidate results"),m.left,m.top+340.0*m.scale,scale:0.85*m.scale,snap:true,pixelRatio:pixelRatio) }
    if (app.menuPage==4) {
        f.draw(app.agentSettings.baseUrl,m.left,m.top+54.0*m.scale,scale:0.85*m.scale,shadow:false,snap:true,pixelRatio:pixelRatio)
        f.draw(app.t("模型名称","Model name"),m.left,m.top+80.0*m.scale,scale:m.scale,snap:true,pixelRatio:pixelRatio)
        f.draw("API Key "+app.t("（仅保存在本机）","(stored locally)"),m.left,m.top+168.0*m.scale,scale:m.scale,snap:true,pixelRatio:pixelRatio)
        drawAgentSignal(app.assets,m.at(0.0,324.0,20.0,16.0),app.agentSettings.connectionState,app.agentSettings.latencyMillis,app.clockNow)
        f.draw(app.t("状态：","Status: ")+agentConnectionLabel(app),m.left+28.0*m.scale,m.top+324.0*m.scale,scale:0.85*m.scale,snap:true,pixelRatio:pixelRatio)
        f.draw(app.t("Enter 完成输入 / Esc 取消当前输入","Enter: finish input / Esc: cancel input"),m.left,m.top+354.0*m.scale,scale:0.8*m.scale,snap:true,pixelRatio:pixelRatio)
    }
    if (app.menuPage==5) {
        f.center(app.t("当前项目或编辑预览尚未保存。","Your project or edit preview is unsaved."),m.at(0.0,82.0,448.0,24.0),scale:m.scale,snap:true,pixelRatio:pixelRatio)
        if (app.startCell>=0 || app.activeField>=0) { f.center(app.t("请先返回工作台处理预览或输入。","Return to finish or cancel the pending edit."),m.at(0.0,116.0,448.0,24.0),scale:m.scale,snap:true,pixelRatio:pixelRatio) }
    }
    if(app.menuPage==8){
        f.draw(app.t("拖动调节，0为静音；设置自动保存。","Drag to adjust; 0 mutes. Saved locally."),m.left,m.top+72.0*m.scale,scale:0.85*m.scale,snap:true,pixelRatio:pixelRatio)
        f.draw(app.t("← → 调整5% / Home 静音 / End 最大","Left/Right: 5% / Home: Mute / End: Max"),m.left,m.top+288.0*m.scale,scale:0.85*m.scale,snap:true,pixelRatio:pixelRatio)
        if(!app.audio.ready){f.draw(app.t("音频未就绪，请检查音频文件或输出设备。","Check local audio files and output device."),m.left,m.top+326.0*m.scale,scale:0.8*m.scale,snap:true,pixelRatio:pixelRatio)}
    }
    for (id in m.controls(app.menuPage)) {
        if(app.menuPage==8 && (id==114 || id==115)){drawAudioSlider(app,m,id,pixelRatio)}
        else{mcButtonAt(app,m.box(id,page:app.menuPage),id,menuLabel(app,id),app.menuFocus==id || app.activeField==id,enabled:app.menuEnabled(id),textScale:m.scale,pixelRatio:pixelRatio,snapText:true)}
    }
    let hint=app.t("Esc 返回 / Tab 切换 / Enter 确认","Esc: Back / Tab: Focus / Enter: Select")
    f.center(hint,m.at(0.0,if(app.menuPage==0){456.0}else{444.0},448.0,24.0),scale:m.scale,snap:true,pixelRatio:pixelRatio,color:Color.rgb(190,190,190))
    r.pushClip(Rect(24.0,l.height-54.0,l.width-48.0,26.0))
    f.draw(app.message,24.0,l.height-48.0,color:Color.rgb(245,221,143)); r.popClip()
}
