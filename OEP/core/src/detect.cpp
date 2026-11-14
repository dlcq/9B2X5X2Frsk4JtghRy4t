#include "oep/detect.hpp"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <map>
#include <set>

#include "fsutil.hpp"

namespace oep {
namespace {

namespace fs = fsutil::fs;

std::string trim(std::string s) {
    const char* ws = " \t\r\n";
    const auto b = s.find_first_not_of(ws);
    if (b == std::string::npos) return {};
    const auto e = s.find_last_not_of(ws);
    return s.substr(b, e - b + 1);
}

bool startsWith(const std::string& s, const char* prefix) {
    const std::size_t n = std::strlen(prefix);
    return s.size() >= n && std::memcmp(s.data(), prefix, n) == 0;
}

std::string lowerAscii(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(::tolower(c)); });
    return s;
}

// ---------------------------------------------------------------- PE resource
struct VerBlock {
    uint16_t length = 0;
    uint16_t valueLength = 0;
    uint16_t type = 0;
    std::string key;
    std::size_t valueOffset = 0;
    std::size_t valueBytes = 0;
    std::size_t childOffset = 0;  // == length end when there are no children
};

bool readUtf16Key(const std::vector<uint8_t>& d, std::size_t& off, std::size_t limit,
                  std::string& out) {
    while (off + 1 < limit) {
        const uint32_t u = static_cast<uint32_t>(d[off]) |
                           (static_cast<uint32_t>(d[off + 1]) << 8);
        off += 2;
        if (u == 0) return true;
        if (u < 0x80)
            out.push_back(static_cast<char>(u));
        else
            fsutil::appendUtf8(out, u);
    }
    return false;
}

bool readVerBlock(const std::vector<uint8_t>& d, std::size_t off, std::size_t limit,
                  VerBlock& out) {
    if (off + 6 > limit) return false;
    out.length = static_cast<uint16_t>(d[off] | (d[off + 1] << 8));
    out.valueLength = static_cast<uint16_t>(d[off + 2] | (d[off + 3] << 8));
    out.type = static_cast<uint16_t>(d[off + 4] | (d[off + 5] << 8));
    if (out.length < 6 || off + out.length > limit) return false;

    std::size_t cursor = off + 6;
    out.key.clear();
    if (!readUtf16Key(d, cursor, off + out.length, out.key)) return false;

    std::size_t aligned = (cursor + 3u) & ~std::size_t(3);
    if (aligned > off + out.length) aligned = off + out.length;
    out.valueOffset = aligned;
    const std::size_t valueBytes =
        out.type == 1 ? static_cast<std::size_t>(out.valueLength) * 2 : out.valueLength;
    out.valueBytes = std::min(valueBytes, off + out.length - aligned);
    std::size_t afterValue = aligned + out.valueBytes;
    out.childOffset = (afterValue + 3u) & ~std::size_t(3);
    return true;
}

std::string blockText(const std::vector<uint8_t>& d, const VerBlock& b) {
    std::string out;
    const std::size_t end = b.valueOffset + b.valueBytes;
    for (std::size_t i = b.valueOffset; i + 1 < end; i += 2) {
        const uint32_t u = static_cast<uint32_t>(d[i]) | (static_cast<uint32_t>(d[i + 1]) << 8);
        if (u == 0) break;
        if (u < 0x80)
            out.push_back(static_cast<char>(u));
        else
            fsutil::appendUtf8(out, u);
    }
    return out;
}

}  // namespace

