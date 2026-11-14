// OEP core - engine identification.
//
// Everything here works on file *metadata* only: Win32 version resources, the
// KiriKiri configuration files (.cf/.cfu), the console log the engine writes
// itself (savedata/krkr.console.log) and the plug-in inventory.  No game
// payload (script text, images, audio) is decoded or interpreted.
#pragma once

#include <string>
#include <utility>
#include <vector>

#include "oep/error.hpp"

namespace oep {

// ---------------------------------------------------------------- PE version
struct PeVersionInfo {
    bool valid = false;
    std::string fileDescription;
    std::string fileVersion;
    std::string productName;
    std::string productVersion;
    std::string internalName;
    std::string originalFilename;
    std::string companyName;
    std::string comments;
    std::string legalCopyright;
};

// Reads the RT_VERSION string table of a PE image (works for the Win32 builds
// of the two target titles and for KiriKiri executables in general).
PeVersionInfo readPeVersionInfo(const std::string& utf8Path);

// ------------------------------------------------------------- console log
struct ConsoleLogInfo {
    bool found = false;
    bool parseError = false;
    std::string engineLine;       // "Kiriki Z Executable core /1.2.0.3 ... TJS2/2.4.28"
    std::string kirikiriVersion;  // "1.2.0.3"
    std::string tjs2Version;      // "2.4.28"
    std::string revision;         // "1947"
    std::string buildStamp;       // "2023/07/21 12:07:28"
    std::string platform;         // "Windows 8 6.2.1008 (Win32)"
    std::vector<std::string> mounts;
    std::vector<std::string> plugins;
};

// Finds the newest krkr.console.log under <folder>/savedata and parses it.
ConsoleLogInfo parseConsoleLog(const std::string& utf8Path);

// ------------------------------------------------------------ .cf / .cfu
struct ConfigValues {
    bool found = false;
    std::vector<std::pair<std::string, std::string>> items;

    std::string get(const std::string& key) const {
        for (const auto& kv : items)
            if (kv.first == key) return kv.second;
        return {};
    }
    bool has(const std::string& key) const { return !get(key).empty(); }
};

// KiriKiri configuration files are `key=value` lines; values often use
// "\xNN" escaped byte sequences for non-ASCII paths.
ConfigValues parseKiriKiriConfig(const std::string& utf8Path);

// ------------------------------------------------------------- plug-ins
enum class PluginSupport {
    Available,  // ships with krkrz_dev and builds for iOS (static)
    Partial,    // buildable but only part of the original behaviour
    Missing,    // Windows-only or not part of krkrz_dev
    Unknown,    // no verified data yet
};

const char* pluginSupportLabel(PluginSupport s);       // "available" / ...
const char* pluginSupportJapanese(PluginSupport s);    // "対応" / "一部対応" ...

struct PluginKnowledge {
    const char* id;
    PluginSupport support;
    const char* note;
};

// dll file name (case-insensitive, with or without ".dll") -> knowledge
PluginKnowledge lookupPlugin(const std::string& dllFileName);

struct PluginEntry {
    std::string file;  // "KAGParserEx.dll"
    std::string id;    // "kagparserex"
    PluginSupport support = PluginSupport::Unknown;
    std::string note;
};

struct PluginInventory {
    std::vector<PluginEntry> entries;
    bool folderPresent = false;
    std::size_t count(PluginSupport s) const;
};

// Scans <folder>/plugin (and <folder>/*.tpm) for plug-in binaries.
PluginInventory collectPlugins(const std::string& utf8Folder);

// ------------------------------------------------------------- engine guess
enum class EngineKind {
    Unknown,
    KiriKiriZ,       // krkrz (1.2.x / 1.3.x) - what krkrz_dev builds
    KiriKiriZGeneric,
    KiriKiri2,       // legacy KiriKiri 2 (TJS 2.4.1x)
    KirikiriSDL,     // another SDL port (e.g. krkrsdl3 based titles)
};

const char* engineKindLabel(EngineKind k);
const char* engineKindJapanese(EngineKind k);

struct EngineIdentity {
    EngineKind kind = EngineKind::Unknown;
    std::string version;      // "1.2.0.3"
    std::string tjs2Version;  // "2.4.28"
    std::string evidence;     // which source proved the version
    PeVersionInfo exe;        // Win32 version resource (may be empty)
    ConsoleLogInfo log;
    ConfigValues config;
};

// Identifies the engine of a game folder using, in order of confidence:
// console log -> PE version resource -> config -> archive/plugin layout.
EngineIdentity identifyEngine(const std::string& utf8Folder);

}  // namespace oep
