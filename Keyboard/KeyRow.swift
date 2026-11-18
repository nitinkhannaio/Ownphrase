import UIKit

/// Key edges measured on the system English keyboard at 1206 physical pixels wide.
/// Layout is relative to the available width, snapped to the current display scale.
final class KeyRow: UIView {
    private let keys: [UIButton]
    private let edges: [(Int, Int)]
    private let landscapeEdges: [(Int, Int)]?

    init(keys: [UIButton], names: [String], inset: Bool, bottom: Bool) {
        self.keys = keys
        if bottom && names.count == 4 {
            edges = [(20,150),(168,298),(316,890),(908,1187)]
        } else if !bottom && names.count == 10 {
            edges = [(20,120),(138,239),(257,357),(375,476),(494,594),(612,713),(731,831),(849,950),(968,1068),(1086,1187)]
        } else if inset && names.count == 9 {
            edges = [(79,179),(197,298),(316,416),(434,535),(553,653),(671,772),(790,890),(908,1009),(1027,1127)]
        } else if names.first == "Shift" && names.count == 9 {
            edges = [(20,156),(197,298),(316,416),(434,535),(553,653),(671,772),(790,890),(908,1009),(1050,1187)]
        } else if names.last == "Delete" && names.count == 7 {
            edges = [(20,156),(197,345),(363,511),(529,677),(695,843),(861,1009),(1050,1187)]
        } else {
            let gaps = 18 * (names.count - 1)
            let available = 1167 - gaps
            let fixed = names.map { name in name == "return" ? 279 : (name == "space" ? 0 : 130) }
            let space = available - fixed.reduce(0, +)
            var x = 20
            edges = names.enumerated().map { index, name in
                let width = bottom ? (name == "space" ? space : fixed[index]) : available / names.count
                defer { x += width + 18 }
                return (x, x + width)
            }
        }
        let top = [(237,436),(454,652),(670,869),(887,1085),(1103,1302),(1320,1519),(1537,1735),(1753,1952),(1970,2168),(2186,2385)]
        let middle = [(345,544),(562,761),(779,977),(995,1194),(1212,1410),(1428,1627),(1645,1844),(1862,2060),(2078,2277)]
        if bottom && names.count == 4 {
            landscapeEdges = [(237,436),(454,652),(670,1952),(1970,2385)]
        } else if !bottom && names.count == 10 {
            landscapeEdges = top
        } else if inset && names.count == 9 {
            landscapeEdges = middle
        } else if names.first == "Shift" && names.count == 9 {
            landscapeEdges = [(237,501)] + Array(middle.dropFirst().dropLast()) + [(2121,2385)]
        } else {
            landscapeEdges = nil
        }
        super.init(frame: .zero)
        keys.forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let wide = bounds.width > 560 && landscapeEdges != nil
        let layout = wide ? landscapeEdges! : edges
        func align(_ pixel: Int) -> CGFloat {
            (CGFloat(pixel - (wide ? 225 : 0)) / (wide ? 2172 : 1206) * bounds.width * scale).rounded() / scale
        }
        for (key, edge) in zip(keys, layout) {
            let start = align(edge.0)
            key.frame = CGRect(x: start, y: 0, width: align(edge.1) - start, height: bounds.height)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: bounds.width > 560 ? -4 : -5.5).contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit !== self { return hit }
        return keys.min { abs($0.center.x - point.x) < abs($1.center.x - point.x) }
    }
}
