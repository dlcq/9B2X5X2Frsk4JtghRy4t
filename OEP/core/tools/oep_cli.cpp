// oep-cli - command line driver for the OEP core (Windows / macOS / Linux).
//
// It is the tool used to verify the archive reader, the engine detection and the
// scan results outside of the iOS app, and it produces the JSON reports that the
// app's import screen can consume.
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#endif

#include "oep/json.hpp"
#include "oep/log.hpp"
#include "oep/pack.hpp"
#include "oep/platform.hpp"
#include "oep/scan.hpp"
#include "oep/xp3.hpp"

namespace {

using namespace oep;

std::string oep_path_utf8(const std::filesystem::path& p) {
    const auto s = p.u8string();
    return std::string(s.begin(), s.end());
}

void usage() {
    std::printf(
        "oep-cli %s\n"
        "\n"
        "usage:\n"
        "  oep-cli scan <folder> [--json] [--no-probe]\n"
        "  oep-cli report <rootFolder> [--json]\n"
        "  oep-cli detect <folder>\n"
        "  oep-cli xp3 list <archive.xp3> [--limit N]\n"
        "  oep-cli xp3 verify <archive.xp3>\n"
        "  oep-cli xp3 extract <archive.xp3> <storageName> <outFile>\n"
        "  oep-cli version\n",
        "0.1.0");
}

std::string humanBytes(uint64_t bytes) {
    static const char* units[] = {"B", "KB", "MB", "GB", "TB"};
    double v = static_cast<double>(bytes);
    int u = 0;
    while (v >= 1024.0 && u < 4) {
        v /= 1024.0;
        ++u;
    }
    char buf[64];
    std::snprintf(buf, sizeof(buf), (u == 0 ? "%.0f %s" : "%.2f %s"), v, units[u]);
    return buf;
}

int cmdScan(const std::string& folder, bool json, bool probe) {
    ScanOptions options;
    options.probeContent = probe;
    const GameScan scan = scanGame(folder, options);
    if (json) {
        std::printf("%s\n", scanToJson(scan, true).c_str());
        return scan.level == SupportLevel::Unsupported ? 2 : 0;
    }

    std::printf("== %s ==\n", scan.displayName.c_str());
    std::printf("  folder        : %s\n", scan.folder.c_str());
    std::printf("  engine        : %s %s (TJS2 %s, evidence: %s)\n",
                engineKindLabel(scan.engine.kind), scan.engine.version.c_str(),
                scan.engine.tjs2Version.empty() ? "?" : scan.engine.tjs2Version.c_str(),
                scan.engine.evidence.empty() ? "?" : scan.engine.evidence.c_str());
    if (scan.engine.exe.valid) {
        std::printf("  win32 exe     : %s / %s\n", scan.engine.exe.fileDescription.c_str(),
                    scan.engine.exe.fileVersion.c_str());
    }
    if (scan.engine.log.found) {
        std::printf("  console log   : kirikiri %s, rev %s, %s\n",
                    scan.engine.log.kirikiriVersion.c_str(), scan.engine.log.revision.c_str(),
                    scan.engine.log.platform.c_str());
    }
    std::printf("  entry point   : %s\n", scan.hasStartupScript ? "startup.tjs" : "(none)");
    std::printf("  data.xp3      : %s\n", scan.hasDataXp3 ? "yes" : "no");
    std::printf("  total size    : %s\n", humanBytes(scan.totalBytes).c_str());
    std::printf("  archives      : %zu\n", scan.archives.size());
    for (const auto& a : scan.archives) {
        std::printf("    - %-22s %10s  %6llu entries", a.fileName.c_str(),
                    humanBytes(a.fileSize).c_str(),
                    static_cast<unsigned long long>(a.entries));
        if (a.protectedEntries) std::printf("  protected=%llu",
                                            static_cast<unsigned long long>(a.protectedEntries));
        if (a.hashedNames) std::printf("  hashed=%llu",
                                       static_cast<unsigned long long>(a.hashedNames));
        if (!a.indexOk) std::printf("  INDEX ERROR: %s", a.indexError.c_str());
        if (a.probeAttempted && !a.contentReadable) std::printf("  FILTERED");
        std::printf("\n");
    }
    std::printf("  plugins       : %zu (available %zu / partial %zu / missing %zu / unknown %zu)\n",
                scan.plugins.entries.size(),
                scan.plugins.count(PluginSupport::Available),
                scan.plugins.count(PluginSupport::Partial),
                scan.plugins.count(PluginSupport::Missing),
                scan.plugins.count(PluginSupport::Unknown));
    std::printf("  support       : %s (%s)\n", supportLevelLabel(scan.level),
                supportLevelJapanese(scan.level));
    for (const auto& i : scan.issues) {
        std::printf("    [%s] %s: %s\n", supportLevelLabel(i.level), i.code.c_str(),
                    i.detail.c_str());
    }
    return scan.level == SupportLevel::Unsupported ? 2 : 0;
}

int cmdReport(const std::string& root, bool json) {
    std::vector<std::string> folders;
    std::error_code ec;
    std::filesystem::directory_iterator it{std::filesystem::path(root), ec};
    if (ec) {
        std::fprintf(stderr, "cannot open %s\n", root.c_str());
        return 1;
    }
    for (; it != std::filesystem::directory_iterator(); it.increment(ec)) {
        if (ec) break;
        if (it->is_directory(ec)) folders.push_back(oep_path_utf8(it->path()));
    }
    std::sort(folders.begin(), folders.end());

    if (json) {
        JsonWriter w(true);
        w.beginObject();
        w.field("root", root);
        w.key("games").beginArray();
        int unsupported = 0;
        for (const auto& f : folders) {
            const GameScan scan = scanGame(f);
            if (scan.archives.empty() && scan.rootFiles.empty()) continue;
            w.beginObject();
            w.field("displayName", scan.displayName);
            w.field("folder", scan.folder);
            w.field("engine", engineKindLabel(scan.engine.kind));
            w.field("engineVersion", scan.engine.version);
            w.field("supportLevel", supportLevelLabel(scan.level));
            w.field("supportLevelJa", supportLevelJapanese(scan.level));
            w.field("totalBytes", scan.totalBytes);
            w.field("archiveCount", static_cast<uint64_t>(scan.archives.size()));
            w.field("hasStartupScript", scan.hasStartupScript);
            w.key("issues").beginArray();
            for (const auto& i : scan.issues) {
                w.beginObject();
                w.field("level", supportLevelLabel(i.level));
                w.field("code", i.code);
                w.endObject();
            }
            w.endArray();
            w.endObject();
            if (scan.level == SupportLevel::Unsupported) ++unsupported;
        }
        w.endArray();
        w.endObject();
        std::printf("%s\n", w.str().c_str());
        return 0;
    }

    for (const auto& f : folders) {
        const GameScan scan = scanGame(f);
        if (scan.archives.empty() && scan.rootFiles.empty()) continue;
        std::printf("%-40s %-24s %-10s %s\n", scan.displayName.c_str(),
                    engineKindLabel(scan.engine.kind), scan.engine.version.c_str(),
                    supportLevelJapanese(scan.level));
    }
    return 0;
}

int cmdDetect(const std::string& folder) {
    const EngineIdentity id = identifyEngine(folder);
    std::printf("kind         : %s\n", engineKindLabel(id.kind));
    std::printf("version      : %s\n", id.version.c_str());
    std::printf("tjs2         : %s\n", id.tjs2Version.c_str());
    std::printf("evidence     : %s\n", id.evidence.c_str());
    std::printf("exe valid    : %s\n", id.exe.valid ? "yes" : "no");
    std::printf("exe desc     : %s\n", id.exe.fileDescription.c_str());
    std::printf("exe version  : %s\n", id.exe.fileVersion.c_str());
    std::printf("product      : %s\n", id.exe.productName.c_str());
    std::printf("log found    : %s\n", id.log.found ? "yes" : "no");
    std::printf("log engine   : %s\n", id.log.engineLine.c_str());
    std::printf("config       : %s\n", id.config.found ? "yes" : "no");
    for (const auto& kv : id.config.items)
        std::printf("  %-14s = %s\n", kv.first.c_str(), kv.second.c_str());
    return 0;
}

int cmdXp3List(const std::string& path, int limit) {
    Xp3Archive archive;
    Error e = archive.open(path);
    if (!e) {
        std::fprintf(stderr, "open failed: %s\n", e.describe().c_str());
        return 1;
    }
    const auto st = archive.stats();
    std::printf("%s: %llu entries, %s -> %s, protected=%llu hashed=%llu\n", path.c_str(),
                static_cast<unsigned long long>(st.totalEntries),
                humanBytes(st.totalOrgSize).c_str(), humanBytes(st.totalArcSize).c_str(),
                static_cast<unsigned long long>(st.protectedEntries),
                static_cast<unsigned long long>(st.hashedNames));
    int shown = 0;
    for (const auto& entry : archive.entries()) {
        if (limit >= 0 && shown >= limit) break;
        std::printf("  %c %10llu %10llu  %s\n",
                    entry.segments.empty() || !entry.segments.front().compressed() ? '-' : 'Z',
                    static_cast<unsigned long long>(entry.orgSize),
                    static_cast<unsigned long long>(entry.arcSize), entry.name.c_str());
        ++shown;
    }
    return 0;
}

int cmdXp3Verify(const std::string& path) {
    Xp3Archive archive;
    Error e = archive.open(path);
    if (!e) {
        std::fprintf(stderr, "open failed: %s\n", e.describe().c_str());
        return 1;
    }
    std::size_t examined = 0;
    std::vector<std::string> failures;
    archive.verify(examined, failures);
    std::printf("%s: examined %zu entries, %zu problem(s)\n", path.c_str(), examined,
                failures.size());
    for (const auto& f : failures) std::printf("  ! %s\n", f.c_str());
    return failures.empty() ? 0 : 1;
}

int cmdXp3Pack(const std::string& folder, const std::string& outPath, bool compressIndex) {
    oep::PackOptions options;
    options.compressIndex = compressIndex;
    oep::PackResult result;
    const oep::Error e = oep::packFolderToXp3(folder, outPath, options, result);
    if (!e.ok()) {
        std::fprintf(stderr, "pack failed: %s\n", e.describe().c_str());
        return 1;
    }
    std::printf("packed %llu file(s) -> %s (%llu bytes)\n",
                static_cast<unsigned long long>(result.fileCount), outPath.c_str(),
                static_cast<unsigned long long>(result.archiveBytes));
    return 0;
}

int cmdXp3Extract(const std::string& path, const std::string& name,
                  const std::string& outPath) {
    Xp3Archive archive;
    Error e = archive.open(path);
    if (!e) {
        std::fprintf(stderr, "open failed: %s\n", e.describe().c_str());
        return 1;
    }
    const Xp3Entry* entry = archive.find(name);
    if (!entry) {
        std::fprintf(stderr, "entry not found: %s\n", name.c_str());
        return 1;
    }
    e = archive.extractEntry(*entry, outPath);
    if (!e) {
        std::fprintf(stderr, "extract failed: %s\n", e.describe().c_str());
        return 1;
    }
    std::printf("wrote %s (%llu bytes)\n", outPath.c_str(),
                static_cast<unsigned long long>(entry->orgSize));
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
#if defined(_WIN32)
    SetConsoleOutputCP(CP_UTF8);
#endif
    std::vector<std::string> args = processArguments(argc, argv);
    if (!args.empty()) args.erase(args.begin());  // argv[0]
    if (args.empty()) {
        usage();
        return 1;
    }

    bool json = false;
    bool probe = true;
    bool noCompressIndex = false;
    int limit = 60;
    std::vector<std::string> positional;
    for (std::size_t i = 0; i < args.size(); ++i) {
        if (args[i] == "--json") {
            json = true;
        } else if (args[i] == "--no-compress-index") {
            noCompressIndex = true;
        } else if (args[i] == "--no-probe") {
            probe = false;
        } else if (args[i] == "--limit" && i + 1 < args.size()) {
            limit = std::atoi(args[++i].c_str());
        } else if (args[i] == "-h" || args[i] == "--help") {
            usage();
            return 0;
        } else {
            positional.push_back(args[i]);
        }
    }
    if (positional.empty()) {
        usage();
        return 1;
    }

    const std::string& cmd = positional[0];
    if (cmd == "version") {
        std::printf("oep-cli 0.1.0 (KiriKiri Z 1.2.0.3 target)\n");
        return 0;
    }
    if (cmd == "scan" && positional.size() >= 2) return cmdScan(positional[1], json, probe);
    if (cmd == "report" && positional.size() >= 2) return cmdReport(positional[1], json);
    if (cmd == "detect" && positional.size() >= 2) return cmdDetect(positional[1]);
    if (cmd == "xp3" && positional.size() >= 2) {
        if (positional[1] == "list" && positional.size() >= 3)
            return cmdXp3List(positional[2], limit);
        if (positional[1] == "verify" && positional.size() >= 3)
            return cmdXp3Verify(positional[2]);
        if (positional[1] == "extract" && positional.size() >= 5)
            return cmdXp3Extract(positional[2], positional[3], positional[4]);
        if (positional[1] == "pack" && positional.size() >= 4)
            return cmdXp3Pack(positional[2], positional[3], !noCompressIndex);
    }
    usage();
    return 1;
}
