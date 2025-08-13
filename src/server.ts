import express from 'express';
import multer from 'multer';
import cors from 'cors';
import path from 'path';
import fs from 'fs/promises';
import { FFmpegConverter } from './ffmpegConverter';
import { firebaseService } from './firebaseService';
import WebSocket from 'ws';
import { createServer } from 'http';

const app = express();
const server = createServer(app);
const wss = new WebSocket.Server({ server });

const PORT = process.env.PORT || 3000;
const UPLOAD_DIR = './uploads';
const OUTPUT_DIR = './outputs';

const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    await fs.mkdir(UPLOAD_DIR, { recursive: true });
    cb(null, UPLOAD_DIR);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({ 
  storage: storage,
  limits: {
    fileSize: 500 * 1024 * 1024
  }
});

app.use(cors());
app.use(express.json());
app.use('/outputs', express.static(OUTPUT_DIR));
app.use(express.static('.'));

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.post('/convert/video', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { format = 'mp4', videoCodec, audioCodec, resolution, fps, videoBitrate, audioBitrate, preset, crf } = req.body;
  
  const inputPath = req.file.path;
  const outputFileName = `${path.parse(req.file.filename).name}-converted.${format}`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  const startTime = Date.now();

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    
    const wsClients = Array.from(wss.clients).filter(client => client.readyState === WebSocket.OPEN);
    
    converter.on('progress', (progress) => {
      wsClients.forEach(client => {
        client.send(JSON.stringify({
          type: 'progress',
          data: progress,
          filename: req.file?.filename
        }));
      });
    });

    await converter.convertVideo(format, {
      videoCodec,
      audioCodec,
      resolution,
      fps: fps ? parseInt(fps) : undefined,
      videoBitrate,
      audioBitrate,
      preset,
      crf: crf ? parseInt(crf) : undefined
    });

    const metadata = await converter.getMetadata();
    const conversionTime = (Date.now() - startTime) / 1000; // seconds

    res.json({
      success: true,
      outputUrl: `/outputs/${outputFileName}`,
      metadata: {
        duration: metadata.format.duration,
        size: metadata.format.size,
        bitrate: metadata.format.bit_rate,
        format: metadata.format.format_name,
        conversionTime: conversionTime
      }
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Conversion error:', error);
    res.status(500).json({ error: 'Conversion failed', details: error });
  }
});

app.post('/extract/audio', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { format = 'mp3' } = req.body;
  
  const inputPath = req.file.path;
  const outputFileName = `${path.parse(req.file.filename).name}-audio.${format}`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    await converter.extractAudio(format as 'mp3' | 'aac' | 'wav' | 'flac');

    res.json({
      success: true,
      outputUrl: `/outputs/${outputFileName}`
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Audio extraction error:', error);
    res.status(500).json({ error: 'Audio extraction failed', details: error });
  }
});

// MP4 해상도 변환 엔드포인트 (320p, 720p)
app.post('/resize/video', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { resolution = '720p' } = req.body; // 320p 또는 720p
  
  const inputPath = req.file.path;
  const outputFileName = `${path.parse(req.file.filename).name}-${resolution}.mp4`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  const startTime = Date.now();

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    
    // 해상도 설정
    let resolutionString: string;
    let videoBitrate: string;
    
    if (resolution === '144p') {
      resolutionString = '256x144';
      videoBitrate = '200k';
    } else if (resolution === '320p') {
      resolutionString = '480x320';
      videoBitrate = '500k';
    } else if (resolution === '720p') {
      resolutionString = '1280x720';
      videoBitrate = '2500k';
    } else {
      return res.status(400).json({ error: 'Invalid resolution. Use 144p, 320p or 720p' });
    }

    const wsClients = Array.from(wss.clients).filter(client => client.readyState === WebSocket.OPEN);
    
    converter.on('progress', (progress) => {
      wsClients.forEach(client => {
        client.send(JSON.stringify({
          type: 'progress',
          data: progress,
          filename: req.file?.filename
        }));
      });
    });

    await converter.convertVideo('mp4', {
      resolution: resolutionString,
      videoBitrate: videoBitrate,
      audioCodec: 'aac',
      videoCodec: 'libx264',
      preset: 'fast',
      crf: 23
    });

    const metadata = await converter.getMetadata();
    const conversionTime = (Date.now() - startTime) / 1000; // seconds

    res.json({
      success: true,
      outputUrl: `/outputs/${outputFileName}`,
      metadata: {
        duration: metadata.format.duration,
        size: metadata.format.size,
        bitrate: metadata.format.bit_rate,
        format: metadata.format.format_name,
        resolution: resolution,
        conversionTime: conversionTime
      }
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Resize error:', error);
    res.status(500).json({ error: 'Resize failed', details: error });
  }
});

