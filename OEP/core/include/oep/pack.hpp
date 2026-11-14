// OEP core - XP3 writer.
//
// A deliberately small packer: one raw segment per file, names stored verbatim,
// and a zlib-compressed index (the layout krkrz's own xp3 tool produces).  It
// exists so self-made test data can be validated end to end, and so a user can
// repack their own folder into data.xp3 if a title needs an archive.
#pragma once

#include <string>

#include "oep/error.hpp"

namespace oep {

struct PackOptions {
    // Compress the index when that makes it smaller (matches the engine default).
    bool compressIndex = true;
    // Skip files whose name starts with '.' and .xp3 files.
    bool skipArchives = true;
};

struct PackResult {
    uint64_t fileCount = 0;
    uint64_t payloadBytes = 0;
    uint64_t archiveBytes = 0;
};

Error packFolderToXp3(const std::string& utf8Folder, const std::string& utf8OutFile,
                      const PackOptions& options, PackResult& result);

}  // namespace oep
