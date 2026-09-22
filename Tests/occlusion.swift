// Runnable check for the only non-obvious logic in Aloft: deciding when a pinned
// window needs re-raising. Re-states the function under test (WindowList pulls in
// SwiftUI, so it cannot be compiled standalone) and must be kept in sync with
// WindowList.covered.
//
//   swift Tests/occlusion.swift
import CoreGraphics

func covered(_ pinned: Set<CGWindowID>, in stack: [(id: CGWindowID, frame: CGRect)]) -> [CGWindowID] {
    pinned.filter { id in
        guard let index = stack.firstIndex(where: { $0.id == id }) else { return false }
        let frame = stack[index].frame
        return stack[..<index].contains { $0.frame.intersects(frame) }
    }
}

let a = CGRect(x: 0, y: 0, width: 100, height: 100)      // left
let b = CGRect(x: 50, y: 0, width: 100, height: 100)     // overlaps a
let c = CGRect(x: 400, y: 0, width: 100, height: 100)    // disjoint

assert(covered([1], in: [(1, a), (2, b)]) == [])          // frontmost is never covered
assert(covered([2], in: [(1, a), (2, b)]) == [2])         // overlapping window in front
assert(covered([2], in: [(1, c), (2, b)]) == [])          // in front but disjoint
assert(covered([99], in: [(1, a)]) == [])                 // other Space / minimised
assert(Set(covered([2, 3], in: [(1, a), (2, b), (3, c)])) == [2])

print("occlusion: ok")
