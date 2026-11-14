// OEP core - the few platform shims the tools need.
//
// On Windows the CRT hands `char** argv` in the active ANSI code page, which
// cannot represent Japanese folder names.  The helpers below recover the real
// UTF-16 command line and convert it to UTF-8 so the rest of the code only ever
// deals with UTF-8 strings.
#pragma once

#include <string>
#include <vector>

namespace oep {

std::vector<std::string> processArguments(int argc, char** argv);

// UTF-16 -> UTF-8 and back (identity on non-Windows platforms).
std::string utf8FromWide(const std::wstring& wide);
std::wstring wideFromUtf8(const std::string& utf8);

}  // namespace oep
