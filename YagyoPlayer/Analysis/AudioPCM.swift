import AVFoundation
import AudioToolbox

enum AudioChannelRole: Hashable, Sendable {
    case left, right, center, lfe
    case leftCenter, rightCenter
    case leftSurround, rightSurround
    case leftSurroundDirect, rightSurroundDirect
    case rearSurroundLeft, rearSurroundRight, centerSurround
}

struct PCMSourceDescription: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: Int
    // nil means absent or ambiguous multichannel labels.
    let channelRoles: [AudioChannelRole]?
}

struct AnalysisPCMFormat: Equatable, Sendable {
    let sampleRate: Double
    let channelRoles: [AudioChannelRole]

    var channelCount: Int { channelRoles.count }

    init(sampleRate: Double, channelRoles: [AudioChannelRole]) throws {
        guard sampleRate.isFinite, sampleRate > 0 else {
            throw AudioPCMError.invalidSampleRate
        }
        guard (1...8).contains(channelRoles.count) else {
            throw AudioPCMError.invalidChannelCount
        }
        guard Set(channelRoles).count == channelRoles.count else {
            throw AudioPCMError.duplicateChannelRole
        }

        self.sampleRate = sampleRate
        self.channelRoles = channelRoles
    }
}

struct AVAudioPCMBufferAdapter: Sendable {
    let sourceDescription: PCMSourceDescription
    let analysisFormat: AnalysisPCMFormat?

    private let channelCount: Int
    private let isInterleaved: Bool

    init(format: AVAudioFormat) throws {
        guard format.commonFormat == .pcmFormatFloat32 else {
            throw AudioPCMError.unsupportedPCMFormat
        }
        guard format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw AudioPCMError.invalidSampleRate
        }

        let channelCount = Int(format.channelCount)
        guard (1...8).contains(channelCount) else {
            throw AudioPCMError.invalidChannelCount
        }

        let roles = Self.resolveChannelRoles(format: format, channelCount: channelCount)
        sourceDescription = PCMSourceDescription(
            sampleRate: format.sampleRate,
            channelCount: channelCount,
            channelRoles: roles
        )
        if let roles, Self.isSupportedAnalysisRoleSet(roles) {
            analysisFormat = try AnalysisPCMFormat(sampleRate: format.sampleRate, channelRoles: roles)
        } else {
            analysisFormat = nil
        }
        self.channelCount = channelCount
        isInterleaved = format.isInterleaved
    }

    // Validated, nonthrowing, allocation-free hot path.
    func copyInterleavedSamples(
        from buffer: AVAudioPCMBuffer,
        sourceFrameOffset: Int,
        frameCount: Int,
        into destination: UnsafeMutableBufferPointer<Float>
    ) -> Bool {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.format.sampleRate == sourceDescription.sampleRate,
              Int(buffer.format.channelCount) == channelCount,
              buffer.format.isInterleaved == isInterleaved,
              sourceFrameOffset >= 0,
              frameCount >= 0 else {
            return false
        }

        let availableFrameCount = Int(buffer.frameLength)
        guard sourceFrameOffset <= availableFrameCount,
              frameCount <= availableFrameCount - sourceFrameOffset else {
            return false
        }

        let sampleCount = frameCount * channelCount
        guard destination.count >= sampleCount else {
            return false
        }
        guard sampleCount > 0 else {
            return true
        }
        guard let destinationBase = destination.baseAddress,
              let channelData = buffer.floatChannelData else {
            return false
        }

        if isInterleaved {
            let source = channelData[0].advanced(by: sourceFrameOffset * channelCount)
            destinationBase.update(from: source, count: sampleCount)
            return true
        }

        for frameIndex in 0..<frameCount {
            let sourceFrameIndex = sourceFrameOffset + frameIndex
            let destinationFrameOffset = frameIndex * channelCount
            for channelIndex in 0..<channelCount {
                destinationBase[destinationFrameOffset + channelIndex] = channelData[channelIndex][sourceFrameIndex]
            }
        }
        return true
    }
}

