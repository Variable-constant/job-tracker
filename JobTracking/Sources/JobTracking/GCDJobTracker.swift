//
//  File.swift
//  
//
//  Created by Andrey Karpenko on 25.12.2022.
//

import Foundation

public class GCDJobTracker<Key: Hashable, Output, Failure: Error>: CallbackJobTracking {
    private let memoizing: MemoizationOptions
    private let worker: JobWorker<Key, Output, Failure>
    private let execQueue: DispatchQueue
    private let syncQueue: DispatchQueue
    private var cache: [Key: StoredData<Output, Failure>] = [:]
    
    required public init(memoizing: MemoizationOptions, worker: @escaping JobWorker<Key, Output, Failure>) {
        self.memoizing = memoizing
        self.worker = worker
        self.execQueue = DispatchQueue(label: "gcdJobTrackerExecutionQueue", attributes: .concurrent)
        self.syncQueue = DispatchQueue(label: "gcdJobTrackerSyncQueue")
    }
    
    public func startJob(for key: Key, completion: @escaping (Result<Output, Failure>) -> Void) {
        syncQueue.sync {
            guard memoizing.contains(.started) else {
                execQueue.async {
                    self.worker(key) { completion($0) }
                }
                return
            }
            
            if cache[key] == nil {
                cache[key] = StoredData()
            }
            
            guard cache[key]!.isRunning else {
                cache[key]?.isRunning = true
                cache[key]?.notifier.enter()
                execQueue.async {
                    if self.cache[key]?.failed != nil && self.memoizing.contains(.failed) {
                        self.cache[key]?.running = self.cache[key]?.failed
                    } else if self.cache[key]?.succeeded != nil && self.memoizing.contains(.succeeded) {
                        self.cache[key]?.running = self.cache[key]?.failed
                    } else {
                        self.worker(key) { res in
                            switch res {
                            case .success(_):
                                if self.memoizing.contains(.succeeded) {
                                    self.cache[key]?.succeeded = res
                                }
                            case .failure(_):
                                if self.memoizing.contains(.failed) {
                                    self.cache[key]?.failed = res
                                }
                            }
                            self.cache[key]?.running = res
                        }
                    }
                    self.cache[key]?.notifier.leave()
                    completion(self.cache[key]!.running!)
                    self.cache[key]?.isRunning = false
                }
                return
            }
            
            execQueue.async {
                self.cache[key]?.notifier.wait()
                completion(self.cache[key]!.running!)
            }
        }
    }
}

struct StoredData<Output, Failure: Error> {
    var failed: Result<Output, Failure>?
    var succeeded: Result<Output, Failure>?
    var running: Result<Output, Failure>?
    var isRunning: Bool = false
    let notifier: DispatchGroup = DispatchGroup()
}
