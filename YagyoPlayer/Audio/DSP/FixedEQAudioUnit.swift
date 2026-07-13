import AVFoundation
@preconcurrency import AudioToolbox
import Darwin
import Synchronization

enum FixedEQAudioUnitError: LocalizedError, Equatable {
    case mailboxInitializationFailed
    case unsupportedFormat
    case inputOutputFormatMismatch
    case invalidMaximumFrames

    var errorDescription: String? {
        switch self {
        case .mailboxInitializationFailed:
            return "The Fixed EQ control mailbox could not be initialized."
        case .unsupportedFormat:
            return "Fixed EQ requires non-interleaved Float32 mono or stereo audio."
        case .inputOutputFormatMismatch:
            return "Fixed EQ input and output formats must match."
        case .invalidMaximumFrames:
            return "Fixed EQ requires a positive maximum render frame count."
        }
    }
}

enum FixedEQAudioUnitRenderFault: Int32, Equatable, Sendable {
    case none = 0
    case notReady
    case invalidOutputBus
    case frameOverflow
    case invalidOutputBuffers
    case missingPullInput
    case pullInputFailure
    case invalidInputBuffers
    case processorInvalidBuffers
}

struct FixedEQAudioUnitRenderTelemetry: Equatable, Sendable {
    let appliedGeneration: UInt64?
    let processResult: FixedEQProcessResult
    let isOriginalLatched: Bool
    let fault: FixedEQAudioUnitRenderFault
    let status: OSStatus
}

/// Minimal in-process effect AU for the explicit Fixed EQ preview graph.
/// The production AVAudioPlayer path does not instantiate this unit.
final class FixedEQAudioUnit: AUAudioUnit {
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x5967_4551, // YgEQ
        componentManufacturer: 0x5961_6779, // Yagy
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static let componentRegistration: Void = {
        AUAudioUnit.registerSubclass(
            FixedEQAudioUnit.self,
            as: componentDescription,
            name: "YagyoPlayer: Fixed EQ",
            version: 1
        )
    }()

    /// Register once on the control side before `AVAudioUnit.instantiate`.
    static func registerComponent() {
        _ = componentRegistration
    }

    private let renderState: FixedEQAudioUnitRenderState
    private var snapshotProducer: FixedEQSnapshotProducer
    private var inputBusArrayStorage: AUAudioUnitBusArray?
    private var outputBusArrayStorage: AUAudioUnitBusArray?
    private var renderBlockStorage: AUInternalRenderBlock?

    override var inputBusses: AUAudioUnitBusArray {
        guard let inputBusArrayStorage else {
            preconditionFailure("Fixed EQ input bus is unavailable after initialization")
        }
        return inputBusArrayStorage
    }

    override var outputBusses: AUAudioUnitBusArray {
        guard let outputBusArrayStorage else {
            preconditionFailure("Fixed EQ output bus is unavailable after initialization")
        }
        return outputBusArrayStorage
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        guard let renderBlockStorage else {
            preconditionFailure("Fixed EQ render block is unavailable after initialization")
        }
        return renderBlockStorage
    }

    override var canProcessInPlace: Bool { false }

