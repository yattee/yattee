//
//  BackendSwitcher.swift
//  Yattee
//
//  Handles seamless switching between player backends during playback.
//

import Foundation

// MARK: - Backend Switcher

/// Manages seamless hot-swapping between player backends.
@MainActor
final class BackendSwitcher {
    // MARK: - Dependencies

    /// Factory for creating backend instances.
    private let backendFactory: BackendFactory

    /// Settings manager for quality preferences.
    weak var settingsManager: SettingsManager?

    init(backendFactory: BackendFactory, settingsManager: SettingsManager?) {
        self.backendFactory = backendFactory
        self.settingsManager = settingsManager
    }
}

// MARK: - Backend Factory

/// Factory for creating player backend instances with pre-warming pool.
@MainActor
final class BackendFactory {
    /// Pool of pre-warmed backends ready for instant playback (1 per type)
    private var backendPool: [PlayerBackendType: any PlayerBackend] = [:]
    
    /// Statistics for monitoring pool efficiency
    private var poolHits = 0
    private var poolMisses = 0
    
    /// Create or retrieve a pre-warmed backend.
    func createBackend(type: PlayerBackendType) throws -> any PlayerBackend {
        // Try to get from pool first
        if let backend = backendPool[type] {
            backendPool[type] = nil  // Remove from pool
            poolHits += 1
            
            LoggingService.shared.debug("BackendFactory: pool hit for \(type.displayName) (hits=\(poolHits), misses=\(poolMisses))", category: .mpv)
            
            // Immediately start warming a replacement in background
            Task {
                await prewarmBackend(type: type)
            }
            
            return backend
        }
        
        poolMisses += 1
        LoggingService.shared.debug("BackendFactory: pool miss for \(type.displayName) (hits=\(poolHits), misses=\(poolMisses))", category: .mpv)
        
        // Create new backend and begin setup
        let backend = createBackendInstance(type: type)
        if let mpvBackend = backend as? MPVBackend {
            mpvBackend.beginSetup()
        }
        return backend
    }
    
    /// Create a backend instance (without pool).
    private func createBackendInstance(type: PlayerBackendType) -> any PlayerBackend {
        switch type {
        case .mpv:
            return MPVBackend()
        }
    }
    
    /// Pre-warm a backend and add to pool.
    func prewarmBackend(type: PlayerBackendType) async {
        let startTime = Date()
        LoggingService.shared.debug("BackendFactory: pre-warming \(type.displayName)", category: .mpv)
        
        let backend = await MainActor.run {
            createBackendInstance(type: type)
        }
        
        // Begin async setup
        if let mpvBackend = backend as? MPVBackend {
            await MainActor.run {
                mpvBackend.beginSetup()
            }
            // Wait for setup to complete
            do {
                try await mpvBackend.waitForSetup()
            } catch {
                LoggingService.shared.debug("BackendFactory: pre-warm failed for \(type.displayName): \(error)", category: .mpv)
                return
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        LoggingService.shared.debug("BackendFactory: \(type.displayName) pre-warmed in \(String(format: "%.3f", duration))s", category: .mpv)
        
        // Add to pool (only if slot is empty - don't accumulate)
        await MainActor.run {
            if backendPool[type] == nil {
                backendPool[type] = backend
                LoggingService.shared.debug("BackendFactory: \(type.displayName) added to pool", category: .mpv)
            } else {
                LoggingService.shared.debug("BackendFactory: \(type.displayName) pool already full, discarding", category: .mpv)
            }
        }
    }
    
    /// Pre-warm all available backends in parallel.
    func prewarmAllBackends() async {
        let startTime = Date()
        LoggingService.shared.debug("BackendFactory: pre-warming all backends", category: .mpv)
        
        // Pre-warm in parallel
        await withTaskGroup(of: Void.self) { group in
            for type in availableBackends {
                group.addTask {
                    await self.prewarmBackend(type: type)
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        LoggingService.shared.debug("BackendFactory: all backends pre-warmed in \(String(format: "%.3f", duration))s", category: .mpv)
    }
    
    /// Drain the pool (called on memory warning).
    func drainPool() {
        let count = backendPool.count
        backendPool.removeAll()
        LoggingService.shared.debug("BackendFactory: pool drained (\(count) backends released)", category: .mpv)
    }

    /// Check if a backend type is available on this platform.
    func isAvailable(_ type: PlayerBackendType) -> Bool {
        switch type {
        case .mpv:
            return true
        }
    }

    /// Get all available backend types.
    var availableBackends: [PlayerBackendType] {
        PlayerBackendType.allCases.filter { isAvailable($0) }
    }
}
