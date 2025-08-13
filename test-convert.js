const fs = require('fs');
const FormData = require('form-data');
const http = require('http');

// 간단한 1x1 GIF 생성 (투명 GIF)
const gifData = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');

// test.gif 파일로 저장
fs.writeFileSync('test.gif', gifData);
console.log('test.gif 파일 생성됨');

// 서버로 전송 테스트
const form = new FormData();
form.append('video', fs.createReadStream('test.gif'), {
  filename: 'test.gif',
  contentType: 'image/gif'
});
form.append('format', 'mp4');

const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/convert/video',
  method: 'POST',
  headers: form.getHeaders()
};

const req = http.request(options, (res) => {
  console.log(`상태 코드: ${res.statusCode}`);
  
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  
  res.on('end', () => {
    console.log('응답:', data);
    try {
      const json = JSON.parse(data);
      console.log('파싱된 응답:', json);
    } catch (e) {
      console.log('JSON 파싱 실패');
    }
  });
});

req.on('error', (error) => {
  console.error('요청 에러:', error);
});

form.pipe(req);