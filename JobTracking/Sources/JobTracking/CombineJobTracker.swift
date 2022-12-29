//
//  File.swift
//  
//
//  Created by Andrey Karpenko on 25.12.2022.
//

import Combine
import Dispatch
import Foundation

public class CombineJobTracker<Key: Hashable, Output, Failure: Error>: PublishingJobTracking {
    private let memoizing: MemoizationOptions
    private let worker: JobWorker<Key, Output, Failure>
    private var activeWorkers: [Key: AnyPublisher<Output, Failure>] = [:]
    private var cache: [Key: Result<Output, Failure>] = [:]
    private var activeWorkersLock: NSLock

    required public init(memoizing: MemoizationOptions, worker: @escaping JobWorker<Key, Output, Failure>) {
        self.memoizing = memoizing
        self.worker = worker
        self.activeWorkersLock = NSLock()
    }

    public func startJob(for key: Key) -> AnyPublisher<Output, Failure> {
        activeWorkersLock.lock()
        
        if memoizing.contains(.started) {
            if let result = activeWorkers[key] {
                activeWorkersLock.unlock()
                return result
            }
        }
        
        
        let publisher = DelayedPublisher<Output, Failure>()
        
        let anyPublisher = publisher.eraseToAnyPublisher()
        activeWorkers[key] = anyPublisher
        activeWorkersLock.unlock()
        
        worker(key) { res in
            self.activeWorkersLock.lock()
            self.activeWorkers[key] = nil
            self.cache[key] = res
            self.activeWorkersLock.unlock()
            
            switch res {
            case let .failure(err):
                publisher.send(completion: .failure(err))
            case let .success(suc):
                publisher.send(suc)
            }
        }
        return anyPublisher
    }
}

// This publisher publishes in 2 cases:
// 1. Subscription is set and after that send(_ value:) method is invoked
// 2. Value is already set and it's got a new subscriber
class DelayedPublisher<Output, Failure: Error>: Publisher {
    private let passthrough = PassthroughSubject<Output, Failure>()
    private var curValue: CurrentValueSubject<Output, Failure>?
    private let lock = NSLock()
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        lock.lock()
        if let cv = curValue {
            cv.receive(subscriber: subscriber)
        }
        passthrough.receive(subscriber: subscriber)
        lock.unlock()
    }

    func send(_ value: Output) {
        lock.lock()
        self.curValue = CurrentValueSubject(value)
        self.passthrough.send(value)
        lock.unlock()
    }
    
    func send(completion: Subscribers.Completion<Failure>) {
        lock.lock()
        if let cv = curValue {
            cv.send(completion: completion)
        }
        passthrough.send(completion: completion)
        lock.unlock()
    }
}
