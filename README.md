# KOBOT 시뮬레이터

ROS2 기반 해양 무인로봇(KOBOT) 시뮬레이터 — 관제 시스템 테스트용

## 개요

실제 KOBOT 없이도 관제 시스템(Backend + Frontend)을 테스트할 수 있는 시뮬레이터입니다.

- **1 컨테이너 = 1 KOBOT**: 각 KOBOT이 독립적인 Docker 컨테이너로 실행
- **ROS2 기반**: 실제 KOBOT의 ROS2 토픽 구조를 재현
- **MQTT 통신**: ROS2 → MQTT Bridge로 관제 시스템과 통신
- **카메라 스트리밍**: 5채널 RTMP → MediaMTX → WebRTC 변환 (cam1 비전 + cam2~5 일반)

> **참고**: 이 시뮬레이터는 관제 시스템 개발/테스트를 위한 것으로, 실제 KOBOT의 내부 구현(ROS2 노드 구조, 자율주행 로직 등)과는 다릅니다. 관제 시스템은 MQTT로 수신하는 센서 데이터의 토픽과 JSON 포맷만 일치하면 동작하므로, 실제 KOBOT에서도 동일한 MQTT 메시지 형식으로 발행해 주시면 관제 연동이 됩니다.

## ⚠️ Namespace 충돌 주의

시뮬레이터의 namespace(kobot11, kobot12 등)는 **MQTT 토픽의 식별자**로 사용됩니다. 같은 namespace로 여러 시뮬레이터를 동시에 실행하면 다음과 같은 문제가 발생합니다:

- GPS 위치가 두 시뮬레이터 사이를 왔다갔다 점프
- 센서 데이터가 뒤섞여 관제 화면에 비정상 표시
- 명령 ACK가 엉뚱한 시뮬레이터에서 응답

**기본 설정은 kobot11 ~ kobot15입니다.** 만약 다른 곳에서 이미 같은 번호를 사용 중이라면, `.env.simulator.prod` 파일에서 namespace를 다른 번호(예: kobot16 ~ kobot20)로 변경해서 사용해 주세요.

```bash
# .env.simulator.prod에서 namespace 변경 예시
KOBOT_011_NAMESPACE=kobot16
KOBOT_011_USERNAME=kobot16
```

## 사전 준비

- Docker & Docker Compose 설치
- 엠바스에서 전달받은 관제 서버 접속 정보 (서버 주소, MQTT 비밀번호)

---

## 빠른 시작

### 1. 초기 설정 (최초 1회)

```bash
# setup 스크립트 실행 — 관제 서버 주소와 비밀번호를 입력하면 환경 파일이 자동 생성됩니다
bash setup.sh
```

스크립트가 물어보는 항목:
- **관제 서버 IP/도메인**: 엠바스에서 전달받은 서버 주소
- **MQTT 비밀번호**: 엠바스에서 전달받은 비밀번호
- **MQTT 포트**: 기본 1883 (변경 필요 시 입력)

> 수동으로 설정하려면: `.env.simulator.example`을 `.env.simulator.prod`로 복사 후 직접 수정

### 2. 시뮬레이터 시작

```bash
# 전체 5대 시작
docker compose -f docker-compose.simulator-prod.yml up -d

# 특정 KOBOT만 시작 (예: #11번)
docker compose -f docker-compose.simulator-prod.yml up -d kobot-sim-prod-011
```

### 3. 연결 확인

```bash
# 컨테이너 상태 확인
docker compose -f docker-compose.simulator-prod.yml ps

# 로그에서 "Connected to MQTT broker" 메시지 확인
docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-011
```

### 4. 중지

```bash
# 전체 중지
docker compose -f docker-compose.simulator-prod.yml down
```

---

## 시뮬레이터 제어

```bash
# 전체 시작/중지
docker compose -f docker-compose.simulator-prod.yml up -d
docker compose -f docker-compose.simulator-prod.yml down

# 개별 KOBOT 제어
docker compose -f docker-compose.simulator-prod.yml up -d kobot-sim-prod-011
docker compose -f docker-compose.simulator-prod.yml stop kobot-sim-prod-011
docker compose -f docker-compose.simulator-prod.yml restart kobot-sim-prod-011

# 로그 확인
docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-011
```

