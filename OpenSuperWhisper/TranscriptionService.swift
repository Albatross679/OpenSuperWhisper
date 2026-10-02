import Foundation

@MainActor
class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var currentSegment = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Float = 0.0
    @Published private(set) var isConverting = false
    @Published private(set) var conversionProgress: Float = 0.0
    
    private final class TranscriptionTaskBox {
        let task: Task<String, Error>
        init(_ task: Task<String, Error>) { self.task = task }
    }
    
    private var currentEngine: TranscriptionEngine?
    private var usageLoadedSelection: UsageSelection?
    private var transcriptionTask: TranscriptionTaskBox? = nil
    private var isCancelled = false
    private var usageServiceBusy = false
    
    private let usageMetricsStore: UsageMetricsStore

    init(metricsStore: UsageMetricsStore = .shared) {
        self.usageMetricsStore = metricsStore
        loadEngine()
    }
    
    func cancelTranscription() {
        isCancelled = true
        currentEngine?.cancelTranscription()
        transcriptionTask?.task.cancel()
        transcriptionTask = nil
        
        isTranscribing = false
        currentSegment = ""
        progress = 0.0
        isCancelled = false
    }
    
    private func loadEngine() {
        let selectedEngine = AppPreferences.shared.selectedEngine
        let usageSelection = UsageSelection.capture(engine: selectedEngine)
        print("Loading engine: \(selectedEngine)")
        
        isLoading = true
        
        Task.detached(priority: .userInitiated) {
            let engine: TranscriptionEngine?
            
            if selectedEngine == "fluidaudio" {
                engine = await FluidAudioEngine()
            } else if selectedEngine == "cloudflare" {
                engine = await CloudflareEngine()
            } else {
                engine = await WhisperEngine()
            }
            
            do {
                try await engine?.initialize()
                
                await MainActor.run {
                    self.currentEngine = engine
                    self.usageLoadedSelection = usageSelection
                    self.isLoading = false
                    print("Engine loaded: \(selectedEngine)")
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Failed to load engine: \(error)")
                }
            }
        }
    }
    
    func reloadEngine() {
        loadEngine()
    }
    
    func reloadModel(with path: String) {
        if AppPreferences.shared.selectedEngine == "whisper" {
            AppPreferences.shared.selectedWhisperModelPath = path
            reloadEngine()
        }
    }
    
    func transcribeAudio(url: URL, settings: Settings, metricID: UUID = UUID(), recordedAt: Date? = nil) async throws -> String {
        // Reserve the whole call before the asynchronous original-duration read.
        // Otherwise indicator and queue calls can both pass the engine busy check.
        while usageServiceBusy { try await Task.sleep(nanoseconds: 1_000_000) }
        usageServiceBusy = true
        defer { usageServiceBusy = false }

        // Serialize access to the engine: a whisper context must not process
        // two transcriptions concurrently (indicator flow and queue flow can
        // both reach this point due to async busy checks).
        while let existing = transcriptionTask {
            _ = try? await existing.task.value
            if transcriptionTask === existing {
                transcriptionTask = nil
            }
        }
        
        // Read the original recording before any engine converts or speeds it up.
        let usageEngine = currentEngine
        let selection = usageEngine is CloudflareEngine ? UsageSelection.capture(engine: "cloudflare") : usageLoadedSelection ?? UsageSelection.capture(engine: AppPreferences.shared.selectedEngine)
        let date = recordedAt ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let seconds = await UsageTracking.audioSeconds(url)
        let store = usageMetricsStore
        let metricRun = store.begin(UsageDictation(id: metricID, recordedAt: date, originalSeconds: seconds,
                                                 engine: selection.engine, provider: selection.provider, model: selection.model),
                                    engine: selection.engine, provider: selection.provider, model: selection.model)
        var metricOutcome = "failure"
        defer { store.finishRun(metricRun, outcome: metricOutcome) }

        progress = 0.0
        conversionProgress = 0.0
        isConverting = true
        isTranscribing = true
        transcribedText = ""
        currentSegment = ""
        isCancelled = false
        
        defer {
            Task { @MainActor in
                self.isTranscribing = false
                self.isConverting = false
                self.currentSegment = ""
                if !self.isCancelled {
                    self.progress = 1.0
                }
                self.transcriptionTask = nil
            }
        }
        
        guard let engine = usageEngine else {
            throw TranscriptionError.contextInitializationFailed
        }
        
        // Setup progress callback for engines
        if let whisperEngine = engine as? WhisperEngine {
            whisperEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self = self, !self.isCancelled else { return }
                    self.progress = newProgress
                }
            }
        } else if let cloudflareEngine = engine as? CloudflareEngine {
            cloudflareEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    self?.progress = newProgress
                }
            }
        } else if let fluidEngine = engine as? FluidAudioEngine {
            fluidEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self = self, !self.isCancelled else { return }
                    self.progress = newProgress
                }
            }
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            try Task.checkCancellation()
            
            let cancelled = await MainActor.run {
                guard let self = self else { return true }
                return self.isCancelled
            }
            
            guard !cancelled else {
                throw CancellationError()
            }
            
            let result = try await UsageTracking.$context.withValue(
                UsageContext(dictationID: metricID, runID: metricRun, store: store)) {
                try await engine.transcribeAudio(url: url, settings: settings)
            }
            
            try Task.checkCancellation()
            
            let finalCancelled = await MainActor.run {
                guard let self = self else { return true }
                return self.isCancelled
            }
            
            await MainActor.run {
                guard let self = self, !self.isCancelled else { return }
                self.transcribedText = result
                self.progress = 1.0
            }
            
            guard !finalCancelled else {
                throw CancellationError()
            }
            
            return result
        }
        
        transcriptionTask = TranscriptionTaskBox(task)
        
        do {
            let result = try await task.value
            metricOutcome = "success"
            return result
        } catch is CancellationError {
            metricOutcome = "cancelled"
            isCancelled = true
            throw TranscriptionError.processingFailed
        }
    }
}

enum TranscriptionError: Error {
    case contextInitializationFailed
    case audioConversionFailed
    case processingFailed
}
