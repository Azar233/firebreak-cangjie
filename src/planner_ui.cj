package firebreak

import sdl.*

func candidateName(app: App,c: PlanCandidate): String {
    match(c.kind) { case 1=>app.t("道路邻接处理带","Road-adjacent strip"); case 2=>app.t("目标周边处理带","Target perimeter"); case _=>app.t("关键连接格清理","Connector-cell clearing") }
}
func drawSuggestions(app: App,l: Layout): Unit {
    let x=l.panel.x+18.0; let y=l.panel.y
    uiText(app,l,app.t("方案建议 / 有限候选","Plan Suggestions / Finite Search"),x,y+18.0)
    if (let Some(result) <- app.searchResult) {
        if (!result.entries.isEmpty()) {
            let entry=result.entries[app.candidateIndex]
            uiText(app,l,app.t("候选 ${app.candidateIndex+1}/${result.entries.size} / 训练8 + 复核8","Candidate ${app.candidateIndex+1}/${result.entries.size} / Train 8 + Review 8"),x,y+44.0)
            uiText(app,l,candidateName(app,entry.candidate),x,y+70.0,color:Color.rgb(245,221,143))
            uiText(app,l,app.t("训练收益/元 ${money(entry.score)}","Training benefit / CNY ${money(entry.score)}"),x,y+96.0)
            uiText(app,l,app.t("复核接触 ${money(result.heldout.mean(2))} → ${money(entry.review.mean(2))}","Review contacts ${money(result.heldout.mean(2))} -> ${money(entry.review.mean(2))}"),x,y+122.0)
            uiText(app,l,app.t("新增 ${entry.candidate.added.size} 格 / ￥${money(entry.candidate.deltaCost)}","Add ${entry.candidate.added.size} cells / CNY ${money(entry.candidate.deltaCost)}"),x,y+148.0)
            let status=if (result.recommended==app.candidateIndex) { app.t("训练入选且复核通过；仅候选内推荐。","Training winner passed holdout; best only within this candidate set.") }
                else if (!entry.verified) { app.t("留出复核未通过；未自动推荐。","Holdout check failed; not automatically recommended.") }
                else { app.t("非训练入选项；仅供手动检查。","Not the training winner; available for manual inspection.") }
            uiText(app,l,status,l.canvas.x+12.0,l.toolbar.y+12.0,color:Color.rgb(245,221,143))
            uiText(app,l,app.t("复核剩余 ${money(result.heldout.mean(1))} → ${money(entry.review.mean(1))} | 总费用 ￥${money(entry.candidate.cost)} / 预算 ￥${money(app.work.project.budget)}",
                "Review remaining ${money(result.heldout.mean(1))} -> ${money(entry.review.mean(1))} | Total CNY ${money(entry.candidate.cost)} / Budget ${money(app.work.project.budget)}"),l.canvas.x+12.0,l.toolbar.y+40.0)
        } else { uiText(app,l,app.t("当前约束内无可行新增候选","No feasible additions in this search"),x,y+56.0); uiText(app,l,app.t("检查预算、禁区与可用几何。","Check budget, exclusions and geometry."),x,y+88.0) }
    } else if (let Some(job) <- app.searchJob) {
        let state=job.progress(); uiText(app,l,app.t("后台评估 ${state.completed}/${state.total}","Background evaluation ${state.completed}/${state.total}"),x,y+56.0)
        uiText(app,l,app.t("保留当前处理，新增有限候选。","Existing treatment is preserved."),x,y+88.0)
    } else {
        uiText(app,l,app.t("道路 / 目标周边 / 关键连接格","Roads / Targets / Connector cells"),x,y+56.0)
        uiText(app,l,app.t("先生成，再预览并手动应用。","Generate, preview, then apply manually."),x,y+88.0)
    }
    mcButton(app,l,70,app.t("生成建议","Generate")); mcButton(app,l,71,app.t("取消搜索","Cancel"))
    mcButton(app,l,72,app.t("上一候选","Previous")); mcButton(app,l,73,app.t("下一候选","Next"))
    mcButton(app,l,74,if (app.candidateVisible) { app.t("隐藏预览","Hide Preview") } else { app.t("地图预览","Preview") })
    mcButtonAt(app,l.control(75),75,app.t("手动应用","Apply Manually"),CONTROLS[app.focus]==75,enabled:app.candidateVisible)
    mcButton(app,l,76,app.t("查看留出情景对照","Compare Holdout Scenarios"))
    mcButton(app,l,78,app.t("导出全部候选指标","Export All Candidate Metrics"))
    mcButton(app,l,77,app.t("返回场地编辑","Back to Site Editor"))
}
