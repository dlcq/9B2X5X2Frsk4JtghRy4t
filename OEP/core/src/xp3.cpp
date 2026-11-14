#include "oep/xp3.hpp"

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <memory>

#include "fsutil.hpp"
#include "miniz.h"

namespace oep {
namespace {

namespace fs = std::filesystem;

std::ifstream* asIn(void* p) { return static_cast<std::ifstream*>(p); }

fs::path toPath(const std::string& utf8) { return fsutil::path(utf8); }

using fsutil::utf8;

uint16_t rd16(const uint8_t* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }
uint32_t rd32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}
uint64_t rd64(const uint8_t* p) {
    return static_cast<uint64_t>(rd32(p)) | (static_cast<uint64_t>(rd32(p + 4)) << 32);
}

// BMP only (the engine itself stores ttstr names as UTF-16 code units).
std::string utf16leToUtf8(const uint8_t* p, std::size_t units) {
    std::string out;
    out.reserve(units);
    std::size_t i = 0;
    while (i < units) {
        uint32_t cp = rd16(p + i * 2);
        ++i;
        if (cp >= 0xD800 && cp <= 0xDBFF && i < units) {
            uint32_t lo = rd16(p + i * 2);
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                ++i;
            }
        }
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    return out;
}

}  // namespace

bool Xp3Entry::isHashedStorageName(const std::string& n) {
    if (n.size() != 32) return false;
    for (char c : n) {
        const bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                         (c >= 'A' && c <= 'F');
        if (!hex) return false;
    }
    return true;
}

Xp3Archive::~Xp3Archive() { close(); }

void Xp3Archive::close() {
    if (file_) {
        delete asIn(file_);
        file_ = nullptr;
    }
    entries_.clear();
    path_.clear();
    fileSize_ = 0;
}

bool Xp3Archive::hasXp3Magic(const std::string& utf8Path) {
    std::ifstream f(toPath(utf8Path), std::ios::binary);
    if (!f) return false;
    unsigned char head[11] = {0};
    f.read(reinterpret_cast<char*>(head), 11);
    return f.gcount() == 11 && std::memcmp(head, kXp3Magic, 11) == 0;
}

Error Xp3Archive::readAt(uint64_t offset, void* dst, std::size_t len) const {
    auto* in = asIn(file_);
    if (!in) return {ErrorCode::Io, "archive is not open"};
    in->clear();
    in->seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!*in) return {ErrorCode::Io, "seek failed"};
    in->read(reinterpret_cast<char*>(dst), static_cast<std::streamsize>(len));
    if (static_cast<std::size_t>(in->gcount()) != len)
        return {ErrorCode::Corrupt, "short read at offset " + std::to_string(offset)};
    return {};
}

Error Xp3Archive::readIndexBlock(uint64_t offset, std::vector<uint8_t>& out,
                                 bool& more, uint64_t& nextOffset) const {
    out.clear();
    more = false;
    nextOffset = 0;
    if (offset >= fileSize_)
        return {ErrorCode::Corrupt, "index offset past end of file"};

    uint8_t flag = 0;
    Error e = readAt(offset, &flag, 1);
    if (!e) return e;

    uint64_t cursor = offset + 1;
    const unsigned method = flag & 0x07u;

    if (method == 0x01u) {  // zlib
        uint8_t sizes[16];
        e = readAt(cursor, sizes, 16);
        if (!e) return e;
        cursor += 16;
        const uint64_t compressed = rd64(sizes);
        const uint64_t raw = rd64(sizes + 8);
        if (compressed > fileSize_ || raw > (1ull << 32))
            return {ErrorCode::Corrupt, "implausible compressed index size"};
        std::vector<uint8_t> src(static_cast<std::size_t>(compressed));
        if (compressed) {
            e = readAt(cursor, src.data(), src.size());
            if (!e) return e;
        }
        cursor += compressed;
        out.resize(static_cast<std::size_t>(raw));
        if (raw) {
            mz_ulong dstLen = static_cast<mz_ulong>(out.size());
            const int rc = mz_uncompress(out.data(), &dstLen, src.data(),
                                         static_cast<mz_ulong>(src.size()));
            if (rc != MZ_OK || dstLen != out.size())
                return {ErrorCode::Filtered,
                        "index stream does not inflate (title-specific cipher?)"};
        }
    } else if (method == 0x00u) {  // stored
        uint8_t size[8];
        e = readAt(cursor, size, 8);
        if (!e) return e;
        cursor += 8;
        const uint64_t raw = rd64(size);
        if (raw > (1ull << 32))
            return {ErrorCode::Corrupt, "implausible index size"};
        out.resize(static_cast<std::size_t>(raw));
        if (raw) {
            e = readAt(cursor, out.data(), out.size());
            if (!e) return e;
        }
        cursor += raw;
    } else {
        return {ErrorCode::Unsupported,
                "unknown index encoding " + std::to_string(method)};
    }

    if (flag & 0x80u) {
        more = true;
        uint8_t n[8];
        e = readAt(cursor, n, 8);
        if (!e) return e;
        nextOffset = rd64(n);
    }
    return {};
}

