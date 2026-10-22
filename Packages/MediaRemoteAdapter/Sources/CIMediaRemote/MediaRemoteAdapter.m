// Copyright (c) 2025 Jonas van den Berg and contributors.
// Modifications copyright (c) 2026 MacMix contributors.
// Licensed under the BSD 3-Clause License; see LICENSE.

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

#import "MediaRemote.h"
#import "MediaRemoteAdapter.h"
#import "MediaRemoteAdapterKeys.h"

typedef void (^ObjectCompletion)(id value);
typedef void (^PlaybackStateCompletion)(unsigned int state);
typedef void (^IsPlayingCompletion)(BOOL isPlaying);

static dispatch_queue_t gQueue;
static CFRunLoopRef gRunLoop;
static dispatch_source_t gParentMonitor;
static dispatch_source_t gRefreshTimer;
static dispatch_source_t gStdinSource;
static NSMutableData *gStdinBuffer;
static NSMutableDictionary<NSString *, id> *gKnownPaths;
static NSMutableDictionary<NSString *, NSNumber *> *gKnownPIDs;
static NSMutableDictionary<NSString *, NSString *> *gKnownBundleIdentifiers;
static NSMutableDictionary<NSString *, NSNumber *> *gKnownPathPriorities;
static NSMutableDictionary<NSString *, NSNumber *> *gLatestUpdateSequences;
static NSMutableDictionary<NSString *, NSNumber *> *gMissingInfoCounts;
static NSMutableDictionary<NSString *, NSString *> *gArtworkSignatures;
static NSMutableDictionary<NSString *, NSString *> *gDesiredArtworkSignatures;
static NSMutableSet<NSString *> *gArtworkRequestsInFlight;
static pid_t gParentPID;

