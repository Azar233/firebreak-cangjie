package firebreak

// Only known model diagnostics are translated. User paths and site annotations remain intact.
let MODEL_MESSAGES=[
    ["候选不能覆盖已有处理方案","Candidate cannot replace existing treatment"],
    ["候选没有新增处理格","Candidate adds no treatment cells"],
    ["请先标定场地宽度再生成建议","Calibrate site width before searching for suggestions"],
    ["缺少完整候选评估","Complete candidate assessment is missing"],
    ["候选搜索已取消","Candidate search cancelled"],
    ["非法连通网格","Invalid connectivity grid"],
    ["保护目标尺寸不匹配","Target mask dimensions do not match"],
    ["起火格超出网格","Ignition is outside the grid"],
    ["非法评估情景","Invalid evaluation scenario"],
    ["评估样本数须为 1 至 64","Sample count must be 1-64"],
    ["原始场地没有可燃林地，无法生成起火情景","Baseline has no fuel cells for ignition scenarios"],
    ["评估指标不守恒","Evaluation metrics do not conserve baseline fuel"],
    ["情景集合不能为空或超过 64","Scenario set must contain 1-64 entries"],
    ["情景起火点不可燃或 id 重复","Scenario ignition has no baseline fuel or duplicate id"],
    ["非法传播网格","Invalid spread grid"],
    ["请在当前模式的可燃林地上设置起火点","Choose ignition on fuel in the current mode"],
    ["传播概率须在 0 至 1 之间","Spread probability must be 0-1"],
    ["燃烧持续步或 seed 超出范围","Burn duration or seed is out of range"],
    ["回放位置超出已有快照","Replay position is outside the available snapshots"],
    ["非法起火点或传播概率","Invalid ignition or spread probability"],
    ["燃烧步数须为 1 至 8，seed 须为 0 至 2147483647","Burn duration must be 1-8; seed must be 0-2147483647"],
    ["底图宽高比超出 1:20 至 20:1","Image aspect ratio must be between 1:20 and 20:1"],
    ["场地宽度须在 0 至 100000 米内","Site width must be 0-100000 meters"],
    ["费用参数超出范围","Cost parameter is out of range"],
    ["非法格子数据","Invalid cell data"],
    ["处理带与地类、保护目标或禁区冲突","Treatment conflicts with land, protected targets or exclusions"],
    ["未标定的场地不能保存收费处理方案","Calibrate the site before applying a priced treatment"],
    ["方案超过预算","Plan exceeds budget"],
    ["底图或来源信息过大","Reference image or source text is too large"],
    ["格子数量不匹配","Cell count does not match"],
    ["项目文件过大","Project file is too large"],
    ["不支持的项目格式或版本","Unsupported project format or version"],
    ["回放历史达到内存上限，请重置试验或缩小网格","Replay memory limit reached; reset the trial or use a smaller grid"],
    ["不支持的传播规则版本","Unsupported spread rule version"],
    ["底图上限 8 MB","Reference image limit: 8 MB"],
    ["底图尺寸与项目不符","Reference dimensions do not match the project"],
    ["非法文件路径","Invalid file path"],
    ["保存临时文件已存在，请先检查：","Recovery file already exists; inspect it first: "],
    ["无法安全替换目标文件；原文件保留","Cannot safely replace the target; original file preserved"],
    ["选区超出场地","Selection is outside the site"],
    ["选区含禁区或保护目标，整笔操作未应用","Selection includes exclusions or targets; stroke not applied"],
    ["没有完整评估结果","No complete evaluation result"],
    ["无法发布报告目录，已有目标保留","Cannot publish report directory; existing target preserved"]
]
func localizedError(message: String,english: Bool): String {
    if (!english) { return message }
    for (row in MODEL_MESSAGES) {
        if (message.startsWith(row[0])) { return row[1]+message[row[0].size..].replace("；未完成的导出保留于 ","; incomplete export retained at ") }
    }
    return message.replace("；未完成的导出保留于 ","; incomplete export retained at ")
}
