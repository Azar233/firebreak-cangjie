package firebreak

import sdl.*

class LongReplay <: Resource {
    let result:LongResult;let base:Project;let scenes:Array<Scene>;let views:Array<VoxelView>;let camera=Camera()
    var cursor:Int64=0;var playing=false;var nextTick:UInt64=0;var frameStart:UInt64=0;var firePhase=false;var closed=false
    init(result:LongResult,assets:Assets){
        this.result=result;let p=readProjectText(result.source);base=p
        let worlds=Array<Scene>(2,{_=>Scene(nx:p.nx,nz:p.nz,demo:false)});scenes=worlds
        views=Array<VoxelView>(2,{i=>VoxelView(worlds[i],assets)})
        camera.fitScene(scenes[0],Rect(0.0,0.0,400.0,260.0));applyFrame()
    }
    func frame():LongPairFrame {result.frames[cursor]}
    func applyFrame():Unit {
        let current=frame()
        for(policy in 0..2){
            let p=base.copy();for(i in 0..p.cells){if(p.treatment[i]==0){p.vegetation[i]=if(current.states[policy][i]>0){1}else{0}}}
            populateScene(scenes[policy],p,true)
        };setPhase(true)
    }
    func setPhase(fire:Bool):Unit {
        firePhase=fire;let current=frame()
        for(policy in 0..2){
            let age=Array<Int64>(base.cells,{i=>if(current.states[policy][i]==2){-1}else{0}})
            if(fire && current.drive>0){for(i in current.burned[policy]){age[i]=1}}
            views[policy].setFireState(age,1)
        }
    }
    func seek(index:Int64,now:UInt64):Unit {cursor=max(0,min(result.frames.size-1,index));playing=false;frameStart=now;applyFrame()}
    func play(now:UInt64):Unit {if(cursor==result.frames.size-1){seek(0,now)};playing=true;nextTick=now+400;frameStart=now}
    func tick(now:UInt64):Unit {
        if(playing && now>=nextTick){cursor=min(result.frames.size-1,cursor+1);frameStart=now;nextTick=now+400;applyFrame();if(cursor==result.frames.size-1){playing=false}}
        let phase=now>=frameStart && now-frameStart<220
        if(phase!=firePhase){setPhase(phase)}
    }
    func snapshot(policy:Int64):Project {
        require(policy==0 || policy==1,"Invalid snapshot policy")
        let p=base.copy();let current=frame()
        for(i in 0..p.cells){if(p.treatment[i]==0){p.vegetation[i]=if(current.states[policy][i]==1){1}else{0}}}
        p.seed=current.rows[policy].seed;p.ignition=if(current.drive>0 && current.rows[policy].lightning){current.rows[policy].ignition}else{-1}
        p.source="growth-lightning-v1 sample 1, observation drive ${current.drive}, policy ${policy}; vegetation snapshot only"
        p.validate();return p
    }
    public func close():Unit {if(closed){return};closed=true;for(view in views){view.close()}}
    public func isClosed():Bool {closed}
}
func longChart(l:Layout):Rect {Rect(l.canvas.x+50.0,l.canvas.y+44.0,l.canvas.w-78.0,l.canvas.h*0.27)}
func longArea(l:Layout,policy:Int64):Rect {
    let chart=longChart(l);let width=(l.canvas.w-52.0)/2.0;let top=chart.bottom()+126.0
    return Rect(l.canvas.x+18.0+Float32(policy)*(width+16.0),top,width,l.canvas.bottom()-top-14.0)
}
func longSceneBox(l:Layout,policy:Int64,aspect:Float64,topDown:Bool):Rect {
    let area=longArea(l,policy);if(!topDown){return area}
    let width=min(area.w,area.h*Float32(aspect));let height=width/Float32(aspect)
    return Rect(area.centerX()-width/2.0,area.centerY()-height/2.0,width,height)
}
func longScenePoint(replay:LongReplay,box:Rect,cell:Int64,topDown:Bool,height:Float64):Point {
    let x=cell%replay.base.nx;let z=cell/replay.base.nx
    if(topDown){let world=replay.camera.mapWorldBox(box);return Point(world.x+(Float32(x)+0.5)*world.w/Float32(replay.base.nx),world.y+(Float32(z)+0.5)*world.h/Float32(replay.base.nz))}
    return replay.camera.project(Vec(Float64(x)+0.5,height,Float64(z)+0.5),box)
}
// Vanilla lightning is untextured vertex color. Generate a jagged colored ribbon
// as layered SDL GPU strokes; the voxel views continue to use D3D11/HLSL.
func drawLongLightning(app:App,replay:LongReplay,policy:Int64,box:Rect,now:UInt64):Unit {
    let current=replay.frame();let row=current.rows[policy]
    if(current.drive<=0 || !row.lightning || now<replay.frameStart || now-replay.frameStart>=220){return}
    let r=app.assets.r;let target=longScenePoint(replay,box,row.ignition,app.longTopDown,1.1)
    r.pushClip(box)
    if(app.longTopDown){
        app.assets.blit("textures/particle/flash.png",Rect(target.x-18.0,target.y-18.0,36.0,36.0),tint:Color.rgba(205,222,255,210))
    }else{
        let x=Float64(row.ignition%replay.base.nx)+0.5;let z=Float64(row.ignition/replay.base.nx)+0.5
        var previous=replay.camera.project(Vec(x,16.0,z),box)
        for(segment in 1..9){
            let y=16.0-Float64(segment)*14.9/8.0
            let dx=if(segment==8){0.0}else{(longRandom(row.seed,row.globalDrive,3,segment)-0.5)*2.0}
            let dz=if(segment==8){0.0}else{(longRandom(row.seed,row.globalDrive,4,segment)-0.5)*2.0}
            let point=replay.camera.project(Vec(x+dx,y,z+dz),box)
            for(layer in 0..3){r.strokeLine(previous.x,previous.y,point.x,point.y,Pen(width:if(layer==0){8.0}else if(layer==1){3.0}else{1.0},color:if(layer==0){Color.rgba(160,178,255,55)}else if(layer==1){Color.rgba(196,210,255,180)}else{Color.rgb(248,250,255)}))}
            previous=point
        }
    }
    r.strokeRect(Rect(target.x-5.0,target.y-5.0,10.0,10.0),Pen(width:2.0,color:if(row.suppressed){Color.rgb(124,239,176)}else if(!row.hit){Color.rgb(180,183,190)}else{Color.rgb(255,177,67)}))
    r.popClip()
}
func drawLongFlames(app:App,replay:LongReplay,policy:Int64,box:Rect):Unit {
    if(!replay.firePhase){return};let cells=replay.frame().burned[policy];let stride=max(1,(cells.size+255)/256)
    let texture=app.assets.image("textures/block/fire_0.png");let side=texture.width;let count=max(1,Int64(texture.height/side));let animation=Int64(app.clockNow/80)%count
    app.assets.r.pushClip(box)
    var index:Int64=0
    while(index<cells.size){
        let cell=cells[index];index+=stride
        let point=if(app.longTopDown){longScenePoint(replay,box,cell,true,1.0)}else{replay.camera.project(replay.views[policy].fireAnchor(cell),box)}
        if(!box.contains(point.x,point.y)){continue}
        let size:Float32=if(app.longTopDown){max(4.0,min(20.0,box.w*Float32(replay.camera.mapZoom)/Float32(replay.base.nx)))}else{max(4.0,Float32(replay.camera.zoom))}
        app.assets.blit("textures/block/fire_0.png",Rect(point.x-size/2.0,point.y-size,size,size),source:Some(Rect(0.0,Float32(animation)*side,side,side)))
    };app.assets.r.popClip()
}
