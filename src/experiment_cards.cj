package firebreak

import sdl.*
import std.math.{abs,ceil}
import std.collection.ArrayList

class ExperimentCard <: Resource {
    let title:String;let details:String;let revision:Int64;let runId:Int64;let texture:Texture
    var closed=false
    init(title:String,details:String,revision:Int64,runId:Int64,texture:Texture){this.title=title;this.details=details;this.revision=revision;this.runId=runId;this.texture=texture}
    public func close():Unit {if(!closed){closed=true;texture.close()}}
    public func isClosed():Bool {closed}
}
func cardLine(pixels:Array<Color>,w:Int64,h:Int64,x0:Int64,y0:Int64,x1:Int64,y1:Int64,color:Color):Unit {
    let steps=max(1,max(abs(x1-x0),abs(y1-y0)))
    for(i in 0..steps+1){let x=x0+(x1-x0)*i/steps;let y=y0+(y1-y0)*i/steps;if(x>=0 && x<w && y>=0 && y<h){pixels[y*w+x]=color}}
}
func cardTexture(app:App,pixels:Array<Color>,w:Int64,h:Int64):Texture {
    var texture:?Texture=None
    try(surface=Surface.create(Int32(w),Int32(h))){surface.writeRgbaRows(0,h,{x,y=>pixels[y*w+x]});texture=Some(app.assets.r.textureFromSurface(surface))}
    return texture.getOrThrow()
}
func pipelineCurveCard(app:App,result:PipelineResult,long:Bool):ExperimentCard {
    let w:Int64=384;let h:Int64=192;let pixels=Array<Color>(w*h,repeat:Color.rgb(34,40,32));let blue=Color.rgb(95,210,241);let green=Color.rgb(179,232,106)
    for(i in 0..5){cardLine(pixels,w,h,16,12+i*40,368,12+i*40,Color.rgb(72,83,66));cardLine(pixels,w,h,16+i*88,12,16+i*88,172,Color.rgb(72,83,66))}
    if(!long){
        let cells=readProjectText(result.scan.source).cells
        for(i in 0..result.scan.points.size){let p=result.scan.points[i];let x=16+Int64(p.probability*352.0)
            cardLine(pixels,w,h,x,172-Int64(p.interval[0]*160.0),x,172-Int64(p.interval[1]*160.0),blue)
            if(i>0){let previous=result.scan.points[i-1];let px=16+Int64(previous.probability*352.0)
                cardLine(pixels,w,h,px,172-Int64(previous.frequency()*160.0),x,172-Int64(p.frequency()*160.0),blue)
                cardLine(pixels,w,h,px,172-Int64(previous.largest/Float64(cells)*160.0),x,172-Int64(p.largest/Float64(cells)*160.0),green)
            }
        }
    }else{
        let run=result.longRun
        for(policy in 0..2){for(i in 1..run.spec.drives){cardLine(pixels,w,h,16+352*(i-1)/max(1,run.spec.drives-1),172-Int64(run.trace[policy][i-1]*160.0),16+352*i/max(1,run.spec.drives-1),172-Int64(run.trace[policy][i]*160.0),if(policy==0){blue}else{green})}}
    }
    let p=readProjectText(result.scan.source)
    let details=if(long){app.t("首seed覆盖轨迹：蓝自然/绿抑制；汇总使用全部seed，预热排除。","First-seed cover: blue natural/green suppressed; summary uses all seeds, excluding warmup.")+app.t(" 横轴观测轮/纵轴覆盖0–100%。"," x: measured round; y: cover 0-100%.")+" g=${money(result.longRun.spec.growth)} f=${money(result.longRun.spec.lightning)} T=${result.longRun.spec.drives} n=${result.longRun.spec.samples}"}else{app.t("横轴p 0–1；纵轴0–100%。蓝贯通频次+Wilson，绿最大簇/全图；不是pc区间。","p 0-1; y 0-100%. Blue spanning+Wilson; green largest/grid; not pc CI.")+" n=${result.scan.samples}"}
    return ExperimentCard(app.t(if(long){"长期演化覆盖轨迹"}else{"密度扫描"},if(long){"Long-run cover"}else{"Density scan"}),"${p.nx}x${p.nz} seed=${p.seed}; "+details,result.revision,result.id,cardTexture(app,pixels,w,h))
}
func pipelineMapCard(app:App,result:PipelineResult):ExperimentCard {
    let w:Int64=384;let h:Int64=192;let pixels=Array<Color>(w*h,repeat:Color.rgb(34,40,32))
    for(policy in 0..2){let p=result.plans.preview(0,if(policy==0){0}else{result.spec.policy});let scene=Scene(nx:p.nx,nz:p.nz,demo:false);populateScene(scene,p,true)
        let mapW=max(1,min(188,Int64(188.0*p.aspect)));let mapH=max(1,min(188,Int64(Float64(mapW)/p.aspect)));let left=policy*192+(192-mapW)/2;let top=(192-mapH)/2
        try(view=VoxelView(scene,app.assets)){
            for(y in 0..mapH){for(x in 0..mapW){let cell=min(p.nz-1,y*p.nz/mapH)*p.nx+min(p.nx-1,x*p.nx/mapW)
                var color=view.color(overheadRay(scene,(Float64(x)+0.5)/Float64(mapW),(Float64(y)+0.5)/Float64(mapH)))
                if(policy==1 && p.treatment[cell]!=0){color=color.lerp(Color.rgb(239,190,61),0.7)};pixels[(top+y)*w+left+x]=color
            }}
        }
    }
    let seed=readProjectText(result.plans.source).seed
    return ExperimentCard(app.t("结构干预样本","Structural sample"),app.t("左未处理，右为所选策略；金色为清理格，尚未应用。","Left baseline, right selected policy; gold marks clearing, not applied.")+" p=${money(result.plans.probability)} seed=${seed} policy=${result.spec.policy} k=${result.plans.dose}",result.revision,result.id,cardTexture(app,pixels,w,h))
}
func publishPipelineCards(app:App,result:PipelineResult):Unit {
    let cards=ArrayList<ExperimentCard>()
    try{cards.add(pipelineCurveCard(app,result,false));cards.add(pipelineMapCard(app,result));cards.add(pipelineCurveCard(app,result,true))}
    catch(e:Exception){for(card in cards){card.close()};throw e}
    for(card in cards){app.terminal.appendCard(card)}
}
func cardRowCount(card:ExperimentCard,width:Float32,scale:Float32,lineHeight:Float32):Int64 {Int64(ceil(Float64(min(width,400.0*scale)*card.texture.height/card.texture.width/lineHeight)))}
func drawExpandedCard(app:App,l:Layout,card:ExperimentCard):Unit {
    let r=app.assets.r;let stale=card.revision!=app.work.revision;r.fill(Rect(0.0,0.0,l.width,l.height),Color.rgba(0,0,0,235))
    studyText(app,card.title+" / run ${card.runId} / revision ${card.revision}"+if(stale){app.t(" / 已失效·历史图"," / STALE historical image")}else{""},40.0,30.0,l.width-80.0)
    let width=min(l.width-80.0,(l.height-190.0)*card.texture.width/card.texture.height);let height=width*card.texture.height/card.texture.width
    r.textureStyled(card.texture,Rect((l.width-width)/2.0,80.0,width,height),style:TextureStyle(sampling:TextureScaleMode.Nearest))
    studyText(app,card.details,40.0,l.height-80.0,l.width-80.0);studyText(app,app.t("点击或Esc返回对话","Click or Esc to return"),40.0,l.height-45.0,l.width-80.0)
}
