import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let resultado = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Registra no APNs já na abertura (não depende de o Dart pedir antes).
    application.registerForRemoteNotifications()
    return resultado
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Guarda o resultado do registro no APNs para o diagnóstico do app (o
  // shared_preferences do Flutter lê as chaves com prefixo "flutter.").
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    UserDefaults.standard.set("ok (\(deviceToken.count) bytes)", forKey: "flutter.apns_status")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    UserDefaults.standard.set("ERRO: \(error.localizedDescription)", forKey: "flutter.apns_status")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
