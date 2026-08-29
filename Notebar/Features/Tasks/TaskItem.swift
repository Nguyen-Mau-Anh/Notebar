import Foundation

/// A single task card. In-memory only for this M1 slice — see `Note` for the
/// same note on `NotesTab`.
struct TaskItem: Identifiable {
    let id = UUID()
    var title: String
}

/// A status column on the Tasks board (spec §6.3). Dragging a card between
/// groups is M2 scope; this slice only appends into the first group via the
/// toolbar's `+`.
struct TaskGroup: Identifiable {
    let id = UUID()
    var name: String
    var tasks: [TaskItem]

    /// The board always opens on these three groups — there is no group
    /// management yet, only the seeded shape from the mockup in spec §6.3.
    static let seeded: [TaskGroup] = [
        TaskGroup(name: "Queue", tasks: []),
        TaskGroup(name: "Working", tasks: []),
        TaskGroup(name: "Done", tasks: [])
    ]
}
