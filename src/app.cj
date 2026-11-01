package firebreak

import sdl.*
import sdl.dialogs.*
import std.collection.ArrayList
import std.convert.*
import std.math.floor
import std.fs.{File,exists}
import stdx.encoding.base64.toBase64String

let CONTROLS=[0,1,2,3,4,5,6,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,30,31,32,33,34,35,36,40,41,42,43,44,45,46,47,48,49,50,51]
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
    func available(id: Int64,settings: Bool,simulation!: Bool=false,parameters!: Bool=false): Bool {
        if (id>=40) { return simulation && (if (id==48) { true } else if (id>=49) { parameters } else { !parameters }) }
        if (simulation && ((id>=2 && id<=6) || id==17 || (id>=30 && id<=36))) { return false }
        if (id>=33 && id<=36) { return settings }
        if (id>=2 && id<=6) { return !settings }
        return true
    }
    func hit(x: Float32,y: Float32,settings!: Bool=false,simulation!: Bool=false,parameters!: Bool=false): Int64 {
        for (id in CONTROLS) { if (available(id,settings,simulation:simulation,parameters:parameters) && control(id).contains(x,y)) { return id } }; return -1
    }
}

class App {
    let scene=Scene()
    let work=Workbench()
    let camera=Camera()
    let assets: Assets
    let font: PixelFont
    let view: VoxelView
    let experiment=Experiment()
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
    var painting=false
    var startCell: Int64 = -1
    var endCell: Int64 = -1
    var lastX: Float32=0.0
    var lastY: Float32=0.0
    var message="场地编辑后可进入火势实验；模型为四邻接、无风的离散示例。"
    var dialog: ?FileDialogRequest=None
    var dialogKind: Int64=0
    init(assets: Assets) {
        this.assets=assets; font=PixelFont(assets); view=VoxelView(scene,assets); syncScene()
    }
    func refreshExperimentView(): Unit {
        if (let Some(r) <- experiment.run) { view.setFireState(r.current().age,r.duration) }
        else { view.setFireState(Array<Int64>(CELL_COUNT,repeat:0),1) }
        view.clusterLabels=if (experiment.showConnectivity) { experiment.analysis.labels } else { Array<Int64>(CELL_COUNT,repeat:-1) }
        view.dirty=true
    }
    func updateExperiment(now: UInt64): Unit {
        clockNow=now
        if (experiment.sync(work.project,work.revision)) { refreshExperimentView() }
        if (let Some(r) <- experiment.run) { if (r.tick(now)) { refreshExperimentView() } }
    }
    func simulationAction(id: Int64): Unit {
        require(startCell<0,"请先应用或取消编辑预览")
        if (experiment.sync(work.project,work.revision)) { refreshExperimentView() }
        match(id) {
            case 40 | 41 =>
                let r=experiment.run ?? experiment.create(work.project)
                if (id==41) { r.running=false; r.advance() }
                else if (r.running) { r.running=false } else { r.play(clockNow) }
                pickingIgnition=false; refreshExperimentView()
                message="同步四邻接传播；仿真步不代表现实秒数，单次结果不代表现实概率。"
            case 42 => experiment.run=None; pickingIgnition=false; refreshExperimentView(); message="已重置试验；场地、处理方案与起火点均保留。"
            case 43 | 44 =>
                if (let Some(r) <- experiment.run) {
                    r.seek(max(0,min(r.snapshots.size-1,r.cursor+(if (id==43) { -1 } else { 1 })))); refreshExperimentView()
                }
            case 45 =>
                if (let Some(r) <- experiment.run) { r.running=false }
                pickingIgnition = !pickingIgnition
                message=if (pickingIgnition) { "点击当前模式的可燃林地设置起火点；Esc 取消。" } else { "已取消起火点选择。" }
            case 46 => experiment.showConnectivity = !experiment.showConnectivity; refreshExperimentView()
            case 47 =>
                experiment.planned = !experiment.planned; pickingIgnition=false; syncScene()
                message="已切换"+(if (experiment.planned) { "处理方案" } else { "原始场地" })+"；旧试验已失效。"
            case 48 => simParameters = !simParameters
            case _ => ()
        }
    }
    func setIgnition(i: Int64): Unit {
        require(i>=0 && i<CELL_COUNT && work.project.fuel(i,planned:experiment.planned)>0.0,"起火点必须位于当前模式的可燃林地")
        let p=work.project.copy(); p.ignition=i; work.commit(p); pickingIgnition=false; syncScene()
        message="起火点 (${i%GRID_X}, ${i/GRID_X}) 已设置；可开始或单步运行。"
    }
    func syncScene(): Unit {
        experiment.sync(work.project,work.revision); refreshExperimentView()
        // P1's bounded scene is rebuilt once per committed edit, never per preview cell.
        // Future larger forests will replace this with dirty chunks and distance-dependent detail.
        let p=work.project
        for (i in 0..scene.blocks.size) { scene.blocks[i]=0 }; scene.trees=0
        for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
            let i=z*GRID_X+x; let h: Int64=if (p.image.isEmpty() && x>15 && z>12) { 3 } else if (p.image.isEmpty() && x>12 && z>10) { 2 } else { 1 }
            scene.canopyColumns[i]=p.fuel(i,planned:experiment.planned)>0.0
            scene.heights[i]=h
            let mat=if (experiment.planned && p.treatment[i]!=0) { 8 } else { match(p.land[i]) { case 0=>2; case 2=>8; case 3=>9; case 4=>5; case _=>1 } }
            for (y in 0..h) { scene.set(x,y,z,if (y==h-1) { mat } else { 2 }) }
            if (p.land[i]==4) { for (y in h..h+3) { scene.set(x,y,z,6) }; scene.set(x,h+3,z,7) }
        } }
        for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
            let i=z*GRID_X+x
            if (p.fuel(i,planned:experiment.planned)>0.0 && x%4==3 && z%4==3) { scene.tree(x,z) }
        } }
        view.dirty=true
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
        work.acceptLoaded(p,path); replaceReference(next); cancel(); syncScene(); mapMode=reference.isSome(); referenceMode=false
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
    func cellAt(x: Float32,y: Float32,l: Layout): Int64 {
        if (!l.canvas.contains(x,y)) { return -1 }
        if (mapMode) {
            let b=mapBox(l); if (!b.contains(x,y)) { return -1 }
            if (let Some(h) <- trace(scene,overheadRay(scene,Float64((x-b.x)/b.w),Float64((y-b.y)/b.h)),groundOnly:true)) { return h.z*GRID_X+h.x }
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
        if (blocked) { return "含保护目标或禁区：整笔不可应用" }
        if (p.metersWide<=0.0) { return "未标定：无法核算平方米和处理费用" }
        var cost=0.0
        for (v in mask) { cost+=if (v==1) { p.clearingPrice } else if (v==2) { p.breakPrice } else { 0.0 } }
        cost*=p.cellArea()
        return "选区 ${money(Float64(cells.size)*p.cellArea())} 平方米 | 方案 ￥${money(cost)}"+(if (cost>p.budget) { " / 超预算" } else { " / 预算内" })
    }
    func cancel(): Unit { painting=false; startCell = -1; endCell = -1; pressed = -1; activeField = -1; dragging=false; panning=false }
    func commitStroke(): Unit {
        require(startCell>=0 && !painting,"请先拖动选区并松开鼠标")
        let changed=work.apply(selection(),tool,erase)
        cancel(); if (changed) { syncScene() }; message=if (changed) { "已应用；整笔操作可撤销。" } else { "选区没有需要更改的格子。" }
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
                require(!value.isNaN() && !value.isInf() && value>=0.0 && value<=2147483647.0 && floor(value)==value,"请输入范围内的整数")
                if (activeField==50) { p.burnSteps=Int64(value) } else { p.seed=Int64(value) }
            case _=>()
        }
        work.commit(p); activeField = -1; updateExperiment(clockNow); message="参数已更新；旧试验失效，预算约束已重新校验。"
    }
    func activate(id: Int64): Unit {
        if ((id>=33 && id<=36) || (id>=49 && id<=51)) {
            commitField(); activeField=id; draft="${fieldValue(id)}"; message="输入数值，Enter 确认，Esc 取消；Backspace 删除。"; return
        }
        commitField()
        if (id>=40 && id<=48) { simulationAction(id); return }
        if (id>=20 && id<=28) { cancel(); pickingIgnition=false; tool=id-20; message="工具："+TOOL_NAMES[tool]+"；拖动预览，再确认应用。"; return }
        match (id) {
            case 0 => camera.reset(); message="相机已复位。"
            case 1 => camera.pitch=1.5707963267948966; mapMode=false; message="俯视编辑。"
            case 2 => view.showCanopy = !view.showCanopy
            case 3 => camera.rotate(-20.0,0.0)
            case 4 => camera.rotate(20.0,0.0)
            case 5 => camera.scale(1.0)
            case 6 => camera.scale(-1.0)
            case 14 | 15 =>
                let from=if (id==14) { work.undo } else { work.redo }
                if (!from.isEmpty()) {
                    let next=makeReference(readProjectText(from[from.size-1]))
                    cancel(); work.history(id==14); replaceReference(next); syncScene()
                    message=if (id==14) { "已撤销。" } else { "已重做。" }
                }
            case 16 => cancel(); mapMode = !mapMode
            case 17 => settings = !settings
            case 18 =>
                if (reference.isNone()) { message="请先导入底图；二维地图已使用三维场景的纹理俯视。"; return }
                cancel(); referenceMode = if (mapMode) { !referenceMode } else { true }; mapMode=true
            case 19 => cancel(); pickingIgnition=false; simPanel = !simPanel; simParameters=false
            case 30 => cancel(); erase = !erase; message="擦除模式：地类恢复空地，标记或处理带移除。"
            case 31 => commitStroke()
            case 32 => cancel(); message="已取消预览。"
            case _ => ()
        }
        view.dirty=true
    }
    func select(x: Float32,y: Float32,l: Layout): Unit {
        let i=cellAt(x,y,l)
        view.selectedX=if (i>=0) { i%GRID_X } else { -1 }; view.selectedZ=if (i>=0) { i/GRID_X } else { -1 }; view.dirty=true
        if (i>=0) {
            let p=work.project
            message="格 (${i%GRID_X}, ${i/GRID_X})："+LAND_NAMES[p.land[i]]+"；相对可燃量 ${p.fuel(i)} / 方案 ${p.fuel(i,planned:true)}"
        } else { message="当前位置没有地面。" }
    }
    func discard(window: SdlWindow): Bool {
        if (!work.dirty() && startCell<0 && activeField<0) { return true }
        var opts=MessageBoxOptions("未保存更改","当前项目或预览尚未保存。是否放弃并继续？")
        opts.kind=MessageBoxKind.Warning
        opts.buttons=[MessageBoxButton("取消",id:0,returnKeyDefault:true,escapeKeyDefault:true),MessageBoxButton("放弃更改",id:1)]
        return showMessageBox(opts,window:Some(window))==1
    }
    func requestFile(window: SdlWindow,kind: Int64): Unit {
        require(dialog.isNone(),"请先完成文件对话框")
        commitField(); require(startCell<0,"请先应用或取消选区")
        dialogKind=kind
        let filter=if (kind==13) { FileDialogFilter("底图 PNG / JPEG","png;jpg;jpeg") } else { FileDialogFilter("断火线项目","firebreak") }
        let options=FileDialogOptions(filters:[filter])
        dialog=Some(if (kind==12) { FileDialogs.saveFile(options:options,window:Some(window)) } else { FileDialogs.openFile(options:options,window:Some(window)) })
    }
    func importImage(path: String): Unit {
        let bytes=File.readFrom(path); require(bytes.size<=8000000,"底图上限 8 MB")
        let p=Project(demo:false); p.image=toBase64String(bytes); p.source="用户导入底图"; p.metersWide=0.0
        try (s=Surface.loadBytes(bytes,options:ImageLoadOptions(maxPixels:16000000))) { p.aspect=Float64(s.size().w)/Float64(s.size().h) }
        p.validate()
        // Decode/upload before changing the document so a failed import keeps the current project.
        let s=decodeReference(p).getOrThrow()
        let t=try { assets.r.textureFromSurface(s) } finally { s.close() }
        work.commit(p); work.path=""; if (let Some(old) <- reference) { old.close() }; reference=Some(t)
        cancel(); syncScene(); mapMode=true; referenceMode=true; settings=true; message="底图已导入；请标定宽度并标注。点击纹理俯视查看三维场景的正上方。"
    }
    func pollFile(window: SdlWindow): Unit {
        if (let Some(request) <- dialog) {
            match(request.result()) {
                case FileDialogResult.FileDialogPending => ()
                case FileDialogResult.FileDialogCanceled => dialog=None
                case FileDialogResult.FileDialogFailed(error) => dialog=None; message="文件对话框失败："+error
                case FileDialogResult.FileDialogSelected(paths,_) =>
                    dialog=None; if (paths.isEmpty()) { return }
                    try {
                        if (dialogKind==12) {
                            var path=paths[0]; if (!path.endsWith(".firebreak")) { path+=".firebreak" }
                            if (exists(path) && path!=work.path) {
                                var opts=MessageBoxOptions("覆盖项目","所选项目已存在，是否替换？")
                                opts.buttons=[MessageBoxButton("取消",id:0,returnKeyDefault:true,escapeKeyDefault:true),MessageBoxButton("替换",id:1)]
                                if (showMessageBox(opts,window:Some(window))!=1) { return }
                            }
                            work.save(path); message="项目已安全保存。"
                        } else if (discard(window)) {
                            if (dialogKind==13) { importImage(paths[0]) }
                            else { loadProject(paths[0]); message="项目已读取。" }
                        }
                    } catch(e: Exception) { message="操作失败："+e.message }
            }
        }
    }
    func action(window: SdlWindow,id: Int64): Unit {
        if (id==10) {
            if (discard(window)) { cancel(); work.commit(Project()); work.path=""; work.unsaved=true; refreshReference(); syncScene(); message="已建立示例；请另存项目。" }
        } else if (id>=11 && id<=13) { requestFile(window,id) } else { activate(id) }
    }
    func handle(window: SdlWindow,record: UiEventRecord): Bool {
        clockNow=window.ticks()
        try { return handleInput(window,record) } catch(e: Exception) { painting=false; message="操作未应用："+e.message; return true }
    }
    func handleInput(window: SdlWindow,record: UiEventRecord): Bool {
        let l=Layout(Float32(window.width),Float32(window.height))
        match (record.event) {
            case UiEvent.Quit | UiEvent.WindowCloseRequested => return !discard(window)
            case UiEvent.WindowResized(_,_) | UiEvent.WindowDisplayScaleChanged =>
                window.refreshSize()
                if (window.width<1100 || window.height<780) { window.setSize(max(1100,window.width),max(780,window.height)) }; view.dirty=true
            case UiEvent.MouseMove(x,y) =>
                hover=l.hit(x,y,settings:settings,simulation:simPanel,parameters:simParameters)
                if (painting) { let i=cellAt(x,y,l); if (i>=0) { endCell=i } }
                if (dragging) { camera.rotate(Float64(x-lastX),Float64(y-lastY)); view.dirty=true }
                if (panning) { camera.panX+=Float64(x-lastX); camera.panY+=Float64(y-lastY); view.dirty=true }
                lastX=x; lastY=y
            case UiEvent.MouseDown(button,x,y) =>
                lastX=x; lastY=y
                match (button) {
                    case MouseButton.Left => pressed=l.hit(x,y,settings:settings,simulation:simPanel,parameters:simParameters)
                        if (pressed>=0) { for (i in 0..CONTROLS.size) { if (CONTROLS[i]==pressed) { focus=i } } }
                        else if (l.canvas.contains(x,y)) {
                            commitField()
                            if (pickingIgnition) { setIgnition(cellAt(x,y,l)); return true }
                            select(x,y,l)
                            if (tool!=0) { if (let Some(r) <- experiment.run) { r.running=false } }
                            if (tool!=0 && startCell<0) { startCell=cellAt(x,y,l); endCell=startCell; painting=startCell>=0 }
                        }
                    case MouseButton.Right => dragging = !mapMode && startCell<0 && l.canvas.contains(x,y)
                    case MouseButton.Middle => panning = !mapMode && startCell<0 && l.canvas.contains(x,y)
                    case _ => ()
                }
            case UiEvent.MouseUp(button,x,y) =>
                match (button) {
                    case MouseButton.Left =>
                        if (painting) { painting=false; message="选区 ${selection().size} 格；确认应用 / Enter，取消 / Esc。" }
                        else if (pressed>=0 && pressed==l.hit(x,y,settings:settings,simulation:simPanel,parameters:simParameters)) { action(window,pressed) }; pressed = -1
                    case MouseButton.Right => dragging=false
                    case MouseButton.Middle => panning=false
                    case _ => ()
                }
            case UiEvent.MouseWheel(_,dy,x,y) => if (!mapMode && startCell<0 && l.canvas.contains(x,y)) { camera.scale(Float64(dy)); view.dirty=true }
            case UiEvent.WindowFocusLost =>
                if (let Some(r) <- experiment.run) { r.running=false }
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
                        case Key.Letter(83) => if (work.path.isEmpty() || record.metadata.modifiers.shift) { requestFile(window,12) } else { require(startCell<0,"请先应用或取消选区"); work.save(work.path); message="项目已保存。" }; return true
                        case Key.Letter(79) => requestFile(window,11); return true
                        case Key.Letter(90) => activate(if (record.metadata.modifiers.shift) { 15 } else { 14 }); return true
                        case Key.Letter(89) => activate(15); return true
                        case _ => ()
                    }
                }
                match (key) {
                    case Key.Tab => if (!repeat) {
                        let step=if (record.metadata.modifiers.shift) { CONTROLS.size-1 } else { 1 }
                        for (_ in 0..CONTROLS.size) { focus=(focus+step)%CONTROLS.size; if (l.available(CONTROLS[focus],settings,simulation:simPanel,parameters:simParameters)) { break } }
                    }
                    case Key.Enter => if (!repeat) { if (startCell>=0) { commitStroke() } else { action(window,CONTROLS[focus]) } }
                    case Key.Space => if (!repeat) { action(window,CONTROLS[focus]) }
                    case Key.Home => activate(0)
                    case Key.Letter(84) => activate(1)
                    case Key.Letter(72) => activate(2)
                    case Key.Digit(n) => if (n>=49 && n<=57) { activate(20+Int64(n-49)) }
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
                    case Key.Escape => cancel(); pickingIgnition=false; message="已取消当前操作。"
                    case _ => ()
                }
            case _ => ()
        }
        return true
    }
    func close(): Unit { view.close(); if (let Some(t) <- reference) { t.close() }; reference=None }
}



