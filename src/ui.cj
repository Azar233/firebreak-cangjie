package firebreak

import sdl.*
import std.fs.remove
import std.convert.*

func money(v: Float64): String { v.format(".2") }
func uiText(app: App,l: Layout,s: String,x: Float32,y: Float32,color!: Color=Color.rgb(235,235,224),scale!: Float32=1.0): Unit {
    let available=if (x>=l.panel.x) { l.panel.right()-x-12.0 } else { l.width-x-20.0 }
    let fitted=min(scale,available/max(1.0,app.font.measure(s)))
    app.font.draw(s,x,y,color:color,scale:fitted)
}
func frame(r: Renderer,b: Rect,dark!: Bool=false): Unit {
    r.fill(b,Color.rgb(22,24,21))
    r.fill(Rect(b.x+2.0,b.y+2.0,b.w-4.0,b.h-4.0),if (dark) { Color.rgb(59,63,54) } else { Color.rgb(105,108,97) })
    r.fill(Rect(b.x+2.0,b.y+2.0,b.w-4.0,2.0),Color.rgb(173,176,158))
    r.fill(Rect(b.x+2.0,b.y+2.0,2.0,b.h-4.0),Color.rgb(173,176,158))
    r.fill(Rect(b.x+4.0,b.bottom()-4.0,b.w-6.0,2.0),Color.rgb(41,43,37))
    r.fill(Rect(b.right()-4.0,b.y+4.0,2.0,b.h-6.0),Color.rgb(41,43,37))
}
func mcButton(app: App,l: Layout,id: Int64,title: String): Unit {
    mcButtonAt(app,l.control(id),id,title,CONTROLS[app.focus]==id || app.activeField==id)
}
func mcButtonAt(app: App,b: Rect,id: Int64,title: String,focused: Bool,enabled!: Bool=true,textScale!: Float32=1.0,pixelRatio!: Float32=1.0,snapText!: Bool=false): Unit {
    let selected=app.hover==id || app.pressed==id || app.activeField==id
    let sy: Float32=if (!enabled) { 46.0 } else if (selected) { 86.0 } else { 66.0 }
    let xs: Array<Float32>=[0.0,2.0,198.0,200.0]; let ys=[sy,sy+2.0,sy+18.0,sy+20.0]
    let edge=4.0*textScale
    let dx=[b.x,b.x+edge,b.right()-edge,b.right()]; let dy=[b.y,b.y+edge,b.bottom()-edge,b.bottom()]
    for (y in 0..3) { for (x in 0..3) {
        app.assets.blit("textures/gui/widgets.png",Rect(dx[x],dy[y],dx[x+1]-dx[x],dy[y+1]-dy[y]),
            source:Some(Rect(xs[x],ys[y],xs[x+1]-xs[x],ys[y+1]-ys[y])))
    } }
    if (app.pressed==id) { app.assets.r.fill(b,Color.rgba(0,0,0,40)) }
    let scale=min(textScale,(b.w-16.0*textScale)/max(1.0,app.font.measure(title)))
    app.assets.r.pushClip(Rect(b.x+edge,b.y+edge,b.w-2.0*edge,b.h-2.0*edge))
    app.font.draw(title,b.centerX()-app.font.measure(title)*scale/2.0,b.centerY()-8.0*scale,scale:scale,snap:snapText,pixelRatio:pixelRatio,
        color:if (enabled) { Color.rgb(235,235,224) } else { Color.rgb(150,150,150) }); app.assets.r.popClip()
    if (focused && enabled) { app.assets.r.strokeRect(Rect(b.x-2.0,b.y-2.0,b.w+4.0,b.h+4.0),Pen(width:2.0,color:Color.rgb(234,215,129))) }
}
func cellOutline(app: App,l: Layout,i: Int64,color: Color): Unit {
    let x=i%GRID_X; let z=i/GRID_X; let r=app.assets.r
    if (app.mapMode) {
        let b=app.mapWorldBox(l); r.strokeRect(Rect(b.x+Float32(x)*b.w/24.0,b.y+Float32(z)*b.h/20.0,b.w/24.0,b.h/20.0),Pen(width:2.0,color:color)); return
    }
    let y=app.scene.ground(x,z)+0.04
    let p=[Vec(Float64(x),y,Float64(z)),Vec(Float64(x+1),y,Float64(z)),Vec(Float64(x+1),y,Float64(z+1)),Vec(Float64(x),y,Float64(z+1))]
    for (j in 0..4) {
        let a=app.camera.project(p[j],l.canvas); let b=app.camera.project(p[(j+1)%4],l.canvas)
        r.strokeLine(a.x,a.y,b.x,b.y,Pen(width:2.0,color:color))
    }
}
func landColor(n: Int64): Color {
    match(n) { case 1=>Color.rgb(74,125,48); case 2=>Color.rgb(151,134,94); case 3=>Color.rgb(53,120,181); case 4=>Color.rgb(173,111,80); case _=>Color.rgb(127,118,98) }
}
func drawMapPaper(app: App,l: Layout): Unit {
    drawMapPaperAt(app,app.mapPaperBox(l))
}
func drawMapPaperAt(app: App,b: Rect): Unit {
    // Original resource packs can use different resolutions; preserve the outer
    // 1/16 of each edge rather than assuming a particular texture size.
    let texture=app.assets.image("textures/map/map_background.png")
    let sx: Array<Float32>=[0.0,texture.width/16.0,texture.width*15.0/16.0,texture.width]
    let sy: Array<Float32>=[0.0,texture.height/16.0,texture.height*15.0/16.0,texture.height]
    let xs=[b.x,b.x+24.0,b.right()-24.0,b.right()]
    let ys=[b.y,b.y+24.0,b.bottom()-24.0,b.bottom()]
    for (y in 0..3) { for (x in 0..3) {
        app.assets.blit("textures/map/map_background.png",Rect(xs[x],ys[y],xs[x+1]-xs[x],ys[y+1]-ys[y]),
            source:Some(Rect(sx[x],sy[y],sx[x+1]-sx[x],sy[y+1]-sy[y])))
    } }
}
func drawReference(app: App,l: Layout): Unit {
    let r=app.assets.r; let p=app.work.project; let b=app.mapWorldBox(l)
    r.pushClip(app.mapBox(l));r.fill(app.mapBox(l),Color.rgb(174,166,139))
    if (let Some(t) <- app.reference) { r.textureStyled(t,b) }
    for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
        let i=z*GRID_X+x; let box=Rect(b.x+Float32(x)*b.w/24.0,b.y+Float32(z)*b.h/20.0,b.w/24.0,b.h/20.0)
        if (app.reference.isNone() || p.land[i]!=0) {
            r.strokeRect(box,Pen(width:2.0,color:landColor(p.land[i])))
        }
        if (p.treatment[i]!=0) { r.strokeRect(box,Pen(width:2.0,color:Color.rgb(239,190,61))) }
        r.strokeRect(box,Pen(width:1.0,color:Color.rgba(20,24,20,65)))
    } }
    r.popClip()
}
func drawOverlays(app: App,l: Layout): Unit {
    let r=app.assets.r; let p=app.work.project
    r.pushClip(if(app.mapMode){app.mapBox(l)}else{l.canvas})
    for (i in 0..CELL_COUNT) {
        if (p.targets[i]!=0) { cellOutline(app,l,i,Color.rgb(103,219,241)) }
        if (p.forbidden[i]!=0) { cellOutline(app,l,i,Color.rgb(237,103,116)) }
    }
    if (app.view.selectedX>=0 && app.view.selectedZ>=0) { cellOutline(app,l,app.view.selectedZ*GRID_X+app.view.selectedX,Color.rgb(255,235,137)) }
    if (app.suggestPanel && app.candidateVisible) {
        if (let Some(result) <- app.searchResult) {
            if (!result.entries.isEmpty()) { for (i in result.entries[app.candidateIndex].candidate.added) { cellOutline(app,l,i,Color.rgb(255,215,66)) } }
        }
    }
    for (i in app.selection()) { cellOutline(app,l,i,Color.rgb(255,235,137)) }
    if (app.experiment.showConnectivity) {
        for (i in app.experiment.analysis.path) { cellOutline(app,l,i,Color.rgb(255,218,89)) }
    }
    if (p.ignition>=0) { cellOutline(app,l,p.ignition,Color.rgb(255,137,44)) }
    if (let Some(run) <- app.experiment.run) {
        r.pushClip(if (app.mapMode) { app.mapBox(l) } else { l.canvas })
        let snapshot=run.current(); let flame=app.assets.image("textures/block/fire_0.png")
        let side=flame.width; let count=max(1,Int64(flame.height/side))
        let animation=Int64(app.clockNow/80)%count
        for (i in 0..CELL_COUNT) {
            if (snapshot.exposed[i]) { cellOutline(app,l,i,Color.rgb(255,104,73)) }
            if (snapshot.age[i]<=0) { continue }
            let x=i%GRID_X; let z=i/GRID_X
            let point=if (app.mapMode) {
                let b=app.mapWorldBox(l); Point(b.x+(Float32(x)+0.5)*b.w/24.0,b.y+(Float32(z)+0.5)*b.h/20.0)
            } else { app.camera.project(app.view.fireAnchor(i),l.canvas) }
            let size=if (app.mapMode) { max(10.0,min(48.0,app.mapWorldBox(l).w/24.0)) } else { Float32(app.camera.zoom)*1.1 }
            app.assets.blit("textures/block/fire_0.png",Rect(point.x-size/2.0,point.y-(if (app.mapMode) { size/2.0 } else { size }),size,size),
                source:Some(Rect(0.0,Float32(animation)*side,side,side)))
        }
        r.popClip()
    }
    r.popClip()
}
func drawSimulationPanel(app: App,l: Layout): Unit {
    let x=l.panel.x+18.0; let y=l.panel.y; let p=app.work.project; let e=app.experiment
    if (app.simParameters) {
        uiText(app,l,app.t("无风 / 四邻接 / 规则 v1","No wind / 4 neighbors / Rule v1"),x,y+18.0)
        let labels=[app.t("每步每条边传播概率 (0-1)","Spread chance / edge / step (0-1)"),app.t("燃烧持续步数 (1-8)","Burn duration (1-8 steps)"),app.t("情景 seed (0-2147483647)","Scenario seed (0-2147483647)")]
        for (i in 0..3) {
            uiText(app,l,labels[i],x,y+36.0+Float32(i)*76.0,color:Color.rgb(206,211,190))
            let id=49+i
            mcButton(app,l,id,if (app.activeField==id) { app.draft+"_" } else { if (id==49) { money(p.spreadProbability) } else if (id==50) { "${p.burnSteps}" } else { "${p.seed}" } })
        }
        uiText(app,l,app.t("Enter 确认 / Esc 取消输入","Enter: Apply / Esc: Cancel input"),x,y+300.0,color:Color.rgb(206,211,190))
        uiText(app,l,app.t("修改参数会清除旧试验。","Edits invalidate previous trials."),x,y+332.0,color:Color.rgb(206,211,190))
        uiText(app,l,app.t("仿真步不代表现实秒数。","Steps are not real-world seconds."),x,y+364.0,color:Color.rgb(245,221,143))
    } else {
        uiText(app,l,app.t("火势实验 / 四邻接无风","Fire Trial / 4 neighbors, no wind"),x,y+18.0)
        let state=if (let Some(run) <- e.run) { app.t("${run.cursor} / ${run.snapshots.size-1} 步","Step ${run.cursor} / ${run.snapshots.size-1}")+(if (run.running) { app.t(" · 运行"," / Running") } else { app.t(" · 暂停"," / Paused") }) }
            else { if (p.ignition<0) { app.t("尚未开始 / 先设置起火点","Set ignition before starting") }
                else if (p.fuel(p.ignition,planned:e.planned)<=0.0) { app.t("起火格不可燃 / 请重新设置","No fuel at ignition; choose again") }
                else { app.t("起火点 (${p.ignition%GRID_X},${p.ignition/GRID_X}) / 未开始","Ignition (${p.ignition%GRID_X},${p.ignition/GRID_X}) / Ready") } }
        uiText(app,l,state,x,y+46.0,color:Color.rgb(245,221,143))
        let stats=if (let Some(run) <- e.run) { app.t("燃烧 ${run.current().burning()} / 燃尽 ${run.current().burned()} 格","Burning ${run.current().burning()} / Burned ${run.current().burned()}") } else { app.t("相对可燃量：林地为 1","Relative fuel: forest = 1") }
        uiText(app,l,stats,x,y+74.0,color:Color.rgb(206,211,190))
        uiText(app,l,app.t("连通 ${e.analysis.sizes.size} 片 / 最大 ${e.analysis.largest} 格","${e.analysis.sizes.size} clusters / Largest ${e.analysis.largest}"),x,y+100.0,color:Color.rgb(206,211,190))
        let contacts=if (let Some(run) <- e.run) { app.t("目标接触 ${run.current().contacts()} 格","Target contact: ${run.current().contacts()} cells") }
            else { if (e.analysis.path.isEmpty()) { app.t("无可燃路径到目标邻域","No fuel path to target perimeter") } else { app.t("可燃路径到目标邻域 ${e.analysis.path.size} 格","Path to target: ${e.analysis.path.size} cells") } }
        uiText(app,l,contacts,x,y+126.0,color:Color.rgb(245,221,143))
        mcButton(app,l,40,if (let Some(run) <- e.run) { if (run.running) { app.t("暂停","Pause") } else { app.t("开始/继续","Resume") } } else { app.t("开始","Start") })
        mcButton(app,l,41,app.t("单步","Step"))
        mcButton(app,l,42,app.t("重置","Reset"))
        mcButton(app,l,45,if (app.pickingIgnition) { app.t("点击林地","Pick Fuel") } else { app.t("设置起火","Ignition") })
        mcButton(app,l,43,app.t("上一快照","Previous")); mcButton(app,l,44,app.t("下一快照","Next"))
        mcButton(app,l,46,if (e.showConnectivity) { app.t("连通覆盖：开","Clusters: On") } else { app.t("连通覆盖：关","Clusters: Off") })
        mcButton(app,l,47,if (e.planned) { app.t("当前：处理方案","Mode: Treatment") } else { app.t("当前：原始场地","Mode: Baseline") })
    }
    mcButton(app,l,48,if (app.simParameters) { app.t("返回火势实验","Back to Trial") } else { app.t("传播参数与 seed","Experiment Settings") })
}
func render(app: App,window: SdlWindow,capture!: String=""): Unit {
    pollAgentConnection(app)
    pollAgentChat(app)
    app.frameMeter.tick(app.frameMeter.clock.ms())
    let r=window.renderer; let p=app.work.project
    let l=Layout(Float32(window.width),Float32(window.height))
    let reference=app.mapMode && app.referenceMode && app.reference.isSome()
    app.view.useGpu=app.preferences.gpuEnabled
    app.view.shadersEnabled=app.preferences.shadersEnabled && app.preferences.gpuEnabled
    if (app.comparePanel) {
        if (let Some(v) <- app.pairView) { v.baseline.useGpu=app.preferences.gpuEnabled;v.planned.useGpu=app.preferences.gpuEnabled;v.baseline.shadersEnabled=app.view.shadersEnabled;v.planned.shadersEnabled=app.view.shadersEnabled;v.prepare(app.camera,l.canvas,window,app.mapMode,app.view.showCanopy,!capture.isEmpty(),app.dragging || app.panning) }
    } else if (!reference) { app.view.prepare(app.camera,if (app.mapMode) { app.mapBox(l) } else { l.canvas },window,
        interacting:app.dragging || app.panning,forceFull:!capture.isEmpty(),topDown:app.mapMode) }
    r.beginScene(l.width,l.height,Color.rgb(34,38,32))
    frame(r,Rect(12.0,12.0,l.width-24.0,76.0))
    uiText(app,l,app.t("断火线","Firebreak"),30.0,26.0,scale:if (app.preferences.english) { 1.6 } else { 2.0 })
    uiText(app,l,app.t("P4 / 方案建议","P4 / Plan Suggestions")+(if (app.work.dirty()) { app.t(" * 未保存"," * Unsaved") } else if (app.work.path.isEmpty()) { app.t(" / 未另存"," / Not Saved") } else { app.t(" / 已保存"," / Saved") }),if (app.preferences.english) { 250.0 } else { 164.0 },40.0,color:Color.rgb(222,220,192))
    mcButton(app,l,53,app.t("菜单 [Esc]","Menu [Esc]"))
    mcButton(app,l,54,app.t("研究员","Researcher"))
    mcButton(app,l,0,app.t("相机复位","Reset Camera")); mcButton(app,l,1,app.t("俯视编辑","Overhead"))
    let titles=[app.t("新建","New"),app.t("打开","Open"),app.t("另存为","Save As"),app.t("导入底图","Import Image"),app.t("撤销","Undo"),app.t("重做","Redo"),if (app.mapMode) { app.t("三维场景","3D Scene") } else { app.t("二维地图","2D Map") }]
    for (i in 0..7) { mcButton(app,l,10+i,titles[i]) }
    if (!app.comparePanel && !app.suggestPanel) { mcButton(app,l,18,if (reference) { app.t("纹理俯视","Texture Map") } else { app.t("参照底图","Reference") }) }
    mcButton(app,l,19,if (app.simPanel) { app.t("场地编辑","Site Editor") } else { app.t("火势实验","Fire Trial") })
    mcButton(app,l,52,if (app.comparePanel) { app.t("返回编辑","Back to Editor") } else { app.t("方案对比","Compare Plans") })
    if (app.comparePanel) { drawComparison(app,l) }
    else {
        if (app.mapMode) {
            r.fill(l.canvas,Color.rgb(33,39,34)); drawMapPaper(app,l)
        } else { frame(r,Rect(l.canvas.x-4.0,l.canvas.y-4.0,l.canvas.w+8.0,l.canvas.h+8.0),dark:true) }
        if (reference) { drawReference(app,l) }
        else {
            if (!app.mapMode) { r.fill(l.canvas,Color.rgb(33,39,34)) }
            app.view.draw(if (app.mapMode) { app.mapBox(l) } else { l.canvas })
        }
        drawOverlays(app,l)
    }
    frame(r,l.panel,dark:true)
    let x=l.panel.x+18.0; let y=l.panel.y
    if (app.suggestPanel) { drawSuggestions(app,l) }
    else if (app.comparePanel) { drawComparisonPanel(app,l) }
    else if (app.simPanel) { drawSimulationPanel(app,l) }
    else if (app.settings) {
        uiText(app,l,app.t("尺度与预算 / Enter 确认","Scale & Budget / Enter: Apply"),x,y+18.0)
        let labels=[app.t("整张底图宽度 (米，0 未标定)","Full width (m; 0 = uncalibrated)"),app.t("预算上限 (元)","Budget limit (CNY)"),app.t("清理单价 (元/平方米)","Clearing cost (CNY / m2)"),app.t("隔离带单价 (元/平方米)","Firebreak cost (CNY / m2)")]
        for (i in 0..4) {
            uiText(app,l,labels[i],x,y+36.0+Float32(i)*76.0,color:Color.rgb(206,211,190))
            let id=33+i; mcButton(app,l,id,if (app.activeField==id) { app.draft+"_" } else { money(app.fieldValue(id)) })
        }
        uiText(app,l,app.t("点击数值编辑 / Ctrl+A 清空","Click to edit / Ctrl+A: Clear"),x,y+316.0,color:Color.rgb(206,211,190))
    } else {
        uiText(app,l,app.t("24 x 20 场地标注","24 x 20 Site Annotation"),x,y+18.0)
        uiText(app,l,app.t("工具：","Tool: ")+app.toolName(app.tool),x,y+48.0,color:Color.rgb(245,221,143))
        uiText(app,l,if (p.metersWide>0.0) { app.t("每格 ${money(p.cellArea())} 平方米","${money(p.cellArea())} m2 per cell") } else { app.t("未标定：面积/费用不可用","Uncalibrated: area/cost unavailable") },x,y+78.0,color:Color.rgb(206,211,190))
        uiText(app,l,app.t("处理 ${p.count(p.treatment)} 格 / ￥${money(p.cost())}","Treated ${p.count(p.treatment)} / CNY ${money(p.cost())}"),x,y+108.0,color:Color.rgb(245,221,143))
        uiText(app,l,app.t("预算 ￥${money(p.budget)}","Budget CNY ${money(p.budget)}"),x,y+138.0,color:Color.rgb(206,211,190))
        uiText(app,l,app.t("保护 ${p.count(p.targets)} 格 / 禁区 ${p.count(p.forbidden)} 格","Protected ${p.count(p.targets)} / Excluded ${p.count(p.forbidden)}"),x,y+164.0,color:Color.rgb(206,211,190))
        mcButton(app,l,2,if (app.view.showCanopy) { app.t("隐藏树冠 [H]","Hide Canopy [H]") } else { app.t("显示树冠 [H]","Show Canopy [H]") })
        mcButton(app,l,3,app.t("向左旋转","Rotate Left")); mcButton(app,l,4,app.t("向右旋转","Rotate Right"))
        mcButton(app,l,5,app.t("放大 +","Zoom In +")); mcButton(app,l,6,app.t("缩小 -","Zoom Out -"))
    }
    if (!app.simPanel && !app.comparePanel && !app.suggestPanel) {
        mcButton(app,l,30,if (app.erase) { app.t("擦除模式：开","Erase: On") } else { app.t("擦除模式：关","Erase: Off") })
        mcButton(app,l,31,app.t("确认应用","Apply")); mcButton(app,l,32,app.t("取消选区","Cancel"))
        mcButton(app,l,17,if (app.settings) { app.t("返回场地信息","Back to Site Info") } else { app.t("尺度与预算设置","Project Settings") })
    }
    let status=if (app.suggestPanel) { app.t("金色边框：新增候选，尚未应用 | 每个候选共用情景，不保证全局最优","Gold outlines: unapplied candidate | Shared scenarios; no global-optimum guarantee") } else if (app.comparePanel) { app.t("同步相机 / 同步仿真步 | 回放：情景 1 | 汇总：全部情景 | H 树冠","Shared camera / time | Replay: scenario 1 | Summary: all | H: Canopy") } else if (app.startCell>=0) { app.t("预览 ${app.selection().size} 格 | Enter 应用 / Esc 取消 | 青色保护 / 红色禁区","Preview ${app.selection().size} cells | Enter: Apply / Esc: Cancel | Cyan: Protected / Red: Excluded") }
        else if(app.mapMode){app.t("滚轮缩放 | 中键平移 | 左键框选 | 相机复位：整图 | Ctrl+S 保存","Wheel: Zoom | Middle: Pan | Drag: Select | Reset: Fit Map | Ctrl+S: Save")}
        else { app.t("左键框选 | 右键旋转 / 中键平移 | 1-9 工具 | Ctrl+S 保存 | Ctrl+Z 撤销","Drag: Select | Right: Rotate / Middle: Pan | 1-9: Tools | Ctrl+S: Save | Esc: Menu") }
    r.pushClip(Rect(20.0,l.canvas.bottom()+6.0,l.canvas.w,24.0)); uiText(app,l,status,20.0,l.canvas.bottom()+10.0,color:Color.rgb(190,199,170)); r.popClip()
    if (!app.comparePanel && !app.suggestPanel) {
        app.assets.blit("textures/gui/widgets.png",l.toolbar,source:Some(Rect(0.0,0.0,182.0,22.0)))
        app.assets.blit("textures/gui/widgets.png",Rect(l.toolbar.x+Float32(app.tool)*60.0-3.0,l.toolbar.y,72.0,66.0),source:Some(Rect(0.0,22.0,24.0,22.0)))
        for (i in 0..9) {
            let b=l.control(20+i)
            if (app.hover==20+i) { r.fill(b,Color.rgba(255,255,255,25)) }
            let icon=if (i==1) { "textures/block/oak_leaves.png" } else if (i==4) { "textures/block/bricks.png" } else { "textures/item/"+TOOL_PATHS[i]+".png" }
            app.assets.blit(icon,Rect(b.x+10.0,b.y+8.0,40.0,40.0),tint:if (i==1) { Color.rgb(91,157,57) } else { Color.rgb(255,255,255) })
            if (CONTROLS[app.focus]==20+i) { r.strokeRect(b,Pen(width:2.0,color:Color.rgb(234,215,129))) }
        }
        uiText(app,l,app.toolName(app.tool),l.panel.x+16.0,l.toolbar.y+22.0,color:Color.rgb(245,221,143))
    }
    r.pushClip(Rect(20.0,l.height-25.0,l.width-40.0,22.0)); uiText(app,l,app.view.backendName()+" | "+(if (app.startCell>=0) { app.previewText() } else if(!app.view.gpuError.isEmpty()){app.view.gpuError}else{app.message}),20.0,l.height-23.0,color:Color.rgb(222,220,192)); r.popClip()
    if (app.menuOpen) { drawMenu(app,l,pixelRatio:Float32(window.scale)*Float32(window.currentPixelDensity)) }
    if (app.preferences.showFps) { drawFps(app.font,app.frameMeter,l.canvas) }
    drawTerminal(app,l,window)
    r.endScene()
    if (!capture.isEmpty()) {
        r.captureBmp(capture+".bmp")
        try (s=Surface.loadBmp(capture+".bmp")) { s.savePng(capture) }; remove(capture+".bmp")
    }
    r.present()
}


func drawFps(font: PixelFont,meter: FrameMeter,canvas: Rect): Unit {
    let label=if (meter.fps>0.0) { "FPS: "+meter.fps.format(".0") } else { "FPS: --" }
    let width=font.measure(label)+12.0
    let box=Rect(canvas.right()-width-4.0,canvas.y+4.0,width,22.0)
    let r=font.assets.r
    r.pushClip(canvas);r.fill(box,Color.rgba(0,0,0,210))
    font.draw(label,box.x+6.0,box.y+3.0);r.popClip()
}
