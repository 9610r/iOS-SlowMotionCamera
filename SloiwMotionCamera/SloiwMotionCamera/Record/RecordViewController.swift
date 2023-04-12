//
//  RecordViewController.swift
//  SloiwMotionCamera
//
//  Created by 中島 on 2023/03/28.
//

import UIKit
import AVFoundation

class RecordViewController: UIViewController, UIGestureRecognizerDelegate {
    
    
    @IBOutlet weak var cameraPreview: UIImageView!
    private var forcusBoxView = UIView()
    
    private var presenter: RecordPresenterInput?
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var pinchGestureRecognizer: UIPinchGestureRecognizer = UIPinchGestureRecognizer()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        self.presenter = RecordPresenter(view: self)
        
        // フォーカス用の黄色い枠線を作成
        forcusBoxView.frame = self.cameraPreview.frame
        forcusBoxView.layer.borderWidth = 1
        forcusBoxView.layer.borderColor = UIColor.systemYellow.cgColor
        forcusBoxView.isHidden = true
        cameraPreview.addSubview(forcusBoxView)
        
        // タップとピンチインアウトのジェスチャーを初期化
        let tapGestureRecognizer:UITapGestureRecognizer = UITapGestureRecognizer(
                       target: self,
                       action: #selector(self.tapped(_:)))
        tapGestureRecognizer.cancelsTouchesInView = false
        tapGestureRecognizer.delegate = self
        
        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchedGesture(_:)))
        pinchGestureRecognizer.delegate = self
        
        self.view.addGestureRecognizer(tapGestureRecognizer)
        self.view.addGestureRecognizer(pinchGestureRecognizer)
        
    }
    
    /// ピンチイン/ピンチアウト処理
    /// - Parameter gestureRecgnizer:
    @objc func  pinchedGesture(_ recognizer: UIPinchGestureRecognizer) {
        var state = false
        // ピンチの度合い
        let pinchZoomScale = Float(recognizer.scale)
        print(pinchZoomScale)
        // 画面から指が離れたとき、stateをオンにして送信
        if recognizer.state == .ended {
            state = true
        }
        self.presenter?.onChangedPinchGesture(state: state, pinchZoomScale: pinchZoomScale)
    }
    
    @objc func tapped(_ sender: UITapGestureRecognizer){
        let pointInView = sender.location(in: sender.view)
        // タップした箇所にフォーカスを行う
        guard let pointInCamera = previewLayer?.captureDevicePointConverted(fromLayerPoint: pointInView) else { return }
        // フォーカスの変更通知
        self.presenter?.onChangeCameraFocus(point: pointInCamera)
        
        // タップしたポイントを中心に表示する
        forcusBoxView.center = pointInView
        forcusBoxView.isHidden = false
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.5, delay: 0, options: []) {
            self.forcusBoxView.frame = CGRect(  x: pointInView.x - (self.view.bounds.width * 0.075),
                                            y: pointInView.y - (self.view.bounds.width * 0.075),
                                            width: (self.view.bounds.width * 0.15),
                                            height: (self.view.bounds.width * 0.15))
        } completion: { (UIViewAnimatingPosition) in
            // 0.4秒 待機してからフォーカスviewを非表示にする
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { (Timer) in
                self.forcusBoxView.isHidden = true
                self.forcusBoxView.frame.size = CGSize(width: self.view.bounds.width * 0.3, height: self.view.bounds.width * 0.3)
            }
        }
    }

}

extension RecordViewController: RecordPresenterOutput {
    func cameraSetupComplete(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        self.previewLayer?.frame = self.cameraPreview.frame
        self.cameraPreview.layer.insertSublayer(self.previewLayer!, at: 0)
    }
    
    func onSetStopWatchTime() {
        
    }
    
    
    
    
}
