package firebreak

import sdl.*

func drawComparison(app: App,l: Layout): Unit {
    let r=app.assets.r; let f=app.font
    r.fill(l.canvas,Color.rgb(33,39,34))
    for (right in [false,true]) {
        let b=compareBox(l.canvas,right)
        f.draw(if (right) { "处理方案" } else { "原始场地" },b.x+10.0,l.canvas.y+6.0,color:Color.rgb(245,221,143))
        if (let Some(v) <- app.pairView) {
            let view=if (right) { v.planned } else { v.baseline }
            let box=if (app.mapMode) { fittedMap(b,v.aspect) } else { b }
            if (app.mapMode) { drawMapPaperAt(app,Rect(box.x-32.0,box.y-32.0,box.w+64.0,box.h+64.0)) }
            view.draw(box)
            let run=if (right) { v.result.plannedReplay } else { v.result.baselineReplay }
            let snapshot=run.snapshots[min(v.step,run.snapshots.size-1)]
            r.pushClip(box)
            let targets=run.targets
            for (i in 0..CELL_COUNT) {
                if (!targets[i] && snapshot.age[i]<=0) { continue }
                let x=i%GRID_X; let z=i/GRID_X
                let point=if (app.mapMode) { Point(box.x+(Float32(x)+0.5)*box.w/24.0,box.y+(Float32(z)+0.5)*box.h/20.0) }
                    else { app.camera.project(view.fireAnchor(i),box) }
                if (targets[i]) { r.strokeRect(Rect(point.x-4.0,point.y-4.0,8.0,8.0),Pen(width:2.0,color:if (snapshot.exposed[i]) { Color.rgb(255,104,73) } else { Color.rgb(103,219,241) })) }
                if (snapshot.age[i]>0) {
                    let flame=app.assets.image("textures/block/fire_0.png"); let side=flame.width
                    let n=max(1,Int64(flame.height/side)); let index=Int64(app.clockNow/80)%n
                    let size=if (app.mapMode) { max(8.0,min(24.0,box.w/24.0)) } else { Float32(app.camera.zoom) }
                    app.assets.blit("textures/block/fire_0.png",Rect(point.x-size/2.0,point.y-size/2.0,size,size),source:Some(Rect(0.0,Float32(index)*side,side,side)))
                }
            }
            r.popClip()
            f.draw("燃烧 ${snapshot.burning()} / 燃尽 ${snapshot.burned()}",b.x+8.0,b.bottom()-24.0)
        }
    }
    if (app.pairView.isNone()) { f.draw("选择样本数，再开始配对评估",l.canvas.x+24.0,l.canvas.centerY()) }
}
func drawComparisonPanel(app: App,l: Layout): Unit {
    let f=app.font; let x=l.panel.x+18.0; let y=l.panel.y
    f.draw("配对评估 / 无风规则 v1",x,y+18.0)
    if (let Some(result) <- app.evalResult) {
        f.draw("全部 ${result.rows.size} 组 / 加权均值",x,y+44.0)
        f.draw("烧损 ${money(result.mean(false,0))} → ${money(result.mean(true,0))}",x,y+70.0)
        f.draw("剩余 ${money(result.mean(false,1))} → ${money(result.mean(true,1))}",x,y+96.0)
        f.draw("规划清理 ${money(result.mean(true,3))} 格",x,y+122.0)
        f.draw("目标接触样本 ${result.exposedSamples(false)} → ${result.exposedSamples(true)}",x,y+148.0)
    } else if (let Some(job) <- app.evalJob) {
        let progress=job.progress(); f.draw("正在评估 ${progress.completed}/${progress.total}",x,y+50.0)
        f.draw("保持相同起火点和随机输入",x,y+86.0)
    } else { f.draw("评估当前场地与处理方案",x,y+50.0); f.draw("未运行 / 不显示推测结果",x,y+86.0) }
    mcButton(app,l,60,"开始评估"); mcButton(app,l,61,"取消评估")
    mcButton(app,l,62,"上一步"); mcButton(app,l,63,"下一步")
    mcButton(app,l,64,if (let Some(v) <- app.pairView) { if (v.playing) { "暂停回放" } else { "播放情景 1" } } else { "播放情景 1" })
    mcButton(app,l,66,"下次样本数：${app.sampleCount}")
    mcButton(app,l,65,"导出报告与地图"); mcButton(app,l,67,"查看最终状态")
    if (let Some(v) <- app.pairView) { f.draw("情景 1 / 同步 ${v.step}/${v.maxStep} 步",l.canvas.x+12.0,l.toolbar.y+10.0) }
    f.draw("样本比例不是现实概率",l.canvas.x+12.0,l.toolbar.y+38.0,color:Color.rgb(245,221,143))
}
