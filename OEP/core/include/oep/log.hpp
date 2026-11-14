// OEP core - in-process log ring buffer.
//
// The same buffer feeds the diagnostics screen, the log export in Settings and
// the CLI.  Timestamps are local time with millisecond precision, every entry
// carries a severity and a category so a report can be filtered meaningfully.
#pragma once

#include <cstddef>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

namespace oep {

enum class LogLevel { Debug = 0, Info = 1, Warning = 2, Error = 3 };

const char* logLevelName(LogLevel level);      // "DEBUG" / ...
const char* logLevelJapanese(LogLevel level);  // "デバッグ" / ...

struct LogEntry {
    std::string timestamp;  // "2026-11-14T08:31:22.517"
    LogLevel level = LogLevel::Info;
    std::string category;
    std::string message;

    std::string toLine() const;
};

class Logger {
public:
    static Logger& shared();

    void setMinimumLevel(LogLevel level);
    LogLevel minimumLevel() const;

    void log(LogLevel level, std::string category, std::string message);
    void debug(const std::string& category, const std::string& message);
    void info(const std::string& category, const std::string& message);
    void warning(const std::string& category, const std::string& message);
    void error(const std::string& category, const std::string& message);

    std::vector<LogEntry> snapshot() const;
    std::size_t size() const;
    void clear();
    std::string exportText() const;

    void setCapacity(std::size_t capacity);

private:
    Logger() = default;

    mutable std::mutex mutex_;
    std::deque<LogEntry> entries_;
    std::size_t capacity_ = 4000;
    LogLevel minimum_ = LogLevel::Debug;
};

}  // namespace oep
