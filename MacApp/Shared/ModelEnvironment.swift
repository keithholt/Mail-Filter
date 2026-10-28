import Foundation
import FoundationModels
import Darwin

/// Explicit diagnostic metadata; no host name, serial, Mail access or inference.
struct ModelEnvironment: Encodable {
    struct Model: Encodable {
        let useCase: String
        let availability: String
        let contextTokens: Int
        let variant: String?
        let supportsReasoning: Bool?
    }
    let operatingSystem: String
    let hardwareModel: String?
    let processor: String?
    let physicalMemoryMiB: UInt64
    let preferredLanguages: [String]
    let locale: String
    let lowPowerMode: Bool
    let models: [Model]

    static func systemString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    @MainActor
    static func capture() -> ModelEnvironment {
        let models: [Model] = [("general", SystemLanguageModel.UseCase.general), ("contentTagging", .contentTagging)].map { name, useCase in
            let model = SystemLanguageModel(useCase: useCase, guardrails: .permissiveContentTransformations)
            var variant: String?, reasoning: Bool?
            if #available(macOS 27.0, *) {
                variant = model.variant.displayName
                reasoning = model.capabilities.contains(.reasoning)
            }
            return Model(useCase: name, availability: String(describing: model.availability),
                contextTokens: model.contextSize, variant: variant, supportsReasoning: reasoning)
        }
        return ModelEnvironment(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: systemString("hw.model"), processor: systemString("machdep.cpu.brand_string"),
            physicalMemoryMiB: ProcessInfo.processInfo.physicalMemory / 1_048_576,
            preferredLanguages: Locale.preferredLanguages, locale: Locale.current.identifier,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, models: models)
    }
}
