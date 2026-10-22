// A small, entitlement-free AirPods control probe for macOS.
//
// Build:
//   clang -Wall -Wextra -framework CoreAudio -framework CoreFoundation \
//     Tools/airpodsctl.c -o /tmp/airpodsctl
//
// The private property selectors below were recovered from
// BTAudioHALPlugin and verified on macOS 27.0 (26A5416b). They are not API
// and may change in later macOS builds.

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define FOURCC(a,b,c,d) \
    ((UInt32)(a) << 24 | (UInt32)(b) << 16 | (UInt32)(c) << 8 | (UInt32)(d))

enum {
    kAirPodsPropertyListenMode = FOURCC('l', 's', 't', 'm'),
    kAirPodsPropertyListenModeSupport = FOURCC('l', 's', 'm', 's'),
    kAirPodsPropertyAdaptiveVolumeEnabled = FOURCC('a', 'd', 'v', 'l'),
    kAirPodsPropertySpatialAudioSupported = FOURCC('s', 'p', 'a', 'p'),
    kAirPodsPropertySpatialAudioEnabled = FOURCC('s', 'p', 'e', 'n'),
    kAirPodsPropertyHeadTrackingAvailable = FOURCC('h', 't', 'a', 'v'),
    kAirPodsPropertyHeadTrackingStatus = FOURCC('h', 't', 's', 't'),
    kAirPodsPropertySpatialControlCenterState = FOURCC('s', 'p', 'c', 's'),
    kAirPodsPropertySpatializeStereoControlCenterState = FOURCC('s', 'p', 's', 's'),
    kAirPodsPropertySpatialMode = FOURCC('s', 'p', 'm', 'd'),
    kAirPodsPropertySpatialAudioUserEnabled = FOURCC('s', 'p', 'h', 's'),
};

enum {
    kAirPodsListenModeNoiseCancellation = 2,
    kAirPodsListenModeTransparency = 3,
    kAirPodsListenModeAdaptive = 4,
};

typedef struct {
    AudioDeviceID id;
    CFStringRef name;
    CFStringRef uid;
} AirPodsDevice;

// BTAudioHALPlugin expects this exact eight-byte payload for 'spcs'/'spss'.
typedef struct {
    int32_t processID;
    uint8_t headTracking;
    uint8_t enabled;
    uint8_t reserved[2];
} AirPodsSpatialRequest;

_Static_assert(sizeof(AirPodsSpatialRequest) == 8,
               "AirPods spatial request ABI changed");

static AudioObjectPropertyAddress address_for(AudioObjectPropertySelector selector) {
    return (AudioObjectPropertyAddress) {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    };
}

static void fourcc_string(UInt32 value, char output[5]) {
    for (unsigned index = 0; index < 4; index++) {
        unsigned shift = 24 - index * 8;
        unsigned char byte = (value >> shift) & 0xff;
        output[index] = isprint(byte) ? (char)byte : '.';
    }
    output[4] = '\0';
}

static void print_status_error(const char *operation, OSStatus status) {
    char code[5];
    fourcc_string((UInt32)status, code);
    fprintf(stderr, "%s failed: %d ('%s')\n", operation, (int)status, code);
}

static CFStringRef copy_string_property(AudioObjectID object,
                                        AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = address_for(selector);
    CFStringRef result = NULL;
    UInt32 size = sizeof(result);
    OSStatus status = AudioObjectGetPropertyData(
        object, &address, 0, NULL, &size, &result
    );
    return status == noErr ? result : NULL;
}

static void print_cfstring(CFStringRef value) {
    if (!value) {
        printf("<unknown>");
        return;
    }
    char buffer[1024];
    if (CFStringGetCString(value, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
        printf("%s", buffer);
    } else {
        printf("<unprintable>");
    }
}

static bool has_output_streams(AudioDeviceID device) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreams,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain,
    };
    UInt32 size = 0;
    return AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) == noErr
        && size > 0;
}

