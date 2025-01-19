import ImageIO
import XCTest

@testable import Gifu

private let imageData = testImageDataNamed("mugen.gif")
private let staticImage = UIImage(data: imageData)!
private let preloadFrameCount = 20

class DummyAnimatable: GIFAnimatable {
  init() {}
  var animator: Animator? = nil
  var image: UIImage? = nil
  var layer = CALayer()
  var frame: CGRect = .zero
  var contentMode: UIView.ContentMode = .scaleToFill
  func animatorHasNewFrame() {}
}

@MainActor
class GifuTests: XCTestCase {
  var animator: Animator!
  var originalFrameCount: Int!
  let delegate = DummyAnimatable()

  override func setUp() {
    super.setUp()
    animator = Animator(withDelegate: delegate)
    animator.prepareForAnimation(
      withGIFData: imageData, size: staticImage.size, contentMode: .scaleToFill)
    originalFrameCount = 44
  }

  func testIsAnimatable() {
    XCTAssertNotNil(animator.frameStore)
    guard let store = animator.frameStore else { return }
    XCTAssertTrue(store.isAnimatable)
  }

  func testCurrentFrame() {
    XCTAssertNotNil(animator.frameStore)
    guard let store = animator.frameStore else { return }
    XCTAssertEqual(store.currentFrameIndex, 0)
  }

  func testFramePreload() {
    XCTAssertNotNil(animator.frameStore)
    guard let store = animator.frameStore else { return }

    let expectation = self.expectation(description: "frameDuration")

    store.prepareFrames { [originalFrameCount] in
      let animatedFrameCount = store.animatedFrames.count
      XCTAssertEqual(animatedFrameCount, originalFrameCount)
      XCTAssertNotNil(store.frame(at: preloadFrameCount - 1))
      XCTAssertNil(store.frame(at: preloadFrameCount + 1)?.images)
      XCTAssertEqual(store.currentFrameIndex, 0)

      store.shouldChangeFrame(with: 1.0) { hasNewFrame in
        XCTAssertTrue(hasNewFrame)
        XCTAssertEqual(store.currentFrameIndex, 1)
        expectation.fulfill()
      }
    }

    waitForExpectations(timeout: 1.0) { error in
      if let error = error {
        print("Error: \(error.localizedDescription)")
      }
    }
  }

  func testFrameInfo() {
    XCTAssertNotNil(animator.frameStore)
    guard let store = animator.frameStore else { return }

    let expectation = self.expectation(description: "testFrameInfoIsAccurate")

    store.prepareFrames {
      let frameDuration = store.frame(at: 5)?.duration ?? 0
      XCTAssertTrue((frameDuration - 0.05) < 0.00001)

      let imageSize = store.frame(at: 5)?.size ?? CGSize.zero
      XCTAssertEqual(imageSize, staticImage.size)

      expectation.fulfill()
    }

    waitForExpectations(timeout: 1.0) { error in
      if let error = error {
        print("Error: \(error.localizedDescription)")
      }
    }
  }

  func testFinishedStates() {
    animator = Animator(withDelegate: delegate)
    animator.prepareForAnimation(
      withGIFData: imageData, size: staticImage.size, contentMode: .scaleToFill, loopCount: 2)

    XCTAssertNotNil(animator.frameStore)
    guard let store = animator.frameStore else { return }

    let expectation = self.expectation(description: "testFinishedStatesAreSetCorrectly")

    store.prepareFrames {
      let animatedFrameCount = store.animatedFrames.count
      XCTAssertEqual(store.currentFrameIndex, 0)

      // Animate through all the frames (first loop)
      for frame in 1..<animatedFrameCount {
        XCTAssertFalse(store.isLoopFinished)
        XCTAssertFalse(store.isFinished)
        store.shouldChangeFrame(with: 1.0) { hasNewFrame in
          XCTAssertTrue(hasNewFrame)
          XCTAssertEqual(store.currentFrameIndex, frame)
        }
      }

      XCTAssertTrue(store.isLoopFinished, "First loop should be finished")
      XCTAssertFalse(store.isFinished, "Animation should not be finished yet")

      store.shouldChangeFrame(with: 1.0) { hasNewFrame in
        XCTAssertTrue(hasNewFrame)
      }

      XCTAssertEqual(store.currentFrameIndex, 0)

      // Animate through all the frames (second loop)
      for frame in 1..<animatedFrameCount {
        XCTAssertFalse(store.isLoopFinished)
        XCTAssertFalse(store.isFinished)
        store.shouldChangeFrame(with: 1.0) { hasNewFrame in
          XCTAssertTrue(hasNewFrame)
          XCTAssertEqual(store.currentFrameIndex, frame)
        }
      }

      XCTAssertTrue(store.isLoopFinished, "Second loop should be finished")
      XCTAssertTrue(store.isFinished, "Animation should be finished (loopCount: 2)")

      expectation.fulfill()
    }

    waitForExpectations(timeout: 1.0) { error in
      if let error = error {
        print("Error: \(error.localizedDescription)")
      }
    }
  }
}

private func testImageDataNamed(_ name: String) -> Data {
  let testBundle = Bundle(for: GifuTests.self)
  let imagePath = testBundle.bundleURL.appendingPathComponent(name)
  return (try! Data(contentsOf: imagePath))
}