---

## KOBOT 시뮬레이터 목록

| 컨테이너 | Namespace | ROS_DOMAIN_ID | 시나리오 | 카메라 |
|---------|-----------|---------------|---------|--------|
| kobot-sim-prod-011 | kobot11 | 11 | patrol | cam1~5 (5채널) |
| kobot-sim-prod-012 | kobot12 | 12 | patrol | cam1~5 (5채널) |
| kobot-sim-prod-013 | kobot13 | 13 | stationary | cam1~5 (5채널) |
| kobot-sim-prod-014 | kobot14 | 14 | patrol | cam1~5 (5채널) |
| kobot-sim-prod-015 | kobot15 | 15 | patrol | cam1~5 (5채널) |

각 KOBOT은 독립적인 `ROS_DOMAIN_ID`를 가져 DDS 도메인이 완전히 격리됩니다.

---

## 발행하는 센서 데이터

시뮬레이터는 실제 KOBOT과 동일한 MQTT 토픽으로 센서 데이터를 발행합니다.

> **중요**: 모든 MQTT 토픽은 `koai/` prefix를 사용합니다. (예: `koai/kobot11/gps`)

### GPS (`koai/{namespace}/gps`)

발행 주기: 환경변수 `GPS_RATE`로 조정 (현재 1.0Hz = 1초당 1회), QoS 0

```json
{
  "ts_iso": "2026-04-01T10:30:00.123456+00:00",
  "header": {
    "stamp": { "sec": 1774935000, "nanosec": 123456000 },
    "frame_id": "gps_antenna"
  },
  "status": { "status": 2, "service": 1 },
  "latitude": 35.1158,
  "longitude": 129.0403,
  "altitude": 0.5,
  "position_covariance": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
  "position_covariance_type": 2
}
```

### IMU (`koai/{namespace}/imu`)

발행 주기: 환경변수 `IMU_RATE`로 조정 (기본 0.2Hz = 5초당 1회), QoS 0

```json
{
  "ts_iso": "2026-04-01T10:30:05.456789+00:00",
  "header": {
    "stamp": { "sec": 1774935005, "nanosec": 456789000 },
    "frame_id": "imu"
  },
  "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 },
  "orientation_covariance": [0.01, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.01],
  "angular_velocity": { "x": 0.01, "y": -0.02, "z": 0.03 },
  "angular_velocity_covariance": [0.01, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.01],
  "linear_acceleration": { "x": 0.05, "y": 0.02, "z": 9.81 },
  "linear_acceleration_covariance": [0.01, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.01]
}
```

### LiDAR (`koai/{namespace}/lidar`)

발행 주기: 환경변수 `LIDAR_RATE`로 조정 (기본 0.33Hz = 3초당 1회), QoS 0

```json
{
  "ts_iso": "2026-04-01T10:30:03.789012+00:00",
  "header": {
    "stamp": { "sec": 1774935003, "nanosec": 789012000 },
    "frame_id": "lidar"
  },
  "angle_min": 0.0,
  "angle_max": 6.2832,
  "angle_increment": 0.0175,
  "range_min": 0.1,
  "range_max": 30.0,
  "ranges": [3.45, 3.42, 5.1, 12.0],
  "intensities": [100, 105, 80, 50]
}
```

> **참고**: ranges/intensities는 10x 샘플링 (원본의 10개당 1개만 전송)

### System Status (`koai/{namespace}/status`)

> **참고**: Status 토픽의 항목과 포맷은 아직 협의 중이며, 현재 시뮬레이터에서는 배터리 잔량만 임시로 발행하고 있습니다. 항목이 확정되면 업데이트 예정입니다.

발행 주기: 환경변수 `STATUS_RATE`로 조정 (기본 0.2Hz = 5초당 1회), QoS 0

```json
{
  "ts_iso": "2026-04-01T10:30:10.000000+00:00",
  "header": {
    "stamp": { "sec": 1774935010, "nanosec": 0 },
    "frame_id": "status"
  },
  "battery_percentage": 85.5
}
```

