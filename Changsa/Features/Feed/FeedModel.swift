import Foundation

@Observable
final class FeedModel {
    var cards: [FeedCard] = []
    var isLoading = false
    var matchedCard: FeedCard?
    var errorMessage: String?

    private var isFetching = false

    @MainActor
    func loadInitial() async {
        guard cards.isEmpty else { return }
        isLoading = true
        await fetchMore()
        isLoading = false
    }

    @MainActor
    func fetchMore() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let fresh: TolerantList<FeedCard> = try await APIClient.shared.get(
                "/api/feed",
                query: [URLQueryItem(name: "limit", value: "20")]
            )
            let known = Set(cards.map(\.uid))
            cards.append(contentsOf: fresh.items.filter { !known.contains($0.uid) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes the card immediately for a snappy deck, then records the swipe.
    @MainActor
    func swipe(_ card: FeedCard, action: SwipeAction) {
        cards.removeAll { $0.uid == card.uid }
        Task {
            do {
                let result: SwipeResult = try await APIClient.shared.post(
                    "/api/swipes/\(card.uid)",
                    body: SwipeIn(action: action)
                )
                if action != .pass, result.isMatch {
                    matchedCard = card
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            if cards.count <= 3 {
                await fetchMore()
            }
        }
    }

    @MainActor
    func reportAndRemove(_ card: FeedCard, reason: String) {
        cards.removeAll { $0.uid == card.uid }
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/reports",
                    body: ReportIn(reportedUid: card.uid, reason: reason, note: "")
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    func blockAndRemove(_ card: FeedCard) {
        cards.removeAll { $0.uid == card.uid }
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post("/api/blocks/\(card.uid)")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
