import UIKit
import ImageIO

/// Responsible for storing and updating the frames of a `AnimatableImageView` instance via delegation.
class Animator {
  /// Maximum duration to increment the frame timer with.
  let maxTimeStep = 1.0
  /// An array of animated frames from a single GIF image.
  var animatedFrames = [AnimatedFrame]()
  /// The size to resize all frames to
  let size: CGSize
  /// The content mode to use when resizing
  let contentMode: UIViewContentMode
  /// Maximum number of frames to load at once
  let maxFrameCount: Int
  /// The total number of frames in the GIF.
  var frameCount = 0
  /// A reference to the original image source.
  var imageSource: CGImageSourceRef
  /// The index of the current GIF frame.
  var currentFrameIndex = 0
  /// The index of the current GIF frame from the source.
  var currentPreloadIndex = 0
  /// Time elapsed since the last frame change. Used to determine when the frame should be updated.
  var timeSinceLastFrameChange: NSTimeInterval = 0.0
  /// Determines whether resizing is required.
  /// - seealso: `needsFramesResizing` in AnimatableImageView.swift
  var needsFramesResizing = true

  /// The current image frame to show.
  var currentFrame: UIImage? {
    return frameAtIndex(currentFrameIndex)
  }

  /// Is this image animatable?
  var isAnimatable: Bool {
    return imageSource.isAnimatedGIF
  }

  /// Initializes an animator instance from raw GIF image data.
  ///
  /// - parameter data: The raw GIF image data.
  /// - parameter size: Size that is used for all GIF frames resizing.
  /// - parameter contentMode: Mode that determines how a view adjusts its content.
  /// - parameter framePreloadCount: Number of frames that will be preloaded into memory.
  init(data: NSData, size: CGSize, contentMode: UIViewContentMode, framePreloadCount: Int) {
    let options = [String(kCGImageSourceShouldCache): kCFBooleanFalse]
    self.imageSource = CGImageSourceCreateWithData(data, options) ?? CGImageSourceCreateIncremental(options)
    self.size = size
    self.contentMode = contentMode
    self.maxFrameCount = framePreloadCount
  }

  // MARK: - Frames
  /// Loads the frames from an image source, resizes them, then caches them in `animatedFrames`.
  func prepareFrames() {
    frameCount = Int(CGImageSourceGetCount(imageSource))
    let framesToProcess = min(frameCount, maxFrameCount)
    animatedFrames.reserveCapacity(framesToProcess)
    animatedFrames = (0..<framesToProcess).reduce([]) { $0 + pure(prepareFrame($1)) }
    currentPreloadIndex = framesToProcess
  }
  
  /// Loads a single frame from an image source, resizes it, then returns an `AnimatedFrame`.
  ///
  /// - parameter index: The index of the GIF image source to prepare
  /// - returns: An AnimatedFrame object
  func prepareFrame(index: Int) -> AnimatedFrame {
    guard let frameImageRef = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
      return AnimatedFrame.null()
    }
    
    let frameDuration = CGImageSourceGIFFrameDuration(imageSource, index: index)
    let image = UIImage(CGImage: frameImageRef)
    let scaledImage: UIImage?
    
    if needsFramesResizing == true {
      switch contentMode {
      case .ScaleAspectFit: scaledImage = image.resizeAspectFit(size)
      case .ScaleAspectFill: scaledImage = image.resizeAspectFill(size)
      default: scaledImage = image.resize(size)
      }
    } else {
      scaledImage = image
    }
    
