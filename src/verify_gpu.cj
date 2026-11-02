package firebreak

import sdl.*
import std.math.abs
import std.fs.{File,remove}

func verifyGpu(app: App,w: SdlWindow): Unit {
    try(view=VoxelView(app.scene,app.assets)){
        view.useGpu=true; let camera=Camera(); let box=Rect(0.0,0.0,128.0,96.0)
        camera.fitScene(app.scene,box)
        view.prepare(camera,box,w,forceFull:true)
        require(view.gpuActive,"Actual GPU backend did not start: "+view.gpuError)
        let bytes=view.gpu.getOrThrow().engine.readback()
        require(bytes.size==128*96*4,"GPU readback dimensions changed")
        var sky: Int64=0;var terrain: Int64=0
        for(i in 0..128*96){require(bytes[i*4+3]==255,"GPU alpha is not opaque");if(bytes[i*4]==122 && bytes[i*4+1]==155 && bytes[i*4+2]==169){sky++}else{terrain++}}
        println("GPU pixels: sky ${sky}, terrain ${terrain}")
        pass(sky>0 && terrain>0,"Actual D3D11 compute shader renders opaque terrain and sky and completes readback")
        let r=w.renderer;r.beginScene(Float32(w.width),Float32(w.height),Color.rgb(0,0,0));view.draw(Rect(0.0,0.0,512.0,384.0));r.endScene();saveStressCapture(w,"artifacts/gpu-first-frame.png");r.present()
    }
    let scene=Scene(nx:32,nz:32,demo:false)
    for(z in 0..32){for(x in 0..32){scene.heights[z*32+x]=1;scene.set(x,0,z,1)}}
    scene.tree(16,16)
    try(view=VoxelView(scene,app.assets)){
        let b=Rect(0.0,0.0,256.0,256.0);let camera=Camera();camera.fitScene(scene,b);view.useGpu=true
        for(state in 0..4){
            view.showCanopy=state!=1
            if(state==2){view.setFireState(Array<Int64>(1024,repeat:-1),3)}
            if(state==3){view.setFireState(Array<Int64>(1024,repeat:0),3);view.setClusters(Array<Int64>(1024,{i=>i%9-1}));view.selectedX=1;view.selectedZ=1}
            view.dirty=true;view.prepare(camera,b,w,forceFull:true,topDown:true)
            require(view.gpuActive,"GPU terrain validation fell back")
            let bytes=view.gpu.getOrThrow().engine.readback()
            try(cpu=Surface.create(256,256)){
                view.rows(cpu,camera,b,256,256,0,256,parallel:false)
                for(y in 0..256){for(x in 0..256){let c=cpu.readPixel(Int32(x),Int32(y));let i=(y*256+x)*4
                    require(abs(Int64(c.r)-Int64(bytes[i]))<=1 && abs(Int64(c.g)-Int64(bytes[i+1]))<=1 && abs(Int64(c.b)-Int64(bytes[i+2]))<=1 && bytes[i+3]==255,"GPU top-down differs from CPU state ${state} pixel ${x},${y}")
                }}
            }
        }
        pass(true,"GPU top-down pixels match CPU within one channel level for alpha, canopy, burnout, ash, stumps, cluster palette and selection")
        let g=view.gpu.getOrThrow();let before=g.engine.uploads
        camera.rotate(17.0,4.0);view.dirty=true;view.prepare(camera,b,w,topDown:false)
        pass(g.engine.uploads==before && view.nativeReady(),"GPU camera change reuses voxel, chunk, atlas and state buffers at native resolution")
        view.setFireState(Array<Int64>(1024,repeat:2),3);view.prepare(camera,b,w)
        pass(g.engine.uploads==before+1,"Fire-only GPU updates replace compact column state without uploading geometry")
        scene.set(1,1,1,5);view.dirty=true;view.prepare(camera,b,w)
        pass(g.engine.uploads==before+4,"Scene revision uploads changed geometry, occupancy and columns consistently")
        let resized=Rect(0.0,0.0,144.0,112.0);view.dirty=true;view.prepare(camera,resized,w)
        pass(g.engine.readback().size==144*112*4,"GPU viewport resize replaces target and supports odd workgroup boundaries")
        g.engine.profile=true;view.dirty=true;view.prepare(camera,resized,w);g.engine.profile=false
        pass(g.engine.lastGpuMs>=0.0,"Native GPU timestamp queries measure completed dispatch and presentation copy")
        println("GPU adapter: "+g.engine.adapterName+"; GPU completed "+money(g.engine.lastGpuMs)+" ms")
        view.useGpu=false;view.prepare(camera,resized,w,forceFull:true)
        pass(!view.gpuActive && g.isClosed() && view.nativeReady(),"Switching to CPU releases GPU resources and renders a complete CPU frame")
        view.useGpu=true;view.prepare(camera,resized,w)
        pass(view.gpuActive && !view.gpu.getOrThrow().isClosed(),"Switching back recreates a working GPU backend")
    }
    try(view=VoxelView(scene,app.assets)){
        view.useGpu=true;view.gpuError="Controlled unavailable GPU";view.prepare(Camera(),Rect(0.0,0.0,64.0,64.0),w,forceFull:true)
        pass(!view.gpuActive && view.nativeReady() && view.backendName()=="CPU (GPU fallback)","Unavailable GPU keeps an explicit functional CPU fallback")
    }
    let preference="artifacts/gpu-preference-test.json"
    File.writeTo(preference,"{\"language\":\"zh-CN\",\"showFps\":true}".toArray())
    try{
        let p=Preferences(preference);require(p.gpuEnabled,"Legacy preferences should select GPU automatically")
        p.setGpu(false);p.setEnglish(true);p.setShowFps(false);let restored=Preferences(preference)
        pass(!restored.gpuEnabled && restored.english && !restored.showFps,"GPU preference persists across language/FPS changes and legacy settings default to auto")
    }finally{remove(preference)}
    let before=app.work.project.text();let revision=app.work.revision
    app.preferences.gpuEnabled=false;app.menuOpen=true;app.menuPage=2;menuClick(app,w,101)
    render(app,w,capture:"artifacts/gpu-menu.png")
    pass(app.preferences.gpuEnabled && app.view.gpuActive && app.work.project.text()==before && app.work.revision==revision,"Display-menu GPU switch uses actual renderer without changing project/evaluation inputs")
    menuClick(app,w,101);render(app,w);app.menuOpen=false
    pass(!app.preferences.gpuEnabled && !app.view.gpuActive,"Display-menu CPU switch immediately restores the CPU backend")
}
