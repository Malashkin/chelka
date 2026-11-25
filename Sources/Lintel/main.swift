import AppKit
import LintelCore

// До переименования приложение звалось Chelka (dev.mike.Chelka): переносим
// настройки один раз, до того как кто-либо их прочитает.
let migrated = Settings.migrate()
if migrated > 0 { NSLog("Lintel: перенесено настроек из \(Settings.legacyDomain): \(migrated)") }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
