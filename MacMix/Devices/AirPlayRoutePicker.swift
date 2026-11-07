//
//  AirPlayRoutePicker.swift
//  MacMix
//

import AppKit
import AVKit
import SwiftUI

extension Notification.Name {
    // `object` is whether the picker is now open.
    static let airPlayRoutePickerPresentationChanged = Notification.Name("MacMix.AirPlayRoutePickerPresentationChanged")
}

// Apps cannot connect an AirPlay receiver through public API; the system route
// picker does, after which Core Audio publishes the output as usual.
@MainActor
final class AirPlayRoutePickerController {
    // The popover closes on mouse down, before a row's click action runs on mouse up.
    private static let reopenGuard: TimeInterval = 0.5

    fileprivate weak var pickerView: AVRoutePickerView?
    fileprivate var isOpen = false
    fileprivate var closedAt = Date.distantPast

    func toggle() {
        guard !isOpen, Date().timeIntervalSince(closedAt) > Self.reopenGuard else { return }
        pickerView.flatMap(Self.button)?.performClick(nil)
    }

    private static func button(in view: NSView) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton ?? button(in: subview) { return button }
        }
        return nil
    }
}

struct AirPlayRoutePicker: NSViewRepresentable {
    let controller: AirPlayRoutePickerController
    var onPresent: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, onPresent: onPresent) }

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.delegate = context.coordinator
        controller.pickerView = view
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        controller.pickerView = view
        context.coordinator.onPresent = onPresent
    }

    @MainActor
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        private let controller: AirPlayRoutePickerController
        var onPresent: () -> Void

        init(controller: AirPlayRoutePickerController, onPresent: @escaping () -> Void) {
            self.controller = controller
            self.onPresent = onPresent
        }

        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            controller.isOpen = true
            onPresent()
            NotificationCenter.default.post(name: .airPlayRoutePickerPresentationChanged, object: true)
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            controller.isOpen = false
            controller.closedAt = Date()
            NotificationCenter.default.post(name: .airPlayRoutePickerPresentationChanged, object: false)
        }
    }
}
