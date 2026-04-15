import Foundation
import SwiftUI

@MainActor
public final class OrganizeSession: ObservableObject {
    public let originalText: String

    @Published public var selectedIntensity: CleanupIntensity = .medium
    @Published public var results: [CleanupIntensity: String] = [:]
    @Published public var loadingStates: [CleanupIntensity: Bool] = [:]
    @Published public var errors: [CleanupIntensity: String] = [:]

    @Published public var chatInstruction: String = ""
    @Published public var isRefining: Bool = false
    @Published public var refineError: String?

    private var generationTasks: [CleanupIntensity: Task<Void, Never>] = [:]
    private var refineTask: Task<Void, Never>?

    public init(originalText: String) {
        self.originalText = originalText
    }

    public var currentOutput: String {
        results[selectedIntensity] ?? ""
    }

    public var isLoadingCurrent: Bool {
        loadingStates[selectedIntensity] ?? false
    }

    public var currentError: String? {
        errors[selectedIntensity]
    }

    public func isLoading(_ intensity: CleanupIntensity) -> Bool {
        loadingStates[intensity] ?? false
    }

    public func selectTab(_ intensity: CleanupIntensity) {
        selectedIntensity = intensity
        refineError = nil
        if results[intensity] == nil && !(loadingStates[intensity] ?? false) {
            generate(intensity: intensity)
        }
    }

    public func generate(intensity: CleanupIntensity) {
        generationTasks[intensity]?.cancel()
        errors[intensity] = nil
        results[intensity] = ""
        loadingStates[intensity] = true

        let text = originalText
        generationTasks[intensity] = Task { [weak self] in
            guard let self else { return }
            do {
                let service = try OpenRouterService()
                let stream = service.organize(text: text, intensity: intensity)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    self.results[intensity, default: ""] += chunk
                }
            } catch is CancellationError {
                // swallowed
            } catch {
                self.errors[intensity] = error.localizedDescription
            }
            self.loadingStates[intensity] = false
        }
    }

    public func submitChatInstruction() {
        let instruction = chatInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty,
              !isRefining,
              !(loadingStates[selectedIntensity] ?? false),
              let current = results[selectedIntensity],
              !current.isEmpty
        else { return }

        let intensity = selectedIntensity
        let previous = current
        refineError = nil
        isRefining = true
        results[intensity] = ""

        refineTask?.cancel()
        refineTask = Task { [weak self] in
            guard let self else { return }
            do {
                let service = try OpenRouterService()
                let stream = service.refine(
                    originalText: self.originalText,
                    currentOutput: previous,
                    instruction: instruction,
                    intensity: intensity
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    self.results[intensity, default: ""] += chunk
                }
                if !Task.isCancelled {
                    self.chatInstruction = ""
                }
            } catch is CancellationError {
                self.results[intensity] = previous
            } catch {
                self.refineError = error.localizedDescription
                self.results[intensity] = previous
            }
            self.isRefining = false
        }
    }

    public func cancelAll() {
        for (_, task) in generationTasks { task.cancel() }
        generationTasks.removeAll()
        refineTask?.cancel()
        refineTask = nil
    }
}