bool Xp3Archive::findChunk(const std::vector<uint8_t>& buf, uint64_t start,
                           uint64_t size, const char* name, Chunk& out) {
    uint64_t pos = 0;
    uint64_t off = start;
    while (pos + 12 <= size && off + 12 <= buf.size()) {
        const bool match = std::memcmp(buf.data() + off, name, 4) == 0;
        const uint64_t len = rd64(buf.data() + off + 4);
        off += 12;
        if (len > size || off + len > buf.size()) return false;
        if (match) {
            out.name.assign(name, 4);
            out.offset = off;
            out.size = len;
            return true;
        }
        off += len;
        pos += 12 + len;
    }
    return false;
}

Error Xp3Archive::parseIndex(const std::vector<uint8_t>& index) {
    uint64_t fileStart = 0;
    uint64_t fileSize = index.size();
    Chunk file;

    while (findChunk(index, fileStart, fileSize, "File", file)) {
        Xp3Entry entry;

        Chunk info;
        if (!findChunk(index, file.offset, file.size, "info", info))
            return {ErrorCode::Corrupt, "File chunk without info chunk"};
        if (info.size < 22) return {ErrorCode::Corrupt, "info chunk too small"};
        entry.flags = rd32(index.data() + info.offset);
        entry.orgSize = rd64(index.data() + info.offset + 4);
        entry.arcSize = rd64(index.data() + info.offset + 12);
        const uint16_t nameUnits = rd16(index.data() + info.offset + 20);
        if (info.offset + 22 + static_cast<uint64_t>(nameUnits) * 2 > index.size())
            return {ErrorCode::Corrupt, "file name runs past index"};
        entry.name = utf16leToUtf8(index.data() + info.offset + 22, nameUnits);

        Chunk segm;
        if (!findChunk(index, file.offset, file.size, "segm", segm))
            return {ErrorCode::Corrupt, "File chunk without segm chunk"};
        const uint64_t count = segm.size / 28;
        entry.segments.reserve(static_cast<std::size_t>(count));
        for (uint64_t i = 0; i < count; ++i) {
            const uint8_t* p = index.data() + segm.offset + i * 28;
            Xp3Segment s;
            s.flags = rd32(p);
            s.start = rd64(p + 4);
            s.orgSize = rd64(p + 12);
            s.arcSize = rd64(p + 20);
            entry.segments.push_back(s);
        }

        Chunk adlr;
        if (findChunk(index, file.offset, file.size, "adlr", adlr) && adlr.size >= 4)
            entry.fileHash = rd32(index.data() + adlr.offset);

        entries_.push_back(std::move(entry));

        fileStart = file.offset + file.size;
        fileSize = index.size() - fileStart;
    }
    return {};
}

Error Xp3Archive::open(const std::string& utf8Path) {
    close();
    path_ = utf8Path;

    auto* in = new std::ifstream(toPath(utf8Path), std::ios::binary);
    if (!*in) {
        delete in;
        return {ErrorCode::Io, "cannot open " + utf8Path};
    }
    file_ = in;

    in->seekg(0, std::ios::end);
    fileSize_ = static_cast<uint64_t>(in->tellg());
    if (fileSize_ < 19) return {ErrorCode::NotXp3, "file too small"};

    uint8_t header[19];
    Error e = readAt(0, header, sizeof(header));
    if (!e) return e;
    if (std::memcmp(header, kXp3Magic, 11) != 0)
        return {ErrorCode::NotXp3, "XP3 magic not found"};

    uint64_t indexOffset = rd64(header + 11);
    int guard = 0;
    while (true) {
        if (++guard > 4096)
            return {ErrorCode::Corrupt, "index chain too long"};
        std::vector<uint8_t> block;
        bool more = false;
        uint64_t next = 0;
        e = readIndexBlock(indexOffset, block, more, next);
        if (!e) return e;
        if (!block.empty()) {
            e = parseIndex(block);
            if (!e) return e;
        }
        if (!more) break;
        indexOffset = next;
    }

    // The engine keeps archives sorted by name; mirror that so lookups behave
    // the same way and callers can binary search.
    std::stable_sort(entries_.begin(), entries_.end(),
                     [](const Xp3Entry& a, const Xp3Entry& b) { return a.name < b.name; });
    return {};
}

