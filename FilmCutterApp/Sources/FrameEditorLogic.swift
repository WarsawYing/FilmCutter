import Foundation
import CoreGraphics

struct PreviewLayout: Equatable {
    let scale: CGFloat
    let imageSize: CGSize
    let origin: CGPoint
}

struct FrameEditHistory: Equatable {
    var undo: [[FilmFrame]] = []
    var redo: [[FilmFrame]] = []
}

enum FrameGeometryIssue: Equatable {
    case outsideImage(UUID)
    case tooSmall(UUID)
    case nearDuplicate(UUID, UUID)
}

enum FrameEditorLogic {
    static let minimumSide = 20

    static func previewLayout(
        container: CGSize,
        imageWidth: Int,
        imageHeight: Int,
        inset: CGFloat = 18
    ) -> PreviewLayout {
        let availableWidth = max(1, container.width - inset * 2)
        let availableHeight = max(1, container.height - inset * 2)
        let sourceWidth = CGFloat(max(1, imageWidth))
        let sourceHeight = CGFloat(max(1, imageHeight))
        let scale = max(0.000_001, min(availableWidth / sourceWidth, availableHeight / sourceHeight))
        let imageSize = CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
        return PreviewLayout(
            scale: scale,
            imageSize: imageSize,
            origin: CGPoint(
                x: (container.width - imageSize.width) / 2,
                y: (container.height - imageSize.height) / 2
            )
        )
    }

    static func normalized(_ frames: [FilmFrame]) -> [FilmFrame] {
        frames.enumerated().map { offset, frame in
            FilmFrame(
                id: frame.id,
                index: offset,
                x: frame.x,
                y: frame.y,
                width: frame.width,
                height: frame.height
            )
        }
    }

    static func moved(
        _ frame: FilmFrame,
        deltaX: Int,
        deltaY: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> FilmFrame {
        let maxX = max(0, imageWidth - frame.width)
        let maxY = max(0, imageHeight - frame.height)
        return FilmFrame(
            id: frame.id,
            index: frame.index,
            x: min(max(0, frame.x + deltaX), maxX),
            y: min(max(0, frame.y + deltaY), maxY),
            width: min(frame.width, imageWidth),
            height: min(frame.height, imageHeight)
        )
    }

    static func resizedFromBottomRight(
        _ frame: FilmFrame,
        deltaWidth: Int,
        deltaHeight: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> FilmFrame {
        let maximumWidth = max(1, imageWidth - frame.x)
        let maximumHeight = max(1, imageHeight - frame.y)
        return FilmFrame(
            id: frame.id,
            index: frame.index,
            x: max(0, min(frame.x, imageWidth - 1)),
            y: max(0, min(frame.y, imageHeight - 1)),
            width: min(max(minimumSide, frame.width + deltaWidth), maximumWidth),
            height: min(max(minimumSide, frame.height + deltaHeight), maximumHeight)
        )
    }

    static func defaultFrame(
        existing: [FilmFrame],
        imageWidth: Int,
        imageHeight: Int
    ) -> FilmFrame {
        let widths = existing.map(\.width).sorted()
        let heights = existing.map(\.height).sorted()
        let width = min(imageWidth, widths.isEmpty ? max(80, imageWidth / 5) : widths[widths.count / 2])
        let height = min(imageHeight, heights.isEmpty ? max(80, Int(Double(width) / 1.5)) : heights[heights.count / 2])
        return FilmFrame(
            index: existing.count,
            x: max(0, (imageWidth - width) / 2),
            y: max(0, (imageHeight - height) / 2),
            width: max(1, width),
            height: max(1, height)
        )
    }

    /// Sort by the dominant scan direction while keeping nearby strips in
    /// reading order. Reordering is explicit so numbers never jump mid-drag.
    static func spatiallyOrdered(_ frames: [FilmFrame]) -> [FilmFrame] {
        guard frames.count > 1 else { return normalized(frames) }
        let centersX = frames.map { Double($0.x) + Double($0.width) / 2 }
        let centersY = frames.map { Double($0.y) + Double($0.height) / 2 }
        let spreadX = (centersX.max() ?? 0) - (centersX.min() ?? 0)
        let spreadY = (centersY.max() ?? 0) - (centersY.min() ?? 0)
        let ordered: [FilmFrame]
        if spreadX >= spreadY {
            ordered = frames.sorted { lhs, rhs in
                let tolerance = max(lhs.height, rhs.height) / 2
                return abs(lhs.y - rhs.y) > tolerance ? lhs.y < rhs.y : lhs.x < rhs.x
            }
        } else {
            ordered = frames.sorted { lhs, rhs in
                let tolerance = max(lhs.width, rhs.width) / 2
                return abs(lhs.x - rhs.x) > tolerance ? lhs.x < rhs.x : lhs.y < rhs.y
            }
        }
        return normalized(ordered)
    }

    static func issues(
        in frames: [FilmFrame],
        imageWidth: Int,
        imageHeight: Int
    ) -> [FrameGeometryIssue] {
        var result: [FrameGeometryIssue] = []
        for frame in frames {
            if frame.width < minimumSide || frame.height < minimumSide {
                result.append(.tooSmall(frame.id))
            }
            if frame.x < 0 || frame.y < 0 || frame.x + frame.width > imageWidth || frame.y + frame.height > imageHeight {
                result.append(.outsideImage(frame.id))
            }
        }
        for firstIndex in frames.indices {
            for secondIndex in frames.indices where secondIndex > firstIndex {
                let first = frames[firstIndex]
                let second = frames[secondIndex]
                let overlapWidth = max(0, min(first.x + first.width, second.x + second.width) - max(first.x, second.x))
                let overlapHeight = max(0, min(first.y + first.height, second.y + second.height) - max(first.y, second.y))
                let overlap = overlapWidth * overlapHeight
                let smallerArea = min(first.width * first.height, second.width * second.height)
                if smallerArea > 0 && Double(overlap) / Double(smallerArea) >= 0.80 {
                    result.append(.nearDuplicate(first.id, second.id))
                }
            }
        }
        return result
    }
}