PeVersionInfo readPeVersionInfo(const std::string& utf8Path) {
    PeVersionInfo info;
    std::vector<uint8_t> d;
    if (!fsutil::readWholeFile(utf8Path, d, 64ull * 1024 * 1024)) return info;
    if (d.size() < 64 || d[0] != 'M' || d[1] != 'Z') return info;

    // Locate the version resource by its key; the block header starts 6 bytes
    // before the key (wLength, wValueLength, wType).
    static const uint8_t sig[] = {'V', 0, 'S', 0, '_', 0, 'V', 0, 'E', 0, 'R', 0,
                                  'S', 0, 'I', 0, 'O', 0, 'N', 0, '_', 0, 'I', 0,
                                  'N', 0, 'F', 0, 'O', 0};
    std::size_t found = std::string::npos;
    for (std::size_t i = 6; i + sizeof(sig) <= d.size(); ++i) {
        if (std::memcmp(d.data() + i, sig, sizeof(sig)) == 0) {
            found = i - 6;
            break;
        }
    }
    if (found == std::string::npos) return info;

    VerBlock root;
    if (!readVerBlock(d, found, d.size(), root)) return info;
    if (root.key != "VS_VERSION_INFO") return info;
    info.valid = true;

    std::map<std::string, std::string> strings;
    std::size_t cursor = root.childOffset;
    const std::size_t rootEnd = found + root.length;
    while (cursor + 6 <= rootEnd) {
        VerBlock child;
        if (!readVerBlock(d, cursor, rootEnd, child)) break;
        if (child.length == 0) break;
        if (child.key == "StringFileInfo") {
            std::size_t t = child.childOffset;
            const std::size_t tEnd = cursor + child.length;
            while (t + 6 <= tEnd) {
                VerBlock table;
                if (!readVerBlock(d, t, tEnd, table)) break;
                if (table.length == 0) break;
                std::size_t s = table.childOffset;
                const std::size_t sEnd = t + table.length;
                while (s + 6 <= sEnd) {
                    VerBlock str;
                    if (!readVerBlock(d, s, sEnd, str)) break;
                    if (str.length == 0) break;
                    const std::string v = blockText(d, str);
                    if (!str.key.empty() && strings.find(str.key) == strings.end())
                        strings[str.key] = v;
                    s = (s + str.length + 3u) & ~std::size_t(3);
                }
                t = (t + table.length + 3u) & ~std::size_t(3);
            }
        }
        cursor = (cursor + child.length + 3u) & ~std::size_t(3);
    }

    auto take = [&strings](const char* k) {
        auto it = strings.find(k);
        return it == strings.end() ? std::string() : it->second;
    };
    info.fileDescription = take("FileDescription");
    info.fileVersion = take("FileVersion");
    info.productName = take("ProductName");
    info.productVersion = take("ProductVersion");
    info.internalName = take("InternalName");
    info.originalFilename = take("OriginalFilename");
    info.companyName = take("CompanyName");
    info.comments = take("Comments");
    info.legalCopyright = take("LegalCopyright");
    if (info.fileVersion.empty() && info.productVersion.empty() && strings.empty())
        info.valid = false;
    return info;
}

// ------------------------------------------------------------- console log
namespace {

std::string newestConsoleLog(const std::string& folder) {
    const std::string savedata = fsutil::join(folder, "savedata");
    std::string best;
    uint64_t bestStamp = 0;
    for (const std::string& dir : {folder, savedata}) {
        for (const auto& name : fsutil::listDirectory(dir)) {
            if (!fsutil::endsWithNoCase(name, ".log")) continue;
            if (lowerAscii(name).find("console") == std::string::npos) continue;
            const std::string full = fsutil::join(dir, name);
            std::error_code ec;
            const auto t = fs::last_write_time(fsutil::path(full), ec);
            const uint64_t stamp = ec ? 0 : static_cast<uint64_t>(t.time_since_epoch().count());
            if (best.empty() || stamp > bestStamp) {
                best = full;
                bestStamp = stamp;
            }
        }
    }
    return best;
}

}  // namespace

