package firebreak

import sdl.*

func populateScene(scene: Scene,p: Project,planned: Bool): Unit {
    scene.clear()
    for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
        let i=z*GRID_X+x; let h: Int64=if (p.image.isEmpty() && x>15 && z>12) { 3 } else if (p.image.isEmpty() && x>12 && z>10) { 2 } else { 1 }
        scene.canopyColumns[i]=p.fuel(i,planned:planned)>0.0; scene.heights[i]=h
        let mat=if (planned && p.treatment[i]!=0) { 8 } else { match(p.land[i]) { case 0=>2; case 2=>8; case 3=>9; case 4=>5; case _=>1 } }
        for (y in 0..h) { scene.set(x,y,z,if (y==h-1) { mat } else { 2 }) }
        if (p.land[i]==4) { for (y in h..h+3) { scene.set(x,y,z,6) }; scene.set(x,h+3,z,7) }
    } }
    for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
        let i=z*GRID_X+x
        if (p.fuel(i,planned:planned)>0.0 && x%4==3 && z%4==3) { scene.tree(x,z) }
    } }
}
func fittedMap(canvas: Rect,aspect: Float64): Rect {
    let a=Float32(aspect); let w=min(canvas.w-96.0,(canvas.h-96.0)*a)
    return Rect(canvas.centerX()-w/2.0,canvas.centerY()-w/a/2.0,w,w/a)
}
func compareBox(canvas: Rect,right: Bool): Rect {
    let width=(canvas.w-16.0)/2.0
    return Rect(canvas.x+(if (right) { width+16.0 } else { 0.0 }),canvas.y+34.0,width,canvas.h-34.0)
}
class ComparisonView <: Resource {
    let baselineScene=Scene()
    let plannedScene=Scene()
    let baseline: VoxelView
    let planned: VoxelView
    let result: EvaluationResult
    let aspect: Float64
    let maxStep: Int64
    var step: Int64=0
    var playing=false
    var nextTick: UInt64=0
    var lastCamera=Array<Float64>()
    var closed=false
    init(result: EvaluationResult,assets: Assets) {
        this.result=result; let p=readProjectText(result.projectText); aspect=p.aspect
        populateScene(baselineScene,p,false); populateScene(plannedScene,p,true)
        baseline=VoxelView(baselineScene,assets); planned=VoxelView(plannedScene,assets)
        maxStep=max(result.baselineReplay.snapshots.size,result.plannedReplay.snapshots.size)-1
        applyStep()
    }
    func applyStep(): Unit {
        let a=result.baselineReplay; let b=result.plannedReplay
        baseline.setFireState(a.snapshots[min(step,a.snapshots.size-1)].age,a.duration)
        planned.setFireState(b.snapshots[min(step,b.snapshots.size-1)].age,b.duration)
    }
    func seek(value: Int64): Unit { step=max(0,min(maxStep,value)); playing=false; applyStep() }
    func play(now: UInt64): Unit { if (step==maxStep) { seek(0) }; playing=true; nextTick=now+500 }
    func tick(now: UInt64): Unit {
        for (_ in 0..4) {
            if (!playing || now<nextTick) { break }
            step=min(maxStep,step+1); nextTick+=500; applyStep()
            if (step==maxStep) { playing=false }
        }
    }
    func prepare(camera: Camera,canvas: Rect,window: SdlWindow,topDown: Bool,canopy: Bool,force: Bool,interacting: Bool): Unit {
        let state=[camera.yaw,camera.pitch,camera.zoom,camera.panX,camera.panY]
        if (state!=lastCamera || baseline.showCanopy!=canopy) {
            lastCamera=state; baseline.dirty=true; planned.dirty=true
        }
        baseline.showCanopy=canopy; planned.showCanopy=canopy
        let a=compareBox(canvas,false); let b=compareBox(canvas,true)
        baseline.prepare(camera,if (topDown) { fittedMap(a,aspect) } else { a },window,topDown:topDown,forceFull:force,interacting:interacting)
        planned.prepare(camera,if (topDown) { fittedMap(b,aspect) } else { b },window,topDown:topDown,forceFull:force,interacting:interacting)
    }
    public func close(): Unit { if (closed) { return }; closed=true; baseline.close(); planned.close() }
    public func isClosed(): Bool { closed }
}
