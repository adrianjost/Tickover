import AppKit

/// Menu bar item showing the overtime. Any click shows its menu, like other menu bar apps.
final class StatusItemController: NSObject, NSMenuDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()
  private let extraMenuItems: () -> [NSMenuItem]
  private let onOpen: () -> Void

  init(
    title: String, extraMenuItems: @escaping () -> [NSMenuItem], onOpen: @escaping () -> Void
  ) {
    self.extraMenuItems = extraMenuItems
    self.onOpen = onOpen
    super.init()

    statusItem.button?.font = .monospacedDigitSystemFont(
      ofSize: NSFont.systemFontSize, weight: .regular)
    menu.delegate = self
    statusItem.menu = menu
    setTitle(title)
  }

  func setTitle(_ title: String) {
    statusItem.button?.title = title
  }

  func remove() {
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    menu.addItem(MenuAction.item("Open Tickover", key: "", onOpen))
    let extra = extraMenuItems()
    if !extra.isEmpty {
      menu.addItem(.separator())
      extra.forEach(menu.addItem)
    }
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
  }
}

/// A menu item that runs a closure.
final class MenuAction: NSObject {
  private let handler: () -> Void

  private init(_ handler: @escaping () -> Void) {
    self.handler = handler
  }

  static func item(_ title: String, key: String, _ handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: key)
    item.target = action
    item.representedObject = action  // the item keeps its target alive
    return item
  }

  @objc private func run() {
    handler()
  }
}
