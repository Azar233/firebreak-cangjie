package firebreak

import std.collection.ArrayList

// Iterative low-link traversal: exact largest-component loss after removing each
// articulation cell, including components outside its DFS tree. No recursion.
func articulationGains(fuel:Array<Bool>,nx:Int64,nz:Int64,graph:Connectivity,cancelled:()->Bool):Array<Int64> {
    let n=fuel.size;let discovered=Array<Int64>(n,repeat:-1);let low=Array<Int64>(n,repeat:0)
    let parent=Array<Int64>(n,repeat:-1);let cursor=Array<Int64>(n,repeat:0);let subtree=Array<Int64>(n,repeat:1)
    let cutSum=Array<Int64>(n,repeat:0);let cutMax=Array<Int64>(n,repeat:0);let cuts=Array<Int64>(n,repeat:0)
    let gains=Array<Int64>(n,repeat:-1);let stack=ArrayList<Int64>();var time:Int64=0
    for(root in 0..n){
        if(cancelled()){return Array<Int64>(n,repeat:-1)}
        if(!fuel[root] || discovered[root]>=0){continue}
        discovered[root]=time;low[root]=time;time++;stack.add(root)
        while(!stack.isEmpty()){
            if(cancelled()){return Array<Int64>(n,repeat:-1)}
            let v=stack[stack.size-1];let adjacent=neighbors(v,nx,nz)
            if(cursor[v]<adjacent.size){
                let w=adjacent[cursor[v]];cursor[v]++
                if(!fuel[w]){continue}
                if(discovered[w]<0){parent[w]=v;discovered[w]=time;low[w]=time;time++;stack.add(w)}
                else if(w!=parent[v]){low[v]=min(low[v],discovered[w])}
            }else{
                stack.remove(at:stack.size-1);let p=parent[v]
                if(p>=0){
                    subtree[p]+=subtree[v];low[p]=min(low[p],low[v])
                    if(low[v]>=discovered[p]){cuts[p]++;cutSum[p]+=subtree[v];cutMax[p]=max(cutMax[p],subtree[v])}
                }
            }
        }
    }
    var second:Int64=0
    for(i in 0..graph.sizes.size){if(i!=graph.largestLabel){second=max(second,graph.sizes[i])}}
    for(v in 0..n){if(fuel[v]){
        let rest=graph.sizes[graph.labels[v]]-1-cutSum[v]
        let pieces=cuts[v]+if(rest>0){1}else{0}
        if(pieces>1){
            let outside=if(graph.labels[v]==graph.largestLabel){second}else{graph.largest}
            gains[v]=graph.largest-max(outside,max(rest,cutMax[v]))
        }
    }}
    return gains
}
