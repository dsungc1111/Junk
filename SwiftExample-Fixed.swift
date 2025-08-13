import SwiftUI
import PhotosUI
import UIKit

struct ConvertTestView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var isConverting = false
    @State private var uploadProgress: Double = 0
    @State private var gifData: Data?
    @State private var convertedVideoURL: String?
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    
    // 서버 URL 설정 - 127.0.0.1 사용
    let serverURL = "http://127.0.0.1:3000"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("GIF to Video Converter")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // GIF 미리보기
            if let gifData {
                GIFImage(data: gifData)
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                Text("파일 크기: \(ByteCountFormatter.string(fromByteCount: Int64(gifData.count), countStyle: .file))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("GIF 선택")
                                .foregroundColor(.gray)
                        }
                    )
            }
            
            // GIF 선택 버튼
            PhotosPicker("GIF 파일 선택", selection: $selectedItem, matching: .images)
                .buttonStyle(.borderedProminent)
                .onChange(of: selectedItem) { newItem in
                    Task {
                        await loadGIF(from: newItem)
                    }
                }
            
            // 변환 버튼들
            HStack(spacing: 15) {
                Button(action: {
                    Task {
                        await convertVideo(format: "mp4")
                    }
                }) {
                    Label("MP4 변환", systemImage: "video.fill")
                }
                .buttonStyle(.bordered)
                .disabled(gifData == nil || isConverting)
                
                Button(action: {
                    Task {
                        await convertVideo(format: "webm")
                    }
                }) {
                    Label("WebM 변환", systemImage: "film.fill")
                }
                .buttonStyle(.bordered)
                .disabled(gifData == nil || isConverting)
            }
            
            // 오디오 추출 버튼
            Button(action: {
                Task {
                    await extractAudio()
                }
            }) {
                Label("오디오 추출 (MP3)", systemImage: "music.note")
            }
            .buttonStyle(.bordered)
            .disabled(gifData == nil || isConverting)
            
            // 진행 상태
            if isConverting {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("변환 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // 에러 메시지
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .alert("변환 완료!", isPresented: $showSuccessAlert) {
            if let convertedVideoURL {
                Button("URL 복사") {
                    UIPasteboard.general.string = convertedVideoURL
                }
            }
            Button("확인") { }
        } message: {
            if let convertedVideoURL {
                Text("변환된 파일:\n\(convertedVideoURL)")
            }
        }
    }
    
    func loadGIF(from item: PhotosPickerItem?) async {
        guard let item else { return }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    self.gifData = data
                    self.errorMessage = nil
                    self.convertedVideoURL = nil
                    print("📸 GIF 로드 완료: \(data.count) bytes")
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "GIF 로드 실패: \(error.localizedDescription)"
            }
        }
    }
    
    func convertVideo(format: String) async {
        guard let gifData else { return }
        
        print("🚀 변환 시작 - 형식: \(format)")
        print("📊 GIF 데이터 크기: \(gifData.count) bytes")
        
        await MainActor.run {
            self.isConverting = true
            self.errorMessage = nil
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
        
        // 출력 형식
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"format\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(format)\r\n".data(using: .utf8)!)
        
        // 옵션: 해상도 (GIF는 일반적으로 작으므로 원본 유지)
        // body.append("--\(boundary)\r\n".data(using: .utf8)!)
        // body.append("Content-Disposition: form-data; name=\"resolution\"\r\n\r\n".data(using: .utf8)!)
        // body.append("640x480\r\n".data(using: .utf8)!)
        
        // 옵션: FPS (GIF 기본값 사용)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"fps\"\r\n\r\n".data(using: .utf8)!)
        body.append("10\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // URLRequest 생성 - 일반 엔드포인트 사용 (Firebase 아님)
        let endpoint = "\(serverURL)/convert/video"  // ⚠️ 중요: /convert/video 사용
        print("🌐 서버 엔드포인트: \(endpoint)")
        
        guard let url = URL(string: endpoint) else {
            await MainActor.run {
                self.errorMessage = "잘못된 서버 URL"
                self.isConverting = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300 // 5분 타임아웃
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 서버 응답 상태 코드: \(httpResponse.statusCode)")
            }
            
            // 응답 데이터 출력
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 서버 응답: \(responseString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ 서버 오류 메시지: \(errorMessage)")
                throw NSError(domain: "ConversionError", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                            userInfo: [NSLocalizedDescriptionKey: "서버 오류 (\((response as? HTTPURLResponse)?.statusCode ?? 0)): \(errorMessage)"])
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool,
               success,
               let outputUrl = json["outputUrl"] as? String {
                
                let fullUrl = "\(serverURL)\(outputUrl)"
                
                await MainActor.run {
                    self.convertedVideoURL = fullUrl
                    self.isConverting = false
                    self.showSuccessAlert = true
                    print("✅ 변환 성공! URL: \(fullUrl)")
                }
                
            } else {
                throw NSError(domain: "ConversionError", code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "응답 파싱 실패"])
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "변환 실패: \(error.localizedDescription)"
                self.isConverting = false
                print("❌ 변환 실패: \(error)")
                print("❌ 오류 상세: \(error.localizedDescription)")
            }
        }
    }
    
    func extractAudio() async {
        guard let gifData else { return }
        
        await MainActor.run {
            self.isConverting = true
            self.errorMessage = nil
        }
        
        let boundary = UUID().uuidString
        var body = Data()
        
        // GIF 파일 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"animation.gif\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/gif\r\n\r\n".data(using: .utf8)!)
        body.append(gifData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 오디오 형식
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"format\"\r\n\r\n".data(using: .utf8)!)
        body.append("mp3\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // 일반 엔드포인트 사용
        guard let url = URL(string: "\(serverURL)/extract/audio") else {
            await MainActor.run {
                self.errorMessage = "잘못된 서버 URL"
                self.isConverting = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NSError(domain: "ExtractionError", code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "서버 응답 오류"])
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool,
               success,
               let outputUrl = json["outputUrl"] as? String {
                
                let fullUrl = "\(serverURL)\(outputUrl)"
                
                await MainActor.run {
                    self.convertedVideoURL = fullUrl
                    self.isConverting = false
                    self.showSuccessAlert = true
                }
                
                print("오디오 추출 성공! URL: \(fullUrl)")
                
            } else {
                throw NSError(domain: "ExtractionError", code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "응답 파싱 실패"])
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "오디오 추출 실패: \(error.localizedDescription)"
                self.isConverting = false
            }
        }
    }
}

// GIF 이미지 뷰 컴포넌트
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

// UIImage GIF Extension
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