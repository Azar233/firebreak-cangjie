package firebreak

import sdl.*
import sdl.dialogs.*
import std.collection.ArrayList
import std.convert.*
import std.math.floor
import std.fs.{File,exists}
import stdx.encoding.base64.toBase64String

let CONTROLS=[0,1,2,3,4,5,6,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,30,31,32,33,34,35,36,40,41,42,43,44,45,46,47,48,49,50,51,52,54,53,60,61,62,63,64,65,66,67,70,71,72,73,74,75,76,77,78]
let TOOL_NAMES=["选择","林地","道路","水域","建筑","清理植被","隔离带","保护目标","禁止处理"]

class Layout {
    let width: Float32
    let height: Float32
    let canvas: Rect
    let panel: Rect
    let toolbar: Rect
    init(width: Float32,height: Float32) {
        this.width=width; this.height=height
        canvas=Rect(20.0,152.0,width-330.0,height-282.0)
        panel=Rect(width-294.0,152.0,274.0,height-282.0)
        toolbar=Rect(20.0+(canvas.w-546.0)/2.0,height-96.0,546.0,66.0)
    }
    func control(id: Int64): Rect {
        if (id>=70 && id<=78) {
            if (id<=75) { return Rect(panel.x+18.0+Float32((id-70)%2)*122.0,panel.y+180.0+Float32((id-70)/2)*52.0,116.0,44.0) }
            let row=match(id) { case 76=>0; case 78=>1; case _=>2 }
            return Rect(panel.x+18.0,panel.y+336.0+Float32(row)*52.0,238.0,44.0)
        }
        if (id==54) { return Rect(width-484.0,28.0,110.0,44.0) }
        if (id==53) { return Rect(width-366.0,28.0,110.0,44.0) }
        if (id==52) { return Rect(956.0,94.0,124.0,44.0) }
        if (id>=60) {
            if (id<=63) { return Rect(panel.x+18.0+Float32((id-60)%2)*122.0,panel.y+184.0+Float32((id-60)/2)*52.0,116.0,44.0) }
            let row=match(id) { case 64=>0; case 66=>1; case 65=>2; case _=>3 }
            return Rect(panel.x+18.0,panel.y+288.0+Float32(row)*52.0,238.0,44.0)
        }
        if (id==19) { return Rect(852.0,94.0,98.0,44.0) }
        if (id>=49 && id<=51) { return Rect(panel.x+18.0,panel.y+56.0+Float32(id-49)*76.0,238.0,44.0) }
        if (id>=40 && id<=45) {
            let row=if (id==40 || id==41) { 0 } else if (id==42 || id==45) { 1 } else { 2 }
            let column=if (id==40 || id==42 || id==43) { 0 } else { 1 }
            return Rect(panel.x+18.0+Float32(column)*122.0,panel.y+154.0+Float32(row)*52.0,116.0,44.0)
        }
        if (id>=46 && id<=48) { return Rect(panel.x+18.0,panel.y+310.0+Float32(id-46)*52.0,238.0,44.0) }
        if (id==18) { return Rect(748.0,94.0,98.0,44.0) }
        if (id>=20 && id<=28) { return Rect(toolbar.x+3.0+Float32(id-20)*60.0,toolbar.y+3.0,60.0,60.0) }
        if (id>=10 && id<=16) { return Rect(20.0+Float32(id-10)*104.0,94.0,98.0,44.0) }
        if (id>=33 && id<=36) { return Rect(panel.x+18.0,panel.y+56.0+Float32(id-33)*76.0,238.0,44.0) }
        return match (id) {
            case 0 => Rect(width-130.0,28.0,110.0,44.0)
            case 1 => Rect(width-248.0,28.0,110.0,44.0)
            case 2 => Rect(panel.x+18.0,panel.y+186.0,238.0,44.0)
            case 3 | 4 => Rect(panel.x+18.0+Float32(id-3)*122.0,panel.y+238.0,116.0,44.0)
            case 5 | 6 => Rect(panel.x+18.0+Float32(id-5)*122.0,panel.y+290.0,116.0,44.0)
            case 30 => Rect(panel.x+18.0,panel.y+342.0,238.0,44.0)
            case 31 | 32 => Rect(panel.x+18.0+Float32(id-31)*122.0,panel.y+394.0,116.0,44.0)
            case _ => Rect(panel.x+18.0,panel.y+446.0,238.0,44.0)
        }
    }
    func available(id: Int64,settings: Bool,simulation!: Bool=false,parameters!: Bool=false,comparison!: Bool=false,suggestions!: Bool=false): Bool {
        if (id==52 || id==53 || id==54) { return true }
        if (id>=70) { return suggestions }
        if (suggestions) { return id<=1 || (id>=10 && id<=16) || id==19 || id==52 }
        if (id>=60) { return comparison }
        if (comparison) { return id<=1 || (id>=10 && id<=16) || id==19 }
        if (id>=40) { return simulation && (if (id==48) { true } else if (id>=49) { parameters } else { !parameters }) }
        if (simulation && ((id>=2 && id<=6) || id==17 || (id>=30 && id<=36))) { return false }
        if (id>=33 && id<=36) { return settings }
        if (id>=2 && id<=6) { return !settings }
        return true
    }
    func hit(x: Float32,y: Float32,settings!: Bool=false,simulation!: Bool=false,parameters!: Bool=false,comparison!: Bool=false,suggestions!: Bool=false): Int64 {
        for (id in CONTROLS) { if (available(id,settings,simulation:simulation,parameters:parameters,comparison:comparison,suggestions:suggestions) && control(id).contains(x,y)) { return id } }; return -1
    }
}

