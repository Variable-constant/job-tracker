import XCTest
import Combine
@testable import JobTracking

final class JobTrackingTests: XCTestCase {
    func testGCDJobTrackerSimple() {
        let tracker = GCDJobTracker<String, Int, Never>(memoizing: [], worker: { key, completion in
            completion(.success(1))
        })

        let expectation = XCTestExpectation(description: "Worker closure should be executed")

        tracker.startJob(for: "key") { result in
            XCTAssertEqual(result, .success(1))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
    
    func testConcurrentJobTrackerSimple() async {
        let tracker = ConcurrentJobTracker<String, Int>(memoizing: [], worker: { key, completion in
            completion(.success(1))
        })

        let expectation = XCTestExpectation(description: "Worker closure should be executed")
        let res = try! await tracker.startJob(for: "key")
        
        XCTAssertEqual(res, 1)
        expectation.fulfill()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCombineJobTrackerSimple() {
        let tracker = CombineJobTracker<String, Int, Never>(memoizing: [], worker: { key, completion in
            completion(.success(1))
        })

        let expectation = XCTestExpectation(description: "Worker closure should be executed")

        let res = tracker.startJob(for: "key")
        
        let cancellable = res.sink { result in
            XCTAssertEqual(result, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
