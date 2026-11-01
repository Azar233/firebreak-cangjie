package firebreak

import sdl.*
import std.fs.remove
import std.convert.*

func money(v: Float64): String { v.format(".2") }
func frame(r: Renderer,b: Rect,dark!: Bool=false): Unit {
    r.fill(b,Color.rgb(22,24,21))
    r.fill(Rect(b.x+2.0,b.y+2.0,b.w-4.0,b.h-4.0),if (dark) { Color.rgb(59,63,54) } else { Color.rgb(105,108,97) })
    r.fill(Rect(b.x+2.0,b.y+2.0,b.w-4.0,2.0),Color.rgb(173,176,158))
    r.fill(Rect(b.x+2.0,b.y+2.0,2.0,b.h-4.0),Color.rgb(173,176,158))
    r.fill(Rect(b.x+4.0,b.bottom()-4.0,b.w-6.0,2.0),Color.rgb(41,43,37))
    r.fill(Rect(b.right()-4.0,b.y+4.0,2.0,b.h-6.0),Color.rgb(41,43,37))
}
func mcButton(app: App,l: Layout,id: Int64,title: String): Unit {
    let b=l.control(id); let selected=app.hover==id || app.pressed==id || app.activeField==id
    let sy: Float32=if (selected) { 86.0 } else { 66.0 }
    let xs: Array<Float32>=[0.0,2.0,198.0,200.0]; let ys=[sy,sy+2.0,sy+18.0,sy+20.0]
    let dx=[b.x,b.x+4.0,b.right()-4.0,b.right()]; let dy=[b.y,b.y+4.0,b.bottom()-4.0,b.bottom()]
    for (y in 0..3) { for (x in 0..3) {
        app.assets.blit("textures/gui/widgets.png",Rect(dx[x],dy[y],dx[x+1]-dx[x],dy[y+1]-dy[y]),
            source:Some(Rect(xs[x],ys[y],xs[x+1]-xs[x],ys[y+1]-ys[y])))
    } }
    if (app.pressed==id) { app.assets.r.fill(b,Color.rgba(0,0,0,40)) }
    app.assets.r.pushClip(Rect(b.x+4.0,b.y+4.0,b.w-8.0,b.h-8.0)); app.font.center(title,b); app.assets.r.popClip()
    if (CONTROLS[app.focus]==id || app.activeField==id) { app.assets.r.strokeRect(Rect(b.x-2.0,b.y-2.0,b.w+4.0,b.h+4.0),Pen(width:2.0,color:Color.rgb(234,215,129))) }
}
func cellOutline(app: App,l: Layout,i: Int64,color: Color): Unit {
    let x=i%GRID_X; let z=i/GRID_X; let r=app.assets.r
    if (app.mapMode) {
        let b=app.mapBox(l); r.strokeRect(Rect(b.x+Float32(x)*b.w/24.0,b.y+Float32(z)*b.h/20.0,b.w/24.0,b.h/20.0),Pen(width:2.0,color:color)); return
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
    let r=app.assets.r; let p=app.work.project; let b=app.mapBox(l)
    r.fill(b,Color.rgb(174,166,139))
    if (let Some(t) <- app.reference) { r.textureStyled(t,b) }
    for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
        let i=z*GRID_X+x; let box=Rect(b.x+Float32(x)*b.w/24.0,b.y+Float32(z)*b.h/20.0,b.w/24.0,b.h/20.0)
        if (app.reference.isNone() || p.land[i]!=0) {
            r.strokeRect(box,Pen(width:2.0,color:landColor(p.land[i])))
        }
        if (p.treatment[i]!=0) { r.strokeRect(box,Pen(width:2.0,color:Color.rgb(239,190,61))) }
        r.strokeRect(box,Pen(width:1.0,color:Color.rgba(20,24,20,65)))
    } }
}
func drawOverlays(app: App,l: Layout): Unit {
    let r=app.assets.r; let p=app.work.project
    r.pushClip(l.canvas)
    for (i in 0..CELL_COUNT) {
        if (p.targets[i]!=0) { cellOutline(app,l,i,Color.rgb(103,219,241)) }
        if (p.forbidden[i]!=0) { cellOutline(app,l,i,Color.rgb(237,103,116)) }
    }
    if (app.view.selectedX>=0 && app.view.selectedZ>=0) { cellOutline(app,l,app.view.selectedZ*GRID_X+app.view.selectedX,Color.rgb(255,235,137)) }
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
                let b=app.mapBox(l); Point(b.x+(Float32(x)+0.5)*b.w/24.0,b.y+(Float32(z)+0.5)*b.h/20.0)
            } else { app.camera.project(app.view.fireAnchor(i),l.canvas) }
            let size=if (app.mapMode) { max(10.0,min(24.0,app.mapBox(l).w/24.0)) } else { Float32(app.camera.zoom)*1.1 }
            app.assets.blit("textures/block/fire_0.png",Rect(point.x-size/2.0,point.y-(if (app.mapMode) { size/2.0 } else { size }),size,size),
                source:Some(Rect(0.0,Float32(animation)*side,side,side)))
        }
        r.popClip()
    }
    r.popClip()
}
func drawSimulationPanel(app: App,l: Layout): Unit {
    let f=app.font; let x=l.panel.x+18.0; let y=l.panel.y; let p=app.work.project; let e=app.experiment
    if (app.simParameters) {
        f.draw("无风 / 四邻接 / 规则 v1",x,y+18.0)
        let labels=["每步每条边传播概率 (0-1)","燃烧持续步数 (1-8)","情景 seed (0-2147483647)"]
        for (i in 0..3) {
            f.draw(labels[i],x,y+36.0+Float32(i)*76.0,color:Color.rgb(206,211,190))
            let id=49+i
            mcButton(app,l,id,if (app.activeField==id) { app.draft+"_" } else { if (id==49) { money(p.spreadProbability) } else if (id==50) { "${p.burnSteps}" } else { "${p.seed}" } })
        }
        f.draw("Enter 确认 / Esc 取消输入",x,y+300.0,color:Color.rgb(206,211,190))
        f.draw("修改参数会清除旧试验。",x,y+332.0,color:Color.rgb(206,211,190))
        f.draw("仿真步不代表现实秒数。",x,y+364.0,color:Color.rgb(245,221,143))
    } else {
        f.draw("火势实验 / 四邻接无风",x,y+18.0)
        let state=if (let Some(run) <- e.run) { "${run.cursor} / ${run.snapshots.size-1} 步"+(if (run.running) { " · 运行" } else { " · 暂停" }) }
            else { if (p.ignition<0) { "尚未开始 / 先设置起火点" }
                else if (p.fuel(p.ignition,planned:e.planned)<=0.0) { "起火格不可燃 / 请重新设置" }
                else { "起火点 (${p.ignition%GRID_X},${p.ignition/GRID_X}) / 未开始" } }
        f.draw(state,x,y+46.0,color:Color.rgb(245,221,143))
        let stats=if (let Some(run) <- e.run) { "燃烧 ${run.current().burning()} / 燃尽 ${run.current().burned()} 格" } else { "相对可燃量：林地为 1" }
        f.draw(stats,x,y+74.0,color:Color.rgb(206,211,190))
        f.draw("连通 ${e.analysis.sizes.size} 片 / 最大 ${e.analysis.largest} 格",x,y+100.0,color:Color.rgb(206,211,190))
        let contacts=if (let Some(run) <- e.run) { "目标接触 ${run.current().contacts()} 格" }
            else { if (e.analysis.path.isEmpty()) { "无可燃路径到目标邻域" } else { "可燃路径到目标邻域 ${e.analysis.path.size} 格" } }
        f.draw(contacts,x,y+126.0,color:Color.rgb(245,221,143))
        mcButton(app,l,40,if (let Some(run) <- e.run) { if (run.running) { "暂停" } else { "开始/继续" } } else { "开始" })
        mcButton(app,l,41,"单步")
        mcButton(app,l,42,"重置")
        mcButton(app,l,45,if (app.pickingIgnition) { "点击林地" } else { "设置起火" })
        mcButton(app,l,43,"上一快照"); mcButton(app,l,44,"下一快照")
        mcButton(app,l,46,if (e.showConnectivity) { "连通覆盖：开" } else { "连通覆盖：关" })
        mcButton(app,l,47,if (e.planned) { "当前：处理方案" } else { "当前：原始场地" })
    }
    mcButton(app,l,48,if (app.simParameters) { "返回火势实验" } else { "传播参数与 seed" })
}
func render(app: App,window: SdlWindow,capture!: String=""): Unit {
    let r=window.renderer; let f=app.font; let p=app.work.project
    let l=Layout(Float32(window.width),Float32(window.height))
    let reference=app.mapMode && app.referenceMode && app.reference.isSome()
    if (app.comparePanel) {
        if (let Some(v) <- app.pairView) { v.prepare(app.camera,l.canvas,window,app.mapMode,app.view.showCanopy,!capture.isEmpty(),app.dragging || app.panning) }
    } else if (!reference) { app.view.prepare(app.camera,if (app.mapMode) { app.mapBox(l) } else { l.canvas },window,
        interacting:app.dragging || app.panning,forceFull:!capture.isEmpty(),topDown:app.mapMode) }
    r.beginScene(l.width,l.height,Color.rgb(34,38,32))
    frame(r,Rect(12.0,12.0,l.width-24.0,76.0))
    f.draw("断火线",30.0,26.0,scale:2.0)
    f.draw("P3 / 方案对比"+(if (app.work.dirty()) { " * 未保存" } else if (app.work.path.isEmpty()) { " / 未另存" } else { " / 已保存" }),164.0,40.0,color:Color.rgb(222,220,192))
    mcButton(app,l,0,"相机复位"); mcButton(app,l,1,"俯视编辑")
    let titles=["新建","打开","另存为","导入底图","撤销","重做",if (app.mapMode) { "三维场景" } else { "二维地图" }]
    for (i in 0..7) { mcButton(app,l,10+i,titles[i]) }
    if (!app.comparePanel) { mcButton(app,l,18,if (reference) { "纹理俯视" } else { "参照底图" }) }
    mcButton(app,l,19,if (app.simPanel) { "场地编辑" } else { "火势实验" })
    mcButton(app,l,52,if (app.comparePanel) { "返回编辑" } else { "方案对比" })
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
    if (app.comparePanel) { drawComparisonPanel(app,l) }
    else if (app.simPanel) { drawSimulationPanel(app,l) }
    else if (app.settings) {
        f.draw("尺度与预算 / Enter 确认",x,y+18.0)
        let labels=["整张底图宽度 (米，0 未标定)","预算上限 (元)","清理单价 (元/平方米)","隔离带单价 (元/平方米)"]
        for (i in 0..4) {
            f.draw(labels[i],x,y+36.0+Float32(i)*76.0,color:Color.rgb(206,211,190))
            let id=33+i; mcButton(app,l,id,if (app.activeField==id) { app.draft+"_" } else { money(app.fieldValue(id)) })
        }
        f.draw("点击数值编辑 / Ctrl+A 清空",x,y+316.0,color:Color.rgb(206,211,190))
    } else {
        f.draw("24 x 20 场地标注",x,y+18.0)
        f.draw("工具："+TOOL_NAMES[app.tool],x,y+48.0,color:Color.rgb(245,221,143))
        f.draw(if (p.metersWide>0.0) { "每格 ${money(p.cellArea())} 平方米" } else { "未标定：面积/费用不可用" },x,y+78.0,color:Color.rgb(206,211,190))
        f.draw("处理 ${p.count(p.treatment)} 格 / ￥${money(p.cost())}",x,y+108.0,color:Color.rgb(245,221,143))
        f.draw("预算 ￥${money(p.budget)}",x,y+138.0,color:Color.rgb(206,211,190))
        f.draw("保护 ${p.count(p.targets)} 格 / 禁区 ${p.count(p.forbidden)} 格",x,y+164.0,color:Color.rgb(206,211,190))
        mcButton(app,l,2,if (app.view.showCanopy) { "隐藏树冠 [H]" } else { "显示树冠 [H]" })
        mcButton(app,l,3,"向左旋转"); mcButton(app,l,4,"向右旋转")
        mcButton(app,l,5,"放大 +"); mcButton(app,l,6,"缩小 -")
    }
    if (!app.simPanel && !app.comparePanel) {
        mcButton(app,l,30,if (app.erase) { "擦除模式：开" } else { "擦除模式：关" })
        mcButton(app,l,31,"确认应用"); mcButton(app,l,32,"取消选区")
        mcButton(app,l,17,if (app.settings) { "返回场地信息" } else { "尺度与预算设置" })
    }
    let status=if (app.comparePanel) { "同步相机 / 同步仿真步 | 回放：情景 1 | 汇总：全部情景 | H 树冠" } else if (app.startCell>=0) { "预览 ${app.selection().size} 格 | Enter 应用 / Esc 取消 | 青色保护 / 红色禁区" }
        else { "左键框选 | 右键旋转 / 中键平移 | 1-9 工具 | Ctrl+S 保存 | Ctrl+Z 撤销" }
    r.pushClip(Rect(20.0,l.canvas.bottom()+6.0,l.canvas.w,24.0)); f.draw(status,20.0,l.canvas.bottom()+10.0,color:Color.rgb(190,199,170)); r.popClip()
    if (!app.comparePanel) {
        app.assets.blit("textures/gui/widgets.png",l.toolbar,source:Some(Rect(0.0,0.0,182.0,22.0)))
        app.assets.blit("textures/gui/widgets.png",Rect(l.toolbar.x+Float32(app.tool)*60.0-3.0,l.toolbar.y,72.0,66.0),source:Some(Rect(0.0,22.0,24.0,22.0)))
        for (i in 0..9) {
            let b=l.control(20+i)
            if (app.hover==20+i) { r.fill(b,Color.rgba(255,255,255,25)) }
            let icon=if (i==1) { "textures/block/oak_leaves.png" } else if (i==4) { "textures/block/bricks.png" } else { "textures/item/"+TOOL_PATHS[i]+".png" }
            app.assets.blit(icon,Rect(b.x+10.0,b.y+8.0,40.0,40.0),tint:if (i==1) { Color.rgb(91,157,57) } else { Color.rgb(255,255,255) })
            if (CONTROLS[app.focus]==20+i) { r.strokeRect(b,Pen(width:2.0,color:Color.rgb(234,215,129))) }
        }
        f.draw(TOOL_NAMES[app.tool],l.panel.x+16.0,l.toolbar.y+22.0,color:Color.rgb(245,221,143))
    }
    r.pushClip(Rect(20.0,l.height-25.0,l.width-40.0,22.0)); f.draw(if (app.startCell>=0) { app.previewText() } else { app.message },20.0,l.height-23.0,color:Color.rgb(222,220,192)); r.popClip()
    r.endScene()
    if (!capture.isEmpty()) {
        r.captureBmp(capture+".bmp")
        try (s=Surface.loadBmp(capture+".bmp")) { s.savePng(capture) }; remove(capture+".bmp")
    }
    r.present()
}

