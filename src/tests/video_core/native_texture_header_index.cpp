// SPDX-License-Identifier: GPL-3.0-or-later

#include <limits>
#include <catch2/catch_test_macros.hpp>

#include "video_core/textures/texture.h"
#include "video_core/texture_cache/format_lookup_table.h"

TEST_CASE("Legacy texture indices never decode as native header offsets",
          "[video_core][texture_header_index]") {
    using Tegra::Texture::TextureHeaderIndex;
    REQUIRE(TextureHeaderIndex(64, 63, false) == 64);
    REQUIRE(TextureHeaderIndex(2016, 63, false) == 2016);
    REQUIRE(TextureHeaderIndex(32, 0, false) == 32);
}

TEST_CASE("Native header offsets decode only when the shifted index is valid",
          "[video_core][texture_header_index]") {
    using Tegra::Texture::TextureHeaderIndex;
    REQUIRE(TextureHeaderIndex(64, 63, true) == 2);
    REQUIRE(TextureHeaderIndex(2016, 63, true) == 63);
    REQUIRE(TextureHeaderIndex(2048, 63, true) == 2048);
    REQUIRE(TextureHeaderIndex(65, 63, true) == 65);
    REQUIRE(TextureHeaderIndex(32, 0, true) == 32);
}

TEST_CASE("Resolved texture indices stay unchanged for both memory layouts",
          "[video_core][texture_header_index]") {
    using Tegra::Texture::TextureHeaderIndex;
    constexpr u32 maximum = std::numeric_limits<u32>::max();
    for (const bool native_tiling : {false, true}) {
        REQUIRE(TextureHeaderIndex(0, 0, native_tiling) == 0);
        REQUIRE(TextureHeaderIndex(32, 63, native_tiling) == 32);
        REQUIRE(TextureHeaderIndex(64, 64, native_tiling) == 64);
        REQUIRE(TextureHeaderIndex(maximum, maximum, native_tiling) == maximum);
        REQUIRE(TextureHeaderIndex(maximum, 63, native_tiling) == maximum);
    }
}

TEST_CASE("Uninitialized native TIC formats fall back to a deterministic shader format",
          "[video_core][texture_header_index]") {
    using Tegra::Texture::ComponentType;
    using Tegra::Texture::TextureFormat;
    using VideoCore::Surface::PixelFormat;
    for (const bool srgb : {false, true}) {
        for (const auto component : {ComponentType::UNORM, ComponentType::FLOAT}) {
            REQUIRE(VideoCommon::PixelFormatFromTextureInfo(
                        TextureFormat{}, component, component, component, component, srgb) ==
                    PixelFormat::A8B8G8R8_UNORM);
        }
    }
}

TEST_CASE("Native byte-offset TIC fallback never overrides valid direct indices",
          "[video_core][texture_header_index]") {
    using Tegra::Texture::AlternateTextureHeaderIndex;
    // If an in-range direct index 32 was invalid, try offset index 1.
    REQUIRE(AlternateTextureHeaderIndex(32, 32, 63, true) == 1);
    // Never infer a byte offset for legacy textures or non-aligned native handles.
    REQUIRE(AlternateTextureHeaderIndex(32, 32, 63, false) == 32);
    REQUIRE(AlternateTextureHeaderIndex(33, 33, 63, true) == 33);
    REQUIRE(AlternateTextureHeaderIndex(2048, 2048, 63, true) == 2048);
    // The usual out-of-range native handle has already been decoded; keep that index.
    REQUIRE(AlternateTextureHeaderIndex(64, 2, 63, true) == 2);
}
