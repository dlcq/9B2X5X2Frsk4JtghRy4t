// OEP core - internal filesystem/text helpers (not part of the public API).
#pragma once

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace oep {
namespace fsutil {

namespace fs = std::filesystem;

// UTF-8 <-> std::filesystem::path.  Windows paths are UTF-16, so the conversion
// is explicit instead of relying on the (C++20) u8 overloads.
inline fs::path path(const std::string& text) {
#if defined(_WIN32)
    if (text.empty()) return fs::path();
    const int len = ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), (int)text.size(), nullptr, 0);
    std::wstring wide(static_cast<size_t>(len), L'\0');
    if (len > 0)
        ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), (int)text.size(), &wide[0], len);
    return fs::path(wide);
#else
    return fs::path(text);
#endif
}

inline std::string utf8(const fs::path& p) {
#if defined(_WIN32)
    const std::wstring wide = p.wstring();
    if (wide.empty()) return {};
    const int len = ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(),
                                          nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<size_t>(len), '\0');
    if (len > 0)
        ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(), &out[0], len,
                              nullptr, nullptr);
    return out;
#else
    return p.string();
#endif
}

inline bool isDirectory(const std::string& utf8Path) {
    std::error_code ec;
    return fs::is_directory(path(utf8Path), ec);
}

inline bool isRegularFile(const std::string& utf8Path) {
    std::error_code ec;
    return fs::is_regular_file(path(utf8Path), ec);
}

inline bool exists(const std::string& utf8Path) {
    std::error_code ec;
    return fs::exists(path(utf8Path), ec);
}

inline uint64_t fileSize(const std::string& utf8Path) {
    std::error_code ec;
    const auto s = fs::file_size(path(utf8Path), ec);
    return ec ? 0 : static_cast<uint64_t>(s);
}

inline std::string join(const std::string& a, const std::string& b) {
    if (a.empty()) return b;
    if (!a.empty() && (a.back() == '/' || a.back() == '\\')) return a + b;
    return a + "/" + b;
}

inline std::vector<std::string> listDirectory(const std::string& utf8Dir) {
    std::vector<std::string> out;
    std::error_code ec;
    fs::directory_iterator it(path(utf8Dir), ec), end;
    if (ec) return out;
    for (; it != end; it.increment(ec)) {
        if (ec) break;
        out.push_back(utf8(it->path().filename()));
    }
    std::sort(out.begin(), out.end());
    return out;
}

inline std::string fileName(const std::string& utf8Path) {
    return utf8(path(utf8Path).filename());
}

inline std::string stem(const std::string& utf8Path) {
    return utf8(path(utf8Path).stem());
}

inline std::string extensionLower(const std::string& utf8Path) {
    std::string e = utf8(path(utf8Path).extension());
    std::transform(e.begin(), e.end(), e.begin(),
                   [](unsigned char c) { return static_cast<char>(::tolower(c)); });
    return e;
}

inline std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(::tolower(c)); });
    return s;
}

inline bool endsWithNoCase(const std::string& s, const std::string& suffix) {
    if (s.size() < suffix.size()) return false;
    return lower(s.substr(s.size() - suffix.size())) == lower(suffix);
}

inline bool readWholeFile(const std::string& utf8Path, std::vector<uint8_t>& out,
                          uint64_t maxBytes = 64ull * 1024 * 1024) {
    fs::path p = path(utf8Path);
    std::error_code ec;
    const uint64_t size = fs::file_size(p, ec);
    if (ec || size > maxBytes) return false;
    std::ifstream f(p, std::ios::binary);
    if (!f) return false;
    out.resize(static_cast<std::size_t>(size));
    if (size) f.read(reinterpret_cast<char*>(out.data()), static_cast<std::streamsize>(size));
    return static_cast<uint64_t>(f.gcount()) == size || size == 0;
}

inline bool readPrefix(const std::string& utf8Path, std::vector<uint8_t>& out,
                       std::size_t bytes) {
    std::ifstream f(path(utf8Path), std::ios::binary);
    if (!f) return false;
    out.resize(bytes);
    f.read(reinterpret_cast<char*>(out.data()), static_cast<std::streamsize>(bytes));
    out.resize(static_cast<std::size_t>(f.gcount()));
    return true;
}

inline std::string ascii(const std::vector<uint8_t>& v, std::size_t from = 0,
                         std::size_t len = std::string::npos) {
    if (from >= v.size()) return {};
    const std::size_t n = (len == std::string::npos) ? v.size() - from : len;
    return std::string(reinterpret_cast<const char*>(v.data()) + from,
                       std::min(n, v.size() - from));
}

inline void appendUtf8(std::string& out, uint32_t cp) {
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

// Decodes UTF-16 with a BOM/even-byte heuristic (KiriKiri console logs are
// UTF-16LE on Windows).
inline std::string decodeUtf16Auto(const std::vector<uint8_t>& bytes) {
    std::size_t start = 0;
    bool be = false;
    if (bytes.size() >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        start = 2;
    } else if (bytes.size() >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        start = 2;
        be = true;
    } else if (bytes.size() >= 4) {
        std::size_t zerosEven = 0, zerosOdd = 0;
        for (std::size_t i = 0; i + 1 < bytes.size() && i < 4096; i += 2) {
            if (bytes[i] == 0) ++zerosEven;
            if (bytes[i + 1] == 0) ++zerosOdd;
        }
        be = zerosEven > zerosOdd * 2;
    }

    std::string out;
    out.reserve((bytes.size() - start) / 2);
    for (std::size_t i = start; i + 1 < bytes.size(); i += 2) {
        uint32_t u = be ? (static_cast<uint32_t>(bytes[i]) << 8) | bytes[i + 1]
                        : (static_cast<uint32_t>(bytes[i + 1]) << 8) | bytes[i];
        if (u == 0 && i + 3 < bytes.size()) {
            // NUL padding inside UTF-16 text terminates the record
            continue;
        }
        appendUtf8(out, u);
    }
    return out;
}

}  // namespace fsutil
}  // namespace oep
