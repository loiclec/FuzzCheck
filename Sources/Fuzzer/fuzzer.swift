
var array: [Int] = []
/*
@_cdecl("__sanitizer_cov_trace_pc_guard") public func tracepcguard(g: UnsafePointer<UInt32>) {
	let gp = Int(g.pointee)
	if array.count <= gp {
		array += repeatElement(0, count: (gp - array.count)+1)
	}
	array[gp] += 1

	print(array)
}
*/
var rand = Rand.init(seed: 0)

public func analyze <F: FuzzTarget> (_ f: F) {
    for _ in 0 ..< 10 {
        f.run(F.Input(&rand))
    }
}
