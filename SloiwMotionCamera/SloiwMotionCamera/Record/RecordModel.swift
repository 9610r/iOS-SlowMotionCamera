//
//  RecordModel.swift
//  SloiwMotionCamera
//
//  Created by 中島 on 2023/03/28.
//

import Foundation
import AVFoundation
import Photos

enum RecordState {
    case STOP
    case START
    case LOADING
    case ERROR
}

struct RecordDeviceInfo {
    var currentCamera: AVCaptureDevice?
    var currentMicrophone: AVCaptureDevice?
    var videoSettings: [String : Any]?
    var currentFps: Double = 30.0
    var currentFrameSize: Double = 0
    var recordTime: Float = 0
    
    init(currentCamera: AVCaptureDevice? = nil, currentMicrophone: AVCaptureDevice? = nil, videoSettings: [String : Any]?, currentFps: Double, currentFrameSize: Double, recordTime: Float) {
        self.currentCamera = currentCamera
        self.currentMicrophone = currentMicrophone
        self.videoSettings = videoSettings
        self.currentFps = currentFps
        self.currentFrameSize = currentFrameSize
        self.recordTime = recordTime
    }
}

struct CameraZoomScale: Comparable {
    var currentDevice: AVCaptureDevice.DeviceType
    var zoomScale: Double
    
    // より広角なカメラを大きい値として扱う
    static func < (lhs: CameraZoomScale, rhs: CameraZoomScale) -> Bool {
        let telephoto: AVCaptureDevice.DeviceType = .builtInTelephotoCamera
        let wide: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        let ultra: AVCaptureDevice.DeviceType = .builtInUltraWideCamera
        
        // 右辺のカメラが左辺より広角なカメラであればtrueを返す
        // カメラが同一の場合は左辺のズームの数値が右辺より大きければtrue
        switch lhs.currentDevice {
        case telephoto:
            switch rhs.currentDevice {
            case .builtInTelephotoCamera:
                return lhs.zoomScale > rhs.zoomScale
            case .builtInWideAngleCamera, .builtInUltraWideCamera:
                return true
            default:
                return false
            }
        case wide:
            switch rhs.currentDevice {
            case .builtInTelephotoCamera:
                return false
            case .builtInWideAngleCamera:
                return lhs.zoomScale > rhs.zoomScale
            case .builtInUltraWideCamera:
                return true
            default:
                return false
            }
        case ultra:
            switch rhs.currentDevice {
            case .builtInTelephotoCamera, .builtInWideAngleCamera:
                return false
            case .builtInUltraWideCamera:
                return lhs.zoomScale > rhs.zoomScale
            default:
                return false
            }
        default:
            return false
        }
    }
    
    static func deviceName(_ data: CameraZoomScale)-> String {
        switch data.currentDevice {
        case .builtInTelephotoCamera:
            return "望遠カメラ"
        case .builtInWideAngleCamera:
            return "広角カメラ"
        case .builtInUltraWideCamera:
            return "超広角カメラ"
        default:
            return "不明のカメラ"
        }
    }
    
    static func deviceDefaultZoomValue(_ data: CameraZoomScale)-> Double {
        switch data.currentDevice {
        case .builtInTelephotoCamera:
            return 3.0
        case .builtInWideAngleCamera:
            return 1.0
        case .builtInUltraWideCamera:
            return 0.5
        default:
            return 1.0
        }
    }
    
}

// Model to Presenter
protocol RecordModelOutput: AnyObject {
    func onCompIntialize(session: AVCaptureSession)
    
}

// Presenter to Model
protocol RecordModelInput: AnyObject {
    func changeRecordState(state: RecordState)
    func onChangeCameraFocus(point: CGPoint)
    func onChangeCameraZoom(state: Bool, pinchZoomScale: Float)
}


class RecordModel: NSObject {
    // Delegate
    private weak var presenter: RecordModelOutput?
    
    // MARK: 定数
    private let DEFAULT_FPS: Double = 30.0
    private let GESTURE_DEFAULT_VALUE: Float = 1.0
    
