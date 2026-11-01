package firebreak

import sdl.*
import std.fs.{File,Directory,exists}
import std.collection.ArrayList
import stdx.encoding.json.*

func evaluationCsv(result: EvaluationResult): String {
    let lines=ArrayList<String>(["scenario,ignition_cell,seed,weight,mode,burned_cells,cleared_cells,remaining_cells,target_contact_cells,steps,ignition_blocked"])
    for (row in result.rows) { for (planned in [false,true]) {
        let v=if (planned) { row.planned } else { row.baseline }
        lines.add("${row.scenario.id},${row.scenario.ignition},${row.scenario.seed},"+numberText(row.scenario.weight)+","+
            (if (planned) { "planned" } else { "baseline" })+",${v.burned},${v.cleared},${v.remaining},${v.contacts},${v.steps},${v.ignitionBlocked}")
    } }
    return String.join(lines.toArray(),delimiter:"\n")+"\n"
}
func evaluationParameters(result: EvaluationResult): String {
    let p=readProjectText(result.projectText); let j=JsonObject()
    j.put("format",JsonString("firebreak-evaluation")); j.put("version",JsonInt(1)); j.put("revision",JsonInt(result.revision))
    j.put("wind",JsonString("none")); j.put("spreadRuleVersion",JsonInt(1))
    j.put("spreadProbability",JsonString(numberText(p.spreadProbability))); j.put("burnSteps",JsonInt(p.burnSteps))
    let scenarios=JsonArray()
    for (row in result.rows) {
        let s=row.scenario; let value=JsonObject()
        value.put("id",JsonInt(s.id)); value.put("ignitionCell",JsonInt(s.ignition)); value.put("seed",JsonInt(s.seed))
        value.put("weight",JsonString(numberText(s.weight))); scenarios.add(value)
    }
    j.put("scenarios",scenarios); return j.toJsonString()
}
func evaluationReport(result: EvaluationResult,english!: Bool=false): String {
    if (english) { return englishEvaluationReport(result) }
    let p=readProjectText(result.projectText)
    return "# 断火线：多情景方案比较\n\n"+
        "场地快照：site.firebreak；revision ${result.revision}；样本 ${result.rows.size} 组。\n\n"+
        "|加权均值（格）|原始场地|处理方案|\n|---|---:|---:|\n"+
        "|模拟烧损|${money(result.mean(false,0))}|${money(result.mean(true,0))}|\n"+
        "|规划清理|0|${money(result.mean(true,3))}|\n"+
        "|剩余植被|${money(result.mean(false,1))}|${money(result.mean(true,1))}|\n"+
        "|目标接触|${money(result.mean(false,2))}|${money(result.mean(true,2))}|\n\n"+
        "目标发生接触的样本：原始 ${result.exposedSamples(false)}/${result.rows.size}，方案 ${result.exposedSamples(true)}/${result.rows.size}。"+
        "方案烧损或目标接触较大的样本 ${result.worseSamples()} 组；全部样本均保留。\n\n"+
        (if (p.metersWide>0.0) { "每格 ${money(p.cellArea())} 平方米；计划处理 ${p.count(p.treatment)} 格，费用 ￥${money(p.cost())}，预算 ￥${money(p.budget)}。\n\n" }
         else { "未标定：平方米与费用不可用。\n\n" })+
        "计算：各指标使用 sum(weight × value) / sum(weight)。CSV 保留逐样本整数与原始权重，汇总表显示两位小数。\n\n"+
        "情景生成：优先使用已设置的可燃起火格，再取林地索引分位点，至多四个不同起火位置；"+
        "循环这些位置并递增 seed，等权，不是地理均匀抽样或独立真实观测。参数以 parameters.json 为准。\n\n"+
        "规则 v1：四邻接、无风、同步离散传播、有限燃烧；基线与方案共享情景和按步/传播边生成的随机输入。"+
        "处理格不再可燃；若同一起火格已处理，方案起火被阻止，不另换起火点。\n\n"+
        "目标接触指保护格自身或四邻接出现燃烧的累计保护格数，不等同于建筑损失。"+
        "规划清理与烧损分开；原始林地 = 清理 + 烧损 + 剩余。\n\n"+
        "baseline.png / planned.png 仅为情景 1 的最终纹理俯视，不是全样本风险图。"+
        "样本比例不是现实火灾概率，步数不是现实秒数；本工具用于教学与方案试算，尚未用真实火灾数据标定。\n"
}
func saveEvaluationMap(view: VoxelView,aspect: Float64,path: String): Unit {
    let width: Int64=384; let height=max(1,Int64(Float64(width)/aspect)); view.topDown=true
    try (surface=Surface.create(Int32(width),Int32(height))) {
        view.rows(surface,Camera(),Rect(0.0,0.0,Float32(width),Float32(height)),width,height,0,height); surface.savePng(path)
    }
}
func exportEvaluation(result: EvaluationResult,assets: Assets,parent: String,english!: Bool=false): String {
    require(!result.rows.isEmpty(),"没有完整评估结果")
    let temp=Directory.createTemp(parent).toString()
    try {
        File.writeTo(temp+"/site.firebreak",result.projectText.toArray())
        File.writeTo(temp+"/metrics.csv",evaluationCsv(result).toArray())
        File.writeTo(temp+"/parameters.json",evaluationParameters(result).toArray())
        File.writeTo(temp+"/report.md",evaluationReport(result,english:english).toArray())
        try (pair=ComparisonView(result,assets)) {
            pair.seek(pair.maxStep)
            saveEvaluationMap(pair.baseline,pair.aspect,temp+"/baseline.png")
            saveEvaluationMap(pair.planned,pair.aspect,temp+"/planned.png")
        }
        let prefix=parent+"/firebreak-r${result.revision}"; var path=prefix; var suffix: Int64=1
        while (exists(path)) { path=prefix+"-${suffix}"; suffix++ }
        let src=widePath(temp); let dst=widePath(path)
        let a=unsafe { acquireArrayRawData(src) }; let b=unsafe { acquireArrayRawData(dst) }
        let ok=unsafe { MoveFileExW(a.pointer,b.pointer,UInt32(8)) }
        unsafe { releaseArrayRawData(b); releaseArrayRawData(a) }
        require(ok!=0,"无法发布报告目录，已有目标保留")
        return path
    } catch(e: Exception) { throw Exception(e.message+"；未完成的导出保留于 "+temp) }
}
func englishEvaluationReport(result: EvaluationResult): String {
    let p=readProjectText(result.projectText)
    return "# Firebreak: Paired Scenario Evaluation\n\n"+
        "Frozen site: site.firebreak. Revision ${result.revision}; ${result.rows.size} paired scenarios.\n\n"+
        "|Weighted mean (cells)|Baseline|Treatment|\n|---|---:|---:|\n"+
        "|Burned|${money(result.mean(false,0))}|${money(result.mean(true,0))}|\n"+
        "|Planned clearing|0|${money(result.mean(true,3))}|\n"+
        "|Remaining forest|${money(result.mean(false,1))}|${money(result.mean(true,1))}|\n"+
        "|Target contact|${money(result.mean(false,2))}|${money(result.mean(true,2))}|\n\n"+
        "Samples with target contact (unweighted): baseline ${result.exposedSamples(false)}/${result.rows.size}; treatment ${result.exposedSamples(true)}/${result.rows.size}. "+
        "Samples with greater treatment burn loss or target contact: ${result.worseSamples()}. All samples are retained.\n\n"+
        (if (p.metersWide>0.0) { "Cell area: ${money(p.cellArea())} m2; treated: ${p.count(p.treatment)} cells; cost CNY ${money(p.cost())}; budget CNY ${money(p.budget)}.\n\n" }
         else { "Site is uncalibrated: physical area and cost are unavailable.\n\n" })+
        "Aggregation: sum(weight * value) / sum(weight). Tables show two decimals; metrics.csv retains integer sample metrics and exact weights.\n\n"+
        "Scenarios: use the configured fuel-cell ignition first, then forest-index quantiles, up to four distinct ignition sites. Cycle these sites and increment seed with equal weights. "+
        "This is not geographically uniform sampling or independent real-world observation. Exact inputs are in parameters.json.\n\n"+
        "Rule v1: four neighbors, no wind, synchronous discrete spread, finite burn duration. Each pair shares ignition, seed, parameters and step/directed-edge random inputs. "+
        "Treatment removes fuel; a treated ignition is recorded as prevented, without resampling.\n\n"+
        "Target contact counts protected cells that burn or have a burning four-neighbor; it is not building damage. Baseline forest = cleared + burned + remaining.\n\n"+
        "baseline.png and planned.png show only scenario 1 at its final state, not aggregate risk. Sample rates are not real-world fire probabilities; steps are not seconds. "+
        "This educational planning prototype has not been calibrated against real fires.\n"
}
