# AirPods controls from an ordinary macOS process

Investigation date: 2026-08-22

Test system: macOS 27.0 (26A5416b)

Test device: connected AirPods Pro

Target plugin SHA-256: `68f181f21b5be0ee248f7ad7e44b70d043a86bd7efcc5c0db307616878fac09f`

This document records interfaces observed on this specific macOS build. The
selectors are private implementation details, not stable API. They must be
feature-detected at runtime.

## Result

Noise Cancellation, Transparency, Adaptive Audio, and per-process Spatial
Audio can be read and changed by a normal process through undocumented
CoreAudio HAL properties. No private entitlement, helper daemon, code
injection, or modification of macOS is needed.

The verified property is:

| HAL property | FourCC | Type | Settable | Verified values |
| --- | --- | --- | --- | --- |
| `kAudioDevicePropertyListenMode` | `lstm` | `UInt32` | Yes | `2` Noise Cancellation, `3` Transparency, `4` Adaptive Audio |
| `kAudioDevicePropertyListenModeSupport` | `lsms` | `UInt32` bit mask | No | `0x7` on the tested device |

Both the value returned by `AudioObjectGetPropertyData` and the selected state
in System Settings changed immediately. A setter call returned `noErr`, and an
immediate read-back returned the requested value.

The repository contains a standalone proof-of-concept at
`Tools/airpodsctl.c`. It implements only the commands whose behavior was
verified:

```sh
clang -Wall -Wextra -framework CoreAudio -framework CoreFoundation \
  Tools/airpodsctl.c -o /tmp/airpodsctl

/tmp/airpodsctl status
/tmp/airpodsctl anc
/tmp/airpodsctl transparency
/tmp/airpodsctl adaptive
/tmp/airpodsctl spatial off <pid> [stereo|multichannel]
/tmp/airpodsctl spatial fixed <pid> [stereo|multichannel]
/tmp/airpodsctl spatial head-tracked <pid> [stereo|multichannel]
```

The tool selects the default output device when it exposes `lstm`; otherwise it
requires exactly one connected Bluetooth output device exposing the property.
It checks `AudioObjectHasProperty`, checks settable state, checks the support
mask, and reads the value back after setting it. Spatial settings are scoped to
the process that owns the audio stream, so those commands require its PID.

## Existing probes inspected

The investigation reused the existing Desktop probes instead of replacing
them:

- `airpods_probe.m` loads AudioAccessoryServices and AVFoundation and enumerates
  runtime classes and methods.
- `airpods_inspect.m` prints Objective-C method encodings.
- `airpods_state.m` probes the private `IOBluetoothDevice` listening-mode
  methods.
- `aa_monitor_probe.m` enumerates AudioAccessoryServices classes.
- `aa_devices.m` constructs `AADeviceManager` and fetches paired accessory
  devices.

The `AADeviceManager` path is not usable by a normal third-party process.
Calling `activateWithCompletion:` fails with `BTErrorDomain` code `-71168`,
`kMissingEntitlementErr`, for the entitlement
`com.apple.AudioAccessoryServices`.

Private AVFoundation runtime methods were also present, including
`currentBluetoothListeningMode`, `setCurrentBluetoothListeningMode:error:`,
conversation-detection methods, and head-tracked spatial-audio methods. Their
presence does not make them a supported or entitlement-free control path.

## BTAudioHALPlugin static analysis

Target:

`/System/Library/Audio/Plug-Ins/HAL/BTAudioHALPlugin.driver/Contents/MacOS/BTAudioHALPlugin`

It is a universal `x86_64`/`arm64e` Mach-O bundle with identifier
`com.apple.audio.BTAudioHALPlugin`. Most device implementation is stripped C++,
but Objective-C metadata exposes these concrete classes:

- `BTAudioPersonalizedVolumeDevice`
- `BTAudioSmartRouteManager`
- `LocalizedStrings`
- `SpatialAudioQueue`
- `SpatialAudioClient`
- `BTHearingHealthObject`
- `BTAudioSmartRouteDevice`
- `BTAudioSmartRouteSession`
- `USBDevice`
- `USBMetric`
- `USBDeviceManager`

Notable selectors include:

