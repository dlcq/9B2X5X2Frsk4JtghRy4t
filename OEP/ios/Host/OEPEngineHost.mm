// OEP engine host - drives one KiriKiri Z session on top of SDL3/UIKit.
//
// SDL3's own iOS entry point installs a CADisplayLink and then calls exit() when
// the game finishes.  OEP needs the opposite: a launcher first, a controlled
// error path when a title cannot start, and a defined end-of-session that the
// Swift side can observe.  So the host owns the loop and calls the engine's
// SDL_App* callbacks directly.
#include "OEPHost.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_init.h>
// NOTE: <SDL3/SDL_main.h> must not be included here.  On iOS it defines main()
// unless SDL_MAIN_HANDLED is set, and OEPHostMain.mm owns the entry point.

#include <cstdlib>
#include <cstring>
#include <vector>
#include <mutex>
#include <string>

// ---------------------------------------------------------------- engine entry
// Defined by krkrz_dev src/core/sdl3/environ/main.cpp (statically linked).
extern "C" SDL_AppResult SDL_AppInit(void **appstate, int argc, char *argv[]);
extern "C" SDL_AppResult SDL_AppIterate(void *appstate);
extern "C" SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event);
extern "C" void SDL_AppQuit(void *appstate, SDL_AppResult result);

#ifndef OEP_ENGINE_VERSION
#define OEP_ENGINE_VERSION "KiriKiri Z (unknown)"
#endif

namespace {

std::mutex g_mutex;
std::string g_projectPath;          // UTF-8, absolute, trailing '/'
OEPEngineEventCallback g_callback = nullptr;
void *g_appState = nullptr;
int g_running = 0;
int g_sessionUsed = 0;
int g_preferredFPS = 0;
CFTimeInterval g_sessionStart = 0;
std::string g_sessionGameID;
std::string g_emittedTick;          // last whole second value emitted

void emit(int event, const char *detail) {
    OEPEngineEventCallback cb = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        cb = g_callback;
    }
    if (cb) cb(event, detail ? detail : "");
}

// The host writes into the same ring buffer the launcher reads (OEP core logger).
void OEPCoreLog(const std::string& category, const std::string& message);

void pushEngineEvent(SDL_EventType type) {
    SDL_Event event;
    SDL_zero(event);
    event.type = type;
    // Queued; the next frame dispatches it through the engine's SDL_AppEvent.
    SDL_PushEvent(&event);
}

}  // namespace

// Implemented in OEPCoreBridge.mm (oep::Logger).
extern "C" void OEPHostLog(int level, const char *category, const char *message);

namespace {
void OEPCoreLog(const std::string& category, const std::string& message) {
    OEPHostLog(1, category.c_str(), message.c_str());
}
}  // namespace

// Read by the patched krkrz InitPath() on iOS.
extern "C" const char *OEPHostProjectPath(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_projectPath.empty() ? nullptr : g_projectPath.c_str();
}

// ---------------------------------------------------------------- display link
@interface OEPEngineDisplayLink : NSObject
@property(nonatomic, strong) CADisplayLink *link;
- (void)tick:(CADisplayLink *)sender;
- (void)finishWith:(SDL_AppResult)result;
@end

static OEPEngineDisplayLink *g_driver = nil;

@implementation OEPEngineDisplayLink

- (void)tick:(CADisplayLink *)sender {
    void *state = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        state = g_appState;
    }
    if (!state) return;

    SDL_Event event;
    SDL_AppResult rc = SDL_APP_CONTINUE;
    // Mirror SDL_IterateMainCallbacks: pump, dispatch what is queued, iterate.
    SDL_PumpEvents();
    while (SDL_PollEvent(&event)) {
        rc = SDL_AppEvent(state, &event);
        if (rc != SDL_APP_CONTINUE) break;
    }
    if (rc == SDL_APP_CONTINUE) rc = SDL_AppIterate(state);

    if (rc != SDL_APP_CONTINUE) {
        [self finishWith:rc];
        return;
    }

    // Playtime accounting: report whole seconds to the launcher.
    const CFTimeInterval now = CACurrentMediaTime();
    const long long seconds = (long long)(now - g_sessionStart);
    const std::string asText = std::to_string(seconds);
    if (asText != g_emittedTick) {
        g_emittedTick = asText;
        emit(OEPEngineEventTick, asText.c_str());
    }
}

- (void)finishWith:(SDL_AppResult)result {
    if (self.link) {
        [self.link invalidate];
        self.link = nil;
    }
    void *state = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        state = g_appState;
        g_appState = nullptr;
        g_running = 0;
    }
    if (state) {
        // TVPSystemUninit + audio/storage teardown happen here.
        SDL_AppQuit(state, result);
    }
    g_driver = nil;
    emit(OEPEngineEventEnded, result == SDL_APP_SUCCESS ? "success" : "failure");
}

@end

// ---------------------------------------------------------------- lifecycle
@interface OEPLifecycleObserver : NSObject
- (void)install;
- (void)remove;
@end

@implementation OEPLifecycleObserver {
    BOOL _installed;
}

- (void)install {
    if (_installed) return;
    _installed = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(willResignActive:)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(didBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(willTerminate:)
                   name:UIApplicationWillTerminateNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(didReceiveMemoryWarning:)
                   name:UIApplicationDidReceiveMemoryWarningNotification
                 object:nil];
}