    override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        var mailbox = FixedEQSnapshotMailbox()
        guard let producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            throw FixedEQAudioUnitError.mailboxInitializationFailed
        }
        snapshotProducer = consume producer
        renderState = FixedEQAudioUnitRenderState(consumer: consume consumer)

        try super.init(componentDescription: componentDescription, options: options)

        guard let defaultFormat = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 2
        ) else {
            throw FixedEQAudioUnitError.unsupportedFormat
        }
        let inputBus = try AUAudioUnitBus(format: defaultFormat)
        let outputBus = try AUAudioUnitBus(format: defaultFormat)
        inputBus.supportedChannelCounts = [1, 2]
        outputBus.supportedChannelCounts = [1, 2]
        inputBusArrayStorage = AUAudioUnitBusArray(
            audioUnit: self,
            busType: .input,
            busses: [inputBus]
        )
        outputBusArrayStorage = AUAudioUnitBusArray(
            audioUnit: self,
            busType: .output,
            busses: [outputBus]
        )

        let state = renderState
        renderBlockStorage = { [state]
            actionFlags,
            timestamp,
            frameCount,
            outputBusNumber,
            outputData,
            realtimeEventListHead,
            pullInputBlock in
            return state.render(
                actionFlags: actionFlags,
                timestamp: timestamp,
                frameCount: frameCount,
                outputBusNumber: outputBusNumber,
                outputData: outputData,
                realtimeEventListHead: realtimeEventListHead,
                pullInputBlock: pullInputBlock
            )
        }
    }

    override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
        !renderResourcesAllocated && Self.supports(format)
    }

    override func allocateRenderResources() throws {
        let inputFormat = inputBusses[0].format
        let outputFormat = outputBusses[0].format
        guard Self.supports(inputFormat), Self.supports(outputFormat) else {
            throw FixedEQAudioUnitError.unsupportedFormat
        }
        guard Self.formatsMatch(inputFormat, outputFormat) else {
            throw FixedEQAudioUnitError.inputOutputFormatMismatch
        }
        guard maximumFramesToRender > 0 else {
            throw FixedEQAudioUnitError.invalidMaximumFrames
        }

        try super.allocateRenderResources()
        renderState.allocateScratch(
            channelCount: Int(outputFormat.channelCount),
            maximumFrames: Int(maximumFramesToRender)
        )
    }

    override func deallocateRenderResources() {
        // Host lifecycle contract: the engine must stop rendering before this call.
        // `ready` rejects later calls; it is deliberately not a render-thread join.
        renderState.deallocateScratch()
        super.deallocateRenderResources()
    }

    override func reset() {
        renderState.reset()
        super.reset()
    }

    /// Single control-thread endpoint. A full mailbox rejects the snapshot; it never
    /// overwrites unread render data.
    @MainActor
    func enqueue(_ snapshot: FixedEQSnapshot) -> Bool {
        snapshotProducer.enqueue(snapshot)
    }

    var lastAppliedGeneration: UInt64? {
        renderTelemetry.appliedGeneration
    }

    var lastProcessResult: FixedEQProcessResult {
        renderTelemetry.processResult
    }

    var isOriginalLatched: Bool {
        renderTelemetry.isOriginalLatched
    }

    var lastRenderFault: FixedEQAudioUnitRenderFault {
        renderTelemetry.fault
    }

    var lastRenderStatus: OSStatus {
        renderTelemetry.status
    }

    /// Coherent control-side acknowledgement. Callers that need more than the
    /// generation must read this value once instead of composing the convenience
    /// properties above across multiple render epochs.
    var renderTelemetry: FixedEQAudioUnitRenderTelemetry {
        renderState.telemetry
    }

    private static func supports(_ format: AVAudioFormat) -> Bool {
        format.commonFormat == .pcmFormatFloat32
            && !format.isInterleaved
            && (1...2).contains(Int(format.channelCount))
            && format.sampleRate.isFinite
            && format.sampleRate > 0
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
            && lhs.channelCount == rhs.channelCount
            && lhs.sampleRate == rhs.sampleRate
    }
}

/// Render-owned mutable state. Its address remains stable for the lifetime of the AU;
/// the render block owns it through a direct strong capture and borrows that capture
/// for each invocation.
private final class FixedEQAudioUnitRenderState: @unchecked Sendable {
    private var processor: FixedEQRenderProcessor
    private var scratchBufferList: UnsafeMutableAudioBufferListPointer?
    private var scratchLeft: UnsafeMutablePointer<Float>?
    private var scratchRight: UnsafeMutablePointer<Float>?
    private var outputLeft: UnsafeMutablePointer<Float>?
    private var outputRight: UnsafeMutablePointer<Float>?
    private var channelCount = 0
    private var maximumFrames = 0

    private let ready = Atomic<Bool>(false)
    private let telemetrySequence = Atomic<UInt64>(0)
    private let appliedGeneration = Atomic<UInt64>(0)
    private let hasAppliedGeneration = Atomic<Bool>(false)
    private let processResult = Atomic<UInt32>(FixedEQProcessResult.original.rawValue)
    private let originalLatched = Atomic<Bool>(false)
    private let renderFault = Atomic<Int32>(FixedEQAudioUnitRenderFault.none.rawValue)
    private let renderStatus = Atomic<Int32>(noErr)

    // Swift 6.2 no longer imports the C enum case as a top-level symbol.
    private static let outputIsSilence = AudioUnitRenderActionFlags(rawValue: 1 << 4)

