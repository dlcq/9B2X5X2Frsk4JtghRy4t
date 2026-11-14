// OEP - C wrappers around the portable core library so Swift can scan a game
// folder and read the log without knowing anything about C++.
#include "OEPHost.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>

#include "oep/log.hpp"
#include "oep/scan.hpp"

namespace {

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

}  // namespace

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
