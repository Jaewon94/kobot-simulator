#!/bin/bash
# Phase 6 검증 테스트: MQTT Bridge
#
# 테스트 항목:
#   1. MQTT Bridge 파일 존재 확인
#   2. MQTT Bridge 문법 확인
#   3. MQTT Bridge import 확인
#   4. aiomqtt 패키지 확인
#   5. ROS2 워크스페이스 빌드
#   6. MQTT 브로커 연결 확인
#   7. MQTT Bridge 실행 (5초)
#   8. MQTT 메시지 발행 확인

# 에러 발생 시에도 계속 진행 (broken pipe 등의 harmless 에러 허용)
set +e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 테스트 결과 카운터
PASSED=0
FAILED=0

# 테스트 함수
test_step() {
    local description=$1
    local command=$2

    echo -e "\n${YELLOW}[TEST]${NC} $description"

    if eval "$command"; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((FAILED++))
        return 1
    fi
}

echo "=========================================="
echo "Phase 6: MQTT Bridge 검증 테스트"
echo "=========================================="

# 현재 디렉토리 확인
if [ ! -d "ros2_ws/src/kobot_simulator" ]; then
    echo -e "${RED}Error: ros2_ws/src/kobot_simulator not found${NC}"
    echo "Please run this script from simulator/ directory"
    exit 1
fi

# Test 1: MQTT Bridge 파일 확인
test_step "MQTT Bridge 파일 확인" \
    "[ -f ros2_ws/src/kobot_simulator/kobot_simulator/mqtt_bridge.py ]"

# Test 2: MQTT Bridge Python 문법 확인
test_step "MQTT Bridge Python 문법 확인" \
    "python3 -m py_compile ros2_ws/src/kobot_simulator/kobot_simulator/mqtt_bridge.py"

# Test 3: MQTT Bridge import 확인 (Docker 내부)
test_step "MQTT Bridge import 확인 (Docker)" \
    "docker run --rm -v $(pwd)/ros2_ws:/root/ros2_ws kobot-sim:test \
     python3 -c 'import sys; sys.path.insert(0, \"/root/ros2_ws/src/kobot_simulator\"); from kobot_simulator import mqtt_bridge'"

# Test 4: aiomqtt 패키지 확인
test_step "aiomqtt 패키지 확인 (Docker)" \
    "docker run --rm kobot-sim:test python3 -c 'import aiomqtt'"

# Test 5: ROS2 워크스페이스 빌드 (Docker 내부)
echo -e "\n${YELLOW}[TEST]${NC} ROS2 워크스페이스 빌드"
docker run --rm \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && source /opt/ros/humble/setup.bash && colcon build --packages-select kobot_simulator" \
    > /tmp/ros2_mqtt_build.log 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → Build log: /tmp/ros2_mqtt_build.log"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → Build log: /tmp/ros2_mqtt_build.log"
    cat /tmp/ros2_mqtt_build.log
    ((FAILED++))
fi

# Test 6: MQTT 브로커 연결 확인
echo -e "\n${YELLOW}[TEST]${NC} MQTT 브로커 연결 확인"
docker run --rm \
    --network ondeviceai-test2_kobot-network \
    kobot-sim:test \
    bash -c "timeout 5s python3 -c '
import asyncio
import aiomqtt

