import SwiftUI
import UIKit

enum CinueRemoteArtworkPhase {
    case empty
    case loading
    case success(UIImage)
    case failure
}

struct CinueRemoteArtworkTaskIdentity: Hashable {
    let url: URL?
    let maximumPixelSize: Int
}

@MainActor
final class CinueRemoteArtworkLoader: ObservableObject {
    @Published private(set) var phase: CinueRemoteArtworkPhase = .empty
    private var request: ArtworkLoadRequest?

    func load(
        url: URL?,
        maximumPixelSize: Int,
        pipeline: any ArtworkImageLoading
    ) async {
        guard let url else {
            request = nil
            phase = .empty
            return
        }

        let nextRequest = ArtworkLoadRequest(url: url, maximumPixelSize: maximumPixelSize)
        guard request != nextRequest || isLoaded == false else {
            return
        }

        request = nextRequest
        phase = .loading

        do {
            let image = try await pipeline.image(for: nextRequest)
            guard request == nextRequest else {
                return
            }
            phase = .success(image.value)
        } catch is CancellationError {
            return
        } catch {
            guard request == nextRequest else {
                return
            }
            phase = .failure
        }
    }

    private var isLoaded: Bool {
        if case .success = phase {
            return true
        }
        return false
    }
}

struct CinueRemoteArtworkImage<Content: View>: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.displayScale) private var displayScale
    @StateObject private var loader = CinueRemoteArtworkLoader()

    let url: URL?
    let pointSize: CGSize
    private let content: (CinueRemoteArtworkPhase) -> Content

    init(
        url: URL?,
        pointSize: CGSize,
        @ViewBuilder content: @escaping (CinueRemoteArtworkPhase) -> Content
    ) {
        self.url = url
        self.pointSize = pointSize
        self.content = content
    }

    var body: some View {
        content(loader.phase)
            .task(id: taskIdentity) {
                await loader.load(
                    url: url,
                    maximumPixelSize: taskIdentity.maximumPixelSize,
                    pipeline: environment.artworkPipeline
                )
            }
    }

    private var taskIdentity: CinueRemoteArtworkTaskIdentity {
        CinueRemoteArtworkTaskIdentity(
            url: url,
            maximumPixelSize: min(
                ArtworkLimits.standard.maximumRenderedSide,
                max(1, Int((max(pointSize.width, pointSize.height) * displayScale).rounded(.up)))
            )
        )
    }

}
