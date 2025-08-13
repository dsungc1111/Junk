// Swift 코드에 추가할 함수들

// 1. MP4 비디오를 320p 또는 720p로 변환
func resizeVideo(to resolution: String) async {
    guard let videoURL else {
        await MainActor.run {
            self.errorMessage = "비디오가 선택되지 않았습니다"
        }
        return
    }
    
    print("🎬 비디오 해상도 변환 시작: \(resolution)")
    
    await MainActor.run {
        self.isUploading = true
        self.errorMessage = nil
    }
    
    do {
        // 비디오 파일 데이터 로드
        let videoData = try Data(contentsOf: videoURL)
        
        // Multipart form data 생성
        let boundary = UUID().uuidString
        var body = Data()
        
        // 비디오 파일 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"video.mp4\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 해상도 설정 (320p 또는 720p)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"resolution\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(resolution)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // URLRequest 생성
        let endpoint = "\(serverURL)/resize/video"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "InvalidURL", code: 0)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ResizeError", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool,
           success,
           let outputUrl = json["outputUrl"] as? String {
            
            let fullUrl = "\(serverURL)\(outputUrl)"
            
            // Firebase에 업로드
            await uploadConvertedVideoToFirebase(from: URL(string: fullUrl)!, format: "mp4-\(resolution)", metadata: nil)
            
            print("✅ 해상도 변환 성공: \(fullUrl)")
        }
        
    } catch {
        await MainActor.run {
            self.errorMessage = "해상도 변환 실패: \(error.localizedDescription)"
            self.isUploading = false
        }
    }
}

// 2. MP4 비디오를 GIF로 변환
func convertVideoToGIF() async {
    guard let videoURL else {
        await MainActor.run {
            self.errorMessage = "비디오가 선택되지 않았습니다"
        }
        return
    }
    
    print("🎬 비디오 → GIF 변환 시작")
    
    await MainActor.run {
        self.isUploading = true
        self.errorMessage = nil
    }
    
    do {
        // 비디오 파일 데이터 로드
        let videoData = try Data(contentsOf: videoURL)
        
        // Multipart form data 생성
        let boundary = UUID().uuidString
        var body = Data()
        
        // 비디오 파일 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"video.mp4\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        // GIF 변환 옵션
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"fps\"\r\n\r\n".data(using: .utf8)!)
        body.append("10\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"scale\"\r\n\r\n".data(using: .utf8)!)
        body.append("320\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"duration\"\r\n\r\n".data(using: .utf8)!)
        body.append("10\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // URLRequest 생성
        let endpoint = "\(serverURL)/convert/to-gif"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "InvalidURL", code: 0)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GIFError", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool,
           success,
           let outputUrl = json["outputUrl"] as? String {
            
            let fullUrl = "\(serverURL)\(outputUrl)"
            
            // GIF 다운로드 후 Firebase에 업로드
            let (gifData, _) = try await URLSession.shared.data(from: URL(string: fullUrl)!)
            
            // Firebase Realtime Database에 저장
            let base64String = gifData.base64EncodedString()
            let ref = Database.database().reference()
            let gifId = UUID().uuidString
            let gifRef = ref.child("converted_gifs").child(gifId)
            
            let gifObject: [String: Any] = [
                "data": base64String,
                "timestamp": ServerValue.timestamp(),
                "size": gifData.count,
                "fromVideo": true
            ]
            
            gifRef.setValue(gifObject) { error, _ in
                Task { @MainActor in
                    if let error = error {
                        self.errorMessage = "GIF 저장 실패: \(error.localizedDescription)"
                        self.isUploading = false
                    } else {
                        self.convertedVideoURL = URL(string: fullUrl)
                        self.isUploading = false
                        self.errorMessage = "GIF 변환 완료! ID: \(gifId)"
                    }
                }
            }
            
            print("✅ GIF 변환 성공: \(fullUrl)")
        }
        
    } catch {
        await MainActor.run {
            self.errorMessage = "GIF 변환 실패: \(error.localizedDescription)"
            self.isUploading = false
        }
    }
}

// SwiftUI View에 추가할 버튼들
struct VideoConversionButtons: View {
    let convertTestView: ConvertTestView
    
    var body: some View {
        Group {
            // 비디오가 선택된 경우 표시할 버튼들
            if convertTestView.mediaType == .video {
                HStack(spacing: 10) {
                    // 해상도 변환 버튼
                    Button("320p 변환") {
                        Task {
                            await convertTestView.resizeVideo(to: "320p")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(convertTestView.isUploading)
                    
                    Button("720p 변환") {
                        Task {
                            await convertTestView.resizeVideo(to: "720p")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(convertTestView.isUploading)
                    
                    // GIF 변환 버튼
                    Button("GIF로 변환") {
                        Task {
                            await convertTestView.convertVideoToGIF()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(convertTestView.isUploading)
                }
            }
            
            // GIF가 선택된 경우 표시할 버튼들 (기존)
            if convertTestView.mediaType == .gif {
                HStack(spacing: 10) {
                    Button("MP4로 변환") {
                        Task {
                            await convertTestView.convertToVideo(format: "mp4")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(convertTestView.isUploading)
                    
                    Button("WebM으로 변환") {
                        Task {
                            await convertTestView.convertToVideo(format: "webm")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(convertTestView.isUploading)
                }
            }
        }
    }
}