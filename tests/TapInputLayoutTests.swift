// The runner compiles the real tap input offset helper from AppAudioMixer.swift.
@main struct TapInputLayoutTests {
    static func main() {
        typealias Shape = Layout.InputStreamShape
        let stereo = Shape(channels: 2, buffers: 1)
        let quad = Shape(channels: 4, buffers: 1)

        // Built-in speakers and split USB headsets: the aggregate has no physical inputs.
        precondition(Layout.tapInputBufferBase(streams: [stereo], taps: [stereo]) == 0)
        precondition(Layout.tapInputBufferBase(streams: [stereo, quad], taps: [stereo, quad]) == 0)

        // Scarlett 4i4 Gen3: a 6-channel interleaved input stream precedes the 4-channel tap.
        let scarlettInput = Shape(channels: 6, buffers: 1)
        precondition(Layout.tapInputBufferBase(streams: [scarlettInput, quad], taps: [quad]) == 1)
        precondition(Layout.tapInputBufferBase(streams: [scarlettInput, quad, stereo], taps: [quad, stereo]) == 1)

        // Non-interleaved physical inputs occupy one buffer per channel.
        let planarInput = Shape(channels: 8, buffers: 8)
        precondition(Layout.tapInputBufferBase(streams: [planarInput, stereo], taps: [stereo]) == 8)

        // Tap streams not yet published must not be mistaken for physical inputs.
        precondition(Layout.tapInputBufferBase(streams: [scarlettInput], taps: [quad]) == nil)
        precondition(Layout.tapInputBufferBase(streams: [], taps: [stereo]) == nil)
        precondition(Layout.tapInputBufferBase(streams: [stereo], taps: [stereo, stereo]) == nil)
        print("Tap input layout tests passed")
    }
}
