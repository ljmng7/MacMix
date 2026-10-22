//
//  HALPropertyReads.swift
//  MacMix
//

import CoreAudio
import Foundation

/// Reads a variable-length HAL AudioObjectID property without treating a failed
/// size/read pair as a valid empty list. HAL may resize these lists between calls.
nonisolated func readHALAudioObjectIDs(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    maximumAttempts: Int = 3
) -> [AudioObjectID]? {
    let elementSize = MemoryLayout<AudioObjectID>.stride

    for _ in 0..<max(maximumAttempts, 1) {
        var mutableAddress = address
        var requestedSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            objectID,
            &mutableAddress,
            0,
            nil,
            &requestedSize
        ) == noErr else {
            continue
        }

        guard requestedSize > 0 else {
            return []
        }
        guard Int(requestedSize).isMultiple(of: elementSize) else {
            continue
        }

        var objectIDs = Array(
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(requestedSize) / elementSize
        )
        var returnedSize = requestedSize
        let status = objectIDs.withUnsafeMutableBytes { storage in
            AudioObjectGetPropertyData(
                objectID,
                &mutableAddress,
                0,
                nil,
                &returnedSize,
                storage.baseAddress!
            )
        }

        guard status == noErr,
              returnedSize <= requestedSize,
              Int(returnedSize).isMultiple(of: elementSize) else {
            continue
        }

        let returnedCount = Int(returnedSize) / elementSize
        return objectIDs.prefix(returnedCount).filter { $0 != kAudioObjectUnknown }
    }

    return nil
}

nonisolated func readHALAudioObjectIDs(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
    maximumAttempts: Int = 3
) -> [AudioObjectID]? {
    readHALAudioObjectIDs(
        objectID: objectID,
        address: AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        ),
        maximumAttempts: maximumAttempts
    )
}