ConsoleLogInfo parseConsoleLog(const std::string& utf8Path) {
    ConsoleLogInfo info;
    if (utf8Path.empty()) return info;
    std::vector<uint8_t> bytes;
    if (!fsutil::readWholeFile(utf8Path, bytes, 32ull * 1024 * 1024)) return info;
    info.found = true;

    const std::string text = fsutil::decodeUtf16Auto(bytes);
    std::size_t pos = 0;
    while (pos <= text.size()) {
        std::size_t eol = text.find('\n', pos);
        if (eol == std::string::npos) eol = text.size();
        const std::string line = trim(text.substr(pos, eol - pos));
        pos = eol + 1;

        if (line.find("Kiriki Z Executable core /") != std::string::npos) {
            info.engineLine = line;
            const std::size_t slash = line.find("core /");
            if (slash != std::string::npos) {
                const std::size_t from = slash + 6;
                const std::size_t to = line.find(' ', from);
                info.kirikiriVersion = line.substr(from, to == std::string::npos
                                                              ? std::string::npos
                                                              : to - from);
            }
            const std::size_t tjs = line.find("TJS2/");
            if (tjs != std::string::npos) {
                const std::size_t from = tjs + 5;
                const std::size_t to = line.find(' ', from);
                info.tjs2Version =
                    line.substr(from, to == std::string::npos ? std::string::npos : to - from);
            }
        }
        if (startsWith(line, "Kirikiri : ") || line.find(" Kirikiri : ") != std::string::npos)
            info.kirikiriVersion = trim(line.substr(line.find("Kirikiri : ") + 11));
        if (line.find("Engine : Revision ") != std::string::npos) {
            const std::size_t at = line.find("Engine : Revision ") + 18;
            const std::size_t comma = line.find(',', at);
            info.revision = trim(line.substr(at, comma == std::string::npos
                                                     ? std::string::npos
                                                     : comma - at));
            const std::size_t ls = line.find("Last Changed ", comma == std::string::npos
                                                             ? at
                                                             : comma);
            if (ls != std::string::npos) {
                const std::size_t from = ls + 13;
                const std::size_t to = line.find(',', from);
                info.buildStamp = trim(line.substr(
                    from, to == std::string::npos ? std::string::npos : to - from));
            }
        }
        if (line.find("OS : ") != std::string::npos)
            info.platform = trim(line.substr(line.find("OS : ") + 5));
        const std::size_t mount = line.find("mount domain ");
        if (mount != std::string::npos) {
            const std::size_t colon = line.find(": ", mount);
            if (colon != std::string::npos) {
                const std::string value = trim(line.substr(colon + 2));
                if (!value.empty()) info.mounts.push_back(value);
            }
        }
        const std::size_t use = line.find("use:");
        if (use != std::string::npos && use + 4 < line.size()) {
            const std::string value = trim(line.substr(use + 4));
            if (!value.empty() && fsutil::endsWithNoCase(value, ".dll"))
                info.plugins.push_back(value);
        }
    }
    return info;
}

// ------------------------------------------------------------ .cf / .cfu
namespace {

std::string unescape(const std::string& raw) {
    std::string out;
    for (std::size_t i = 0; i < raw.size(); ++i) {
        const char c = raw[i];
        if (c != '\\' || i + 1 >= raw.size()) {
            out.push_back(c);
            continue;
        }
        const char n = raw[i + 1];
        if (n == 'x' || n == 'X') {
            auto hex = [](char h) -> int {
                if (h >= '0' && h <= '9') return h - '0';
                if (h >= 'a' && h <= 'f') return h - 'a' + 10;
                if (h >= 'A' && h <= 'F') return h - 'A' + 10;
                return -1;
            };
            if (i + 3 < raw.size()) {
                const int hi = hex(raw[i + 2]);
                const int lo = hex(raw[i + 3]);
                if (hi >= 0 && lo >= 0) {
                    out.push_back(static_cast<char>((hi << 4) | lo));
                    i += 3;
                    continue;
                }
            }
            out.push_back(c);
        } else if (n == 'n') {
            out.push_back('\n');
            ++i;
        } else if (n == 't') {
            out.push_back('\t');
            ++i;
        } else if (n == '\\' || n == '"') {
            out.push_back(n);
            ++i;
        } else {
            out.push_back(c);
        }
    }
    return out;
}

std::string stripQuotes(std::string s) {
    s = trim(s);
    if (s.size() >= 2 && s.front() == '"' && s.back() == '"')
        return s.substr(1, s.size() - 2);
    return s;
}

}  // namespace