struct AudioSampleBlock {
    let format: AnalysisPCMFormat
    let frameCount: Int
    let streamStartFrame: Int64
    let interleavedSamples: UnsafeBufferPointer<Float>
}

enum AudioPCMError: Error, Equatable {
    case unsupportedPCMFormat
    case invalidSampleRate
    case invalidChannelCount
    case duplicateChannelRole
}

private extension AVAudioPCMBufferAdapter {
    static func resolveChannelRoles(format: AVAudioFormat, channelCount: Int) -> [AudioChannelRole]? {
        if let layout = format.channelLayout {
            return roles(from: layout, expectedChannelCount: channelCount)
        }

        switch channelCount {
        case 1:
            return [.center]
        case 2:
            return [.left, .right]
        default:
            return nil
        }
    }

    static func roles(from layout: AVAudioChannelLayout, expectedChannelCount: Int) -> [AudioChannelRole]? {
        let layoutPointer = layout.layout
        let layoutTag = layoutPointer.pointee.mChannelLayoutTag

        if layoutTag == kAudioChannelLayoutTag_UseChannelDescriptions {
            return roles(from: layoutPointer, expectedChannelCount: expectedChannelCount)
        }

        if let roles = roles(forSupportedLayoutTag: layoutTag),
           roles.count == expectedChannelCount {
            return roles
        }

        guard supportedLayoutTags.contains(layoutTag),
              let resolvedLayoutPointer = resolvedLayout(for: layoutTag) else {
            return nil
        }
        defer { resolvedLayoutPointer.deallocate() }

        return roles(from: UnsafePointer(resolvedLayoutPointer), expectedChannelCount: expectedChannelCount)
    }

    static func roles(forSupportedLayoutTag layoutTag: AudioChannelLayoutTag) -> [AudioChannelRole]? {
        switch layoutTag {
        case kAudioChannelLayoutTag_Mono:
            return [.center]
        case kAudioChannelLayoutTag_Stereo:
            return [.left, .right]
        default:
            return nil
        }
    }

    static func roles(
        from layoutPointer: UnsafePointer<AudioChannelLayout>,
        expectedChannelCount: Int
    ) -> [AudioChannelRole]? {
        let layout = layoutPointer.pointee
        let descriptionCount = Int(layout.mNumberChannelDescriptions)
        guard descriptionCount == expectedChannelCount,
              descriptionCount > 0 else {
            return nil
        }

        guard let descriptionsOffset = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) else {
            return nil
        }
        let descriptions = UnsafeRawPointer(layoutPointer)
            .advanced(by: descriptionsOffset)
            .assumingMemoryBound(to: AudioChannelDescription.self)

        var roles: [AudioChannelRole] = []
        roles.reserveCapacity(descriptionCount)
        for index in 0..<descriptionCount {
            guard let role = AudioChannelRole(label: descriptions[index].mChannelLabel),
                  !roles.contains(role) else {
                return nil
            }
            roles.append(role)
        }

