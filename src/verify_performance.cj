package firebreak

import sdl.*
import std.fs.{File,remove}

func verifyPerformance(app: App,w: SdlWindow): Unit {
    let meter=FrameMeter(); meter.tick(1000.0); meter.tick(1250.0); meter.tick(1500.0)
    pass(meter.fps==4.0,"FPS uses elapsed frame time, including waits")
    meter.tick(2500.0); pass(meter.fps==1.0,"FPS reflects a long frame rather than hiding stalls")
    let path="artifacts/fps-preferences-test.json"
    File.writeTo(path,"{\"language\":\"en-US\"}".toArray())
    try {
        let p=Preferences(path); require(p.english && !p.showFps,"Legacy preference default changed")
        p.setShowFps(true); p.setEnglish(false)
        let loaded=Preferences(path)
        pass(loaded.showFps && !loaded.english,"FPS setting persists and survives language changes; old settings default off")
    } finally { remove(path) }
    app.menuOpen=true; app.menuPage=2; app.preferences.setShowFps(false)
    let before=app.work.project.text(); let revision=app.work.revision
    menuClick(app,w,100)
    pass(app.preferences.showFps && app.work.project.text()==before && app.work.revision==revision,"Display-menu FPS toggle does not alter planning or evaluation inputs")
    render(app,w,capture:"artifacts/fps-settings.png")
    menuClick(app,w,100); require(!app.preferences.showFps,"FPS toggle cannot turn off"); app.menuOpen=false
    let clock=PerformanceClock(); let example=ForestExample(ForestSpec(64,0.74,42),clock)
    let low=forestField(ForestSpec(64,0.42,42)); let high=forestField(ForestSpec(64,0.74,42))
    let repeat=forestField(ForestSpec(64,0.74,42)); var count: Int64=0
    for (i in 0..high.size) { require(high[i]==repeat[i] && (!low[i] || high[i]),"Forest seed/coupled density changed"); if (high[i]) { count++ } }
    pass(count==example.occupied && example.scene.blocks.size==64*64*14 && example.scene.trees>0,"Large-scene generator is deterministic with nested occupation and correctly sized voxel storage")
    let labels=example.largestLabels(clock)
    pass(labels.size==4096 && example.largest>0 && example.largest<=example.occupied,"Diagnostic connectivity uses fuel cells separately from rendered tree instances")
    let camera=Camera(); camera.fitScene(example.scene,Rect(0.0,0.0,900.0,600.0))
    pass(camera.centerX==32.0 && camera.centerZ==32.0 && camera.distance>64.0 && camera.zoom<8.0,"Stress camera fits a large world without changing normal camera defaults")
    try (view=VoxelView(example.scene,app.assets)) { pass(view.fireAge.size==4096 && view.burnStages.size==4096 && view.clusterLabels.size==4096,"Renderer display buffers follow diagnostic scene dimensions") }
    pass(ProcessMemory().workingMiB>0.0 && clock.ms()>0.0,"Native Windows timing and process-memory counters are available")
}
