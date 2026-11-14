#include "oep/log.hpp"

#include <chrono>
#include <cstdio>
#include <ctime>
#include <sstream>

namespace oep {
namespace {

std::string nowStamp() {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto secs = time_point_cast<seconds>(now);
    const auto ms = duration_cast<milliseconds>(now - secs).count();
    const std::time_t t = system_clock::to_time_t(secs);

    std::tm tm{};
#if defined(_WIN32)
    localtime_s(&tm, &t);
#else
    localtime_r(&t, &tm);
#endif
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d.%03d",
                  tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min,
                  tm.tm_sec, static_cast<int>(ms));
    return buf;
}

}  // namespace

const char* logLevelName(LogLevel level) {
    switch (level) {
        case LogLevel::Debug: return "DEBUG";
        case LogLevel::Info: return "INFO";
        case LogLevel::Warning: return "WARNING";
        case LogLevel::Error: return "ERROR";
    }
    return "INFO";
}

const char* logLevelJapanese(LogLevel level) {
    switch (level) {
        case LogLevel::Debug: return "デバッグ";
        case LogLevel::Info: return "情報";
        case LogLevel::Warning: return "警告";
        case LogLevel::Error: return "エラー";
    }
    return "情報";
}

std::string LogEntry::toLine() const {
    std::ostringstream oss;
    oss << timestamp << " [" << logLevelName(level) << "] " << category << ": " << message;
    return oss.str();
}

Logger& Logger::shared() {
    static Logger instance;
    return instance;
}

void Logger::setMinimumLevel(LogLevel level) {
    std::lock_guard<std::mutex> lock(mutex_);
    minimum_ = level;
}

LogLevel Logger::minimumLevel() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return minimum_;
}

void Logger::setCapacity(std::size_t capacity) {
    std::lock_guard<std::mutex> lock(mutex_);
    capacity_ = capacity ? capacity : 1;
    while (entries_.size() > capacity_) entries_.pop_front();
}

void Logger::log(LogLevel level, std::string category, std::string message) {
    if (static_cast<int>(level) < static_cast<int>(minimumLevel())) return;
    LogEntry entry;
    entry.timestamp = nowStamp();
    entry.level = level;
    entry.category = std::move(category);
    entry.message = std::move(message);

    std::lock_guard<std::mutex> lock(mutex_);
    entries_.push_back(std::move(entry));
    while (entries_.size() > capacity_) entries_.pop_front();
}

void Logger::debug(const std::string& c, const std::string& m) { log(LogLevel::Debug, c, m); }
void Logger::info(const std::string& c, const std::string& m) { log(LogLevel::Info, c, m); }
void Logger::warning(const std::string& c, const std::string& m) { log(LogLevel::Warning, c, m); }
void Logger::error(const std::string& c, const std::string& m) { log(LogLevel::Error, c, m); }

std::vector<LogEntry> Logger::snapshot() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return std::vector<LogEntry>(entries_.begin(), entries_.end());
}

std::size_t Logger::size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return entries_.size();
}

void Logger::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    entries_.clear();
}

std::string Logger::exportText() const {
    std::string out;
    for (const auto& e : snapshot()) {
        out += e.toLine();
        out += '\n';
    }
    return out;
}

}  // namespace oep
