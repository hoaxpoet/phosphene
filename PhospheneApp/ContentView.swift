import SwiftUI
import Renderer

struct ContentView: View {
    private let context: MetalContext
    private let pipeline: RenderPipeline

    init() {
        // Fatal error here is intentional — no Metal device means we can't run at all.
        let ctx = try! MetalContext()
        self.context = ctx
        self.pipeline = RenderPipeline(context: ctx)
    }

    var body: some View {
        MetalView(context: context, pipeline: pipeline)
            .frame(minWidth: 800, minHeight: 600)
    }
}
