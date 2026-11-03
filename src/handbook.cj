package firebreak

import sdl.*
import std.collection.ArrayList

let BOOK_PAGES: Int64=8
func bookTitle(app: App): String {
    let zh=["为什么做《断火线》","非线性：局部与整体","渗流：森林能否连通","临界点与相变","本软件怎样模拟火势","这就是自组织临界性吗？","怎样公平比较方案","从知识走向规划"]
    let en=["Why Firebreak?","Nonlinear Responses","Percolation & Connectivity","Critical Points & Transitions","Our Fire Model","Self-Organized Criticality?","Fair Plan Comparisons","From Theory to Planning"]
    return app.t(zh[app.bookPage],en[app.bookPage])
}
func bookBody(app: App): String {
    let zh=[
        "森林怎样从零散小片连成整体？清理少量关键位置，能否阻断大范围传播？\n\n断火线把森林变成可编辑的方格沙盘。建立森林、观察连通与火势、设计干预，再在相同条件下比较结果。\n\n目标是用数学解释结构变化和干预效果。当前支持单次火灾，尚无持续生长或随机落雷。",
        "非线性意味着：改变输入后，整体结果未必按相同比例变化。\n\n想象两片森林仅靠一格窄桥相连。处理普通边缘格可能只影响局部；处理窄桥却可能切断两大片区域。位置和连接结构都很重要。\n\n火势又会逐步改变可燃状态。这种耦合过程不能只把每棵树的结果简单相加；也不能仅凭复杂画面就断言出现混沌。",
        "渗流研究的是：局部可以通行的位置或连接，能否组成跨越系统的通路。\n\n理想格点模型中，每格独立地以概率 p 被占据，相邻占据格连成簇。可以观察最大簇，或是否从一边贯通另一边。\n\n在这里，林地格是可燃位置，道路和处理带可以切断通路。可燃通路表示火有传播的可能，不表示它一定烧过去。",
        "理想无限系统中，贯通行为可在临界占据概率附近发生质的改变。这是渗流相变的核心。\n\n阈值取决于网络结构、邻接方式，以及研究的是格点还是连接。不能把某个理想模型的数值直接套到真实森林。\n\n临界观察可扫描多个密度与seed，显示有限网格的50%贯通经验括区。误差线是逐点贯通频次区间，不是精确临界值或临界值的置信区间。",
        "规则 v1：每步只向四邻接可燃格传播；每次尝试的概率是 q。燃烧持续有限步，随后燃尽。\n\n理想独立尝试下，若有 k 个燃烧邻居，一步内被点燃的概率为：\n1 - (1 - q)^k\n\n这里的 q 是传播参数，不是前面格点占据概率 p。模型当前无风、无飞火；播放速度也不等于现实时间。",
        "自组织临界性讨论某些受缓慢驱动、能耗散的系统如何自行接近临界状态。\n\n经典沙堆会不断加沙；达到局部阈值时向邻居分配，可能引发连锁雪崩，边界让沙流失。\n\n本软件没有持续的森林生长与点火驱动机制，所以不把单次森林火灾模拟称为自组织临界系统。渗流临界性与自组织临界性需要区分。",
        "同一场地，设置同样的起火位置、seed 与模型参数，再分别计算基线和处理方案。这样才能更清楚地比较处理的影响。\n\n原始林地 = 规划清理 + 模拟烧损 + 剩余植被。不能把主动清理算成火灾收益而忽略其代价。\n\n单次火势对照中，右栏汇总全部样本；并排回放只展示情景 1。目标接触不等于建筑损坏，样本比例不是现实火灾概率。",
        "按四步操作：建立森林，观察连通与单次传播，设计清理或隔离带，最后运行同条件对照。\n\n观察森林中的临界观察可扫描密度。固定清理格数，对照随机疏林、连接优先与中线条带；预览实际样本，确认后应用。保留不奏效的样本，再导出数据。\n\n文件与高级标注位于Esc菜单。本项目用于教学和方案试算，尚未以真实火灾校准。"
    ]
    let en=[
        "How do small forest patches become one connected system? Can clearing a few key cells interrupt widespread fire?\n\nBuild a forest, observe connectivity and spread, design an intervention, then compare matched scenarios.\n\nThe aim is to explain structural changes and treatment effects. The current model supports single fires, without ongoing growth or random lightning.",
        "A nonlinear response need not change in proportion to its input.\n\nImagine two forest patches joined by one narrow bridge. Clearing an ordinary edge cell may have a local effect; clearing the bridge may disconnect two large regions. Location and connectivity matter.\n\nFire also changes the fuel state as it spreads. Complex-looking behavior alone is not evidence of chaos.",
        "Percolation asks whether locally passable sites or links form a path across a system.\n\nIn ideal site percolation, each site is occupied independently with probability p. Adjacent occupied sites form clusters. We can study the largest cluster or a boundary-to-boundary path.\n\nHere forest cells are fuel; roads and treatments can interrupt paths. A fuel path allows spread but does not guarantee it.",
        "An infinite system may acquire a spanning cluster near a critical occupation probability: a percolation transition.\n\nThe threshold depends on network geometry and the site/bond rule. It cannot be assigned directly to a real forest.\n\nScan densities and seeds in Critical region. The 50% spanning bracket is empirical for this finite grid. Pointwise frequency intervals are not critical-point intervals.",
        "Rule v1 spreads fire to four-neighbor fuel cells. Each attempt has probability q. A cell burns for a finite number of steps, then burns out.\n\nFor ideal independent attempts from k burning neighbors, the one-step ignition probability is:\n1 - (1 - q)^k\n\nThis spread parameter q differs from site occupation p. There is no wind or spotting. Playback speed is not physical time.",
        "Self-organized criticality concerns how some slowly driven, dissipative systems approach a critical state.\n\nIn a classic sandpile, grains are added; local threshold events distribute grains to neighbors, triggering avalanches. Boundaries allow dissipation.\n\nOur single-fire model lacks ongoing forest growth and ignition driving. We do not label it a self-organized critical system merely because fire cascades.",
        "Use the same site, ignitions, seeds and parameters for baseline and treatment.\n\nBaseline forest = planned clearing + burned + remaining. Clearing is an intervention cost, not fire damage.\n\nIn single-fire comparison, the sidebar summarizes all scenarios; replay shows scenario 1. Target contact is not building damage. Sample rates are not real fire probabilities.",
        "Build a forest, observe connectivity and fire, design a treatment, then compare matched scenarios.\n\nOpen Critical region under Observe Forest. Scan density and compare random, connector and center-strip clearing at equal cell counts. Preview before applying. Keep unsuccessful samples and export data.\n\nEsc contains files and advanced annotations. This educational model has no real-fire calibration."
    ]
    return app.t(zh[app.bookPage],en[app.bookPage])
}
func bookLines(font: PixelFont,text: String,width: Float32,scale: Float32): Array<String> {
    let lines=ArrayList<String>()
    for (paragraph in text.split("\n")) {
        var line=""
        for (word in paragraph.split(" ")) {
            if (word.isEmpty()) { continue }
            let candidate=if (line.isEmpty()) { word } else { line+" "+word }
            if (font.measure(candidate,scale:scale)<=width) { line=candidate; continue }
            if (!line.isEmpty()) { lines.add(line); line="" }
            for (ch in word.runes()) {
                let next=ch.toString()
                if (!line.isEmpty() && font.measure(line+next,scale:scale)>width) { lines.add(line); line="" }
                line+=next
            }
        }
        lines.add(line)
    }
    return lines.toArray()
}
func drawHandbook(app: App,m: MenuLayout,pixelRatio: Float32): Unit {
    let b=m.book; let f=app.font; let r=app.assets.r
    app.assets.blit("textures/gui/book.png",b,source:Some(Rect(20.0,0.0,146.0,182.0)))
    let ink=Color.rgb(53,40,28)
    let title=bookTitle(app); let scale=min(m.scale,(b.w-88.0*m.scale)/max(1.0,f.measure(title)))
    f.draw(title,b.x+44.0*m.scale,b.y+38.0*m.scale,color:ink,scale:scale,shadow:false,snap:true,pixelRatio:pixelRatio)
    let body=m.bookBodyBox(); let lines=bookLines(f,bookBody(app),body.w,m.scale)
    r.pushClip(body)
    for (i in 0..lines.size) { f.draw(lines[i],body.x,body.y+Float32(i)*22.0*m.scale,color:ink,scale:m.scale,shadow:false,snap:true,pixelRatio:pixelRatio) }
    r.popClip()
    f.center("${app.bookPage+1} / ${BOOK_PAGES}",m.bookAt(165.0,488.0,108.0,30.0),color:ink,scale:m.scale,shadow:false,snap:true,pixelRatio:pixelRatio)
    for (id in [96,97]) {
        let box=m.box(id,page:6); let enabled=app.menuEnabled(id)
        app.assets.blit("textures/gui/book.png",Rect(box.x+m.scale,box.y+9.0*m.scale,46.0*m.scale,26.0*m.scale),
            source:Some(Rect(if (enabled && (app.hover==id || app.pressed==id)) { 23.0 } else { 0.0 },if (id==97) { 192.0 } else { 205.0 },23.0,13.0)),
            tint:if (enabled) { Color.rgb(255,255,255) } else { Color.rgb(130,130,130) })
        if (enabled && app.menuFocus==id) { r.strokeRect(box,Pen(width:2.0,color:ink)) }
    }
    mcButtonAt(app,m.box(88,page:6),88,app.t("返回菜单","Back to Menu"),app.menuFocus==88,textScale:m.scale,pixelRatio:pixelRatio,snapText:true)
    f.center(app.t("← → 翻页 / Esc 返回","Left / Right: Turn page / Esc: Back"),m.bookAt(0.0,612.0,438.0,24.0),scale:m.scale,snap:true,pixelRatio:pixelRatio)
}