    // 変数
    private lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        return session
    }()
    private var videoDevice: AVCaptureDevice?
    private var videoDeviceInput: AVCaptureDeviceInput?
    let videoOutput = AVCaptureVideoDataOutput()
    var recordingURL: URL?
    var assetWriter: AVAssetWriter!
    var assetWriterInput: AVAssetWriterInput!
    var assetWriterInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    
    private var beforeZoomScale: Double = 0.0
    private var recordInfo: RecordDeviceInfo
    private var currentCamaraInfo: CameraZoomScale
    
    
    init(presenter: RecordModelOutput) {
        self.presenter = presenter
        self.recordInfo = RecordDeviceInfo(videoSettings: [:], currentFps: DEFAULT_FPS, currentFrameSize: 0, recordTime: 0.0)
        self.currentCamaraInfo = CameraZoomScale(currentDevice: .builtInWideAngleCamera, zoomScale: 1.0)
        
        super.init()
        // セッションを開始
        try? self.setupSession()
    }
    
    /// キャプチャデバイスのセッション開始処理
    func setupSession() throws{
        videoDevice = setupVideoDevice()
        guard let videoDevice = videoDevice else {throw AVCaptureError.deviceNotFound}
        let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        
        // セッションが動作中であれば停止させる
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        
        captureSession.beginConfiguration()
        
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
        }
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        let videoDataOutputQueue = DispatchQueue(label: "videoDataOutputQueue", qos: .userInteractive)
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        Task {
            captureSession.commitConfiguration()
            captureSession.startRunning()
        }
        // カメラのセットアップ完了を通知する
        self.presenter?.onCompIntialize(session: captureSession)
    }
    
    /// 映像撮影デバイスセットアップ
    func setupVideoDevice() -> AVCaptureDevice? {
        // デバイスタイプを列挙する
        // （配列の上から順に使用できるものが選択される為、優先度の高いものは上にする）
        let deviceTypes:[AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera
        ]
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: .back)
        let devices = deviceDiscoverySession.devices
        
        
        // 使用できるカメラがない場合は終了
        if let device = devices.first {
            self.recordInfo.currentCamera = device
            return device
        }else{
            fatalError("デバイスがありません.")
        }
    }
    
    func setupAudioDevice()-> AVCaptureDevice {
        let audioSession = AVCaptureDevice.DiscoverySession(deviceTypes:[AVCaptureDevice.DeviceType.builtInMicrophone],
                                                            mediaType:AVMediaType.audio,
                                                            position:AVCaptureDevice.Position.unspecified)
        
        if let audioDevice = audioSession.devices.first{
            self.recordInfo.currentMicrophone = audioDevice
            return audioDevice
        }else{
            fatalError("音声入力デバイスがありません。")
        }
        
    }
    
    private func resetupDevice(cameraDevice: AVCaptureDevice.DeviceType)-> Bool {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [cameraDevice], mediaType: AVMediaType.video, position: .back)
        let devices = deviceDiscoverySession.devices
        if devices.isEmpty {
            return false
        }
        self.videoDevice = devices.first
        // 動作中のセッションを閉じる
        self.captureSession.stopRunning()
        self.captureSession.inputs.forEach { input in
            self.captureSession.removeInput(input)
        }
        self.captureSession.outputs.forEach { output in
            self.captureSession.removeOutput(output)
        }
        
        try? self.setupSession()
        // カメラのセッションを開始する処理
        self.captureSession.startRunning()
        
        return true
    }
    
    
    // MARK: 録画開始・停止処理
    
    func startRecording() {
        
        // Start recording
        assetWriter.startWriting()
        captureSession.startRunning()
        assetWriter.startSession(atSourceTime: .zero)

    }
    
    func setupWritter() {
        // Set up the asset writer
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let date = dateFormatter.string(from: Date())
        let fileName = "\(date).mov"
        recordingURL = URL(fileURLWithPath: "\(documentsDirectory)/\(fileName)")
        do {
            assetWriter = try AVAssetWriter(outputURL: recordingURL!, fileType: .mov)
        } catch {
            print(error.localizedDescription)
            return
        }
        self.recordInfo.videoSettings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: self.recordInfo.videoSettings)
        assetWriterInput.expectsMediaDataInRealTime = true
        if assetWriter.canAdd(assetWriterInput) {
            assetWriter.add(assetWriterInput)
        }
        assetWriterInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
    }
    
    
    /// 録画を停止する
    func stopRecording() {
       // Stop recording
        assetWriterInput.markAsFinished()
        assetWriter.finishWriting {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.recordingURL!)
            }) { saved, error in
                if let error = error {
                    print(error.localizedDescription)
                } else {
                    print("動画を保存しました")
                }
            }
        }
        captureSession.stopRunning()
    }
    
    
    /// ズーム値を合算する
    /// - Parameters:
    ///   - currentZoom: 現在のズーム値
    ///   - pinchVal: ピンチの倍率
    func sumZoomVal<T>(_ currentZoom: inout T, _ pinchVal: T) where T: Numeric {
        currentZoom = currentZoom + pinchVal
    }
}

