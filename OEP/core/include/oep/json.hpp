// OEP core - tiny JSON writer (write-only; the app persists its library with
// Codable on the Swift side, and this writer produces scan/diagnostic reports).
#pragma once

#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>
#include <type_traits>
#include <vector>

namespace oep {

class JsonWriter {
public:
    explicit JsonWriter(bool pretty = true) : pretty_(pretty) {}

    JsonWriter& beginObject() {
        beginItem();
        out_ << '{';
        push(true);
        return *this;
    }
    JsonWriter& endObject() { return end('}'); }
    JsonWriter& beginArray() {
        beginItem();
        out_ << '[';
        push(false);
        return *this;
    }
    JsonWriter& endArray() { return end(']'); }

    JsonWriter& key(const std::string& k) {
        beginItem();
        writeString(k);
        out_ << (pretty_ ? ": " : ":");
        afterKey_ = true;
        return *this;
    }

    JsonWriter& value(const std::string& v) {
        beginItem();
        writeString(v);
        return *this;
    }
    JsonWriter& value(const char* v) { return value(std::string(v)); }
    JsonWriter& value(bool v) {
        beginItem();
        out_ << (v ? "true" : "false");
        return *this;
    }
    JsonWriter& value(double v) {
        beginItem();
        std::ostringstream tmp;
        tmp << std::setprecision(10) << v;
        out_ << tmp.str();
        return *this;
    }
    template <typename T,
              typename = typename std::enable_if<
                  std::is_integral<T>::value && !std::is_same<T, bool>::value>::type>
    JsonWriter& value(T v) {
        beginItem();
        out_ << static_cast<long long>(v);
        return *this;
    }
    JsonWriter& value(std::nullptr_t) {
        beginItem();
        out_ << "null";
        return *this;
    }

    JsonWriter& field(const std::string& k, const std::string& v) { return key(k).value(v); }
    JsonWriter& field(const std::string& k, const char* v) { return key(k).value(v); }
    JsonWriter& field(const std::string& k, bool v) { return key(k).value(v); }
    template <typename T,
              typename = typename std::enable_if<
                  std::is_integral<T>::value && !std::is_same<T, bool>::value>::type>
    JsonWriter& field(const std::string& k, T v) {
        return key(k).value(v);
    }

    JsonWriter& fieldArray(const std::string& k, const std::vector<std::string>& v) {
        key(k).beginArray();
        for (const auto& s : v) value(s);
        return endArray();
    }

    std::string str() const { return out_.str(); }

private:
    JsonWriter& end(char c) {
        const bool empty = firstStack_.empty() || firstStack_.back();
        if (!firstStack_.empty()) firstStack_.pop_back();
        if (!objectStack_.empty()) objectStack_.pop_back();
        if (pretty_ && !empty) {
            out_ << '\n';
            indent(objectStack_.size());
        }
        out_ << c;
        return *this;
    }

    void push(bool isObject) {
        objectStack_.push_back(isObject);
        firstStack_.push_back(true);
        afterKey_ = false;
    }

    void beginItem() {
        if (afterKey_) {
            afterKey_ = false;
            return;
        }
        if (firstStack_.empty()) return;  // top-level scalar
        if (!firstStack_.back()) out_ << ',';
        firstStack_.back() = false;
        if (pretty_) {
            out_ << '\n';
            indent(objectStack_.size());
        }
    }

    void indent(std::size_t depth) {
        for (std::size_t i = 0; i < depth; ++i) out_ << "  ";
    }

    void writeString(const std::string& s) {
        out_ << '"';
        for (unsigned char c : s) {
            switch (c) {
                case '"': out_ << "\\\""; break;
                case '\\': out_ << "\\\\"; break;
                case '\n': out_ << "\\n"; break;
                case '\r': out_ << "\\r"; break;
                case '\t': out_ << "\\t"; break;
                case '\b': out_ << "\\b"; break;
                case '\f': out_ << "\\f"; break;
                default:
                    if (c < 0x20) {
                        out_ << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                             << static_cast<int>(c) << std::dec << std::setfill(' ');
                    } else {
                        out_ << static_cast<char>(c);
                    }
            }
        }
        out_ << '"';
    }

    bool pretty_;
    bool afterKey_ = false;
    std::ostringstream out_;
    std::vector<bool> objectStack_;
    std::vector<bool> firstStack_;
};

}  // namespace oep
