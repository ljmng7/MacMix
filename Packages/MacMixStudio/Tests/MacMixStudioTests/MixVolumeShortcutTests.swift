import CoreGraphics
import XCTest
@testable import MacMixStudio

final class MixVolumeShortcutTests: XCTestCase {
    func testRoundsAfterTenPercentagePointStep() {
        XCTAssertEqual(MixVolumeStep.volume(0.43, action: .increase), 0.5)
        XCTAssertEqual(MixVolumeStep.volume(0.43, action: .decrease), 0.3)
        XCTAssertEqual(MixVolumeStep.volume(0.49, action: .increase), 0.6)
        XCTAssertEqual(MixVolumeStep.volume(0.5, action: .increase), 0.6)
        XCTAssertEqual(MixVolumeStep.volume(0.5, action: .decrease), 0.4)
        XCTAssertEqual(MixVolumeStep.volume(0.03, action: .decrease), 0)
        XCTAssertEqual(MixVolumeStep.volume(1.43, action: .increase), 1.5)
        XCTAssertEqual(MixVolumeStep.volume(0.43, action: .toggleMute), 0.43)
    }

    func testDigitOrderAndReleaseAfterModifier() {
        var chord = MixVolumeChord(modifier: .control)
        let codes: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (index, code) in codes.enumerated() {
            XCTAssertTrue(chord.digit(keyCode: code, isDown: true, flags: .maskControl))
            XCTAssertEqual(chord.appIndex(flags: .maskControl), index)
            XCTAssertNil(chord.appIndex(flags: []))
            XCTAssertTrue(chord.digit(keyCode: code, isDown: false, flags: []))
            XCTAssertNil(chord.appIndex(flags: .maskControl))
        }
    }

    func testNormalTypingDisabledAndMultipleDigits() {
        var chord = MixVolumeChord(modifier: .option)
        XCTAssertFalse(chord.digit(keyCode: 18, isDown: true, flags: []))
        XCTAssertNil(chord.appIndex(flags: []))
        XCTAssertNil(chord.appIndex(flags: [.maskAlternate, .maskCommand]))
        XCTAssertFalse(chord.digit(keyCode: 18, isDown: false, flags: []))
        XCTAssertTrue(chord.digit(keyCode: 18, isDown: true, flags: .maskAlternate))
        XCTAssertTrue(chord.digit(keyCode: 19, isDown: true, flags: .maskAlternate))
        XCTAssertNil(chord.appIndex(flags: .maskAlternate))
        chord = MixVolumeChord(modifier: .disabled)
        XCTAssertFalse(chord.digit(keyCode: 18, isDown: true, flags: .maskControl))
        XCTAssertNil(chord.appIndex(flags: .maskControl))
    }

    func testFunctionKeys() {
        XCTAssertEqual(MixVolumeChord.functionAction(keyCode: 109), .toggleMute)
        XCTAssertEqual(MixVolumeChord.functionAction(keyCode: 103), .decrease)
        XCTAssertEqual(MixVolumeChord.functionAction(keyCode: 111), .increase)
        XCTAssertNil(MixVolumeChord.functionAction(keyCode: 100))
    }

    func testZeroDoesNotSelectTenthAppOrConsumeTyping() {
        var chord = MixVolumeChord(modifier: .control)
        XCTAssertFalse(chord.digit(keyCode: 29, isDown: true, flags: .maskControl))
        XCTAssertNil(chord.appIndex(flags: .maskControl))
        XCTAssertFalse(chord.digit(keyCode: 29, isDown: false, flags: .maskControl))
    }
}
