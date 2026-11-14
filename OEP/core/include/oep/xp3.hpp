// OEP core - KiriKiri XP3 archive reader.
//
// The layout implemented here mirrors krkrz src/core/common/base/XP3Archive.cpp
// (Wamsoft KiriKiri Z 1.2.0.3), which is the engine both target titles use:
//
//   header  : 11 byte magic "XP3\r\n \n\x1a\x8b\x67\x01" + uint64 index offset
//   index   : chained blocks, each block starts with one flag byte
//               bits 0..2 : 0 = raw, 1 = zlib
//               bit  7    : set => another uint64 index offset follows the block
//             zlib block: uint64 compressed size, uint64 uncompressed size,
//                         zlib stream
//             raw  block: uint64 size, raw bytes
//   index body: chunks; chunk = 4 byte name + uint64 size + payload
//               "File" chunks contain "info" (flags/sizes/UTF-16 name),
//               "segm" (N * 28 byte segment descriptors) and "adlr" (uint32
//               file hash used by extraction filters and by protected archives).
//
// KiriKiri archives produced by title-side protection tools store hashed file
// names (32 hex chars) and/or flag every entry as extraction-protected; the
// archive itself stays structurally readable.  This reader reports that state
// instead of pretending the archive is plain.
#pragma once

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

#include "oep/error.hpp"

namespace oep {

constexpr unsigned char kXp3Magic[11] = {'X', 'P', '3', 0x0d, 0x0a, 0x20,
                                         0x0a, 0x1a, 0x8b, 0x67, 0x01};

struct Xp3Segment {
    uint32_t flags = 0;
    uint64_t start = 0;    // absolute offset of the segment payload in the file
    uint64_t orgSize = 0;  // size after decompression
    uint64_t arcSize = 0;  // size stored in the file

    bool compressed() const { return (flags & 0x07u) == 0x01u; }
};

struct Xp3Entry {
    std::string name;  // UTF-8
    uint32_t flags = 0;
    uint64_t orgSize = 0;
    uint64_t arcSize = 0;
    uint32_t fileHash = 0;
    std::vector<Xp3Segment> segments;

    // TVP_XP3_FILE_PROTECTED: extraction-protection attribute.  It is advisory
    // (the engine still reads the data); OEP shows it but never hides it.
    bool extractionProtected() const { return (flags & 0x80000000u) != 0; }

    // True when the stored name looks like a protection-tool hash
    // (32 lowercase hex characters, no slash, no extension).
    bool hashedName() const { return isHashedStorageName(name); }

    static bool isHashedStorageName(const std::string& n);
};

class Xp3Archive {
public:
    Xp3Archive() = default;
    ~Xp3Archive();
    Xp3Archive(const Xp3Archive&) = delete;
    Xp3Archive& operator=(const Xp3Archive&) = delete;

    // Reads only the header and checks the magic; cheap detection helper.
    static bool hasXp3Magic(const std::string& utf8Path);

    // Opens the archive and parses the full index.  On success entries() is
    // sorted by name, like the engine does.
    Error open(const std::string& utf8Path);

    void close();
    bool isOpen() const { return file_ != nullptr; }

    const std::string& path() const { return path_; }
    uint64_t fileSize() const { return fileSize_; }
    const std::vector<Xp3Entry>& entries() const { return entries_; }
    const Xp3Entry* find(const std::string& name) const;

    // Reads one entry into memory.  Returns ErrorCode::Filtered when the data is
    // stored compressed but cannot be inflated (title-specific cipher/filter).
    Error readEntry(const Xp3Entry& entry, std::vector<uint8_t>& out) const;

    // Streams one entry to disk.
    Error extractEntry(const Xp3Entry& entry, const std::string& utf8OutPath) const;

    // Reads every entry and checks that the declared sizes match.  This is a
    // metadata/format check only, it never interprets the payload.
    Error verify(std::size_t& examined, std::vector<std::string>& failures) const;

    struct Stats {
        uint64_t totalEntries = 0;
        uint64_t totalOrgSize = 0;
        uint64_t totalArcSize = 0;
        uint64_t compressedEntries = 0;
        uint64_t protectedEntries = 0;
        uint64_t hashedNames = 0;
        uint64_t segments = 0;
    };
    Stats stats() const;

private:
    struct Chunk {
        std::string name;  // 4 chars
        uint64_t offset = 0;  // payload offset inside the index buffer
        uint64_t size = 0;
    };

    Error readAt(uint64_t offset, void* dst, std::size_t len) const;
    Error readIndexBlock(uint64_t offset, std::vector<uint8_t>& out, bool& more,
                         uint64_t& nextOffset) const;
    Error parseIndex(const std::vector<uint8_t>& index);
    static bool findChunk(const std::vector<uint8_t>& buf, uint64_t start,
                          uint64_t size, const char* name, Chunk& out);

    void* file_ = nullptr;  // std::ifstream*
    std::string path_;
    uint64_t fileSize_ = 0;
    std::vector<Xp3Entry> entries_;
};

}  // namespace oep
