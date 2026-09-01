import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var statusBarBackground: UIView?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let window else { return }

    window.backgroundColor = .black
    window.rootViewController?.view.backgroundColor = .black

    let background = UIView()
    background.translatesAutoresizingMaskIntoConstraints = false
    background.backgroundColor = .black
    window.addSubview(background)
    NSLayoutConstraint.activate([
      background.leadingAnchor.constraint(equalTo: window.leadingAnchor),
      background.trailingAnchor.constraint(equalTo: window.trailingAnchor),
      background.topAnchor.constraint(equalTo: window.topAnchor),
      background.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor),
    ])
    statusBarBackground = background
  }
}