// MP4를 GIF로 변환하는 엔드포인트
app.post('/convert/to-gif', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { 
    fps = '10',
    scale = '320',
    duration = '10' // 최대 10초
  } = req.body;
  
  const inputPath = req.file.path;
  const outputFileName = `${path.parse(req.file.filename).name}.gif`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  const startTime = Date.now();

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    
    // GIF 변환을 위한 특별한 설정
    await new Promise<void>((resolve, reject) => {
      const ffmpeg = require('fluent-ffmpeg');
      
      ffmpeg(inputPath)
        .outputOptions([
          `-vf fps=${fps},scale=${scale}:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse`,
          `-t ${duration}` // 최대 지속 시간
        ])
        .on('start', (commandLine: string) => {
          console.log('Converting to GIF:', commandLine);
        })
        .on('progress', (progress: any) => {
          const wsClients = Array.from(wss.clients).filter(client => client.readyState === WebSocket.OPEN);
          wsClients.forEach(client => {
            client.send(JSON.stringify({
              type: 'progress',
              data: progress,
              filename: req.file?.filename
            }));
          });
        })
        .on('end', () => {
          console.log('✓ GIF conversion completed');
          resolve();
        })
        .on('error', (err: any) => {
          console.error('Error converting to GIF:', err);
          reject(err);
        })
        .save(outputPath);
    });

    // 파일 크기 확인
    const stats = await fs.stat(outputPath);
    const conversionTime = (Date.now() - startTime) / 1000; // seconds

    res.json({
      success: true,
      outputUrl: `/outputs/${outputFileName}`,
      metadata: {
        size: stats.size,
        format: 'gif',
        fps: parseInt(fps),
        scale: parseInt(scale),
        conversionTime: conversionTime
      }
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('GIF conversion error:', error);
    res.status(500).json({ error: 'GIF conversion failed', details: error });
  }
});

app.post('/thumbnail', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { timestamps, size } = req.body;
  
  const inputPath = req.file.path;
  const thumbnailFileName = `${path.parse(req.file.filename).name}-thumbnail.png`;
  const thumbnailPath = path.join(OUTPUT_DIR, thumbnailFileName);

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, thumbnailPath);
    await converter.generateThumbnail({
      timestamps: timestamps ? timestamps.split(',') : ['50%'],
      filename: thumbnailFileName,
      folder: OUTPUT_DIR,
      size: size || '640x480'
    });

    res.json({
      success: true,
      thumbnailUrl: `/outputs/${thumbnailFileName}`
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Thumbnail generation error:', error);
    res.status(500).json({ error: 'Thumbnail generation failed', details: error });
  }
});

app.post('/trim', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { startTime, duration } = req.body;
  
  if (!startTime || !duration) {
    return res.status(400).json({ error: 'startTime and duration are required' });
  }

  const inputPath = req.file.path;
  const outputFileName = `${path.parse(req.file.filename).name}-trimmed.mp4`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    await converter.trim(startTime, duration);

    res.json({
      success: true,
      outputUrl: `/outputs/${outputFileName}`
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Trim error:', error);
    res.status(500).json({ error: 'Video trim failed', details: error });
  }
});

