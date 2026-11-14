#include "oep/pack.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <utility>
#include <vector>

#include "fsutil.hpp"
#include "miniz.h"
#include "oep/xp3.hpp"

namespace oep {
namespace {

namespace fs = std::filesystem;

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

// XP3 stores names as UTF-16 code units; the packer takes UTF-8 from the OS and
// widens it so non-ASCII folder names survive.
void putNameUtf16(std::vector<uint8_t>& v, const std::string& utf8Name) {
    std::size_t i = 0;
    while (i < utf8Name.size()) {
        const unsigned char c = static_cast<unsigned char>(utf8Name[i]);
        uint32_t cp = c;
        std::size_t extra = 0;
        if (c >= 0xF0) {
            cp = c & 0x07u;
            extra = 3;
        } else if (c >= 0xE0) {
            cp = c & 0x0Fu;
            extra = 2;
        } else if (c >= 0xC0) {
            cp = c & 0x1Fu;
            extra = 1;
        }
        for (std::size_t k = 1; k <= extra && i + k < utf8Name.size(); ++k)
            cp = (cp << 6) | (static_cast<unsigned char>(utf8Name[i + k]) & 0x3Fu);
        i += extra + 1;

        if (cp >= 0x10000) {
            cp -= 0x10000;
            put16(v, static_cast<uint16_t>(0xD800 + (cp >> 10)));
            put16(v, static_cast<uint16_t>(0xDC00 + (cp & 0x3FF)));
        } else {
            put16(v, static_cast<uint16_t>(cp));
        }
    }
}

std::size_t utf16Units(const std::string& utf8Name) {
    std::vector<uint8_t> tmp;
    putNameUtf16(tmp, utf8Name);
    return tmp.size() / 2;
}

std::vector<uint8_t> zlibDeflate(const std::vector<uint8_t>& in) {
    mz_ulong bound = mz_compressBound(static_cast<mz_ulong>(in.size()));
    std::vector<uint8_t> out(bound);
    if (mz_compress(out.data(), &bound, in.data(), static_cast<mz_ulong>(in.size())) != MZ_OK)
        return {};
    out.resize(bound);
    return out;
}

struct PackItem {
    std::string name;
    std::vector<uint8_t> data;
};

bool collect(const fs::path& root, const fs::path& current, const PackOptions& options,
             std::vector<PackItem>& out, Error& error) {
    std::error_code ec;
    fs::directory_iterator it(current, ec);
    if (ec) {
        error = {ErrorCode::Io, "cannot read " + fsutil::utf8(current)};
        return false;
    }
    for (; it != fs::directory_iterator(); it.increment(ec)) {
        if (ec) break;
        const fs::path path = it->path();
        const std::string leaf = fsutil::utf8(path.filename());
        if (leaf.empty() || leaf[0] == '.') continue;
        const std::string lower = fsutil::lower(leaf);
        if (options.skipArchives && lower.size() >= 4 &&
            lower.compare(lower.size() - 4, 4, ".xp3") == 0)
            continue;
        if (fs::is_directory(path, ec)) {
            if (!collect(root, path, options, out, error)) return false;
            continue;
        }
        if (!fs::is_regular_file(path, ec)) continue;

        std::ifstream f(path, std::ios::binary);
        if (!f) {
            error = {ErrorCode::Io, "cannot read " + fsutil::utf8(path)};
            return false;
        }
        std::vector<uint8_t> data((std::istreambuf_iterator<char>(f)),
                                  std::istreambuf_iterator<char>());
        const fs::path rel = fs::relative(path, root, ec);
        if (ec) {
            error = {ErrorCode::Io, "cannot compute a relative path for " + fsutil::utf8(path)};
            return false;
        }
        std::string name = fsutil::utf8(rel);
        std::replace(name.begin(), name.end(), '\\', '/');
        out.push_back({name, std::move(data)});
    }
    return true;
}

}  // namespace

Error packFolderToXp3(const std::string& utf8Folder, const std::string& utf8OutFile,
                      const PackOptions& options, PackResult& result) {
    result = PackResult{};
    if (!fsutil::isDirectory(utf8Folder))
        return {ErrorCode::NotFound, "not a folder: " + utf8Folder};

    std::vector<PackItem> items;
    Error error;
    if (!collect(fsutil::path(utf8Folder), fsutil::path(utf8Folder), options, items, error))
        return error;
    if (items.empty()) return {ErrorCode::NotFound, "folder has no packable files"};

    std::sort(items.begin(), items.end(),
              [](const PackItem& a, const PackItem& b) { return a.name < b.name; });

    std::vector<uint8_t> archive(kXp3Magic, kXp3Magic + sizeof(kXp3Magic));
    put64(archive, 0);  // index offset, patched once the payload is written

    std::vector<uint8_t> index;
    for (const auto& item : items) {
        const uint64_t start = archive.size();
        archive.insert(archive.end(), item.data.begin(), item.data.end());
        result.payloadBytes += item.data.size();

        std::vector<uint8_t> info;
        put32(info, 0);  // flags: not extraction-protected
        put64(info, item.data.size());
        put64(info, item.data.size());
        put16(info, static_cast<uint16_t>(utf16Units(item.name)));
        putNameUtf16(info, item.name);

        std::vector<uint8_t> segm;
        put32(segm, 0);  // raw segment
        put64(segm, start);
        put64(segm, item.data.size());
        put64(segm, item.data.size());

        std::vector<uint8_t> adlr;
        put32(adlr, 0);

        std::vector<uint8_t> fileChunk;
        for (const auto& chunk : std::vector<std::pair<const char*, std::vector<uint8_t>>>{
                 {"info", info}, {"segm", segm}, {"adlr", adlr}}) {
            fileChunk.insert(fileChunk.end(), chunk.first, chunk.first + 4);
            put64(fileChunk, chunk.second.size());
            fileChunk.insert(fileChunk.end(), chunk.second.begin(), chunk.second.end());
        }
        index.insert(index.end(), {'F', 'i', 'l', 'e'});
        put64(index, fileChunk.size());
        index.insert(index.end(), fileChunk.begin(), fileChunk.end());
    }

    const std::vector<uint8_t> compressed =
        options.compressIndex ? zlibDeflate(index) : std::vector<uint8_t>{};
    std::vector<uint8_t> block;
    if (!compressed.empty() && compressed.size() < index.size()) {
        block.push_back(0x01);  // zlib index
        put64(block, compressed.size());
        put64(block, index.size());
        block.insert(block.end(), compressed.begin(), compressed.end());
    } else {
        block.push_back(0x00);  // stored index
        put64(block, index.size());
        block.insert(block.end(), index.begin(), index.end());
    }

    const uint64_t indexOffset = archive.size();
    patch64(archive, 11, indexOffset);
    archive.insert(archive.end(), block.begin(), block.end());

    fs::path outPath = fsutil::path(utf8OutFile);
    std::error_code ec;
    if (outPath.has_parent_path()) fs::create_directories(outPath.parent_path(), ec);
    std::ofstream out(outPath, std::ios::binary | std::ios::trunc);
    if (!out) return {ErrorCode::Io, "cannot write " + utf8OutFile};
    out.write(reinterpret_cast<const char*>(archive.data()),
              static_cast<std::streamsize>(archive.size()));
    if (!out) return {ErrorCode::Io, "write failed: " + utf8OutFile};

    result.fileCount = items.size();
    result.archiveBytes = archive.size();
    return {};
}

}  // namespace oep
