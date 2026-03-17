# KOBOT 시뮬레이터

ROS2 기반 해양 무인로봇(KOBOT) 시뮬레이터 — 관제 시스템 테스트용

## 개요

실제 KOBOT 없이도 관제 시스템(Backend + Frontend)을 테스트할 수 있는 시뮬레이터입니다.

- **1 컨테이너 = 1 KOBOT**: 각 KOBOT이 독립적인 Docker 컨테이너로 실행
- **ROS2 기반**: 실제 KOBOT의 ROS2 토픽 구조를 재현
- **MQTT 통신**: ROS2 → MQTT Bridge로 관제 시스템과 통신
- **카메라 스트리밍**: 3채널 RTMP → MediaMTX → WebRTC 변환

> **참고**: 이 시뮬레이터는 관제 시스템 개발/테스트를 위한 것으로, 실제 KOBOT의 내부 구현(ROS2 노드 구조, 자율주행 로직 등)과는 다릅니다. 관제 시스템은 MQTT로 수신하는 센서 데이터의 토픽과 JSON 포맷만 일치하면 동작하므로, 실제 KOBOT에서도 동일한 MQTT 메시지 형식으로 발행해 주시면 관제 연동이 됩니다.

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

# 특정 KOBOT만 시작 (예: #6번)
docker compose -f docker-compose.simulator-prod.yml up -d kobot-sim-prod-006
```

### 3. 연결 확인

```bash
# 컨테이너 상태 확인
docker compose -f docker-compose.simulator-prod.yml ps

# 로그에서 "Connected to MQTT broker" 메시지 확인
docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-006
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
docker compose -f docker-compose.simulator-prod.yml up -d kobot-sim-prod-006
docker compose -f docker-compose.simulator-prod.yml stop kobot-sim-prod-006
docker compose -f docker-compose.simulator-prod.yml restart kobot-sim-prod-006

# 로그 확인
docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-006
```

---

## KOBOT 시뮬레이터 목록

| 컨테이너 | Namespace | ROS_DOMAIN_ID | 시나리오 | 카메라 |
|---------|-----------|---------------|---------|--------|
| kobot-sim-prod-006 | kobot6 | 6 | stationary | cam1, cam2, cam3 |
| kobot-sim-prod-007 | kobot7 | 7 | stationary | cam1, cam2, cam3 |
| kobot-sim-prod-008 | kobot8 | 8 | stationary | cam1, cam2, cam3 |
| kobot-sim-prod-009 | kobot9 | 9 | stationary | cam1, cam2, cam3 |
| kobot-sim-prod-010 | kobot10 | 10 | stationary | cam1, cam2, cam3 |

각 KOBOT은 독립적인 `ROS_DOMAIN_ID`를 가져 DDS 도메인이 완전히 격리됩니다.

---

## 발행하는 센서 데이터

시뮬레이터는 실제 KOBOT과 동일한 MQTT 토픽으로 센서 데이터를 발행합니다.

> **중요**: 모든 MQTT 토픽은 선행 슬래시(`/`) 없이 사용됩니다. (예: `kobot6/sensors/gps`)

### GPS (`{namespace}/sensors/gps`)

발행 주기: 환경변수 `GPS_RATE`로 조정 (기본 1.0Hz = 1초당 1회)

```json
{
  "type": "sensor_data",
  "namespace": "kobot6",
  "timestamp": "2025-10-11T12:34:56.789Z",
  "data": {
    "sensor_type": "gps",
    "latitude": 35.1158,
    "longitude": 129.0403,
    "altitude": 0.5,
    "gps_status": 3,
    "num_satellites": 12
  }
}
```

### IMU (`{namespace}/sensors/imu`)

발행 주기: 환경변수 `IMU_RATE`로 조정 (기본 0.2Hz = 5초당 1회)

```json
{
  "type": "sensor_data",
  "namespace": "kobot6",
  "timestamp": "2025-10-11T12:34:56.789Z",
  "data": {
    "sensor_type": "imu",
    "orientation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
    "angular_velocity": {"x": 0.01, "y": -0.02, "z": 0.03},
    "linear_acceleration": {"x": 0.05, "y": 0.02, "z": 9.81}
  }
}
```

### LiDAR (`{namespace}/sensors/lidar`)

발행 주기: 환경변수 `LIDAR_RATE`로 조정 (기본 0.33Hz = 3초당 1회)

```json
{
  "type": "sensor_data",
  "namespace": "kobot6",
  "timestamp": "2025-10-11T12:34:56.789Z",
  "data": {
    "sensor_type": "lidar",
    "ranges": [2.5, 3.1, 4.2],
    "min_distance": 2.5,
    "obstacle_count": 3
  }
}
```

### System Status (`{namespace}/status`)

발행 주기: 환경변수 `STATUS_RATE`로 조정 (기본 0.2Hz = 5초당 1회)

```json
{
  "type": "status_update",
  "timestamp": 1760504493.028899,
  "battery_percentage": 85
}
```

---

## 명령 수신 및 ACK

시뮬레이터는 관제 시스템의 명령을 수신하고 ACK를 자동 응답합니다.

### 명령 수신 (`{namespace}/command`)

```json
{
  "type": "stop_autodrive",
  "namespace": "kobot6",
  "timestamp": "2025-10-11T12:34:56.789Z",
  "data": {
    "command_id": "cmd_1234567890",
    "params": {}
  }
}
```

### ACK 응답 (`{namespace}/command/ack`)

```json
{
  "type": "stop_autodrive",
  "namespace": "kobot6",
  "timestamp": "2025-10-11T12:34:57.123Z",
  "data": {
    "command_id": "cmd_1234567890",
    "status": "success",
    "message": "Autodrive stopped"
  }
}
```

---

## 카메라 스트리밍

각 KOBOT은 3채널 카메라 스트리밍을 지원합니다.

### 아키텍처

```
KOBOT Simulator → FFmpeg H.264 → RTMP → MediaMTX → WebRTC → Client
```

### 카메라 채널

| 채널 | 용도 | 비디오 패턴 | 라벨 색상 |
|-----|------|----------|---------|
| CAM1 | 주행용 (Navigation) | 컬러 바 | 노란색 |
| CAM2 | 인식용 1 (Recognition-1) | RGB 그라데이션 | 청록색 |
| CAM3 | 인식용 2 (Recognition-2) | Game of Life | 라임색 |

### 스트리밍 URL

- **RTMP 송출**: `rtmp://{서버주소}:1935/koai/{namespace}/live/cam{1-3}`
- **WebRTC 수신**: `http://{서버주소}:8889/koai/{namespace}/live/cam{1-3}/whep`
- **포맷**: H.264 Baseline, 1280x720@30fps, 2Mbps

