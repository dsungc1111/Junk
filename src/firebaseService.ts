import * as admin from 'firebase-admin';
import fs from 'fs/promises';
import path from 'path';

export class FirebaseService {
  private storage?: admin.storage.Storage;
  private bucket?: any;
  private initialized: boolean = false;

  constructor() {
    // Firebase Admin SDK 초기화는 나중에 수행
  }

  async initialize(serviceAccountPath?: string) {
    if (this.initialized) return;

    try {
      if (serviceAccountPath) {
        // 서비스 계정 키 파일을 사용한 초기화
        const serviceAccount = JSON.parse(await fs.readFile(serviceAccountPath, 'utf8'));
        
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          storageBucket: `${serviceAccount.project_id}.appspot.com`
        });
      } else {
        // 환경 변수를 사용한 초기화
        const projectId = process.env.FIREBASE_PROJECT_ID;
        const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
        const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
        const storageBucket = process.env.FIREBASE_STORAGE_BUCKET;

        if (!projectId || !clientEmail || !privateKey || !storageBucket) {
          throw new Error('Firebase 환경 변수가 설정되지 않았습니다.');
        }

        admin.initializeApp({
          credential: admin.credential.cert({
            projectId,
            clientEmail,
            privateKey
          }),
          storageBucket
        });
      }

      this.storage = admin.storage();
      this.bucket = this.storage.bucket();
      this.initialized = true;
      console.log('✓ Firebase Storage 초기화 완료');
    } catch (error) {
      console.error('Firebase 초기화 실패:', error);
      throw error;
    }
  }

  async uploadFile(
    localFilePath: string,
    destinationPath: string,
    metadata?: { [key: string]: string }
  ): Promise<string> {
    if (!this.initialized || !this.bucket) {
      throw new Error('Firebase가 초기화되지 않았습니다.');
    }

    try {
      const fileName = path.basename(destinationPath);
      const file = this.bucket.file(destinationPath);

      // 파일 업로드
      await this.bucket.upload(localFilePath, {
        destination: destinationPath,
        metadata: {
          metadata: {
            ...metadata,
            uploadedAt: new Date().toISOString()
          }
        }
      });

      // 공개 URL 생성 (선택적)
      await file.makePublic();

      // 공개 URL 반환
      const publicUrl = `https://storage.googleapis.com/${this.bucket.name}/${destinationPath}`;
      
      console.log(`✓ Firebase Storage 업로드 완료: ${fileName}`);
      return publicUrl;
    } catch (error) {
      console.error('Firebase Storage 업로드 실패:', error);
      throw error;
    }
  }

  async uploadBuffer(
    buffer: Buffer,
    destinationPath: string,
    contentType: string,
    metadata?: { [key: string]: string }
  ): Promise<string> {
    if (!this.initialized || !this.bucket) {
      throw new Error('Firebase가 초기화되지 않았습니다.');
    }

    try {
      const file = this.bucket.file(destinationPath);
      
      const stream = file.createWriteStream({
        metadata: {
          contentType,
          metadata: {
            ...metadata,
            uploadedAt: new Date().toISOString()
          }
        }
      });

      return new Promise((resolve, reject) => {
        stream.on('error', reject);
        stream.on('finish', async () => {
          await file.makePublic();
          const publicUrl = `https://storage.googleapis.com/${this.bucket.name}/${destinationPath}`;
          console.log(`✓ Firebase Storage 업로드 완료: ${destinationPath}`);
          resolve(publicUrl);
        });
        
        stream.end(buffer);
      });
    } catch (error) {
      console.error('Firebase Storage 업로드 실패:', error);
      throw error;
    }
  }

  async deleteFile(filePath: string): Promise<void> {
    if (!this.initialized || !this.bucket) {
      throw new Error('Firebase가 초기화되지 않았습니다.');
    }

    try {
      await this.bucket.file(filePath).delete();
      console.log(`✓ Firebase Storage 파일 삭제: ${filePath}`);
    } catch (error) {
      console.error('Firebase Storage 파일 삭제 실패:', error);
      throw error;
    }
  }

  async getSignedUrl(filePath: string, expiresInMinutes: number = 60): Promise<string> {
    if (!this.initialized || !this.bucket) {
      throw new Error('Firebase가 초기화되지 않았습니다.');
    }

    try {
      const file = this.bucket.file(filePath);
      const [url] = await file.getSignedUrl({
        action: 'read',
        expires: Date.now() + expiresInMinutes * 60 * 1000
      });
      
      return url;
    } catch (error) {
      console.error('Signed URL 생성 실패:', error);
      throw error;
    }
  }

  generateStoragePath(userId: string, type: 'video' | 'audio' | 'thumbnail', originalName: string): string {
    const timestamp = Date.now();
    const ext = path.extname(originalName);
    const nameWithoutExt = path.basename(originalName, ext);
    
    return `users/${userId}/${type}/${timestamp}-${nameWithoutExt}${ext}`;
  }
}

export const firebaseService = new FirebaseService();