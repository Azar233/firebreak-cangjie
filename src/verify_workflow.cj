package firebreak

import sdl.*

func verifyWorkflow(app:App,w:SdlWindow):Unit {
    app.cancel();app.menuOpen=false;app.terminal.open=false;app.work.acceptLoaded(Project(),"");app.syncScene()
    let previousGpu=app.preferences.gpuEnabled
    app.preferences.gpuEnabled=true;app.mapMode=false;app.view.showCanopy=true;app.camera.reset()
    let source=app.work.project.text();let revision=app.work.revision
    let forest=app.work.project
    require(forest.count(forest.targets)==0 && forest.count(forest.forbidden)==0 && forest.count(forest.treatment)==0,"New forest retained legacy annotation masks")
    for(land in forest.land){require(land==1,"New forest contains a legacy road or building")}
    for(material in app.scene.blocks){require(material!=6 && material!=7 && material!=8,"New forest still renders legacy building or road voxels")}
    pass(true,"Default forest has no camp, road, protected target or exclusion zone in either project data or rendered voxels")
    for(size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]){
        let l=Layout(size.w,size.h)
        for(step in 0..4){let b=l.control(55+step);require(b.w>=44.0 && b.right()<=size.w && l.hit(b.centerX(),b.centerY())==55+step,"Pipeline target outside window")}
        for(id in [10,11,12,13,17,18,19,22,23,24,27,28,52]){require(!l.available(id,false),"Advanced action leaks into the primary canvas hit map")}
        for(page in [9,10]){let m=MenuLayout(l);for(id in m.controls(page)){let b=m.box(id,page:page);require(b.x>=0.0 && b.y>=0.0 && b.right()<=size.w && b.bottom()<=size.h && m.hit(b.centerX(),b.centerY(),page)==id,"Moved menu action outside window or overlapping")}}
    }
    pass(true,"Four pipeline steps and advanced menu targets fit desktop sizes without hidden canvas hotspots")
    click(app,w,55);pass(currentWorkflow(app)==0 && app.tool==1 && app.work.revision==revision && app.work.project.text()==source,"Build step changes the workspace without editing the project")
    render(app,w,capture:"artifacts/workflow-build.png")
    app.startCell=0;app.endCell=1;let tool=app.tool;click(app,w,58)
    pass(currentWorkflow(app)==0 && app.startCell==0 && app.endCell==1 && app.tool==tool,"A pending edit blocks pipeline navigation without discarding its selection")
    app.cancel();click(app,w,56);click(app,w,45)
    let l=Layout(Float32(w.width),Float32(w.height));app.mapMode=true;let point=mapPoint(app,l,3,3)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,point.x,point.y));event(app,w,UiEvent.MouseUp(MouseButton.Left,point.x,point.y));click(app,w,41)
    let run=app.experiment.run.getOrThrow();let cursor=run.cursor
    click(app,w,57)
    pass(currentWorkflow(app)==2 && app.tool==5 && app.work.project.ignition==75 && !run.running && run.cursor==cursor,"Intervention step pauses the trial and preserves its logical snapshot when its inputs are unchanged")
    render(app,w,capture:"artifacts/workflow-intervene.png")
    click(app,w,56);pass(refEq(run,app.experiment.run.getOrThrow()) && run.cursor==cursor,"Returning to observation restores the existing single-fire trial")
    render(app,w,capture:"artifacts/workflow-observe.png")
    click(app,w,58);pass(app.comparePanel && currentWorkflow(app)==3 && app.work.project.ignition==75,"Compare step reuses paired evaluation without altering the ignition")
    render(app,w,capture:"artifacts/workflow-compare.png")
    click(app,w,55);click(app,w,53);menuClick(app,w,81)
    pass(app.menuPage==9 && MenuLayout(l).controls(9).contains(12),"File actions and advanced configuration are discoverable in Files & Project")
    menuClick(app,w,119);menuClick(app,w,28)
    pass(!app.menuOpen && app.tool==8 && currentWorkflow(app)==0,"Advanced tools remain reachable while the main toolbar stays focused")
    event(app,w,UiEvent.KeyDown(Key.Digit(51),false));pass(app.tool==5,"Third toolbar shortcut selects clearing rather than a hidden land annotation")
    event(app,w,UiEvent.KeyDown(Key.Digit(52),false));pass(app.tool==6,"Fourth toolbar shortcut selects the firebreak tool")
    for(id in [55,56,57,58,20,21,25,26,45,46,53,54]){
        require(!controlIcon(id).isEmpty() && !workflowTip(app,id).isEmpty(),"Primary action lacks an icon or readable explanation")
        app.assets.image(controlIcon(id))
    }
    pass(true,"Primary actions load actual Minecraft textures and retain text explanations")
    app.work.acceptLoaded(Project(),"");app.syncScene();enterWorkflow(app,0);app.tool=0;app.focus=0
    app.preferences.gpuEnabled=previousGpu;app.view.useGpu=previousGpu
}