static id sendObject0(id receiver, NSString *selectorName) {
    if (receiver == nil) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![receiver respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static id sendObject1(id receiver, NSString *selectorName, id argument) {
    if (receiver == nil) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![receiver respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(receiver, selector, argument);
}

static id sendObject3(id receiver, NSString *selectorName, id first, id second,
                      id third) {
    if (receiver == nil) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![receiver respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)(receiver, selector,
                                                       first, second, third);
}

static int sendInt0(id receiver, NSString *selectorName) {
    if (receiver == nil) return 0;
    SEL selector = NSSelectorFromString(selectorName);
    if (![receiver respondsToSelector:selector]) return 0;
    return ((int (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static void requestObject(id receiver, NSString *selectorName,
                          ObjectCompletion completion) {
    SEL selector = NSSelectorFromString(selectorName);
    if (receiver == nil || ![receiver respondsToSelector:selector]) {
        completion(nil);
        return;
    }
    ((void (*)(id, SEL, dispatch_queue_t, ObjectCompletion))objc_msgSend)(
        receiver, selector, gQueue, completion);
}

static void requestPlaybackState(id receiver,
                                 PlaybackStateCompletion completion) {
    SEL selector =
        NSSelectorFromString(@"requestPlaybackStateOnQueue:completion:");
    if (receiver == nil || ![receiver respondsToSelector:selector]) {
        completion(0);
        return;
    }
    ((void (*)(id, SEL, dispatch_queue_t,
               PlaybackStateCompletion))objc_msgSend)(receiver, selector,
                                                       gQueue, completion);
}

static void requestIsPlaying(id receiver, IsPlayingCompletion completion) {
    SEL selector = NSSelectorFromString(@"requestIsPlayingOnQueue:completion:");
    if (receiver != nil && [receiver respondsToSelector:selector]) {
        ((void (*)(id, SEL, dispatch_queue_t,
                   IsPlayingCompletion))objc_msgSend)(receiver, selector,
                                                       gQueue, completion);
        return;
    }
    requestPlaybackState(receiver, ^(unsigned int playbackState) {
      completion(playbackState == 1);
    });
}

static void printOut(NSString *message) {
    fprintf(stdout, "%s\n", message.UTF8String);
    fflush(stdout);
}

static void printErr(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    fflush(stderr);
}

static void printDictionary(NSDictionary *payload) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        @"type" : @"data",
        @"diff" : @NO,
        @"payload" : payload,
    } options:0 error:&error];
    if (data == nil) {
        printErr([NSString stringWithFormat:@"JSON serialization failed: %@",
                                            error.localizedDescription]);
        return;
    }
    printOut([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

static NSString *stringValue(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static id pathClient(id path) { return sendObject0(path, @"client"); }
static id pathPlayer(id path) { return sendObject0(path, @"player"); }

static NSData *pathData(id path) {
    id data = sendObject0(path, @"data");
    return [data isKindOfClass:NSData.class] ? data : nil;
}

static NSString *bundleIdentifierForPath(id path) {
    id client = pathClient(path);
    NSString *parent =
        stringValue(sendObject0(client, @"parentApplicationBundleIdentifier"));
    NSString *bundle = stringValue(sendObject0(client, @"bundleIdentifier"));
    return parent.length > 0 ? parent : bundle;
}

static NSInteger priorityForPath(id path) {
    id client = pathClient(path);
    NSString *bundle = stringValue(sendObject0(client, @"bundleIdentifier"));
    NSString *parent =
        stringValue(sendObject0(client, @"parentApplicationBundleIdentifier"));
    if ([bundle isEqualToString:@"com.apple.WebKit.GPU"]) return 30;
    if (parent.length > 0) return 20;
    return 10;
}

static NSString *sessionIdentifierForPath(id path) {
    id player = pathPlayer(path);
    NSString *bundle = bundleIdentifierForPath(path) ?: @"unknown";
    NSString *playerIdentifier =
        stringValue(sendObject0(player, @"identifier")) ?: @"default";
    return [NSString stringWithFormat:@"%@:%@", bundle, playerIdentifier];
}

static id currentPlayerPath(void) {
    Class requestClass = NSClassFromString(@"MRNowPlayingRequest");
    return sendObject0(requestClass, @"localNowPlayingPlayerPath");
}

static BOOL pathsRepresentSameSession(id first, id second) {
    NSData *firstData = pathData(first);
    NSData *secondData = pathData(second);
    if (firstData.length == 0 || secondData.length == 0) return NO;
    if ([firstData isEqualToData:secondData]) return YES;

    NSString *firstIdentifier = sessionIdentifierForPath(first);
    NSString *secondIdentifier = sessionIdentifierForPath(second);
    return ![firstIdentifier hasPrefix:@"unknown:"] &&
        [firstIdentifier isEqualToString:secondIdentifier];
}

static BOOL pathIsCurrent(id path) {
    return pathsRepresentSameSession(path, currentPlayerPath());
}

static id requestForPath(id path) {
    Class requestClass = NSClassFromString(@"MRNowPlayingRequest");
    id allocated = sendObject0(requestClass, @"alloc");
    return sendObject1(allocated, @"initWithPlayerPath:", path);
}

static id playerPathFromDataString(NSString *encoded) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (data.length == 0) return nil;
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    id allocated = sendObject0(pathClass, @"alloc");
    return sendObject1(allocated, @"initWithData:", data);
}

static NSString *stringFromBase64(NSString *encoded) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (data.length == 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSMutableDictionary *convertedInformation(NSDictionary *information) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    void (^copyValue)(NSString *, NSString *) =
        ^(NSString *targetKey, NSString *sourceKey) {
          id value = information[sourceKey];
          if (value != nil) payload[targetKey] = value;
        };

    copyValue(kTitle, (__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle);
    copyValue(kArtist, (__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist);
    copyValue(kAlbum, (__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum);
    copyValue(kArtworkMimeType,
              (__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtworkMIMEType);
    copyValue(kShuffleMode,
              (__bridge NSString *)kMRMediaRemoteNowPlayingInfoShuffleMode);
    copyValue(kRepeatMode,
              (__bridge NSString *)kMRMediaRemoteNowPlayingInfoRepeatMode);
    copyValue(kPlaybackRate,
              (__bridge NSString *)kMRMediaRemoteNowPlayingInfoPlaybackRate);

    NSData *artwork =
        information[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtworkData];
    if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
        payload[kArtworkDataBase64] =
            [artwork base64EncodedStringWithOptions:0];
    }

    NSNumber *duration =
        information[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDuration];
    if ([duration isKindOfClass:NSNumber.class] && isfinite(duration.doubleValue)) {
        payload[kDurationMicros] = @(floor(duration.doubleValue * 1000000));
    }

    NSNumber *elapsed =
        information[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime];
    if ([elapsed isKindOfClass:NSNumber.class] && isfinite(elapsed.doubleValue)) {
        payload[kElapsedTimeMicros] = @(floor(elapsed.doubleValue * 1000000));
    }

    NSDate *timestamp =
        information[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTimestamp];
    if ([timestamp isKindOfClass:NSDate.class]) {
        payload[kTimestampEpochMicros] =
            @(floor(timestamp.timeIntervalSince1970 * 1000000));
    }
    return payload;
}

static NSString *artworkSignature(NSDictionary *information) {
    NSArray<NSString *> *keys = @[
        @"kMRMediaRemoteNowPlayingInfoArtworkIdentifier",
        @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier",
        (__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle,
        (__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist,
        (__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum,
    ];
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    for (NSString *key in keys) {
        id value = information[key];
        if (value != nil) [components addObject:[value description]];
    }
    return [components componentsJoinedByString:@"\x1f"];
}

static void requestAndEmitArtwork(id request, id path, NSString *identifier,
                                  NSString *signature,
                                  NSDictionary *basePayload) {
    if (signature.length == 0 ||
        [gArtworkSignatures[identifier] isEqualToString:signature]) return;

    NSString *requestIdentifier =
        [NSString stringWithFormat:@"%@\x1e%@", identifier, signature];
    if ([gArtworkRequestsInFlight containsObject:requestIdentifier]) return;
    [gArtworkRequestsInFlight addObject:requestIdentifier];

    requestObject(request, @"requestNowPlayingItemArtworkOnQueue:completion:",
                  ^(id artworkValue) {
      [gArtworkRequestsInFlight removeObject:requestIdentifier];
      if (![gDesiredArtworkSignatures[identifier] isEqualToString:signature]) {
          return;
      }
      NSData *imageData = sendObject0(artworkValue, @"imageData");
      if (![imageData isKindOfClass:NSData.class] || imageData.length == 0) {
          return;
      }

      NSMutableDictionary *payload = [NSMutableDictionary dictionary];
      for (NSString *key in @[ kTitle, kArtist, kAlbum ]) {
          if (basePayload[key] != nil) payload[key] = basePayload[key];
      }
      payload[kSessionIdentifier] = identifier;
      payload[kPlayerPathDataBase64] =
          [pathData(path) base64EncodedStringWithOptions:0];
      payload[kArtworkDataBase64] =
          [imageData base64EncodedStringWithOptions:0];
      gArtworkSignatures[identifier] = signature;
      printDictionary(payload);
    });
}

// NSRunningApplication only knows LaunchServices applications. WebKit's GPU
// service for an iPad app is not one, so it would expire a live session on
// every refresh; the kernel answers for any process, including EPERM.
static BOOL processIsRunning(pid_t pid) {
    return kill(pid, 0) == 0 || errno == EPERM;
}

static BOOL rememberPath(id path) {
    NSString *identifier = sessionIdentifierForPath(path);
    if (identifier.length == 0) return NO;

    id existingPath = gKnownPaths[identifier];
    NSData *existingData = pathData(existingPath);
    NSData *candidateData = pathData(path);
    NSInteger candidatePriority = priorityForPath(path);
    NSInteger existingPriority = gKnownPathPriorities[identifier].integerValue;
    NSNumber *existingPID = gKnownPIDs[identifier];
    BOOL existingProcessIsRunning = existingPID.intValue <= 0 ||
        processIsRunning(existingPID.intValue);
    BOOL candidateIsCurrent = pathIsCurrent(path);
    if (existingData.length > 0 &&
        ![existingData isEqualToData:candidateData] &&
        existingProcessIsRunning && !candidateIsCurrent &&
        candidatePriority <= existingPriority) {
        return NO;
    }

    gKnownPaths[identifier] = path;
    gKnownPathPriorities[identifier] = @(candidatePriority);
    id client = pathClient(path);
    int pid = sendInt0(client, @"processIdentifier");
    if (pid > 0) gKnownPIDs[identifier] = @(pid);
    NSString *bundle = bundleIdentifierForPath(path);
    if (bundle.length > 0) gKnownBundleIdentifiers[identifier] = bundle;
    return YES;
}

static void emitRemoval(NSString *identifier) {
    if (identifier.length == 0) return;
    printDictionary(@{kSessionIdentifier : identifier, kRemoved : @YES});
    [gKnownPaths removeObjectForKey:identifier];
    [gKnownPIDs removeObjectForKey:identifier];
    [gKnownBundleIdentifiers removeObjectForKey:identifier];
    [gKnownPathPriorities removeObjectForKey:identifier];
    [gLatestUpdateSequences removeObjectForKey:identifier];
    [gMissingInfoCounts removeObjectForKey:identifier];
    [gArtworkSignatures removeObjectForKey:identifier];
    [gDesiredArtworkSignatures removeObjectForKey:identifier];
}

static void emitRemovalIfPathIsCurrent(id path, NSString *identifier) {
    if (pathsRepresentSameSession(gKnownPaths[identifier], path)) {
        emitRemoval(identifier);
    }
}

static void emitPath(id path) {
    if (path == nil || pathData(path).length == 0) return;
    NSString *identifier = sessionIdentifierForPath(path);
    id request = requestForPath(path);
    requestObject(request, @"requestNowPlayingInfoOnQueue:completion:",
                  ^(id informationValue) {
      NSDictionary *information =
          [informationValue isKindOfClass:NSDictionary.class]
              ? informationValue
              : nil;
      NSString *title =
          stringValue(information[(__bridge NSString *)
                                      kMRMediaRemoteNowPlayingInfoTitle]);
      if (title.length == 0) {
          if ([pathData(gKnownPaths[identifier]) isEqualToData:pathData(path)]) {
              NSUInteger misses =
                  gMissingInfoCounts[identifier].unsignedIntegerValue + 1;
              gMissingInfoCounts[identifier] = @(misses);
              if (misses >= 3) emitRemovalIfPathIsCurrent(path, identifier);
          }
          return;
      }
      if (!rememberPath(path)) return;
      [gMissingInfoCounts removeObjectForKey:identifier];

      NSUInteger updateSequence =
          gLatestUpdateSequences[identifier].unsignedIntegerValue + 1;
      gLatestUpdateSequences[identifier] = @(updateSequence);

      requestIsPlaying(request, ^(BOOL isPlaying) {
        if (gLatestUpdateSequences[identifier].unsignedIntegerValue !=
            updateSequence) return;
        NSMutableDictionary *payload = convertedInformation(information);
        payload[kSessionIdentifier] = identifier;
        payload[kPlayerPathDataBase64] =
            [pathData(path) base64EncodedStringWithOptions:0];
        payload[kIsControllable] = @(pathIsCurrent(path));

        NSNumber *rate = payload[kPlaybackRate];
        payload[kIsPlaying] = @(isPlaying);
        payload[kPlaybackRate] = isPlaying
            ? @([rate isKindOfClass:NSNumber.class] && rate.doubleValue > 0
                    ? rate.doubleValue
                    : 1)
            : @0;

        id client = pathClient(path);
        int pid = sendInt0(client, @"processIdentifier");
        NSString *bundle = bundleIdentifierForPath(path);
        NSString *displayName =
            stringValue(sendObject0(client, @"displayName"));
        if (pid > 0) payload[kPID] = @(pid);
        if (bundle.length > 0) payload[kBundleIdentifier] = bundle;

        NSRunningApplication *application = pid > 0
            ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid]
            : nil;
        NSString *applicationName = application.localizedName ?: displayName;
        if (applicationName.length > 0) {
            payload[kApplicationName] = applicationName;
        }

        NSString *signature = artworkSignature(information);
        gDesiredArtworkSignatures[identifier] = signature;
        if ([gArtworkSignatures[identifier] isEqualToString:signature]) {
            [payload removeObjectForKey:kArtworkDataBase64];
        }
        printDictionary(payload);
        requestAndEmitArtwork(request, path, identifier, signature, payload);
      });
    });
}

static void resolveAndEmitPath(id path) {
    id request = requestForPath(path);
    requestObject(request, @"nowPlayingPlayerPathOnQueue:completion:",
                  ^(id resolvedPath) {
      if (pathData(resolvedPath).length > 0) emitPath(resolvedPath);
    });
}

static void discoverApplication(NSRunningApplication *application) {
    NSString *bundle = application.bundleIdentifier;
    if (bundle.length == 0 || [bundle hasPrefix:@"jazmin.MacMix"]) return;

    Class originClass = NSClassFromString(@"MROrigin");
    Class playerClass = NSClassFromString(@"MRPlayer");
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    id origin = sendObject0(originClass, @"localOrigin");
    id player = sendObject0(playerClass, @"defaultPlayer");
    id allocated = sendObject0(pathClass, @"alloc");
    id candidate = sendObject3(allocated,
        @"initWithOrigin:bundleIdentifier:player:", origin, bundle, player);
    resolveAndEmitPath(candidate);
}

static void discoverRunningApplications(void) {
    for (NSRunningApplication *application in
         NSWorkspace.sharedWorkspace.runningApplications) {
        discoverApplication(application);
    }
}

static void refreshKnownPaths(void) {
    NSArray *identifiers = gKnownPaths.allKeys.copy;
    for (NSString *identifier in identifiers) {
        NSNumber *pid = gKnownPIDs[identifier];
        if (pid.intValue > 0 && !processIsRunning(pid.intValue)) {
            emitRemoval(identifier);
            continue;
        }
        emitPath(gKnownPaths[identifier]);
    }
}

static void refreshCurrentAndKnownPaths(void) {
    id currentPath = currentPlayerPath();
    NSString *identifier = sessionIdentifierForPath(currentPath);
    BOOL currentPathIsKnown =
        pathsRepresentSameSession(gKnownPaths[identifier], currentPath);
    refreshKnownPaths();
    if (!currentPathIsKnown) emitPath(currentPath);
}

static BOOL validateCommandPath(id path) {
    NSData *targetData = pathData(path);
    if (targetData.length == 0) {
        printErr(@"Ignored command without a MediaRemote session path");
        return NO;
    }
    int pid = sendInt0(pathClient(path), @"processIdentifier");
    if (pid > 0 && !processIsRunning(pid)) {
        printErr(@"Ignored command for an expired MediaRemote process");
        return NO;
    }

    if (!pathIsCurrent(path)) {
        printErr(@"Ignored command for a non-current MediaRemote session");
        refreshCurrentAndKnownPaths();
        return NO;
    }
    return YES;
}

static void refreshPathAfterCommand(id path) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                   gQueue, ^{ emitPath(path); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 650 * NSEC_PER_MSEC),
                   gQueue, ^{ emitPath(path); });
}

static void sendCommandToPath(MRCommand command, id path) {
    if (!validateCommandPath(path)) return;
    if (!MRMediaRemoteSendCommand(command, nil)) {
        printErr(@"MediaRemote rejected the command for its current session");
    }
    refreshPathAfterCommand(path);
}

static void setElapsedTimeForPath(double elapsedTime, id path) {
    if (!validateCommandPath(path)) return;
    MRMediaRemoteSetElapsedTime(MAX(0, elapsedTime));
    refreshPathAfterCommand(path);
}

static NSArray<NSString *> *commandParts(NSString *line) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [line componentsSeparatedByCharactersInSet:
                                  NSCharacterSet.whitespaceCharacterSet]) {
        if (part.length > 0) [parts addObject:part];
    }
    return parts;
}

static void executeInlineCommand(NSString *line) {
    NSArray<NSString *> *parts = commandParts(line);
    if (parts.count == 0) return;
    NSString *name = parts[0];
    id path = parts.count > 1 ? playerPathFromDataString(parts[1]) : nil;
    NSString *identifier =
        parts.count > 2 ? stringFromBase64(parts[2]) : nil;
    id latestPath = identifier.length > 0 ? gKnownPaths[identifier] : nil;
    if (pathData(latestPath).length > 0) path = latestPath;

    NSDictionary<NSString *, NSNumber *> *commands = @{
        @"play" : @(kMRPlay),
        @"pause" : @(kMRPause),
        @"toggle_play_pause" : @(kMRTogglePlayPause),
        @"next_track" : @(kMRNextTrack),
        @"previous_track" : @(kMRPreviousTrack),
        @"stop" : @(kMRStop),
        @"skip_fifteen_seconds" : @(kMRSkipFifteenSeconds),
        @"go_back_fifteen_seconds" : @(kMRGoBackFifteenSeconds),
    };
    NSNumber *command = commands[name];
    if (command != nil) {
        sendCommandToPath((MRCommand)command.unsignedIntValue, path);
    } else if ([name isEqualToString:@"set_time"]) {
        if (parts.count > 3) {
            setElapsedTimeForPath([parts[3] doubleValue], path);
        } else if (parts.count > 1) {
            setElapsedTimeForPath([parts[1] doubleValue], currentPlayerPath());
        } else {
            printErr(@"Missing elapsed time for set_time");
        }
    } else if ([name isEqualToString:@"refresh_all"]) {
        refreshKnownPaths();
        discoverRunningApplications();
    } else {
        printErr([NSString stringWithFormat:@"Unknown inline command: %@",
                                            name]);
    }
}

static void setupStdinReader(void) {
    gStdinBuffer = [NSMutableData data];
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    if (flags >= 0) fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    gStdinSource =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0,
                               gQueue);
    if (gStdinSource == nil) return;
    dispatch_source_set_event_handler(gStdinSource, ^{
      char buffer[2048];
      while (true) {
          ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
          if (count > 0) {
              [gStdinBuffer appendBytes:buffer length:(NSUInteger)count];
          } else if (count == 0) {
              exit(0);
          } else if (errno == EINTR) {
              continue;
          } else {
              break;
          }
      }
      while (true) {
          NSRange newline =
              [gStdinBuffer rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]
                                options:0
                                  range:NSMakeRange(0, gStdinBuffer.length)];
          if (newline.location == NSNotFound) break;
          NSData *lineData =
              [gStdinBuffer subdataWithRange:NSMakeRange(0, newline.location)];
          [gStdinBuffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(newline))
                                  withBytes:NULL
                                     length:0];
          NSString *line =
              [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
          if (line != nil) executeInlineCommand(line);
      }
    });
    dispatch_resume(gStdinSource);
}

static void setupProcessMonitoring(void) {
    gParentPID = getppid();
    gParentMonitor =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
    dispatch_source_set_timer(gParentMonitor,
                              dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                              5 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(gParentMonitor, ^{
      if (gParentPID > 0 && kill(gParentPID, 0) != 0) exit(0);
    });
    dispatch_resume(gParentMonitor);
}

static void setupPeriodicRefresh(void) {
    gRefreshTimer =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
    dispatch_source_set_timer(gRefreshTimer,
                              dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gRefreshTimer, ^{
      refreshCurrentAndKnownPaths();
    });
    dispatch_resume(gRefreshTimer);
}

void bootstrap(void) {
    MediaRemoteInitialize();
    gQueue = dispatch_queue_create("MacMix.MediaRemoteAdapter",
                                   DISPATCH_QUEUE_SERIAL);
    gKnownPaths = [NSMutableDictionary dictionary];
    gKnownPIDs = [NSMutableDictionary dictionary];
    gKnownBundleIdentifiers = [NSMutableDictionary dictionary];
    gKnownPathPriorities = [NSMutableDictionary dictionary];
    gLatestUpdateSequences = [NSMutableDictionary dictionary];
    gMissingInfoCounts = [NSMutableDictionary dictionary];
    gArtworkSignatures = [NSMutableDictionary dictionary];
    gDesiredArtworkSignatures = [NSMutableDictionary dictionary];
    gArtworkRequestsInFlight = [NSMutableSet set];
    setupProcessMonitoring();
}

void loop(void) {
    gRunLoop = CFRunLoopGetCurrent();
    setupStdinReader();
    setupPeriodicRefresh();
    MRMediaRemoteRegisterForNowPlayingNotifications(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));

    dispatch_async(gQueue, ^{
      emitPath(currentPlayerPath());
      discoverRunningApplications();
    });

    void (^handler)(__unused NSNotification *) = ^(__unused NSNotification *note) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                     gQueue, ^{
        refreshCurrentAndKnownPaths();
      });
    };
    void (^applicationHandler)(__unused NSNotification *) =
        ^(__unused NSNotification *note) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                     gQueue, ^{
        refreshCurrentAndKnownPaths();
        discoverRunningApplications();
      });
    };
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:(__bridge NSString *)
                                   kMRMediaRemoteNowPlayingInfoDidChangeNotification
                        object:nil queue:nil usingBlock:handler];
    [center addObserverForName:(__bridge NSString *)
                                   kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
                        object:nil queue:nil usingBlock:handler];
    [center addObserverForName:(__bridge NSString *)
                                   kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                        object:nil queue:nil usingBlock:applicationHandler];

    NSNotificationCenter *workspaceCenter =
        NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                                  object:nil queue:nil
                              usingBlock:^(NSNotification *note) {
      NSRunningApplication *application = note.userInfo[NSWorkspaceApplicationKey];
      dispatch_async(gQueue, ^{ discoverApplication(application); });
    }];
    [workspaceCenter addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                                  object:nil queue:nil
                              usingBlock:^(NSNotification *note) {
      NSRunningApplication *application = note.userInfo[NSWorkspaceApplicationKey];
      dispatch_async(gQueue, ^{
        NSArray *identifiers = gKnownPaths.allKeys.copy;
        for (NSString *identifier in identifiers) {
            if (gKnownPIDs[identifier].intValue == application.processIdentifier ||
                [gKnownBundleIdentifiers[identifier]
                    isEqualToString:application.bundleIdentifier]) {
                emitRemoval(identifier);
            }
        }
      });
    }];
    CFRunLoopRun();
}

