#include "oep/scan.hpp"

#include <algorithm>
#include <cctype>

#include "fsutil.hpp"
#include "oep/json.hpp"

namespace oep {
namespace {

std::string lowerAscii(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(::tolower(c)); });
    return s;
}

bool endsWithNoCase(const std::string& s, const std::string& suffix) {
    return fsutil::endsWithNoCase(s, suffix);
}

bool isArchiveName(const std::string& name) { return endsWithNoCase(name, ".xp3"); }

std::string extOfStorageName(const std::string& name) {
    const std::size_t slash = name.find_last_of('/');
    const std::string leaf = slash == std::string::npos ? name : name.substr(slash + 1);
    const std::size_t dot = leaf.find_last_of('.');
    if (dot == std::string::npos || dot + 1 >= leaf.size()) return "(none)";
    return lowerAscii(leaf.substr(dot));
}

ArchiveSummary summariseArchive(const std::string& path, const std::string& fileName,
                                const ScanOptions& options) {
    ArchiveSummary s;
    s.fileName = fileName;
    s.fileSize = fsutil::fileSize(path);
    s.hasProtectionWarning = false;
    s.xp3Magic = Xp3Archive::hasXp3Magic(path);
    if (!s.xp3Magic) {
        s.indexOk = false;
        s.indexError = "no XP3 magic (the file is not an XP3 archive)";
        return s;
    }

    Xp3Archive archive;
    Error e = archive.open(path);
    if (!e) {
        s.indexOk = false;
        s.indexError = e.describe();
        return s;
    }
    s.indexOk = true;

    const Xp3Archive::Stats st = archive.stats();
    s.entries = st.totalEntries;
    s.orgBytes = st.totalOrgSize;
    s.arcBytes = st.totalArcSize;
    s.compressedEntries = st.compressedEntries;
    s.protectedEntries = st.protectedEntries;
    s.hashedNames = st.hashedNames;
    s.segments = st.segments;

    for (const auto& entry : archive.entries()) {
        ++s.extensionCounts[extOfStorageName(entry.name)];
        const std::string lower = lowerAscii(entry.name);
        if (lower == "startup.tjs" || lower == "data/startup.tjs" ||
            lower == "system/startup.tjs") {
            s.hasStartupScript = true;
        }
        if (entry.name.find("This is a protected archive") != std::string::npos)
            s.hasProtectionWarning = true;
    }

    if (options.probeContent && !archive.entries().empty()) {
        const Xp3Entry* probe = nullptr;
        for (const auto& entry : archive.entries()) {
            if (entry.arcSize == 0) continue;
            if (entry.arcSize > options.probeMaxBytes) continue;
            if (!entry.segments.empty() && entry.segments.front().compressed()) {
                probe = &entry;
                break;
            }
            if (!probe) probe = &entry;
        }
        if (probe) {
            s.probeAttempted = true;
            std::vector<uint8_t> data;
            Error pe = archive.readEntry(*probe, data);
            s.contentReadable = pe.ok();
            if (!pe.ok()) s.probeError = pe.describe();
        }
    }
    return s;
}

void addIssue(GameScan& scan, SupportLevel level, const std::string& code,
              const std::string& detail) {
    scan.issues.push_back(SupportIssue{level, code, detail});
    if (level == SupportLevel::Unsupported)
        scan.level = SupportLevel::Unsupported;
    else if (level == SupportLevel::Partial && scan.level != SupportLevel::Unsupported)
        scan.level = SupportLevel::Partial;
    else if (level == SupportLevel::Unknown && scan.level == SupportLevel::Supported)
        scan.level = SupportLevel::Unknown;
}

}  // namespace

const char* supportLevelLabel(SupportLevel l) {
    switch (l) {
        case SupportLevel::Supported: return "supported";
        case SupportLevel::Partial: return "partial";
        case SupportLevel::Unsupported: return "unsupported";
        default: return "unknown";
    }
}

const char* supportLevelJapanese(SupportLevel l) {
    switch (l) {
        case SupportLevel::Supported: return "対応済み";
        case SupportLevel::Partial: return "一部対応";
        case SupportLevel::Unsupported: return "未対応";
        default: return "調査中";
    }
}

bool GameScan::engineVersionMatchesBundle() const {
    // krkrz_dev in this repository builds KiriKiri Z 1.2.0.3.
    const std::string& v = engine.version;
    if (v.empty()) return engine.kind == EngineKind::KiriKiriZ;
    if (engine.kind != EngineKind::KiriKiriZ) return false;
    return v.rfind("1.2.", 0) == 0 || v.rfind("1.3.", 0) == 0;
}

