//
//  MPVSoftwareRenderView.swift
//  Yattee
//
//  Software (CPU-based) rendering view for MPV in iOS/tvOS Simulator.
//  Uses MPV_RENDER_API_TYPE_SW to render to memory buffer, then displays via CGImage.
//

import Foundation
import Libmpv
#if os(iOS)
import UIKit
#elseif os(tvOS)
import UIKit
#endif
import CoreMedia

#if targetEnvironment(simulator) && (os(iOS) || os(tvOS))

/// Software-based MPV render view for iOS/tvOS Simulator (where OpenGL ES is not available).
/// Renders video frames to CPU memory buffer and displays via CALayer.
final class MPVSoftwareRenderView: UIView {
    // MARK: - Properties
    
    private weak var mpvClient: MPVClient?
    private var isSetup = false
    
    /// Render buffer for MPV to write pixel data
    private var renderBuffer: UnsafeMutableRawPointer?
    private var renderWidth: Int = 0
    private var renderHeight: Int = 0
    private var renderStride: Int = 0
    
    /// Display link for frame rendering
    private var displayLink: CADisplayLink?
    
    /// Video frame rate from MPV
    var videoFPS: Double = 30.0 {
        didSet {
            updateDisplayLinkFrameRate()
        }
    }
    
    /// Current display link target frame rate
    var displayLinkTargetFPS: Double {
        videoFPS
    }
    
    /// Lock for thread-safe rendering
    private let renderLock = NSLock()
    private var isRendering = false
    
    /// Tracks whether first frame has been rendered
    private var hasRenderedFirstFrame = false
    
    /// Tracks whether MPV has signaled it has a frame ready
    private var mpvHasFrameReady = false
    
    /// Generation counter to invalidate stale frame callbacks
    private var frameGeneration: UInt = 0
    
    /// Callback when first frame is rendered
    var onFirstFrameRendered: (() -> Void)?
    
    /// Callback when view is added to window (for PiP setup)
    var onDidMoveToWindow: ((UIView) -> Void)?
    
    /// Dedicated queue for rendering operations
    private let renderQueue = DispatchQueue(label: "stream.yattee.mpv.software-render", qos: .userInitiated)
    
    /// Lock for buffer recreation
    private let bufferLock = NSLock()
    private var isRecreatingBuffer = false
    
    // MARK: - Initialization
    
    init() {
        super.init(frame: .zero)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        backgroundColor = .black
        contentScaleFactor = UIScreen.main.scale
        
        // Observe app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        displayLink?.isPaused = true
        MPVLogging.logDisplayLink("paused", isPaused: true, reason: "enterBackground")
    }
    
