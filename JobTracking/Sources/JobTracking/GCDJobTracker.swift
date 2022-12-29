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
    private var states: [Key: JobState<Output, Failure>] = [:]
    
    required public init(memoizing: MemoizationOptions, worker: @escaping JobWorker<Key, Output, Failure>) {
        self.memoizing = memoizing
        self.worker = worker
        self.execQueue = DispatchQueue(label: "gcdJobTrackerExecutionQueue", attributes: .concurrent)
        self.syncQueue = DispatchQueue(label: "gcdJobTrackerSyncQueue")
    }
    
    public func startJob(for key: Key, completion: @escaping (Result<Output, Failure>) -> Void) {
        guard self.memoizing.contains(.started) else {
            self.execQueue.async {
                self.worker(key) { completion($0) }
            }
            return
        }
        
        // sync block for nil value check
        // if don't have that block it is possible to assign states[key] multiple times, it won't affect us in the future but it's race condition
        syncQueue.async {
            if self.states[key] == nil {
                self.states[key] = JobState.neverStarted
            }
            
            // sync "append to running queue in case of running" with "start of running queue evaluation"
            self.syncQueue.async {
                switch self.states[key]! {
                case JobState<Output, Failure>.neverStarted:
                    break
                case var JobState.running(awaitingCallbacks: queue):
                    queue.append(completion)
                    return
                case let JobState.completed(result: res):
                    switch res {
                    case .failure(_):
                        if self.memoizing.contains(.failed) {
                            completion(res)
                            return
                        }
                    case .success(_):
                        if self.memoizing.contains(.succeeded) {
                            completion(res)
                            return
                        }
                    }
                }
                self.states[key] = JobState.running(awaitingCallbacks: [completion])
                self.execQueue.async {
                    self.worker(key) { res in
                        // that is "start of running queue evaluation" part of sync
                        self.syncQueue.async {
                            // if we are in this block then self.states[key] is at .running state
                            if case let JobState.running(awaitingCallbacks: completions) = self.states[key]! {
                                self.states[key] = JobState.completed(result: res)
                                self.execQueue.async {
                                    for c in completions {
                                        c(res)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

enum JobState<Output, Failure: Error> {
    case neverStarted
    case running(awaitingCallbacks: [(Result<Output, Failure>) -> Void])
    case completed(result: Result<Output, Failure>)
}
