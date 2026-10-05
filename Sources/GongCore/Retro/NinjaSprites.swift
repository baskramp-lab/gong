import Foundation

public enum NinjaPose: String, CaseIterable, Sendable {
    case idle    // wide fighting stance
    case crouch  // anticipation and landing
    case leap    // jump toward the gong
    case tuck    // salto back home
}

/// Ninja silhouettes, facing right, 20 px wide. Materials: s suit, k skin, r headband, b/w band, W/P eye.
public enum NinjaSprites {
    public static let width = 20
    /// Head + torso rows; the legs follow below.
    public static let upperRows = 22

    static let head = [
        ".......ssssss.......",
        ".....ssssssssss.....",
        "....ssssssssssss....",
        "...ssssssssssssss...",
        "...rrrrrrrrrrrrrr...",
        "...ssssssskkkkkks...",
        "...sssssskWPkkWPs...",
        "...ssssssskkkkkks...",
        "...ssssssssssssss...",
        "....ssssssssssss....",
        "......ssssssss......",
    ]
    static let headBlink = head.enumerated().map { $0.offset == 6 ? "...sssssskkkkkkks..." : $0.element }

    static let torso = [
        "......ssssssss......",
        ".....ssssssssss.....",
        "....ssssssssssss....",
        "....ssssssssssss....",
        "....ssssssssssss....",
        "....ssssssssssss....",
        "....bbbbbbbbbbbb....",
        "....ssssssssssss....",
        "....ssssssssssss....",
        "...ssssssssssssss...",
        "...sssssss.sssssss..",
    ]

    static let legs: [NinjaPose: [String]] = [
        .idle: [
            "...sssssss.sssssss..",
            "..ssssss....sssssss.",
            "..sssss......ssssss.",
            ".sssss........sssss.",
            ".ssss..........ssss.",
            "ssss...........ssss.",
            "www............wwww.",
            "sss............ssss.",
            "sss...........sssss.",
            "ssss..........ssssss",
        ],
        .crouch: [
            "..sssssssss.ssssss..",
            ".ssssss......ssssss.",
            "sssss.........sssss.",
            "www............wwww.",
            "sss...........sssss.",
            "ssss..........ssssss",
        ],
        .leap: [
            ".....ssssssssssss...",
            "....ssssss..sssssss.",
            "...sssss.....sssssss",
            "..sssss.......ssssss",
            ".sssss.........sss..",
            "ssss...........sss..",
            "www............www..",
            "ss..............ss..",
            "s..............sss..",
            "...............ss...",
        ],
        .tuck: [
            ".....sssssssssssss..",
            "....ssssssssssssss..",
            "....wwwwssssswwww...",
            ".....ssssssssssss...",
        ],
    ]

    /// Full sprite for a pose. `sink` lowers head+torso by 1 px (breathing) while the feet stay planted.
    public static func grid(pose: NinjaPose, blink: Bool = false, sink: Bool = false, rotation: Int = 0) -> SpriteGrid {
        var upper = SpriteGrid((blink ? headBlink : head) + torso)
        if sink { upper = upper.sunk(upperRows: upperRows) }
        return (upper + SpriteGrid(legs[pose] ?? [])).rotated(quarterTurns: rotation)
    }
}
