import ffmpeg from 'fluent-ffmpeg';
import path from 'path';
import fs from 'fs/promises';
import { EventEmitter } from 'events';

export interface ConversionOptions {
  videoBitrate?: string;
  audioBitrate?: string;
  videoCodec?: string;
  audioCodec?: string;
  fps?: number;
  resolution?: string;
  preset?: 'ultrafast' | 'superfast' | 'veryfast' | 'faster' | 'fast' | 'medium' | 'slow' | 'slower' | 'veryslow';
  crf?: number;
}

export interface ThumbnailOptions {
  timestamps?: string[];
  filename?: string;
  folder?: string;
  size?: string;
}

export class FFmpegConverter extends EventEmitter {
  private inputPath: string;
  private outputPath: string;

  constructor(inputPath: string, outputPath: string) {
    super();
    this.inputPath = inputPath;
    this.outputPath = outputPath;
  }

  async convertVideo(format: string, options: ConversionOptions = {}): Promise<void> {
    await this.ensureOutputDirectory();
    
    return new Promise((resolve, reject) => {
      let command = ffmpeg(this.inputPath);

      if (options.videoCodec) {
        command = command.videoCodec(options.videoCodec);
      }

      if (options.audioCodec) {
        command = command.audioCodec(options.audioCodec);
      }

      if (options.videoBitrate) {
        command = command.videoBitrate(options.videoBitrate);
      }

      if (options.audioBitrate) {
        command = command.audioBitrate(options.audioBitrate);
      }

      if (options.fps) {
        command = command.fps(options.fps);
      }

      if (options.resolution) {
        command = command.size(options.resolution);
      }

      if (options.preset) {
        command = command.outputOptions(`-preset ${options.preset}`);
      }

      if (options.crf) {
        command = command.outputOptions(`-crf ${options.crf}`);
      }

      command
        .on('start', (commandLine) => {
          console.log('FFmpeg command:', commandLine);
          this.emit('start', commandLine);
        })
        .on('progress', (progress) => {
          console.log(`Processing: ${progress.percent?.toFixed(2)}% done`);
          this.emit('progress', progress);
        })
        .on('end', () => {
          console.log('✓ Video conversion completed');
          this.emit('end');
          resolve();
        })
        .on('error', (err) => {
          console.error('Error during conversion:', err);
          this.emit('error', err);
          reject(err);
        })
        .save(this.outputPath);
    });
  }

  async extractAudio(format: 'mp3' | 'aac' | 'wav' | 'flac' = 'mp3'): Promise<void> {
    await this.ensureOutputDirectory();
    
    return new Promise((resolve, reject) => {
      ffmpeg(this.inputPath)
        .noVideo()
        .audioCodec(format === 'aac' ? 'aac' : format === 'mp3' ? 'libmp3lame' : 'copy')
        .on('start', (commandLine) => {
          console.log('Extracting audio:', commandLine);
          this.emit('start', commandLine);
        })
        .on('progress', (progress) => {
          this.emit('progress', progress);
        })
        .on('end', () => {
          console.log('✓ Audio extraction completed');
          this.emit('end');
          resolve();
        })
        .on('error', (err) => {
          console.error('Error extracting audio:', err);
          this.emit('error', err);
          reject(err);
        })
        .save(this.outputPath);
    });
  }

  async generateThumbnail(options: ThumbnailOptions = {}): Promise<void> {
    const folder = options.folder || path.dirname(this.outputPath);
    await this.ensureDirectory(folder);
    
    return new Promise((resolve, reject) => {
      ffmpeg(this.inputPath)
        .screenshots({
          timestamps: options.timestamps || ['50%'],
          filename: options.filename || 'thumbnail.png',
          folder: folder,
          size: options.size || '320x240'
        })
        .on('end', () => {
          console.log('✓ Thumbnail generated');
          this.emit('thumbnailGenerated');
          resolve();
        })
        .on('error', (err) => {
          console.error('Error generating thumbnail:', err);
          this.emit('error', err);
          reject(err);
        });
    });
  }

  async getMetadata(): Promise<ffmpeg.FfprobeData> {
    return new Promise((resolve, reject) => {
      ffmpeg.ffprobe(this.inputPath, (err, metadata) => {
        if (err) {
          reject(err);
        } else {
          resolve(metadata);
        }
      });
    });
  }

  async trim(startTime: string, duration: string): Promise<void> {
    await this.ensureOutputDirectory();
    
    return new Promise((resolve, reject) => {
      ffmpeg(this.inputPath)
        .setStartTime(startTime)
        .setDuration(duration)
        .on('start', (commandLine) => {
          console.log('Trimming video:', commandLine);
          this.emit('start', commandLine);
        })
        .on('progress', (progress) => {
          this.emit('progress', progress);
        })
        .on('end', () => {
          console.log('✓ Video trimmed successfully');
          this.emit('end');
          resolve();
        })
        .on('error', (err) => {
          console.error('Error trimming video:', err);
          this.emit('error', err);
          reject(err);
        })
        .save(this.outputPath);
    });
  }

