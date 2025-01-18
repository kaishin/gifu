import UIKit

/// Example class that conforms to `GIFAnimatable`. Uses default values for the animator frame buffer count and resize behavior. You can either use it directly in your code or use it as a blueprint for your own subclass.
public class GIFImageView: UIImageView, GIFAnimatable {
  /// A lazy animator.
  public lazy var animator: Animator? = {
    Animator(withDelegate: self)
  }()

  /// Layer delegate method called periodically by the layer. **Should not** be called manually.
  ///
  /// - parameter layer: The delegated layer.
  override public func display(_ layer: CALayer) {
    if UIImageView.instancesRespond(to: #selector(display(_:))) {
      super.display(layer)
    }
    updateImageIfNeeded()
  }
}