static bool is_bluetooth_device(AudioDeviceID device) {
    AudioObjectPropertyAddress address = address_for(kAudioDevicePropertyTransportType);
    UInt32 transport = 0;
    UInt32 size = sizeof(transport);
    return AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &transport) == noErr
        && transport == kAudioDeviceTransportTypeBluetooth;
}

static bool read_uint32(AudioObjectID object,
                        AudioObjectPropertySelector selector,
                        UInt32 *result) {
    AudioObjectPropertyAddress address = address_for(selector);
    if (!AudioObjectHasProperty(object, &address)) return false;
    UInt32 size = sizeof(*result);
    return AudioObjectGetPropertyData(object, &address, 0, NULL, &size, result) == noErr
        && size == sizeof(*result);
}

static bool property_is_settable(AudioObjectID object,
                                 AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = address_for(selector);
    Boolean settable = false;
    return AudioObjectHasProperty(object, &address)
        && AudioObjectIsPropertySettable(object, &address, &settable) == noErr
        && settable;
}

static OSStatus copy_audio_devices(AudioDeviceID **devices, UInt32 *count) {
    AudioObjectPropertyAddress address = address_for(kAudioHardwarePropertyDevices);
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject, &address, 0, NULL, &size
    );
    if (status != noErr) return status;

    AudioDeviceID *result = malloc(size);
    if (!result) return kAudioHardwareUnspecifiedError;
    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject, &address, 0, NULL, &size, result
    );
    if (status != noErr) {
        free(result);
        return status;
    }
    *devices = result;
    *count = size / sizeof(AudioDeviceID);
    return noErr;
}

static bool make_airpods_device(AudioDeviceID id, AirPodsDevice *result) {
    AudioObjectPropertyAddress listenAddress = address_for(kAirPodsPropertyListenMode);
    if (!has_output_streams(id)
        || !is_bluetooth_device(id)
        || !AudioObjectHasProperty(id, &listenAddress)) {
        return false;
    }
    result->id = id;
    result->name = copy_string_property(id, kAudioObjectPropertyName);
    result->uid = copy_string_property(id, kAudioDevicePropertyDeviceUID);
    return true;
}

static void release_airpods_device(AirPodsDevice *device) {
    if (device->name) CFRelease(device->name);
    if (device->uid) CFRelease(device->uid);
    memset(device, 0, sizeof(*device));
}

static const char *listen_mode_name(UInt32 mode) {
    switch (mode) {
        case kAirPodsListenModeNoiseCancellation: return "noise-cancellation";
        case kAirPodsListenModeTransparency: return "transparency";
        case kAirPodsListenModeAdaptive: return "adaptive";
        case 1: return "off (unverified on this model)";
        default: return "unknown";
    }
}

static void print_bool_property(AudioDeviceID id,
                                const char *label,
                                AudioObjectPropertySelector selector) {
    UInt32 value = 0;
    if (read_uint32(id, selector, &value)) {
        printf("  %-29s %s (%u)%s\n",
               label,
               value ? "yes" : "no",
               value,
               property_is_settable(id, selector) ? " [settable]" : "");
    } else {
        printf("  %-29s unavailable\n", label);
    }
}

