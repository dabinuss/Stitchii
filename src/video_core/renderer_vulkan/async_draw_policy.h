// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <cstddef>

#include "common/common_types.h"

namespace Vulkan {

/// Whether a draw whose graphics pipeline is still building may be skipped (asynchronous
/// shaders) instead of waiting for the build.
/// @param native         The draw comes from a Switch 2 (native Turing macro) program.
/// @param depth_enabled  The depth test is on for the draw.
/// @param index_count    Index count of the draw.
/// @param vertex_count   Vertex count of the draw.
/// @param discard_native Opt native draws into the skip heuristic (EDEN_NX2_ASYNC_DISCARD=1).
///                        Default is false to preserve render passes and persistent GPU writes.
/// @return True when the draw may be skipped.
constexpr bool CanDiscardPendingDraw(bool native, bool depth_enabled, u32 index_count,
                                    u32 vertex_count, bool discard_native = false) {
    // Native draws can produce persistent resources, even with depth enabled. Preserve them
    // unless explicitly opted into the faster but visually unsafe skip policy.
    if (native && !discard_native) {
        return false;
    }
    // Preserve the legacy async-shader heuristic.
    return depth_enabled || (index_count > 6 && vertex_count > 6);
}

constexpr bool DefersShaderEmission(bool enabled, bool native, size_t pending, size_t capacity) {
    return enabled && native && pending < capacity;
}

} // namespace Vulkan
