import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GongCore

// Usage:
//   swift run GongIconExport <AppIcon.appiconset>        writes the 10 app-icon PNGs
//   swift run GongIconExport --frames <dir>              writes scene frames at key moments (×4) for review
//   swift run GongIconExport --wav <file.wav>            writes the synthesized gong
//   swift run GongIconExport --game-frames <dir>         writes game frames for each ninja move (×4) for review
//   swift run GongIconExport --web <dir>                 assets for the browser preview of the modal (scene strip, world, sounds)
//   swift run GongIconExport --mix <file.wav>            writes one soundtrack loop with the gong on every strike

func writePNG(_ canvas: PixelCanvas, to url: URL) throws {
    guard let image = canvas.cgImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "GongIconExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot encode \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "GongIconExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "--frames":
        let dir = URL(fileURLWithPath: args.count > 1 ? args[1] : "frames")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = SceneRenderer()
        for t in [0.2, 0.6, 0.78, 0.86, 1.0, 1.2, 1.6, 5.0, 5.8] {
            let state = StrikeTimeline.state(cycleTime: t, time: t, reduceMotion: false)
            try writePNG(renderer.render(state).scaled(to: 400), to: dir.appendingPathComponent(String(format: "frame-%05.2f.png", t)))
        }
        print("Wrote frames to \(dir.path)")
    case "--wav":
        let url = URL(fileURLWithPath: args.count > 1 ? args[1] : "gong.wav")
        try GongSynth.wavData(GongSynth.render()).write(to: url)
        print("Wrote \(url.path)")
    case "--game-frames":
        let dir = URL(fileURLWithPath: args.count > 1 ? args[1] : "game-frames")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = GameRenderer()
        func shot(_ name: String, _ g: NinjaGame) throws {
            try writePNG(r.render(g, time: g.runTime + g.deathTime, best: 1230, secondsToStart: 161).scaled(to: NinjaGame.width * 4),
                         to: dir.appendingPathComponent("\(name).png"))
        }
        func play(_ g: inout NinjaGame, _ seconds: Double, _ input: GameInput = GameInput()) {
            for _ in 0..<Int((seconds * 60).rounded()) { g.step(dt: 1.0 / 60, input: input, minutesToStart: 3) }
        }
        func quiet() -> NinjaGame { var g = NinjaGame(seed: 1, x: 100); g.autoSpawn = false; return g }
        var g = quiet(); play(&g, 1); try shot("01-idle", g)
        g = quiet(); play(&g, 0.4, GameInput(right: true)); try shot("02-run", g)
        g = quiet(); play(&g, 0.5, GameInput(down: true)); try shot("03-crouch", g)
        g = quiet(); play(&g, 0.2, GameInput(right: true)); play(&g, 1.0 / 60, GameInput(right: true, down: true, downPressed: true)); play(&g, 0.15, GameInput(right: true, down: true)); try shot("04-slide", g)
        for (i, t) in [0.05, 0.15, 0.3, 0.45].enumerated() {
            g = quiet(); play(&g, 1.0 / 60, GameInput(jump: true)); play(&g, t); try shot("05-salto-\(i)", g)
        }
        g = quiet(); g.spawn(Shuriken(x: g.x + 40, y: NinjaGame.highY, vx: -90, lane: .high)); play(&g, 0.2)
        play(&g, 1.0 / 60, GameInput(strike: true)); play(&g, 0.12); try shot("06-strike", g)
        g = quiet(); g.spawn(Shuriken(x: g.x + 5, y: NinjaGame.highY, vx: 1, lane: .high)); play(&g, 0.1); try shot("07-hurt", g)
        g = quiet()
        for _ in 0..<3 { g.spawn(Shuriken(x: g.x + 10, y: g.y + 15, vx: 1, lane: .high)); play(&g, 1.4) }
        try shot("08-game-over-lying", g)
        print("Wrote game frames to \(dir.path)")
    case "--web":
        let dir = URL(fileURLWithPath: args.count > 1 ? args[1] : "web")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // one strike cycle of the scene at 60 fps, without petals, as a horizontal strip
        let fps = 60, frames = Int(StrikeClock.cycle) * fps, layout = SceneLayout.modal
        var strip = PixelCanvas(width: layout.width * frames, height: layout.height)
        let scene = SceneRenderer()
        for i in 0..<frames {
            let t = Double(i) / Double(fps)
            strip.draw(scene.render(StrikeTimeline.state(cycleTime: t, time: t, reduceMotion: false), petals: false),
                       x: i * layout.width, y: 0)
        }
        try writePNG(strip, to: dir.appendingPathComponent("scene-strip.png"))
        try writePNG(SceneRenderer.worldBackground(), to: dir.appendingPathComponent("world.png"))   // gong drawn live
        try GongSynth.wavData(GongSynth.render()).write(to: dir.appendingPathComponent("gong.wav"))
        try GongSynth.wavData(SoundtrackSynth.render()).write(to: dir.appendingPathComponent("soundtrack.wav"))
        try GongSynth.wavData(GameSounds.tink()).write(to: dir.appendingPathComponent("tink.wav"))
        try GongSynth.wavData(GameSounds.tok()).write(to: dir.appendingPathComponent("tok.wav"))
        print("Wrote web assets (\(frames) scene frames) to \(dir.path)")
    case "--mix":
        let url = URL(fileURLWithPath: args.count > 1 ? args[1] : "gong-mix.wav")
        var mix = SoundtrackSynth.render().map { $0 * SoundtrackSynth.mixLevel }
        let gong = GongSynth.render(), sr = Double(GongSynth.sampleRate)
        var strike = StrikeClock.leadIn + StrikeClock.hit
        while strike < SoundtrackSynth.duration {
            let at = Int(strike * sr)
            for (i, v) in gong.enumerated() { mix[(at + i) % mix.count] += v }
            strike += StrikeClock.cycle
        }
        let peak = mix.reduce(0) { max($0, abs($1)) }
        try GongSynth.wavData(mix.map { $0 / max(1, peak) }).write(to: url)
        print("Wrote \(url.path)")
    case let path?:
        let dir = URL(fileURLWithPath: path)
        let icon = SceneRenderer.appIcon()
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try writePNG(icon.scaled(to: points * scale), to: dir.appendingPathComponent(name))
        }
        print("Wrote app icon to \(dir.path)")
    case nil:
        print("usage: GongIconExport <AppIcon.appiconset> | --frames <dir> | --wav <file> | --mix <file>")
        exit(64)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
