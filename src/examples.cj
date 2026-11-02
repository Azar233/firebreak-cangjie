package firebreak

let CASE_FILES=["examples/chain-baseline.firebreak","examples/chain-firebreak.firebreak","examples/budget-camp.firebreak","examples/budget-camp-plan.firebreak"]
func caseLabel(app:App,index:Int64):String {
    let zh=["01 五格传播链 · 原始场地","02 五格传播链 · 清理中间一格","03 百元预算营地 · 原始场地","04 百元预算营地 · 窄桥处理方案"]
    let en=["01 Five-cell chain / baseline","02 Five-cell chain / one-cell cut","03 Budget camp / baseline","04 Budget camp / bridge cut"]
    return app.t(zh[index],en[index])
}
func openExample(app:App,index:Int64):Unit {
    require(index>=0 && index<CASE_FILES.size,"Invalid example index")
    app.loadProject(CASE_FILES[index])
    // Treat bundled examples as templates. Save always starts with Save As.
    app.work.path="";app.work.saved="";app.work.unsaved=true
    app.terminal.open=false;app.menuOpen=false;app.comparePanel=false;app.suggestPanel=false;app.settings=false
    app.simPanel=true;app.simParameters=false;app.experiment.planned=true;app.experiment.run=None
    app.camera.resetMap();app.mapMode=true;app.referenceMode=false;app.syncScene()
    app.message=if(index<2){app.t("合成案例：概率1、燃烧1步；左侧起火可被隔开，右侧起火仍会接触目标。请另存项目。","Synthetic case: p=1, one burn step. The cut blocks left-side fire; right-side fire still reaches the target. Save As." )}
        else{app.t("合成营地：预算100元。比较8组训练与8组留出；保留未保护目标的情景。请另存项目。","Synthetic camp: CNY 100. Compare 8 training and 8 holdout scenarios; retain target-contact cases. Save As.")}
}