app.post('/watermark', upload.fields([
  { name: 'video', maxCount: 1 },
  { name: 'watermark', maxCount: 1 }
]), async (req, res) => {
  const files = req.files as { [fieldname: string]: Express.Multer.File[] };
  
  if (!files.video || !files.watermark) {
    return res.status(400).json({ error: 'Both video and watermark files are required' });
  }

  const { position = 'bottomright' } = req.body;
  
  const videoPath = files.video[0].path;
  const watermarkPath = files.watermark[0].path;
  const outputFileName = `${path.parse(files.video[0].filename).name}-watermarked.mp4`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(videoPath, outputPath);
    await converter.addWatermark(watermarkPath, position as 'topleft' | 'topright' | 'bottomleft' | 'bottomright');

    res.json({
      success: true,
      outputUrl: `/outputs/${outputFileName}`
    });

    setTimeout(async () => {
      try {
        await fs.unlink(videoPath);
        await fs.unlink(watermarkPath);
      } catch (err) {
        console.error('Error cleaning up files:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Watermark error:', error);
    res.status(500).json({ error: 'Adding watermark failed', details: error });
  }
});

app.post('/hls', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { segmentDuration = 10 } = req.body;
  
  const inputPath = req.file.path;
  const hlsDir = path.join(OUTPUT_DIR, 'hls', path.parse(req.file.filename).name);
  const outputPath = path.join(hlsDir, 'output.m3u8');

  try {
    await fs.mkdir(hlsDir, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    await converter.convertToHLS(parseInt(segmentDuration));

    res.json({
      success: true,
      playlistUrl: `/outputs/hls/${path.parse(req.file.filename).name}/output.m3u8`
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('HLS conversion error:', error);
    res.status(500).json({ error: 'HLS conversion failed', details: error });
  }
});

app.post('/metadata', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const inputPath = req.file.path;

  try {
    const converter = new FFmpegConverter(inputPath, '');
    const metadata = await converter.getMetadata();

    res.json({
      success: true,
      metadata: {
        format: metadata.format,
        streams: metadata.streams.map(stream => ({
          codec_type: stream.codec_type,
          codec_name: stream.codec_name,
          width: stream.width,
          height: stream.height,
          duration: stream.duration,
          bit_rate: stream.bit_rate,
          fps: stream.r_frame_rate
        }))
      }
    });

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
      } catch (err) {
        console.error('Error cleaning up input file:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Metadata extraction error:', error);
    res.status(500).json({ error: 'Metadata extraction failed', details: error });
  }
});

// Firebase 업로드 기능이 있는 새로운 엔드포인트
app.post('/convert/video-firebase', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { 
    format = 'mp4', 
    videoCodec, 
    audioCodec, 
    resolution, 
    fps, 
    videoBitrate, 
    audioBitrate, 
    preset, 
    crf,
    userId = 'anonymous',
    uploadToFirebase = 'true'
  } = req.body;
  
  const inputPath = req.file.path;
  const outputFileName = `${path.parse(req.file.filename).name}-converted.${format}`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    
    const wsClients = Array.from(wss.clients).filter(client => client.readyState === WebSocket.OPEN);
    
    converter.on('progress', (progress) => {
      wsClients.forEach(client => {
        client.send(JSON.stringify({
          type: 'progress',
          data: progress,
          filename: req.file?.filename
        }));
      });
    });

    await converter.convertVideo(format, {
      videoCodec,
      audioCodec,
      resolution,
      fps: fps ? parseInt(fps) : undefined,
      videoBitrate,
      audioBitrate,
      preset,
      crf: crf ? parseInt(crf) : undefined
    });

    let responseData: any = {
      success: true,
      localUrl: `/outputs/${outputFileName}`
    };

    // Firebase에 업로드
    if (uploadToFirebase === 'true') {
      const firebasePath = firebaseService.generateStoragePath(
        userId,
        'video',
        outputFileName
      );
      
      const firebaseUrl = await firebaseService.uploadFile(
        outputPath,
        firebasePath,
        {
          originalName: req.file.originalname,
          convertedFormat: format,
          userId: userId
        }
      );
      
      responseData.firebaseUrl = firebaseUrl;
      responseData.firebasePath = firebasePath;
    }

    const metadata = await converter.getMetadata();
    responseData.metadata = {
      duration: metadata.format.duration,
      size: metadata.format.size,
      bitrate: metadata.format.bit_rate,
      format: metadata.format.format_name
    };

    res.json(responseData);

    // 임시 파일 정리
    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
        if (uploadToFirebase === 'true') {
          await fs.unlink(outputPath);
        }
      } catch (err) {
        console.error('Error cleaning up files:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Conversion error:', error);
    res.status(500).json({ error: 'Conversion failed', details: error });
  }
});

app.post('/extract/audio-firebase', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const { 
    format = 'mp3',
    userId = 'anonymous',
    uploadToFirebase = 'true'
  } = req.body;
  
  const inputPath = req.file.path;
  const outputFileName = `${path.parse(req.file.filename).name}-audio.${format}`;
  const outputPath = path.join(OUTPUT_DIR, outputFileName);

  try {
    await fs.mkdir(OUTPUT_DIR, { recursive: true });
    
    const converter = new FFmpegConverter(inputPath, outputPath);
    await converter.extractAudio(format as 'mp3' | 'aac' | 'wav' | 'flac');

    let responseData: any = {
      success: true,
      localUrl: `/outputs/${outputFileName}`
    };

    // Firebase에 업로드
    if (uploadToFirebase === 'true') {
      const firebasePath = firebaseService.generateStoragePath(
        userId,
        'audio',
        outputFileName
      );
      
      const firebaseUrl = await firebaseService.uploadFile(
        outputPath,
        firebasePath,
        {
          originalName: req.file.originalname,
          audioFormat: format,
          userId: userId
        }
      );
      
      responseData.firebaseUrl = firebaseUrl;
      responseData.firebasePath = firebasePath;
    }

    res.json(responseData);

    setTimeout(async () => {
      try {
        await fs.unlink(inputPath);
        if (uploadToFirebase === 'true') {
          await fs.unlink(outputPath);
        }
      } catch (err) {
        console.error('Error cleaning up files:', err);
      }
    }, 60000);

  } catch (error) {
    console.error('Audio extraction error:', error);
    res.status(500).json({ error: 'Audio extraction failed', details: error });
  }
});

