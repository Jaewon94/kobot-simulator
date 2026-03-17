# KOBOT 시뮬레이터 테스트 가이드

## 개요

TDD (Test-Driven Development) 방식으로 시뮬레이터를 검증합니다.

**RED → GREEN → REFACTOR** 사이클:
1. **RED**: 테스트 실행 → 실패 확인
2. **GREEN**: 코드 수정 → 테스트 통과
3. **REFACTOR**: 코드 개선 (테스트는 계속 통과)

---

## 테스트 스크립트

### Phase 1: Docker 기본 인프라 검증

```bash
cd simulator
bash tests/test_phase1_docker.sh
```

**검증 항목** (10개):
- ✅ Docker 이미지 빌드
- ✅ ROS2 Humble 설치 확인
- ✅ Python 3.11+ 설치 확인
- ✅ Python 패키지 (aiomqtt, numpy) 확인
- ✅ FFmpeg 설치 확인
- ✅ ROS2 워크스페이스 디렉토리 확인
- ✅ 환경 변수 설정 확인
- ✅ netcat 설치 확인
- ✅ curl 설치 확인

**예상 결과**:
```
==========================================
테스트 결과 요약
==========================================
통과: 10 / 총 10개
실패: 0 / 총 10개

🎉 모든 테스트 통과!
```

---

### Phase 2: ROS2 센서 노드 검증

```bash
cd simulator
bash tests/test_phase2_ros2.sh
```

**검증 항목** (8개):
- ✅ ROS2 패키지 구조 확인 (package.xml, setup.py, setup.cfg)
- ✅ GPS Publisher 파일 확인
- ✅ GPS Publisher Python 문법 확인
- ✅ GPS Publisher import 확인
- ✅ sensor_msgs/NavSatFix 메시지 타입 확인
- ✅ ROS2 워크스페이스 빌드
- ✅ GPS Publisher 노드 실행 (5초)
- ✅ GPS 토픽 발행 확인

**예상 결과**:
```
==========================================
테스트 결과 요약
==========================================
통과: 8 / 총 8개
실패: 0 / 총 8개

🎉 모든 테스트 통과!
```

---

## 테스트 실패 시 대응

### Red (실패) 예시

```bash
[TEST] Docker 이미지 빌드 (kobot-sim:test)
✗ FAIL
```

**원인**: Dockerfile 문법 오류 또는 베이스 이미지 문제

**해결**:
1. 빌드 로그 확인:
   ```bash
   cat /tmp/docker_build.log
   ```
2. Dockerfile 수정
3. 테스트 재실행

---

### Green (통과) 후 할 일

✅ 모든 테스트 통과 시:
1. 코드 커밋
2. 다음 Phase로 진행
3. 또는 Refactor (코드 개선)

---

## 전체 테스트 실행

모든 Phase를 한 번에 테스트:

```bash
cd simulator

echo "====== Phase 1: Docker ======"
bash tests/test_phase1_docker.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "====== Phase 2: ROS2 ======"
    bash tests/test_phase2_ros2.sh
fi
```

---

## 로그 파일 위치

테스트 실패 시 확인할 로그:

- `/tmp/docker_build.log` - Docker 빌드 로그
- `/tmp/ros2_build.log` - ROS2 colcon 빌드 로그
- `/tmp/gps_publisher.log` - GPS Publisher 실행 로그
- `/tmp/topic_list.log` - ROS2 토픽 리스트

---

## TDD 워크플로우 (앞으로 적용)

### 예: IMU Publisher 구현

#### 1. RED - 테스트 먼저 작성

```bash
# tests/test_imu_publisher.sh 작성
# 실행 → 실패 (코드 아직 없음)
bash tests/test_imu_publisher.sh
# ✗ FAIL: imu_publisher.py not found
```

#### 2. GREEN - 코드 작성

```bash
# kobot_simulator/imu_publisher.py 작성
# 테스트 재실행 → 통과
bash tests/test_imu_publisher.sh
# ✓ PASS: 모든 테스트 통과
```

#### 3. REFACTOR - 코드 개선

```bash
# 코드 리팩토링 (중복 제거, 성능 개선 등)
# 테스트 재실행 → 여전히 통과
bash tests/test_imu_publisher.sh
# ✓ PASS: 리팩토링 후에도 통과
```

---

## CI/CD 통합 (향후)

GitHub Actions 예시:

```yaml
name: Simulator Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run Phase 1 Tests
        run: cd simulator && bash tests/test_phase1_docker.sh
      - name: Run Phase 2 Tests
        run: cd simulator && bash tests/test_phase2_ros2.sh
```

---

## 주의사항

### Docker 이미지 캐싱

테스트 실행 전에 이전 이미지 삭제가 필요할 수 있습니다:

```bash
# 기존 테스트 이미지 삭제
docker rmi kobot-sim:test

# 테스트 재실행
bash tests/test_phase1_docker.sh
```

### 테스트 컨테이너 정리

테스트 실패 시 컨테이너가 남아있을 수 있습니다:

```bash
# 테스트 컨테이너 확인
docker ps -a | grep kobot

# 정리
docker rm -f kobot-gps-test
```

---

## 다음 단계

Phase 1, 2 테스트 통과 후:

1. **IMU Publisher 구현** (TDD)
   - 테스트 작성: `test_imu_publisher.sh`
   - 코드 작성: `imu_publisher.py`
   - 검증

2. **LiDAR Publisher 구현** (TDD)
   - 테스트 작성: `test_lidar_publisher.sh`
   - 코드 작성: `lidar_publisher.py`
   - 검증

3. **System Status Publisher 구현** (TDD)
   - 테스트 작성: `test_system_status_publisher.sh`
   - 코드 작성: `system_status_publisher.py`
   - 검증

4. **MQTT Bridge 구현** (TDD)
   - 테스트 작성: `test_mqtt_bridge.sh`
   - 코드 작성: `ros2_to_mqtt.py`, `mqtt_to_ros2.py`
   - 검증

5. **통합 테스트**
   - 전체 시스템 통합 테스트
   - Backend API 연동 테스트
