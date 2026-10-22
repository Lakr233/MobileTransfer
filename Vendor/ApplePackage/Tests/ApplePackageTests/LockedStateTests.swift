@testable import ApplePackage
import Foundation
import Testing

struct LockedStateTests {
    @Test
    func `concurrent updates preserve every increment`() {
        let state = LockedState(0)
        DispatchQueue.concurrentPerform(iterations: 10000) { _ in
            state.withLock { $0 += 1 }
        }
        #expect(state.withLock { $0 } == 10000)
    }

    @Test
    func `throwing operation releases lock`() {
        enum Failure: Error { case expected }

        let state = LockedState(0)
        #expect(throws: Failure.expected) {
            try state.withLock { value in
                value = 42
                throw Failure.expected
            }
        }
        #expect(state.withLock { $0 } == 42)
    }
}
