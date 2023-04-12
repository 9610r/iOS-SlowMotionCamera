//
//  RecordPresenter.swift
//  SloiwMotionCamera
//
//  Created by 中島 on 2023/03/28.
//

import Foundation
import AVFoundation

// presenter to view
protocol RecordPresenterOutput: AnyObject {
    func cameraSetupComplete(session: AVCaptureSession)
    func onSetStopWatchTime()
}

// view to presenter
protocol RecordPresenterInput: AnyObject {
    // 録画状態の変更通知
    func onRecordState(state: RecordState)
    func onChangeCameraFocus(point: CGPoint)
    func onChangedPinchGesture(state: Bool, pinchZoomScale: Float)
}

class RecordPresenter {

    private weak var view: RecordPresenterOutput?
    private var model: RecordModelInput?
    
    init(view: RecordPresenterOutput) {
        self.view = view
        self.model = RecordModel(presenter: self)
    }
}

extension RecordPresenter: RecordPresenterInput {
    func onChangeCameraFocus(point: CGPoint) {
        self.model?.onChangeCameraFocus(point: point)
    }
    
    func onRecordState(state: RecordState) {
        
    }
    
    func onChangedPinchGesture(state: Bool, pinchZoomScale: Float) {
        self.model?.onChangeCameraZoom(state: state, pinchZoomScale: pinchZoomScale)
    }
}

extension RecordPresenter: RecordModelOutput {
    func onCompIntialize(session: AVCaptureSession) {
        self.view?.cameraSetupComplete(session: session)
    }
}