        return isSupportedAnalysisRoleSet(roles) ? roles : nil
    }

    static func resolvedLayout(for layoutTag: AudioChannelLayoutTag) -> UnsafeMutablePointer<AudioChannelLayout>? {
        var tag = layoutTag
        var layoutSize: UInt32 = 0
        let specifierSize = UInt32(MemoryLayout<AudioChannelLayoutTag>.size)
        let infoStatus = withUnsafePointer(to: &tag) { tagPointer in
            AudioFormatGetPropertyInfo(
                kAudioFormatProperty_ChannelLayoutForTag,
                specifierSize,
                tagPointer,
                &layoutSize
            )
        }
        guard infoStatus == noErr, layoutSize > 0 else {
            return nil
        }

        let rawLayout = UnsafeMutableRawPointer.allocate(
            byteCount: Int(layoutSize),
            alignment: MemoryLayout<AudioChannelLayout>.alignment
        )
        let status = withUnsafePointer(to: &tag) { tagPointer in
            AudioFormatGetProperty(
                kAudioFormatProperty_ChannelLayoutForTag,
                specifierSize,
                tagPointer,
                &layoutSize,
                rawLayout
            )
        }
        guard status == noErr else {
            rawLayout.deallocate()
            return nil
        }

        return rawLayout.assumingMemoryBound(to: AudioChannelLayout.self)
    }

    static func isSupportedAnalysisRoleSet(_ roles: [AudioChannelRole]) -> Bool {
        supportedRoleSets.contains(Set(roles))
    }

    static let supportedLayoutTags: Set<AudioChannelLayoutTag> = [
        kAudioChannelLayoutTag_Mono,
        kAudioChannelLayoutTag_Stereo,
        kAudioChannelLayoutTag_MPEG_3_0_A,
        kAudioChannelLayoutTag_MPEG_3_0_B,
        kAudioChannelLayoutTag_MPEG_4_0_A,
        kAudioChannelLayoutTag_MPEG_4_0_B,
        kAudioChannelLayoutTag_Quadraphonic,
        kAudioChannelLayoutTag_ITU_2_2,
        kAudioChannelLayoutTag_MPEG_5_0_A,
        kAudioChannelLayoutTag_MPEG_5_0_B,
        kAudioChannelLayoutTag_MPEG_5_0_C,
        kAudioChannelLayoutTag_MPEG_5_0_D,
        kAudioChannelLayoutTag_MPEG_5_1_A,
        kAudioChannelLayoutTag_MPEG_5_1_B,
        kAudioChannelLayoutTag_MPEG_5_1_C,
        kAudioChannelLayoutTag_MPEG_5_1_D,
        kAudioChannelLayoutTag_MPEG_7_1_A,
        kAudioChannelLayoutTag_MPEG_7_1_B,
        kAudioChannelLayoutTag_MPEG_7_1_C,
        kAudioChannelLayoutTag_AudioUnit_7_1
    ]

    static let supportedRoleSets: Set<Set<AudioChannelRole>> = [
        [.center],
        [.left, .right],
        [.left, .right, .center],
        [.left, .right, .center, .centerSurround],
        [.left, .right, .leftSurround, .rightSurround],
        [.left, .right, .center, .leftSurround, .rightSurround],
        [.left, .right, .center, .lfe, .leftSurround, .rightSurround],
        [.left, .right, .center, .lfe, .leftSurround, .rightSurround, .leftCenter, .rightCenter],
        [.left, .right, .center, .lfe, .leftSurround, .rightSurround, .rearSurroundLeft, .rearSurroundRight]
    ]
}

private extension AudioChannelRole {
    init?(label: AudioChannelLabel) {
        switch label {
        case kAudioChannelLabel_Left:
            self = .left
        case kAudioChannelLabel_Right:
            self = .right
        case kAudioChannelLabel_Center:
            self = .center
        case kAudioChannelLabel_LFEScreen:
            self = .lfe
        case kAudioChannelLabel_LeftCenter:
            self = .leftCenter
        case kAudioChannelLabel_RightCenter:
            self = .rightCenter
        case kAudioChannelLabel_LeftSurround:
            self = .leftSurround
        case kAudioChannelLabel_RightSurround:
            self = .rightSurround
        case kAudioChannelLabel_LeftSurroundDirect:
            self = .leftSurroundDirect
        case kAudioChannelLabel_RightSurroundDirect:
            self = .rightSurroundDirect
        case kAudioChannelLabel_RearSurroundLeft:
            self = .rearSurroundLeft
        case kAudioChannelLabel_RearSurroundRight:
            self = .rearSurroundRight
        case kAudioChannelLabel_CenterSurround:
            self = .centerSurround
        default:
            return nil
        }
    }
}