---

## 명령 수신 및 ACK

시뮬레이터는 관제 시스템의 자율주행 명령을 수신하고 ACK를 자동 응답합니다.

### 명령 토픽

- **수신**: `koai/{namespace}/cmd/autodrive` (QoS 1)
- **ACK 응답**: `koai/{namespace}/ack/autodrive` (QoS 1)

### 자율주행 시작 (웨이포인트 전송)

관제 시스템에서 웨이포인트 목록과 함께 시작 명령을 보내면, 시뮬레이터가 해당 좌표로 GPS 이동을 시뮬레이션합니다.

**명령:**

```json
{
  "cmd": "start",
  "cmd_id": "cmd_1234567890",
  "waypoints": [
    {"lat": 35.1158, "lng": 129.0403},
    {"lat": 35.1165, "lng": 129.0410},
    {"lat": 35.1170, "lng": 129.0415}
  ]
}
```

**ACK 응답:**

```json
{
  "ok": true,
  "cmd_id": "cmd_1234567890",
  "error": "",
  "ts_iso": "2026-04-01T10:30:00.123Z"
}
```

### 자율주행 정지

**명령:**

```json
{
  "cmd": "stop",
  "cmd_id": "cmd_1234567891"
}
```

**ACK 응답:**

```json
{
  "ok": true,
  "cmd_id": "cmd_1234567891",
  "error": "",
  "ts_iso": "2026-04-01T10:35:00.456Z"
}
```

### 시뮬레이터 동작

| 명령 | 시뮬레이터 동작 |
|------|-------------|
| `start` + 웨이포인트 | GPS 좌표가 웨이포인트를 향해 순차 이동 (3m 이내 도달 시 다음 포인트) |
| `start` (주행 중 재수신) | 기존 경로 대체, 새 웨이포인트로 이동 재개 |
| `stop` | 현재 위치에서 정지, 웨이포인트 진행 일시정지 |
| 모든 웨이포인트 도달 | 자동 정지 (idle 상태 전환) |

### ACK 필드 설명

| 필드 | 타입 | 설명 |
|------|------|------|
| `ok` | boolean | 명령 처리 성공 여부 |
| `cmd_id` | string | 수신한 명령의 ID (그대로 반환) |
| `error` | string | 실패 시 에러 메시지 (성공 시 빈 문자열) |
| `ts_iso` | string | ACK 발행 시각 (ISO 8601 UTC) |

---

## 카메라 스트리밍

각 KOBOT은 5채널 카메라 스트리밍을 지원합니다.

### 아키텍처

```
KOBOT Simulator → FFmpeg H.264 → RTMP → MediaMTX → WebRTC → Client
```

### 카메라 채널 (5대)

| 채널 | 용도 | 비디오 패턴 (시뮬레이터) | 라벨 색상 |
|-----|------|---------------------|---------|
| CAM1 | 비전인식 (Vision) | 컬러 바 (testsrc2) | 노란색 |
| CAM2 | 일반 카메라 1 (General-1) | RGB 그라데이션 (rgbtestsrc) | 청록색 |
| CAM3 | 일반 카메라 2 (General-2) | Game of Life (life) | 라임색 |
| CAM4 | 일반 카메라 3 (General-3) | PAL 75% 컬러 바 (pal75bars) | 주황색 |
| CAM5 | 일반 카메라 4 (General-4) | SMPTE 바 (smptebars) | 마젠타 |

### 스트리밍 URL

- **RTMP 송출**: `rtmp://{서버주소}:1935/koai/{namespace}/live/cam{1-5}`
- **WebRTC 수신**: `http://{서버주소}:8889/koai/{namespace}/live/cam{1-5}/whep`
- **포맷**: H.264 Baseline, 1280x720@25fps, ~2Mbps

### 카메라 설정

docker-compose에서 코아이 확정 스펙으로 오버라이드됩니다:

