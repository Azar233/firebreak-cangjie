package firebreak

import sdl.*

let PRIMARY_TOOLS=[0,1,5,6]
func currentWorkflow(app:App):Int64 {
    if(app.comparePanel){return 3};if(app.simPanel){return 1};if(app.suggestPanel){return 2}
    return if(app.workflowStage==2){2}else{0}
}
func workflowName(app:App,step:Int64):String {
    let zh=["建立森林","观察森林","设计干预","同条件对照"]
    let en=["Build Forest","Observe Forest","Intervene","Compare"]
    return app.t(zh[step],en[step])
}
func enterWorkflow(app:App,step:Int64):Unit {
    require(step>=0 && step<=3,"Invalid workflow step")
    require(app.startCell<0 && app.activeField<0 && !app.painting,app.t("请先应用或取消当前选区与输入，再切换步骤。","Apply or cancel the pending selection/input before switching steps."))
    if(let Some(run)<-app.experiment.run){run.running=false}
    if(let Some(pair)<-app.pairView){pair.playing=false}
    app.workflowStage=step;app.comparePanel=step==3;app.simPanel=step==1
    app.settings=false;app.suggestPanel=false;app.simParameters=false;app.pickingIgnition=false;app.referenceMode=false
    app.dragging=false;app.panning=false;app.pressed = -1;app.hover = -1
    if(step==0){app.tool=1};if(step==2){app.tool=5}
    if(step==0 || step==2){app.experiment.planned=true}
    app.syncScene()
    if(step!=1){app.view.setFireState(Array<Int64>(app.work.project.cells,repeat:0),1)}
    app.focus=step
    app.message=match(step){
        case 0=>app.t("建立森林：重建纯森林，或使用植林/擦除工具调整林地，再确认修改。","Build: create a forest or edit vegetation with Plant/Erase, then confirm.")
        case 1=>app.t("观察森林：查看连通结构，设置起火点，再开始或单步传播。当前为单次火灾。","Observe: inspect connectivity, pick ignition, then start or step. Single-fire trial.")
        case 2=>app.t("设计干预：清理或绘制隔离带，先预览再应用；原始林地保留用于对照。","Intervene: preview clearing or a firebreak, then apply. Baseline forest is retained.")
        case _=>app.t("同条件对照：运行配对评估，比较烧损、保留林地和干预量。","Compare: evaluate paired scenarios for burn loss, retained forest and treatment size.")
    }
}
func controlIcon(id:Int64):String {
    let name=match(id){
        case 55 | 21=>"block/oak_sapling"
        case 56=>"item/spyglass"
        case 57 | 25=>"item/iron_axe"
        case 58 | 60 | 82=>"item/comparator"
        case 59 | 12 | 14 | 15 | 65=>"item/paper"
        case 0 | 42 | 92=>"item/compass_16"
        case 16 | 11 | 13 | 118=>"item/map"
        case 2 | 46 | 90=>"block/oak_sapling"
        case 45 | 83=>"item/flint_and_steel"
        case 40 | 43 | 44 | 64=>"item/clock_00"
        case 41=>"item/repeater"
        case 48 | 81 | 117=>"item/book"
        case 53 | 98=>"item/book"
        case 54 | 84=>"item/knowledge_book"
        case 10 | 116 | 108=>"block/oak_sapling"
        case 20=>"item/map"
        case 22 | 26=>"item/iron_shovel"
        case 23=>"item/water_bucket"
        case 24=>"block/bricks"
        case 27=>"item/oak_sign"
        case 28 | 32 | 61 | 71=>"item/barrier"
        case 119=>"item/iron_shovel"
        case _=>""
    }
    return if(name.isEmpty()){name}else{"textures/"+name+".png"}
}
func workflowTip(app:App,id:Int64):String {
    if(id>=55 && id<=58){return app.t("切换到：","Switch to: ")+workflowName(app,id-55)}
    return match(id){
        case 20=>app.t("选择：查看格子，不修改森林。","Select: inspect a cell without changing the forest.")
        case 21=>app.t("植林：左键拖动选区，确认后修改原始林地。","Plant: drag a selection and confirm to edit baseline forest.")
        case 25=>app.t("清理：选中待移除的植被，预览后应用；原始场地保留。","Clear: preview vegetation removal and apply; baseline stays intact.")
        case 26=>app.t("隔离：绘制不再可燃的处理带，预览后应用。","Firebreak: preview a non-fuel treatment strip, then apply.")
        case 16=>app.t("切换纹理俯视地图与三维场景；滚轮缩放，中键平移。","Switch textured map / 3D; wheel zooms, middle mouse pans.")
        case 0=>app.t("恢复当前视图的默认位置与缩放。","Reset position and zoom of the current view.")
        case 2=>app.t("显示或隐藏树冠，便于看清地面与处理带；H快捷键。","Show/hide canopy to inspect ground and treatment; shortcut H.")
        case 45=>app.t("点击可燃林地设置起火点，不会自动开始燃烧。","Pick a fuel cell for ignition; this does not start the fire.")
        case 46=>app.t("显示当前试验起始林地的连通区域，不是风险预测图。","Show connected fuel regions at trial start, not a risk prediction map.")
        case 54=>app.t("打开研究员终端；/也可呼出快捷输入。","Open the researcher terminal; / opens quick input.")
        case 53=>app.t("文件、示例、显示、声音、实验与智能体设置。","Files, examples, display, sound, experiment and agent settings.")
        case 59=>app.t("完成当前修改后，进入流程下一步。","Finish the current edit, then continue to the next step.")
        case _=>""
    }
}
func drawWorkflowBar(app:App,l:Layout):Unit {
    for(step in 0..4){let id=55+step
        mcButtonAt(app,l.control(id),id,"${step+1}  "+workflowName(app,step),currentWorkflow(app)==step,
            enabled:app.startCell<0 && app.activeField<0)
    }
}
func drawForestPanel(app:App,l:Layout):Unit {
    let graph=app.experiment.analysis;let x=l.panel.x+18.0;let y=l.panel.y
    uiText(app,l,workflowName(app,currentWorkflow(app))+" / ${app.work.project.nx}×${app.work.project.nz}",x,y+18.0)
    uiText(app,l,app.t("可燃覆盖 ${money(Float64(graph.total)*100.0/Float64(app.work.project.cells))}%","Fuel cover ${money(Float64(graph.total)*100.0/Float64(app.work.project.cells))}%"),x,y+50.0,color:Color.rgb(245,221,143))
    uiText(app,l,app.t("最大连通片 ${graph.largest} 格","Largest cluster ${graph.largest} cells"),x,y+78.0)
    uiText(app,l,app.t("${graph.sizes.size} 片 / 左右贯通：","${graph.sizes.size} clusters / L-R span: ")+app.t(if(graph.spansLeftRight(app.work.project.nx,app.work.project.nz)){"是"}else{"否"},if(graph.spansLeftRight(app.work.project.nx,app.work.project.nz)){"Yes"}else{"No"}),x,y+106.0)
    uiText(app,l,app.t("当前工具：","Tool: ")+app.toolName(app.tool),x,y+134.0,color:Color.rgb(245,221,143))
    mcButton(app,l,116,app.t("重建纯森林","New Forest"))
    mcButton(app,l,14,app.t("撤销","Undo"));mcButton(app,l,15,app.t("重做","Redo"))
    mcButton(app,l,30,if(app.erase){app.t("擦除：开","Erase: On")}else{app.t("擦除：关","Erase: Off")})
    mcButton(app,l,31,app.t("应用选区","Apply Edit"));mcButton(app,l,32,app.t("取消选区","Cancel Edit"))
    uiText(app,l,if(app.startCell>=0){app.t("待确认 ${app.selection().size} 格","${app.selection().size} cells pending")}else{app.t("左键拖动 → 预览 → 应用","Drag -> Preview -> Apply")},x,y+402.0,color:Color.rgb(206,211,190))
    let next=currentWorkflow(app)+1
    mcButton(app,l,59,app.t("下一步：","Next: ")+workflowName(app,next))
}
