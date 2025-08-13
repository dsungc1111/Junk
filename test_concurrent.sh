#!/bin/bash

# 동시 변환 테스트 스크립트

echo "🧪 서버 부하 테스트 시작"
echo "================================"

# 1. 단일 변환 테스트
echo -e "\n1️⃣ 단일 변환 테스트"
start_time=$(date +%s.%N)
result=$(curl -X POST -F "video=@test_video.mp4" -F "resolution=320p" http://localhost:3000/resize/video -s 2>/dev/null)
end_time=$(date +%s.%N)
conversion_time=$(echo "$result" | jq -r '.metadata.conversionTime')
total_time=$(echo "$end_time - $start_time" | bc)
echo "  변환 시간: ${conversion_time}초"
echo "  전체 시간: ${total_time}초"

# 2. 3개 동시 변환
echo -e "\n3️⃣ 3개 동시 변환 테스트"
start_time=$(date +%s.%N)
for i in {1..3}; do
  (curl -X POST -F "video=@test_video.mp4" -F "resolution=320p" http://localhost:3000/resize/video -s -o result_3_$i.json 2>/dev/null) &
done
wait
end_time=$(date +%s.%N)
total_time=$(echo "$end_time - $start_time" | bc)
echo "  전체 완료 시간: ${total_time}초"
for i in {1..3}; do
  conv_time=$(jq -r '.metadata.conversionTime' result_3_$i.json)
  echo "  요청 $i 변환 시간: ${conv_time}초"
done

# 3. 5개 동시 변환
echo -e "\n5️⃣ 5개 동시 변환 테스트"
start_time=$(date +%s.%N)
for i in {1..5}; do
  (curl -X POST -F "video=@test_video.mp4" -F "resolution=320p" http://localhost:3000/resize/video -s -o result_5_$i.json 2>/dev/null) &
done
wait
end_time=$(date +%s.%N)
total_time=$(echo "$end_time - $start_time" | bc)
echo "  전체 완료 시간: ${total_time}초"
for i in {1..5}; do
  conv_time=$(jq -r '.metadata.conversionTime' result_5_$i.json)
  echo "  요청 $i 변환 시간: ${conv_time}초"
done

# 4. 10개 동시 변환
echo -e "\n🔟 10개 동시 변환 테스트"
start_time=$(date +%s.%N)
for i in {1..10}; do
  (curl -X POST -F "video=@test_video.mp4" -F "resolution=320p" http://localhost:3000/resize/video -s -o result_10_$i.json 2>/dev/null) &
done
wait
end_time=$(date +%s.%N)
total_time=$(echo "$end_time - $start_time" | bc)
echo "  전체 완료 시간: ${total_time}초"
for i in {1..10}; do
  conv_time=$(jq -r '.metadata.conversionTime' result_10_$i.json)
  echo "  요청 $i 변환 시간: ${conv_time}초"
done

# 정리
rm -f result_*.json

echo -e "\n================================"
echo "✅ 테스트 완료"