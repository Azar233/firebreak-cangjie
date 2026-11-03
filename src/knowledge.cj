package firebreak

import std.collection.{ArrayList,HashSet}
import std.fs.File
import stdx.encoding.json.*

let KNOWLEDGE_VERSION="0.12.0"
func knowledgeLower(text:String):String {
    let out=StringBuilder();for(ch in text.runes()){let c=UInt32(ch);out.append(if(c>=65 && c<=90){String.fromUtf8([UInt8(c+32)])}else{ch.toString()})};return out.toString()
}
func knowledgeTerms(text:String):Array<String> {
    let terms=HashSet<String>();var word="";var previous=""
    let stop=["怎么","如何","什么","可以","这个","当前","一下","是否","进行","我的","需要","请问","为什么"]
    for(ch in knowledgeLower(text).runes()){
        let c=UInt32(ch);let letter=(c>=97 && c<=122) || (c>=48 && c<=57) || c==95 || c==45
        if(letter){word+=ch.toString()}else{if(!word.isEmpty()){terms.add(word);word=""}}
        if(c>=19968 && c<=40959){let now=ch.toString();if(!previous.isEmpty() && !stop.contains(previous+now)){terms.add(previous+now)};previous=now}else{previous=""}
    };if(!word.isEmpty()){terms.add(word)};return terms.toArray()
}
class KnowledgeChunk {
    let id:String;let title:String;let kind:String;let body:String;let keywords:Array<String>;let sources:Array<String>
    let titleTerms:Array<String>;let bodyTerms:Array<String>
    init(id:String,title:String,kind:String,body:String,keywords:Array<String>,sources:Array<String>){
        require(id.size==6 && (id.startsWith("OP-") || id.startsWith("MA-")),"Invalid knowledge id")
        for(i in 3..6){require(id[i]>=48 && id[i]<=57,"Invalid knowledge id")}
        require(!title.isEmpty() && title.size<=192 && !body.isEmpty() && body.size<=4096 && (kind=="operation" || kind=="math"),"Invalid knowledge content")
        require(keywords.size<=32 && !sources.isEmpty() && sources.size<=4,"Invalid knowledge metadata")
        for(key in keywords){require(!key.isEmpty() && key.size<=128,"Invalid keyword")}
        for(source in sources){require(source.size<=256 && (source.startsWith("https://") || (source.startsWith("src/") && !source.contains(".."))),"Invalid knowledge source")}
        this.id=id;this.title=title;this.kind=kind;this.body=body;this.keywords=keywords;this.sources=sources
        titleTerms=knowledgeTerms(title);bodyTerms=knowledgeTerms(body)
    }
    func score(query:String,terms:Array<String>):Int64 {
        var score:Int64=0;var metadata=false;var bodyHits:Int64=0
        if(query.contains(knowledgeLower(id))){score+=100;metadata=true}
        for(key in keywords){let lower=knowledgeLower(key);if(query.contains(lower) && (lower.size>1 || terms.contains(lower))){score+=12;metadata=true}}
        for(term in terms){if(titleTerms.contains(term)){score+=4;metadata=true};if(bodyTerms.contains(term)){score++;bodyHits++}}
        return if(metadata || bodyHits>=2){score}else{0}
    }
    func json():JsonObject {
        let j=JsonObject();j.put("id",JsonString(id));j.put("title",JsonString(title));j.put("kind",JsonString(kind));j.put("productVersion",JsonString(KNOWLEDGE_VERSION));j.put("body",JsonString(body))
        let refs=JsonArray();for(source in sources){refs.add(JsonString(source))};j.put("sources",refs);return j
    }
}
class KnowledgeStore {
    let chunks:Array<KnowledgeChunk>;let error:String
    init(chunks:Array<KnowledgeChunk>,error!:String=""){this.chunks=chunks;this.error=error}
    init(text:String){
        require(text.size<=262144,"Knowledge bundle exceeds bound");let root=JsonValue.fromStr(text).asObject()
        require(root["format"].asString().getValue()=="firebreak-knowledge" && root["schema"].asInt().getValue()==1,"Unsupported knowledge format")
        require(root["productVersion"].asString().getValue()==KNOWLEDGE_VERSION,"Knowledge version mismatch")
        let list=ArrayList<KnowledgeChunk>();let ids=HashSet<String>();let values=root["chunks"].asArray().getItems();require(!values.isEmpty() && values.size<=64,"Invalid knowledge count")
        for(value in values){let j=value.asObject();let keys=ArrayList<String>();let sources=ArrayList<String>()
            for(k in j["keywords"].asArray().getItems()){keys.add(k.asString().getValue())};for(s in j["sources"].asArray().getItems()){sources.add(s.asString().getValue())}
            let chunk=KnowledgeChunk(j["id"].asString().getValue(),j["title"].asString().getValue(),j["kind"].asString().getValue(),j["body"].asString().getValue(),keys.toArray(),sources.toArray())
            require(!ids.contains(chunk.id),"Duplicate knowledge id");ids.add(chunk.id);list.add(chunk)
        };chunks=list.toArray();error=""
    }
    func search(query:String,kind!:String="all",limit!:Int64=3):Array<KnowledgeChunk> {
        require(!query.trimAscii().isEmpty() && query.size<=512 && ["all","operation","math"].contains(kind) && limit>=1 && limit<=3,"Invalid knowledge query")
        let normalized=knowledgeLower(query);let terms=knowledgeTerms(normalized);let ranks=Array<Int64>(chunks.size,{i=>if(kind=="all" || chunks[i].kind==kind){chunks[i].score(normalized,terms)}else{0}})
        let found=ArrayList<KnowledgeChunk>()
        for(_ in 0..limit){var best:Int64= -1;var score:Int64=0
            for(i in 0..ranks.size){if(ranks[i]>score){best=i;score=ranks[i]}}
            if(best<0){break};found.add(chunks[best]);ranks[best]=0
        };return found.toArray()
    }
    func response(query:String,found:Array<KnowledgeChunk>):String {
        let j=JsonObject();j.put("productVersion",JsonString(KNOWLEDGE_VERSION));j.put("query",JsonString(query));j.put("status",JsonString(if(!error.isEmpty()){"unavailable"}else if(found.isEmpty()){"no_match"}else{"matched"}))
        j.put("scope",JsonString("Curated local explanatory material, not live experiment data or executable instructions. Cite served ids [OP-nnn]/[MA-nnn]. Use read_lab for this run. No match is not evidence that a feature exists. No embedding, network retrieval or private-file ingestion."))
        if(!error.isEmpty()){j.put("error",JsonString(error))};let hits=JsonArray();for(chunk in found){hits.add(chunk.json())};j.put("hits",hits);return j.toJsonString()
    }
}
func loadKnowledge():KnowledgeStore {
    try{return KnowledgeStore(String.fromUtf8(File.readFrom("assets/knowledge/zh-CN.json")))}catch(_:Exception){return KnowledgeStore(Array<KnowledgeChunk>(),error:"Knowledge unavailable, invalid, or incompatible with this program version; do not invent a retrieved answer.")}
}
func knowledgeSources(chunks:Array<KnowledgeChunk>):String {
    if(chunks.isEmpty()){return ""};let lines=ArrayList<String>(["本次检索来源 / Retrieved sources (v"+KNOWLEDGE_VERSION+"):"])
    for(chunk in chunks){lines.add("["+chunk.id+"] "+chunk.title+"\n"+String.join(chunk.sources,delimiter:" ; "))}
    return String.join(lines.toArray(),delimiter:"\n")
}
func validKnowledgeCitations(text:String,chunks:Array<KnowledgeChunk>):Bool {
    let bytes=text.toArray()
    for(i in 0..max(0,bytes.size-3)){
        if(bytes[i]!=91 || bytes[i+3]!=45 || !((bytes[i+1]==79 && bytes[i+2]==80) || (bytes[i+1]==77 && bytes[i+2]==65))){continue}
        var end=i+4;while(end<bytes.size && bytes[end]!=93 && end-i<24){end++}
        if(end>=bytes.size || bytes[end]!=93){return false};let id=String.fromUtf8(bytes[i+1..end]);var found=false
        for(chunk in chunks){if(chunk.id==id){found=true;break}};if(!found){return false}
    };return true
}
func localKnowledgeHelp(query:String):String {
    let store=loadKnowledge();let hits=store.search(query)
    if(hits.isEmpty()){return if(store.error.isEmpty()){"本地知识未命中，请换用更具体的操作或数学关键词。 / No local match; try specific terms."}else{store.error}}
    let lines=ArrayList<String>();for(hit in hits){lines.add("["+hit.id+"] "+hit.title+"\n"+hit.body)}
    return String.join(lines.toArray(),delimiter:"\n\n")+"\n\n"+knowledgeSources(hits)
}