class App {
    let scene=Scene()
    let work=Workbench()
    let camera=Camera()
    let assets: Assets
    let frameMeter=FrameMeter()
    let font: PixelFont
    let view: VoxelView
    let preferences: Preferences
    var menuOpen=false
    var bookPage: Int64=0
    var menuPage: Int64=0
    var menuFocus: Int64=80
    var exitReady=false
    var quitReturnMenu=false
    var quitReturnPage: Int64=0
    var quitReturnFocus: Int64=80
    var quitAfterSave=false
    let experiment=Experiment()
    let terminal=AgentTerminal()
    let agentSettings: DeepSeekSettings
    var agentConnection: ?AgentConnectionJob=None
    let agentModelEditor=TerminalEditor()
    let agentKeyEditor=TerminalEditor()
    var agentField: Int64= -1
    var agentOriginal=""
    var suggestPanel=false
    var searchJob: ?PlanSearchJob=None
    var searchResult: ?PlanSearchResult=None
    var candidateIndex: Int64=0
    var candidateVisible=false
    var comparePanel=false
    var sampleCount: Int64=16
    var evalJob: ?EvaluationJob=None
    var evalResult: ?EvaluationResult=None
    var pairView: ?ComparisonView=None
    var simPanel=false
    var simParameters=false
    var pickingIgnition=false
    var clockNow: UInt64=0
    var reference: ?Texture=None
    var mapMode=false
    var referenceMode=false
    var settings=false
    var erase=false
    var activeField: Int64 = -1
    var draft=""
    var tool: Int64 = 0
    var focus: Int64 = 0
    var hover: Int64 = -1
    var pressed: Int64 = -1
    var dragging=false
    var panning=false
    var mapPanWidth: Float64=1.0
    var mapPanHeight: Float64=1.0
    var painting=false
    var startCell: Int64 = -1
    var endCell: Int64 = -1
    var lastX: Float32=0.0
    var lastY: Float32=0.0
    var message=""
    var dialog: ?FileDialogRequest=None
    var dialogKind: Int64=0
    init(assets: Assets,preferencesPath!: String="") {
        preferences=Preferences(preferencesPath)
        agentSettings=DeepSeekSettings(if(preferencesPath.isEmpty()){""}else{"agent.local.json"})
        this.assets=assets; font=PixelFont(assets); view=VoxelView(scene,assets); syncScene()
        message=t("按 Esc 打开工作台菜单。","Press Esc to open the workbench menu.")
        if (!preferences.loadError.isEmpty()) { message=t("本地设置读取失败，已使用默认语言：","Could not load preferences; using default language: ")+preferences.loadError }
        if(agentSettings.loadError){message=t("智能体配置读取失败，请在菜单中重新填写。","Agent settings could not be loaded. Re-enter them in the menu.")}
    }
    func refreshExperimentView(): Unit {
        if (let Some(r) <- experiment.run) { view.setFireState(r.current().age,r.duration) }
        else { view.setFireState(Array<Int64>(CELL_COUNT,repeat:0),1) }
        view.setClusters(if (experiment.showConnectivity) { experiment.analysis.labels } else { Array<Int64>(CELL_COUNT,repeat:-1) })
        view.dirty=true
    }
    func updateExperiment(now: UInt64): Unit {
        clockNow=now; syncSuggestions(); pollSearch(); syncComparison(); pollEvaluation(now)
        if (experiment.sync(work.project,work.revision)) { refreshExperimentView() }
        if (let Some(r) <- experiment.run) { if (r.tick(now)) { refreshExperimentView() } }
    }
    func clearComparison(): Unit {
        if (let Some(v) <- pairView) { v.close() }; pairView=None; evalResult=None
    }
    func syncComparison(): Unit {
        if (let Some(job) <- evalJob) {
            if (job.revision!=work.revision) { job.cancel(); evalJob=None; message=t("场地或参数已修改，旧评估失效。","Site or parameters changed; previous results are invalid.") }
        }
        if (let Some(result) <- evalResult) { if (result.revision!=work.revision) { clearComparison() } }
    }
    func pollEvaluation(now: UInt64): Unit {
        if (let Some(job) <- evalJob) {
            let progress=job.progress()
            if (progress.done) {
                evalJob=None
                if (!progress.cancelled && job.revision==work.revision) {
                    if (let Some(result) <- progress.result) {
                        let replacement=ComparisonView(result,assets)
                        clearComparison(); evalResult=Some(result); pairView=Some(replacement)
                        message=t("${result.rows.size} 组配对评估完成；回放展示情景 1，汇总包含全部情景。","${result.rows.size} paired scenarios complete. Replay: scenario 1; summary: all scenarios.")
                    } else { message=t("评估失败：","Evaluation failed: ")+localizedError(progress.error,preferences.english) }
                }
            }
        }
        if (!menuOpen) { if (let Some(v) <- pairView) { v.tick(now) } }
    }
    func comparisonAction(id: Int64): Unit {
        require(startCell<0,t("请先应用或取消编辑预览","Apply or cancel the edit preview first"))
        match(id) {
            case 60 =>
                let job=EvaluationJob(work.project,work.revision,makeScenarios(work.project,sampleCount))
                if (let Some(old) <- evalJob) { old.cancel() }
                clearComparison(); evalJob=Some(job); job.start(); message=t("后台配对评估中；场地修改会使结果失效。","Evaluating in background. Site edits invalidate the results.")
            case 61 =>
                if (let Some(job) <- evalJob) { job.cancel(); evalJob=None }
                message=t("已取消评估；不发布或导出部分结果。","Evaluation cancelled. Partial results are not published.")
            case 66 => sampleCount=if (sampleCount==4) { 16 } else if (sampleCount==16) { 32 } else { 4 }
            case _ => if (let Some(v) <- pairView) {
                match(id) {
                    case 62=>v.seek(v.step-1)
                    case 63=>v.seek(v.step+1)
                    case 64=>if (v.playing) { v.playing=false } else { v.play(clockNow) }
                    case 67=>v.seek(v.maxStep)
                    case _=>()
                }
            }
        }
    }
    func simulationAction(id: Int64): Unit {
        require(startCell<0,t("请先应用或取消编辑预览","Apply or cancel the edit preview first"))
        if (experiment.sync(work.project,work.revision)) { refreshExperimentView() }
        match(id) {
            case 40 | 41 =>
                let r=experiment.run ?? experiment.create(work.project)
                if (id==41) { r.running=false; r.advance() }
                else if (r.running) { r.running=false } else { r.play(clockNow) }
                pickingIgnition=false; refreshExperimentView()
                message=t("同步四邻接传播；仿真步不代表现实秒数，单次结果不代表现实概率。","Synchronous four-neighbor spread. Steps are not seconds; results are not real-world probabilities.")
            case 42 => experiment.run=None; pickingIgnition=false; refreshExperimentView(); message=t("已重置试验；场地、处理方案与起火点均保留。","Trial reset. Site, treatment and ignition are preserved.")
            case 43 | 44 =>
                if (let Some(r) <- experiment.run) {
                    r.seek(max(0,min(r.snapshots.size-1,r.cursor+(if (id==43) { -1 } else { 1 })))); refreshExperimentView()
                }
            case 45 =>
                if (let Some(r) <- experiment.run) { r.running=false }
                pickingIgnition = !pickingIgnition
                message=if (pickingIgnition) { t("点击当前模式的可燃林地设置起火点；Esc 取消。","Click a fuel cell to set ignition; Esc cancels.") } else { t("已取消起火点选择。","Ignition selection cancelled.") }
            case 46 => experiment.showConnectivity = !experiment.showConnectivity; refreshExperimentView()
            case 47 =>
                experiment.planned = !experiment.planned; pickingIgnition=false; syncScene()
                message=t("已切换","Switched to ")+(if (experiment.planned) { t("处理方案","Treatment Plan") } else { t("原始场地","Baseline Site") })+t("；旧试验已失效。","; previous trial invalidated.")
            case 48 => simParameters = !simParameters
            case _ => ()
        }
    }
    func setIgnition(i: Int64): Unit {
        require(i>=0 && i<CELL_COUNT && work.project.fuel(i,planned:experiment.planned)>0.0,t("起火点必须位于当前模式的可燃林地","Ignition must be on fuel in the current mode"))
        let p=work.project.copy(); p.ignition=i; work.commit(p); pickingIgnition=false; syncScene()
        message=t("起火点 (${i%GRID_X}, ${i/GRID_X}) 已设置；可开始或单步运行。","Ignition set at (${i%GRID_X}, ${i/GRID_X}). Start or step to run.")
    }
    func syncScene(): Unit {
        experiment.sync(work.project,work.revision); refreshExperimentView()
        populateScene(scene,work.project,experiment.planned); view.dirty=true
        syncComparison(); syncSuggestions()
    }
    func makeReference(p: Project): ?Texture {
        var next: ?Texture=None
        if (let Some(s) <- decodeReference(p)) {
            try { next=Some(assets.r.textureFromSurface(s)) } finally { s.close() }
        }
        return next
    }
    func replaceReference(next: ?Texture): Unit {
        if (let Some(t) <- reference) { t.close() }; reference=next
    }
    func refreshReference(): Unit { replaceReference(makeReference(work.project)) }
    func loadProject(path: String): Unit {
        let p=readProjectText(String.fromUtf8(File.readFrom(path)))
        let next=makeReference(p)
        work.acceptLoaded(p,path); replaceReference(next); cancel();camera.resetMap(); syncScene(); mapMode=reference.isSome(); referenceMode=false
    }
    func mapBox(l: Layout): Rect {
        // Keep 32 logical pixels of original-map parchment around the editable content,
        // plus 16 pixels between the paper and the viewport boundary.
        let a=Float32(work.project.aspect); let w=min(l.canvas.w-96.0,(l.canvas.h-96.0)*a); let h=w/a
        return Rect(l.canvas.centerX()-w/2.0,l.canvas.centerY()-h/2.0,w,h)
    }
    func mapPaperBox(l: Layout): Rect {
        let b=mapBox(l); return Rect(b.x-32.0,b.y-32.0,b.w+64.0,b.h+64.0)
    }
    func mapWorldBox(l: Layout): Rect {camera.mapWorldBox(mapBox(l))}
    func mapInputBox(l: Layout,x: Float32,y: Float32): ?Rect {
        if(comparePanel){
            if(let Some(v)<-pairView){for(right in [false,true]){let b=fittedMap(compareBox(l.canvas,right),v.aspect);if(b.contains(x,y)){return Some(b)}}}
            return None
        }
        let b=mapBox(l);return if(b.contains(x,y)){Some(b)}else{None}
    }
    func cellAt(x: Float32,y: Float32,l: Layout): Int64 {
        if (!l.canvas.contains(x,y)) { return -1 }
        if (mapMode) {
            let b=mapBox(l); if (!b.contains(x,y)) { return -1 }
            if (let Some(h) <- trace(scene,overheadRay(scene,camera.mapU(Float64((x-b.x)/b.w)),camera.mapV(Float64((y-b.y)/b.h))),groundOnly:true)) { return h.z*GRID_X+h.x }
            return -1
        }
        if (let Some(h) <- trace(scene,camera.ray(Float64(x),Float64(y),l.canvas),groundOnly:true)) { return h.z*GRID_X+h.x }
        return -1
    }
    func selection(): Array<Int64> {
        let cells=ArrayList<Int64>()
        if (startCell<0 || endCell<0) { return cells.toArray() }
        let x0=min(startCell%GRID_X,endCell%GRID_X); let x1=max(startCell%GRID_X,endCell%GRID_X)
        let z0=min(startCell/GRID_X,endCell/GRID_X); let z1=max(startCell/GRID_X,endCell/GRID_X)
        for (z in z0..z1+1) { for (x in x0..x1+1) { cells.add(z*GRID_X+x) } }; return cells.toArray()
    }
    func previewText(): String {
        let p=work.project; let cells=selection(); let mask=p.treatment.clone()
        var blocked=false
        for (i in cells) {
            if (tool==5 || tool==6) {
                if (!erase && (p.targets[i]!=0 || p.forbidden[i]!=0)) { blocked=true }
                if (erase) { mask[i]=0 } else if (p.land[i]==1) { mask[i]=tool-4 }
            } else { mask[i]=0 }
        }
        if (blocked) { return t("含保护目标或禁区：整笔不可应用","Protected / forbidden cells: stroke cannot be applied") }
        if (p.metersWide<=0.0) { return t("未标定：无法核算平方米和处理费用","Uncalibrated: area and cost unavailable") }
        var cost=0.0
        for (v in mask) { cost+=if (v==1) { p.clearingPrice } else if (v==2) { p.breakPrice } else { 0.0 } }
        cost*=p.cellArea()
        return t("选区 ${money(Float64(cells.size)*p.cellArea())} 平方米 | 方案 ￥${money(cost)}","Selected ${money(Float64(cells.size)*p.cellArea())} m2 | Plan CNY ${money(cost)}")+(if (cost>p.budget) { t(" / 超预算"," / Over budget") } else { t(" / 预算内"," / Within budget") })
    }
    func cancel(): Unit { painting=false; startCell = -1; endCell = -1; pressed = -1; activeField = -1; dragging=false; panning=false }
    func commitStroke(): Unit {
        require(startCell>=0 && !painting,t("请先拖动选区并松开鼠标","Drag a selection and release the mouse first"))
        let changed=work.apply(selection(),tool,erase)
        cancel(); if (changed) { syncScene() }; message=if (changed) { t("已应用；整笔操作可撤销。","Applied. Undo restores the entire stroke.") } else { t("选区没有需要更改的格子。","No cells need changing.") }
    }
    func fieldValue(id: Int64): Float64 {
        let p=work.project
        return match(id) { case 33=>p.metersWide; case 34=>p.budget; case 35=>p.clearingPrice; case 36=>p.breakPrice
            case 49=>p.spreadProbability; case 50=>Float64(p.burnSteps); case _=>Float64(p.seed) }
    }
    func commitField(): Unit {
        if (activeField<0) { return }
        let value=Float64.parse(draft); let p=work.project.copy()
        match(activeField) {
            case 33=>p.metersWide=value; case 34=>p.budget=value; case 35=>p.clearingPrice=value; case 36=>p.breakPrice=value
            case 49=>p.spreadProbability=value
            case 50 | 51 =>
                require(!value.isNaN() && !value.isInf() && value>=0.0 && value<=2147483647.0 && floor(value)==value,t("请输入范围内的整数","Enter an integer within the allowed range"))
                if (activeField==50) { p.burnSteps=Int64(value) } else { p.seed=Int64(value) }
            case _=>()
        }
        work.commit(p); activeField = -1; updateExperiment(clockNow); message=t("参数已更新；旧试验失效，预算约束已重新校验。","Parameters updated; old results invalidated and budget rechecked.")
    }
    func activate(id: Int64): Unit {
        if ((id>=33 && id<=36) || (id>=49 && id<=51)) {
            commitField(); activeField=id; draft="${fieldValue(id)}"; message=t("输入数值，Enter 确认，Esc 取消；Backspace 删除。","Enter a number; Enter confirms, Esc cancels, Backspace deletes."); return
        }
        commitField()
        if (id>=70) { suggestionAction(id); return }
        if (id>=60) { comparisonAction(id); return }
        if (id>=40 && id<=48) { simulationAction(id); return }
        if (id>=20 && id<=28) { cancel(); pickingIgnition=false; tool=id-20; message=t("工具：","Tool: ")+toolName(tool)+t("；拖动预览，再确认应用。","; drag to preview, then apply."); return }
        match (id) {
            case 0 => if(mapMode){camera.resetMap()}else{camera.reset()}; message=t("相机已复位。","Camera reset.")
            case 1 => camera.pitch=1.5707963267948966; mapMode=false; message=t("俯视编辑。","Overhead editing view.")
            case 2 => view.showCanopy = !view.showCanopy
            case 3 => camera.rotate(-20.0,0.0)
            case 4 => camera.rotate(20.0,0.0)
            case 5 => if(mapMode){camera.scaleMap(1.0,0.5,0.5)}else{camera.scale(1.0)}
            case 6 => if(mapMode){camera.scaleMap(-1.0,0.5,0.5)}else{camera.scale(-1.0)}
            case 14 | 15 =>
                let from=if (id==14) { work.undo } else { work.redo }
                if (!from.isEmpty()) {
                    let next=makeReference(readProjectText(from[from.size-1]))
                    cancel(); work.history(id==14); replaceReference(next); syncScene()
                    message=if (id==14) { t("已撤销。","Undone.") } else { t("已重做。","Redone.") }
                }
            case 16 => cancel(); mapMode = !mapMode
            case 17 => settings = !settings
            case 18 =>
                if (reference.isNone()) { message=t("请先导入底图；二维地图已使用三维场景的纹理俯视。","Import a reference image first. The map already uses actual voxel textures."); return }
                cancel(); referenceMode = if (mapMode) { !referenceMode } else { true }; mapMode=true
            case 19 => cancel(); pickingIgnition=false; suggestPanel=false; comparePanel=false; simPanel = !simPanel; simParameters=false
            case 53 => openMenu()
            case 52 =>
                require(startCell<0,t("请先应用或取消编辑预览","Apply or cancel the edit preview first"))
                cancel(); pickingIgnition=false; suggestPanel=false; comparePanel = !comparePanel; simPanel=false; referenceMode=false
                if (let Some(r) <- experiment.run) { r.running=false }
                message=t("同情景对比 / 无风规则 v1；样本比例不代表现实火灾概率。","Paired scenarios / no-wind rule v1. Sample rates are not real-world probabilities.")
            case 30 => cancel(); erase = !erase; message=t("擦除模式：地类恢复空地，标记或处理带移除。","Erase: clear land, markers or treatment strips.")
            case 31 => commitStroke()
            case 32 => cancel(); message=t("已取消预览。","Preview cancelled.")
            case _ => ()
        }
        view.dirty=true
    }
    func select(x: Float32,y: Float32,l: Layout): Unit {
        let i=cellAt(x,y,l)
        view.selectedX=if (i>=0) { i%GRID_X } else { -1 }; view.selectedZ=if (i>=0) { i/GRID_X } else { -1 }; view.dirty=true
        if (i>=0) {
            let p=work.project
            message=t("格 (${i%GRID_X}, ${i/GRID_X})：","Cell (${i%GRID_X}, ${i/GRID_X}): ")+landName(p.land[i])+t("；相对可燃量 ${p.fuel(i)} / 方案 ${p.fuel(i,planned:true)}","; relative fuel ${p.fuel(i)} / planned ${p.fuel(i,planned:true)}")
        } else { message=t("当前位置没有地面。","No ground at this position.") }
    }
    func discard(window: SdlWindow): Bool {
        if (!work.dirty() && startCell<0 && activeField<0) { return true }
        var opts=MessageBoxOptions(t("未保存更改","Unsaved Changes"),t("当前项目或预览尚未保存。是否放弃并继续？","Your project or preview is unsaved. Discard changes and continue?"))
        opts.kind=MessageBoxKind.Warning
        opts.buttons=[MessageBoxButton(t("取消","Cancel"),id:0,returnKeyDefault:true,escapeKeyDefault:true),MessageBoxButton(t("放弃更改","Discard Changes"),id:1)]
        return showMessageBox(opts,window:Some(window))==1
    }
    func requestFile(window: SdlWindow,kind: Int64): Unit {
        require(dialog.isNone(),t("请先完成文件对话框","Finish the file dialog first"))
        commitField(); require(startCell<0,t("请先应用或取消选区","Apply or cancel the selection first"))
        dialogKind=kind
        if (kind==65 || kind==78) {
            if (kind==78) { syncSuggestions(); require(searchResult.isSome(),t("请先完成候选搜索","Complete candidate search first")) }
            else { syncComparison(); require(evalResult.isSome(),t("请先完成当前场地的评估","Complete evaluation of the current site first")) }
            dialog=Some(FileDialogs.openFolder(options:FileDialogOptions(),window:Some(window))); return
        }
        let filter=if (kind==13) { FileDialogFilter(t("底图 PNG / JPEG","Reference PNG / JPEG"),"png;jpg;jpeg") } else { FileDialogFilter(t("断火线项目","Firebreak Project"),"firebreak") }
        let options=FileDialogOptions(filters:[filter])
        dialog=Some(if (kind==12) { FileDialogs.saveFile(options:options,window:Some(window)) } else { FileDialogs.openFile(options:options,window:Some(window)) })
    }
    func importImage(path: String): Unit {
        let bytes=File.readFrom(path); require(bytes.size<=8000000,t("底图上限 8 MB","Reference image limit: 8 MB"))
        let p=Project(demo:false); p.image=toBase64String(bytes); p.source=t("用户导入底图","Imported reference"); p.metersWide=0.0
        try (s=Surface.loadBytes(bytes,options:ImageLoadOptions(maxPixels:16000000))) { p.aspect=Float64(s.size().w)/Float64(s.size().h) }
        p.validate()
        // Decode/upload before changing the document so a failed import keeps the current project.
        let s=decodeReference(p).getOrThrow()
        let texture=try { assets.r.textureFromSurface(s) } finally { s.close() }
        work.commit(p); work.path=""; if (let Some(old) <- reference) { old.close() }; reference=Some(texture)
        cancel();camera.resetMap(); syncScene(); mapMode=true; referenceMode=true; settings=true; message=t("底图已导入；请标定宽度并标注。点击纹理俯视查看三维场景的正上方。","Reference imported. Set its width and annotate. Switch to the textured map for an overhead view.")
    }
    func pollFile(window: SdlWindow): Unit {
        if (let Some(request) <- dialog) {
            match(request.result()) {
                case FileDialogResult.FileDialogPending => ()
                case FileDialogResult.FileDialogCanceled => dialog=None; quitAfterSave=false
                case FileDialogResult.FileDialogFailed(error) => dialog=None; quitAfterSave=false; message=t("文件对话框失败：","File dialog failed: ")+localizedError(error,preferences.english)
                case FileDialogResult.FileDialogSelected(paths,_) =>
                    dialog=None; if (paths.isEmpty()) { quitAfterSave=false; return }
                    try {
                        if (dialogKind==78) {
                            syncSuggestions(); let result=searchResult.getOrThrow()
                            message=t("候选报告已导出：","Candidate report exported: ")+exportSearch(result,paths[0],preferences.english)
                        } else if (dialogKind==65) {
                            syncComparison(); let result=evalResult.getOrThrow()
                            message=t("报告已导出：","Report exported: ")+exportEvaluation(result,assets,paths[0],english:preferences.english)
                        } else if (dialogKind==12) {
                            var path=paths[0]; if (!path.endsWith(".firebreak")) { path+=".firebreak" }
                            if (exists(path) && path!=work.path) {
                                var opts=MessageBoxOptions(t("覆盖项目","Replace Project"),t("所选项目已存在，是否替换？","This project already exists. Replace it?"))
                                opts.buttons=[MessageBoxButton(t("取消","Cancel"),id:0,returnKeyDefault:true,escapeKeyDefault:true),MessageBoxButton(t("替换","Replace"),id:1)]
                                if (showMessageBox(opts,window:Some(window))!=1) { quitAfterSave=false; return }
                            }
                            work.save(path); message=t("项目已安全保存。","Project saved safely."); exitReady=quitAfterSave; quitAfterSave=false
                        } else if (discard(window)) {
                            if (dialogKind==13) { importImage(paths[0]) }
                            else { loadProject(paths[0]); message=t("项目已读取。","Project loaded.") }
                        }
                    } catch(e: Exception) { quitAfterSave=false; message=t("操作失败：","Operation failed: ")+localizedError(e.message,preferences.english) }
            }
        }
    }
    func action(window: SdlWindow,id: Int64): Unit {
        if(id==54){openTerminal(this,false);return}
        if (id==10) {
            if (discard(window)) { cancel();camera.resetMap(); work.commit(Project()); work.path=""; work.unsaved=true; refreshReference(); syncScene(); message=t("已建立示例；请另存项目。","Demo created. Save it as a new project.") }
        } else if (id==65 || id==78) { requestFile(window,id) } else if (id>=11 && id<=13) { requestFile(window,id) } else { activate(id) }
    }
    func handle(window: SdlWindow,record: UiEventRecord): Bool {
        clockNow=window.ticks()
        try { return handleInput(window,record) } catch(e: Exception) { painting=false; message=t("操作未应用：","Action not applied: ")+localizedError(e.message,preferences.english); return true }
    }
    func handleInput(window: SdlWindow,record: UiEventRecord): Bool {
        let l=Layout(Float32(window.width),Float32(window.height))
        match (record.event) {
            case UiEvent.Quit | UiEvent.WindowCloseRequested => requestExit(); return !exitReady
            case UiEvent.WindowResized(_,_) | UiEvent.WindowDisplayScaleChanged =>
                window.refreshSize()
                if (window.width<1100 || window.height<780) { window.setSize(max(1100,window.width),max(780,window.height)) }; view.dirty=true; return true
            case _=>()
        }
        if (menuOpen) { return handleMenu(window,record,l) }
        if (terminal.open) { return handleTerminalInput(this,record,l) }
        match (record.event) {
            case UiEvent.MouseMove(x,y) =>
                hover=l.hit(x,y,settings:settings,simulation:simPanel,parameters:simParameters,comparison:comparePanel,suggestions:suggestPanel)
                if (painting) { let i=cellAt(x,y,l); if (i>=0) { endCell=i } }
                if (dragging) { camera.rotate(Float64(x-lastX),Float64(y-lastY)); view.dirty=true }
                if (panning) { if(mapMode){camera.panMap(Float64(x-lastX),Float64(y-lastY),mapPanWidth,mapPanHeight)}else{camera.panX+=Float64(x-lastX); camera.panY+=Float64(y-lastY)}; view.dirty=true }
                lastX=x; lastY=y
            case UiEvent.MouseDown(button,x,y) =>
                lastX=x; lastY=y
                match (button) {
                    case MouseButton.Left => pressed=l.hit(x,y,settings:settings,simulation:simPanel,parameters:simParameters,comparison:comparePanel,suggestions:suggestPanel)
                        if (pressed>=0) { for (i in 0..CONTROLS.size) { if (CONTROLS[i]==pressed) { focus=i } } }
                        else if (!comparePanel && !suggestPanel && l.canvas.contains(x,y)) {
                            commitField()
                            if (pickingIgnition) { setIgnition(cellAt(x,y,l)); return true }
                            select(x,y,l)
                            if (tool!=0) { if (let Some(r) <- experiment.run) { r.running=false } }
                            if (tool!=0 && startCell<0) { startCell=cellAt(x,y,l); endCell=startCell; painting=startCell>=0 }
                        }
                    case MouseButton.Right => dragging = !mapMode && startCell<0 && l.canvas.contains(x,y)
                    case MouseButton.Middle =>
                        panning=false
                        if(startCell<0){
                            if(mapMode){if(let Some(b)<-mapInputBox(l,x,y)){panning=true;mapPanWidth=Float64(b.w);mapPanHeight=Float64(b.h)}}
                            else{panning=l.canvas.contains(x,y)}
                        }
                    case _ => ()
                }
            case UiEvent.MouseUp(button,x,y) =>
                match (button) {
                    case MouseButton.Left =>
                        if (painting) { painting=false; message=t("选区 ${selection().size} 格；确认应用 / Enter，取消 / Esc。","${selection().size} cells selected; Enter applies, Esc cancels.") }
                        else if (pressed>=0 && pressed==l.hit(x,y,settings:settings,simulation:simPanel,parameters:simParameters,comparison:comparePanel,suggestions:suggestPanel)) { action(window,pressed) }; pressed = -1
                    case MouseButton.Right => dragging=false
                    case MouseButton.Middle => panning=false
                    case _ => ()
                }
            case UiEvent.MouseWheel(_,dy,x,y) => if (startCell<0 && !panning && l.canvas.contains(x,y)) {
                if(mapMode){if(let Some(b)<-mapInputBox(l,x,y)){camera.scaleMap(Float64(dy),Float64((x-b.x)/b.w),Float64((y-b.y)/b.h));view.dirty=true}}
                else{camera.scale(Float64(dy));view.dirty=true}
            }
            case UiEvent.WindowFocusLost =>
                if (let Some(r) <- experiment.run) { r.running=false }
                if (let Some(v) <- pairView) { v.playing=false }
                if (painting) { startCell = -1; endCell = -1 }; painting=false; dragging=false; panning=false; pressed = -1
            case UiEvent.DropFile(path,_,_) => if (discard(window)) { importImage(path) }
            case UiEvent.TextInput(text) => if (activeField>=0 && draft.size+text.size<=24) {
                var valid=true; for (ch in text.toArray()) { if (!(ch>=48 && ch<=57) && ch!=46) { valid=false } }; if (valid) { draft+=text }
            }
            case UiEvent.KeyDown(key,repeat) =>
                if (activeField>=0) {
                    match(key) {
                        case Key.Escape => activeField = -1
                        case Key.Enter => commitField()
                        case Key.Backspace => if (!draft.isEmpty()) { draft=draft[..draft.size-1] }
                        case Key.Letter(65) => if (record.metadata.modifiers.ctrl) { draft="" }
                        case _ => ()
                    }; return true
                }
                if (record.metadata.modifiers.ctrl && !repeat) {
                    match(key) {
                        case Key.Letter(83) => if (work.path.isEmpty() || record.metadata.modifiers.shift) { requestFile(window,12) } else { require(startCell<0,t("请先应用或取消选区","Apply or cancel the selection first")); work.save(work.path); message=t("项目已保存。","Project saved.") }; return true
                        case Key.Letter(79) => requestFile(window,11); return true
                        case Key.Letter(90) => activate(if (record.metadata.modifiers.shift) { 15 } else { 14 }); return true
                        case Key.Letter(89) => activate(15); return true
                        case _ => ()
                    }
                }
                match (key) {
                    case Key.Tab => if (!repeat) {
                        let step=if (record.metadata.modifiers.shift) { CONTROLS.size-1 } else { 1 }
                        for (_ in 0..CONTROLS.size) { focus=(focus+step)%CONTROLS.size; if (l.available(CONTROLS[focus],settings,simulation:simPanel,parameters:simParameters,comparison:comparePanel,suggestions:suggestPanel)) { break } }
                    }
                    case Key.Enter => if (!repeat) { if (startCell>=0) { commitStroke() } else if (l.available(CONTROLS[focus],settings,simulation:simPanel,parameters:simParameters,comparison:comparePanel,suggestions:suggestPanel)) { action(window,CONTROLS[focus]) } }
                    case Key.Space => if (!repeat && l.available(CONTROLS[focus],settings,simulation:simPanel,parameters:simParameters,comparison:comparePanel,suggestions:suggestPanel)) { action(window,CONTROLS[focus]) }
                    case Key.Home => activate(0)
                    case Key.Letter(84) => activate(1)
                    case Key.Letter(72) => activate(2)
                    case Key.Digit(n) => if (!comparePanel && !suggestPanel && n>=49 && n<=57) { activate(20+Int64(n-49)) }
                    case Key.Left => camera.rotate(-8.0,0.0); view.dirty=true
                    case Key.Right => camera.rotate(8.0,0.0); view.dirty=true
                    case Key.Up => camera.rotate(0.0,8.0); view.dirty=true
                    case Key.Down => camera.rotate(0.0,-8.0); view.dirty=true
                    case Key.Letter(87) => camera.panY-=12.0; view.dirty=true
                    case Key.Letter(83) => camera.panY+=12.0; view.dirty=true
                    case Key.Letter(65) => camera.panX-=12.0; view.dirty=true
                    case Key.Letter(68) => camera.panX+=12.0; view.dirty=true
                    case Key.PageUp => activate(5)
                    case Key.PageDown => activate(6)
                    case Key.RawScancode(56) => if(!repeat && !record.metadata.modifiers.shift){openTerminal(this,true);terminal.suppressSlash=true}
                    case Key.Escape => if (!repeat) { if (startCell>=0 || pickingIgnition) { cancel(); pickingIgnition=false; message=t("已取消当前操作。","Current action cancelled.") } else { openMenu() } }
                    case _ => ()
                }
            case _ => ()
        }
        return true
    }

