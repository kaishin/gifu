import ImageIO
import UIKit

/// Responsible for storing and updating the frames of a single GIF.
final class FrameStore: @unchecked Sendable {
  /// The strategy to use for frame cache.
  enum FrameCachingStrategy: Equatable, Sendable {
    // Cache only a given number of upcoming frames.
    case cacheUpcoming(Int)

    // Cache all frames.
    case cacheAll
  }

  /// The caching strategy to use for frames
  var cachingStrategy: FrameCachingStrategy

  /// Total duration of one animation loop
  var loopDuration: TimeInterval = 0

  /// Flag indicating that a single loop has finished
  var isLoopFinished: Bool = false

  /// Flag indicating if number of loops has been reached (never true for infinite loop)
  var isFinished: Bool = false

  /// Desired number of loops, <= 0 for infinite loop
  let loopCount: Int

  /// Index of current loop
  var currentLoop = 0

  /// Maximum duration to increment the frame timer with.
  let maxTimeStep = 1.0

  /// An array of animated frames from a single GIF image.
  var animatedFrames = [AnimatedFrame]()

  /// The target size for all frames.
  let size: CGSize

  /// The content mode to use when resizing.
  let contentMode: UIView.ContentMode

  /// Maximum number of upcoming frames to keep in the cache.
  /// Defaults to 10 when all frames are cached indefinitely.
  var frameBufferSize: Int {
    switch cachingStrategy {
    case .cacheUpcoming(let size): size
    case .cacheAll: 10
    }
  }

  /// The total number of frames in the GIF.
  var frameCount = 0

  /// A reference to the original image source.
  var imageSource: CGImageSource

  /// The index of the current GIF frame.
  var currentFrameIndex = 0 {
    didSet {
      previousFrameIndex = oldValue
    }
  }

  /// The index of the previous GIF frame.
  var previousFrameIndex = 0 {
    didSet {
      preloadFrameQueue.async {
        self.updateFrameCache()
      }
    }
  }

  /// Time elapsed since the last frame change. Used to determine when the frame should be updated.
  var timeSinceLastFrameChange: TimeInterval = 0.0

  /// Specifies whether GIF frames should be resized.
  var shouldResizeFrames = true

  /// Dispatch queue used for preloading images.
  private lazy var preloadFrameQueue: DispatchQueue = {
    return DispatchQueue(label: "co.kaishin.Gifu.preloadQueue")
  }()

  /// The current image frame to show.
  var currentFrameImage: UIImage? {
    return frame(at: currentFrameIndex)
  }

  /// The current frame duration
  var currentFrameDuration: TimeInterval {
    return duration(at: currentFrameIndex)
  }

  /// Is this image animatable?
  var isAnimatable: Bool {
    return imageSource.isAnimatedGIF
  }

  private let lock = NSLock()

  /// Creates an animator instance from raw GIF image data and an `Animatable` delegate.
  ///
  /// - parameter data: The raw GIF image data.
  /// - parameter size: The target size for the frames.
  /// - parameter contentMode: The content mode to use when resizing.
  /// - parameter cachingStrategy: The caching strategy to use for frames.
  /// - parameter loopCount: Desired number of loops, <= 0 for infinite loop.
  init(
    data: Data,
    size: CGSize,
    contentMode: UIView.ContentMode,
    cachingStrategy: FrameCachingStrategy,
    loopCount: Int
  ) {
    let options = [String(kCGImageSourceShouldCache): kCFBooleanFalse] as CFDictionary
    self.imageSource =
      CGImageSourceCreateWithData(data as CFData, options)
      ?? CGImageSourceCreateIncremental(options)
    self.size = size
    self.contentMode = contentMode
    self.cachingStrategy = cachingStrategy
    self.loopCount = loopCount
  }

  /// Creates an animator instance from raw GIF image data and an `Animatable` delegate.
  ///
  /// - parameter data: The raw GIF image data.
  /// - parameter size: The target size for the frames.
  /// - parameter contentMode: The content mode to use when resizing.
  /// - parameter frameBufferSize: The number of frames to cache.
  /// - parameter loopCount: Desired number of loops, <= 0 for infinite loop.
  @available(*, deprecated, message: "Use the initializer with `FrameCachingStrategy` instead.")
  init(
    data: Data,
    size: CGSize,
    contentMode: UIView.ContentMode,
    frameBufferSize: Int,
    loopCount: Int
  ) {
    let options = [String(kCGImageSourceShouldCache): kCFBooleanFalse] as CFDictionary
    self.imageSource =
      CGImageSourceCreateWithData(data as CFData, options)
      ?? CGImageSourceCreateIncremental(options)
    self.size = size
    self.contentMode = contentMode
    self.cachingStrategy = frameBufferSize > 0 ? .cacheUpcoming(frameBufferSize) : .cacheAll
    self.loopCount = loopCount
  }

  // MARK: - Frames
  /// Loads the frames from an image source, resizes them, then caches them in `animatedFrames`.
  func prepareFrames(_ completionHandler: (@Sendable () -> Void)? = nil) {
    frameCount = Int(CGImageSourceGetCount(imageSource))
    lock.lock()
    animatedFrames.reserveCapacity(frameCount)
    lock.unlock()
    preloadFrameQueue.async {
      self.setupAnimatedFrames()
      completionHandler?()
    }
  }

  /// Returns the frame at a particular index.
  ///
  /// - parameter index: The index of the frame.
  /// - returns: An optional image at a given frame.
  func frame(at index: Int) -> UIImage? {
    lock.lock()
    defer { lock.unlock() }
    return animatedFrames[safe: index]?.image
  }

