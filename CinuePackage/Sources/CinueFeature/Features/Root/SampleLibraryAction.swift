import CoreData
import SwiftUI

struct SampleLibraryAction: View {
    @Environment(AppEnvironment.self) private var environment
    @FetchRequest private var trackedItems: FetchedResults<NSManagedObject>
    @FetchRequest private var lists: FetchedResults<NSManagedObject>
    @FetchRequest private var listItems: FetchedResults<NSManagedObject>
    @FetchRequest private var episodes: FetchedResults<NSManagedObject>

    init() {
        func request(_ entity: String) -> NSFetchRequest<NSManagedObject> {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.sortDescriptors = []
            request.fetchLimit = 1
            return request
        }
        _trackedItems = FetchRequest(fetchRequest: request("TrackedItem"))
        _lists = FetchRequest(fetchRequest: request("UserList"))
        _listItems = FetchRequest(fetchRequest: request("UserListItem"))
        _episodes = FetchRequest(fetchRequest: request("EpisodeState"))
    }
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        if trackedItems.isEmpty && lists.isEmpty && listItems.isEmpty && episodes.isEmpty {
            VStack(spacing: CinueSpacing.sm) {
                Text("Adds fictional items to your local library. No TMDB key is needed. You can edit or remove them like any other items.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    guard !isLoading else { return }
                    isLoading = true
                    Task { @MainActor in
                        // Yield once so the loading state is visible before the synchronous save.
                        await Task.yield()
                        do {
                            try SampleLibraryStore(persistence: environment.persistence).addSamples()
                        } catch SampleLibraryStore.SampleError.libraryNotEmpty {
                            errorMessage = "Your library already contains data. Sample items were not added."
                        } catch SampleLibraryStore.SampleError.busy {
                            errorMessage = "A library import is in progress. Try again when it finishes."
                        } catch {
                            errorMessage = "Could not add the sample library. Please try again."
                        }
                        isLoading = false
                    }
                } label: {
                    if isLoading { ProgressView() } else { Text("Try a sample library") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 320)
            .padding(.horizontal)
        }
    }
}