```bash
# docker-compose.simulator-prod.yml의 environment에서 설정
CAMERA_RESOLUTION=1280x720   # 720p
CAMERA_FPS=25                # 25fps
CAMERA_BITRATE=2000k         # ~2Mbps
```

> **참고**: 시뮬레이터는 FFmpeg으로 테스트 패턴을 **소프트웨어 인코딩**하므로 CPU 부하가 큽니다.
> 컨테이너당 2GB 메모리 제한이 설정되어 있습니다 (5대 × 2GB = 최대 10GB).
> 실제 KOBOT에서는 물리 카메라의 하드웨어 인코더를 사용하므로 720p/25fps를 문제없이 처리합니다.

### 자동 시작

`CAMERA_AUTO_START=true` (기본값) 설정 시 시뮬레이터 시작과 함께 카메라 스트리밍이 자동으로 시작됩니다.

수동 제어가 필요한 경우:

```bash
# 카메라 시작
docker exec kobot-sim-prod-011 bash /root/camera/fake_stream.sh kobot11 {서버주소} 1935

# 카메라 중지
docker exec kobot-sim-prod-011 pkill ffmpeg
```

---

## RTMP 스트림 끊김 시 재연결 책임

### 스트리밍 경로와 재연결 책임

```
KOBOT (FFmpeg/카메라) → RTMP → MediaMTX → WebRTC (WHEP) → 관제 브라우저
         ①                                    ②
```

| 구간 | 책임 | 재연결 방법 | 상태 |
|------|------|-----------|------|
| ① KOBOT → MediaMTX (RTMP) | **코아이 (KOBOT 측)** | FFmpeg/카메라 프로세스 재시작 → 같은 RTMP URL로 재전송 | 코아이 구현 필요 |
| ② MediaMTX → 브라우저 (WebRTC) | **GCS (관제 측)** | 자동 재연결 (지수 백오프, 최대 10회) | ✅ GCS 구현 완료 |

### GCS에서 구현된 것 (②)

GCS 관제 화면의 WebRTC 플레이어는 **자동 재연결**을 지원합니다:

- 스트림 끊김 감지 → 지수 백오프로 재시도 (2초 → 4 → 8 → 16 → 30초, 최대 10회)
- RTMP 스트림이 복구되면 자동으로 새 WebRTC 세션을 맺어 영상 복구
- 10회 초과 시 "연결 실패" 표시 + [다시 연결] 버튼 제공

### 코아이에서 구현해야 하는 것 (①)

MediaMTX는 **수동적 중계기**입니다. RTMP 소스가 들어오면 수락하고, 끊기면 해당 WebRTC 세션도 종료됩니다.
**MediaMTX가 KOBOT에게 "다시 연결해"라고 알려주지 않습니다.**

따라서 KOBOT 측에서 RTMP 스트림이 끊겼을 때 **자체적으로 감지하고 같은 RTMP URL로 재전송**해주시면 됩니다.
에러 발생 시에는 아래 "카메라 에러 보고" 섹션의 MQTT 토픽으로 에러 내용을 함께 발행해주시면 GCS 관제 화면에서 확인 가능합니다.

> **요약**: KOBOT에서 RTMP를 다시 쏘기만 하면, GCS는 자동으로 WebRTC 재연결하여 영상을 복구합니다.

---

## 카메라 에러 보고 — 코아이 KOBOT → GCS

### 왜 필요한가?

GCS 관제 화면에는 **카메라 로그 모달**이 있어서, 운영자가 각 KOBOT의 카메라 상태를 실시간으로 모니터링합니다.

현재 GCS가 **자체적으로 감지하는 이벤트**:
- `CAMERA_CONNECTED` — RTMP 스트림이 MediaMTX에 연결됨 (자동 감지)
- `CAMERA_DISCONNECTED` — RTMP 스트림이 끊김 (자동 감지)
- `RECORDING_STARTED/COMPLETED/FAILED` — 녹화 이벤트 (GCS 내부 처리)

하지만 **KOBOT 내부에서 발생하는 에러**는 GCS가 알 수 없습니다:
- 카메라 하드웨어 고장 (디바이스 응답 없음)
- 인코딩 실패 (H264 인코더 오류)
- 네트워크 문제로 RTMP 전송 실패
- 프레임레이트 저하 (카메라는 살아 있지만 성능 저하)