- `-[BTAudioPersonalizedVolumeDevice initWithBluetoothInfo:deviceAddr:]`
- `-[BTAudioPersonalizedVolumeDevice NotifyManualVolumeChanged:shouldUpdateBuds:]`
- `-[SpatialAudioClient initWithPid:deviceID:]`
- `-[SpatialAudioClient UpdateSpatialAudioQueueInfo:]`
- `-[SpatialAudioClient spatialAudioUserSelection]`
- `-[SpatialAudioClient setSpatialAudioUserSelection:]`
- `-[SpatialAudioClient spatialAudioHeadTrackingUserSelection]`
- `-[SpatialAudioClient setSpatialAudioHeadTrackingUserSelection:]`

These classes live inside the CoreAudio plugin and are not themselves a public
client API.

## XPC services and access checks

The plugin uses raw libxpc rather than `NSXPCConnection` for the relevant
services.

Observed service roles:

| Service | Plugin role | Finding |
| --- | --- | --- |
| `com.apple.BTAudioHALPlugin.xpc` | Client connection | Internal connection toward `bluetoothd` |
| `com.apple.BTAudioHALPluginAccessories` | Mach-service listener | Incoming clients are code-signing-identity checked |
| `com.apple.accessory.AudioDevice.xpc` | Mach-service listener | Accessory/USB-related messaging |
| `com.apple.AudioAccessoryCommunication.xpc` | Mach-service listener | Incoming clients are identity checked |

On the x86_64 slice, the incoming connection path around file offsets
`0x49e8c` and `0x4800e` calls:

1. `xpc_connection_get_audit_token`
2. `xpc_copy_code_signing_identity_for_token`
3. string comparisons against exactly `com.apple.audioaccessoryd` and
   `com.apple.cloudpaird`
4. `xpc_connection_cancel` for an unrecognized identity

The plugin also contains the diagnostic string:

`Client %s is not allowed to xpc into accessory communication service.`

Therefore `com.apple.BTAudioHALPluginAccessories` is not a viable normal-app
interface. It is protected by an explicit Apple process identity allowlist,
even though the service lookup itself is visible to other processes. Rebuilding
the message dictionary would not bypass this check.

`/System/Library/CoreServices/audioaccessoryd` contains references to both
`com.apple.BTAudioHALPluginAccessories` and
`com.apple.AudioAccessoryCommunication.xpc`, confirming it as a system client.
On this build its code-signing identifier reports as `com.apple.cloudpaird`,
which also explains why both identities appear in the allowlist.

Internal message/property strings found in the plugin include:

- `kBTAudioMsgPropertyListenMode`
- `kBTAudioMsgPropertyListenModeSupported`
- `kBTAudioMsgPropertyAdaptiveVolume`
- `kBTAudioMsgPropertyAdaptiveVolumeMode`
- `kBTAudioMsgPropertyConversationDetect`
- `kBTAudioMsgPropertyHeadTrack`
- `kBTAudioMsgPropertyAllowSpatialAudio`
- `kBTAudioMsgPropertySpatialAudioAppBasedMode`

These describe the plugin's privileged Bluetooth transport protocol. They are
not proof that an ordinary process can send the messages.

## CoreAudio HAL properties

The following selectors were recovered from the plugin's property dispatch and
then queried from a normal process. All returned a four-byte `UInt32` on the
tested AirPods. Global, output, and input scopes resolved to the same underlying
device values; the proof-of-concept uses global scope and main element.

