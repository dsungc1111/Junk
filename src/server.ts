import express from 'express';
import multer from 'multer';
import cors from 'cors';
import path from 'path';
import fs from 'fs/promises';
import { FFmpegConverter } from './ffmpegConverter';
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

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'test-client.html'));
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/ads.txt', (req, res) => {
  res.type('text/plain');
  res.sendFile(path.join(__dirname, '..', 'ads.txt'));
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
    const conversionTime = (Date.now() - startTime) / 1000;

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
    }, 300000);

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
    }, 300000);

  } catch (error) {
    console.error('Audio extraction error:', error);
    res.status(500).json({ error: 'Audio extraction failed', details: error });
  }
});

// WebSocket 연결 처리
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

server.listen(Number(PORT), '0.0.0.0', () => {
  console.log(`FFmpeg Media Server running on http://0.0.0.0:${PORT}`);
  console.log('Available endpoints:');
  console.log('  GET / - Web client interface');
  console.log('  GET /health - Health check');
  console.log('  POST /convert/video - Convert video format');
  console.log('  POST /extract/audio - Extract audio from video');
  console.log(`  WebSocket support on ws://0.0.0.0:${PORT}`);
});