GameScan scanGame(const std::string& utf8Folder, const ScanOptions& options) {
    GameScan scan;
    scan.folder = utf8Folder;
    scan.displayName = fsutil::utf8(fsutil::path(utf8Folder).filename());
    if (scan.displayName.empty()) scan.displayName = utf8Folder;

    scan.engine = identifyEngine(utf8Folder);
    scan.plugins = collectPlugins(utf8Folder);
    scan.hasConfigFile = scan.engine.config.found;
    scan.hasSaveFolder = fsutil::isDirectory(fsutil::join(utf8Folder, "savedata")) ||
                         fsutil::isDirectory(fsutil::join(utf8Folder, "save"));
    scan.hasDataFolder = fsutil::exists(fsutil::join(utf8Folder, "data/startup.tjs"));

    for (const auto& name : fsutil::listDirectory(utf8Folder)) {
        const std::string full = fsutil::join(utf8Folder, name);
        if (fsutil::isDirectory(full)) continue;
        scan.rootFiles.push_back(name);
        scan.totalBytes += fsutil::fileSize(full);
        if (!isArchiveName(name)) continue;
        if (lowerAscii(name) == "data.xp3") scan.hasDataXp3 = true;
        ArchiveSummary summary = summariseArchive(full, name, options);
        if (summary.hasStartupScript) {
            scan.hasStartupScript = true;
            scan.startupCandidates.push_back(name + ":startup.tjs");
        }
        scan.archives.push_back(std::move(summary));
    }
    std::sort(scan.archives.begin(), scan.archives.end(),
              [](const ArchiveSummary& a, const ArchiveSummary& b) {
                  return a.fileName < b.fileName;
              });

    if (scan.hasDataFolder) {
        scan.hasStartupScript = true;
        scan.startupCandidates.push_back("data/startup.tjs");
    }

    scan.level = SupportLevel::Supported;

    // -------- entry point
    if (!scan.hasStartupScript) {
        addIssue(scan, SupportLevel::Unsupported, "no_startup_script",
                 "No startup.tjs found in archives or data/ - the engine has nothing to run.");
    }

    // -------- engine identity
    if (scan.engine.kind == EngineKind::Unknown) {
        if (scan.hasStartupScript) {
            // Data-only folders (self-made test data, ripped project folders) have no
            // version resource.  The archive layout still tells us what to run, so this
            // is informational rather than a blocker.
            addIssue(scan, SupportLevel::Supported, "engine_unversioned",
                     "No version evidence (EXE/log/config); running from the archive layout.");
        } else {
            addIssue(scan, SupportLevel::Unknown, "engine_unknown",
                     "Engine could not be identified from version resources, config or archives.");
        }
    } else if (scan.engine.kind == EngineKind::KiriKiriZ && !scan.engineVersionMatchesBundle()) {
        addIssue(scan, SupportLevel::Partial, "engine_version_differs",
                 "Title engine version " + scan.engine.version +
                     " differs from the bundled KiriKiri Z 1.2.0.3.");
    } else if (scan.engine.kind == EngineKind::KiriKiri2) {
        addIssue(scan, SupportLevel::Partial, "engine_kirikiri2",
                 "KiriKiri 2 title: TJS2/KAG are compatible but APIs may differ.");
    }

    // -------- archives
    for (const auto& a : scan.archives) {
        if (!a.xp3Magic) {
            addIssue(scan, SupportLevel::Unknown, "misnamed_xp3",
                     a.fileName + ": has an .xp3 extension but no XP3 header (ignored).");
            continue;
        }
        if (!a.indexOk) {
            const bool required = lowerAscii(a.fileName) == "data.xp3";
            addIssue(scan, required ? SupportLevel::Unsupported : SupportLevel::Partial,
                     required ? "data_archive_unreadable" : "archive_unreadable",
                     a.fileName + ": " + a.indexError);
            continue;
        }
        if (a.probeAttempted && !a.contentReadable) {
            const bool required = lowerAscii(a.fileName) == "data.xp3";
            addIssue(scan, required ? SupportLevel::Unsupported : SupportLevel::Partial,
                     required ? "data_archive_filtered" : "archive_filtered",
                     a.fileName + ": content is not readable without a title filter (" +
                         a.probeError + ")");
        }
        if (a.hashedNames > 0 && (a.entries == a.hashedNames || a.hashedNames * 2 > a.entries)) {
            addIssue(scan, SupportLevel::Partial, "hashed_storage_names",
                     a.fileName + ": " + std::to_string(a.hashedNames) + " of " +
                         std::to_string(a.entries) +
                         " entries use protection-tool hashed names.");
        }
        if (a.protectedEntries > 0) {
            addIssue(scan, SupportLevel::Unknown, "extraction_protected",
                     a.fileName + ": " + std::to_string(a.protectedEntries) +
                         " entries carry the extraction-protection attribute.");
        }
    }

    // -------- plug-ins
    for (const auto& p : scan.plugins.entries) {
        if (p.support == PluginSupport::Missing) {
            addIssue(scan, SupportLevel::Partial, "plugin_missing:" + p.id,
                     p.file + ": " + p.note);
        } else if (p.support == PluginSupport::Partial) {
            addIssue(scan, SupportLevel::Partial, "plugin_partial:" + p.id,
                     p.file + ": " + p.note);
        } else if (p.support == PluginSupport::Unknown) {
            addIssue(scan, SupportLevel::Unknown, "plugin_unknown:" + p.id,
                     p.file + ": " + p.note);
        }
    }

    // -------- layout observations (informational)
    if (scan.archives.empty() && !scan.hasDataFolder) {
        addIssue(scan, SupportLevel::Unsupported, "no_archives",
                 "Folder contains no .xp3 archive and no data/ folder.");
    }
    return scan;
}

