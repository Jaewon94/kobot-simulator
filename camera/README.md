# KOBOT 카메라 스트리밍

KOBOT 시뮬레이터의 3채널 카메라 스트리밍 구현

---

## 개요

각 KOBOT은 **3대의 카메라**를 시뮬레이션합니다:
- **CAM1**: 주행용 카메라 (Navigation)
- **CAM2**: 인식용 카메라 1 (Recognition-1)
- **CAM3**: 인식용 카메라 2 (Recognition-2)

**스트리밍 파이프라인**:
```
FFmpeg (H.264 Encoding) → RTMP → MediaMTX → WebRTC → Client
```

---

## 스크립트: fake_stream.sh

### 사용법

```bash
# 기본 사용 (3개 카메라 모두 시작)
./fake_stream.sh <KOBOT_NAMESPACE> <MEDIAMTX_HOST> <MEDIAMTX_PORT>

# 예시
./fake_stream.sh kobot1 host.docker.internal 1935
```

### 인자

| 인자 | 설명 | 예시 |
|-----|------|-----|
| `KOBOT_NAMESPACE` | KOBOT 고유 식별자 | `kobot1` |
| `MEDIAMTX_HOST` | MediaMTX 서버 주소 | `host.docker.internal` (Mac/Windows)<br>`172.17.0.1` (Linux)<br>`192.168.1.100` (원격 서버) |
| `MEDIAMTX_PORT` | MediaMTX RTMP 포트 | `1935` (기본값) |

### 동작 방식

1. **입력 검증**: 3개 인자 확인
2. **카메라별 RTMP URL 생성**:
   - CAM1: `rtmp://{host}:1935/koai/{namespace}/live/cam1`
   - CAM2: `rtmp://{host}:1935/koai/{namespace}/live/cam2`
   - CAM3: `rtmp://{host}:1935/koai/{namespace}/live/cam3`
3. **3개 카메라 순차 시작** (각각 2초 간격):
   - FFmpeg 프로세스를 백그라운드로 실행
   - 각 카메라마다 고유한 비디오 패턴 사용
4. **로그 출력**: PID와 스트리밍 상태 실시간 표시

---

## 카메라별 비디오 패턴

| 카메라 | FFmpeg Source | 비디오 패턴 | 라벨 색상 | 용도 |
|-------|---------------|-----------|---------|-----|
| **CAM1** | `testsrc2` | 컬러 바 (Color Bars) | 노란색 (yellow) | 주행용 |
| **CAM2** | `rgbtestsrc` | RGB 그라데이션 (RGB Gradient) | 청록색 (cyan) | 인식용 1 |
| **CAM3** | `life` | Game of Life 애니메이션 | 라임색 (lime) | 인식용 2 |

**각 비디오에 오버레이되는 정보**:
- 왼쪽 상단: KOBOT Namespace (예: `kobot1`)
- 중앙 상단: 카메라 설명 + 색상 라벨 (예: `CAM1 (Navigation)` - 노란색)
- 왼쪽 하단: 실시간 타임스탬프 (예: `2025-10-11 08:48:37`)

---

## FFmpeg 인코딩 설정

| 옵션 | 값 | 설명 |
|-----|---|-----|
| **해상도** | 1280x720 | HD 720p |
| **프레임레이트** | 30fps | 초당 30프레임 |
| **비트레이트** | 2Mbps | 고화질 스트리밍 |
| **코덱** | H.264 Baseline | 최대 호환성 |
| **프로파일** | Baseline Level 3.1 | 모바일 디바이스 지원 |
| **프리셋** | ultrafast | 저지연 인코딩 |
| **튜닝** | zerolatency | 실시간 스트리밍 최적화 |
| **I-Frame 간격** | 60프레임 (2초) | 빠른 탐색 |

**주요 FFmpeg 명령어 옵션**:
```bash
ffmpeg \
  -re \                                # 실시간 속도로 읽기
  -f lavfi \                           # lavfi (Virtual Video Source)
  -i "testsrc2=size=1280x720:rate=30" \
  -vf "drawtext=..." \                 # 텍스트 오버레이
  -c:v libx264 \                       # H.264 인코더
  -preset ultrafast \                  # 저지연 프리셋
  -tune zerolatency \                  # 실시간 튜닝
  -profile:v baseline \                # Baseline 프로파일
  -b:v 2M -maxrate 2M \                # 2Mbps 비트레이트
  -bufsize 4096k \                     # 버퍼 크기
  -g 60 -keyint_min 30 \               # I-Frame 간격
  -sc_threshold 0 \                    # Scene Change 감지 비활성화
  -pix_fmt yuv420p \                   # 픽셀 포맷
  -f flv \                             # FLV 컨테이너 (RTMP)
  -reconnect 1 \                       # 자동 재연결
  rtmp://host:1935/koai/namespace/live/cam1
```

---

## 사용 예시

### Docker 컨테이너에서 실행

