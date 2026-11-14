#include "oep/platform.hpp"

#include <cstdlib>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#endif

namespace oep {

std::string utf8FromWide(const std::wstring& wide) {
#if defined(_WIN32)
    if (wide.empty()) return {};
    const int len = ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                          static_cast<int>(wide.size()), nullptr, 0,
                                          nullptr, nullptr);
    std::string out(static_cast<std::size_t>(len), '\0');
    if (len > 0)
        ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                              &out[0], len, nullptr, nullptr);
    return out;
#else
    std::string out;
    out.assign(wide.begin(), wide.end());
    return out;
#endif
}

std::wstring wideFromUtf8(const std::string& utf8) {
#if defined(_WIN32)
    if (utf8.empty()) return {};
    const int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                          static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring out(static_cast<std::size_t>(len), L'\0');
    if (len > 0)
        ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                              &out[0], len);
    return out;
#else
    std::wstring out;
    out.assign(utf8.begin(), utf8.end());
    return out;
#endif
}

std::vector<std::string> processArguments(int argc, char** argv) {
    std::vector<std::string> args;
#if defined(_WIN32)
    int wargc = 0;
    wchar_t** wargv = ::CommandLineToArgvW(::GetCommandLineW(), &wargc);
    if (wargv) {
        for (int i = 0; i < wargc; ++i) args.push_back(utf8FromWide(wargv[i]));
        ::LocalFree(wargv);
        return args;
    }
#endif
    for (int i = 0; i < argc; ++i) args.push_back(argv[i]);
    return args;
}

}  // namespace oep
