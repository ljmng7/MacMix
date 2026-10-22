import AppKit
import SwiftUI
import MacMixStudio

/// NSMenuItem.image is explicit here: native SwiftUI toggle-menu rows can discard
/// a custom label's image when reserving their checkmark column.
struct NativeEqualizerPresetPicker: NSViewRepresentable {
    let presets: [EqualizerPreset]
    let userPresetIDs: Set<String>
    let configuration: EqualizerConfiguration
    let imageForPreset: (EqualizerPreset) -> NSImage
    let onSelect: (String) -> Void
    let onOverwrite: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.isBordered = false
        button.autoenablesItems = false
        button.alignment = .left
        if let cell = button.cell as? NSPopUpButtonCell {
            // Commands may become the menu's selection during tracking. Keep the
            // displayed preset independent so command titles never flash here.
            cell.usesItemFromMenu = false
            cell.altersStateOfSelectedItem = false
            cell.menuItem = context.coordinator.displayItem
        }
        button.setAccessibilityLabel(String(localized: "EQ Preset"))
        context.coordinator.button = button
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let isCustom = configuration.presetID == "custom"
        if coordinator.presets != presets || coordinator.userIDs != userPresetIDs || coordinator.hasCustom != isCustom {
            coordinator.rebuild()
        }
        if isCustom, coordinator.customGains != configuration.normalizedGains {
            coordinator.customGains = configuration.normalizedGains
            coordinator.item("custom")?.image = imageForPreset(EqualizerPreset(id: "custom", name: "Custom", gains: configuration.normalizedGains))
            button.needsDisplay = true
        }
        coordinator.restoreSelection()
        let isUserPreset = userPresetIDs.contains(configuration.presetID)
        let canSave = isCustom || isUserPreset
        if let save = coordinator.item("save") {
            let title = isUserPreset ? String(localized: "Save as New Preset…") : String(localized: "Save as Preset…")
            if save.title != title { save.title = title }
            if save.isEnabled != canSave { save.isEnabled = canSave }
        }
        let savedPreset = presets.first { $0.id == configuration.presetID }
        let hasPresetChanges = isUserPreset && savedPreset.map {
            $0.gains != configuration.normalizedGains
                || $0.toneGains != configuration.normalizedToneGains
        } == true
        let hidesSave = isUserPreset && !hasPresetChanges
        if let save = coordinator.item("save"), save.isHidden != hidesSave {
            save.isHidden = hidesSave
        }
        if let overwrite = coordinator.item("overwrite"), overwrite.isHidden != !hasPresetChanges {
            overwrite.isHidden = !hasPresetChanges
        }
        let hidesDelete = !isUserPreset
        if let delete = coordinator.item("delete"), delete.isHidden != hidesDelete { delete.isHidden = hidesDelete }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let ideal = nsView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? 165, ideal.width), height: max(20, ideal.height))
    }

    @MainActor final class Coordinator: NSObject {
        var parent: NativeEqualizerPresetPicker
        weak var button: NSPopUpButton?
        var presets: [EqualizerPreset] = []
        var userIDs: Set<String> = []
        var hasCustom = false
        var customGains: [Double] = []
        let displayItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        init(parent: NativeEqualizerPresetPicker) { self.parent = parent }
        func item(_ id: String) -> NSMenuItem? {
            button?.menu?.items.first { $0.representedObject as? String == id }
        }
        func addItem(_ title: String, id: String, image: NSImage?, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.image = image
            menu.addItem(item)
        }
        func rebuild() {
            presets = parent.presets; userIDs = parent.userPresetIDs
            hasCustom = parent.configuration.presetID == "custom"
            let menu = NSMenu()
            menu.autoenablesItems = false
            let builtIn = presets.filter { !userIDs.contains($0.id) }
            func addPreset(_ preset: EqualizerPreset) {
                addItem(String(localized: String.LocalizationValue(preset.name)), id: preset.id,
                        image: parent.imageForPreset(preset), to: menu)
            }
            if let flat = builtIn.first(where: { $0.id == "flat" }) { addPreset(flat) }
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: String(localized: "MUSIC")))
            let effectIDs = ["acoustic", "vocal", "bass", "bass-reducer", "treble", "treble-reducer"]
            for preset in builtIn where preset.id != "flat" && !effectIDs.contains(preset.id) {
                addPreset(preset)
            }
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: String(localized: "EFFECT")))
            for id in effectIDs {
                if let preset = builtIn.first(where: { $0.id == id }) { addPreset(preset) }
            }
            if !userIDs.isEmpty {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: String(localized: "My Presets")))
                for preset in presets where userIDs.contains(preset.id) {
                    addItem(preset.name, id: preset.id, image: parent.imageForPreset(preset), to: menu)
                }
            }
            if hasCustom {
                addItem(String(localized: "Custom"), id: "custom", image: parent.imageForPreset(
                    EqualizerPreset(id: "custom", name: "Custom", gains: parent.configuration.normalizedGains)), to: menu)
            }
            menu.addItem(.separator())
            addItem(String(localized: "Overwrite Original Preset"), id: "overwrite", image: nil, to: menu)
            addItem(String(localized: "Save as New Preset…"), id: "save", image: nil, to: menu)
            addItem(String(localized: "Delete Preset"), id: "delete", image: nil, to: menu)
            button?.menu = menu
        }
        func restoreSelection() {
            displaySelection(parent.configuration.presetID)
        }
        func displaySelection(_ id: String) {
            if let selected = item(id) {
                if button?.selectedItem !== selected { button?.select(selected) }
                if displayItem.title != selected.title {
                    displayItem.title = selected.title
                    button?.invalidateIntrinsicContentSize()
                }
                if displayItem.image !== selected.image { displayItem.image = selected.image }
                if let cell = button?.cell as? NSPopUpButtonCell {
                    cell.menuItem = displayItem
                }
            }
            for item in button?.menu?.items ?? [] {
                let state: NSControl.StateValue = item.representedObject as? String == id ? .on : .off
                if item.state != state { item.state = state }
            }
        }
        @objc func selectItem(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String else { return }
            switch id {
            case "overwrite": restoreSelection(); parent.onOverwrite()
            case "save": restoreSelection(); parent.onSave()
            case "delete": restoreSelection(); parent.onDelete()
            case "custom": restoreSelection()
            default:
                // Update the native label during the selection action rather than
                // waiting for SwiftUI to deliver the changed configuration.
                displaySelection(id)
                button?.needsDisplay = true
                button?.displayIfNeeded()
                parent.onSelect(id)
            }
        }
    }
}
