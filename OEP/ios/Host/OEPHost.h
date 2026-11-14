// OEP iOS host API - the C boundary between the KiriKiri engine (C++/SDL3) and
// the SwiftUI launcher.
//
// Layering:
//
//   Swift (launcher: library, import, settings, diagnostics)
//     |  this header (plain C, importable from Swift through the bridging header)
//   Host (Objective-C++): engine session + SDL3/UIKit lifecycle
//     |  krkrz's SDL_AppInit / SDL_AppIterate / SDL_AppEvent / SDL_AppQuit
//   KiriKiri Z (krkrz_dev, statically linked) + OEP core (XP3/scan)
//
#ifndef OEP_HOST_H
#define OEP_HOST_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------- engine events
enum {
    OEPEngineEventStarting = 0,  // engine init about to run (blocking)
    OEPEngineEventRunning = 1,   // engine loop is live; launcher should step aside
    OEPEngineEventEnded = 2,     // the game ended; det: "success" | "failure"
    OEPEngineEventFailed = 3,    // engine init failed; det: reason
    OEPEngineEventTick = 4,      // det: whole seconds of the running session
    OEPEngineEventPaused = 5,    // app went to the background
    OEPEngineEventResumed = 6,   // app came back to the foreground
};

typedef void (*OEPEngineEventCallback)(int event, const char *detail);

void OEPHostSetEngineCallback(OEPEngineEventCallback callback);

// Frame pacing for the game session (30 / 60 / 120). Applied to the
// CADisplayLink that drives the engine. 0 = system default.
void OEPHostEngineSetPreferredFPS(int fps);

// Starts one engine session on the given UTF-8 absolute path (the imported game
// folder). The engine loop is driven by the host's display link, so this call
// returns right after initialisation.
//   returns 0 on success
//          -1 when a session is already running
//          -2 when the engine already ran in this process (needs an app restart;
//             krkrz's system initialisation is one-shot by design)
//          -3 invalid argument
//          -4 engine initialisation failed (see OEPEngineEventFailed)
int OEPHostEngineStart(const char *utf8ProjectPath);

void OEPHostEngineRequestStop(void);
int OEPHostEngineIsRunning(void);
int OEPHostEngineSessionUsed(void);
const char *OEPHostEngineBuildInfo(void);

// ---------------------------------------------------------------- OEP core
const char *OEPHostCoreVersion(void);

// Scans a folder (metadata only) and returns malloc'ed UTF-8 JSON.
// Release with OEPHostFree().
char *OEPHostScanGameJSON(const char *utf8Folder);

// Log access (shared ring buffer from oep::Logger).
char *OEPHostLogExport(void);
void OEPHostLogClear(void);
void OEPHostLog(int level, const char *category, const char *message);
void OEPHostLogSetMinimumLevel(int level);
int OEPHostLogCount(void);

// Library bookkeeping used by the playtime display.
void OEPHostSetSessionGameID(const char *gameID);

// Diagnostics: mirror the in-process log into a file so a crash cannot lose it,
// and install OS-level crash breadcrumbs.  Safe to call more than once.
void OEPHostInstallDiagnostics(void);

// UTF-8 path of the file log (Documents/OEP/oep.log).  Empty if unavailable.
const char *OEPHostLogFilePath(void);

void OEPHostFree(char *pointer);

// ---------------------------------------------------------------- Swift side
// Implemented in Swift (@_cdecl). Called once, from SDL's UIKit delegate, after
// the application finished launching. Builds the launcher window and returns;
// the launcher then runs on the normal UIKit run loop.
int OEPHostRunLauncher(void);

#ifdef __cplusplus
}
#endif

#endif  // OEP_HOST_H
