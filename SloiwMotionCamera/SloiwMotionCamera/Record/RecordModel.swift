//
//  RecordModel.swift
//  SloiwMotionCamera
//
//  Created by 中島 on 2023/03/28.
//

import Foundation
import AVFoundation
import Photos
import AssetsLibrary

enum RecordState {
    case STOP
    case START
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
    var fileURL: URL?
    
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
    func onChangeRecordState(state: RecordState)
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
    var fileOutput: AVCaptureMovieFileOutput!
    
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
        // ビデオをセッションのInputに追加.
        let videoInput = try! AVCaptureDeviceInput.init(device: setupVideoDevice()!)
        self.captureSession.addInput(videoInput)
        // オーディオをセッションに追加.
        let audioInput = try! AVCaptureDeviceInput.init(device: setupAudioDevice())
        self.captureSession.addInput(audioInput)
        // 動画の保存.
        self.fileOutput = AVCaptureMovieFileOutput()
        // ビデオ出力をOutputに追加.
        self.captureSession.addOutput(self.fileOutput)
        // バッググラウンドスレッドで実行
        Task {
            self.captureSession.startRunning()
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
        let datetimeString = self.getNowTimeString()
        // 保存用ファイル名とURL生成
        let tempDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory())
        self.recordingURL = tempDirectory.appendingPathComponent("\(datetimeString).mov")
        if let fileURL = self.recordingURL {
            print("録画開始 : \(fileURL.absoluteString)")
            fileOutput?.startRecording(to: fileURL, recordingDelegate: self)
            //        assetWriter.startSession(atSourceTime: .zero)
            print("START RECORD")
        }
    }
    
    /// 新しいファイル名を取得
    ///
    /// - Returns: ファイル名
    private func getNowTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmssSSSSSS"
        formatter.locale = NSLocale.system
        let datetime = formatter.string(from: Date())
        
        return String("\(datetime)")
    }
    
    /// 動画保存用のURLを取得する
    /// - Returns: URL
    private func createVideoUrl() -> URL? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "\(self.getNowTimeString()).mov"
        let videoUrl = documentsDirectory.appendingPathComponent(fileName)
        
        return videoUrl
    }
    /// 録画を停止する
    func stopRecording() {
        print("RECORD STOP")
        fileOutput.stopRecording()
    }
    
    /// 指定の FPS のフォーマットに切り替える (その FPS で最大解像度のフォーマットを選ぶ)
    /// - parameter desiredFps: 切り替えたい FPS (AVFrameRateRange.maxFrameRate が Double なので合わせる)
    private func switchFormat(desiredFps: Double) {
        let isRunning = captureSession.isRunning
        // セッションが動いていたら停止しておく
        if isRunning {
            captureSession.stopRunning()
        }
        var selectedFormat: AVCaptureDevice.Format! = nil
        var currentMaxWidth: Int32 = 0
        
        guard let videoDevice = self.videoDevice else {
            print("デバイスが見つかりません。")
            return
        }
        for format in videoDevice.formats {
            // フォーマット内の情報を抜き出す (for in と書いているが1つの format につき1つの range しかない)
            for range: AVFrameRateRange in format.videoSupportedFrameRateRanges {
                let description = format.formatDescription as CMFormatDescription
                // 幅と高さ情報を取得
                let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                let width = dimensions.width
                
                // フルHD以下で一番大きい解像度を取得
                if desiredFps == range.maxFrameRate && currentMaxWidth <= width && width <= 1920 {
                    selectedFormat = format
                    currentMaxWidth = width
                }
            }
        }
        
        // フォーマットが取得できていれば設定する
        if selectedFormat != nil {
            do {
                if let videoDevice = self.videoDevice {
                    try videoDevice.lockForConfiguration()  // ロックできなければ例外を投げる
                    videoDevice.activeFormat = selectedFormat
                    videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFps))
                    videoDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFps))
                    videoDevice.unlockForConfiguration()
                    // セッションが停止していたら再開する
                    if isRunning {
                        self.captureSession.startRunning()
                    }
                }
            }
            catch {
                print("フォーマット・フレームレートが指定できなかった : \(desiredFps) fps")
            }
        }
        else {
            print("フォーマットが取得できなかった : \(desiredFps) fps")
        }
    }
}

enum AVCaptureError: Error {
    case deviceNotFound
    case overMemory
    case notCompleteSaved
}

extension RecordModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    
    /*
     動画のキャプチャーが終わった時に呼ばれるメソッド.
     */
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard let currentVideoUrl = self.recordingURL else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: currentVideoUrl)
        }) { _, error in
            if let error = error {
                AVCaptureError.notCompleteSaved
                print("保存に失敗しました。")
            }
        }
        print("完了")
    }
}

extension RecordModel: RecordModelInput {
    func onChangeRecordState(state: RecordState) {
        switch state {
        case .STOP:
            self.stopRecording()
        case .START:
            self.startRecording()
        case .ERROR:
            return
        }
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
