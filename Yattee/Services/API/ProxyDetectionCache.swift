import Foundation

/// Caches the answer to "should we proxy streams through this instance?" for the
/// auto-detect path (when `Instance.proxiesVideos` is *off* and we'd otherwise have
/// to HEAD a CDN URL to find out whether the network blocks direct access).
///
/// The HEAD probe is the slowest single thing on the playback startup path on a
/// network where the CDN is blocked: 5 s timeout, paid on *every* video. The
/// answer is a property of the network, not the video, so caching it for a few
/// minutes is safe and cuts videos 2..N down to a synchronous lookup.
///
/// Invalidation:
/// - on `instancesDidChange` (handles the user flipping the proxy toggle, editing
///   the URL, etc.) — wire this up at the call site
/// - implicit via `ttl` so a network change eventually re-tests
///
/// Thread-safety: actor.
actor ProxyDetectionCache {
    static let shared = ProxyDetectionCache()

    /// How long a verdict stays fresh. The only reason the answer can flip is a
    /// network change (Wi-Fi ↔ cellular, VPN on/off). 10 min is a defensible
    /// upper bound for "you'll re-probe shortly after the change settles".
    static let ttl: TimeInterval = 600

    /// How long ago we last saw any CDN URL for this instance. Reused as the
    /// prober URL by ``prewarm(instance:probe:)`` so detection can happen
    /// before the API call for the next video returns.
    private struct Entry {
        var decision: Bool
        var expiresAt: Date
        var sampleURL: URL?
    }

    private var entries: [UUID: Entry] = [:]

    /// In-flight detection per instance, so concurrent callers share one HEAD.
    private var inFlight: [UUID: Task<Bool, Never>] = [:]

    /// Returns the cached verdict if still fresh.
    func cachedDecision(for instance: Instance) -> Bool? {
        guard let entry = entries[instance.id], entry.expiresAt > Date() else {
            return nil
        }
        return entry.decision
    }

    /// Most-recently-seen CDN URL for this instance. Used by ``prewarm`` so we
    /// don't have to wait for the current video's API response just to learn a
    /// URL to probe.
    func lastSampleURL(for instance: Instance) -> URL? {
        entries[instance.id]?.sampleURL
    }

    /// Records a verdict (decision + the URL we probed against, kept as a
    /// future probe sample). Refreshes the TTL.
    func record(decision: Bool, sampleURL: URL?, for instance: Instance) {
        entries[instance.id] = Entry(
            decision: decision,
            expiresAt: Date().addingTimeInterval(Self.ttl),
            sampleURL: sampleURL ?? entries[instance.id]?.sampleURL
        )
    }

    /// Resolves a verdict for `instance`. Returns the cached answer if fresh;
    /// otherwise runs `probe(sampleURL)` and caches the result. Multiple
    /// concurrent callers for the same instance share one probe.
    func decision(
        for instance: Instance,
        sampleURL: URL,
        probe: @Sendable @escaping (URL) async -> Bool
    ) async -> Bool {
        if let cached = cachedDecision(for: instance) {
            return cached
        }

        if let task = inFlight[instance.id] {
            return await task.value
        }

        let task = Task<Bool, Never> { await probe(sampleURL) }
        inFlight[instance.id] = task
        let verdict = await task.value
        inFlight[instance.id] = nil
        record(decision: verdict, sampleURL: sampleURL, for: instance)
        return verdict
    }

    /// Kick off a detection probe in the background using the last-seen sample
    /// URL for this instance, if any and if we don't already have a fresh
    /// answer. Returns immediately. The point: by the time the caller's API
    /// fetch returns, the verdict is likely cached, so the playback path
    /// becomes a synchronous lookup.
    func prewarm(
        instance: Instance,
        probe: @Sendable @escaping (URL) async -> Bool
    ) {
        if cachedDecision(for: instance) != nil { return }
        if inFlight[instance.id] != nil { return }
        guard let sample = entries[instance.id]?.sampleURL else { return }

        let task = Task<Bool, Never> { await probe(sample) }
        inFlight[instance.id] = task
        Task {
            let verdict = await task.value
            self.inFlight[instance.id] = nil
            self.record(decision: verdict, sampleURL: sample, for: instance)
        }
    }

    /// Drop the entry for one instance — e.g. when its settings changed and the
    /// previous verdict may no longer apply.
    func invalidate(instance: Instance) {
        entries.removeValue(forKey: instance.id)
        inFlight[instance.id]?.cancel()
        inFlight.removeValue(forKey: instance.id)
    }

    /// Drop all entries — e.g. after a network reachability change or when the
    /// instances collection mutates broadly.
    func invalidateAll() {
        entries.removeAll()
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
    }
}
