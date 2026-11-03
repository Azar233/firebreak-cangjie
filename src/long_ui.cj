package firebreak

import sdl.*

let LONG_CONTROLS=[55,56,57,58,161,162,163,164,165,166,167,168,170,171,172,173,174,175,176,177,160,16,0,2,54,53]
func clearLong(app:App):Unit {if(let Some(replay)<-app.longReplay){replay.close()};app.longReplay=None;app.longResult=None}
func pollLong(app:App,now:UInt64):Unit {
    if(let Some(result)<-app.longResult){if(result.revision!=app.work.revision){clearLong(app)}}
    if(let Some(job)<-app.longJob){
        if(job.revision!=app.work.revision){job.cancel();app.longJob=None;app.message=app.t("输入已修改，长期实验失效。","Inputs changed; long-run experiment invalidated.");return}
        let state=job.progress()
        if(state.done){app.longJob=None
            if(!state.cancelled && state.error.isEmpty()){
                if(let Some(result)<-state.result){clearLong(app);app.longResult=Some(result);let replay=LongReplay(result,app.assets);replay.seek(0,now);app.longReplay=Some(replay);app.message=app.t("长期对照完成；统计排除预热，回放仅为首seed的采样检查点。","Long-run study complete; statistics exclude warmup, replay samples the first seed.")}
            }else if(!state.error.isEmpty()){app.message=app.t("长期实验未完成：","Long-run study failed: ")+localizedError(state.error,app.preferences.english)}
        }
    }
    if(app.longPanel && !app.menuOpen && !app.terminal.open){if(let Some(replay)<-app.longReplay){replay.tick(now)}}
}
func longEnabled(app:App,id:Int64):Bool {
    let busy=app.longJob.isSome()
    if(id==168){return busy}
    if(id==16){return app.longReplay.isSome()}
    if(id>=161 && id<=167){return !busy}
    if(id>=170 && id<=177){return !busy && app.longReplay.isSome()}
    return true
}
func nextLongValue(value:Float64,values:Array<Float64>):Float64 {for(i in 0..values.size){if(values[i]==value){return values[(i+1)%values.size]}};return values[0]}
func longAction(app:App,w:SdlWindow,id:Int64):Unit {
    require(longEnabled(app,id),app.t("请先等待或取消当前任务。","Wait for or cancel the current task."));playUiClick(app)
    match(id){
        case 160=>if(app.longPanel){app.longPanel=false;if(let Some(replay)<-app.longReplay){replay.playing=false}}else{enterWorkflow(app,1);app.longPanel=true;pollLong(app,app.clockNow)}
        case 161=>app.longGrowth=nextLongValue(app.longGrowth,[0.0,0.002,0.01,0.05,0.1])
        case 162=>app.longLightning=nextLongValue(app.longLightning,[0.0,0.01,0.05,0.1,1.0])
        case 163=>app.longWarmup=match(app.longWarmup){case 0=>64;case 64=>128;case 128=>512;case _=>0}
        case 164=>app.longDrives=match(app.longDrives){case 256=>512;case 512=>2048;case 2048=>8192;case _=>256}
        case 165=>app.longSamples=if(app.longSamples==1){4}else if(app.longSamples==4){8}else{1}
        case 166=>app.longCapacity=match(app.longCapacity){case 0=>16;case 16=>64;case 64=>256;case 256=>app.work.project.cells;case _=>0}
        case 167=>
            let spec=LongSpec(app.longGrowth,app.longLightning,app.longWarmup,app.longDrives,app.longSamples,app.longCapacity)
            let job=LongJob(app.work.project,app.work.revision,spec);clearLong(app);app.longJob=Some(job);job.start()
        case 168=>if(let Some(job)<-app.longJob){job.cancel();app.longJob=None;app.message=app.t("已取消长期实验，不发布部分统计。","Long-run study cancelled; no partial results published.")}
        case 170=>let replay=app.longReplay.getOrThrow();if(replay.playing){replay.playing=false}else{replay.play(app.clockNow)}
        case 171 | 173=>let replay=app.longReplay.getOrThrow();replay.seek(replay.cursor+1,app.clockNow)
        case 172=>let replay=app.longReplay.getOrThrow();replay.seek(replay.cursor-1,app.clockNow)
        case 177=>app.longReplay.getOrThrow().seek(0,app.clockNow)
        case 176=>app.longHistogram = !app.longHistogram
        case 174=>app.requestFile(w,174)
        case 175=>
            let next=app.longReplay.getOrThrow().snapshot(app.longSelectedPolicy);app.work.commit(next);app.refreshReference();app.syncScene();enterWorkflow(app,0);pollLong(app,app.clockNow)
            app.message=app.t("已应用所选组的植被快照，可撤销；长期轨迹不会写入普通项目。","Selected vegetation snapshot applied; undo is available. Trajectory is not stored in a regular project.")
        case 16=>app.longTopDown = !app.longTopDown;for(view in app.longReplay.getOrThrow().views){view.dirty=true}
        case 0=>if(let Some(replay)<-app.longReplay){if(app.longTopDown){replay.camera.resetMap()}else{replay.camera.fitScene(replay.scenes[0],longArea(Layout(Float32(w.width),Float32(w.height)),0))};for(view in replay.views){view.dirty=true}}
        case 2=>app.view.showCanopy = !app.view.showCanopy
        case _=>()
    }
}
func handleLongInput(app:App,w:SdlWindow,record:UiEventRecord,l:Layout):Bool {
    match(record.event){
        case UiEvent.MouseMove(x,y)=>
            app.hover=l.hit(x,y,longMode:true)
            if(let Some(replay)<-app.longReplay){
                if(app.dragging){replay.camera.rotate(Float64(x-app.lastX),Float64(y-app.lastY));for(view in replay.views){view.dirty=true}}
                if(app.panning){if(app.longTopDown){replay.camera.panMap(Float64(x-app.lastX),Float64(y-app.lastY),app.mapPanWidth,app.mapPanHeight)}else{replay.camera.panX+=Float64(x-app.lastX);replay.camera.panY+=Float64(y-app.lastY)};for(view in replay.views){view.dirty=true}}
            };app.lastX=x;app.lastY=y
        case UiEvent.MouseDown(button,x,y)=>
            app.lastX=x;app.lastY=y
            match(button){
                case MouseButton.Left=>app.pressed=l.hit(x,y,longMode:true)
                    if(app.pressed<0){if(let Some(replay)<-app.longReplay){for(policy in 0..2){if(longSceneBox(l,policy,replay.base.aspect,app.longTopDown).contains(x,y)){app.longSelectedPolicy=policy}}}}
                case MouseButton.Right=>if(!app.longTopDown){for(policy in 0..2){if(longArea(l,policy).contains(x,y)){app.dragging=true}}}
                case MouseButton.Middle=>if(let Some(replay)<-app.longReplay){for(policy in 0..2){let box=longSceneBox(l,policy,replay.base.aspect,app.longTopDown);if(box.contains(x,y)){app.panning=true;app.mapPanWidth=Float64(box.w);app.mapPanHeight=Float64(box.h)}}}
                case _=>()
            }
        case UiEvent.MouseUp(button,x,y)=>match(button){
            case MouseButton.Left=>let id=app.pressed;app.pressed = -1;if(id>=0 && id==l.hit(x,y,longMode:true) && longEnabled(app,id)){app.action(w,id)}
            case MouseButton.Right=>app.dragging=false
            case MouseButton.Middle=>app.panning=false
            case _=>()
        }
        case UiEvent.MouseWheel(_,dy,x,y)=>if(let Some(replay)<-app.longReplay){for(policy in 0..2){let box=longSceneBox(l,policy,replay.base.aspect,app.longTopDown);if(box.contains(x,y)){if(app.longTopDown){replay.camera.scaleMap(Float64(dy),Float64((x-box.x)/box.w),Float64((y-box.y)/box.h))}else{replay.camera.scale(Float64(dy))};for(view in replay.views){view.dirty=true};break}}}
        case UiEvent.WindowFocusLost=>app.dragging=false;app.panning=false;app.pressed = -1;if(let Some(replay)<-app.longReplay){replay.playing=false}
        case UiEvent.KeyDown(key,repeat)=>if(!repeat){match(key){
            case Key.Escape=>app.openMenu()
            case Key.Tab=>
                var current:Int64=0;for(i in 0..LONG_CONTROLS.size){if(LONG_CONTROLS[i]==CONTROLS[app.focus]){current=i}}
                let delta=if(record.metadata.modifiers.shift){-1}else{1}
                for(offset in 1..LONG_CONTROLS.size+1){let at=(current+delta*offset+LONG_CONTROLS.size)%LONG_CONTROLS.size;let id=LONG_CONTROLS[at];if(longEnabled(app,id)){for(i in 0..CONTROLS.size){if(CONTROLS[i]==id){app.focus=i}};break}}
            case Key.Enter | Key.Space=>let id=CONTROLS[app.focus];if(LONG_CONTROLS.contains(id) && longEnabled(app,id)){app.action(w,id)}
            case Key.RawScancode(56)=>openTerminal(app,true);app.terminal.suppressSlash=true
            case _=>()
        }}
        case _=>()
    };return true
}
func prepareLong(app:App,w:SdlWindow,l:Layout,force:Bool):Unit {
    if(let Some(replay)<-app.longReplay){for(policy in 0..2){let view=replay.views[policy];view.useGpu=app.preferences.gpuEnabled;view.shadersEnabled=app.preferences.gpuEnabled && app.preferences.shadersEnabled;view.showCanopy=app.view.showCanopy;view.prepare(replay.camera,longSceneBox(l,policy,replay.base.aspect,app.longTopDown),w,topDown:app.longTopDown,forceFull:force,interacting:app.dragging || app.panning)}}
}
func drawLong(app:App,l:Layout):Unit {
    let r=app.assets.r;let chart=longChart(l);frame(r,l.canvas,dark:true)
    let blue=Color.rgb(95,210,241);let green=Color.rgb(179,232,106)
    studyText(app,app.t("DS参考扩展：慢驱动 / 快速整簇燃烧；不是SOC证明","DS-inspired: slow driving / fast cluster fires; not proof of SOC"),l.canvas.x+14.0,l.canvas.y+12.0,l.canvas.w-28.0)
    if(let Some(result)<-app.longResult){
        let replay=app.longReplay.getOrThrow();let colors=[blue,green]
        if(!app.longHistogram){
            for(i in 0..3){let y=chart.bottom()-Float32(i)*chart.h/2.0;r.strokeLine(chart.x,y,chart.right(),y,Pen(width:1.0,color:Color.rgb(78,85,74)));studyText(app,"${i*50}%",l.canvas.x+3.0,y-8.0,44.0)}
            let stride=max(1,(result.spec.drives+255)/256)
            for(policy in 0..2){var last=Point(chart.x,chart.bottom()-Float32(result.trace[policy][0])*chart.h);var at:Int64=stride
                while(at<result.spec.drives){let point=Point(chart.x+Float32(at)*chart.w/Float32(max(1,result.spec.drives-1)),chart.bottom()-Float32(result.trace[policy][at])*chart.h);r.strokeLine(last.x,last.y,point.x,point.y,Pen(width:2.0,color:colors[policy]));last=point;at+=stride}
            }
            let x=chart.x+Float32(replay.frame().drive)*chart.w/Float32(result.spec.drives);r.strokeLine(x,chart.y,x,chart.bottom(),Pen(width:1.0,color:Color.rgb(238,199,99)))
        }else{
            let bins=result.histogram[0].size;var maximum:Int64=0;for(policy in 0..2){for(n in result.histogram[policy]){maximum=max(maximum,n)}}
            for(bin in 0..bins){for(policy in 0..2){let width=chart.w/Float32(bins);let height=Float32(result.histogram[policy][bin])*chart.h/Float32(max(1,maximum));r.fill(Rect(chart.x+Float32(bin)*width+Float32(policy)*width*0.45,chart.bottom()-height,width*0.4,height),colors[policy])}
                if(bin%3==0){var size:Int64=1;for(_ in 0..bin){size*=2};studyText(app,"${size}",chart.x+Float32(bin)*chart.w/Float32(bins),chart.bottom()+3.0,40.0)}
            }
            studyText(app,app.t("箱高上限：","Max bin per 1000 rounds: ")+money(Float64(maximum)*1000.0/Float64(result.spec.drives*result.spec.samples)),chart.x,chart.y+2.0,chart.w)
        }
        studyText(app,if(app.longHistogram){app.t("全部seed：火灾规模log2分箱 / 按相同观测轮数计频次","All seeds: log2 fire-size bins / equal observation duration")}else{app.t("首seed覆盖轨迹 / 观测轮0–${result.spec.drives} / 蓝自然，绿抑制","First seed: cover over rounds 0-${result.spec.drives} / Blue natural, green suppression")},chart.x,chart.bottom()+20.0,chart.w)
        for(policy in 0..2){
            let area=longArea(l,policy);let label=if(policy==0){app.t("自然燃烧","Natural fire")}else{app.t("理想小火抑制","Ideal small-fire suppression")}
            studyText(app,label+app.t(" / 平均覆盖"," / Mean cover ")+money(result.meanDensity(policy)*100.0)+"%",area.x,chart.bottom()+44.0,area.w,color:colors[policy])
            studyText(app,app.t("最大${result.maximum(policy)}格 / 大火${result.sum(policy,1)}/${result.sum(policy,2)}雷击","Max ${result.maximum(policy)} cells / Large ${result.sum(policy,1)}/${result.sum(policy,2)} strikes"),area.x,chart.bottom()+66.0,area.w)
            studyText(app,app.t("燃烧${result.sum(policy,0)}格次 / 抑制${result.sum(policy,3)}次、${result.sum(policy,4)}格次","Burn ${result.sum(policy,0)} cell-events / Suppress ${result.sum(policy,3)} times, ${result.sum(policy,4)} cell-events"),area.x,chart.bottom()+88.0,area.w)
            let box=longSceneBox(l,policy,replay.base.aspect,app.longTopDown)
            if(app.longTopDown){drawMapPaperAt(app,Rect(box.x-6.0,box.y-6.0,box.w+12.0,box.h+12.0))}
            replay.views[policy].draw(box);if(app.longSelectedPolicy==policy){r.strokeRect(box,Pen(width:2.0,color:Color.rgb(238,199,99)))}
            drawLongFlames(app,replay,policy,box);drawLongLightning(app,replay,policy,box,app.clockNow)
        }
    }else{studyText(app,app.t("先运行长期对照；每轮共享生长机会与雷击，完成后回放。","Run paired driving first; both policies share growth and lightning events."),chart.x,chart.y+chart.h/2.0,chart.w)}
}
func drawLongPanel(app:App,l:Layout):Unit {
    let x=l.panel.x+18.0;let y=l.panel.y;uiText(app,l,app.t("长期演化 / DS参考","Long run / DS-inspired"),x,y+18.0)
    let info=if(let Some(job)<-app.longJob){let s=job.progress();"${s.completed}/${s.total}"}else if(let Some(replay)<-app.longReplay){app.t("回放${replay.cursor+1}/${replay.result.frames.size} / 观测轮${replay.frame().drive}","Frame ${replay.cursor+1}/${replay.result.frames.size} / Round ${replay.frame().drive}")}else{app.t("下列参数用于下一次实验","Settings below apply to the next run")}
    uiText(app,l,info,x,y+48.0)
    if(let Some(result)<-app.longResult){uiText(app,l,if(result.spec.samples>1){app.t("大火/轮配对差SE ","Paired large/round SE ")+money(result.pairedLargeSE())}else{app.t("单seed：无重复间标准误","One seed: no replicate SE")},x,y+68.0,color:Color.rgb(206,211,190))}
    for(id in [161,162,163,164,165,166,167,168,170,171,172,173,174,175,176,177]){
        let label=match(id){
            case 161=>app.t("生长","Grow ")+money(app.longGrowth*100.0)+"%"
            case 162=>app.t("落雷","Strike ")+money(app.longLightning*100.0)+"%"
            case 163=>app.t("预热${app.longWarmup}","Warm ${app.longWarmup}")
            case 164=>app.t("观测${app.longDrives}","Observe ${app.longDrives}")
            case 165=>app.t("${app.longSamples}个seed","${app.longSamples} seeds")
            case 166=>app.t("抑制≤${app.longCapacity}","Suppress<=${app.longCapacity}")
            case 167=>app.t("运行对照","Run")
            case 168=>app.t("取消任务","Cancel")
            case 170=>if(let Some(replay)<-app.longReplay){if(replay.playing){app.t("暂停回放","Pause")}else{app.t("播放回放","Play")}}else{app.t("播放回放","Play")}
            case 171=>app.t("单步回放","Step")
            case 172=>app.t("上一帧","Previous")
            case 173=>app.t("下一帧","Next")
            case 174=>app.t("导出数据","Export")
            case 175=>app.t("应用","Apply ")+if(app.longSelectedPolicy==0){app.t("自然组","natural")}else{app.t("抑制组","suppressed")}
            case 176=>if(app.longHistogram){app.t("切密度图","Density")}else{app.t("火灾分布","Fire sizes")}
            case _=>app.t("回放归零","Rewind")
        };mcButtonAt(app,l.control(id),id,label,CONTROLS[app.focus]==id,enabled:longEnabled(app,id))
    }
    mcButton(app,l,160,app.t("返回单次传播","Back to single fire"));mcButton(app,l,16,if(app.longTopDown){app.t("三维","3D")}else{app.t("地图","Map")});mcButton(app,l,0,app.t("复位","Reset"));mcButton(app,l,2,app.t("树冠","Canopy"))
}