const Xp3Entry* Xp3Archive::find(const std::string& name) const {
    auto it = std::lower_bound(entries_.begin(), entries_.end(), name,
                               [](const Xp3Entry& e, const std::string& v) {
                                   return e.name < v;
                               });
    if (it != entries_.end() && it->name == name) return &*it;
    return nullptr;
}

Error Xp3Archive::readEntry(const Xp3Entry& entry, std::vector<uint8_t>& out) const {
    out.clear();
    out.reserve(static_cast<std::size_t>(entry.orgSize));
    for (const auto& s : entry.segments) {
        if (s.arcSize == 0) continue;
        if (s.arcSize > fileSize_ || s.start > fileSize_ - s.arcSize)
            return {ErrorCode::Corrupt, "segment outside file"};
        if (!s.compressed()) {
            if (s.arcSize > (1ull << 31))
                return {ErrorCode::Unsupported, "segment too large to read into memory"};
            const std::size_t base = out.size();
            out.resize(base + static_cast<std::size_t>(s.arcSize));
            Error e = readAt(s.start, out.data() + base, static_cast<std::size_t>(s.arcSize));
            if (!e) return e;
            continue;
        }

        if (s.arcSize > (1ull << 31) || s.orgSize > (1ull << 31))
            return {ErrorCode::Unsupported, "compressed segment too large"};
        std::vector<uint8_t> src(static_cast<std::size_t>(s.arcSize));
        Error e = readAt(s.start, src.data(), src.size());
        if (!e) return e;
        const std::size_t base = out.size();
        out.resize(base + static_cast<std::size_t>(s.orgSize));
        mz_ulong dstLen = static_cast<mz_ulong>(s.orgSize);
        const int rc = mz_uncompress(out.data() + base, &dstLen, src.data(),
                                     static_cast<mz_ulong>(src.size()));
        if (rc != MZ_OK || dstLen != s.orgSize) {
            out.resize(base);
            return {ErrorCode::Filtered,
                    "segment does not inflate (archive needs a title filter?) entry=" +
                        entry.name};
        }
    }
    return {};
}

Error Xp3Archive::extractEntry(const Xp3Entry& entry,
                               const std::string& utf8OutPath) const {
    std::vector<uint8_t> data;
    Error e = readEntry(entry, data);
    if (!e) return e;

    fs::path outPath = toPath(utf8OutPath);
    std::error_code ec;
    if (outPath.has_parent_path()) fs::create_directories(outPath.parent_path(), ec);
    std::ofstream os(outPath, std::ios::binary | std::ios::trunc);
    if (!os) return {ErrorCode::Io, "cannot create " + utf8OutPath};
    os.write(reinterpret_cast<const char*>(data.data()),
             static_cast<std::streamsize>(data.size()));
    if (!os) return {ErrorCode::Io, "write failed for " + utf8OutPath};
    return {};
}

Error Xp3Archive::verify(std::size_t& examined,
                         std::vector<std::string>& failures) const {
    examined = 0;
    failures.clear();
    for (const auto& e : entries_) {
        ++examined;
        std::vector<uint8_t> data;
        Error err = readEntry(e, data);
        if (err.ok() && data.size() != e.orgSize) {
            err = {ErrorCode::Corrupt,
                   "size mismatch: " + std::to_string(data.size()) + " != " +
                       std::to_string(e.orgSize)};
        }
        if (err.ok()) continue;
        if (err.code == ErrorCode::Filtered) {
            failures.push_back(e.name + " [filtered/cipher]");
        } else {
            failures.push_back(e.name + " [" + err.describe() + "]");
        }
    }
    return failures.empty() ? Error{} : Error{ErrorCode::Corrupt, "verification failures"};
}

Xp3Archive::Stats Xp3Archive::stats() const {
    Stats s;
    s.totalEntries = entries_.size();
    for (const auto& e : entries_) {
        s.totalOrgSize += e.orgSize;
        s.totalArcSize += e.arcSize;
        if (e.extractionProtected()) ++s.protectedEntries;
        if (e.hashedName()) ++s.hashedNames;
        s.segments += e.segments.size();
        for (const auto& seg : e.segments) {
            if (seg.compressed()) {
                ++s.compressedEntries;
                break;
            }
        }
    }
    return s;
}

}  // namespace oep