    @objc private func appDidBecomeActive() {
        displayLink?.isPaused = false
        MPVLogging.logDisplayLink("resumed", isPaused: false, reason: "becomeActive")
        
        if isSetup {
            renderQueue.async { [weak self] in
                self?.performRender()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopDisplayLink()
        
        // Free render buffer on render queue
        renderQueue.sync {
            freeRenderBuffer()
        }
    }
    
    // MARK: - View Lifecycle
    
    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        
        if newSuperview == nil {
            MPVLogging.logDisplayLink("stop", reason: "removedFromSuperview")
            stopDisplayLink()
        }
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if superview != nil && isSetup {
            if displayLink == nil {
                MPVLogging.logDisplayLink("start", reason: "addedToSuperview")
                startDisplayLink()
            }
            
            // Trigger immediate render
            renderQueue.async { [weak self] in
                self?.performRender()
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard isSetup else { return }
        
        let currentSize = bounds.size
        let scale = contentScaleFactor
        let expectedWidth = Int(currentSize.width * scale)
        let expectedHeight = Int(currentSize.height * scale)
        
        // Check if buffer size needs update
        let bufferMismatch = abs(renderWidth - expectedWidth) > 2 || abs(renderHeight - expectedHeight) > 2
        
        guard bufferMismatch && expectedWidth > 0 && expectedHeight > 0 else { return }
        
        MPVLogging.logTransition("layoutSubviews - size mismatch (async resize)",
            fromSize: CGSize(width: renderWidth, height: renderHeight),
            toSize: CGSize(width: expectedWidth, height: expectedHeight))
        
        // Recreate buffer on background queue
        isRecreatingBuffer = true
        
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.allocateRenderBuffer(width: expectedWidth, height: expectedHeight)
            self.isRecreatingBuffer = false
            MPVLogging.log("layoutSubviews: buffer recreation complete")
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        if window != nil {
            onDidMoveToWindow?(self)
        }
    }
    
    // MARK: - Setup
    
    /// Set up with an MPV client (async version).
    func setupAsync(with client: MPVClient) async throws {
        self.mpvClient = client
        
        // Create MPV software render context
        let success = client.createSoftwareRenderContext()
        if !success {
            MPVLogging.warn("setupAsync: failed to create MPV software render context")
            throw MPVRenderError.renderContextFailed(-1)
        }
        
        // Set up render update callback
        client.onRenderUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.setNeedsDisplay()
            }
        }
        
        // Set up video frame callback
        client.onVideoFrameReady = { [weak self] in
            guard let self else { return }
            let capturedGeneration = self.frameGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.frameGeneration == capturedGeneration else { return }
                self.mpvHasFrameReady = true
            }
        }
        
        await MainActor.run {
            // Allocate initial render buffer
            let scale = contentScaleFactor
            let width = Int(bounds.width * scale)
            let height = Int(bounds.height * scale)
            
            if width > 0 && height > 0 {
                renderQueue.async { [weak self] in
                    self?.allocateRenderBuffer(width: width, height: height)
                }
            }
            
            startDisplayLink()
            isSetup = true
        }
        
        MPVLogging.log("MPVSoftwareRenderView: setup complete")
    }
    
    /// Update time position for frame timestamps.
    func updateTimePosition(_ time: Double) {
        // Not used in software rendering, but kept for API compatibility
    }
    
    // MARK: - Buffer Management
    
