//
//  File.swift
//  
//
//  Created by Andrey Karpenko on 25.12.2022.
//

import Foundation

public actor ConcurrentJobTracker<Key: Hashable, Output>: AsyncJobTracking {
    private let memoizing: MemoizationOptions
    private let worker: JobWorker<Key, Output, Failure>
    private var activeTasks: [Key: Task<Output, Error>] = [:]
    private var cache: [Key: Result<Output, Error>] = [:]

    public init(memoizing: MemoizationOptions, worker: @escaping JobWorker<Key, Output, Error>) {
        self.memoizing = memoizing
        self.worker = worker
    }

    public func startJob(for key: Key) async throws -> Output {
        if memoizing.contains(.started) {
            // if task is nil then no job is running
            if let existingTask = activeTasks[key] {
                return try await existingTask.value
            }
        }

        let task: Task<Output, Error> = Task<Output, Error> {
            if let cacheRes = cache[key] {
                switch cacheRes {
                case let .failure(err):
                    if memoizing.contains(.failed) {
                        activeTasks[key] = nil
                        throw err
                    }
                case let .success(out):
                    if memoizing.contains(.succeeded) {
                        activeTasks[key] = nil
                        return out
                    }
                }
            }
            do {
                // we have to somehow extract result from working closure:
                let res = try await withCheckedThrowingContinuation { continuation in
                    worker(key) { res in
                        switch res {
                        case let .success(output):
                            continuation.resume(returning: output)
                        case let .failure(err):
                            continuation.resume(throwing: err)
                        }
                    }
                }
                cache[key] = .success(res)
                activeTasks[key] = nil
                return res
            } catch {
                cache[key] = .failure(error)
                activeTasks[key] = nil
                throw error
            }
        }
        
        activeTasks[key] = task
        
        return try await task.value
    }
}