    init(consumer: consuming FixedEQSnapshotConsumer) {
        processor = FixedEQRenderProcessor(consumer: consume consumer)
    }

    deinit {
        deallocateScratch()
    }

    var telemetry: FixedEQAudioUnitRenderTelemetry {
        while true {
            let sequenceBefore = telemetrySequence.load(ordering: .acquiring)
            guard sequenceBefore & 1 == 0 else { continue }

            let hasGeneration = hasAppliedGeneration.load(ordering: .relaxed)
            let generation = appliedGeneration.load(ordering: .acquiring)
            let result = FixedEQProcessResult(
                rawValue: processResult.load(ordering: .relaxed)
            ) ?? .invalidBuffers
            let latched = originalLatched.load(ordering: .relaxed)
            let fault = FixedEQAudioUnitRenderFault(
                rawValue: renderFault.load(ordering: .relaxed)
            ) ?? .processorInvalidBuffers
            let status = renderStatus.load(ordering: .relaxed)

            // Keep every payload read before the final sequence validation. Together
            // with the writer's odd acq-rel RMW and even release RMW, this closes both
            // reorder windows in the single-writer seqlock.
            atomicMemoryFence(ordering: .acquiringAndReleasing)
            let sequenceAfter = telemetrySequence.load(ordering: .acquiring)
            guard sequenceBefore == sequenceAfter else { continue }
            return FixedEQAudioUnitRenderTelemetry(
                appliedGeneration: hasGeneration ? generation : nil,
                processResult: result,
                isOriginalLatched: latched,
                fault: fault,
                status: status
            )
        }
    }

