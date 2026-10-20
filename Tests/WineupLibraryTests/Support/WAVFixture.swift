import Foundation

/// Gera WAV PCM 16-bit estéreo minúsculo, sem ferramentas externas.
enum WAVFixture {
    static func write(to url: URL, seconds: Double = 0.25, frequency: Double = 440,
                      sampleRate: Int = 44100) throws {
        let frames = max(1, Int(seconds * Double(sampleRate)))
        let channels = 2, bytesPerSample = 2
        let dataSize = frames * channels * bytesPerSample
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(channels)
        u32(sampleRate); u32(sampleRate * channels * bytesPerSample)
        u16(channels * bytesPerSample); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        for i in 0..<frames {
            let s = Int16(sin(2 * .pi * frequency * Double(i) / Double(sampleRate)) * 12000)
            for _ in 0..<channels { var x = s.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        }
        try d.write(to: url)
    }
}