    return AnimatedFrame(image: scaledImage, duration: frameDuration)
  }
  
  /// Updates the cached frames after moving to an arbitrary frame.
  /// - parameter index: The index of the frame the timeline was moved to.
  func prepareFramesAfterMovingToIndex(index: Int) {
    if index < 0 || index >= frameCount {
      return
    }
    
    // Check whether all of the GIF frames are containted in the cache.
    if animatedFrames.count == frameCount {
      currentFrameIndex = index
    } else {
      rebuildCacheFromIndex(index)
    }
    
    // Reset updating time.
    timeSinceLastFrameChange = 0.0
  }
  
  /// Rebuilds cache after frame moving in cases when all the frames cannot be loaded into the cache completely.
  /// - parameter index: The index of the frame the timeline was moved to.
  func rebuildCacheFromIndex(index: Int) {
    let convertedIndices = convertCacheIndicesToGIFIndices()
    
    // Check whether cache rebuilding is needed.
    if convertedIndices[currentFrameIndex] == index { return }
    
    // Calculate indices for preload.
    var indicesForPreload = [Int](count: animatedFrames.count, repeatedValue: 0)
    var baseIndex = index
    for indexForPreload in (0..<indicesForPreload.count) {
      indicesForPreload[indexForPreload] = baseIndex % frameCount
      ++baseIndex
    }
    
    // Reset all previous animation indices.
    currentFrameIndex = 0
    currentPreloadIndex = baseIndex % frameCount
    
    // Fill the cache with the new animated frames.
    animatedFrames = indicesForPreload.reduce([]) { $0 + pure(prepareFrame($1)) }
  }
  
  /// Maps from the currentFrameIndex to the index in the GIF's frames array.
  /// - returns: Converted index.
  func convertCurrentCacheIndexToGIFIndex() -> Int {
    // Check whether the cache is empty.
    if animatedFrames.count <= 0 { return -1 }
    
    // Check whether the cache doesn't require conversion.
    if animatedFrames.count == frameCount { return currentFrameIndex }
  
    var convertedIndex: Int = currentPreloadIndex
    for _ in (0..<animatedFrames.count) {
      convertedIndex = (convertedIndex - 1) < 0 ? { convertedIndex = (frameCount - 1); return convertedIndex }() : --convertedIndex
    }
    
    return convertedIndex
  }
  
  /// Maps from cache array indices to GIF frames array indices.
  /// - returns: An array with GIF frames array indices. Each index positon corresponds to the cache array index.
  func convertCacheIndicesToGIFIndices() -> [Int] {
    // Check whether the cache is empty.
    if animatedFrames.count <= 0 { return [Int]() }
    
    // Check whether the cache doesn't require conversion.
    if animatedFrames.count == frameCount { return (0..<frameCount).map{$0} }
    
    // Declare required vars.
    var convertedIndices = [Int](count: animatedFrames.count, repeatedValue: 0)
    var currentCachedFrameIndex = -1
    var currentConvertedIndex = -1
    
    // Resets negative preload index so that it points to the max GIF frame.
    func resetToMaxGIFIndex() -> Int {
      currentConvertedIndex = (frameCount - 1)
      return currentConvertedIndex
    }

    // Map negative indices to the max array index during decrement operations.
    // Note: (currentFrameIndex - 1) index points to the correct position in GIF's frames array which is equal to (currentPreloadIndex - 1).
    if (currentFrameIndex - 1) < 0 {
      currentCachedFrameIndex = (animatedFrames.count - 1)
    } else {
      currentCachedFrameIndex = (currentFrameIndex - 1)
    }
    
    if (currentPreloadIndex - 1) < 0 {
      currentConvertedIndex = (frameCount - 1)
    } else {
      currentConvertedIndex = (currentPreloadIndex - 1)
    }
    
    // Save already converted index.
    convertedIndices[currentCachedFrameIndex] = currentConvertedIndex
    
    // Build left-hand side cache from the current cached frame index.
    for lhsIndex in (0..<currentCachedFrameIndex).reverse() {
      convertedIndices[lhsIndex] = (currentConvertedIndex - 1) < 0 ?  resetToMaxGIFIndex() : --currentConvertedIndex
    }
    
    // Build right-hand side cache from the current cached frame index.
    for rhsIndex in ((currentCachedFrameIndex + 1)..<self.animatedFrames.count).reverse() {
      convertedIndices[rhsIndex] = (currentConvertedIndex - 1) < 0 ?  resetToMaxGIFIndex() : --currentConvertedIndex
    }
    
    return convertedIndices
  }

  /// Returns the frame at a particular index.
  ///
  /// - parameter index: The index of the frame.
  /// - returns: An optional image at a given frame.
  func frameAtIndex(index: Int) -> UIImage? {
    return animatedFrames[index].image
  }

  /// Updates the current frame if necessary using the frame timer and the duration of each frame in `animatedFrames`.
  ///
  /// - returns: An optional image at a given frame.
  func updateCurrentFrame(duration: CFTimeInterval) -> Bool {
    timeSinceLastFrameChange += min(maxTimeStep, duration)
    guard let frameDuration = animatedFrames[safe:currentFrameIndex]?.duration where
    frameDuration <= timeSinceLastFrameChange else { return false }

    timeSinceLastFrameChange -= frameDuration
    let lastFrameIndex = currentFrameIndex
    currentFrameIndex = ++currentFrameIndex % animatedFrames.count
    
    // Loads the next needed frame for progressive loading
    if animatedFrames.count < frameCount {
      animatedFrames[lastFrameIndex] = prepareFrame(currentPreloadIndex)
      currentPreloadIndex = ++currentPreloadIndex % frameCount
    }
    
    return true
  }
}
