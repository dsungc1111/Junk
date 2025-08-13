import SwiftUI
import Firebase
import FirebaseStorage
import PhotosUI
import UIKit

struct ConvertTestView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var downloadURL: URL?
    @State private var gifData: Data?
    @State private var convertedVideoURL: URL?
    @State private var errorMessage: String?
    
    // 서버 URL (실제 IP로 변경 필요)
    let serverURL = "http://192.168.1.7:3000"
    
    var body: some View {
        VStack(spacing: 20) {
            // GIF 미리보기
            if let gifData {
                GIFImage(data: gifData)
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // 변환된 비디오 URL 표시
            if let convertedVideoURL {
                VStack {
                    Text("변환 완료!")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    Text(convertedVideoURL.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal)
                }
            }
            
            // 에러 메시지
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            // GIF 선택 버튼
            PhotosPicker("GIF 선택", selection: $selectedItem, matching: .images)
                .buttonStyle(.borderedProminent)
                .onChange(of: selectedItem) { newItem in
                    Task {
                        await loadGIF(from: newItem)
                    }
                }
            
            // 변환 옵션들
            HStack(spacing: 15) {
                // GIF를 MP4로 변환
                Button("MP4로 변환") {
                    Task {
                        await convertToVideo(format: "mp4")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(gifData == nil || isUploading)
                
                // GIF를 WebM으로 변환
                Button("WebM으로 변환") {
                    Task {
                        await convertToVideo(format: "webm")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(gifData == nil || isUploading)
            }
            
            // 진행률 표시
            if isUploading {
                VStack {
                    ProgressView(value: uploadProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)
                    
                    Text("변환 중... \(Int(uploadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    func loadGIF(from item: PhotosPickerItem?) async {
        guard let item else { return }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    self.gifData = data
                    self.convertedVideoURL = nil
                    self.errorMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "GIF 로드 실패: \(error.localizedDescription)"
            }
        }
    }
    
    func convertToVideo(format: String) async {
        guard let gifData else {
            await MainActor.run {
                self.errorMessage = "GIF 데이터가 없습니다"
            }
            return
        }
        
        await MainActor.run {
            self.isUploading = true
            self.uploadProgress = 0
            self.errorMessage = nil
        }
        
        // 파일 크기 체크 (100MB 제한)
        let maxSize = 100 * 1024 * 1024
        guard gifData.count < maxSize else {
            await MainActor.run {
                self.errorMessage = "파일이 너무 큽니다. 100MB 이하만 가능합니다."
                self.isUploading = false
            }
            return
        }
        
        // Multipart form data 생성
        let boundary = UUID().uuidString
        var body = Data()
        
        // GIF 파일 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"animation.gif\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/gif\r\n\r\n".data(using: .utf8)!)
        body.append(gifData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 출력 형식 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"format\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(format)\r\n".data(using: .utf8)!)
        
        // 해상도 설정 (옵션)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"resolution\"\r\n\r\n".data(using: .utf8)!)
        body.append("640x480\r\n".data(using: .utf8)!)
        
        // 사용자 ID (Firebase Auth 사용 시 실제 UID로 변경)
        let userId = Auth.auth().currentUser?.uid ?? "anonymous"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)
        
        // Firebase 업로드 옵션
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"uploadToFirebase\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // URLRequest 생성
        guard let url = URL(string: "\(serverURL)/convert/video-firebase") else {
            await MainActor.run {
                self.errorMessage = "잘못된 서버 URL"
                self.isUploading = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300 // 5분 타임아웃
        
        // WebSocket 연결 (진행률 모니터링)
        connectWebSocket()
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NSError(domain: "ConversionError", code: 0, 
                            userInfo: [NSLocalizedDescriptionKey: "서버 응답 오류"])
            }
            
            let result = try JSONDecoder().decode(ConversionResponse.self, from: data)
            
            await MainActor.run {
                self.convertedVideoURL = URL(string: result.firebaseUrl ?? result.localUrl)
                self.isUploading = false
                self.uploadProgress = 1.0
                
                // Firebase Realtime Database에 메타데이터 저장
                if let firebaseUrl = result.firebaseUrl {
                    saveMetadataToDatabase(
                        url: firebaseUrl,
                        format: format,
                        metadata: result.metadata
                    )
                }
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "변환 실패: \(error.localizedDescription)"
                self.isUploading = false
            }
        }
    }
    
    func connectWebSocket() {
        guard let url = URL(string: "ws://192.168.1.7:3000") else { return }
        
        let session = URLSession(configuration: .default)
        let webSocketTask = session.webSocketTask(with: url)
        webSocketTask.resume()
        
        func receiveMessage() {
            webSocketTask.receive { [weak webSocketTask] result in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = json["type"] as? String,
                           type == "progress",
                           let progressData = json["data"] as? [String: Any],
                           let percent = progressData["percent"] as? Double {
                            
                            Task { @MainActor in
                                self.uploadProgress = percent / 100.0
                            }
                        }
                    default:
                        break
                    }
                    
                    receiveMessage() // 계속 메시지 수신
                    
                case .failure(let error):
                    print("WebSocket error: \(error)")
                    webSocketTask?.cancel(with: .goingAway, reason: nil)
                }
            }
        }
        
        receiveMessage()
    }
    
    func saveMetadataToDatabase(url: String, format: String, metadata: VideoMetadata?) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let ref = Database.database().reference()
        let videoRef = ref.child("users").child(userId).child("videos").childByAutoId()
        
        var videoData: [String: Any] = [
            "url": url,
            "format": format,
            "timestamp": ServerValue.timestamp(),
            "type": "converted_from_gif"
        ]
        
        if let metadata = metadata {
            videoData["duration"] = metadata.duration ?? 0
            videoData["size"] = metadata.size ?? 0
            videoData["bitrate"] = metadata.bitrate ?? 0
        }
        
        videoRef.setValue(videoData) { error, _ in
            if let error = error {
                print("메타데이터 저장 실패: \(error)")
            } else {
                print("메타데이터 저장 완료")
            }
        }
    }
}

// Response 모델들
struct ConversionResponse: Codable {
    let success: Bool
    let localUrl: String
    let firebaseUrl: String?
    let firebasePath: String?
    let metadata: VideoMetadata?
}

struct VideoMetadata: Codable {
    let duration: Double?
    let size: Int?
    let bitrate: Int?
    let format: String?
}

// GIF 이미지 뷰 (기존 코드 그대로)
struct GIFImage: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        
        if let image = UIImage.gifImageWithData(data) {
            imageView.image = image
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        if let image = UIImage.gifImageWithData(data) {
            uiView.image = image
        }
    }
}

extension UIImage {
    static func gifImageWithData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        let count = CGImageSourceGetCount(source)
        var images = [UIImage]()
        var duration = 0.0
        
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                continue
            }
            
            let frameDuration = UIImage.frameDurationAtIndex(i, source: source)
            duration += frameDuration
            
            images.append(UIImage(cgImage: cgImage))
        }
        
        if images.count == 1 {
            return images.first
        } else {
            return UIImage.animatedImage(with: images, duration: duration)
        }
    }
    
    private static func frameDurationAtIndex(_ index: Int, source: CGImageSource) -> Double {
        var frameDuration = 0.1
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return frameDuration
        }
        
        if let unclampedDelayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double {
            frameDuration = unclampedDelayTime
        } else if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double {
            frameDuration = delayTime
        }
        
        if frameDuration < 0.011 {
            frameDuration = 0.1
        }
        
        return frameDuration
    }
}

#Preview {
    ConvertTestView()
}