static int print_device_status(const AirPodsDevice *device) {
    printf("device: ");
    print_cfstring(device->name);
    printf("\nuid: ");
    print_cfstring(device->uid);
    printf("\naudio-object-id: %u\n", device->id);

    UInt32 mode = 0;
    if (read_uint32(device->id, kAirPodsPropertyListenMode, &mode)) {
        printf("  listening-mode:               %s (%u)%s\n",
               listen_mode_name(mode), mode,
               property_is_settable(device->id, kAirPodsPropertyListenMode)
                   ? " [settable]" : "");
    } else {
        printf("  listening-mode:               unavailable\n");
    }

    UInt32 support = 0;
    if (read_uint32(device->id, kAirPodsPropertyListenModeSupport, &support)) {
        printf("  listening-mode-support:       0x%x\n", support);
    }
    print_bool_property(device->id, "adaptive-volume-enabled:",
                        kAirPodsPropertyAdaptiveVolumeEnabled);
    print_bool_property(device->id, "spatial-audio-supported:",
                        kAirPodsPropertySpatialAudioSupported);
    print_bool_property(device->id, "spatial-audio-enabled:",
                        kAirPodsPropertySpatialAudioEnabled);
    print_bool_property(device->id, "head-tracking-available:",
                        kAirPodsPropertyHeadTrackingAvailable);
    print_bool_property(device->id, "head-tracking-status:",
                        kAirPodsPropertyHeadTrackingStatus);
    print_bool_property(device->id, "spatial-user-enabled:",
                        kAirPodsPropertySpatialAudioUserEnabled);

    UInt32 spatialMode = 0;
    if (read_uint32(device->id, kAirPodsPropertySpatialMode, &spatialMode)) {
        printf("  spatial-mode:                 %u\n", spatialMode);
    }

    UInt32 spatialState = 0;
    if (read_uint32(device->id, kAirPodsPropertySpatialControlCenterState,
                    &spatialState)) {
        printf("  spatial-control-center-state: %u%s\n",
               spatialState,
               property_is_settable(device->id,
                                    kAirPodsPropertySpatialControlCenterState)
                   ? " [settable]" : "");
    }
    UInt32 stereoState = 0;
    if (read_uint32(device->id,
                    kAirPodsPropertySpatializeStereoControlCenterState,
                    &stereoState)) {
        printf("  spatialize-stereo-state:      %u%s\n",
               stereoState,
               property_is_settable(
                   device->id,
                   kAirPodsPropertySpatializeStereoControlCenterState
               ) ? " [settable]" : "");
    }
    return 0;
}

static int status_command(void) {
    AudioDeviceID *devices = NULL;
    UInt32 count = 0;
    OSStatus status = copy_audio_devices(&devices, &count);
    if (status != noErr) {
        print_status_error("Audio device enumeration", status);
        return 1;
    }

    unsigned matches = 0;
    for (UInt32 index = 0; index < count; index++) {
        AirPodsDevice device = {0};
        if (!make_airpods_device(devices[index], &device)) continue;
        if (matches++) printf("\n");
        print_device_status(&device);
        release_airpods_device(&device);
    }
    free(devices);
    if (!matches) {
        fprintf(stderr, "No connected Bluetooth output device exposing 'lstm' was found.\n");
        return 2;
    }
    return 0;
}

static AudioDeviceID default_output_device(void) {
    AudioObjectPropertyAddress address = address_for(
        kAudioHardwarePropertyDefaultOutputDevice
    );
    AudioDeviceID result = kAudioObjectUnknown;
    UInt32 size = sizeof(result);
    return AudioObjectGetPropertyData(
        kAudioObjectSystemObject, &address, 0, NULL, &size, &result
    ) == noErr ? result : kAudioObjectUnknown;
}

static int select_control_device(AirPodsDevice *selected) {
    AudioDeviceID preferred = default_output_device();
    if (preferred != kAudioObjectUnknown && make_airpods_device(preferred, selected)) {
        return 0;
    }

    AudioDeviceID *devices = NULL;
    UInt32 count = 0;
    OSStatus status = copy_audio_devices(&devices, &count);
    if (status != noErr) {
        print_status_error("Audio device enumeration", status);
        return 1;
    }
    unsigned matches = 0;
    AirPodsDevice candidate = {0};
    for (UInt32 index = 0; index < count; index++) {
        AirPodsDevice current = {0};
        if (!make_airpods_device(devices[index], &current)) continue;
        matches++;
        if (matches == 1) candidate = current;
        else release_airpods_device(&current);
    }
    free(devices);
    if (matches == 1) {
        *selected = candidate;
        return 0;
    }
    if (matches > 0) release_airpods_device(&candidate);
    fprintf(stderr,
            matches == 0
                ? "No connected AirPods-like output device was found.\n"
                : "Multiple AirPods-like devices found; make the intended one the default output.\n");
    return 2;
}