### 자동 시작

`CAMERA_AUTO_START=true` (기본값) 설정 시 시뮬레이터 시작과 함께 카메라 스트리밍이 자동으로 시작됩니다.

---

## MQTT 토픽 구조

| 토픽 | 방향 | 설명 |
|------|------|------|
| `{namespace}/sensors/gps` | KOBOT → 관제 | GPS 위치 데이터 |
| `{namespace}/sensors/imu` | KOBOT → 관제 | IMU 자세 데이터 |
| `{namespace}/sensors/lidar` | KOBOT → 관제 | LiDAR 요약 데이터 |
| `{namespace}/status` | KOBOT → 관제 | 시스템 상태 |
| `{namespace}/command` | 관제 → KOBOT | 제어 명령 |
| `{namespace}/command/ack` | KOBOT → 관제 | 명령 ACK 응답 |

---

## 센서 발행 주기 설정

`.env.simulator.prod` 파일에서 센서별 발행 주기를 조정할 수 있습니다:

```bash
GPS_RATE=1.0      # 1.0Hz = 1초마다 1회
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
│   └── fake_stream.sh                # FFmpeg 테스트 패턴 스트리밍
├── mqtt_bridge/
├── scenarios/                        # 시나리오 (patrol, stationary)
├── scripts/
│   └── start_kobot.sh
├── config/
└── tests/
```

---

## 문제 해결

### MQTT 연결 실패

```bash
# 1. 시뮬레이터 로그 확인
docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-006

# 2. MQTT 브로커 연결 테스트
docker exec kobot-sim-prod-006 nc -zv $MQTT_BROKER 1883
```

### 카메라 스트리밍 안 됨

```bash
# FFmpeg 프로세스 확인
docker exec kobot-sim-prod-006 ps aux | grep ffmpeg

# 수동 카메라 시작
docker exec kobot-sim-prod-006 bash /root/camera/fake_stream.sh kobot6 {서버주소} 1935
```

### ROS2 노드 확인

```bash
docker exec -it kobot-sim-prod-006 bash
ros2 node list
ros2 topic list
ros2 topic echo /kobot6/sensors/gps
```