```bash
# 시뮬레이터 001의 카메라 시작
docker exec kobot-sim-001 bash /root/camera/fake_stream.sh kobot1 host.docker.internal 1935

# 백그라운드로 실행
docker exec kobot-sim-001 bash -c "nohup bash /root/camera/fake_stream.sh kobot1 host.docker.internal 1935 > /tmp/camera.log 2>&1 &"

# 로그 확인
docker exec kobot-sim-001 tail -f /tmp/camera.log
```

### 카메라 중지

```bash
# 모든 FFmpeg 프로세스 종료 (3개 카메라 모두 중지)
docker exec kobot-sim-001 pkill ffmpeg

# 특정 카메라만 종료
docker exec kobot-sim-001 pkill -f "cam2"
```

### 스트리밍 확인

```bash
# MediaMTX에서 활성 스트림 확인
docker logs kobot-mediamtx --tail 50 | grep "is publishing"

# 출력 예시:
# 2025/10/11 08:48:38 INF [RTMP] [conn 172.25.0.1:59220] is publishing to path 'kobot1/live/cam1', 1 track (H264)
# 2025/10/11 08:48:41 INF [RTMP] [conn 172.25.0.1:59290] is publishing to path 'kobot1/live/cam2', 1 track (H264)
# 2025/10/11 08:48:43 INF [RTMP] [conn 172.25.0.1:59318] is publishing to path 'kobot1/live/cam3', 1 track (H264)

# FFmpeg 프로세스 확인
docker exec kobot-sim-001 ps aux | grep ffmpeg
```

---

## WebRTC 재생 URL

클라이언트에서 각 카메라를 재생할 수 있는 WHEP 엔드포인트:

### 로컬 개발 환경
```
http://localhost:8889/koai/kobot1/live/cam1/whep
http://localhost:8889/koai/kobot1/live/cam2/whep
http://localhost:8889/koai/kobot1/live/cam3/whep
```

### 운영 환경
```
https://kobot.example.com:8889/koai/kobot1/live/cam1/whep
https://kobot.example.com:8889/koai/kobot1/live/cam2/whep
https://kobot.example.com:8889/koai/kobot1/live/cam3/whep
```

---

## 문제 해결

### 1. "Connection refused" 에러

**원인**: MediaMTX 서버에 접근할 수 없음

**해결**:
```bash
# MediaMTX 상태 확인
docker ps | grep mediamtx

# MediaMTX 로그 확인
docker logs kobot-mediamtx

# 포트 개방 확인 (원격 서버)
sudo ufw status
sudo ufw allow 1935/tcp
```

### 2. "Stream not found" 에러

**원인**: RTMP 스트림이 MediaMTX에 도달하지 않음

**해결**:
```bash
# FFmpeg 프로세스 확인
docker exec kobot-sim-001 ps aux | grep ffmpeg

# 스크립트 로그 확인
docker exec kobot-sim-001 cat /tmp/camera.log

# MediaMTX API로 스트림 확인
curl http://localhost:9997/v3/paths/list
```

### 3. 카메라 2개만 시작됨 (cam2 누락)

**원인**: CPU 과부하 또는 네트워크 문제로 `mandelbrot` 같은 집약적 패턴 실패

**해결**: [fake_stream.sh](fake_stream.sh)에서 `mandelbrot` 대신 `rgbtestsrc` 사용 (이미 적용됨)

### 4. FFmpeg 경고: "Stray % near 'S}'"

**원인**: drawtext 필터의 타임스탬프 포맷 이스케이프 문제

**영향**: 경고일 뿐, 스트리밍 기능에는 영향 없음 (타임스탬프는 정상 표시됨)

---

## 성능 및 리소스

### 단일 KOBOT (3개 카메라)
- **대역폭**: ~6Mbps (2Mbps × 3 채널)
- **CPU**: ~15-20% (FFmpeg 인코딩)
- **메모리**: ~180MB (각 카메라 60MB)

### 5개 KOBOT (15개 스트림)
- **대역폭**: ~30Mbps
- **CPU**: ~75-100%
- **메모리**: ~900MB

**권장 사양**: 최대 5대 KOBOT 동시 스트리밍 (t3.medium: 2vCPU, 4GB RAM, 실측 메모리 ~900MB)

---

## 향후 개선 사항

- [ ] MQTT 카메라 제어 명령 (`CAMERA_START_ALL`, `CAMERA_STOP_ALL`)
- [ ] 실제 비디오 파일 재생 (테스트 패턴 대신)
- [ ] 녹화 기능 (S3 아카이빙)
- [ ] 비트레이트 동적 조정 (네트워크 상태 기반)
- [ ] 스냅샷 캡처 (썸네일 생성)

---

## 참고 문서

- [MQTT Protocol Specification](../../docs/04.mqtt-protocol-specification.md)
- [WebRTC Streaming Guide](../../docs/10.webrtc-streaming-guide.md)
- [System Architecture Summary](../../docs/01-1.system-architecture-summary.md)
- [MediaMTX Configuration](../../config/mediamtx/mediamtx.yml)
