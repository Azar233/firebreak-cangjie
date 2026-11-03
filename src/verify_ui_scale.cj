package firebreak

import sdl.*
import std.math.abs

func verifyUiScale(app:App,w:SdlWindow):Unit {
    for(size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(1920.0,1080.0),Size(2560.0,1380.0),Size(3840.0,2160.0)]){
        let l=Layout(size.w,size.h);let s=uiScale(size.w,size.h)
        require(abs(l.width*s-size.w)<0.01 && abs(l.height*s-size.h)<0.01,"UI coordinate space does not cover window")
        require(l.canvas.w>0.0 && l.canvas.h>0.0 && abs(l.panel.w-274.0)<0.01,"Default panel proportions changed")
        require(abs(l.control(2).right()-(l.width-20.0))<0.01 && l.control(16).right()<l.control(0).x && l.control(0).right()<l.control(2).x,"View controls are not separated and edge anchored")
        let m=MenuLayout(l);for(id in m.controls(0)){let b=m.box(id);require(b.x>=0.0 && b.right()<=l.width && b.y>=0.0 && b.bottom()<=l.height,"Scaled modal outside logical window")}
    }
    pass(true,"Default panel/button proportions and edge anchoring survive five window sizes through 4K")
    app.menuOpen=false;app.terminal.open=false;app.cancel();enterWorkflow(app,0);app.preferences.gpuEnabled=true
    w.setSize(1280,860);w.refreshSize();render(app,w,capture:"artifacts/ui-proportion-default.png")
    w.setSize(2560,1380);w.refreshSize();render(app,w,capture:"artifacts/ui-proportion-fullscreen.png")
    let l=Layout(Float32(w.width),Float32(w.height));let s=uiScale(Float32(w.width),Float32(w.height));let button=l.control(2);let before=app.view.showCanopy
    // Unlike the logical-coordinate helper, deliver actual native-window coordinates.
    require(app.handle(w,UiEventRecord(UiEvent.MouseDown(MouseButton.Left,button.centerX()*s,button.centerY()*s))),"Unexpected quit")
    require(app.handle(w,UiEventRecord(UiEvent.MouseUp(MouseButton.Left,button.centerX()*s,button.centerY()*s))),"Unexpected quit")
    pass(app.view.showCanopy!=before,"Fullscreen edge control is clickable at the physical rendered position")
    app.view.showCanopy=before
    pass(app.view.targetWidth==canvasResolution(l.canvas,Float64(uiPixelRatio(w))).width,"Scaled viewport retains native physical render resolution")
    w.setSize(1280,860);w.refreshSize();app.preferences.gpuEnabled=false;app.view.useGpu=false
    let demo=App(app.assets,preferencesPath:"",audioEnabled:false)
    try{
        demo.work.acceptLoaded(densityForest(Project(nx:64,nz:64),0.6,42),"");enterWorkflow(demo,0);demo.preferences.gpuEnabled=true
        demo.camera.fitScene(demo.scene,Layout(Float32(w.width),Float32(w.height)).canvas);render(demo,w,capture:"artifacts/release-workbench.png")
    }finally{demo.close()}
}
