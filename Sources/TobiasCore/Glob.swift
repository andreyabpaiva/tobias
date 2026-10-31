import Foundation

/// Thin wrapper over glob(3), with brace expansion, returning only paths that exist.
enum Glob {
    static func expand(_ pattern: String) -> [String] {
        var g = glob_t()
        defer { globfree(&g) }
        guard glob(pattern, GLOB_BRACE, nil, &g) == 0 else { return [] }
        var out: [String] = []
        for i in 0..<Int(g.gl_pathc) {
            if let p = g.gl_pathv[i] {
                out.append(String(cString: p))
            }
        }
        return out
    }

    static func hasMagic(_ s: String) -> Bool {
        s.contains { "*?[{".contains($0) }
    }
}
