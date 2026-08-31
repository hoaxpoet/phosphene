// AudioFeatures — @frozen, SIMD-aligned structs for audio analysis data.
// These types are the shared currency between CPU analysis, GPU shaders,
// and ANE inference. All use value semantics and fixed layouts suitable
// for direct upload to Metal buffers.
//
// Split into topic-based files:
//   AudioFeatures+Frame.swift    — AudioFrame, FFTResult, StemData
//   AudioFeatures+Metadata.swift — MetadataSource, TrackMetadata, PreFetchedTrackProfile
//   AudioFeatures+Analyzed.swift — FeatureVector, FeedbackParams, EmotionalQuadrant,
//                                  EmotionalState, StructuralPrediction