    /// Allocate aligned render buffer for MPV to write pixels.
    /// Must be called on renderQueue.
    private func allocateRenderBuffer(width: Int, height: Int) {
        guard width > 0 && height > 0 else {
            return
        }
        
        // Free existing buffer
        freeRenderBuffer()
        
        // Calculate stride (4 bytes per pixel for RGBA, aligned to 64 bytes)
        let bytesPerPixel = 4
        let minStride = width * bytesPerPixel
        let stride = ((minStride + 63) / 64) * 64  // Round up to 64-byte alignment
        
        // Allocate aligned buffer
        var buffer: UnsafeMutableRawPointer?
        let bufferSize = stride * height
        let alignResult = posix_memalign(&buffer, 64, bufferSize)
        
        guard alignResult == 0, let buffer else {
            MPVLogging.warn("allocateRenderBuffer: posix_memalign failed (\(alignResult))")
            return
        }
        
        // Zero out buffer
        memset(buffer, 0, bufferSize)
        
        renderBuffer = buffer
        renderWidth = width
        renderHeight = height
        renderStride = stride
        
        // Trigger an immediate render now that we have a buffer
        if isSetup {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isRendering else { return }
                
                self.renderLock.lock()
                self.isRendering = true
                self.renderLock.unlock()
                
                self.renderQueue.async { [weak self] in
                    self?.performRender()
                }
            }
        }
    }
    
    /// Free render buffer.
    /// Must be called on renderQueue.
    private func freeRenderBuffer() {
        if let buffer = renderBuffer {
            free(buffer)
            renderBuffer = nil
        }
        renderWidth = 0
        renderHeight = 0
        renderStride = 0
    }
    
    // MARK: - Display Link
    
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        updateDisplayLinkFrameRate()
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func updateDisplayLinkFrameRate() {
        guard let displayLink else { return }
        
        // Match video FPS
        let preferred = Float(min(max(videoFPS, 24.0), 60.0))
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 24,
            maximum: 60,
            preferred: preferred
        )
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    /// Pause rendering.
    func pauseRendering() {
        displayLink?.isPaused = true
    }
    
    /// Resume rendering.
    func resumeRendering() {
        guard let displayLink else { return }
        displayLink.isPaused = false
        
        if isSetup {
            renderQueue.async { [weak self] in
                self?.performRender()
            }
        }
    }
    
    /// Reset first frame tracking.
    func resetFirstFrameTracking() {
        frameGeneration += 1
        hasRenderedFirstFrame = false
        mpvHasFrameReady = false
    }
    
    /// Clear the render view to black.
    func clearToBlack() {
        guard renderBuffer != nil else { return }
        
        renderQueue.async { [weak self] in
            guard let self, let buffer = self.renderBuffer else { return }
            memset(buffer, 0, self.renderStride * self.renderHeight)
            
            DispatchQueue.main.async { [weak self] in
                self?.layer.contents = nil
            }
        }
    }
    
    // MARK: - Rendering
    
    @objc private func displayLinkFired() {
        guard isSetup, !isRendering else { return }
        
        renderLock.lock()
        isRendering = true
        renderLock.unlock()
        
        renderQueue.async { [weak self] in
            self?.performRender()
        }
    }
    
    /// Frame counter for periodic logging
    private var renderFrameLogCounter: UInt64 = 0
    
    private func performRender() {
        defer {
            renderLock.lock()
            isRendering = false
            renderLock.unlock()
        }
        
        guard let mpvClient else {
            renderFrameLogCounter += 1
            return
        }
        
        guard let buffer = renderBuffer, renderWidth > 0, renderHeight > 0 else {
            renderFrameLogCounter += 1
            return
        }
        
        // Skip if buffer is being recreated
        if isRecreatingBuffer {
            return
        }
        
        // Render frame to buffer - returns true if a frame was actually rendered
        let didRender = mpvClient.renderSoftware(
            buffer: buffer,
            width: Int32(renderWidth),
            height: Int32(renderHeight),
            stride: renderStride
        )
        
        // Only update the layer if we actually rendered a frame
        guard didRender else {
            return
        }
        
        // Convert buffer to CGImage and update layer
        if let image = bufferToCGImage() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layer.contents = image
            }
            
            // Notify on first frame rendered
            if !hasRenderedFirstFrame {
                hasRenderedFirstFrame = true
                mpvHasFrameReady = true
                DispatchQueue.main.async { [weak self] in
                    self?.onFirstFrameRendered?()
                }
            }
        }
        
        renderFrameLogCounter += 1
    }
    
    /// Convert render buffer to CGImage for display.
    /// Must be called on renderQueue.
    private func bufferToCGImage() -> CGImage? {
        guard let buffer = renderBuffer, renderWidth > 0, renderHeight > 0 else {
            return nil
        }
        
        // Copy buffer data to avoid lifetime issues
        let bufferSize = renderStride * renderHeight
        let dataCopy = Data(bytes: buffer, count: bufferSize)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        guard let dataProvider = CGDataProvider(data: dataCopy as CFData) else {
            return nil
        }
        
        guard let image = CGImage(
            width: renderWidth,
            height: renderHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: renderStride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return image
    }
    
    // MARK: - PiP Compatibility Stubs
    
    /// These properties/methods exist for API compatibility with MPVRenderView.
    /// PiP is not supported in software rendering mode.
    
    var captureFramesForPiP: Bool = false
    var isPiPActive: Bool = false
    var videoContentWidth: Int = 0
    var videoContentHeight: Int = 0
    var onFrameReady: ((CVPixelBuffer, CMTime) -> Void)?

    func clearMainViewForPiP() {
        clearToBlack()
    }
}

#endif