static int set_listen_mode(UInt32 target) {
    AirPodsDevice device = {0};
    int selectionStatus = select_control_device(&device);
    if (selectionStatus != 0) return selectionStatus;

    UInt32 current = 0;
    if (!read_uint32(device.id, kAirPodsPropertyListenMode, &current)) {
        fprintf(stderr, "Cannot read the current listening mode.\n");
        release_airpods_device(&device);
        return 3;
    }
    if (!property_is_settable(device.id, kAirPodsPropertyListenMode)) {
        fprintf(stderr, "The 'lstm' property is not settable on this device.\n");
        release_airpods_device(&device);
        return 3;
    }

    UInt32 support = 0;
    if (read_uint32(device.id, kAirPodsPropertyListenModeSupport, &support)) {
        UInt32 requiredBit = 1u << (target - kAirPodsListenModeNoiseCancellation);
        if ((support & requiredBit) == 0) {
            fprintf(stderr,
                    "Requested mode %s is not present in support mask 0x%x.\n",
                    listen_mode_name(target), support);
            release_airpods_device(&device);
            return 4;
        }
    }

    printf("device: ");
    print_cfstring(device.name);
    printf("\nlistening-mode: %s (%u) -> %s (%u)\n",
           listen_mode_name(current), current,
           listen_mode_name(target), target);

    AudioObjectPropertyAddress address = address_for(kAirPodsPropertyListenMode);
    OSStatus status = AudioObjectSetPropertyData(
        device.id, &address, 0, NULL, sizeof(target), &target
    );
    if (status != noErr) {
        print_status_error("AudioObjectSetPropertyData('lstm')", status);
        release_airpods_device(&device);
        return 5;
    }

    UInt32 confirmed = 0;
    if (!read_uint32(device.id, kAirPodsPropertyListenMode, &confirmed)
        || confirmed != target) {
        fprintf(stderr, "Setter returned success but read-back did not match.\n");
        release_airpods_device(&device);
        return 6;
    }
    printf("confirmed: %s (%u)\n", listen_mode_name(confirmed), confirmed);
    release_airpods_device(&device);
    return 0;
}

static bool parse_process_id(const char *text, int32_t *result) {
    errno = 0;
    char *end = NULL;
    long value = strtol(text, &end, 10);
    if (errno != 0 || !end || *end != '\0' || value <= 0 || value > INT32_MAX) {
        return false;
    }
    *result = (int32_t)value;
    return true;
}

static const char *spatial_mode_name(bool enabled, bool headTracking) {
    if (!enabled) return "off";
    return headTracking ? "head-tracked" : "fixed";
}

