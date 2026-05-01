// FidelityRubric+Optional — E1–E4 (expected) and P1–P4 (preferred) evaluators.

import Foundation
import Shared

// MARK: - E1–E4 Evaluators

extension DefaultFidelityRubric {

    // MARK: E1: Triplanar

    func evaluateE1(_ src: String) -> RubricItem {
        let found = src.contains("triplanar_sample(")
            || src.contains("triplanar_normal(")
            || src.contains("triplanar_blend_weights(")
            || src.contains("triplanar_detail_normal(")
        return RubricItem(
            id: "E1_triplanar",
            label: "Triplanar texturing",
            category: .expected,
            status: found ? .pass : .fail,
            detail: found ? "triplanar_* call found" : "no triplanar_* calls found"
        )
    }

    // MARK: E2: Detail Normals

    func evaluateE2(_ src: String) -> RubricItem {
        let found = src.contains("combine_normals_udn(")
            || src.contains("combine_normals_whiteout(")
            || src.contains("detail_normal")
            || src.contains("tbn_from_derivatives(")
        return RubricItem(
            id: "E2_detail_normals",
            label: "Detail normals",
            category: .expected,
            status: found ? .pass : .fail,
            detail: found ? "detail-normal utility call found" : "no detail-normal calls found"
        )
    }

    // MARK: E3: Volumetric Fog / Aerial Perspective

    func evaluateE3(_ src: String, _ descriptor: PresetDescriptor) -> RubricItem {
        let inSource = src.contains("fog(")
            || src.contains("aerial_perspective(")
            || src.contains("vol_accumulate(")
            || src.contains("ls_radial_step_uv(")
            || src.contains("cloud_march(")
        let inJSON = descriptor.sceneFog > 0
        let found = inSource || inJSON
        let detail = inJSON
            ? "scene_fog: \(String(format: "%.4f", descriptor.sceneFog))"
            : (inSource ? "volumetric/fog call found in source" : "no fog/aerial/volumetric calls found")
        return RubricItem(
            id: "E3_fog_aerial",
            label: "Volumetric fog / aerial perspective",
            category: .expected,
            status: found ? .pass : .fail,
            detail: detail
        )
    }

    // MARK: E4: Advanced BRDF (SSS / fiber / anisotropic)

    func evaluateE4(_ src: String) -> RubricItem {
        let found = src.contains("sss_backlit(")
            || src.contains("sss_wrap_lighting(")
            || src.contains("fiber_marschner_lite(")
            || src.contains("fiber_trt_lobe(")
            || src.contains("brdf_ashikhmin_shirley(")
            || src.contains("oren_nayar(")
        return RubricItem(
            id: "E4_advanced_brdf",
            label: "SSS / fiber / anisotropic BRDF",
            category: .expected,
            status: found ? .pass : .fail,
            detail: found ? "advanced BRDF call found" : "no SSS/fiber/anisotropic BRDF calls found"
        )
    }
}

// MARK: - P1–P4 Evaluators

extension DefaultFidelityRubric {

    // MARK: P1: Hero Specular (author-asserted)

    func evaluateP1(_ descriptor: PresetDescriptor) -> RubricItem {
        let asserted = descriptor.rubricHints.heroSpecular
        return RubricItem(
            id: "P1_hero_specular",
            label: "Hero specular highlight ≥60% of frames",
            category: .preferred,
            status: asserted ? .pass : .fail,
            detail: asserted
                ? "rubric_hints.hero_specular: true (author-asserted)"
                : "rubric_hints.hero_specular: false (set to true in JSON when present)"
        )
    }

    // MARK: P2: Parallax Occlusion Mapping

    func evaluateP2(_ src: String) -> RubricItem {
        let found = src.contains("parallax_occlusion(") || src.contains("parallax_shadowed(")
        return RubricItem(
            id: "P2_parallax_occlusion",
            label: "Parallax occlusion mapping",
            category: .preferred,
            status: found ? .pass : .fail,
            detail: found ? "parallax_occlusion* call found" : "no parallax_occlusion calls found"
        )
    }

    // MARK: P3: Volumetric Light Shafts / Dust Motes

    func evaluateP3(_ src: String, _ descriptor: PresetDescriptor) -> RubricItem {
        let inSource = src.contains("ls_radial_step_uv(")
            || src.contains("ls_shadow_march(")
            || src.contains("ls_sun_disk(")
            || src.contains("ls_intensity_audio(")
        let asserted = descriptor.rubricHints.dustMotes
        let found = inSource || asserted
        let detail: String
        if inSource {
            detail = "light-shaft utility call found in source"
        } else if asserted {
            detail = "rubric_hints.dust_motes: true (author-asserted)"
        } else {
            detail = "no light-shaft calls; rubric_hints.dust_motes: false"
        }
        return RubricItem(
            id: "P3_volumetric_light_motes",
            label: "Volumetric light shafts / dust motes",
            category: .preferred,
            status: found ? .pass : .fail,
            detail: detail
        )
    }

    // MARK: P4: Chromatic Aberration / Thin-Film Interference

    func evaluateP4(_ src: String) -> RubricItem {
        let found = src.contains("chromatic_aberration_radial(")
            || src.contains("chromatic_aberration_directional(")
            || src.contains("thinfilm_rgb(")
            || src.contains("thinfilm_hue_rotate(")
        return RubricItem(
            id: "P4_chroma_thinfilm",
            label: "Chromatic aberration / thin-film",
            category: .preferred,
            status: found ? .pass : .fail,
            detail: found
                ? "chromatic_aberration or thinfilm call found"
                : "no chromatic aberration / thin-film calls"
        )
    }
}
