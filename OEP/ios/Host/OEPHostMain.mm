// OEP - process entry point.
//
// SDL must own UIApplicationMain on iOS so that its UIKit app/scene delegate is
// installed; OEP then runs its launcher from that delegate instead of jumping
// straight into the engine.  SDL_RunApp() calls OEPHostMain() from the delegate's
// postFinishLaunch step, on the main thread, once the application finished
// launching.
#define SDL_MAIN_HANDLED 1
#include <SDL3/SDL_main.h>

#include "OEPHost.h"

namespace {

int OEPHostMain(int argc, char **argv) {
    (void)argc;
    (void)argv;
    // Implemented in Swift: builds the launcher window and returns.  The launcher
    // then lives on the normal UIKit run loop; the engine is started from there.
    return OEPHostRunLauncher();
}

}  // namespace

int main(int argc, char **argv) {
    return SDL_RunApp(argc, argv, OEPHostMain, nullptr);
}