wss.on('connection', (ws) => {
  console.log('WebSocket client connected');
  
  ws.on('message', (message) => {
    console.log('Received:', message.toString());
  });

  ws.on('close', () => {
    console.log('WebSocket client disconnected');
  });

  ws.send(JSON.stringify({ type: 'connected', message: 'Connected to FFmpeg server' }));
});

// Firebase 초기화
async function initializeServices() {
  try {
    // Firebase 서비스 계정 키 파일이 있는지 확인
    const serviceAccountPath = './firebase-service-account.json';
    try {
      await fs.access(serviceAccountPath);
      await firebaseService.initialize(serviceAccountPath);
    } catch {
      // 파일이 없으면 환경 변수 사용
      console.log('Firebase 서비스 계정 파일이 없습니다. 환경 변수를 사용합니다.');
      await firebaseService.initialize();
    }
  } catch (error) {
    console.error('Firebase 초기화 실패:', error);
    console.log('Firebase 기능을 사용하려면 설정이 필요합니다.');
  }
}

server.listen(PORT, async () => {
  await initializeServices();
  
  console.log(`FFmpeg Media Server running on http://localhost:${PORT}`);
  console.log('Available endpoints:');
  console.log('  POST /convert/video - Convert video format');
  console.log('  POST /convert/video-firebase - Convert and upload to Firebase');
  console.log('  POST /convert/to-gif - Convert MP4 to GIF');
  console.log('  POST /resize/video - Resize video (320p, 720p)');
  console.log('  POST /extract/audio - Extract audio from video');
  console.log('  POST /extract/audio-firebase - Extract audio and upload to Firebase');
  console.log('  POST /thumbnail - Generate video thumbnail');
  console.log('  POST /trim - Trim video');
  console.log('  POST /watermark - Add watermark to video');
  console.log('  POST /hls - Convert to HLS streaming format');
  console.log('  POST /metadata - Get video metadata');
  console.log('  WebSocket support on ws://localhost:' + PORT);
});