static int set_spatial_mode(const char *mode,
                            const char *processIDText,
                            const char *contentType) {
    bool enabled = false;
    bool headTracking = false;
    if (strcmp(mode, "off") == 0) {
        enabled = false;
    } else if (strcmp(mode, "fixed") == 0) {
        enabled = true;
    } else if (strcmp(mode, "head-tracked") == 0) {
        enabled = true;
        headTracking = true;
    } else {
        fprintf(stderr, "Unknown spatial mode: %s\n", mode);
        return 64;
    }

    AudioObjectPropertySelector selector = 0;
    const char *selectorName = NULL;
    if (strcmp(contentType, "stereo") == 0) {
        selector = kAirPodsPropertySpatializeStereoControlCenterState;
        selectorName = "spss";
    } else if (strcmp(contentType, "multichannel") == 0) {
        selector = kAirPodsPropertySpatialControlCenterState;
        selectorName = "spcs";
    } else {
        fprintf(stderr,
                "Unknown content type: %s (expected stereo or multichannel)\n",
                contentType);
        return 64;
    }

    int32_t processID = 0;
    if (!parse_process_id(processIDText, &processID)) {
        fprintf(stderr, "Invalid process ID: %s\n", processIDText);
        return 64;
    }

    AirPodsDevice device = {0};
    int selectionStatus = select_control_device(&device);
    if (selectionStatus != 0) return selectionStatus;
    if (!property_is_settable(device.id, selector)) {
        fprintf(stderr, "The '%s' property is not settable on this device.\n",
                selectorName);
        release_airpods_device(&device);
        return 3;
    }

    AirPodsSpatialRequest request = {
        .processID = processID,
        .headTracking = headTracking ? 1 : 0,
        .enabled = enabled ? 1 : 0,
        .reserved = {0, 0},
    };
    printf("device: ");
    print_cfstring(device.name);
    printf("\nspatial: %s, pid=%d, content=%s, selector='%s'\n",
           spatial_mode_name(enabled, headTracking), processID, contentType,
           selectorName);

    AudioObjectPropertyAddress address = address_for(selector);
    OSStatus status = AudioObjectSetPropertyData(
        device.id, &address, 0, NULL, sizeof(request), &request
    );
    if (status != noErr) {
        char operation[96];
        snprintf(operation, sizeof(operation),
                 "AudioObjectSetPropertyData('%s')", selectorName);
        print_status_error(operation, status);
        release_airpods_device(&device);
        return 5;
    }

    UInt32 confirmedEnabled = UINT32_MAX;
    UInt32 confirmedHeadTracking = UINT32_MAX;
    bool readEnabled = false;
    bool readHeadTracking = false;
    bool matches = false;
    for (unsigned attempt = 0; attempt < 40; attempt++) {
        readEnabled = read_uint32(device.id, selector, &confirmedEnabled);
        readHeadTracking = read_uint32(
            device.id, kAirPodsPropertyHeadTrackingStatus, &confirmedHeadTracking
        );
        matches = readEnabled && ((confirmedEnabled != 0) == enabled);
        if (matches && enabled && readHeadTracking) {
            matches = ((confirmedHeadTracking != 0) == headTracking);
        }
        if (matches) break;
        struct timespec delay = {.tv_sec = 0, .tv_nsec = 50 * 1000 * 1000};
        nanosleep(&delay, NULL);
    }
    printf("confirmed: spatial=%s",
           readEnabled ? (confirmedEnabled ? "on" : "off") : "unavailable");
    if (readHeadTracking) {
        printf(", head-tracking=%s", confirmedHeadTracking ? "on" : "off");
    }
    printf("\n");

    release_airpods_device(&device);
    if (!matches) {
        fprintf(stderr, "Setter returned success but read-back did not match.\n");
        return 6;
    }
    return 0;
}

static void usage(const char *program) {
    fprintf(stderr,
            "usage: %s status|anc|transparency|adaptive\n"
            "       %s spatial off|fixed|head-tracked PID [stereo|multichannel]\n"
            "\n"
            "Verified commands:\n"
            "  status         Read AirPods HAL state without changing it\n"
            "  anc            Set Noise Cancellation (lstm=2)\n"
            "  transparency   Set Transparency (lstm=3)\n"
            "  adaptive       Set Adaptive Audio (lstm=4)\n"
            "  spatial ...    Set per-process spatial mode; content defaults to stereo\n",
            program, program);
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "spatial") == 0) {
        if (argc != 4 && argc != 5) {
            usage(argv[0]);
            return 64;
        }
        return set_spatial_mode(argv[2], argv[3], argc == 5 ? argv[4] : "stereo");
    }
    if (argc != 2) {
        usage(argv[0]);
        return 64;
    }
    if (strcmp(argv[1], "status") == 0) return status_command();
    if (strcmp(argv[1], "anc") == 0) {
        return set_listen_mode(kAirPodsListenModeNoiseCancellation);
    }
    if (strcmp(argv[1], "transparency") == 0) {
        return set_listen_mode(kAirPodsListenModeTransparency);
    }
    if (strcmp(argv[1], "adaptive") == 0) {
        return set_listen_mode(kAirPodsListenModeAdaptive);
    }
    usage(argv[0]);
    return 64;
}