- (void)remove {
    if (!_installed) return;
    _installed = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)pauseLink {
    if (g_driver && g_driver.link && !g_driver.link.paused) {
        g_driver.link.paused = YES;
    }
}

- (void)resumeLink {
    if (g_driver && g_driver.link && g_driver.link.paused) {
        g_driver.link.paused = NO;
    }
}

- (void)willResignActive:(NSNotification *)note {
    [self pauseLink];
    pushEngineEvent(SDL_EVENT_WILL_ENTER_BACKGROUND);
    emit(OEPEngineEventPaused, "background");
}

- (void)didBecomeActive:(NSNotification *)note {
    pushEngineEvent(SDL_EVENT_DID_ENTER_FOREGROUND);
    [self resumeLink];
    emit(OEPEngineEventResumed, "foreground");
}

- (void)willTerminate:(NSNotification *)note {
    pushEngineEvent(SDL_EVENT_TERMINATING);
}

- (void)didReceiveMemoryWarning:(NSNotification *)note {
    pushEngineEvent(SDL_EVENT_LOW_MEMORY);
}

@end

static OEPLifecycleObserver *g_lifecycle = nil;

// ---------------------------------------------------------------- C API
extern "C" void OEPHostSetEngineCallback(OEPEngineEventCallback callback) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_callback = callback;
}

extern "C" void OEPHostEngineSetPreferredFPS(int fps) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_preferredFPS = fps;
}

extern "C" int OEPHostEngineIsRunning(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_running;
}

extern "C" int OEPHostEngineSessionUsed(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_sessionUsed;
}

extern "C" const char *OEPHostEngineBuildInfo(void) { return OEP_ENGINE_VERSION; }

extern "C" void OEPHostSetSessionGameID(const char *gameID) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_sessionGameID = gameID ? gameID : "";
}

extern "C" int OEPHostEngineStart(const char *utf8ProjectPath) {
    NSString *path = nil;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_running) return -1;
        // krkrz's TVPSystemUninit is a one-shot teardown; a second session in the
        // same process would run on half-initialised globals.
        if (g_sessionUsed) return -2;
        if (!utf8ProjectPath || !*utf8ProjectPath) return -3;

        std::string project(utf8ProjectPath);
        if (project.back() != '/') project.push_back('/');
        g_projectPath = project;
        g_sessionUsed = 1;
        g_sessionStart = CACurrentMediaTime();
        g_emittedTick.clear();
        path = [NSString stringWithUTF8String:utf8ProjectPath];
    }

    // The engine reads the folder through POSIX APIs; make sure it is reachable.
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] ||
        !isDirectory) {
        emit(OEPEngineEventFailed, "project folder not found");
        return -4;
    }

    emit(OEPEngineEventStarting, utf8ProjectPath);

    // On iOS krkrz maps user:// to SDL_OpenUserStorage(orgname, appname).  Giving
    // every game its own appname keeps save data and logs isolated per title
    // instead of sharing one folder.
    std::string orgName = "OEP";
    std::string appName;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        appName = g_sessionGameID;
    }
    if (appName.empty()) {
        std::string path(utf8ProjectPath);
        while (!path.empty() && path.back() == '/') path.pop_back();
        const std::size_t slash = path.find_last_of('/');
        const std::string leaf = slash == std::string::npos ? path : path.substr(slash + 1);
        for (char c : leaf) {
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
                c == '-' || c == '_')
                appName.push_back(c);
        }
    }
    if (appName.empty()) appName = "game";

    std::vector<std::string> argStore = {"krkrz.exe", "-orgname=" + orgName,
                                         "-appname=" + appName};
    std::vector<char*> argv;
    argv.reserve(argStore.size() + 1);
    for (auto& a : argStore) argv.push_back(a.data());
    argv.push_back(nullptr);
    OEPCoreLog("engine", "user:// = orgname=" + orgName + " appname=" + appName);

    void *state = nullptr;
    const SDL_AppResult rc = SDL_AppInit(&state, static_cast<int>(argStore.size()), argv.data());
    if (rc != SDL_APP_CONTINUE) {
        if (state) SDL_AppQuit(state, rc);
        emit(OEPEngineEventFailed, "engine initialisation failed");
        return -4;
    }

    int fps = 0;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_appState = state;
        g_running = 1;
        fps = g_preferredFPS;
    }

    if (!g_lifecycle) g_lifecycle = [[OEPLifecycleObserver alloc] init];
    [g_lifecycle install];

    g_driver = [[OEPEngineDisplayLink alloc] init];
    g_driver.link = [CADisplayLink displayLinkWithTarget:g_driver
                                                selector:@selector(tick:)];
    if (g_driver.link == nil) {
        emit(OEPEngineEventFailed, "CADisplayLink could not be created");
        return -4;
    }
    if (@available(iOS 15.0, *)) {
        const NSInteger preferred = fps > 0 ? fps : 60;
        g_driver.link.preferredFrameRateRange =
            CAFrameRateRangeMake(preferred > 60 ? 60 : preferred, preferred, preferred);
    }
    [g_driver.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];

    emit(OEPEngineEventRunning, utf8ProjectPath);
    return 0;
}

extern "C" void OEPHostEngineRequestStop(void) {
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (!g_running) return;
    }
    // Ask the engine to shut down the way the game itself would.
    pushEngineEvent(SDL_EVENT_QUIT);
}

