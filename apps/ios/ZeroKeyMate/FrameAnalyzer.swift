@preconcurrency import AVFoundation
import Foundation
import Vision

struct FrameObservation:Sendable {
    let capturedAt:Date
    let labels:[String]
    let faceCount:Int
    let horizontalFocus:Double?
    let verticalFocus:Double?
    var faceDetectionAvailable=true
    var description:String {
        let objects=labels.joined(separator:", ")
        return "Approximate local observations: \(faceCount) face region(s); image labels: \(objects). Not identity or a statement of certainty."
    }
}

/// Buffers are consumed only on this serial queue; no frame is stored or exported.
final class FrameAnalyzer:NSObject,AVCaptureVideoDataOutputSampleBufferDelegate,@unchecked Sendable {
    let queue=DispatchQueue(label:"com.zerokeymate.local-vision",qos:.userInitiated)
    private let lock=NSLock()
    private var callback:(@Sendable (FrameObservation)->Void)?
    private var enabled=false
    private var lastTime:TimeInterval=0
    private var lastLabels:TimeInterval=0
    private var labels:[String]=[]
    private var generation:UInt64=0
    func configure(enabled:Bool,callback:(@Sendable (FrameObservation)->Void)?=nil){
        lock.lock();generation &+= 1;self.enabled=enabled;if let callback{self.callback=callback};lock.unlock()
    }
    func captureOutput(_ output:AVCaptureOutput,didOutput sampleBuffer:CMSampleBuffer,from connection:AVCaptureConnection){
        lock.lock();let allowed=enabled;let sink=callback;let token=generation;lock.unlock()
        let now=Date()
        guard allowed,let sink,now.timeIntervalSince1970-lastTime>=1.0/12,
              let pixelBuffer=CMSampleBufferGetImageBuffer(sampleBuffer) else{return}
        lastTime=now.timeIntervalSince1970
        let faces=VNDetectFaceRectanglesRequest()
        do {
            let handler=VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up)
            // Face updates must not depend on slow or failed image classification.
            try handler.perform([faces])
            let detections=faces.results ?? []
            let primary=detections.max{$0.boundingBox.width*$0.boundingBox.height < $1.boundingBox.width*$1.boundingBox.height}
            let focus=primary.map{Double($0.boundingBox.midX)*2-1}
            lock.lock();let stillAllowed=enabled && generation==token;lock.unlock()
            if stillAllowed{sink(FrameObservation(capturedAt:now,labels:labels,faceCount:detections.count,horizontalFocus:focus,verticalFocus:primary.map{1-Double($0.boundingBox.midY)*2}))}
            if now.timeIntervalSince1970-lastLabels>=2 {
                lastLabels=now.timeIntervalSince1970
                let objects=VNClassifyImageRequest()
                if (try? handler.perform([objects])) != nil {
                    labels=Array((objects.results ?? []).filter{$0.confidence>=0.65}.prefix(3).map(\.identifier))
                }
            }
        }catch{
            lock.lock();let stillAllowed=enabled && generation==token;lock.unlock()
            if stillAllowed {
                sink(FrameObservation(capturedAt:now,labels:[],faceCount:0,horizontalFocus:nil,verticalFocus:nil,faceDetectionAvailable:false))
            }
        }
    }
}
