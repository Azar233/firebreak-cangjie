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
            case 0=>[80,81,82,83,84,85,98,86,99,87]
            case 1=>[33,34,35,36,88]
            case 2=>[90,91,92,88]
            case 3=>[49,50,51,88]
            case 4=>[88]
            case 6=>[96,97,88]
            case _=>[93,94,95]
        }
    }
    func box(id: Int64,page!: Int64=0): Rect {
        if (page==6) {
            if (id==88) { return bookAt(0.0,558.0,438.0,44.0) }
            return bookAt(if (id==96) { 48.0 } else { 342.0 },482.0,48.0,44.0)
        }
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
        case _=>app.t("工作台菜单","Workbench Menu")
    }
}
func menuLabel(app: App,id: Int64): String {
    match(id) {
        case 80=>app.t("回到工作台","Back to Workbench")
        case 81=>app.t("项目设置…","Project Settings...")
        case 82=>app.t("显示选项…","Display Options...")
        case 83=>app.t("实验参数…","Experiment Settings...")
        case 84=>app.t("智能体设置…","Agent Settings...")
        case 85=>app.t("语言 / Language: 中文","Language / 语言: English")
        case 99=>app.t("方案建议…","Plan Suggestions...")
        case 98=>app.t("项目手册…","Project Handbook...")
        case 86=>app.t("保存项目","Save Project")
        case 87=>app.t("退出软件","Quit to Desktop")
        case 88=>app.t("完成","Done")
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
        let lines=[app.t("状态：尚未接入模型","Status: model not connected"),app.t("计划使用 CangjieMagic 智能体","Planned integration: CangjieMagic"),
            app.t("主界面：电脑终端；/ 快捷输入","Computer terminal + / quick input"),app.t("模型、连接与生成参数将在 P5 提供","Model, connection and generation options in P5"),
            app.t("当前无需联网即可编辑、评估和导出","Editing, evaluation and export work offline")]
        for (i in 0..lines.size) { f.draw(lines[i],m.left,m.top+(96.0+Float32(i)*40.0)*m.scale,scale:0.85*m.scale,snap:true,pixelRatio:pixelRatio) }
    }
    if (app.menuPage==5) {
        f.center(app.t("当前项目或编辑预览尚未保存。","Your project or edit preview is unsaved."),m.at(0.0,82.0,448.0,24.0),scale:m.scale,snap:true,pixelRatio:pixelRatio)
        if (app.startCell>=0 || app.activeField>=0) { f.center(app.t("请先返回工作台处理预览或输入。","Return to finish or cancel the pending edit."),m.at(0.0,116.0,448.0,24.0),scale:m.scale,snap:true,pixelRatio:pixelRatio) }
    }
    for (id in m.controls(app.menuPage)) {
        mcButtonAt(app,m.box(id),id,menuLabel(app,id),app.menuFocus==id || app.activeField==id,enabled:app.menuEnabled(id),textScale:m.scale,pixelRatio:pixelRatio,snapText:true)
    }
    let hint=app.t("Esc 返回 / Tab 切换 / Enter 确认","Esc: Back / Tab: Focus / Enter: Select")
    f.center(hint,m.at(0.0,444.0,448.0,24.0),scale:m.scale,snap:true,pixelRatio:pixelRatio,color:Color.rgb(190,190,190))
    r.pushClip(Rect(24.0,l.height-54.0,l.width-48.0,26.0))
    f.draw(app.message,24.0,l.height-48.0,color:Color.rgb(245,221,143)); r.popClip()
}