ConfigValues parseKiriKiriConfig(const std::string& utf8Path) {
    ConfigValues cv;
    std::vector<uint8_t> bytes;
    if (!fsutil::readWholeFile(utf8Path, bytes, 4ull * 1024 * 1024)) return cv;
    cv.found = true;
    const std::string text(bytes.begin(), bytes.end());

    std::size_t pos = 0;
    while (pos <= text.size()) {
        std::size_t eol = text.find('\n', pos);
        if (eol == std::string::npos) eol = text.size();
        std::string line = trim(text.substr(pos, eol - pos));
        pos = eol + 1;
        if (line.empty() || line[0] == ';' || line[0] == '[' || line[0] == '#') continue;
        const std::size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string key = lowerAscii(trim(line.substr(0, eq)));
        const std::string value = unescape(stripQuotes(line.substr(eq + 1)));
        if (key.empty()) continue;
        cv.items.emplace_back(key, value);
    }
    return cv;
}

// ------------------------------------------------------------- plug-ins
namespace {

const PluginKnowledge kPlugins[] = {
    // id                     support                 note
    {"kagparserex", PluginSupport::Available, "KAG parser (krkrz_dev plugin, static on iOS)"},
    {"alphamovie", PluginSupport::Available, "AlphaMovie decoder (krkrz_dev plugin)"},
    {"layerexdraw", PluginSupport::Missing, "krkrz_dev layerExDraw is Win32 only (windows.h + gdiplus)"},
    {"layerexraster", PluginSupport::Available, "layerExRaster (krkrz_dev plugin)"},
    {"layerexvector", PluginSupport::Available, "layerExVector (krkrz_dev plugin)"},
    {"layerexlongexposure", PluginSupport::Available, "layerExLongExposure (krkrz_dev plugin)"},
    {"layerexbtoa", PluginSupport::Missing, "not part of krkrz_dev"},
    {"extrans", PluginSupport::Available, "extrans transition plugin (krkrz_dev plugin)"},
    {"extnagano", PluginSupport::Available, "extNagano plugin (krkrz_dev plugin)"},
    {"psdfile", PluginSupport::Available, "PSD loader (krkrz_dev psdfile plugin)"},
    {"psd", PluginSupport::Available, "PSD loader (krkrz_dev psdfile plugin)"},
    {"windowex", PluginSupport::Missing, "krkrz_dev windowEx is Win32 only"},
    {"menu", PluginSupport::Missing, "krkrz_dev menu plugin is Win32 only"},
    {"json", PluginSupport::Available, "json plugin (krkrz_dev plugin)"},
    {"shrinkcopy", PluginSupport::Available, "shrinkCopy (krkrz_dev plugin)"},
    {"scriptsex", PluginSupport::Available, "scriptsEx (krkrz_dev plugin)"},
    {"systemex", PluginSupport::Missing, "krkrz_dev systemEx is Win32 only"},
    {"csvparser", PluginSupport::Available, "CSV parser (krkrz_dev plugin)"},
    {"lineparser", PluginSupport::Available, "line parser (krkrz_dev plugin)"},
    {"messenger", PluginSupport::Missing, "krkrz_dev messenger is Win32 only"},
    {"addfont", PluginSupport::Partial, "krkrz_dev addFont is Win32 only; fonts are loaded from the project instead"},
    {"fpslimit", PluginSupport::Missing, "krkrz_dev fpslimit is Win32 only; OEP paces frames with CADisplayLink"},
    {"fstat", PluginSupport::Missing, "krkrz_dev fstat is Win32 only (tchar.h)"},
    {"savestruct", PluginSupport::Available, "saveStruct (krkrz_dev plugin)"},
    {"memfile", PluginSupport::Available, "memfile (krkrz_dev plugin)"},
    {"sigcheck", PluginSupport::Available, "sigcheck (krkrz_dev plugin)"},

    // Built into the engine core, the DLLs exist only for Win32 titles.
    {"wuvorbis", PluginSupport::Available, "Ogg Vorbis decoding is built into krkrz core"},
    {"wuopus", PluginSupport::Available, "Opus decoding is built into krkrz core"},
    {"k2compat", PluginSupport::Partial, "KiriKiri2 compatibility layer; iOS build uses krkrz APIs"},
    {"textrender", PluginSupport::Partial, "krkrz renders text itself; the Win32 DLL is not used"},
    {"krmovie", PluginSupport::Partial, "krkrz 1.2.0.3 movie support comes from the movie-player external"},
    {"getlangname", PluginSupport::Unknown, "behaviour depends on the title's script"},
    {"getsample", PluginSupport::Unknown, "behaviour depends on the title's script"},
    {"kagexopt", PluginSupport::Unknown, "KAG extension; needs verification"},
    {"varfile", PluginSupport::Missing, "krkrz_dev varfile is Win32 only"},
    {"binarystream", PluginSupport::Missing, "krkrz_dev binaryStream is Win32 only"},
    {"packinone", PluginSupport::Missing, "not part of krkrz_dev"},

    // Windows / D3D / title specific
    {"drawdeviced3d", PluginSupport::Missing, "Direct3D draw device; iOS uses GLES / SDL draw device"},
    {"drawdeviced3dz", PluginSupport::Missing, "Direct3D draw device; iOS uses GLES / SDL draw device"},
    {"steamdrawdevice", PluginSupport::Missing, "Steam specific draw device"},
    {"emoteplayer", PluginSupport::Missing, "E-mote player is Win32 only; no iOS build in krkrz_dev"},
    {"motionplayer", PluginSupport::Missing, "motionplayer (D3D) is Win32 only"},
    {"motionplayer_nod3d", PluginSupport::Missing, "Win32 only"},
    {"msdfrender", PluginSupport::Missing, "MSDF renderer is not part of krkrz_dev"},
    {"squirrel", PluginSupport::Missing, "Squirrel script VM plugin is Win32 only"},
    {"lzfs", PluginSupport::Missing, "title specific filesystem plugin"},
    {"yuzuex", PluginSupport::Missing, "Yuzusoft extension plugin (Win32 only)"},
    {"kztouch", PluginSupport::Missing, "Windows touch helper; iOS input is handled by the engine"},
    {"win32dialog", PluginSupport::Missing, "Win32 dialog; krkrz on iOS uses Elements dialogs"},
    {"win32ole", PluginSupport::Missing, "Win32 OLE automation"},
    {"windowexprogress", PluginSupport::Missing, "Win32 only"},
    {"krkrsteam", PluginSupport::Missing, "Steam API bridge"},
    {"steam", PluginSupport::Missing, "Steam API bridge"},
    {"wftypicaldsp", PluginSupport::Missing, "title specific DSP plugin"},
    {"httprequest", PluginSupport::Available, "httprequest (krkrz_dev plugin)"},
};

const PluginKnowledge* findKnowledge(const std::string& id) {
    const std::string key = lowerAscii(id);
    for (const auto& k : kPlugins) {
        if (lowerAscii(k.id) == key) return &k;
    }
    return nullptr;
}

}  // namespace