static void sendCurrent(MRCommand command) {
    const char *encodedPath = getenv("MEDIAREMOTE_PLAYER_PATH");
    id path = encodedPath != NULL
        ? playerPathFromDataString([NSString stringWithUTF8String:encodedPath])
        : nil;
    sendCommandToPath(command,
                      pathData(path).length > 0 ? path : currentPlayerPath());
}

void play(void) { sendCurrent(kMRPlay); }
void pause_command(void) { sendCurrent(kMRPause); }
void toggle_play_pause(void) { sendCurrent(kMRTogglePlayPause); }
void next_track(void) { sendCurrent(kMRNextTrack); }
void previous_track(void) { sendCurrent(kMRPreviousTrack); }
void stop_command(void) { sendCurrent(kMRStop); }
void toggle_shuffle(void) { MRMediaRemoteSendCommand(kMRToggleShuffle, nil); }
void toggle_repeat(void) { MRMediaRemoteSendCommand(kMRToggleRepeat, nil); }
void start_forward_seek(void) { MRMediaRemoteSendCommand(kMRStartForwardSeek, nil); }
void end_forward_seek(void) { MRMediaRemoteSendCommand(kMREndForwardSeek, nil); }
void start_backward_seek(void) { MRMediaRemoteSendCommand(kMRStartBackwardSeek, nil); }
void end_backward_seek(void) { MRMediaRemoteSendCommand(kMREndBackwardSeek, nil); }
void go_back_fifteen_seconds(void) { sendCurrent(kMRGoBackFifteenSeconds); }
void skip_fifteen_seconds(void) { sendCurrent(kMRSkipFifteenSeconds); }
void like_track(void) { MRMediaRemoteSendCommand(kMRLikeTrack, nil); }
void ban_track(void) { MRMediaRemoteSendCommand(kMRBanTrack, nil); }
void add_to_wish_list(void) { MRMediaRemoteSendCommand(kMRAddTrackToWishList, nil); }
void remove_from_wish_list(void) { MRMediaRemoteSendCommand(kMRRemoveTrackFromWishList, nil); }

void set_time_from_env(void) {
    const char *value = getenv("MEDIAREMOTE_SET_TIME");
    if (value == NULL) return;
    const char *encodedPath = getenv("MEDIAREMOTE_PLAYER_PATH");
    id path = encodedPath != NULL
        ? playerPathFromDataString([NSString stringWithUTF8String:encodedPath])
        : nil;
    setElapsedTimeForPath(atof(value),
                          pathData(path).length > 0 ? path : currentPlayerPath());
}

void set_shuffle_mode(void) {
    const char *value = getenv("MEDIAREMOTE_SET_SHUFFLE_MODE");
    if (value != NULL) MRMediaRemoteSetShuffleMode(atoi(value));
}

void set_repeat_mode(void) {
    const char *value = getenv("MEDIAREMOTE_SET_REPEAT_MODE");
    if (value != NULL) MRMediaRemoteSetRepeatMode(atoi(value));
}

void get(void) {
    __block BOOL completed = NO;
    id path = currentPlayerPath();
    if (pathData(path).length == 0) {
        printOut(@"NIL");
        return;
    }
    emitPath(path);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), gQueue,
                   ^{ completed = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.1];
    while (!completed && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}
