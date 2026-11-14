// OEP core - game folder scan and support assessment.
//
// A scan is metadata-only: archive indexes, configuration text, version
// resources, plug-in file names and the engine's own console log.  It never
// decodes game payload.
#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "oep/detect.hpp"
#include "oep/xp3.hpp"

namespace oep {

enum class SupportLevel {
    Supported,    // launches with the bundled engine and its static plug-ins
    Partial,      // launches, but some of the title's plug-ins/features are missing
    Unsupported,  // no KiriKiri entry point / archive readable
    Unknown,      // not enough verified data
};

const char* supportLevelLabel(SupportLevel l);      // "supported" / ...
const char* supportLevelJapanese(SupportLevel l);   // "対応済み" / ...

struct SupportIssue {
    SupportLevel level = SupportLevel::Unknown;
    std::string code;    // stable identifier, localized by the app
    std::string detail;  // human readable English detail
};

struct ArchiveSummary {
    std::string fileName;
    uint64_t fileSize = 0;
    // A file with the .xp3 extension that does not start with the XP3 magic
    // (some releases ship patchers or executables under that name).
    bool xp3Magic = true;
    bool indexOk = false;
    std::string indexError;

    uint64_t entries = 0;
    uint64_t orgBytes = 0;
    uint64_t arcBytes = 0;
    uint64_t compressedEntries = 0;
    uint64_t protectedEntries = 0;
    uint64_t hashedNames = 0;
    uint64_t segments = 0;

    bool hasStartupScript = false;
    bool hasProtectionWarning = false;

    bool probeAttempted = false;
    bool contentReadable = false;
    std::string probeError;

    std::map<std::string, uint64_t> extensionCounts;
};

struct ScanOptions {
    // Probing reads one small entry from every archive to tell a plain archive
    // from one that needs a title-specific extraction filter.  Cheap, and it is
    // what the support level depends on.
    bool probeContent = true;
    uint64_t probeMaxBytes = 4ull * 1024 * 1024;
};

struct GameScan {
    std::string folder;
    std::string displayName;
    EngineIdentity engine;

    bool hasDataXp3 = false;
    bool hasDataFolder = false;
    bool hasStartupScript = false;
    bool hasConfigFile = false;
    bool hasSaveFolder = false;

    std::vector<ArchiveSummary> archives;
    std::vector<std::string> rootFiles;
    std::vector<std::string> startupCandidates;
    PluginInventory plugins;

    uint64_t totalBytes = 0;

    SupportLevel level = SupportLevel::Unknown;
    std::vector<SupportIssue> issues;

    bool engineVersionMatchesBundle() const;
};

GameScan scanGame(const std::string& utf8Folder, const ScanOptions& options = {});

// Serialises a scan (used by the CLI and by the diagnostics screen).
std::string scanToJson(const GameScan& scan, bool pretty = true);

}  // namespace oep
