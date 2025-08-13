import Foundation
import UIKit

class FFmpegAPIClient {
    private let baseURL: String
    private let session: URLSession
    
    init(baseURL: String = "http://localhost:3000") {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }
    
    // MARK: - Video Conversion
    func convertVideo(
        videoData: Data,
        filename: String,
        format: String = "mp4",
        options: VideoConversionOptions? = nil,
        progressHandler: @escaping (Double) -> Void,
        completion: @escaping (Result<ConversionResponse, Error>) -> Void
    ) {
        let url = URL(string: "\(baseURL)/convert/video")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add video file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add format parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"format\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(format)\r\n".data(using: .utf8)!)
        
        // Add optional parameters
        if let options = options {
            if let resolution = options.resolution {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"resolution\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(resolution)\r\n".data(using: .utf8)!)
            }
            
            if let fps = options.fps {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"fps\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(fps)\r\n".data(using: .utf8)!)
            }
            
            if let videoBitrate = options.videoBitrate {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"videoBitrate\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(videoBitrate)\r\n".data(using: .utf8)!)
            }
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        // Setup WebSocket for progress updates
        setupWebSocketForProgress(progressHandler: progressHandler)
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            
            do {
                let conversionResponse = try JSONDecoder().decode(ConversionResponse.self, from: data)
                completion(.success(conversionResponse))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Audio Extraction
    func extractAudio(
        from videoData: Data,
        filename: String,
        format: AudioFormat = .mp3,
        completion: @escaping (Result<AudioExtractionResponse, Error>) -> Void
    ) {
        let url = URL(string: "\(baseURL)/extract/audio")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"format\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(format.rawValue)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(AudioExtractionResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Thumbnail Generation
    func generateThumbnail(
        from videoData: Data,
        filename: String,
        size: String = "640x480",
        timestamps: [String] = ["50%"],
        completion: @escaping (Result<ThumbnailResponse, Error>) -> Void
    ) {
        let url = URL(string: "\(baseURL)/thumbnail")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"size\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(size)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"timestamps\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(timestamps.joined(separator: ","))\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(ThumbnailResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Video Trimming
    func trimVideo(
        videoData: Data,
        filename: String,
        startTime: String,
        duration: String,
        completion: @escaping (Result<TrimResponse, Error>) -> Void
    ) {
        let url = URL(string: "\(baseURL)/trim")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"startTime\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(startTime)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"duration\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(duration)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(TrimResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Download Converted File
    func downloadFile(
        from urlPath: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let url = URL(string: "\(baseURL)\(urlPath)")!
        
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            
            completion(.success(data))
        }
        
        task.resume()
    }
    
    // MARK: - WebSocket Support
    private var webSocketTask: URLSessionWebSocketTask?
    
    private func setupWebSocketForProgress(progressHandler: @escaping (Double) -> Void) {
        let wsURL = URL(string: "ws://localhost:3000")!
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        
        receiveWebSocketMessage { [weak self] message in
            guard let data = message.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "progress",
                  let progressData = json["data"] as? [String: Any],
                  let percent = progressData["percent"] as? Double else {
                return
            }
            
            DispatchQueue.main.async {
                progressHandler(percent)
            }
        }
    }
    
    private func receiveWebSocketMessage(completion: @escaping (String) -> Void) {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    completion(text)
                    self?.receiveWebSocketMessage(completion: completion)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        completion(text)
                    }
                    self?.receiveWebSocketMessage(completion: completion)
                @unknown default:
                    break
                }
            case .failure(let error):
                print("WebSocket error: \(error)")
            }
        }
    }
}

// MARK: - Data Models
struct VideoConversionOptions {
    let resolution: String?
    let fps: Int?
    let videoBitrate: String?
    let audioBitrate: String?
    let videoCodec: String?
    let audioCodec: String?
    let preset: String?
    let crf: Int?
}

enum AudioFormat: String {
    case mp3, aac, wav, flac
}

struct ConversionResponse: Codable {
    let success: Bool
    let outputUrl: String
    let metadata: VideoMetadata?
}

struct AudioExtractionResponse: Codable {
    let success: Bool
    let outputUrl: String
}

struct ThumbnailResponse: Codable {
    let success: Bool
    let thumbnailUrl: String
}

struct TrimResponse: Codable {
    let success: Bool
    let outputUrl: String
}

struct VideoMetadata: Codable {
    let duration: Double?
    let size: Int?
    let bitrate: Int?
    let format: String?
}

enum APIError: Error {
    case noData
    case invalidResponse
}

// MARK: - Usage Example
class VideoConverterViewController: UIViewController {
    let apiClient = FFmpegAPIClient(baseURL: "http://your-server-ip:3000")
    
    func convertVideoExample() {
        guard let videoURL = Bundle.main.url(forResource: "sample", withExtension: "mov"),
              let videoData = try? Data(contentsOf: videoURL) else {
            return
        }
        
        let options = VideoConversionOptions(
            resolution: "1280x720",
            fps: 30,
            videoBitrate: "2M",
            audioBitrate: "128k",
            videoCodec: "libx264",
            audioCodec: "aac",
            preset: "fast",
            crf: 23
        )
        
        apiClient.convertVideo(
            videoData: videoData,
            filename: "video.mov",
            format: "mp4",
            options: options,
            progressHandler: { progress in
                print("Conversion progress: \(progress)%")
            },
            completion: { result in
                switch result {
                case .success(let response):
                    print("Video converted successfully: \(response.outputUrl)")
                    self.downloadConvertedVideo(from: response.outputUrl)
                case .failure(let error):
                    print("Conversion failed: \(error)")
                }
            }
        )
    }
    
    func downloadConvertedVideo(from urlPath: String) {
        apiClient.downloadFile(from: urlPath) { result in
            switch result {
            case .success(let data):
                // Save or use the converted video data
                self.saveVideoToPhotos(data: data)
            case .failure(let error):
                print("Download failed: \(error)")
            }
        }
    }
    
    func saveVideoToPhotos(data: Data) {
        // Implementation to save video to Photos app
    }
}