  /// Returns the duration at a particular index.
  ///
  /// - parameter index: The index of the duration.
  /// - returns: The duration of the given frame.
  func duration(at index: Int) -> TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return animatedFrames[safe: index]?.duration ?? TimeInterval.infinity
  }

  /// Checks whether the frame should be changed and calls a handler with the results.
  ///
  /// - parameter duration: A `CFTimeInterval` value that will be used to determine whether frame should be changed.
  /// - parameter handler: A function that takes a `Bool` and returns nothing. It will be called with the frame change result.
  func shouldChangeFrame(with duration: CFTimeInterval, handler: (Bool) -> Void) {
    timeSinceLastFrameChange += min(maxTimeStep, duration)

    if currentFrameDuration > timeSinceLastFrameChange {
      handler(false)
    } else {
      resetTimeSinceLastFrameChange()
      incrementCurrentFrameIndex()
      handler(true)
    }
  }
}

extension FrameStore {
  /// Optionally loads a single frame from an image source, resizes it if required, then returns an `UIImage`.
  ///
  /// - parameter index: The index of the frame to load.
  /// - returns: An optional `UIImage` instance.
  private func loadFrame(at index: Int) -> UIImage? {
    guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, index, nil)
    else { return nil }

    let image = UIImage(cgImage: imageRef)
    let scaledImage: UIImage?

    if shouldResizeFrames {
      switch self.contentMode {
      case .scaleAspectFit: scaledImage = image.constrained(by: size)
      case .scaleAspectFill: scaledImage = image.filling(size: size)
      default: scaledImage = size != .zero ? image.resized(to: size) : nil
      }
    } else {
      scaledImage = image
    }

    return scaledImage
  }

  /// Updates the frames by preloading new ones and replacing the previous frame with a placeholder.
  private func updateFrameCache() {
    if case let .cacheUpcoming(size) = cachingStrategy,
      size < frameCount - 1 {
      deleteCachedFrame(at: previousFrameIndex)
    }

    guard animatedFrames.filter(\.isPlaceholder).count > 0
    else { return }

    func indexesToCache(startingAt index: Int) -> [Int] {
      let nextIndex = increment(frameIndex: index)
      let lastIndex = increment(frameIndex: index, by: frameBufferSize)

      if lastIndex >= nextIndex {
        return [Int](nextIndex...lastIndex)
      } else {
        return [Int](nextIndex..<frameCount) + [Int](0...lastIndex)
      }
    }

    for index in indexesToCache(startingAt: currentFrameIndex) {
      loadFrameAtIndexIfNeeded(index)
    }
  }

  func deleteCachedFrame(at index: Int) {
    lock.lock()
    animatedFrames[index] = animatedFrames[index].placeholderFrame
    lock.unlock()
  }

  func loadFrameAtIndexIfNeeded(_ index: Int) {
    let frame: AnimatedFrame

    lock.lock()
    frame = animatedFrames[index]
    lock.unlock()

    guard frame.isPlaceholder
    else { return }

    let loadedFrame = frame.makeAnimatedFrame(with: loadFrame(at: index))

    lock.lock()
    animatedFrames[index] = loadedFrame
    lock.unlock()
  }

  /// Ensures that `timeSinceLastFrameChange` remains accurate after each frame change by subtracting the `currentFrameDuration`.
  private func resetTimeSinceLastFrameChange() {
    timeSinceLastFrameChange -= currentFrameDuration
  }

  /// Increments the `currentFrameIndex` property.
  private func incrementCurrentFrameIndex() {
    currentFrameIndex = increment(frameIndex: currentFrameIndex)

    if isLastFrame(frameIndex: currentFrameIndex) {
      isLoopFinished = true
      if isLastLoop(loopIndex: currentLoop) {
        isFinished = true
      }
    } else {
      isLoopFinished = false
      if currentFrameIndex == 0 {
        currentLoop = currentLoop + 1
      }
    }
  }

  /// Increments a given frame index, taking into account the `frameCount` and looping when necessary.
  ///
  /// - parameter index: The `Int` value to increment.
  /// - parameter byValue: The `Int` value to increment with.
  /// - returns: A new `Int` value.
  private func increment(frameIndex: Int, by value: Int = 1) -> Int {
    return (frameIndex + value) % frameCount
  }

  /// Indicates if current frame is the last one.
  /// - parameter frameIndex: Index of current frame.
  /// - returns: True if current frame is the last one.
  private func isLastFrame(frameIndex: Int) -> Bool {
    return frameIndex == frameCount - 1
  }

  /// Indicates if current loop is the last one. Always false for infinite loops.
  /// - parameter loopIndex: Index of current loop.
  /// - returns: True if current loop is the last one.
  private func isLastLoop(loopIndex: Int) -> Bool {
    return loopIndex == loopCount - 1
  }

  private func setupAnimatedFrames() {
    resetAnimatedFrames()

    var duration: TimeInterval = 0

    (0..<frameCount).forEach { index in
      lock.lock()
      let frameDuration = CGImageFrameDuration(with: imageSource, atIndex: index)
      duration += min(frameDuration, maxTimeStep)
      animatedFrames += [AnimatedFrame(image: nil, duration: frameDuration)]
      lock.unlock()

      if index > frameBufferSize { return }
      loadFrameAtIndexIfNeeded(index)
    }

    self.loopDuration = duration
  }

  /// Reset animated frames.
  private func resetAnimatedFrames() {
    animatedFrames = []
  }

  private var totalFrameCacheSize: Int {
    animatedFrames
      .filter({ !$0.isPlaceholder })
      .compactMap(\.image)
      .reduce(0) { size, image in
        size + image.memorySize
      }
  }
}