    func allocateScratch(channelCount: Int, maximumFrames: Int) {
        deallocateScratch()

        let bufferList = AudioBufferList.allocate(maximumBuffers: channelCount)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: maximumFrames)
        left.initialize(repeating: 0, count: maximumFrames)
        let right: UnsafeMutablePointer<Float>?
        if channelCount == 2 {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: maximumFrames)
            pointer.initialize(repeating: 0, count: maximumFrames)
            right = pointer
        } else {
            right = nil
        }
        let renderedLeft = UnsafeMutablePointer<Float>.allocate(capacity: maximumFrames)
        renderedLeft.initialize(repeating: 0, count: maximumFrames)
        let renderedRight: UnsafeMutablePointer<Float>?
        if channelCount == 2 {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: maximumFrames)
            pointer.initialize(repeating: 0, count: maximumFrames)
            renderedRight = pointer
        } else {
            renderedRight = nil
        }

        self.channelCount = channelCount
        self.maximumFrames = maximumFrames
        scratchBufferList = bufferList
        scratchLeft = left
        scratchRight = right
        outputLeft = renderedLeft
        outputRight = renderedRight
        processor.reset()
        configureScratchBufferList(byteCount: maximumFrames * MemoryLayout<Float>.stride)
        ready.store(true, ordering: .releasing)
    }

    func deallocateScratch() {
        ready.store(false, ordering: .releasing)
        if let scratchLeft {
            scratchLeft.deinitialize(count: maximumFrames)
            scratchLeft.deallocate()
            self.scratchLeft = nil
        }
        if let scratchRight {
            scratchRight.deinitialize(count: maximumFrames)
            scratchRight.deallocate()
            self.scratchRight = nil
        }
        if let outputLeft {
            outputLeft.deinitialize(count: maximumFrames)
            outputLeft.deallocate()
            self.outputLeft = nil
        }
        if let outputRight {
            outputRight.deinitialize(count: maximumFrames)
            outputRight.deallocate()
            self.outputRight = nil
        }
        if let scratchBufferList {
            free(scratchBufferList.unsafeMutablePointer)
            self.scratchBufferList = nil
        }
        channelCount = 0
        maximumFrames = 0
        processor.reset()
    }

    func reset() {
        processor.reset()
    }

    func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputBusNumber: Int,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        realtimeEventListHead: UnsafePointer<AURenderEvent>?,
        pullInputBlock: AURenderPullInputBlock?
    ) -> AUAudioUnitStatus {
        _ = realtimeEventListHead
        let requestedFrames = Int(frameCount)
        let requestedBytes = requestedFrames * MemoryLayout<Float>.stride
        actionFlags.pointee.remove(Self.outputIsSilence)

        guard requestedFrames > 0 else { return noErr }
        guard ready.load(ordering: .acquiring) else {
            return failHostContract(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .notReady,
                status: kAudioUnitErr_Uninitialized
            )
        }
        guard outputBusNumber == 0 else {
            return failHostContract(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .invalidOutputBus,
                status: kAudioUnitErr_InvalidElement
            )
        }
        guard requestedFrames <= maximumFrames else {
            return failHostContract(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .frameOverflow,
                status: kAudioUnitErr_TooManyFramesToProcess
            )
        }
        guard let scratchBufferList,
              scratchBufferList.count == channelCount,
              prepareOutputBuffers(outputData, requestedBytes: requestedBytes) else {
            return failHostContract(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .invalidOutputBuffers,
                status: kAudio_ParamError
            )
        }

        configureScratchBufferList(byteCount: requestedBytes)
        guard let pullInputBlock else {
            return failSilently(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .missingPullInput,
                status: kAudioUnitErr_NoConnection
            )
        }

        let pullStatus = pullInputBlock(
            actionFlags,
            timestamp,
            frameCount,
            0,
            scratchBufferList.unsafeMutablePointer
        )
        guard pullStatus == noErr else {
            return failSilently(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .pullInputFailure,
                status: pullStatus
            )
        }
        guard inputBuffersAreValid(scratchBufferList, requestedBytes: requestedBytes) else {
            return failSilently(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .invalidInputBuffers,
                status: kAudio_ParamError
            )
        }

        let inputLeftPointer = scratchBufferList[0].mData!.assumingMemoryBound(to: Float.self)
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
        let outputLeftPointer = outputBuffers[0].mData!.assumingMemoryBound(to: Float.self)
        let inputRightPointer: UnsafePointer<Float>?
        let outputRightPointer: UnsafeMutablePointer<Float>?
        if channelCount == 2 {
            inputRightPointer = UnsafePointer(
                scratchBufferList[1].mData!.assumingMemoryBound(to: Float.self)
            )
            outputRightPointer = outputBuffers[1].mData!.assumingMemoryBound(to: Float.self)
        } else {
            inputRightPointer = nil
            outputRightPointer = nil
        }

        let inputRightBuffer: UnsafeBufferPointer<Float>?
        let outputRightBuffer: UnsafeMutableBufferPointer<Float>?
        if let inputRightPointer, let outputRightPointer {
            inputRightBuffer = UnsafeBufferPointer(
                start: inputRightPointer,
                count: requestedFrames
            )
            outputRightBuffer = UnsafeMutableBufferPointer(
                start: outputRightPointer,
                count: requestedFrames
            )
        } else {
            inputRightBuffer = nil
            outputRightBuffer = nil
        }

        let report = processor.process(
            inputLeft: UnsafeBufferPointer(start: inputLeftPointer, count: requestedFrames),
            inputRight: inputRightBuffer,
            outputLeft: UnsafeMutableBufferPointer(
                start: outputLeftPointer,
                count: requestedFrames
            ),
            outputRight: outputRightBuffer,
            frameCount: requestedFrames
        )

        guard report.processResult != .invalidBuffers else {
            return failSilently(
                actionFlags: actionFlags,
                outputData: outputData,
                requestedBytes: requestedBytes,
                fault: .processorInvalidBuffers,
                status: kAudio_ParamError,
                latchAgain: false,
                appliedGeneration: report.appliedGeneration
            )
        }
        publish(report)
        actionFlags.pointee.remove(Self.outputIsSilence)
        return noErr
    }

    private func configureScratchBufferList(byteCount: Int) {
        guard let scratchBufferList, let scratchLeft else { return }
        scratchBufferList[0].mNumberChannels = 1
        scratchBufferList[0].mDataByteSize = UInt32(byteCount)
        scratchBufferList[0].mData = UnsafeMutableRawPointer(scratchLeft)
        if channelCount == 2, let scratchRight {
            scratchBufferList[1].mNumberChannels = 1
            scratchBufferList[1].mDataByteSize = UInt32(byteCount)
            scratchBufferList[1].mData = UnsafeMutableRawPointer(scratchRight)
        }
    }

    private func inputBuffersAreValid(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        requestedBytes: Int
    ) -> Bool {
        guard buffers.count == channelCount else { return false }
        for channel in 0..<channelCount {
            guard buffers[channel].mNumberChannels == 1,
                  Int(buffers[channel].mDataByteSize) >= requestedBytes,
                  buffers[channel].mData != nil else {
                return false
            }
        }
        return true
    }

    private func prepareOutputBuffers(
        _ outputData: UnsafeMutablePointer<AudioBufferList>,
        requestedBytes: Int
    ) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard buffers.count == channelCount else { return false }
        for channel in 0..<channelCount {
            guard buffers[channel].mNumberChannels == 1 else {
                return false
            }
            if buffers[channel].mData == nil {
                let fallback = channel == 0 ? outputLeft : outputRight
                guard let fallback else { return false }
                buffers[channel].mData = UnsafeMutableRawPointer(fallback)
                buffers[channel].mDataByteSize = UInt32(requestedBytes)
            } else if Int(buffers[channel].mDataByteSize) < requestedBytes {
                return false
            }
            buffers[channel].mDataByteSize = UInt32(requestedBytes)
        }
        return true
    }

    private func publish(_ report: FixedEQRenderReport) {
        beginTelemetryUpdate()
        renderStatus.store(noErr, ordering: .relaxed)
        renderFault.store(FixedEQAudioUnitRenderFault.none.rawValue, ordering: .relaxed)
        processResult.store(report.processResult.rawValue, ordering: .relaxed)
        originalLatched.store(processor.isOriginalLatched, ordering: .relaxed)
        if let generation = report.appliedGeneration {
            hasAppliedGeneration.store(true, ordering: .relaxed)
            // Publish the generation last. A control-side acquire of a newly observed
            // generation also observes the result, latch, and fault stores above.
            appliedGeneration.store(generation, ordering: .releasing)
        }
        endTelemetryUpdate()
    }

    private func failSilently(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        requestedBytes: Int,
        fault: FixedEQAudioUnitRenderFault,
        status: OSStatus,
        latchAgain: Bool = true,
        appliedGeneration: UInt64? = nil
    ) -> AUAudioUnitStatus {
        if latchAgain {
            processor.latchOriginal()
        }
        publishFault(
            fault,
            status: status,
            appliedGeneration: appliedGeneration
        )
        zeroOutput(outputData, requestedBytes: requestedBytes)
        actionFlags.pointee.insert(Self.outputIsSilence)
        return noErr
    }

    private func failHostContract(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        requestedBytes: Int,
        fault: FixedEQAudioUnitRenderFault,
        status: OSStatus
    ) -> AUAudioUnitStatus {
        processor.latchOriginal()
        publishFault(fault, status: status)
        zeroOutput(outputData, requestedBytes: requestedBytes)
        actionFlags.pointee.insert(Self.outputIsSilence)
        return status
    }

    private func publishFault(
        _ fault: FixedEQAudioUnitRenderFault,
        status: OSStatus,
        appliedGeneration generation: UInt64? = nil
    ) {
        beginTelemetryUpdate()
        renderStatus.store(status, ordering: .relaxed)
        renderFault.store(fault.rawValue, ordering: .relaxed)
        processResult.store(FixedEQProcessResult.invalidBuffers.rawValue, ordering: .relaxed)
        originalLatched.store(true, ordering: .relaxed)
        if let generation {
            hasAppliedGeneration.store(true, ordering: .relaxed)
            appliedGeneration.store(generation, ordering: .releasing)
        }
        endTelemetryUpdate()
    }

    /// Render is the sole telemetry writer. The acq-rel odd transition prevents any
    /// payload store from moving before readers can observe that an update is active.
    private func beginTelemetryUpdate() {
        _ = telemetrySequence.wrappingAdd(1, ordering: .acquiringAndReleasing)
    }

    /// Publish the completed payload before returning the sequence to an even value.
    private func endTelemetryUpdate() {
        _ = telemetrySequence.wrappingAdd(1, ordering: .releasing)
    }

    private func zeroOutput(
        _ outputData: UnsafeMutablePointer<AudioBufferList>,
        requestedBytes: Int
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            memset(data, 0, min(requestedBytes, Int(buffer.mDataByteSize)))
        }
    }
}