const char* pluginSupportLabel(PluginSupport s) {
    switch (s) {
        case PluginSupport::Available: return "available";
        case PluginSupport::Partial: return "partial";
        case PluginSupport::Missing: return "missing";
        default: return "unknown";
    }
}

const char* pluginSupportJapanese(PluginSupport s) {
    switch (s) {
        case PluginSupport::Available: return "対応";
        case PluginSupport::Partial: return "一部対応";
        case PluginSupport::Missing: return "未対応";
        default: return "調査中";
    }
}

PluginKnowledge lookupPlugin(const std::string& dllFileName) {
    std::string id = fsutil::stem(fsutil::fileName(dllFileName));
    if (const PluginKnowledge* k = findKnowledge(id)) return *k;
    return PluginKnowledge{"", PluginSupport::Unknown, "no verified data for this plug-in"};
}

std::size_t PluginInventory::count(PluginSupport s) const {
    std::size_t n = 0;
    for (const auto& e : entries)
        if (e.support == s) ++n;
    return n;
}

PluginInventory collectPlugins(const std::string& utf8Folder) {
    PluginInventory inv;
    const std::string pluginDir = fsutil::join(utf8Folder, "plugin");
    inv.folderPresent = fsutil::isDirectory(pluginDir);

    auto consider = [&inv](const std::string&, const std::string& name) {
        if (!fsutil::endsWithNoCase(name, ".dll") && !fsutil::endsWithNoCase(name, ".tpm"))
            return;
        PluginEntry e;
        e.file = name;
        e.id = lowerAscii(fsutil::stem(name));
        const PluginKnowledge k = lookupPlugin(name);
        e.support = k.support;
        e.note = k.note;
        inv.entries.push_back(e);
    };

    if (inv.folderPresent) {
        for (const auto& name : fsutil::listDirectory(pluginDir)) consider(pluginDir, name);
    }
    for (const auto& name : fsutil::listDirectory(utf8Folder)) {
        if (fsutil::endsWithNoCase(name, ".tpm")) consider(utf8Folder, name);
    }
    std::sort(inv.entries.begin(), inv.entries.end(),
              [](const PluginEntry& a, const PluginEntry& b) { return a.file < b.file; });
    return inv;
}

