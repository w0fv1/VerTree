import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static let finderAppGroup = "group.dev.w0fv1.vertree"
  private static let finderRequestPrefix = "finderAction."

  private struct PendingFinderActionItem: Codable {
    let path: String
    let bookmarkBase64: String
  }

  private struct PendingFinderAction: Codable {
    let action: String
    let items: [PendingFinderActionItem]
  }

  private var pendingServiceActions: [(action: String, path: String)] = []
  private var dockChannel: FlutterMethodChannel?
  private var activeSecurityScopedURLs: [String: URL] = [:]

  private func scheduleDockIconRefresh() {
    DispatchQueue.main.async { [weak self] in
      self?.refreshDockIcon()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.refreshDockIcon()
    }
  }

  private func setupDockChannelIfNeeded() {
    guard dockChannel == nil else { return }
    guard let controller = flutterViewController() else { return }

    let channel = FlutterMethodChannel(
      name: "vertree/dock",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "refresh":
        self.scheduleDockIconRefresh()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    dockChannel = channel
  }

  private func ensureRegularActivationPolicy() {



    if NSApp.activationPolicy() != .regular {
      _ = NSApp.setActivationPolicy(.regular)
      scheduleDockIconRefresh()
    }
  }

  private func refreshDockIcon() {

    if let image = NSImage(named: NSImage.Name("DockIcon")) {
      NSApplication.shared.applicationIconImage = image
      NSApp.dockTile.display()
    }
  }

  private func activateAndShowMainWindow() {
    ensureRegularActivationPolicy()
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.mainWindow ?? NSApp.windows.first {
      window.makeKeyAndOrderFront(nil)
    }
    refreshDockIcon()
  }

  private func enqueueServiceAction(_ action: String, path: String) {
    pendingServiceActions.append((action: action, path: path))
  }

  private func flushPendingServiceActions() {
    guard !pendingServiceActions.isEmpty else { return }
    guard flutterViewController() != nil else { return }


    let actions = pendingServiceActions
    pendingServiceActions.removeAll()
    for entry in actions {
      invokeServiceAction(entry.action, path: entry.path)
    }
  }

  private func flutterViewController() -> FlutterViewController? {
    if let window = NSApp.mainWindow,
       let controller = window.contentViewController as? FlutterViewController {
      return controller
    }
    for window in NSApp.windows {
      if let controller = window.contentViewController as? FlutterViewController {
        return controller
      }
    }
    return nil
  }

  private func invokeServiceAction(_ action: String, path: String) {
    guard let controller = flutterViewController() else {
      enqueueServiceAction(action, path: path)
      return
    }
    activateAndShowMainWindow()
    let channel = FlutterMethodChannel(
      name: "vertree/service",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("serviceAction", arguments: [
      "action": action,
      "path": path
    ])
  }

  private func invokeMenuAction(_ action: String) {
    guard let controller = flutterViewController() else { return }
    activateAndShowMainWindow()
    let channel = FlutterMethodChannel(
      name: "vertree/service",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("menuAction", arguments: [
      "action": action
    ])
  }

  private func finderRequestKey(_ requestID: String) -> String {
    "\(Self.finderRequestPrefix)\(requestID)"
  }

  private func consumePendingFinderAction(requestID: String) -> PendingFinderAction? {
    guard let defaults = UserDefaults(suiteName: Self.finderAppGroup) else {
      return nil
    }
    let key = finderRequestKey(requestID)
    guard let data = defaults.data(forKey: key) else {
      return nil
    }
    defaults.removeObject(forKey: key)
    defaults.synchronize()
    return try? JSONDecoder().decode(PendingFinderAction.self, from: data)
  }

  private func resolveSecurityScopedURL(
    from item: PendingFinderActionItem
  ) -> URL? {
    guard let bookmarkData = Data(base64Encoded: item.bookmarkBase64) else {
      return URL(fileURLWithPath: item.path)
    }

    do {
      var isStale = false
      let resolvedURL = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if resolvedURL.startAccessingSecurityScopedResource() {
        activeSecurityScopedURLs[resolvedURL.path] = resolvedURL
      }

      return resolvedURL
    } catch {
      return URL(fileURLWithPath: item.path)
    }
  }

  private func queryValue(
    named name: String,
    in components: URLComponents
  ) -> String? {
    components.queryItems?.first(where: { $0.name == name })?.value
  }

  private func handleVertreeURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "vertree" else {
      return false
    }

    let components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
    let action = queryValue(named: "action", in: components)
    guard let action, !action.isEmpty else {
      return true
    }

    if let requestID = queryValue(
      named: "request",
      in: components
    ), let request = consumePendingFinderAction(requestID: requestID) {
      for item in request.items {
        let resolvedURL = resolveSecurityScopedURL(from: item)
        invokeServiceAction(request.action, path: resolvedURL?.path ?? item.path)
      }
      return true
    }

    if let path = queryValue(
      named: "path",
      in: components
    ), !path.isEmpty {
      invokeServiceAction(action, path: path)
    }

    return true
  }

  @IBAction func openSettings(_ sender: Any?) {
    invokeMenuAction("openSettings")
  }

  @IBAction func menuBackup(_ sender: Any?) {
    invokeMenuAction("backup")
  }

  @IBAction func menuExpressBackup(_ sender: Any?) {
    invokeMenuAction("express-backup")
  }

  @IBAction func menuMonit(_ sender: Any?) {
    invokeMenuAction("monit")
  }

  @IBAction func menuShare(_ sender: Any?) {
    invokeMenuAction("share")
  }

  @IBAction func menuViewtree(_ sender: Any?) {
    invokeMenuAction("viewtree")
  }

  private func readFilePaths(from pboard: NSPasteboard) -> [String] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    if let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
       !urls.isEmpty {
      return urls.map { $0.path }
    }
    if let paths = pboard.propertyList(forType: .fileURL) as? [String], !paths.isEmpty {
      return paths
    }
    if let path = pboard.string(forType: .fileURL), !path.isEmpty {
      return [path]
    }
    return []
  }

  @objc func vertreeBackup(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
    for path in readFilePaths(from: pboard) {
      invokeServiceAction("backup", path: path)
    }
  }

  @objc func vertreeExpressBackup(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
    for path in readFilePaths(from: pboard) {
      invokeServiceAction("express-backup", path: path)
    }
  }

  @objc func vertreeMonit(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
    for path in readFilePaths(from: pboard) {
      invokeServiceAction("monit", path: path)
    }
  }

  @objc func vertreeShare(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
    for path in readFilePaths(from: pboard) {
      invokeServiceAction("share", path: path)
    }
  }

  @objc func vertreeViewtree(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
    for path in readFilePaths(from: pboard) {
      invokeServiceAction("viewtree", path: path)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {

    return false
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupDockChannelIfNeeded()
    scheduleDockIconRefresh()



    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      self?.flushPendingServiceActions()
      self?.setupDockChannelIfNeeded()
      self?.scheduleDockIconRefresh()
    }
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    super.applicationDidBecomeActive(notification)
    setupDockChannelIfNeeded()
    scheduleDockIconRefresh()
    flushPendingServiceActions()
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    var handled = false

    for url in urls {
      if url.isFileURL {
        invokeServiceAction("viewtree", path: url.path)
        handled = true
        continue
      }

      if handleVertreeURL(url) {
        handled = true
      }
    }

    if !handled {
      super.application(application, open: urls)
    }
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {

    for path in filenames {
      invokeServiceAction("viewtree", path: path)
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