  async concatenate(inputFiles: string[]): Promise<void> {
    await this.ensureOutputDirectory();
    
    return new Promise((resolve, reject) => {
      const command = ffmpeg();
      
      inputFiles.forEach(file => {
        command.input(file);
      });

      command
        .on('start', (commandLine) => {
          console.log('Concatenating videos:', commandLine);
          this.emit('start', commandLine);
        })
        .on('progress', (progress) => {
          this.emit('progress', progress);
        })
        .on('end', () => {
          console.log('✓ Videos concatenated successfully');
          this.emit('end');
          resolve();
        })
        .on('error', (err) => {
          console.error('Error concatenating videos:', err);
          this.emit('error', err);
          reject(err);
        })
        .mergeToFile(this.outputPath, './temp/');
    });
  }

  async addWatermark(watermarkPath: string, position: 'topleft' | 'topright' | 'bottomleft' | 'bottomright' = 'bottomright'): Promise<void> {
    await this.ensureOutputDirectory();
    
    const positions = {
      topleft: '10:10',
      topright: 'main_w-overlay_w-10:10',
      bottomleft: '10:main_h-overlay_h-10',
      bottomright: 'main_w-overlay_w-10:main_h-overlay_h-10'
    };
    
    return new Promise((resolve, reject) => {
      ffmpeg(this.inputPath)
        .input(watermarkPath)
        .complexFilter([
          `[0:v][1:v] overlay=${positions[position]}`
        ])
        .on('start', (commandLine) => {
          console.log('Adding watermark:', commandLine);
          this.emit('start', commandLine);
        })
        .on('progress', (progress) => {
          this.emit('progress', progress);
        })
        .on('end', () => {
          console.log('✓ Watermark added successfully');
          this.emit('end');
          resolve();
        })
        .on('error', (err) => {
          console.error('Error adding watermark:', err);
          this.emit('error', err);
          reject(err);
        })
        .save(this.outputPath);
    });
  }

  async convertToHLS(segmentDuration: number = 10): Promise<void> {
    const outputDir = path.dirname(this.outputPath);
    const playlistName = path.basename(this.outputPath, path.extname(this.outputPath)) + '.m3u8';
    await this.ensureDirectory(outputDir);
    
    return new Promise((resolve, reject) => {
      ffmpeg(this.inputPath)
        .outputOptions([
          '-codec: copy',
          '-start_number 0',
          '-hls_time ' + segmentDuration,
          '-hls_list_size 0',
          '-f hls'
        ])
        .on('start', (commandLine) => {
          console.log('Converting to HLS:', commandLine);
          this.emit('start', commandLine);
        })
        .on('progress', (progress) => {
          this.emit('progress', progress);
        })
        .on('end', () => {
          console.log('✓ HLS conversion completed');
          this.emit('end');
          resolve();
        })
        .on('error', (err) => {
          console.error('Error converting to HLS:', err);
          this.emit('error', err);
          reject(err);
        })
        .save(path.join(outputDir, playlistName));
    });
  }

  private async ensureOutputDirectory(): Promise<void> {
    const dir = path.dirname(this.outputPath);
    await this.ensureDirectory(dir);
  }

  private async ensureDirectory(dir: string): Promise<void> {
    try {
      await fs.access(dir);
    } catch {
      await fs.mkdir(dir, { recursive: true });
    }
  }
}

export class FFmpegStreamProcessor {
  static createLiveStream(inputUrl: string, outputUrl: string, options: ConversionOptions = {}): ffmpeg.FfmpegCommand {
    let command = ffmpeg(inputUrl)
      .inputOptions(['-re'])
      .outputOptions([
        '-c:v libx264',
        '-preset veryfast',
        '-tune zerolatency',
        '-c:a aac',
        '-ar 44100',
        '-f flv'
      ]);

    if (options.videoBitrate) {
      command = command.videoBitrate(options.videoBitrate);
    }

    if (options.audioBitrate) {
      command = command.audioBitrate(options.audioBitrate);
    }

    if (options.resolution) {
      command = command.size(options.resolution);
    }

    return command.output(outputUrl);
  }

  static async detectSceneChanges(inputPath: string): Promise<number[]> {
    return new Promise((resolve, reject) => {
      const scenes: number[] = [];
      
      ffmpeg(inputPath)
        .outputOptions([
          '-vf', 'select=gt(scene\\,0.4)',
          '-f', 'null'
        ])
        .on('stderr', (stderrLine) => {
          const match = stderrLine.match(/pts_time:(\d+\.\d+)/);
          if (match) {
            scenes.push(parseFloat(match[1]));
          }
        })
        .on('end', () => {
          resolve(scenes);
        })
        .on('error', (err) => {
          reject(err);
        })
        .save('/dev/null');
    });
  }
}