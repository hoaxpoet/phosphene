// ICB.metal — GPU-driven indirect command buffer population kernel (Increment 3.5).
//
// `icb_populate_kernel` reads the current frame's FeatureVector and encodes draw
// commands into an indirect command buffer.  The CPU issues a single
// `executeCommandsInBuffer` call; the GPU decides how many draw slots are active
// based on live audio energy.
//
// FeatureVector and StemFeatures are defined in Common.metal — this file is
// concatenated into the same compilation unit by ShaderLibrary.

#include <metal_stdlib>
using namespace metal;

// MARK: - Argument Buffer Container

/// Argument buffer wrapping the indirect command buffer reference.
/// Bound at buffer(0) on the compute encoder; Metal's argument buffer
/// reflection maps `command_buffer cmdBuf [[id(0)]]` to the ICB handle.
struct ICBContainer {
    command_buffer cmdBuf [[id(0)]];
};

// MARK: - ICB Population Kernel

/// GPU-driven draw command encoder.
///
/// Each thread index corresponds to one command slot (0 … maxCommandCount-1).
/// Slot 0 is unconditionally active — it guarantees at least one draw call
/// even during silence.  Subsequent slots activate when cumulative bass + mid
/// + treble energy exceeds a linearly spaced per-slot threshold.
///
/// Active slots encode a full-screen triangle draw (3 vertices, 1 instance).
/// Inactive slots are reset so `executeCommandsInBuffer` silently skips them.
/// An atomic counter records the total active draw count (read back by tests).
///
/// - Parameters:
///   - icbContainer: Argument buffer containing the indirect command buffer.
///   - features:     Current frame audio feature vector.
///   - commandCount: Atomic uint for total active draw calls (zeroed by caller).
///   - tid:          Thread index = command slot index.
kernel void icb_populate_kernel(
    device ICBContainer &icbContainer [[buffer(0)]],
    constant FeatureVector &features  [[buffer(1)]],
    device atomic_uint *commandCount  [[buffer(2)]],
    uint tid                          [[thread_position_in_grid]]
) {
    // Cumulative energy across the three primary bands.
    float energy = features.bass + features.mid + features.treble;

    // Slot 0 always draws; subsequent slots need progressively higher energy.
    // Threshold spacing: 1/16 per slot (matches ICBConfiguration.maxCommandCount default).
    float threshold = float(tid) / 16.0;
    bool active = (tid == 0) || (energy > threshold);

    render_command cmd(icbContainer.cmdBuf, tid);
    if (active) {
        // Full-screen triangle: 3 vertices, 1 instance.
        // base_instance carries the slot index so per-layer shaders can read it
        // via [[base_instance]] if needed.
        cmd.draw_primitives(primitive_type::triangle, 0u, 3u, 1u, tid);
        atomic_fetch_add_explicit(commandCount, 1u, memory_order_relaxed);
    } else {
        // Mark this slot as a no-op.
        cmd.reset();
    }
}
