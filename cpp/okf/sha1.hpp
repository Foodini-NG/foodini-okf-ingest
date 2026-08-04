// Minimal SHA-1 (FIPS 180-1), header-only, no dependencies — vendored so the
// C++ binding needs no OpenSSL. Correctness is locked by the conformance
// fixture (content_hashes in expected/store.json) plus known-vector tests in
// the checker.
#pragma once

#include <cstdint>
#include <cstring>
#include <string>

namespace okf::detail {

class Sha1 {
public:
    Sha1() { reset(); }

    void update(const void* data, std::size_t len) {
        const auto* p = static_cast<const std::uint8_t*>(data);
        total_ += len;
        while (len > 0) {
            std::size_t take = 64 - buf_len_;
            if (take > len) take = len;
            std::memcpy(buf_ + buf_len_, p, take);
            buf_len_ += take;
            p += take;
            len -= take;
            if (buf_len_ == 64) {
                process_block(buf_);
                buf_len_ = 0;
            }
        }
    }

    std::string hex_digest() {
        std::uint64_t bits = total_ * 8;
        std::uint8_t pad = 0x80;
        update(&pad, 1);
        std::uint8_t zero = 0x00;
        while (buf_len_ != 56) update(&zero, 1);
        std::uint8_t len_be[8];
        for (int i = 0; i < 8; ++i) len_be[i] = static_cast<std::uint8_t>(bits >> (56 - 8 * i));
        update(len_be, 8);
        static const char* kHex = "0123456789abcdef";
        std::string out;
        out.reserve(40);
        for (std::uint32_t word : h_) {
            for (int i = 28; i >= 0; i -= 4) out.push_back(kHex[(word >> i) & 0xF]);
        }
        return out;
    }

private:
    void reset() {
        h_[0] = 0x67452301u; h_[1] = 0xEFCDAB89u; h_[2] = 0x98BADCFEu;
        h_[3] = 0x10325476u; h_[4] = 0xC3D2E1F0u;
        buf_len_ = 0;
        total_ = 0;
    }

    static std::uint32_t rol(std::uint32_t v, int n) { return (v << n) | (v >> (32 - n)); }

    void process_block(const std::uint8_t* block) {
        std::uint32_t w[80];
        for (int i = 0; i < 16; ++i) {
            w[i] = (std::uint32_t{block[4 * i]} << 24) | (std::uint32_t{block[4 * i + 1]} << 16) |
                   (std::uint32_t{block[4 * i + 2]} << 8) | std::uint32_t{block[4 * i + 3]};
        }
        for (int i = 16; i < 80; ++i) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        std::uint32_t a = h_[0], b = h_[1], c = h_[2], d = h_[3], e = h_[4];
        for (int i = 0; i < 80; ++i) {
            std::uint32_t f, k;
            if (i < 20) { f = (b & c) | (~b & d); k = 0x5A827999u; }
            else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1u; }
            else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDCu; }
            else { f = b ^ c ^ d; k = 0xCA62C1D6u; }
            std::uint32_t t = rol(a, 5) + f + e + k + w[i];
            e = d; d = c; c = rol(b, 30); b = a; a = t;
        }
        h_[0] += a; h_[1] += b; h_[2] += c; h_[3] += d; h_[4] += e;
    }

    std::uint32_t h_[5];
    std::uint8_t buf_[64];
    std::size_t buf_len_ = 0;
    std::uint64_t total_ = 0;
};

inline std::string sha1_hex(const std::string& data) {
    Sha1 s;
    s.update(data.data(), data.size());
    return s.hex_digest();
}

}  // namespace okf::detail
