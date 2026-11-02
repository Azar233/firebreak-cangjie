package firebreak

import sdl.*

func drawComparison(app: App,l: Layout): Unit {
    let r=app.assets.r
    r.fill(l.canvas,Color.rgb(33,39,34))
    for (right in [false,true]) {
        let b=compareBox(l.canvas,right)
        uiText(app,l,if (right) { app.t("处理方案","Treatment Plan") } else { app.t("原始场地","Baseline Site") },b.x+10.0,l.canvas.y+6.0,color:Color.rgb(245,221,143))
        if (let Some(v) <- app.pairView) {
            let view=if (right) { v.planned } else { v.baseline }
            let box=if (app.mapMode) { fittedMap(b,v.aspect) } else { b }
            if (app.mapMode) { drawMapPaperAt(app,Rect(box.x-32.0,box.y-32.0,box.w+64.0,box.h+64.0)) }
            view.draw(box)
            let run=if (right) { v.result.plannedReplay } else { v.result.baselineReplay }
            let snapshot=run.snapshots[min(v.step,run.snapshots.size-1)]
            r.pushClip(box)
            let world=if(app.mapMode){app.camera.mapWorldBox(box)}else{box}
            let targets=run.targets
            for (i in 0..CELL_COUNT) {
                if (!targets[i] && snapshot.age[i]<=0) { continue }
                let x=i%GRID_X; let z=i/GRID_X
                let point=if (app.mapMode) { Point(world.x+(Float32(x)+0.5)*world.w/24.0,world.y+(Float32(z)+0.5)*world.h/20.0) }
                    else { app.camera.project(view.fireAnchor(i),box) }
                if (targets[i]) { r.strokeRect(Rect(point.x-4.0,point.y-4.0,8.0,8.0),Pen(width:2.0,color:if (snapshot.exposed[i]) { Color.rgb(255,104,73) } else { Color.rgb(103,219,241) })) }
                if (snapshot.age[i]>0) {
                    let flame=app.assets.image("textures/block/fire_0.png"); let side=flame.width
                    let n=max(1,Int64(flame.height/side)); let index=Int64(app.clockNow/80)%n
                    let size=if (app.mapMode) { max(8.0,min(48.0,world.w/24.0)) } else { Float32(app.camera.zoom) }
                    app.assets.blit("textures/block/fire_0.png",Rect(point.x-size/2.0,point.y-size/2.0,size,size),source:Some(Rect(0.0,Float32(index)*side,side,side)))
                }
            }
            r.popClip()
            uiText(app,l,app.t("燃烧 ${snapshot.burning()} / 燃尽 ${snapshot.burned()}","Burning ${snapshot.burning()} / Burned ${snapshot.burned()}"),b.x+8.0,b.bottom()-24.0)
        }
    }
    if (app.pairView.isNone()) { uiText(app,l,app.t("选择样本数，再开始配对评估","Choose sample count, then start paired evaluation"),l.canvas.x+24.0,l.canvas.centerY()) }
}
func drawComparisonPanel(app: App,l: Layout): Unit {
    let x=l.panel.x+18.0; let y=l.panel.y
    uiText(app,l,if (let Some(result) <- app.evalResult) { if (result.candidatePreview) { app.t("候选对照 / 尚未应用","Candidate Preview / Unapplied") } else { app.t("配对评估 / 无风规则 v1","Paired Evaluation / No-wind v1") } } else { app.t("配对评估 / 无风规则 v1","Paired Evaluation / No-wind v1") },x,y+18.0)
    if (let Some(result) <- app.evalResult) {
        uiText(app,l,app.t("全部 ${result.rows.size} 组 / 加权均值","All ${result.rows.size} scenarios / Weighted mean"),x,y+44.0)
        uiText(app,l,app.t("烧损 ${money(result.mean(false,0))} → ${money(result.mean(true,0))}","Burned ${money(result.mean(false,0))} -> ${money(result.mean(true,0))}"),x,y+70.0)
        uiText(app,l,app.t("剩余 ${money(result.mean(false,1))} → ${money(result.mean(true,1))}","Remaining ${money(result.mean(false,1))} -> ${money(result.mean(true,1))}"),x,y+96.0)
        uiText(app,l,app.t("规划清理 ${money(result.mean(true,3))} 格","Planned clearing: ${money(result.mean(true,3))} cells"),x,y+122.0)
        uiText(app,l,app.t("目标接触样本 ${result.exposedSamples(false)} → ${result.exposedSamples(true)}","Contact samples ${result.exposedSamples(false)} -> ${result.exposedSamples(true)}"),x,y+148.0)
    } else if (let Some(job) <- app.evalJob) {
        let progress=job.progress(); uiText(app,l,app.t("正在评估 ${progress.completed}/${progress.total}","Evaluating ${progress.completed}/${progress.total}"),x,y+50.0)
        uiText(app,l,app.t("保持相同起火点和随机输入","Shared ignition and random input"),x,y+86.0)
    } else { uiText(app,l,app.t("评估当前场地与处理方案","Compare baseline and treatment"),x,y+50.0); uiText(app,l,app.t("未运行 / 不显示推测结果","Not evaluated / No estimates shown"),x,y+86.0) }
    mcButton(app,l,60,app.t("开始评估","Evaluate")); mcButton(app,l,61,app.t("取消评估","Cancel"))
    mcButton(app,l,62,app.t("上一步","Previous")); mcButton(app,l,63,app.t("下一步","Next"))
    mcButton(app,l,64,if (let Some(v) <- app.pairView) { if (v.playing) { app.t("暂停回放","Pause Replay") } else { app.t("播放情景 1","Play Scenario 1") } } else { app.t("播放情景 1","Play Scenario 1") })
    mcButton(app,l,66,app.t("下次样本数：${app.sampleCount}","Next Sample Count: ${app.sampleCount}"))
    mcButton(app,l,65,app.t("导出报告与地图","Export Report & Maps")); mcButton(app,l,67,app.t("查看最终状态","View Final State"))
    if (let Some(v) <- app.pairView) { uiText(app,l,app.t("情景 1 / 同步 ${v.step}/${v.maxStep} 步","Scenario 1 / Shared step ${v.step}/${v.maxStep}"),l.canvas.x+12.0,l.toolbar.y+10.0) }
    uiText(app,l,app.t("样本比例不是现实概率","Sample rates are not real probabilities"),l.canvas.x+12.0,l.toolbar.y+38.0,color:Color.rgb(245,221,143))
}