// ------------------------------------------------------------- engine guess
const char* engineKindLabel(EngineKind k) {
    switch (k) {
        case EngineKind::KiriKiriZ: return "KiriKiri Z (krkrz)";
        case EngineKind::KiriKiriZGeneric: return "KiriKiri Z (generic)";
        case EngineKind::KiriKiri2: return "KiriKiri 2";
        case EngineKind::KirikiriSDL: return "KiriKiri (SDL port)";
        default: return "Unknown";
    }
}

const char* engineKindJapanese(EngineKind k) {
    switch (k) {
        case EngineKind::KiriKiriZ: return "吉里吉里Z";
        case EngineKind::KiriKiriZGeneric: return "吉里吉里Z (generic)";
        case EngineKind::KiriKiri2: return "吉里吉里2";
        case EngineKind::KirikiriSDL: return "吉里吉里 (SDL版)";
        default: return "不明";
    }
}

EngineIdentity identifyEngine(const std::string& utf8Folder) {
    EngineIdentity id;
    const std::string log = newestConsoleLog(utf8Folder);
    id.log = parseConsoleLog(log);

    // Win32 executables (the .cf name normally matches the exe stem).
    std::vector<std::string> exes;
    for (const auto& name : fsutil::listDirectory(utf8Folder)) {
        if (fsutil::endsWithNoCase(name, ".exe"))
            exes.push_back(fsutil::join(utf8Folder, name));
    }
    std::sort(exes.begin(), exes.end(), [](const std::string& a, const std::string& b) {
        return fsutil::fileSize(a) > fsutil::fileSize(b);
    });
    for (const auto& exe : exes) {
        PeVersionInfo v = readPeVersionInfo(exe);
        if (v.valid) {
            id.exe = v;
            break;
        }
    }

    // Configuration files.
    for (const auto& name : fsutil::listDirectory(utf8Folder)) {
        if (!fsutil::endsWithNoCase(name, ".cf") && !fsutil::endsWithNoCase(name, ".cfu"))
            continue;
        ConfigValues cv = parseKiriKiriConfig(fsutil::join(utf8Folder, name));
        if (cv.found) {
            id.config.found = true;
            for (auto& kv : cv.items) id.config.items.push_back(std::move(kv));
        }
    }

    const std::string product = lowerAscii(id.exe.productName + " " + id.exe.fileDescription);
    const bool looksZ = product.find("kirikiri) z") != std::string::npos ||
                        product.find("kirikiri z") != std::string::npos ||
                        !id.log.kirikiriVersion.empty();
    const bool looks2 = product.find("kirikiri) 2") != std::string::npos ||
                        product.find("kirikiri 2") != std::string::npos;

    if (looksZ) {
        id.kind = EngineKind::KiriKiriZ;
        id.evidence = !id.log.kirikiriVersion.empty() ? "console log" : "PE version resource";
        id.version = !id.log.kirikiriVersion.empty() ? id.log.kirikiriVersion
                                                     : (id.exe.productVersion.empty()
                                                            ? id.exe.fileVersion
                                                            : id.exe.productVersion);
        id.tjs2Version = id.log.tjs2Version;
    } else if (looks2) {
        id.kind = EngineKind::KiriKiri2;
        id.evidence = "PE version resource";
        id.version = id.exe.productVersion.empty() ? id.exe.fileVersion : id.exe.productVersion;
    } else if (fsutil::exists(fsutil::join(utf8Folder, "data.xp3")) ||
               fsutil::exists(fsutil::join(utf8Folder, "data/startup.tjs"))) {
        id.kind = EngineKind::Unknown;
        id.evidence = "archive layout only";
    }
    return id;
}

}  // namespace oep
