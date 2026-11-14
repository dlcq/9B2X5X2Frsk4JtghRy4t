// OEP core tests - portable, no external test framework.
//
//   oep_tests                 unit tests only
//   oep_tests <gameFolder>... also scans real game folders (metadata only)
//
// The XP3 tests build archives byte-for-byte the way krkrz lays them out
// (chained, optionally zlib compressed index; raw or zlib segments), so the
// reader is exercised against the real format rather than a mock.
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>
#include <vector>

#include "miniz.h"
#include "oep/detect.hpp"
#include "oep/json.hpp"
#include "oep/log.hpp"
#include "oep/pack.hpp"
#include "oep/platform.hpp"
#include "oep/scan.hpp"
#include "oep/xp3.hpp"

namespace {

int g_failures = 0;
int g_checks = 0;
std::string g_currentTest;

#define CHECK(cond)                                                                  \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (!(cond)) {                                                               \
            ++g_failures;                                                            \
            std::printf("  FAIL %s:%d [%s] %s\n", __FILE__, __LINE__,                \
                        g_currentTest.c_str(), #cond);                               \
        }                                                                            \
    } while (0)

#define CHECK_EQ(a, b)                                                               \
    do {                                                                             \
        ++g_checks;                                                                  \
        auto va = (a);                                                               \
        auto vb = (b);                                                               \
        if (!(va == vb)) {                                                           \
            ++g_failures;                                                            \
            std::printf("  FAIL %s:%d [%s] %s != %s\n", __FILE__, __LINE__,          \
                        g_currentTest.c_str(), #a, #b);                              \
        }                                                                            \
    } while (0)

struct TestCase {
    const char* name;
    std::function<void()> fn;
};

std::vector<TestCase>& registry() {
    static std::vector<TestCase> tests;
    return tests;
}

struct Register {
    Register(const char* name, std::function<void()> fn) { registry().push_back({name, fn}); }
};

#define TEST(name)                                                     \
    static void test_##name();                                         \
    static Register reg_##name(#name, test_##name);                    \
    static void test_##name()

// ---------------------------------------------------------------- utilities
namespace fs = std::filesystem;

fs::path tempPath(const std::string& name) {
    fs::path dir = fs::temp_directory_path() / "oep-core-tests";
    std::error_code ec;
    fs::create_directories(dir, ec);
    return dir / name;
}

void writeFile(const fs::path& p, const std::vector<uint8_t>& data) {
    std::ofstream f(p, std::ios::binary | std::ios::trunc);
    f.write(reinterpret_cast<const char*>(data.data()),
            static_cast<std::streamsize>(data.size()));
}

std::string norm(const fs::path& p) {
    const auto s = p.u8string();
    return std::string(s.begin(), s.end());
}

void put16(std::vector<uint8_t>& v, uint16_t x) {
    v.push_back(static_cast<uint8_t>(x & 0xFF));
    v.push_back(static_cast<uint8_t>(x >> 8));
}
void put32(std::vector<uint8_t>& v, uint32_t x) {
    for (int i = 0; i < 4; ++i) v.push_back(static_cast<uint8_t>((x >> (8 * i)) & 0xFF));
}
void put64(std::vector<uint8_t>& v, uint64_t x) {
    for (int i = 0; i < 8; ++i) v.push_back(static_cast<uint8_t>((x >> (8 * i)) & 0xFF));
}
void patch64(std::vector<uint8_t>& v, std::size_t at, uint64_t x) {
    for (int i = 0; i < 8; ++i) v[at + i] = static_cast<uint8_t>((x >> (8 * i)) & 0xFF);
}
void putUtf16(std::vector<uint8_t>& v, const std::string& ascii) {
    for (char c : ascii) {
        v.push_back(static_cast<uint8_t>(c));
        v.push_back(0);
    }
}

struct TestFile {
    std::string name;
    std::vector<uint8_t> data;
    bool compress = false;
    bool protect = false;
    bool hashedName = false;
};

std::vector<uint8_t> zlibCompress(const std::vector<uint8_t>& in) {
    mz_ulong outLen = mz_compressBound(static_cast<mz_ulong>(in.size()));
    std::vector<uint8_t> out(outLen);
    const int rc = mz_compress(out.data(), &outLen, in.data(),
                               static_cast<mz_ulong>(in.size()));
    if (rc != MZ_OK) return {};
    out.resize(outLen);
    return out;
}

std::string pseudoHash(const std::string& name) {
    uint32_t h = 2166136261u;
    for (unsigned char c : name) {
        h ^= c;
        h *= 16777619u;
    }
    char buf[40];
    std::snprintf(buf, sizeof(buf), "%08x%08x%08x%08x", h, h * 2654435761u,
                  h ^ 0x9e3779b9u, h + 0x7f4a7c15u);
    return std::string(buf).substr(0, 32);
}

// Builds an archive in the krkrz layout.  When splitIndex is 64 or more the
// entries are spread over two chained index blocks.
std::vector<uint8_t> buildXp3(const std::vector<TestFile>& files, bool compressIndex) {
    std::vector<uint8_t> out;
    for (unsigned char c : oep::kXp3Magic) out.push_back(c);
    put64(out, 0);  // index offset, patched later

    std::vector<uint8_t> index;

    for (const auto& f : files) {
        std::vector<uint8_t> stored = f.compress ? zlibCompress(f.data) : f.data;
        const uint64_t start = out.size();
        out.insert(out.end(), stored.begin(), stored.end());

        std::vector<uint8_t> fileChunk;
        {
            std::vector<uint8_t> info;
            put32(info, f.protect ? 0x80000000u : 0u);
            put64(info, f.data.size());
            put64(info, stored.size());
            const std::string storedName = f.hashedName ? pseudoHash(f.name) : f.name;
            put16(info, static_cast<uint16_t>(storedName.size()));
            putUtf16(info, storedName);

            std::vector<uint8_t> segm;
            put32(segm, f.compress ? 1u : 0u);
            put64(segm, start);
            put64(segm, f.data.size());
            put64(segm, stored.size());

            std::vector<uint8_t> adlr;
            put32(adlr, static_cast<uint32_t>(std::hash<std::string>{}(f.name)));

            for (const auto& chunk :
                 std::vector<std::pair<const char*, std::vector<uint8_t>>>{
                     {"info", info}, {"segm", segm}, {"adlr", adlr}}) {
                const uint64_t len = chunk.second.size();
                fileChunk.insert(fileChunk.end(), chunk.first, chunk.first + 4);
                put64(fileChunk, len);
                fileChunk.insert(fileChunk.end(), chunk.second.begin(), chunk.second.end());
            }
        }
        index.insert(index.end(), {'F', 'i', 'l', 'e'});
        put64(index, fileChunk.size());
        index.insert(index.end(), fileChunk.begin(), fileChunk.end());
    }

    std::vector<uint8_t> block;
    if (compressIndex) {
        std::vector<uint8_t> compressed = zlibCompress(index);
        block.push_back(0x01);
        put64(block, compressed.size());
        put64(block, index.size());
        block.insert(block.end(), compressed.begin(), compressed.end());
    } else {
        block.push_back(0x00);
        put64(block, index.size());
        block.insert(block.end(), index.begin(), index.end());
    }

    const uint64_t indexOffset = out.size();
    patch64(out, 11, indexOffset);
    out.insert(out.end(), block.begin(), block.end());
    return out;
}

// ---------------------------------------------------------------- XP3 tests
TEST(xp3_roundtrip_raw) {
    std::vector<TestFile> files = {
        {"startup.tjs", {'v', 'a', 'r', ' ', 'x', '=', '1', ';'}, false, false, false},
        {"data/hello.txt", {'h', 'e', 'l', 'l', 'o'}, false, false, false},
    };
    const fs::path p = tempPath("raw.xp3");
    writeFile(p, buildXp3(files, false));

    oep::Xp3Archive a;
    oep::Error e = a.open(norm(p));
    CHECK(e.ok());
    CHECK_EQ(a.entries().size(), std::size_t(2));
    const oep::Xp3Entry* startup = a.find("startup.tjs");
    CHECK(startup != nullptr);
    if (startup) {
        std::vector<uint8_t> data;
        e = a.readEntry(*startup, data);
        CHECK(e.ok());
        CHECK_EQ(std::string(data.begin(), data.end()), std::string("var x=1;"));
    }
    CHECK(a.find("missing.tjs") == nullptr);
}

TEST(xp3_roundtrip_compressed_index_and_segments) {
    std::vector<TestFile> files;
    std::string big;
    for (int i = 0; i < 200; ++i) big += "line " + std::to_string(i) + "\n";
    files.push_back({"system/init.tjs", std::vector<uint8_t>(big.begin(), big.end()), true, false,
                     false});
    files.push_back({"image/plain.bin", {1, 2, 3, 4, 5, 6, 7, 8}, false, false, false});

    const fs::path p = tempPath("zlib.xp3");
    writeFile(p, buildXp3(files, true));

    oep::Xp3Archive a;
    oep::Error e = a.open(norm(p));
    CHECK(e.ok());
    CHECK_EQ(a.entries().size(), std::size_t(2));
    const oep::Xp3Entry* init = a.find("system/init.tjs");
    CHECK(init != nullptr);
    if (init) {
        std::vector<uint8_t> data;
        e = a.readEntry(*init, data);
        CHECK(e.ok());
        CHECK_EQ(data.size(), big.size());
        CHECK(std::string(data.begin(), data.end()) == big);
        CHECK_EQ(init->segments.size(), std::size_t(1));
        CHECK(init->segments[0].compressed());
    }
}

TEST(xp3_protected_and_hashed_names) {
    std::vector<TestFile> files = {
        {"$$$ This is a protected archive. $$$ warning.txt", {'w'}, false, true, false},
        {"secret/asset.bin", {9, 9, 9}, false, true, true},
    };
    const fs::path p = tempPath("protected.xp3");
    writeFile(p, buildXp3(files, true));

    oep::Xp3Archive a;
    oep::Error e = a.open(norm(p));
    CHECK(e.ok());
    const auto stats = a.stats();
    CHECK_EQ(stats.totalEntries, uint64_t(2));
    CHECK_EQ(stats.protectedEntries, uint64_t(2));
    CHECK_EQ(stats.hashedNames, uint64_t(1));

    bool foundWarning = false;
    for (const auto& entry : a.entries()) {
        if (entry.name.find("This is a protected archive") != std::string::npos)
            foundWarning = true;
    }
    CHECK(foundWarning);
    CHECK(oep::Xp3Entry::isHashedStorageName(pseudoHash("abc")));
    CHECK(!oep::Xp3Entry::isHashedStorageName("startup.tjs"));
    CHECK(!oep::Xp3Entry::isHashedStorageName("0123456789abcdef"));
}

TEST(xp3_rejects_non_archive) {
    const fs::path p = tempPath("plain.bin");
    writeFile(p, std::vector<uint8_t>(64, 0x41));
    oep::Xp3Archive a;
    oep::Error e = a.open(norm(p));
    CHECK(!e.ok());
    CHECK(e.code == oep::ErrorCode::NotXp3);
    CHECK(!oep::Xp3Archive::hasXp3Magic(norm(p)));

    const fs::path missing = tempPath("does-not-exist.xp3");
    std::error_code ec;
    fs::remove(missing, ec);
    CHECK(!oep::Xp3Archive::hasXp3Magic(norm(missing)));
}

TEST(xp3_truncated_index_is_reported) {
    std::vector<TestFile> files = {{"a.txt", {'a'}, false, false, false}};
    std::vector<uint8_t> bytes = buildXp3(files, true);
    bytes.resize(bytes.size() - 8);  // cut into the compressed index stream
    const fs::path p = tempPath("truncated.xp3");
    writeFile(p, bytes);

    oep::Xp3Archive a;
    oep::Error e = a.open(norm(p));
    CHECK(!e.ok());
}

TEST(xp3_verify_detects_good_archive) {
    std::vector<TestFile> files = {
        {"a.txt", {'a', 'b', 'c'}, true, false, false},
        {"b.bin", {0, 1, 2, 3}, false, false, false},
    };
    const fs::path p = tempPath("verify.xp3");
    writeFile(p, buildXp3(files, true));

    oep::Xp3Archive a;
    CHECK(a.open(norm(p)).ok());
    std::size_t examined = 0;
    std::vector<std::string> failures;
    const oep::Error e = a.verify(examined, failures);
    CHECK(e.ok());
    CHECK_EQ(examined, std::size_t(2));
    CHECK_EQ(failures.size(), std::size_t(0));
}

TEST(xp3_packer_roundtrip) {
    const fs::path dir = tempPath("packed-src");
    std::error_code ec;
    fs::remove_all(dir, ec);
    fs::create_directories(dir / "sub", ec);
    const std::string script = "var greeting = \"hello from OEP\";\n";
    writeFile(dir / "startup.tjs", std::vector<uint8_t>(script.begin(), script.end()));
    writeFile(dir / "sub" / "note.txt", std::vector<uint8_t>{'n', 'o', 't', 'e'});

    oep::PackOptions options;
    oep::PackResult result;
    const fs::path out = tempPath("packed.xp3");
    const oep::Error e = oep::packFolderToXp3(norm(dir), norm(out), options, result);
    CHECK(e.ok());
    CHECK_EQ(result.fileCount, uint64_t(2));
    CHECK(result.archiveBytes > 19);

    oep::Xp3Archive a;
    CHECK(a.open(norm(out)).ok());
    CHECK_EQ(a.entries().size(), std::size_t(2));
    const oep::Xp3Entry* startup = a.find("startup.tjs");
    CHECK(startup != nullptr);
    if (startup) {
        std::vector<uint8_t> data;
        CHECK(a.readEntry(*startup, data).ok());
        CHECK(std::string(data.begin(), data.end()) == script);
    }
    CHECK(a.find("sub/note.txt") != nullptr);

    std::size_t examined = 0;
    std::vector<std::string> failures;
    CHECK(a.verify(examined, failures).ok());
    CHECK_EQ(failures.size(), std::size_t(0));
}

// ---------------------------------------------------------------- config tests
TEST(config_escaped_values) {
    const fs::path p = tempPath("game.cf");
    const std::string text =
        "datapath=\"\\x24\\x28\\x61\\x70\\x70\\x64\\x61\\x74\\x61\\x70\\x61\\x74\\x68\\x29\"\n"
        "vomstyle=\"layer\"\n"
        "; comment\n"
        "[Section]\n"
        "wheel=message\n";
    writeFile(p, std::vector<uint8_t>(text.begin(), text.end()));

    const oep::ConfigValues cv = oep::parseKiriKiriConfig(norm(p));
    CHECK(cv.found);
    CHECK_EQ(cv.get("datapath"), std::string("$(appdatapath)"));
    CHECK_EQ(cv.get("vomstyle"), std::string("layer"));
    CHECK_EQ(cv.get("wheel"), std::string("message"));
}

// ---------------------------------------------------------------- PE version
void putAlign4(std::vector<uint8_t>& v) {
    while (v.size() % 4) v.push_back(0);
}

std::vector<uint8_t> verBlock(const std::string& key, uint16_t type,
                              const std::vector<uint8_t>& value,
                              const std::vector<uint8_t>& children) {
    std::vector<uint8_t> v;
    put16(v, 0);  // length placeholder
    put16(v, static_cast<uint16_t>(type == 1 ? value.size() / 2 : value.size()));
    put16(v, type);
    putUtf16(v, key);
    put16(v, 0);  // terminator
    putAlign4(v);
    v.insert(v.end(), value.begin(), value.end());
    putAlign4(v);
    v.insert(v.end(), children.begin(), children.end());
    putAlign4(v);
    const uint16_t len = static_cast<uint16_t>(v.size());
    v[0] = static_cast<uint8_t>(len & 0xFF);
    v[1] = static_cast<uint8_t>(len >> 8);
    return v;
}

TEST(pe_version_resource) {
    std::vector<uint8_t> table;
    for (const auto& kv : std::vector<std::pair<std::string, std::string>>{
             {"FileDescription", "TVP(KIRIKIRI) Z core / Scripting Platform for Win32"},
             {"FileVersion", "1.2.0.3"},
             {"ProductName", "TVP(KIRIKIRI) Z core / Scripting Platform for Win32"},
             {"ProductVersion", "1.2.0.3"}}) {
        std::vector<uint8_t> value;
        putUtf16(value, kv.second);
        put16(value, 0);
        const std::vector<uint8_t> block = verBlock(kv.first, 1, value, {});
        table.insert(table.end(), block.begin(), block.end());
    }
    std::vector<uint8_t> tableBlock = verBlock("041104b0", 1, {}, table);
    std::vector<uint8_t> sfi = verBlock("StringFileInfo", 1, {}, tableBlock);
    std::vector<uint8_t> root = verBlock("VS_VERSION_INFO", 0, std::vector<uint8_t>(52, 0), sfi);

    std::vector<uint8_t> pe = {'M', 'Z'};
    pe.resize(0x80, 0);
    pe.insert(pe.end(), root.begin(), root.end());

    const fs::path p = tempPath("fake.exe");
    writeFile(p, pe);

    const oep::PeVersionInfo info = oep::readPeVersionInfo(norm(p));
    CHECK(info.valid);
    CHECK_EQ(info.fileVersion, std::string("1.2.0.3"));
    CHECK_EQ(info.productVersion, std::string("1.2.0.3"));
    CHECK(info.fileDescription.find("TVP(KIRIKIRI) Z") != std::string::npos);
}

TEST(pe_version_missing) {
    const fs::path p = tempPath("trunc.bin");
    writeFile(p, {'M', 'Z', 0, 0, 0, 0});
    const oep::PeVersionInfo info = oep::readPeVersionInfo(norm(p));
    CHECK(!info.valid);
}

// ---------------------------------------------------------------- console log
TEST(console_log_parse) {
    const std::string text =
        "18:32:55 ! Kiriki Z Executable core /1.2.0.3 (Compiled on Oct 28 2021 16:12:21) "
        "TJS2/2.4.28 Copyright (C) 1997-2013 W.Dee\n"
        "18:32:56 ! mount domain 0: file://./game/data.xp3\n"
        "18:32:56 ! mount domain 1: file://./game/voice.xp3\n"
        "18:32:56 ! ########################################\n"
        "18:32:56 ! OS : Windows 8 6.2.1008  (Win32)\n"
        "18:32:56 ! Engine : Revision 1947, Last Changed 2023/07/21 12:07:28, Compiled "
        "2023/07/21 12:07:37\n"
        "18:32:56 ! Kirikiri : 1.2.0.3\n"
        "18:32:56 ! use:motionplayer.dll\n";

    std::vector<uint8_t> utf16;
    utf16.push_back(0xFF);
    utf16.push_back(0xFE);
    for (unsigned char c : text) {
        utf16.push_back(c);
        utf16.push_back(0);
    }
    const fs::path dir = tempPath("logtest");
    std::error_code ec;
    fs::create_directories(dir / "savedata", ec);
    writeFile(dir / "savedata" / "krkr.console.log", utf16);

    const oep::ConsoleLogInfo info =
        oep::parseConsoleLog(norm(dir / "savedata" / "krkr.console.log"));
    CHECK(info.found);
    CHECK_EQ(info.kirikiriVersion, std::string("1.2.0.3"));
    CHECK_EQ(info.tjs2Version, std::string("2.4.28"));
    CHECK_EQ(info.revision, std::string("1947"));
    CHECK_EQ(info.mounts.size(), std::size_t(2));
    CHECK_EQ(info.plugins.size(), std::size_t(1));
    CHECK(info.platform.find("Windows") != std::string::npos);
}

// ---------------------------------------------------------------- plugins
TEST(plugin_knowledge) {
    using oep::PluginSupport;
    CHECK(oep::lookupPlugin("KAGParserEx.dll").support == PluginSupport::Available);
    CHECK(oep::lookupPlugin("drawdeviceD3D.dll").support == PluginSupport::Missing);
    CHECK(oep::lookupPlugin("emoteplayer.dll").support == PluginSupport::Missing);
    CHECK(oep::lookupPlugin("wuvorbis.dll").support == PluginSupport::Available);
    CHECK(oep::lookupPlugin("someTitleSpecific.dll").support == PluginSupport::Unknown);
    CHECK_EQ(std::string(oep::pluginSupportJapanese(PluginSupport::Partial)),
             std::string("一部対応"));
}

TEST(plugin_inventory_scan) {
    const fs::path dir = tempPath("inventory");
    std::error_code ec;
    fs::create_directories(dir / "plugin", ec);
    writeFile(dir / "plugin" / "KAGParserEx.dll", {0});
    writeFile(dir / "plugin" / "motionplayer.dll", {0});
    writeFile(dir / "plugin" / "notes.txt", {0});

    const oep::PluginInventory inv = oep::collectPlugins(norm(dir));
    CHECK(inv.folderPresent);
    CHECK_EQ(inv.entries.size(), std::size_t(2));
    CHECK_EQ(inv.count(oep::PluginSupport::Available), std::size_t(1));
    CHECK_EQ(inv.count(oep::PluginSupport::Missing), std::size_t(1));
}

// ---------------------------------------------------------------- JSON writer
TEST(json_writer_shape) {
    oep::JsonWriter w(true);
    w.beginObject();
    w.field("name", "a\"b");
    w.field("count", 3);
    w.field("ok", true);
    w.key("list").beginArray();
    w.value("x");
    w.value("y");
    w.endArray();
    w.key("empty").beginArray();
    w.endArray();
    w.endObject();
    const std::string out = w.str();
    CHECK(out.find("\"name\": \"a\\\"b\"") != std::string::npos);
    CHECK(out.find("\"count\": 3") != std::string::npos);
    CHECK(out.find("\"empty\": []") != std::string::npos);
    CHECK(out.find("\"list\": [") != std::string::npos);
}

// ---------------------------------------------------------------- logger
TEST(logger_ring_buffer) {
    oep::Logger& log = oep::Logger::shared();
    log.setCapacity(3);
    log.clear();
    log.info("test", "one");
    log.warning("test", "two");
    log.error("test", "three");
    log.debug("test", "four");
    CHECK_EQ(log.size(), std::size_t(3));
    const auto entries = log.snapshot();
    CHECK_EQ(entries.size(), std::size_t(3));
    CHECK_EQ(entries.back().message, std::string("four"));
    CHECK_EQ(std::string(oep::logLevelName(entries.back().level)), std::string("DEBUG"));
    const std::string text = log.exportText();
    CHECK(text.find("test: four") != std::string::npos);
    log.setCapacity(4000);
    log.clear();
}

// ---------------------------------------------------------------- real data
void checkRealFolder(const std::string& folder) {
    using namespace oep;
    g_currentTest = "real:" + folder;
    std::printf("         path bytes:");
    for (unsigned char c : folder) std::printf(" %02x", c);
    std::printf("         is_dir(wide)=%d\n",
                (int)std::filesystem::is_directory(
                    std::filesystem::path(oep::wideFromUtf8(folder))));
    const GameScan scan = scanGame(folder);
    std::printf("  [real] %s\n", scan.displayName.c_str());
    std::printf("         engine=%s version=%s tjs2=%s evidence=%s\n",
                engineKindLabel(scan.engine.kind), scan.engine.version.c_str(),
                scan.engine.tjs2Version.c_str(), scan.engine.evidence.c_str());
    std::printf("         archives=%zu total=%llu startup=%d level=%s\n", scan.archives.size(),
                static_cast<unsigned long long>(scan.totalBytes),
                scan.hasStartupScript ? 1 : 0, supportLevelLabel(scan.level));
    for (const auto& a : scan.archives) {
        std::printf("         %-24s idx=%s entries=%llu filtered=%d hashed=%llu\n",
                    a.fileName.c_str(), a.indexOk ? "ok" : "ERR",
                    static_cast<unsigned long long>(a.entries),
                    a.probeAttempted && !a.contentReadable ? 1 : 0,
                    static_cast<unsigned long long>(a.hashedNames));
    }
    const std::string json = scanToJson(scan, true);
    CHECK(!json.empty());
    CHECK(json.find("\"supportLevel\"") != std::string::npos);
    CHECK(scan.engine.kind == EngineKind::KiriKiriZ);
    CHECK(!scan.engine.version.empty());
    CHECK(scan.hasDataXp3);
    CHECK(!scan.archives.empty());
    // Files that merely carry the .xp3 extension are reported, not treated as
    // archives; every real archive must parse.
    for (const auto& a : scan.archives)
        if (a.xp3Magic) CHECK(a.indexOk);
}

}  // namespace

int main(int argc, char** argv) {
    const std::vector<std::string> args = oep::processArguments(argc, argv);
    for (const auto& t : registry()) {
        g_currentTest = t.name;
        const int before = g_failures;
        t.fn();
        std::printf("%s %s\n", g_failures == before ? "ok  " : "FAIL", t.name);
    }

    if (args.size() > 1) {
        std::printf("\n-- real game folders --\n");
        for (std::size_t i = 1; i < args.size(); ++i) checkRealFolder(args[i]);
    }

    std::printf("\n%d checks, %d failure(s)\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
