# BUG-085 — main thread hung in CAMetalLayer.nextDrawable (2026-08-04)

Captured with `sample <pid> 5` against a LIVE frozen app (Matt kept it open rather than
force-quitting). This is the artifact BUG-060 and the Volumetric Lithograph "~3.7 min crash"
have both been waiting for since they were filed.

**100 % of 4250 samples are on the single stack below, at 0.0 % CPU.** Not a spin, not a GPU
hang: every other thread in the process is idle (audio, caulk, CVDisplayLink, all in normal
waits). The main thread asks for a drawable, blocks, and never returns to the run loop —
which is why the window is unresponsive rather than merely not animating.

Session `2026-08-04T17-49-50Z`, preset Witchlight, track Hummer. 12,911 frames ≈ **3.6 min**
before the stop. Frame timings were steady right up to the last frame (frame_cpu_ms p50 20.80,
frame_gpu_ms p50 10.62 over the final 50 frames) with no degradation — an abrupt stop, which is
the signature of pool exhaustion rather than a slow stall.

---

## Header

Analysis of sampling PhospheneApp (pid 42392) every 1 millisecond
Process:         PhospheneApp [42392]
Path:            /Users/USER/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Debug/PhospheneApp.app/Contents/MacOS/PhospheneApp
Load Address:    0x1042a4000
Identifier:      com.phosphene.app
Version:         1.0 (1)
Code Type:       ARM64
Platform:        macOS
Parent Process:  debugserver [42403]
Target Type:     live task

Date/Time:       2026-08-04 13:18:58.169 -0500
Launch Time:     2026-08-04 12:49:40.797 -0500
OS Version:      macOS 26.5.1 (25F80)
Report Version:  7
Analysis Tool:   /usr/bin/sample

Physical footprint:         660.8M
Physical footprint (peak):  1.0G
Idle exit:                  untracked
----


## Main thread — all 4250 samples

    4250 Thread_8389294   DispatchQueue_1: com.apple.main-thread  (serial)
    + 4250 start  (in dyld) + 6992  [0x183e37e00]
    +   4250 __debug_main_executable_dylib_entry_point  (in PhospheneApp.debug.dylib) + 12  [0x1080ea240]  PhospheneApp.swift:0
    +     4250 static PhospheneApp.$main()  (in PhospheneApp.debug.dylib) + 40  [0x1080ea0a4]  /<compiler-generated>:0
    +       4250 static App.main()  (in SwiftUI) + 224  [0x1b96a0344]
    +         4250 runApp<A>(_:)  (in SwiftUI) + 104  [0x1b93d44a4]
    +           4250 specialized runApp(_:)  (in SwiftUI) + 140  [0x1b901e47c]
    +             4250 NSApplicationMain  (in AppKit) + 880  [0x1886ab7b0]
    +               4250 -[NSApplication run]  (in AppKit) + 368  [0x1886d313c]
    +                 4250 -[NSApplication(NSEventRouting) nextEventMatchingMask:untilDate:inMode:dequeue:]  (in AppKit) + 72  [0x1892755bc]
    +                   4250 -[NSApplication(NSEventRouting) _nextEventMatchingEventMask:untilDate:inMode:dequeue:]  (in AppKit) + 688  [0x1892758b0]
    +                     4250 _DPSNextEvent  (in AppKit) + 576  [0x1886e0084]
    +                       4250 _DPSBlockUntilNextEventMatchingListInMode  (in AppKit) + 228  [0x188d8c35c]
    +                         4250 _BlockUntilNextEventMatchingListInMode  (in HIToolbox) + 48  [0x19122414c]
    +                           4250 ReceiveNextEventCommon  (in HIToolbox) + 488  [0x19109a8bc]
    +                             4250 RunCurrentEventLoopInMode  (in HIToolbox) + 320  [0x191097560]
    +                               4250 _CFRunLoopRunSpecificWithOptions  (in CoreFoundation) + 532  [0x1843841c4]
    +                                 4250 __CFRunLoopRun  (in CoreFoundation) + 1944  [0x1842b1cb8]
    +                                   4250 __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__  (in CoreFoundation) + 16  [0x1842ef724]
    +                                     4250 _dispatch_main_queue_callback_4CF  (in libdispatch.dylib) + 44  [0x1043a593c]
    +                                       4250 _dispatch_main_queue_drain  (in libdispatch.dylib) + 176  [0x1043a59fc]
    +                                         4250 _dispatch_main_queue_drain.cold.6  (in libdispatch.dylib) + 612  [0x1043d5358]
    +                                           4250 _dispatch_source_invoke  (in libdispatch.dylib) + 880  [0x1043af630]
    +                                             4250 _dispatch_source_latch_and_call  (in libdispatch.dylib) + 452  [0x1043b0d60]
    +                                               4250 _dispatch_continuation_pop  (in libdispatch.dylib) + 700  [0x104397f2c]
    +                                                 4250 _dispatch_client_callout  (in libdispatch.dylib) + 16  [0x1043b0ee0]
    +                                                   4250 __23-[MTKView __initCommon]_block_invoke  (in MetalKit) + 40  [0x19a2cf45c]
    +                                                     4250 -[MTKView draw]  (in MetalKit) + 268  [0x19a2cf588]
    +                                                       4250 @objc RenderPipeline.draw(in:)  (in PhospheneApp.debug.dylib) + 156  [0x108683de8]  /<compiler-generated>:0
    +                                                         4250 RenderPipeline.draw(in:)  (in PhospheneApp.debug.dylib) + 1540  [0x1086824d4]  RenderPipeline.swift:769
    +                                                           4250 RenderPipeline.renderFrame(commandBuffer:view:features:)  (in PhospheneApp.debug.dylib) + 5604  [0x108642aec]  RenderPipeline+Draw.swift:219
    +                                                             4250 RenderPipeline.drawWithFeedback(_:)  (in PhospheneApp.debug.dylib) + 340  [0x10864bbbc]  RenderPipeline+FeedbackDraw.swift:20
    +                                                               4250 RenderPipeline.drawParticleMode(commandBuffer:view:features:stemFeatures:activePipeline:particles:)  (in PhospheneApp.debug.dylib) + 260  [0x10864bec0]  RenderPipeline+FeedbackDraw.swift:88
    +                                                                 4250 -[MTKView currentRenderPassDescriptor]  (in MetalKit) + 32  [0x19a2cf944]
    +                                                                   4250 -[MTKView currentDrawable]  (in MetalKit) + 188  [0x19a2cfae8]
    +                                                                     4250 -[CAMetalLayer nextDrawable]  (in QuartzCore) + 124  [0x18e2f359c]
    +                                                                       4250 CAMetalLayerPrivateNextDrawableLocked(CAMetalLayer*, CAMetalDrawable**, unsigned long*)  (in QuartzCore) + 1192  [0x18e552d70]
    +                                                                         4250 _dispatch_semaphore_wait_slow  (in libdispatch.dylib) + 76  [0x104396714]
    +                                                                           4250 _dispatch_sema4_timedwait  (in libdispatch.dylib) + 64  [0x1043d0e24]
    +                                                                             4250 semaphore_timedwait_trap  (in libsystem_kernel.dylib) + 8  [0x1841b1bc8]