std::string scanToJson(const GameScan& scan, bool pretty) {
    JsonWriter w(pretty);
    w.beginObject();
    w.field("folder", scan.folder);
    w.field("displayName", scan.displayName);
    w.field("supportLevel", supportLevelLabel(scan.level));
    w.field("supportLevelJa", supportLevelJapanese(scan.level));
    w.field("totalBytes", scan.totalBytes);
    w.field("hasDataXp3", scan.hasDataXp3);
    w.field("hasDataFolder", scan.hasDataFolder);
    w.field("hasStartupScript", scan.hasStartupScript);
    w.field("hasConfigFile", scan.hasConfigFile);
    w.field("hasSaveFolder", scan.hasSaveFolder);

    w.key("engine").beginObject();
    w.field("kind", engineKindLabel(scan.engine.kind));
    w.field("kindJa", engineKindJapanese(scan.engine.kind));
    w.field("version", scan.engine.version);
    w.field("tjs2Version", scan.engine.tjs2Version);
    w.field("evidence", scan.engine.evidence);
    w.field("versionMatchesBundle", scan.engineVersionMatchesBundle());
    w.key("win32VersionInfo").beginObject();
    w.field("valid", scan.engine.exe.valid);
    w.field("fileDescription", scan.engine.exe.fileDescription);
    w.field("fileVersion", scan.engine.exe.fileVersion);
    w.field("productName", scan.engine.exe.productName);
    w.field("productVersion", scan.engine.exe.productVersion);
    w.field("companyName", scan.engine.exe.companyName);
    w.field("comments", scan.engine.exe.comments);
    w.endObject();
    w.key("consoleLog").beginObject();
    w.field("found", scan.engine.log.found);
    w.field("kirikiriVersion", scan.engine.log.kirikiriVersion);
    w.field("tjs2Version", scan.engine.log.tjs2Version);
    w.field("revision", scan.engine.log.revision);
    w.field("buildStamp", scan.engine.log.buildStamp);
    w.field("platform", scan.engine.log.platform);
    w.fieldArray("mounts", scan.engine.log.mounts);
    w.fieldArray("plugins", scan.engine.log.plugins);
    w.endObject();
    w.key("config").beginObject();
    w.field("found", scan.engine.config.found);
    for (const auto& kv : scan.engine.config.items) w.field(kv.first, kv.second);
    w.endObject();
    w.endObject();  // engine

    w.key("archives").beginArray();
    for (const auto& a : scan.archives) {
        w.beginObject();
        w.field("fileName", a.fileName);
        w.field("fileSize", a.fileSize);
        w.field("xp3Magic", a.xp3Magic);
        w.field("indexOk", a.indexOk);
        if (!a.indexOk) w.field("indexError", a.indexError);
        w.field("entries", a.entries);
        w.field("orgBytes", a.orgBytes);
        w.field("arcBytes", a.arcBytes);
        w.field("compressedEntries", a.compressedEntries);
        w.field("protectedEntries", a.protectedEntries);
        w.field("hashedNames", a.hashedNames);
        w.field("hasStartupScript", a.hasStartupScript);
        w.field("contentProbeAttempted", a.probeAttempted);
        w.field("contentReadable", a.contentReadable);
        if (!a.probeError.empty()) w.field("probeError", a.probeError);
        w.key("extensions").beginObject();
        for (const auto& kv : a.extensionCounts) w.field(kv.first, kv.second);
        w.endObject();
        w.endObject();
    }
    w.endArray();

    w.key("plugins").beginArray();
    for (const auto& p : scan.plugins.entries) {
        w.beginObject();
        w.field("file", p.file);
        w.field("id", p.id);
        w.field("support", pluginSupportLabel(p.support));
        w.field("supportJa", pluginSupportJapanese(p.support));
        w.field("note", p.note);
        w.endObject();
    }
    w.endArray();

    w.key("issues").beginArray();
    for (const auto& i : scan.issues) {
        w.beginObject();
        w.field("level", supportLevelLabel(i.level));
        w.field("code", i.code);
        w.field("detail", i.detail);
        w.endObject();
    }
    w.endArray();

    w.fieldArray("startupCandidates", scan.startupCandidates);
    w.fieldArray("rootFiles", scan.rootFiles);
    w.endObject();
    return w.str();
}

}  // namespace oep
