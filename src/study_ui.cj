package firebreak

import sdl.*
import std.math.round

let STUDY_CONTROLS=[55,56,57,58,146,151,141,142,143,144,145,147,152,148,149,140,54,53]
func studyChart(l:Layout):Rect {Rect(l.canvas.x+50.0,l.canvas.y+44.0,l.canvas.w-78.0,l.canvas.h*0.4-44.0)}
func studyMap(l:Layout,aspect:Float64):Rect {
    let top=l.canvas.y+l.canvas.h*0.4+56.0;let h=l.canvas.bottom()-top-20.0
    let width=min(l.canvas.w*0.33,h*Float32(aspect));let height=width/Float32(aspect)
    return Rect(l.canvas.x+18.0,top,width,height)
}
class StudyPreview <: Resource {
    let project:Project;let scene:Scene;let view:VoxelView;let graph:Connectivity;let camera=Camera()
    init(p:Project,assets:Assets){project=p;scene=Scene(nx:p.nx,nz:p.nz,demo:false);populateScene(scene,p,true);view=VoxelView(scene,assets);graph=Connectivity(fuelMask(p,true),p.nx,p.nz)}
    public func close():Unit {view.close()}
    public func isClosed():Bool {view.isClosed()}
}
func studyPolicy(app:App,index:Int64):String {
    let zh=["未处理","随机疏林","连接优先","中线条带"]
    let en=["Baseline","Random","Connector","Center strip"]
    return app.t(zh[index],en[index])
}
func refreshStudyPreview(app:App):Unit {
    if(let Some(old)<-app.studyPreview){old.close()};app.studyPreview=None
    if(let Some(result)<-app.densityResult){
        var p=result.sample(app.studyPoint,app.studySample)
        if(let Some(plans)<-app.interventionResult){p=plans.preview(app.studySample,app.studyPolicy)}
        app.studyPreview=Some(StudyPreview(p,app.assets))
    }
}
func pollStudy(app:App):Unit {
    if(let Some(result)<-app.densityResult){if(result.revision!=app.work.revision){app.densityResult=None;app.interventionResult=None;refreshStudyPreview(app)}}
    if(let Some(job)<-app.studyJob){
        if(job.revision!=app.work.revision){job.cancel();app.studyJob=None;app.message=app.t("场地已变更，旧密度实验失效。","Site changed; previous density experiment invalidated.");return}
        let state=job.progress()
        if(state.done){
            app.studyJob=None
            if(!state.cancelled && state.error.isEmpty()){
                if(let Some(result)<-state.density){app.densityResult=Some(result);app.interventionResult=None;app.studyPoint=12;app.studySample=0;app.studyPolicy=0}
                if(let Some(result)<-state.interventions){app.interventionResult=Some(result);app.studyPolicy=0;app.studySample=min(app.studySample,result.samples-1)}
                refreshStudyPreview(app);app.message=app.t("实验完成，图表和地图使用可复现样本；应用需手动确认。","Study complete; charts and map use reproducible samples. Apply manually.")
            }else if(!state.error.isEmpty()){app.message=app.t("实验未完成：","Study failed: ")+localizedError(state.error,app.preferences.english)}
        }
    }
}
func studyEnabled(app:App,id:Int64):Bool {
    let busy=app.studyJob.isSome()
    if(id==142){return busy}
    if(id==141 || id==146 || id==151){return !busy}
    if(id==143 || id==144 || id==145 || id==147 || id==148 || id==149){return !busy && app.densityResult.isSome()}
    if(id==152){return !busy && app.interventionResult.isSome()}
    return true
}
func studyAction(app:App,w:SdlWindow,id:Int64):Unit {
    require(studyEnabled(app,id),app.t("请先等待或取消当前任务。","Wait for or cancel the current task."))
    playUiClick(app)
    match(id){
        case 140=>
            if(app.studyPanel){app.studyPanel=false}else{enterWorkflow(app,1);app.studyPanel=true;pollStudy(app)}
        case 141=>
            app.densityResult=None;app.interventionResult=None;refreshStudyPreview(app)
            let job=ForestStudyJob(app.work.project,app.work.revision,app.studySamples);app.studyJob=Some(job);job.start()
        case 142=>if(let Some(job)<-app.studyJob){job.cancel();app.studyJob=None;app.message=app.t("已取消实验，不发布部分样本。","Study cancelled; partial samples are not published.")}
        case 143 | 144=>
            let result=app.densityResult.getOrThrow();app.studyPoint=max(0,min(result.points.size-1,app.studyPoint+if(id==143){-1}else{1}));app.interventionResult=None;app.studyPolicy=0;refreshStudyPreview(app)
        case 145=>let result=app.densityResult.getOrThrow();let count=if(let Some(plans)<-app.interventionResult){min(result.samples,plans.samples)}else{result.samples};app.studySample=(app.studySample+1)%count;refreshStudyPreview(app)
        case 146=>app.studySamples=if(app.studySamples==8){32}else if(app.studySamples==32){64}else{8}
        case 151=>app.studyDose=match(app.studyDose){case 1=>4;case 4=>16;case 16=>64;case 64=>128;case _=>1}
        case 147=>
            let result=app.densityResult.getOrThrow();let base=readProjectText(result.source)
            let job=ForestStudyJob(base,app.work.revision,app.studySamples,mode:1,probability:result.points[app.studyPoint].probability,dose:app.studyDose)
            app.interventionResult=None;app.studyPolicy=0;refreshStudyPreview(app);app.studyJob=Some(job);job.start()
        case 152=>app.studyPolicy=(app.studyPolicy+1)%4;refreshStudyPreview(app)
        case 148=>
            let next=app.studyPreview.getOrThrow().project.copy();next.budget=app.work.project.budget
            next.clearingPrice=app.work.project.clearingPrice;next.breakPrice=app.work.project.breakPrice;next.metersWide=app.work.project.metersWide
            app.work.commit(next);app.refreshReference();app.syncScene();enterWorkflow(app,if(app.studyPolicy==0){0}else{2});pollStudy(app)
            app.message=app.t("已将预览样本应用到沙盘，可撤销；汇总均值不是这一个样本的结果。","Preview applied; undo is available. Aggregate means are not this single sample.")
        case 149=>app.requestFile(w,149)
        case _=>()
    }
}
func handleStudyInput(app:App,w:SdlWindow,record:UiEventRecord,l:Layout):Bool {
    match(record.event){
        case UiEvent.MouseMove(x,y)=>app.hover=l.hit(x,y,study:true)
        case UiEvent.MouseDown(button,x,y)=>
            if(let MouseButton.Left <- button){
                app.pressed=l.hit(x,y,study:true)
                if(app.pressed<0 && studyChart(l).contains(x,y) && app.studyJob.isNone()){
                    if(let Some(result)<-app.densityResult){
                        app.studyPoint=max(0,min(result.points.size-1,Int64(round(Float64((x-studyChart(l).x)/studyChart(l).w)*Float64(result.points.size-1)))))
                        app.interventionResult=None;app.studyPolicy=0;refreshStudyPreview(app)
                    }
                }
            }
        case UiEvent.MouseUp(button,x,y)=>if(let MouseButton.Left <- button){let id=app.pressed;app.pressed = -1;if(id>=0 && id==l.hit(x,y,study:true) && studyEnabled(app,id)){app.action(w,id)}}
        case UiEvent.WindowFocusLost=>app.pressed = -1
        case UiEvent.KeyDown(key,repeat)=>if(!repeat){match(key){
            case Key.Escape=>app.openMenu()
            case Key.Tab=>
                var current:Int64=0;for(i in 0..STUDY_CONTROLS.size){if(STUDY_CONTROLS[i]==CONTROLS[app.focus]){current=i}}
                let delta=if(record.metadata.modifiers.shift){-1}else{1}
                for(offset in 1..STUDY_CONTROLS.size+1){let at=(current+delta*offset+STUDY_CONTROLS.size)%STUDY_CONTROLS.size;let id=STUDY_CONTROLS[at];if(studyEnabled(app,id)){for(i in 0..CONTROLS.size){if(CONTROLS[i]==id){app.focus=i}};break}}
            case Key.Enter | Key.Space=>let id=CONTROLS[app.focus];if(STUDY_CONTROLS.contains(id) && studyEnabled(app,id)){app.action(w,id)}
            case Key.RawScancode(56)=>openTerminal(app,true);app.terminal.suppressSlash=true
            case _=>()
        }}
        case _=>()
    };return true
}
func prepareStudy(app:App,w:SdlWindow,l:Layout,force:Bool):Unit {
    if(let Some(preview)<-app.studyPreview){
        preview.view.useGpu=app.preferences.gpuEnabled;preview.view.shadersEnabled=app.preferences.gpuEnabled && app.preferences.shadersEnabled
        preview.view.prepare(preview.camera,studyMap(l,preview.project.aspect),w,topDown:true,forceFull:force)
    }
}
func studyText(app:App,text:String,x:Float32,y:Float32,width:Float32,color!:Color=Color.rgb(235,235,224)):Unit {
    app.font.draw(text,x,y,scale:min(1.0,width/max(1.0,app.font.measure(text))),color:color)
}
func drawStudy(app:App,l:Layout):Unit {
    let r=app.assets.r;let chart=studyChart(l);frame(r,l.canvas,dark:true)
    studyText(app,app.t("密度与连通 / 有限网格 / 四邻接开放边界","Density & connectivity / Finite open four-neighbor grid"),l.canvas.x+14.0,l.canvas.y+12.0,l.canvas.w-28.0)
    let blue=Color.rgb(95,210,241);let green=Color.rgb(179,232,106)
    for(i in 0..3){let y=chart.bottom()-Float32(i)*chart.h/2.0;r.strokeLine(chart.x,y,chart.right(),y,Pen(width:1.0,color:Color.rgb(79,87,74)));studyText(app,"${i*50}%",l.canvas.x+4.0,y-8.0,42.0)}
    for(i in 0..5){let x=chart.x+Float32(i)*chart.w/4.0;studyText(app,"${i*25}",x-12.0,chart.bottom()+8.0,32.0)}
    studyText(app,app.t("抽样密度 p (%) | 蓝：贯通频次+逐点95% Wilson | 绿：最大簇/全网格","Sampling p (%) | Blue: spanning + pointwise 95% Wilson | Green: largest / grid"),chart.x,chart.bottom()+30.0,chart.w)
    if(let Some(result)<-app.densityResult){
        for(i in 0..result.points.size){let point=result.points[i];let x=chart.x+Float32(point.probability)*chart.w
            let y=chart.bottom()-Float32(point.frequency())*chart.h;let g=chart.bottom()-Float32(point.largest/Float64(app.work.project.cells))*chart.h
            r.strokeLine(x,chart.bottom()-Float32(point.interval[0])*chart.h,x,chart.bottom()-Float32(point.interval[1])*chart.h,Pen(width:1.0,color:blue))
            if(i>0){let previous=result.points[i-1];let px=chart.x+Float32(previous.probability)*chart.w
                r.strokeLine(px,chart.bottom()-Float32(previous.frequency())*chart.h,x,y,Pen(width:2.0,color:blue))
                r.strokeLine(px,chart.bottom()-Float32(previous.largest/Float64(app.work.project.cells))*chart.h,x,g,Pen(width:2.0,color:green))
            }
            r.fill(Rect(x-2.0,y-2.0,4.0,4.0),blue)
            if(i==app.studyPoint){r.strokeLine(x,chart.y,x,chart.bottom(),Pen(width:1.0,color:Color.rgb(238,199,99)))}
        }
        let preview=app.studyPreview.getOrThrow();let map=studyMap(l,preview.project.aspect);drawMapPaperAt(app,Rect(map.x-8.0,map.y-8.0,map.w+16.0,map.h+16.0));preview.view.draw(map)
        r.pushClip(map)
        for(i in 0..preview.project.cells){if(preview.project.treatment[i]!=0){r.strokeRect(Rect(map.x+Float32(i%preview.project.nx)*map.w/Float32(preview.project.nx),map.y+Float32(i/preview.project.nx)*map.h/Float32(preview.project.nz),map.w/Float32(preview.project.nx),map.h/Float32(preview.project.nz)),Pen(width:1.0,color:Color.rgb(239,190,61)))}}
        let ignition=preview.project.ignition
        if(ignition>=0){let px=map.x+(Float32(ignition%preview.project.nx)+0.5)*map.w/Float32(preview.project.nx);let py=map.y+(Float32(ignition/preview.project.nx)+0.5)*map.h/Float32(preview.project.nz);r.strokeRect(Rect(px-4.0,py-4.0,8.0,8.0),Pen(width:2.0,color:Color.rgb(255,137,44)))}
        r.popClip()
        let x=map.right()+22.0;let width=l.canvas.right()-x-12.0;let y=map.y;let point=result.points[app.studyPoint]
        studyText(app,"p=${money(point.probability)} / seed ${preview.project.seed} / "+studyPolicy(app,app.studyPolicy),x,y,width)
        let graph=preview.graph
        studyText(app,app.t("本样本 ${graph.total} 格 / 最大簇 ${graph.largest}","Sample ${graph.total} cells / Largest ${graph.largest}"),x,y+24.0,width)
        let band=result.bracket()
        studyText(app,if(band.isEmpty()){app.t("范围内未跨过50%贯通频次","No 50% spanning crossing in range")}else{app.t("50%贯通经验括区：","Empirical 50% crossing bracket: ")+money(band[0])+"–"+money(band[1])},x,y+48.0,width)
        studyText(app,app.t("${result.samples}个seed；频次区间不是临界值区间","${result.samples} seeds; frequency CI is not a critical-point CI"),x,y+72.0,width,color:Color.rgb(235,211,135))
        if(let Some(plans)<-app.interventionResult){
            studyText(app,app.t("策略 | 最大簇 | 烧损 | 保留","Policy | largest | burned | remaining")+" (${plans.samples}, k=${plans.dose})",x,y+100.0,width)
            for(strategy in 0..4){studyText(app,studyPolicy(app,strategy)+" | "+money(plans.mean(strategy,2))+" | "+money(plans.mean(strategy,0))+" | "+money(plans.mean(strategy,1)),x,y+124.0+Float32(strategy)*22.0,width)}
            studyText(app,app.t("烧损配对差值SE：","Paired burn-delta SE: ")+money(plans.burnDeltaSE(1))+" / "+money(plans.burnDeltaSE(2))+" / "+money(plans.burnDeltaSE(3)),x,y+218.0,width,color:Color.rgb(205,213,189))
        }else{studyText(app,app.t("地图为所选seed的结构预览；点击曲线切换密度。","Map: selected seed, before fire. Click plot to select density."),x,y+104.0,width)}
    }else{studyText(app,app.t("开始扫描后显示真实结果；不会预设临界阈值。","Run a scan to display measured results; no preset critical threshold."),chart.x,chart.y+chart.h/2.0,chart.w)}
}
func drawStudyPanel(app:App,l:Layout):Unit {
    let x=l.panel.x+18.0;let y=l.panel.y
    uiText(app,l,app.t("临界观察 / ${app.work.project.nx}×${app.work.project.nz}","Critical-region study / ${app.work.project.nx}x${app.work.project.nz}"),x,y+18.0)
    let progress=if(let Some(job)<-app.studyJob){let state=job.progress();"${state.completed}/${state.total}"}else{app.t("独立占据 / 重采样可生长域","Independent sites / resample domain")}
    uiText(app,l,progress,x,y+48.0)
    for(id in [146,151,141,142,143,144,145,147,152,148,149,140]){
        let label=match(id){
            case 146=>app.t("下次${app.studySamples}次","Next: ${app.studySamples}")
            case 151=>app.t("下次${app.studyDose}格","Next: ${app.studyDose} cells")
            case 141=>app.t("开始扫描","Scan")
            case 142=>app.t("取消任务","Cancel")
            case 143=>app.t("上一密度","Previous p")
            case 144=>app.t("下一密度","Next p")
            case 145=>app.t("样本seed ${app.studySample+1} →","Sample seed ${app.studySample+1} ->")
            case 147=>app.t("运行等量干预对照","Compare equal clearing")
            case 152=>app.t("预览：","Preview: ")+studyPolicy(app,app.studyPolicy)
            case 148=>app.t("应用预览","Apply")
            case 149=>app.t("导出数据","Export")
            case _=>app.t("返回单次传播","Back to single fire")
        }
        mcButtonAt(app,l.control(id),id,label,CONTROLS[app.focus]==id,enabled:studyEnabled(app,id))
    }
}
