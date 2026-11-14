// OEP core - minimal error/result plumbing shared by all modules.
// Portable C++17, no platform dependencies.
#pragma once

#include <string>
#include <utility>

namespace oep {

enum class ErrorCode {
    None = 0,
    Io,
    NotXp3,
    Corrupt,
    Unsupported,
    Filtered,  // data is present but needs a per-title extraction filter/cipher
    NotFound,
};

struct Error {
    ErrorCode code = ErrorCode::None;
    std::string message;

    Error() = default;
    Error(ErrorCode c, std::string m) : code(c), message(std::move(m)) {}
    static Error none() { return {}; }

    bool ok() const { return code == ErrorCode::None; }
    explicit operator bool() const { return ok(); }

    std::string describe() const {
        if (ok()) return "ok";
        static const char* names[] = {"None", "Io", "NotXp3", "Corrupt",
                                      "Unsupported", "Filtered", "NotFound"};
        int i = static_cast<int>(code);
        std::string n = (i >= 0 && i <= 6) ? names[i] : "Unknown";
        return n + ": " + message;
    }
};

}  // namespace oep