    func openSuggestions(): Unit {
        require(startCell<0,t("请先应用或取消编辑预览","Apply or cancel the edit preview first"))
        commitField(); suggestPanel=true; comparePanel=false; simPanel=false; settings=false; referenceMode=false; pickingIgnition=false
        if (let Some(run) <- experiment.run) { run.running=false }
        if (let Some(pair) <- pairView) { pair.playing=false }
        experiment.planned=true; experiment.run=None; experiment.showConnectivity=false; syncScene()
        message=t("有限候选 / 训练 8 组 + 留出复核 8 组；不保证全局最优。","Finite candidates / 8 training + 8 holdout scenarios; no global-optimum guarantee.")
    }
    func syncSuggestions(): Unit {
        if (let Some(job) <- searchJob) {
            if (job.revision!=work.revision) { job.cancel(); searchJob=None; message=t("输入已修改，旧候选搜索失效。","Inputs changed; old candidate search invalidated.") }
        }
        if (let Some(result) <- searchResult) { if (result.revision!=work.revision) { searchResult=None; candidateVisible=false; candidateIndex=0 } }
    }
    func pollSearch(): Unit {
        if (let Some(job) <- searchJob) {
            let state=job.progress()
            if (state.done) {
                searchJob=None
                if (!state.cancelled && job.revision==work.revision) {
                    if (let Some(result) <- state.result) {
                        searchResult=Some(result); candidateIndex=max(0,result.selected); candidateVisible=false
                        message=if (result.entries.isEmpty()) { t("预算、禁区和当前几何候选内没有可行新增处理带。","No feasible additional strip within budget, exclusions and this candidate family.") }
                            else if (result.recommended<0) { t("没有通过训练与留出复核的自动推荐；可检查全部候选。","No automatic recommendation passed training and holdout checks. Inspect all candidates.") }
                            else { t("候选完成；先预览，再由你手动应用。","Candidates complete. Preview, then apply manually.") }
                    } else { message=t("候选搜索失败：","Candidate search failed: ")+localizedError(state.error,preferences.english) }
                }
            }
        }
    }
    func selectedEntry(): PlanEntry {
        syncSuggestions(); let result=searchResult.getOrThrow()
        require(candidateIndex>=0 && candidateIndex<result.entries.size,t("没有可查看的候选","No candidate available")); return result.entries[candidateIndex]
    }
    func suggestionAction(id: Int64): Unit {
        require(startCell<0,t("请先应用或取消编辑预览","Apply or cancel the edit preview first"))
        syncSuggestions()
        match(id) {
            case 70=>
                let job=PlanSearchJob(work.project,work.revision)
                if (let Some(old) <- searchJob) { old.cancel() }
                searchResult=None; candidateVisible=false; searchJob=Some(job); job.start()
                message=t("后台生成和评估候选；现有方案不会被修改。","Generating and evaluating candidates in background; current plan stays unchanged.")
            case 71=>if (let Some(job) <- searchJob) { job.cancel(); searchJob=None; message=t("已取消候选搜索，不发布部分结果。","Candidate search cancelled; partial results are not published.") }
            case 72 | 73=>
                let result=searchResult.getOrThrow(); require(!result.entries.isEmpty(),t("没有可查看的候选","No candidate available"))
                candidateIndex=(candidateIndex+result.entries.size+(if (id==72) { -1 } else { 1 }))%result.entries.size
            case 74=>selectedEntry(); candidateVisible = !candidateVisible
            case 75=>
                let entry=selectedEntry(); let result=searchResult.getOrThrow()
                require(candidateVisible,t("请先预览当前候选，再应用","Preview the candidate before applying"))
                let next=entry.candidate.project(readProjectText(result.source)); work.commit(next); syncScene()
                message=t("已应用候选；可撤销，也可继续手工编辑。","Candidate applied. Undo or edit it manually.")
            case 76=>
                let entry=selectedEntry(); let result=searchResult.getOrThrow(); let next=entry.candidate.project(readProjectText(result.source))
                let job=EvaluationJob(next,work.revision,reviewScenarios(next,8),candidatePreview:true)
                if (let Some(old) <- evalJob) { old.cancel() }
                clearComparison(); evalJob=Some(job); job.start(); suggestPanel=false; comparePanel=true; referenceMode=false
                message=t("候选留出情景对照（未应用）；基线仍为原始场地。","Holdout comparison of unapplied candidate; baseline is the original site.")
            case 77=>suggestPanel=false; candidateVisible=false
            case _=>()
        }
    }
    func t(zh: String,en: String): String { preferences.text(zh,en) }
    func toolName(index: Int64): String {
        let names=["Select","Forest","Road","Water","Building","Clear Vegetation","Firebreak","Protect Target","No Treatment"]
        return t(TOOL_NAMES[index],names[index])
    }
    func landName(index: Int64): String {
        return t(LAND_NAMES[index],["Empty","Forest","Road","Water","Building"][index])
    }
    func openMenu(): Unit {
        menuOpen=true; menuPage=0; menuFocus=80; hover = -1; pressed = -1
        dragging=false; panning=false; painting=false
        if (let Some(run) <- experiment.run) { run.running=false }
        if (let Some(pair) <- pairView) { pair.playing=false }
    }
    func requestExit(): Unit {
        if (dialog.isSome()) { message=t("请先完成文件对话框。","Finish the file dialog first."); return }
        if (!work.dirty() && startCell<0 && activeField<0) { exitReady=true; return }
        if (menuOpen && menuPage==5) { return }
        quitReturnMenu=menuOpen; quitReturnPage=menuPage; quitReturnFocus=menuFocus
        if (!menuOpen) { openMenu() }
        menuPage=5; menuFocus=95; pressed = -1
    }
    func menuEnabled(id: Int64): Bool {
        if (dialog.isSome()) { return false }
        if(id==107){return agentConnection.isNone()}
        if (id==102) { return preferences.gpuEnabled && view.gpuError.isEmpty() }
        if (id==96) { return bookPage>0 }
        if (id==97) { return bookPage<BOOK_PAGES-1 }
        return id!=93 || (startCell<0 && activeField<0)
    }
    func closeMenu(): Unit {
        commitField(); menuOpen=false; hover = -1; pressed = -1
    }
    func saveFromMenu(window: SdlWindow,exitAfter: Bool): Unit {
        require(startCell<0 && activeField<0,t("请先完成或取消预览及输入。","Finish or cancel pending edits first."))
        if (work.path.isEmpty()) { requestFile(window,12); quitAfterSave=exitAfter }
        else { work.save(work.path); exitReady=exitAfter; message=t("项目已保存。","Project saved.") }
    }
    func menuAction(window: SdlWindow,id: Int64): Unit {
        if (!menuEnabled(id)) { return }
        match(id) {
            case 80=>closeMenu()
            case 81 | 82 | 83 | 84=>commitField(); menuPage=id-80; menuFocus=MenuLayout(Layout(Float32(window.width),Float32(window.height))).controls(menuPage)[0];if(id==84){openAgentSettings(this)}
            case 104 | 105=>agentField=id;agentOriginal=agentEditor(this).text;window.setTextInputArea(MenuLayout(Layout(Float32(window.width),Float32(window.height))).box(id,page:4))
            case 106=>
                try{agentSettings.save(agentModelEditor.text,agentKeyEditor.text);agentField = -1;message=t("DeepSeek 配置已保存；尚未进行连接验证。","DeepSeek settings saved; connection has not been verified.")}
                catch(_:Exception){message=t("保存失败，请检查模型名、API Key 格式或本地文件权限。","Save failed. Check the model name, key format and local file access.")}
            case 107=>
                try{
                    require(!agentKeyEditor.text.isEmpty(),"Missing API key")
                    agentSettings.save(agentModelEditor.text,agentKeyEditor.text);agentField = -1
                    let job=AgentConnectionJob(agentSettings.generation,agentSettings.model,agentSettings.apiKey)
                    agentConnection=Some(job);agentSettings.connectionState=1;job.start()
                    message=t("正在验证 DeepSeek API 与模型；此检测不生成对话。","Checking DeepSeek API/model; this probe does not generate a conversation.")
                }catch(_:Exception){message=t("请检查 API Key、模型名称与本地文件权限。","Check the API key, model name and local file access.")}
            case 85=>
                preferences.setEnglish(!preferences.english)
                window.setTitle(t("断火线 · 场地规划工作台","Firebreak - Site Planning Workbench"))
                message=t("语言已切换为简体中文。","Language changed to English.")
            case 86=>saveFromMenu(window,false)
            case 87=>requestExit()
            case 88=>commitField(); menuPage=0; menuFocus=80
            case 90=>view.showCanopy = !view.showCanopy; view.dirty=true
            case 91=>mapMode = !mapMode; referenceMode=false; view.dirty=true
            case 92=>if(mapMode){camera.resetMap()}else{camera.reset()}; view.dirty=true
            case 100=>preferences.setShowFps(!preferences.showFps)
            case 101=>preferences.setGpu(!preferences.gpuEnabled);view.gpuError="";view.dirty=true
            case 102=>preferences.setShaders(!preferences.shadersEnabled);view.dirty=true
            case 93=>saveFromMenu(window,true)
            case 94=>exitReady=true
            case 95=>menuOpen=quitReturnMenu; menuPage=quitReturnPage; menuFocus=quitReturnFocus
            case 96=>bookPage--; menuFocus=if (bookPage==0) { 97 } else { 96 }
            case 97=>bookPage++; menuFocus=if (bookPage==BOOK_PAGES-1) { 96 } else { 97 }
            case 99=>openSuggestions(); menuOpen=false
            case 98=>menuPage=6; menuFocus=if (bookPage<BOOK_PAGES-1) { 97 } else { 96 }
            case _=>if ((id>=33 && id<=36) || (id>=49 && id<=51)) { activate(id) }
        }
        pressed = -1
    }
    func handleMenu(window: SdlWindow,record: UiEventRecord,l: Layout): Bool {
        let m=MenuLayout(l)
        if(handleAgentSettings(this,window,record)){return true}
        match(record.event) {
            case UiEvent.MouseMove(x,y)=>hover=m.hit(x,y,menuPage)
            case UiEvent.MouseDown(MouseButton.Left,x,y)=>
                let id=m.hit(x,y,menuPage); pressed=if (id>=0 && menuEnabled(id)) { id } else { -1 }
                if (pressed>=0) { menuFocus=pressed }
            case UiEvent.MouseUp(MouseButton.Left,x,y)=>
                let id=pressed; pressed = -1
                if (id>=0 && id==m.hit(x,y,menuPage)) { menuAction(window,id) }
            case UiEvent.WindowFocusLost=>pressed = -1; hover = -1
            case UiEvent.TextInput(text)=>if (menuPage!=5 && activeField>=0 && draft.size+text.size<=24) {
                var valid=true; for (ch in text.toArray()) { if (!(ch>=48 && ch<=57) && ch!=46) { valid=false } }
                if (valid) { draft+=text }
            }
            case UiEvent.KeyDown(key,repeat)=>
                if (dialog.isSome()) { return true }
                if (menuPage==5) {
                    match(key) { case Key.Escape=>if (!repeat) { menuAction(window,95) }; return true; case _=>() }
                }
                if (activeField>=0 && menuPage!=5) {
                    match(key) {
                        case Key.Escape=>if (!repeat) { activeField = -1 }
                        case Key.Enter=>if (!repeat) { commitField() }
                        case Key.Backspace=>if (!draft.isEmpty()) { draft=draft[..draft.size-1] }
                        case Key.Letter(65)=>if (record.metadata.modifiers.ctrl) { draft="" }
                        case _=>()
                    }; return true
                }
                if (repeat) { return true }
                match(key) {
                    case Key.Escape=>if (menuPage==0) { closeMenu() } else { menuPage=0; menuFocus=80; pressed = -1 }
                    case Key.Tab | Key.Up | Key.Down=>
                        let ids=m.controls(menuPage); var index: Int64=0
                        for (i in 0..ids.size) { if (ids[i]==menuFocus) { index=i } }
                        let backward=match(key) { case Key.Up=>true; case _=>record.metadata.modifiers.shift }
                        for (_ in 0..ids.size) {
                            index=(index+(if (backward) { ids.size-1 } else { 1 }))%ids.size
                            if (menuEnabled(ids[index])) { menuFocus=ids[index]; break }
                        }
                    case Key.Left=>if (menuPage==6) { menuAction(window,96) }
                    case Key.Right=>if (menuPage==6) { menuAction(window,97) }
                    case Key.Enter | Key.Space=>menuAction(window,menuFocus)
                    case _=>()
                }
            case _=>()
        }
        return !exitReady
    }
    func close(): Unit { if (let Some(job) <- searchJob) { job.cancel() }; if (let Some(job) <- evalJob) { job.cancel() }; clearComparison(); view.close(); if (let Some(t) <- reference) { t.close() }; reference=None }
}