이런 에러를 KOBOT이 MQTT로 보내주면, GCS 관제 화면의 **에러 탭**에 실시간으로 표시되어 운영자가 즉시 대응할 수 있습니다.

### 코아이 구현 요청사항

KOBOT의 ROS2 카메라 노드에서 에러 감지 시, 아래 MQTT 토픽으로 메시지를 발행해주세요.

**토픽**: `koai/{namespace}/error/camera` (QoS 1 — 에러는 유실 방지)

**페이로드 형식** (반드시 이 구조를 따라주세요):

```json
{
    "type": "camera_error",
    "namespace": "kobot1",
    "timestamp": "2025-01-12T10:30:00Z",
    "data": {
        "camera": "cam1",
        "error_code": "STREAM_TIMEOUT",
        "error_message": "RTMP 스트림 전송 타임아웃 (30초 초과)",
        "details": {
            "retry_count": 1,
            "uptime_seconds": 1234
        }
    }
}
```

**필수 필드**:

| 필드 | 타입 | 규칙 | 설명 |
|------|------|------|------|
| `type` | string | 고정: `"camera_error"` | 메시지 타입 식별자 |
| `namespace` | string | `kobot1`~`kobot5` 등 | 발신 KOBOT 식별 |
| `timestamp` | string | ISO 8601 UTC | 에러 발생 시각 |
| `data.camera` | string | `cam1`~`cam5` | 에러 발생 카메라 |
| `data.error_code` | string | 자유 형식 (아래 예시 참고) | 에러 분류 코드 |
| `data.error_message` | string | 한글/영문 | 사람이 읽을 수 있는 에러 설명 |
| `data.details` | object | **선택사항** | 추가 디버깅 정보 (자유 형식) |

**에러 코드 예시** (코아이에서 자유롭게 정의 가능):

| 코드 | 언제 보내야 하나? | 예시 메시지 |
|------|-----------------|------------|
| `STREAM_TIMEOUT` | RTMP 스트림 전송이 일정 시간(예: 30초) 동안 실패할 때 | `"RTMP 스트림 전송 타임아웃 (30초 초과)"` |
| `ENCODING_ERROR` | H264 인코딩 프로세스 에러 발생 시 | `"H264 인코딩 실패 — 카메라 재시작 필요"` |
| `DEVICE_ERROR` | 카메라 디바이스(`/dev/video*`)가 응답하지 않을 때 | `"카메라 디바이스 응답 없음 (/dev/video0)"` |
| `RESOLUTION_ERROR` | 카메라 해상도 설정 변경 실패 시 | `"1280x720 해상도 설정 실패"` |
| `NETWORK_ERROR` | RTMP 서버 연결 자체가 불가할 때 | `"RTMP 서버 연결 불가 (connection refused)"` |
| `LOW_FRAMERATE` | 프레임레이트가 기준치(예: 10fps) 이하로 떨어질 때 | `"프레임레이트 저하 (현재 5fps, 기준 25fps)"` |

> **참고**: 위 에러 코드는 예시입니다. 코아이에서 실제 KOBOT 카메라 상황에 맞는 에러 코드를 자유롭게 정의해주세요.
> GCS에서는 `error_code`와 `error_message`를 그대로 로그에 표시합니다.
> 새 에러 코드를 추가해도 GCS 코드 수정은 필요 없습니다.

### GCS에서의 처리 흐름

```
KOBOT 카메라 에러 발생
  → ROS2 노드가 MQTT 발행: koai/{namespace}/error/camera
  → GCS 백엔드 수신 → event_logs DB 저장 (severity: ERROR)
  → GCS 프론트엔드 카메라 로그 모달의 "에러" 탭에 실시간 표시
  → 운영자가 에러 내용 확인 후 대응
```

### 시뮬레이터로 테스트

실제 KOBOT 없이도 에러 메시지를 테스트할 수 있습니다:

