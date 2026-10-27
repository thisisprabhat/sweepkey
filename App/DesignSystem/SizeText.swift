import SwiftUI

enum SizeFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct SizeText: View {
    let bytes: Int64

    var body: some View {
        Text(SizeFormat.string(bytes))
            .monospacedDigit()
    }
}

#Preview {
    VStack { SizeText(bytes: 1_234_567_890); SizeText(bytes: 42_000) }.padding()
}
