// Runnable check for update version comparison. Must be kept in sync with
// Updater.isNewer.
//
//   swift Tests/version.swift
import Foundation

func isNewer(_ candidate: String, than current: String) -> Bool {
    let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
    let b = current.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(a.count, b.count) {
        let left = index < a.count ? a[index] : 0
        let right = index < b.count ? b[index] : 0
        if left != right { return left > right }
    }
    return false
}

assert(isNewer("1.0.1", than: "1.0.0"))
assert(!isNewer("1.0.0", than: "1.0.1"))
assert(!isNewer("1.0.1", than: "1.0.1"))          // same version is not an update
assert(isNewer("1.0.10", than: "1.0.9"))          // the case a string compare gets wrong
assert(isNewer("1.1", than: "1.0.9"))             // shorter but larger
assert(!isNewer("1.0", than: "1.0.0"))            // missing components read as zero
assert(isNewer("2.0.0", than: "1.99.99"))

print("version: ok")