```bash
# 기본 (kobot1, cam1, STREAM_TIMEOUT)
./scripts/send_camera_error.sh

# 특정 KOBOT + 카메라 + 에러 코드
./scripts/send_camera_error.sh kobot2 cam3 ENCODING_ERROR "H264 인코딩 실패"

# 반복 발생 (5초 간격으로 3번)
./scripts/send_camera_error.sh kobot1 cam1 DEVICE_ERROR "" 3 5
```

---

## MQTT 토픽 구조

| 토픽 | 방향 | QoS | 설명 |
|------|------|-----|------|
| `koai/{namespace}/gps` | KOBOT → 관제 | 0 | GPS 위치 데이터 |
| `koai/{namespace}/imu` | KOBOT → 관제 | 0 | IMU 자세 데이터 |
| `koai/{namespace}/lidar` | KOBOT → 관제 | 0 | LiDAR 장애물 데이터 |
| `koai/{namespace}/status` | KOBOT → 관제 | 0 | 시스템 상태 (배터리) |
| `koai/{namespace}/cmd/autodrive` | 관제 → KOBOT | 1 | 자율주행 명령 (start/stop + 웨이포인트) |
| `koai/{namespace}/ack/autodrive` | KOBOT → 관제 | 1 | 명령 ACK 응답 |
| `koai/{namespace}/error/camera` | KOBOT → 관제 | 1 | 카메라 에러 보고 |

### MQTT 메시지 확인

```bash
# 특정 KOBOT의 전체 데이터 구독
mosquitto_sub -h {MQTT_BROKER} -t "koai/kobot11/#" -u {username} -P {password}

# GPS만 구독
mosquitto_sub -h {MQTT_BROKER} -t "koai/kobot11/gps" -u {username} -P {password}
```

---

## 센서 발행 주기 설정

`.env.simulator.prod` 파일에서 센서별 발행 주기를 조정할 수 있습니다:

```bash
GPS_RATE=1.0      # 1.0Hz = 1초마다 1회 (실시간 위치 추적)
IMU_RATE=0.2      # 0.2Hz = 5초마다 1회
LIDAR_RATE=0.33   # 0.33Hz = 3초마다 1회
STATUS_RATE=0.2   # 0.2Hz = 5초마다 1회
```

---

## 프로젝트 구조

```
kobot-simulator/
├── setup.sh                          # 초기 설정 스크립트
├── docker-compose.simulator-prod.yml # Docker Compose 설정
├── .env.simulator.example            # 환경 변수 템플릿
├── docker/
│   ├── Dockerfile.kobot              # ROS2 Humble 기반 이미지
│   └── entrypoint.sh
├── ros2_ws/                          # ROS2 워크스페이스
│   └── src/kobot_simulator/
│       ├── gps_publisher.py
│       ├── imu_publisher.py
│       ├── lidar_publisher.py
│       ├── system_status_publisher.py
│       ├── mqtt_bridge.py
│       └── scenario_manager.py
├── camera/
│   └── fake_stream.sh                # FFmpeg 테스트 패턴 스트리밍 (5채널)
├── mqtt_bridge/
├── scenarios/                        # 시나리오 (patrol, stationary)
├── scripts/
│   ├── start_kobot.sh                # KOBOT 시작 스크립트
│   └── send_camera_error.sh          # 카메라 에러 MQTT 시뮬레이션
├── config/
└── tests/
```

---

## 문제 해결

### MQTT 연결 실패

```bash
# 1. 시뮬레이터 로그 확인
docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-011

# 2. MQTT 브로커 연결 테스트
docker exec kobot-sim-prod-011 nc -zv $MQTT_BROKER 1883
```

### 카메라 스트리밍 안 됨

```bash
# FFmpeg 프로세스 확인
docker exec kobot-sim-prod-011 ps aux | grep ffmpeg

# 수동 카메라 시작
docker exec kobot-sim-prod-011 bash /root/camera/fake_stream.sh kobot11 {서버주소} 1935
```

### ROS2 노드 확인

```bash
docker exec -it kobot-sim-prod-011 bash
ros2 node list
ros2 topic list
ros2 topic echo /kobot11/sensors/gps
```
