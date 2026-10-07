import Foundation
import MateCore

/// An ephemeral weights-only download. State is protected by lock because
/// URLSession delegate callbacks and task cancellation can arrive concurrently.
final class LocalWeightTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination:URL
    private let expectedBytes:Int64
    private let progress:@Sendable (Double)->Void
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Void,Error>?
    private var task:URLSessionDownloadTask?
    private var cancelled=false
    private var failure:Error?
    private init(destination:URL,expectedBytes:Int64,progress:@escaping @Sendable (Double)->Void) {
        self.destination=destination;self.expectedBytes=expectedBytes;self.progress=progress
    }
    static func download(_ url:URL,to destination:URL,expectedBytes:Int64,
                         progress:@escaping @Sendable (Double)->Void) async throws {
        guard permitted(url) else {throw LocalSearchFailure.download}
        let transfer=LocalWeightTransfer(destination:destination,expectedBytes:expectedBytes,progress:progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let config=URLSessionConfiguration.ephemeral
                config.urlCredentialStorage=nil;config.httpCookieStorage=nil
                config.httpShouldSetCookies=false;config.urlCache=nil
                config.timeoutIntervalForRequest=60;config.timeoutIntervalForResource=1_800
                let session=URLSession(configuration:config,delegate:transfer,delegateQueue:nil)
                let task=session.downloadTask(with:url)
                transfer.lock.lock()
                transfer.continuation=continuation;transfer.task=task
                let cancelled=transfer.cancelled
                transfer.lock.unlock()
                task.resume()
                if cancelled {task.cancel()}
            }
        } onCancel: { transfer.cancel() }
    }
    private func cancel() {
        lock.lock();cancelled=true;let task=task;lock.unlock();task?.cancel()
    }
    static func permitted(_ url:URL)->Bool {
        guard url.scheme == "https",url.user == nil,url.password == nil,
              url.port == nil || url.port == 443,let host=url.host?.lowercased() else {return false}
        return host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host.hasSuffix(".hf.co")
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        completionHandler(request.url.map(Self.permitted) == true ? request:nil)
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,
                    totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if totalBytesWritten>expectedBytes || (totalBytesExpectedToWrite>0 && totalBytesExpectedToWrite != expectedBytes) {
            lock.lock();failure=LocalSearchFailure.integrity;lock.unlock();downloadTask.cancel()
        } else {progress(min(0.99,Double(totalBytesWritten)/Double(expectedBytes)))}
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
        do {
            guard let response=downloadTask.response as? HTTPURLResponse,response.statusCode == 200,
                  response.url.map(Self.permitted) == true else {throw LocalSearchFailure.download}
            try FileManager.default.moveItem(at:location,to:destination)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:destination.path)
        } catch {lock.lock();failure=error;lock.unlock()}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        lock.lock()
        let continuation=continuation;self.continuation=nil;self.task=nil
        let result:Error?=cancelled ? CancellationError() : (failure ?? error)
        lock.unlock()
        if let result {continuation?.resume(throwing:result)} else {continuation?.resume()}
        session.finishTasksAndInvalidate()
    }
}
