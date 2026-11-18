import SwiftUI

enum FieldInk {
    static let color = Color(red: 0.05, green: 0.38, blue: 0.34)
}

struct RoomMap: View {
    let room: RoomLayout
    let activeZoneID: String?

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 8
            let available = CGSize(width: size.width - inset * 2, height: size.height - inset * 2)
            let scale = min(available.width / room.width, available.height / room.height)
            let map = CGSize(width: room.width * scale, height: room.height * scale)
            let origin = CGPoint(x: (size.width - map.width) / 2, y: (size.height - map.height) / 2)
            let plan = CGRect(origin: origin, size: map)

            context.fill(
                Path(roundedRect: plan, cornerRadius: 8),
                with: .color(Color.primary.opacity(0.05))
            )
            context.stroke(
                Path(roundedRect: plan, cornerRadius: 8),
                with: .color(Color.primary.opacity(0.18)),
                lineWidth: 1
            )

            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + (room.height - y) * scale)
            }

            var split = Path()
            split.move(to: point(room.splitX, 0))
            split.addLine(to: point(room.splitX, room.height))
            split.move(to: point(0, room.splitY))
            split.addLine(to: point(room.width, room.splitY))
            context.stroke(split, with: .color(Color.primary.opacity(0.16)), lineWidth: 1)

            for zone in room.zones {
                let center = point(zone.x, zone.y)
                let active = zone.id == activeZoneID
                let radius: CGFloat = active ? 8 : 4.5
                let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(
                    Path(ellipseIn: dot),
                    with: .color(active ? FieldInk.color : Color.secondary)
                )
                context.draw(
                    Text(zone.id)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(active ? FieldInk.color : .secondary),
                    at: CGPoint(x: center.x, y: center.y - 16),
                    anchor: .center
                )
            }
        }
        .frame(height: 300)
        .accessibilityLabel(activeZoneID.map { "Room map, zone \($0)" } ?? "Room map, no zone")
    }
}
