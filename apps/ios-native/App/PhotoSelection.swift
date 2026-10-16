import PhotosUI
import SwiftUI
import Foundation

enum PhotoSelection {
    typealias Completion = @Sendable (Result<PhotoAttachment?, Error>) -> Void

    static func load(_ item: PhotosPickerItem) async throws -> PhotoAttachment {
        try await load { completion in
            item.loadTransferable(type: PhotoTransfer.self) { response in
                switch response {
                case .success(let transfer?):
                    switch transfer.result {
                    case .success(let photo): completion(.success(photo))
                    case .failure(let error): completion(.failure(error))
                    }
                case .success(nil): completion(.success(nil))
                case .failure(let error): completion(.failure(error))
                }
            }
        }
    }
    static func load(transfer: @Sendable (_ completion: @escaping Completion) -> Progress) async throws -> PhotoAttachment {
        let (events, continuation) = AsyncThrowingStream<PhotoAttachment, Error>.makeStream()
        let progress = transfer { result in
            switch result {
            case .success(let photo?): continuation.yield(photo); continuation.finish()
            case .success(nil): continuation.finish(throwing: ClientError("This photo could not be loaded. Choose it again or attach it from Files."))
            case .failure(let error): continuation.finish(throwing: error)
            }
        }
        return try await withTaskCancellationHandler {
            for try await photo in events { try Task.checkCancellation(); return photo }
            throw CancellationError()
        } onCancel: {
            progress.cancel()
            continuation.finish(throwing: CancellationError())
        }
    }
}
