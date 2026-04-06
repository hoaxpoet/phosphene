// Audio — System audio capture, ring buffers, FFT, lookahead buffer,
// streaming metadata (Now Playing + MusicKit), metadata pre-fetcher.
//
// Primary capture uses Core Audio taps (AudioHardwareCreateProcessTap),
// available on macOS 14.2+. ScreenCaptureKit was evaluated but fails to
// deliver audio callbacks on macOS 15+/26 despite video frames arriving.

import Foundation
import CoreAudio
import AVFoundation
import Accelerate
