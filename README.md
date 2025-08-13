# FFmpeg Media Converter

FFmpeg을 사용한 미디어 파일 변환 및 처리 서비스입니다.

## 기능

- **비디오 변환**: 다양한 포맷 간 변환 (MP4, MOV, AVI 등)
- **해상도 조정**: 144p, 360p, 480p, 720p 등 다양한 해상도 지원
- **GIF 변환**: GIF를 MP4로 변환
- **동시 처리**: 여러 파일의 동시 변환 지원
- **크로스 플랫폼**: Node.js, Swift, Kotlin 클라이언트 지원

## 기술 스택

- **백엔드**: Node.js, TypeScript, Express
- **FFmpeg**: 미디어 처리 엔진
- **클라이언트**: 
  - Swift (iOS)
  - Kotlin (Android)
  - HTML/JavaScript (웹)

## 설치 및 실행

### 요구사항

- Node.js 16+
- FFmpeg 설치
- npm 또는 yarn

### 설치

```bash
# 의존성 설치
npm install

# TypeScript 컴파일
npm run build

# 서버 실행
npm start
```

### FFmpeg 설치

#### macOS
```bash
brew install ffmpeg
```

#### Ubuntu/Debian
```bash
sudo apt update
sudo apt install ffmpeg
```

#### Windows
[FFmpeg 공식 사이트](https://ffmpeg.org/download.html)에서 다운로드

## 사용법

### API 엔드포인트

- `POST /convert` - 미디어 파일 변환
- `POST /resize` - 비디오 해상도 조정
- `GET /status/:id` - 변환 상태 확인

### 예시

```bash
# 파일 변환
curl -X POST -F "file=@video.mp4" http://localhost:3000/convert

# 해상도 조정
curl -X POST -F "file=@video.mp4" -F "resolution=720p" http://localhost:3000/resize
```

## 프로젝트 구조

```
ConvertTest/
├── src/                    # TypeScript 소스 코드
│   ├── server.ts          # Express 서버
│   ├── ffmpegConverter.ts # FFmpeg 변환 로직
│   ├── firebaseService.ts # Firebase 연동
│   └── index.ts           # 진입점
├── ios-client/            # iOS Swift 클라이언트
├── kotlin/                # Android Kotlin 클라이언트
├── outputs/               # 변환된 파일 출력
├── uploads/               # 업로드된 파일
└── test-*.html           # 테스트 페이지
```

## 개발

### 빌드

```bash
# 개발 모드
npm run dev

# 프로덕션 빌드
npm run build
```

### 테스트

```bash
# 테스트 실행
npm test

# 테스트 페이지 열기
open test-client.html
```

## 라이선스

MIT License

## 기여

이슈나 풀 리퀘스트를 통해 기여해주세요.

## 연락처

- GitHub: [UnicornCoffeeGallery](https://github.com/UnicornCoffeeGallery)
