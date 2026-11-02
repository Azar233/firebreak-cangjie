package firebreak

import std.collection.ArrayList
import std.fs.{File,Directory,exists}
import stdx.encoding.json.*

func searchCsv(result: PlanSearchResult): String {
    let rows=ArrayList<String>(["candidate_id,kind,added_cells,total_cost,added_cost,training_score,train_eligible,holdout_pass,training_selected,recommended,train_contacts,train_remaining,review_contacts,review_remaining,treatment_mask"])
    for (i in 0..result.entries.size) {
        let e=result.entries[i]; let c=e.candidate
        rows.add("${c.id},${c.kind},${c.added.size},"+numberText(c.cost)+","+numberText(c.deltaCost)+","+numberText(e.score)+
            ",${e.eligible},${e.verified},${result.selected==i},${result.recommended==i},"+numberText(e.training.mean(2))+","+
            numberText(e.training.mean(1))+","+numberText(e.review.mean(2))+","+numberText(e.review.mean(1))+","+maskText(c.treatment))
    }; return String.join(rows.toArray(),delimiter:"\n")+"\n"
}
func searchSamplesCsv(result: PlanSearchResult): String {
    let lines=ArrayList<String>(["candidate_id,dataset,scenario,ignition_cell,seed,weight,burned_cells,cleared_cells,remaining_cells,target_contacts,steps,ignition_blocked"])
    for (index in -1..result.entries.size) { for (review in [false,true]) {
        let a=if (index<0) { if (review) { result.heldout } else { result.current } }
            else { if (review) { result.entries[index].review } else { result.entries[index].training } }
        let id=if (index<0) { -1 } else { result.entries[index].candidate.id }
        for (row in a.rows) {
            let s=row.scenario; let o=row.planned
            lines.add("${id},"+(if (review) { "holdout" } else { "training" })+",${s.id},${s.ignition},${s.seed},"+numberText(s.weight)+
                ",${o.burned},${o.cleared},${o.remaining},${o.contacts},${o.steps},${o.ignitionBlocked}")
        }
    } }; return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func searchScenarioJson(rows: Array<PairedOutcome>): JsonArray {
    let result=JsonArray()
    for (r in rows) {
        let j=JsonObject(); j.put("id",JsonInt(r.scenario.id)); j.put("ignitionCell",JsonInt(r.scenario.ignition)); j.put("seed",JsonInt(r.scenario.seed))
        j.put("weight",JsonString(numberText(r.scenario.weight))); result.add(j)
    }; return result
}
func searchParameters(result: PlanSearchResult): String {
    let j=JsonObject(); j.put("format",JsonString("firebreak-candidates")); j.put("version",JsonInt(1))
    j.put("revision",JsonInt(result.revision)); j.put("wind",JsonString("none")); j.put("spreadRuleVersion",JsonInt(1))
    j.put("training",searchScenarioJson(result.current.rows)); j.put("holdout",searchScenarioJson(result.heldout.rows))
    j.put("contactWeight",JsonInt(CELL_COUNT+1)); j.put("costFloorCny",JsonInt(1))
    j.put("trainingSelectedId",JsonInt(if (result.selected<0) { -1 } else { result.entries[result.selected].candidate.id }))
    j.put("recommendedId",JsonInt(if (result.recommended<0) { -1 } else { result.entries[result.recommended].candidate.id }))
    return j.toJsonString()
}
func searchReport(result: PlanSearchResult,english: Bool): String {
    let p=readProjectText(result.source)
    let head=if (english) { "# Firebreak: Budget-Constrained Candidate Search\n\n" } else { "# 断火线：预算约束候选建议\n\n" }
    let status=if (result.entries.isEmpty()) { if (english) { "No feasible additions in this candidate family." } else { "当前几何候选和约束内无可行新增处理带。" } }
        else if (result.selected<0) { if (english) { "No candidate passed training eligibility." } else { "没有候选通过训练收益条件。" } }
        else if (result.recommended<0) { if (english) { "The training winner failed holdout; no automatic recommendation." } else { "训练入选候选未通过留出复核，不自动推荐。" } }
        else { if (english) { "Training winner ${result.entries[result.recommended].candidate.id} passed holdout; application is manual." }
            else { "训练入选候选 ${result.entries[result.recommended].candidate.id} 通过留出复核；仍须手动应用。" } }
    let table=ArrayList<String>([if (english) { "|Candidate|Type|Added cost (CNY)|Training score|Review contacts|Review remaining|Holdout pass|\n|---|---|---:|---:|---:|---:|---|" }
        else { "|候选|类型|新增费用|训练收益/元|复核目标接触|复核剩余|复核通过|\n|---|---|---:|---:|---:|---:|---|" }])
    for (e in result.entries) { table.add("|${e.candidate.id}|${e.candidate.kind}|${money(e.candidate.deltaCost)}|${money(e.score)}|${money(e.review.mean(2))}|${money(e.review.mean(1))}|${e.verified}|") }
    return head+status+"\n\n"+(if (english) {
        "Revision ${result.revision}; budget CNY ${money(p.budget)}; existing plan CNY ${money(p.cost())}.\n\n"+
        "Compare every candidate against the CURRENT treatment plan, preserving all existing treatment. Type 1: road-adjacent strips (up to 8); type 2: one/two-cell target perimeters; type 3: top 4 articulation cells. Entire invalid candidates are rejected; these finite families do not cover every feasible plan.\n\n"+
        "Training: 8 paired scenarios. Holdout: 8 fixed midpoint-quantile ignitions and seeds offset by 104729. Sets share inputs within each comparison; holdout keys differ from training. They are model tests, not independent observations of real fires.\n\n"+
        "Score = (481 * avoided target-contact cells + net remaining-forest gain) / max(added cost in CNY, 1). Eligibility requires both metrics to be non-worse and at least one to improve, using weighted means. Select by training score only, ties by lower added cost then generation order. Holdout may reject the selected candidate; it never chooses a replacement. No global optimum, greedy combination or real-world probability claim.\n\n"+
        "CURRENT holdout: contacts ${money(result.heldout.mean(2))}, remaining ${money(result.heldout.mean(1))}. candidates.csv keeps all feasible candidates, including failures; samples.csv includes every per-scenario result (-1 denotes current plan). Reconstruct a candidate by assigning its treatment_mask to the frozen site.firebreak. Nothing has been applied by exporting.\n\n"
    } else {
        "revision ${result.revision}；预算 ￥${money(p.budget)}；现有方案 ￥${money(p.cost())}。\n\n"+
        "每个候选相对当前处理方案比较，保留所有已有处理。类型 1：道路邻接处理带（最多 8）；类型 2：目标一格/两格邻域；类型 3：影响最大的 4 个关键连接格。非法候选整笔拒绝，有限几何族不覆盖全部可行方案。\n\n"+
        "训练 8 组配对情景；留出复核 8 组中间分位起火点，seed 偏移 104729。每个对照内部共享输入，复核随机键不同于训练；这不是现实火灾的独立观测。\n\n"+
        "评分 = (481 × 避免目标接触格数 + 净剩余林地增量) / max(新增费用, 1 元)。训练资格要求两项均不变差且至少一项改善，按权重均值计算。仅按训练评分选择，同分先选新增成本低者，再按生成顺序。留出只能否决训练入选项，不用复核集改选赢家。不保证全局最优，不做贪心组合，不声称真实概率。\n\n"+
        "当前方案留出均值：目标接触 ${money(result.heldout.mean(2))}，剩余林地 ${money(result.heldout.mean(1))}。candidates.csv 保留全部可行候选，包括失败项；samples.csv 包含逐样本指标（-1 为当前方案）。将 treatment_mask 赋给冻结的 site.firebreak 可复现对应候选。导出并未应用方案。\n\n"
    })+String.join(table.toArray(),delimiter:"\n")+"\n"
}
func exportSearch(result: PlanSearchResult,parent: String,english: Bool): String {
    let temp=Directory.createTemp(parent).toString()
    try {
        File.writeTo(temp+"/site.firebreak",result.source.toArray()); File.writeTo(temp+"/candidates.csv",searchCsv(result).toArray())
        File.writeTo(temp+"/samples.csv",searchSamplesCsv(result).toArray()); File.writeTo(temp+"/parameters.json",searchParameters(result).toArray())
        File.writeTo(temp+"/report.md",searchReport(result,english).toArray())
        let prefix=parent+"/firebreak-candidates-r${result.revision}"; var path=prefix; var suffix: Int64=1
        while (exists(path)) { path=prefix+"-${suffix}"; suffix++ }
        let src=widePath(temp); let dst=widePath(path); let a=unsafe { acquireArrayRawData(src) }; let b=unsafe { acquireArrayRawData(dst) }
        let ok=unsafe { MoveFileExW(a.pointer,b.pointer,UInt32(8)) }; unsafe { releaseArrayRawData(b); releaseArrayRawData(a) }
        require(ok!=0,"无法发布报告目录，已有目标保留"); return path
    } catch(e: Exception) { throw Exception(e.message+"；未完成的导出保留于 "+temp) }
}
