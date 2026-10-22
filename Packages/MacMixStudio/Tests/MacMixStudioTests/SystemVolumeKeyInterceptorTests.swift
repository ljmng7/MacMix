import IOKit.hidsystem
import XCTest
@testable import MacMixStudio

final class SystemVolumeKeyInterceptorTests: XCTestCase {
    func testDecodesVolumeKeyDownEvents() {
        XCTAssertEqual(
            SystemVolumeKeyInterceptor.action(
                forMediaKeyData: mediaKeyData(code: NX_KEYTYPE_SOUND_UP)
            ),
            .increase
        )
        XCTAssertEqual(
            SystemVolumeKeyInterceptor.action(
                forMediaKeyData: mediaKeyData(code: NX_KEYTYPE_SOUND_DOWN)
            ),
            .decrease
        )
        XCTAssertEqual(
            SystemVolumeKeyInterceptor.action(
                forMediaKeyData: mediaKeyData(code: NX_KEYTYPE_MUTE)
            ),
            .toggleMute
        )
    }

    func testIgnoresKeyUpAndUnrelatedMediaKeys() {
        XCTAssertNil(
            SystemVolumeKeyInterceptor.action(
                forMediaKeyData: mediaKeyData(
                    code: NX_KEYTYPE_SOUND_UP,
                    state: 0xB
                )
            )
        )
        XCTAssertNil(
            SystemVolumeKeyInterceptor.action(
                forMediaKeyData: mediaKeyData(code: NX_KEYTYPE_PLAY)
            )
        )
    }

    private func mediaKeyData(code: Int32, state: Int = 0xA) -> Int {
        (Int(code) << 16) | (state << 8)
    }
}