| Plugin property name | FourCC | Read | HAL says settable | Tested setter |
| --- | --- | --- | --- | --- |
| `kAudioDevicePropertyListenMode` | `lstm` | Yes | Yes | Yes |
| `kAudioDevicePropertyListenModeSupport` | `lsms` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertyAdaptiveVolumeEnabled` | `advl` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertySpatialAudioSupported` | `spap` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertySpatialAudioEnabled` | `spen` | Yes | Yes | No |
| `kBluetoothAudioDevicePropertyHeadTrackingAvailable` | `htav` | Yes | Yes | No; name suggests it is not a user preference |
| `kBluetoothAudioDevicePropertyHeadTrackingStatus` | `htst` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertyHeadTrackingAccessibility` | `htac` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertySpatialCCState` | `spcs` | Yes | Yes | Payload mapped; multichannel live write not yet tested |
| `kBluetoothAudioDevicePropertySpatializeStereoCCState` | `spss` | Yes | Yes | Yes; stereo content |
| `kBluetoothAudioDevicePropertySpatializeStereoCCIsAvail` | `spsv` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertyIsAudioSessionSpatial` | `iass` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertySpatialMode` | `spmd` | Yes | No | N/A |
| `kBluetoothAudioDevicePropertySpatialAudioUserEnableFeature` | `sphs` | Yes | No | N/A |
| Bluetooth feature mask | `btsf` | Yes, 8 bytes | No | N/A |

`iaap` also exists as a readable property on the tested device and appears to
correspond to spatial Control Center availability, but its exact symbolic name
has not yet been proven and it is intentionally omitted from the CLI.

The plugin contains getter diagnostics for additional properties such as
`SpatialMode`, `SpatialAudioUserEnableFeature`, personalized-volume DRC state,
in-ear state, live-listen support, and genuine-AirPods state. Their FourCC or
setter semantics have not all been mapped.

## Feature-by-feature feasibility

### Noise Cancellation, Transparency, Adaptive Audio

Implemented and verified through `AudioObjectSetPropertyData` on `lstm`.

The observed mapping is:

| Mode | Value | Support-mask bit |
| --- | --- | --- |
| Noise Cancellation | `2` | `0x1` |
| Transparency | `3` | `0x2` |
| Adaptive Audio | `4` | `0x4` |

An `Off` value of `1` appears plausible from surrounding private APIs, but was
not offered by the tested device UI and was not written.

### Adaptive Audio strength (macOS 27)

macOS 27 exposes Adaptive Audio strength separately from the `lstm` listening
mode. Setting `lstm = 4` selects Adaptive Audio but does not select a strength.
The tested AirPods report Auto ANC capability `Version3`.

A live trace while moving the System Settings slider from Low through High and
back to Medium established the complete device mapping:

| System value | `AAAutoANCStrength` label | AACP value |
| --- | --- | --- |
| `0` | Low | `0` |
| `1` | Step1 | `10` |
| `2` | Step2 | `20` |
| `3` | Step3 | `30` |
| `4` | Step4 | `40` |
| `5` | Medium | `50` |
| `6` | Step6 | `60` |
| `7` | Step7 | `70` |
| `8` | Step8 | `80` |
| `9` | Step9 | `90` |
| `10` | High | `100` |

For every change, `audioaccessoryd` sent an `AADeviceConfig` containing
`autoANCStrength`. `bluetoothd` then emitted AACP control command `0x2E`; for
example, Medium produced `0x00000032` / decimal `50`, Low produced `0`, and
High produced `0x00000064` / decimal `100`. This confirms that the 11 slider
positions are exact 10-point steps rather than additional `lstm` values.

The system `HeadphoneSettingsExtension` carries
`com.apple.AudioAccessoryServices` and Bluetooth private entitlements. A normal
process cannot activate `AADeviceManager`, and no corresponding writable
CoreAudio HAL property has been found in `BTAudioHALPlugin`. Therefore the
protocol and value mapping are known, but Adaptive Audio strength is not yet
implemented by `airpodsctl` or usable by MacMix without discovering a separate
entitlement-free user-space interface.

### Personalized/Adaptive Volume

`advl` provides a useful read-only enabled state. On the tested device it
returned `1`, but CoreAudio reports it as not settable. The plugin receives
adaptive-volume configuration over its internal Bluetooth XPC protocol and has
a `BTAudioPersonalizedVolumeDevice` implementation, but no ordinary-process
setter has been identified.

### Conversation Awareness

The plugin contains `kBTAudioMsgPropertyConversationDetect`, and
AudioAccessoryServices exposes `conversationDetectConfig` and
`setConversationDetectConfig:`. No corresponding HAL property getter/setter
was found in `BTAudioHALPlugin`, and the AudioAccessoryServices manager path is
entitlement protected.

Unified logging while changing the switch in System Settings established the
device protocol:

- AACP control command: `0x28`
- configuration value `1`: enabled
- configuration value `2`: disabled
- `audiomxd` reports the resulting `ConversationDetectEnable` state as a
  conventional `1` or `0`

The configuration must therefore not be treated as a simple `0`/`1` boolean at
the Bluetooth protocol boundary.

Additional ordinary-process paths were tested:

- `CBController` exposes `sendConversationDetectMessage:device:completionHandler:`
  and `CBDeviceSettings.conversationDetectConfig`. A targeted same-value write
  constructed a `CBDeviceSettings` object whose runtime description was
  `CDC Disabled`, set only `conversationDetectConfig = 2`, and called
  `modifyDevice:settings:completion:`. The completion returned
  `CBErrorDomain -71168` with `Missing entitlement:
  com.apple.bluetooth.system`; no device command was sent.
- A lower-level `CBConnection` was constructed for the connected AirPods with
  service flags `0x80000 < AACP >` and connection flags
  `DontAutoRoute | WaitConnectedServices | AudioRouteHidden`. Activation, with
  no payload sent, returned the same missing `com.apple.bluetooth.system`
  entitlement. Consequently a normal process cannot bypass the settings API
  by opening the raw AACP service either.
- MediaRemote exposes
  `setConversationDetectionEnabled:outputDeviceUID:queue:completion:` on
  `MRAVEndpoint` and related classes. Unified logging showed that MediaRemote's
  actual AirPods identifier uses the form `AA-BB-CC-DD-EE-FF`, without CoreAudio's
  `:output` suffix. It also showed a descriptor with
  `supportsConversationDetection = 1`. Nevertheless, a normal process can
  instantiate only an empty `MRAVLocalEndpoint`; its `externalDevice` is nil.
  Same-value setter attempts with both the HAL UID and the correct MediaRemote
  UID return error 39, “Could not find the given outputDevice.”
- `MRActiveRoutesObserver` and
  `MRAVEndpoint.directEndpointForOutputDeviceUIDs:queue:completion:` were also
  tested. The active local endpoint still contained no AirPods output object;
  direct discovery with both UID forms returned error 47, “Could not discover
  outputDevice.” MediaRemote routing discovery returned empty endpoint and
  device snapshots, despite `mediaremoted` itself logging a populated
  `MRAVDistantEndpoint`. The `LOCAL` and `LOCAL_DEVICE` placeholder UIDs also
  returned error 39.
- AVFoundation exposes the matching methods on `AVOutputDevice`, but the
  ordinary process cannot obtain the system AirPods `AVOutputDevice` from the
  available shared output contexts on this build. Bluetooth discovery feature
  modes `1`, `2`, `4`, and `8` all returned empty device lists;
  `sharedLocalDevice.connectedPairedDevices` was also empty.

A Siri-triggered live trace confirmed the complete privileged implementation
path. At `14:05:57.060`, `assistant_service` connected to the
`com.apple.assistant.settings` Mach service owned by `assistantd`. One
millisecond later, `bluetoothd` logged:

- `conversationDetectConfig ... value 0x0001`
- `Set Conversation Detect config to 0x00000001`
- `Sent Conversation Detect (control cmd 0x28) as Enabled ... reqType = User`

The loaded Siri components were
`SettingsFlowDelegatePlugin` and the private
`SiriSettingsIntents.framework`. Runtime inspection of that framework found
the concrete Swift classes `SetConversationAwarenessHandler`,
`GetConversationAwarenessHandler`, `SetPersonalizedVolumeHandler`,
`GetPersonalizedVolumeHandler`, `SetNoiseManagementHandler`, and
`SettingsNativeApiClient`.

The `assistantd` Objective-C metadata exposes the exact broker protocol
`AFSettingsService`, including:

- `setConversationAwarenessForCurrentlyRoutedDevice:withCompletion:`
- `getConversationAwarenessForCurrentlyRoutedDevice:`
- `setPersonalVolumeForCurrentlyRoutedDevice:withCompletion:`
- `getPersonalVolumeForCurrentlyRoutedDevice:`
- `setHeadGesturesForCurrentlyRoutedDevice:withCompletion:`
- `getHeadGesturesForCurrentlyRoutedDevice:`
- `fetchCurrentlyRoutedHeadphonesCBUUIDWithCompletion:`

This initially appeared to be a possible normal-process broker, so a read-only
`NSXPCConnection` probe called the conversation-awareness getter. The Mach
service lookup succeeded outside the test harness sandbox, but `assistantd`
immediately rejected the peer. Its log states that the client must have either
`com.apple.private.assistant.settings` or
`com.apple.private.assistant.client`. Both `assistantd` and
`assistant_service` also carry `com.apple.bluetooth.system`; `assistantd`
additionally carries `com.apple.AudioAccessoryServices`. Therefore the Siri
route is another entitlement-protected broker, not a reusable interface for a
normally signed application.

The trace also distinguished Siri microphone-session signaling from the user
preference write. While Siri was listening, `audioaccessoryd` sent
Conversation Detect event payload `<030103>`; when microphone use ended it sent
`<030000>`. The actual preference change was the separate AACP control command
`0x28` with configuration value `1`. Those three-byte event payloads must not
be mistaken for the persistent setting protocol.

Thus the low-level value mapping and both direct private setter shapes are
known, but neither is available to a normally signed ordinary process on this
build: CoreBluetooth requires an Apple-only entitlement, while MediaRemote
withholds the required distant output-device object, and the Siri settings
broker requires a private Assistant entitlement. Shortcut-based control is
deliberately excluded from the implementation.

Static analysis showed that the Conversation Detect capability updates the
read-only `btsf` Bluetooth-feature mask, not a writable conversation HAL
property. `btsf` was present as an eight-byte CF object containing a read-only
dictionary entry `kBluetoothAudioDeviceFeatureConversationDetect = 1`.
Attempting to write the unchanged object back returned OSStatus `nope`.
Recursive enumeration of the AirPods CoreAudio device, stream, mute, volume,
and toggle child objects found no conversation control. A targeted scan for
likely conversation selectors (`conv`, `cdet`, `cden`, `cvdt`, and related
variants) found none, and the complete plugin device-property setter dispatch
has no conversation branch.

### Spatial Audio and head tracking

`spcs` and `spss` do not accept the four-byte value returned by their getters.
Disassembly and live tests established an eight-byte setter payload:

```c
struct SpatialRequest {
    int32_t processID;
    uint8_t headTracking;
    uint8_t enabled;
    uint8_t reserved[2];
};
```

`spcs` controls native/multichannel spatial content; `spss` controls
spatialized stereo. The mappings verified against a live Music process are:

| User mode | `enabled` | `headTracking` |
| --- | --- | --- |
| Off | `0` | `0` |
| Fixed | `1` | `0` |
| Head Tracked | `1` | `1` |

All three `spss` writes returned `noErr` and changed the corresponding HAL
state. The change may settle asynchronously; the CLI polls read-back for up to
two seconds instead of treating the first value as final. Off and Head Tracked
were re-tested through the final CLI, and the original Head Tracked state was
restored. The setter is process-specific; the PID must be the application that
owns the active audio stream. `spen` and `htav` are still intentionally not
written even though HAL labels them settable, because they are not the
user-mode request interface.

### Left, right, and charging-case battery levels

All three battery values are readable without changing the accessory. On the
tested connected AirPods, the following normal user-space command returned
stable JSON keys for left, right, and case battery levels:

```sh
system_profiler SPBluetoothDataType -json -detailLevel mini
```

The relevant keys are `device_batteryLevelLeft`,
`device_batteryLevelRight`, and `device_batteryLevelCase`. The compact report
completed in approximately 0.06 seconds in a warm test and returned, for
example, left `75%`, right `80%`, and case `67%`. macOS may report the same
AirPods twice: a BLE case entry containing only the case battery and the main
audio entry containing all available values. A client must merge entries
carefully rather than assuming the display name is unique.

Private `IOBluetoothDevice` runtime selectors `batteryPercentLeft`,
`batteryPercentRight`, `batteryPercentCase`, `batteryPercentCombined`, and
`batteryPercentSingle` are callable from an ordinary process. Left and right
returned current cached values, but the case selector returned `0` on the
tested device even while `system_profiler` reported `67%`; it is therefore not
sufficient as the only source.

The underlying private `CBDevice` model also exposes `batteryLevelMain`,
`batteryLevelLeft`, `batteryLevelRight`, and `batteryLevelCase`. However, a
normal-process call to
`+[CBDiscovery devicesWithDiscoveryFlags:error:]` using the same `0xA00000`
flags found in `SPBluetoothReporter` failed with `CBErrorDomain -71168`,
missing `com.apple.bluetooth.system`. MacMix should use the read-only compact
`system_profiler` JSON as the compatibility path, refresh it off the main
thread, cache the result, and treat absent keys as unknown rather than zero.

## Safety and compatibility requirements

- Never assume these selectors exist; call `AudioObjectHasProperty`.
- Check `AudioObjectIsPropertySettable` before every write.
- Confirm device transport is Bluetooth and that it has output streams.
- Prefer the default output device; do not silently modify every paired device.
- Check `lsms` before changing listening mode.
- Read back every write.
- Treat OS updates as a compatibility boundary and retain a runtime fallback.
- Do not attempt to connect to the identity-allowlisted accessory XPC services,
  inject into their clients, or forge their signatures/entitlements.
