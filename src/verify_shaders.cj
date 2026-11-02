package firebreak

import sdl.*
import std.fs.{File,remove}

func verifyShaders(app: App,w: SdlWindow): Unit {
    verifySmoothLighting(app,w)
    let scene=Scene();let original=scene.blocks.clone();let revision=scene.revision
    try(view=VoxelView(scene,app.assets)){
        view.useGpu=true;let camera=Camera();let box=Rect(0.0,0.0,256.0,192.0);camera.fitScene(scene,box)
        for(top in [false,true]){
            view.shadersEnabled=false;view.dirty=true;view.prepare(camera,box,w,topDown:top)
            require(view.gpuActive,"Shader validation requires actual GPU: "+view.gpuError)
            let engine=view.gpu.getOrThrow().engine;let off=engine.readback();let uploads=engine.uploads
            view.shadersEnabled=true;view.prepare(camera,box,w,topDown:top);let on=engine.readback()
            var changed: Int64=0
            for(i in 0..off.size/4){
                require(on[i*4+3]==255,"Lighting changed output alpha")
                if(off[i*4]==122 && off[i*4+1]==155 && off[i*4+2]==169){require(on[i*4]==122 && on[i*4+1]==155 && on[i*4+2]==169,"Lighting changed sky silhouette")}
                if(off[i*4]!=on[i*4] || off[i*4+1]!=on[i*4+1] || off[i*4+2]!=on[i*4+2]){changed++}
            }
            pass(changed>100 && engine.uploads==uploads,"MC lighting changes actual GPU surface pixels without geometry uploads, alpha or sky changes; top=${top}")
            view.shadersEnabled=false;view.prepare(camera,box,w,topDown:top)
            pass(engine.readback()==off,"Disabling lighting restores exact original GPU pixels; top=${top}")
        }
        view.setFireState(Array<Int64>(scene.nx*scene.nz,repeat:0),4);view.shadersEnabled=true
        view.prepare(camera,box,w,topDown:true);let burnt=view.gpu.getOrThrow().engine.readback()
        view.setFireState(Array<Int64>(scene.nx*scene.nz,repeat:3),4);view.prepare(camera,box,w,topDown:true)
        pass(burnt!=view.gpu.getOrThrow().engine.readback() && scene.blocks==original && scene.revision==revision,"Lit burning/burnout display uses state buffers and preserves the voxel model")
        view.prepare(camera,stressBox(w,scene,false),w,topDown:false)
        stressFrame(w,view,app.font,false,"Shader validation",FrameMeter(),capture:"artifacts/shader-lab-settings.png")
    }
    let path="artifacts/shader-preference-test.json"
    File.writeTo(path,"{\"language\":\"zh-CN\"}".toArray())
    try{
        let p=Preferences(path);require(!p.shadersEnabled,"Legacy preferences must default lighting off")
        p.setShaders(true);p.setEnglish(true);p.setGpu(false);p.setShowFps(true)
        pass(Preferences(path).shadersEnabled,"Lighting preference survives language, FPS and CPU backend changes")
        p.setShaders(false);pass(!Preferences(path).shadersEnabled,"Lighting preference persists off")
    }finally{remove(path)}
    let before=app.work.project.text();let beforeRevision=app.work.revision
    app.menuOpen=true;app.menuPage=2;app.preferences.gpuEnabled=true;app.preferences.shadersEnabled=false
    menuClick(app,w,102);render(app,w,capture:"artifacts/shader-settings.png")
    pass(app.view.gpuActive && app.view.shadersEnabled && app.preferences.shadersEnabled && app.work.project.text()==before && app.work.revision==beforeRevision,"Lighting menu hit target enables real GPU rendering without changing project inputs")
    menuClick(app,w,101);render(app,w)
    pass(!app.menuEnabled(102) && !app.view.shadersEnabled && app.preferences.shadersEnabled,"CPU fallback disables lighting control and retains the preference")
    let p=Project();p.ignition=75;p.treatment[300]=2
    let result=evaluated(p,makeScenarios(p,4));let pair=ComparisonView(result,app.assets)
    app.work.acceptLoaded(p,"");app.syncScene();app.work.revision=result.revision
    app.evalResult=Some(result);app.pairView=Some(pair);app.comparePanel=true;app.mapMode=true
    app.preferences.gpuEnabled=true;app.preferences.shadersEnabled=false;render(app,w)
    let baseline=pair.baseline.gpu.getOrThrow().engine.readback();let planned=pair.planned.gpu.getOrThrow().engine.readback()
    app.preferences.shadersEnabled=true;render(app,w)
    pass(pair.baseline.shadersEnabled && pair.planned.shadersEnabled && pair.baseline.gpu.getOrThrow().engine.readback()!=baseline &&
        pair.planned.gpu.getOrThrow().engine.readback()!=planned,"Comparison menu preference refreshes both independent GPU maps")
    app.preferences.shadersEnabled=false;render(app,w)
    pass(pair.baseline.gpu.getOrThrow().engine.readback()==baseline && pair.planned.gpu.getOrThrow().engine.readback()==planned,"Comparison lighting off restores both original map images")
    app.clearComparison();app.comparePanel=false;app.mapMode=false;app.work.acceptLoaded(Project(),"");app.syncScene()
    app.preferences.shadersEnabled=false;app.preferences.gpuEnabled=false;app.view.useGpu=false;app.menuOpen=false
}

func verifySmoothLighting(app: App,w: SdlWindow): Unit {
    let scene=Scene(nx:8,nz:8,demo:false)
    for(z in 0..8){for(x in 0..8){scene.heights[z*8+x]=1;scene.set(x,0,z,5)}}
    scene.set(4,1,3,5)
    try(view=VoxelView(scene,app.assets)){
        view.useGpu=true;let camera=Camera();let box=Rect(0.0,0.0,256.0,256.0)
        view.prepare(camera,box,w,topDown:true)
        require(view.gpuActive,"Smooth-light regression requires real GPU")
        let engine=view.gpu.getOrThrow().engine
        // Neutral opaque atlas separates lighting gradients from texture detail.
        engine.upload(2,Array<UInt8>(10*256*4,repeat:255))
        view.shadersEnabled=false;view.dirty=true;view.prepare(camera,box,w,topDown:true);let off=engine.readback()
        view.shadersEnabled=true;view.prepare(camera,box,w,topDown:true);let on=engine.readback()
        let row: Int64=112;let near: Int64=(row*256+124)*4;let far: Int64=(row*256+100)*4
        pass(off[near]==off[far] && Int64(on[far])-Int64(on[near])>10,
            "Actual GPU white ground has a smooth within-face contact-light gradient that flat per-voxel lighting cannot produce")
        var previous=Int64(on[far]);var levels: Int64=1
        for(x in 101..125){
            let value=Int64(on[(row*256+x)*4]);require(value<=previous && previous-value<=4,"Smooth contact lighting has a discontinuity inside one face")
            if(value!=previous){levels++};previous=value
        }
        pass(levels>=8,"Contact-light interpolation produces at least eight monotone levels without filtering the texture")
        let left=Int64(on[(row*256+95)*4]);let right=Int64(on[(row*256+96)*4])
        pass(left-right<=2 && right-left<=2,"Adjacent coplanar faces share corner lighting without a block-edge seam")
        for(i in 0..256*256){require(on[i*4+3]==255 && on[i*4]==on[i*4+1] && on[i*4+1]==on[i*4+2],"Smooth lighting changes neutral color or alpha")}
        pass(true,"Neutral material and output alpha remain intact under interpolated lighting")
    }
}
