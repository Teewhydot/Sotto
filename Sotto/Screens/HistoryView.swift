//
//  HistoryView.swift
//  Sotto
//

import SwiftUI

struct HistoryView: View {
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var showDeleteAlert = false
    @State private var showFavouriteAlert = false
    let filters = ["All", "Voice", "Text", "Favourites"]

    var filteredEntries: [MockEntry] {
        var entries = mockEntries
        switch selectedFilter {
        case "Voice":       entries = entries.filter { $0.inputMode == "voice" }
        case "Text":        entries = entries.filter { $0.inputMode == "text" }
        case "Favourites":  entries = entries.filter { $0.isFavourite }
        default: break
        }
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.transcript.localizedCaseInsensitiveContains(searchText) ||
                $0.primaryEmotion.localizedCaseInsensitiveContains(searchText) ||
                $0.themes.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return entries
    }

    var groupedEntries: [(String, [MockEntry])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var groups: [String: [MockEntry]] = [:]
        for entry in filteredEntries {
            let key = formatter.string(from: entry.date)
            groups[key, default: []].append(entry)
        }
        return groups.sorted { a, b in
            let df = DateFormatter()
            df.dateFormat = "MMMM yyyy"
            return (df.date(from: a.0) ?? .now) > (df.date(from: b.0) ?? .now)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Filter chips row
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { filter in
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        selectedFilter = filter
                                    }
                                } label: {
                                    Text(filter)
                                        .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(
                                            selectedFilter == filter
                                                ? Color.sottoAccent
                                                : Color.sottoSecondary,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(
                                            selectedFilter == filter ? .white : .secondary
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden)

                if groupedEntries.isEmpty {
                    ContentUnavailableView(
                        "No entries found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or filter.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    // Entry groups
                    ForEach(groupedEntries, id: \.0) { month, entries in
                        Section {
                            ForEach(entries) { entry in
                                NavigationLink(destination: EntryDetailView(entry: entry)) {
                                    EntryRowView(entry: entry)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        showFavouriteAlert = true
                                    } label: {
                                        Label("Favourite", systemImage: "heart.fill")
                                    }
                                    .tint(.red)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text(month)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Entries")
            .searchable(text: $searchText, prompt: "Search entries…")
            .alert("Delete Entry?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { }
            } message: {
                Text("This entry will be permanently deleted.")
            }
            .alert("Added to Favourites", isPresented: $showFavouriteAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }
}

// MARK: - Entry Row
struct EntryRowView: View {
    let entry: MockEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded)

                Spacer()

                EmotionBadge(emotion: entry.primaryEmotion, color: entry.emotionColor)

                Label(
                    entry.duration,
                    systemImage: entry.inputMode == "voice" ? "mic.fill" : "pencil"
                )
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.leading, 4)
            }

            Text(String(entry.transcript.prefix(90)) + "…")
                .font(.callout).fontDesign(.serif)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .lineSpacing(3)

            HStack(spacing: 6) {
                ForEach(entry.themes.prefix(3), id: \.self) { theme in
                    ThemeChip(label: theme)
                }
                if entry.isFavourite {
                    Image(systemName: "heart.fill")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview("History") {
    HistoryView()
}
#Preview("History — dark") {
    HistoryView()
        .preferredColorScheme(.dark)
}
