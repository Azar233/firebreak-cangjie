package firebreak

import std.collection.ArrayList

func neighbors(i: Int64,nx: Int64,nz: Int64): Array<Int64> {
    let result=ArrayList<Int64>()
    if (i%nx>0) { result.add(i-1) }; if (i%nx<nx-1) { result.add(i+1) }
    if (i/nx>0) { result.add(i-nx) }; if (i/nx<nz-1) { result.add(i+nx) }
    return result.toArray()
}
func fuelMask(p: Project,planned: Bool): Array<Bool> {
    Array<Bool>(p.cells,{i => p.fuel(i,planned:planned)>0.0})
}
class Connectivity {
    let labels: Array<Int64>
    let sizes=ArrayList<Int64>()
    var largest: Int64=0
    var largestLabel: Int64 = -1
    var total: Int64=0
    var path=Array<Int64>()
    init(fuel: Array<Bool>,nx: Int64,nz: Int64,targets!: Array<Bool>=Array<Bool>(),ignition!: Int64 = -1) {
        require(nx>0 && nz>0 && nx*nz==fuel.size,"非法连通网格")
        require(targets.isEmpty() || targets.size==fuel.size,"保护目标尺寸不匹配")
        require(ignition>= -1 && ignition<fuel.size,"起火格超出网格")
        labels=Array<Int64>(fuel.size,repeat:-1)
        let queue=ArrayList<Int64>()
        for (i in 0..fuel.size) {
            if (!fuel[i] || labels[i]>=0) { continue }
            queue.clear(); queue.add(i); labels[i]=sizes.size
            var at: Int64=0
            while (at<queue.size) {
                let cell=queue[at]; at++
                for (n in neighbors(cell,nx,nz)) { if (fuel[n] && labels[n]<0) { labels[n]=sizes.size; queue.add(n) } }
            }
            sizes.add(queue.size); total+=queue.size
            if (queue.size>largest) { largest=queue.size; largestLabel=sizes.size-1 }
        }
        if (ignition<0 || !fuel[ignition] || targets.isEmpty()) { return }
        let parent=Array<Int64>(fuel.size,repeat:-1)
        queue.clear(); queue.add(ignition); parent[ignition]=ignition
        var at: Int64=0; var found: Int64 = -1
        while (at<queue.size && found<0) {
            let cell=queue[at]; at++
            if (targets[cell]) { found=cell; break }
            for (n in neighbors(cell,nx,nz)) {
                if (targets[n]) { found=cell; break }
                if (fuel[n] && parent[n]<0) { parent[n]=cell; queue.add(n) }
            }
        }
        if (found>=0) {
            let route=ArrayList<Int64>(); var cell=found
            while (true) { route.add(cell); if (cell==ignition) { break }; cell=parent[cell] }
            path=Array<Int64>(route.size,{i => route[route.size-1-i]})
        }
    }
    func spansLeftRight(nx: Int64,nz: Int64): Bool {
        for (z in 0..nz) {
            let label=labels[z*nx]; if (label<0) { continue }
            for (right in 0..nz) { if (labels[right*nx+nx-1]==label) { return true } }
        }; return false
    }
}