## Every other thread

Idle. No thread holds a Metal command buffer, waits on `waitUntilCompleted`, or blocks on a
mutex. Full capture retained outside the repo (228 KB) — only the load-bearing stack is
committed here.

## HANG.1 instrumentation (2026-08-05)

HANG.1 adds observation only. `DrawableLifecycleProbe` records, per command buffer:

- render-pass-descriptor and drawable request begin/end plus the call-site label;
- unique drawable identities acquired and scheduled for presentation;
- command-buffer commit, completion, and failure;
- acquisitions left unpresented when their command buffer completes.

`VisualizerEngine` polls the probe from an independent task. Healthy sessions write a
`DRAWABLE_LIFECYCLE heartbeat` every 600 completions. A failure or completed unpresented
acquisition writes `DRAWABLE_LIFECYCLE imbalance` immediately. A descriptor/drawable request
pending for 500 ms writes `DRAWABLE_LIFECYCLE STALL` with its frame, site, age, and the full
counter balance. This last path remains live when the main/render thread is blocked in
`nextDrawable`.

HANG.1 makes no fix and advances no root-cause hypothesis.

## HANG.2 outcome (2026-08-05)

HANG.2 completed the planned particle-preset soak as a clean non-reproduction. The two live
controls ran for 6:50 and more than 10:36 respectively; the longer run crossed two local-file
track transitions and retained balanced drawable acquisition/presentation with no recorded
stall. The full evidence and bounded conclusions are in
[`BUG085_HANG2_SOAK_2026-08-05.md`](BUG085_HANG2_SOAK_2026-08-05.md).

BUG-085 remains open and intermittent; HANG.2 provides neither a diagnosis nor a fix. On the
next live freeze, leave Phosphene running and execute `Scripts/capture_hang.sh` before
force-quitting. Its `session.txt` includes the last 20 drawable-lifecycle records alongside
the stack and process state.
