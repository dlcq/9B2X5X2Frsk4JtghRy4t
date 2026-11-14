// OEP - C wrappers around the portable core library, plus crash-safe logging.
//
// The in-process ring buffer dies with the process, which makes an engine crash
// impossible to diagnose on the device.  Every entry is therefore mirrored to
// Documents/OEP/oep.log (visible in the Files app), and the host installs
// fatal-signal / uncaught-exception breadcrumbs that append to the same file.
#include "OEPHost.h"

#import <Foundation/Foundation.h>

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>

#include <fcntl.h>
#include <unistd.h>

#include "oep/log.hpp"
#include "oep/scan.hpp"

namespace {

std::mutex g_fileMutex;
std::string g_logFilePath;
int g_crashFd = -1;

char *dupCString(const std::string &text) {
    char *out = static_cast<char *>(std::malloc(text.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, text.c_str(), text.size() + 1);
    return out;
}

oep::LogLevel toLevel(int level) {
    switch (level) {
        case 0: return oep::LogLevel::Debug;
        case 2: return oep::LogLevel::Warning;
        case 3: return oep::LogLevel::Error;
        default: return oep::LogLevel::Info;
    }
}

std::string documentsDirectory() {
    @autoreleasepool {
        NSArray<NSString *> *paths =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documents = paths.firstObject;
        return documents ? std::string([documents UTF8String]) : std::string();
    }
}

// Caller must hold g_fileMutex.
void ensureLogPathLocked() {
    if (!g_logFilePath.empty()) return;
    const std::string documents = documentsDirectory();
    if (documents.empty()) return;
    const std::string directory = documents + "/OEP";
    @autoreleasepool {
        [[NSFileManager defaultManager]
            createDirectoryAtPath:[NSString stringWithUTF8String:directory.c_str()]
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
        NSString *path = [NSString stringWithUTF8String:(directory + "/oep.log").c_str()];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                                   error:nil];
        if (attributes) {
            const auto size = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
            if (size > 1024 * 1024) {  // keep the file easy to share
                NSString *backup = [path stringByAppendingString:@".1"];
                [[NSFileManager defaultManager] removeItemAtPath:backup error:nil];
                [[NSFileManager defaultManager] moveItemAtPath:path toPath:backup error:nil];
            }
        }
    }
    g_logFilePath = directory + "/oep.log";
}

void appendToLogFile(const std::string &line) {
    std::lock_guard<std::mutex> lock(g_fileMutex);
    ensureLogPathLocked();
    if (g_logFilePath.empty()) return;
    FILE *file = std::fopen(g_logFilePath.c_str(), "ab");
    if (!file) return;
    std::fwrite(line.data(), 1, line.size(), file);
    std::fputc('\n', file);
    std::fclose(file);
}

// Async-signal-safe breadcrumb: only write(2) is used.
void crashBreadcrumb(const char *text) {
    if (g_crashFd < 0 || !text) return;
    std::size_t length = 0;
    while (text[length]) ++length;
    ssize_t ignored = ::write(g_crashFd, text, length);
    (void)ignored;
}

void fatalSignalHandler(int signalNumber) {
    switch (signalNumber) {
        case SIGABRT: crashBreadcrumb("\n[FATAL] SIGABRT\n"); break;
        case SIGSEGV: crashBreadcrumb("\n[FATAL] SIGSEGV\n"); break;
        case SIGBUS: crashBreadcrumb("\n[FATAL] SIGBUS\n"); break;
        case SIGILL: crashBreadcrumb("\n[FATAL] SIGILL\n"); break;
        case SIGFPE: crashBreadcrumb("\n[FATAL] SIGFPE\n"); break;
        case SIGTRAP: crashBreadcrumb("\n[FATAL] SIGTRAP\n"); break;
        default: crashBreadcrumb("\n[FATAL] signal\n"); break;
    }
    ::signal(signalNumber, SIG_DFL);
    ::raise(signalNumber);
}

void uncaughtExceptionHandler(NSException *exception) {
    @autoreleasepool {
        std::string text = "[FATAL] uncaught NSException: ";
        text += exception.name ? [exception.name UTF8String] : "?";
        text += ": ";
        text += exception.reason ? [exception.reason UTF8String] : "?";
        appendToLogFile(text);
        NSLog(@"OEP %s", text.c_str());
    }
}

void installSignalHandlersLocked() {
    for (int sig : {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP}) {
        struct sigaction action;
        std::memset(&action, 0, sizeof(action));
        action.sa_handler = fatalSignalHandler;
        sigemptyset(&action.sa_mask);
        action.sa_flags = SA_RESETHAND;
        ::sigaction(sig, &action, nullptr);
    }
}

}  // namespace

// ---------------------------------------------------------------- diagnostics

extern "C" void OEPHostInstallDiagnostics(void) {
    static std::once_flag once;
    std::call_once(once, [] {
        {
            std::lock_guard<std::mutex> lock(g_fileMutex);
            ensureLogPathLocked();
            if (!g_logFilePath.empty()) {
                g_crashFd = ::open(g_logFilePath.c_str(), O_WRONLY | O_APPEND | O_CREAT, 0644);
            }
            installSignalHandlersLocked();
        }
        NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
        // Mirror every entry that reaches the logger into the file.
        oep::Logger::shared().addSink([](const oep::LogEntry &entry) {
            appendToLogFile(entry.toLine());
        });
        oep::Logger::shared().info("host", "diagnostics installed (log file: " + g_logFilePath + ")");
    });
}

extern "C" const char *OEPHostLogFilePath(void) {
    std::lock_guard<std::mutex> lock(g_fileMutex);
    ensureLogPathLocked();
    return g_logFilePath.empty() ? nullptr : g_logFilePath.c_str();
}

// ---------------------------------------------------------------- core bridge

extern "C" const char *OEPHostCoreVersion(void) { return "OEP core 0.1.0"; }

extern "C" char *OEPHostScanGameJSON(const char *utf8Folder) {
    if (!utf8Folder || !*utf8Folder) return nullptr;
    try {
        oep::ScanOptions options;
        const oep::GameScan scan = oep::scanGame(utf8Folder, options);
        const std::string json = oep::scanToJson(scan, true);
        oep::Logger::shared().info(
            "scan", std::string("scanned folder, support=") +
                        oep::supportLevelLabel(scan.level) + ", archives=" +
                        std::to_string(scan.archives.size()));
        return dupCString(json);
    } catch (const std::exception &ex) {
        oep::Logger::shared().error("scan", std::string("scan failed: ") + ex.what());
        return nullptr;
    } catch (...) {
        oep::Logger::shared().error("scan", "scan failed with an unknown error");
        return nullptr;
    }
}

extern "C" char *OEPHostLogExport(void) {
    return dupCString(oep::Logger::shared().exportText());
}

extern "C" void OEPHostLogClear(void) { oep::Logger::shared().clear(); }

extern "C" void OEPHostLog(int level, const char *category, const char *message) {
    OEPHostInstallDiagnostics();
    oep::Logger::shared().log(toLevel(level), category ? category : "app",
                              message ? message : "");
}

extern "C" void OEPHostLogSetMinimumLevel(int level) {
    oep::Logger::shared().setMinimumLevel(toLevel(level));
}

extern "C" int OEPHostLogCount(void) {
    return static_cast<int>(oep::Logger::shared().size());
}

extern "C" void OEPHostFree(char *pointer) { std::free(pointer); }