async def test_mqtt():
    try:
        async with aiomqtt.Client(hostname=\"kobot-mosquitto\", port=1883) as client:
            print(\"MQTT connected successfully\")
            return True
    except Exception as e:
        print(f\"MQTT connection failed: {e}\")
        return False

result = asyncio.run(test_mqtt())
exit(0 if result else 1)
'" > /tmp/mqtt_connection.log 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → MQTT 브로커에 정상 연결됨"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → MQTT 브로커 연결 실패"
    cat /tmp/mqtt_connection.log
    ((FAILED++))
fi

# Test 7: MQTT Bridge 실행 테스트 (5초간 실행)
echo -e "\n${YELLOW}[TEST]${NC} MQTT Bridge 노드 실행 (5초)"
docker run --rm \
    --network ondeviceai-test2_kobot-network \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    -e KOBOT_NAMESPACE=kobot_test \
    -e MQTT_BROKER_HOST=kobot-mosquitto \
    -e MQTT_BROKER_PORT=1883 -e MQTT_USERNAME=kobot_test -e MQTT_PASSWORD=test123 \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && \
             source /opt/ros/humble/setup.bash && \
             export PYTHONPATH=/root/ros2_ws/install/kobot_simulator/lib/python3.10/site-packages:\$PYTHONPATH && \
             export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
             timeout 5s /root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/mqtt_bridge \
                --ros-args \
                -p namespace:=kobot_test \
                -p mqtt_broker_host:=kobot-mosquitto \
                -p mqtt_broker_port:=1883" \
    > /tmp/mqtt_bridge.log 2>&1

EXIT_CODE=$?
if [ $EXIT_CODE -eq 124 ]; then
    # timeout 명령의 정상 종료 코드 (124)
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → MQTT Bridge가 5초간 정상 실행됨"
    echo "  → Log: /tmp/mqtt_bridge.log"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → MQTT Bridge 실행 실패 (Exit code: $EXIT_CODE)"
    echo "  → Log: /tmp/mqtt_bridge.log"
    cat /tmp/mqtt_bridge.log
    ((FAILED++))
fi

# Test 8: MQTT 메시지 구독 확인
echo -e "\n${YELLOW}[TEST]${NC} MQTT 메시지 발행 확인"
echo "  → MQTT Bridge + GPS Publisher 시작..."

# GPS Publisher와 MQTT Bridge를 함께 실행
docker run --rm -d \
    --name kobot-mqtt-test \
    --network ondeviceai-test2_kobot-network \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && \
             source /opt/ros/humble/setup.bash && \
             export PYTHONPATH=/root/ros2_ws/install/kobot_simulator/lib/python3.10/site-packages:\$PYTHONPATH && \
             export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
             /root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/gps_publisher \
                --ros-args -p namespace:=kobot_test &
             sleep 2 && \
             /root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/mqtt_bridge \
                --ros-args \
                -p namespace:=kobot_test \
                -p mqtt_broker_host:=kobot-mosquitto \
                -p mqtt_broker_port:=1883" \
    > /dev/null 2>&1

# 5초 대기 (MQTT 메시지 발행 대기)
sleep 5

# MQTT 메시지 구독 테스트
docker run --rm \
    --network ondeviceai-test2_kobot-network \
    kobot-sim:test \
    timeout 3s mosquitto_sub -h kobot-mosquitto -p 1883 -t "kobot_test/sensors/gps" -C 1 \
    > /tmp/mqtt_message.log 2>&1

if [ -s /tmp/mqtt_message.log ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → MQTT 메시지가 정상적으로 발행됨"
    echo "  → Topic: kobot_test/sensors/gps"
    echo "  → Sample message:"
    head -3 /tmp/mqtt_message.log | sed 's/^/    /'
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → MQTT 메시지를 받지 못함"
    echo "  → Log: /tmp/mqtt_message.log"
    cat /tmp/mqtt_message.log
    ((FAILED++))
fi

# 컨테이너 정리
docker stop kobot-mqtt-test > /dev/null 2>&1 || true

echo ""
echo "=========================================="
echo "테스트 결과 요약"
echo "=========================================="
echo -e "통과: ${GREEN}${PASSED}${NC} / 총 $((PASSED + FAILED))개"
echo -e "실패: ${RED}${FAILED}${NC} / 총 $((PASSED + FAILED))개"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 모든 테스트 통과!${NC}"
    echo "Phase 6: MQTT Bridge가 정상적으로 작동합니다."
    echo ""
    echo "다음 단계:"
    echo "  - 통합 테스트 (모든 센서 + MQTT 동시 실행)"
    echo "  - Scenario Manager 구현"
    exit 0
else
    echo ""
    echo -e "${RED}❌ 일부 테스트 실패${NC}"
    echo "MQTT Bridge 구현을 확인하세요."
    echo ""
    echo "로그 파일:"
    echo "  - /tmp/ros2_mqtt_build.log"
    echo "  - /tmp/mqtt_connection.log"
    echo "  - /tmp/mqtt_bridge.log"
    echo "  - /tmp/mqtt_message.log"
    exit 1
fi