enum AVCaptureError: Error {
    case deviceNotFound
    case overMemory
}

extension RecordModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        // サンプルバッファを処理する
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
//        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
//        while !assetWriterInput.isReadyForMoreMediaData {
//            Thread.sleep(forTimeInterval: 0.01)
//        }
//        assetWriterInputPixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }
}

extension RecordModel: RecordModelInput {
    func changeRecordState(state: RecordState) {
        
    }
    
    /// タップしたカメラ座標にピントのフォーカスを行う
    /// - Parameter point: xy座標
    func onChangeCameraFocus(point: CGPoint) {
//        do {
            if let currentDevice = videoDevice {
                try? currentDevice.lockForConfiguration()
                // TODO: カメラ切り替え後にたまにフォーカスがサポートされていない状態になることがあるので、毎回使用可能か確認する。
                // フォーカスがサポートされているか確認する
                if currentDevice.isFocusModeSupported(.autoFocus) && currentDevice.isFocusPointOfInterestSupported {
                    currentDevice.focusPointOfInterest = point
                    currentDevice.focusMode = .autoFocus
                }
                // 露光の調整
                currentDevice.exposurePointOfInterest = point
                currentDevice.exposureMode = .autoExpose
                
                currentDevice.unlockForConfiguration()
                
            }else{
                print("デバイスがない")
            }
//        } catch let error {
//            debugPrint(error)
//        }
    }
    
    
    /// ピンチイン/ピンチアウト処理
    /// - Parameter gestureRecgnizer:
    func onChangeCameraZoom(state: Bool, pinchZoomScale: Float) {
        guard let camera = self.videoDevice else { return }
        defer { camera.unlockForConfiguration() }
        do {
            try camera.lockForConfiguration()
            let maxZoomScale: CGFloat = camera.maxAvailableVideoZoomFactor
            let minZoomScale: CGFloat = camera.minAvailableVideoZoomFactor
            // 現在のカメラのズーム度
            var currentZoomScale: CGFloat = camera.videoZoomFactor
            // ピンチアウトの時、前回のズームに今回のズーム-1を指定
            if pinchZoomScale > GESTURE_DEFAULT_VALUE {
                currentZoomScale = self.beforeZoomScale + CGFloat(pinchZoomScale-1)
            } else {
                currentZoomScale = self.beforeZoomScale - CGFloat(1 - pinchZoomScale) * self.beforeZoomScale
            }
            
            // 最小値より小さく、最大値より大きくならないようにする
            if currentZoomScale < minZoomScale {
                currentZoomScale = minZoomScale
            }else if currentZoomScale > maxZoomScale {
                currentZoomScale = maxZoomScale
            }
            camera.videoZoomFactor = currentZoomScale
            
            // FIXME: カメラを変更する
            let isChangedCamera = false
            
            // ズームが閾値を超えてカメラが切り替わると、flagがtrueになる
            if isChangedCamera {
                // カメラが切り替わったらジェスチャーをリセットして、ピンチジェスチャーの値をリセットする
                currentZoomScale = self.beforeZoomScale
                camera.videoZoomFactor = self.beforeZoomScale
//                self.presenter?.resetPinchGestureRecognizer()
            }else{
                // 画面から指が離れたときに保持している前回のズーム値を更新する
                if state {
                    self.beforeZoomScale = currentZoomScale
                }
            }
        } catch {
            // handle error
            return
        }
    }
    
}

extension AVCaptureDevice.DeviceType {
    
    func defaultZoomValue() -> Double {
        switch self {
        case .builtInTelephotoCamera:
            return 3.0
        case .builtInWideAngleCamera:
            return 1.0
        case .builtInUltraWideCamera:
            return 0.5
        default:
            return 1.0
        }
    }
    
    func zoomup()-> Self {
        switch self {
        case .builtInTelephotoCamera:
            return .builtInTelephotoCamera
        case .builtInWideAngleCamera:
            return .builtInTelephotoCamera
        case .builtInUltraWideCamera:
            return .builtInWideAngleCamera
        default:
            return .builtInWideAngleCamera
        }
    }
    
    func zoomback()-> Self {
        switch self {
        case .builtInTelephotoCamera:
            return .builtInWideAngleCamera
        case .builtInWideAngleCamera:
            return .builtInUltraWideCamera
        case .builtInUltraWideCamera:
            return .builtInUltraWideCamera
        default:
            return .builtInWideAngleCamera
        }
    }
}
