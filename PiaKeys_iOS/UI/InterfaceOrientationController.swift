import UIKit

/// Requests a scene orientation for transient full-screen practice surfaces.
@MainActor
enum InterfaceOrientationController {
    private static var requestGeneration = 0

    /// Updates the app-level orientation contract before a modal controller is presented.
    ///
    /// UIKit evaluates the app delegate's orientation mask while it creates the
    /// presented controller. Keeping that mask in portrait until the presentation
    /// completion callback leaves a landscape-only controller with no valid common
    /// orientation and can terminate the process with
    /// `UIApplicationInvalidInterfaceOrientation`.
    static func prepare(_ orientations: UIInterfaceOrientationMask, in scene: UIWindowScene? = nil) {
        requestGeneration &+= 1
        PiaKeysAppDelegate.supportedOrientations = orientations
        updateRootController(for: scene)
    }

    /// Requests the supplied orientation mask and asks UIKit to rotate the active scene.
    static func request(_ orientations: UIInterfaceOrientationMask, in scene: UIWindowScene? = nil) {
        guard let scene = scene ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        prepare(orientations, in: scene)
        let generation = requestGeneration
        let preferredOrientation: UIInterfaceOrientation = orientations.contains(.landscape)
            ? .landscapeRight
            : .portrait

        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(
                .iOS(interfaceOrientations: orientations),
                errorHandler: { _ in
                    guard requestGeneration == generation else { return }
                    forceDeviceOrientation(preferredOrientation, in: scene)
                }
            )
        } else {
            forceDeviceOrientation(preferredOrientation, in: scene)
        }

        // The SwiftUI hosting window can accept the geometry request without
        // immediately changing the physical scene orientation. Keep this hint
        // generation-scoped so an old portrait request cannot affect a new
        // landscape presentation.
        DispatchQueue.main.async {
            guard requestGeneration == generation else { return }
            forceDeviceOrientation(preferredOrientation, in: scene)
        }
    }

    private static func updateRootController(for scene: UIWindowScene?) {
        let activeScene = scene ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        activeScene?.windows
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private static func forceDeviceOrientation(_ orientation: UIInterfaceOrientation, in scene: UIWindowScene) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        updateRootController(for: scene)
    }
}
