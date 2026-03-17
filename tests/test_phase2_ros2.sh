#!/bin/bash
# Phase 2 검증 테스트: ROS2 센서 노드
#
# 테스트 항목:
#   1. ROS2 패키지 구조 확인
#   2. GPS Publisher 파일 존재 확인
#   3. GPS Publisher 문법 확인 (Python)
#   4. ROS2 워크스페이스 빌드
#   5. GPS Publisher 노드 실행 (5초)
#   6. GPS 토픽 발행 확인

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
echo "Phase 2: ROS2 센서 노드 검증 테스트"
echo "=========================================="

# 현재 디렉토리 확인
if [ ! -d "ros2_ws/src/kobot_simulator" ]; then
    echo -e "${RED}Error: ros2_ws/src/kobot_simulator not found${NC}"
    echo "Please run this script from simulator/ directory"
    exit 1
fi

# Test 1: 패키지 파일 존재 확인
test_step "package.xml 파일 확인" \
    "[ -f ros2_ws/src/kobot_simulator/package.xml ]"

test_step "setup.py 파일 확인" \
    "[ -f ros2_ws/src/kobot_simulator/setup.py ]"

test_step "setup.cfg 파일 확인" \
    "[ -f ros2_ws/src/kobot_simulator/setup.cfg ]"

# Test 2: GPS Publisher 파일 확인
test_step "GPS Publisher 파일 확인" \
    "[ -f ros2_ws/src/kobot_simulator/kobot_simulator/gps_publisher.py ]"

# Test 3: GPS Publisher Python 문법 확인
test_step "GPS Publisher Python 문법 확인" \
    "python3 -m py_compile ros2_ws/src/kobot_simulator/kobot_simulator/gps_publisher.py"

# Test 4: GPS Publisher import 확인 (Docker 내부)
test_step "GPS Publisher import 확인 (Docker)" \
    "docker run --rm -v $(pwd)/ros2_ws:/root/ros2_ws kobot-sim:test \
     python3 -c 'import sys; sys.path.insert(0, \"/root/ros2_ws/src/kobot_simulator\"); from kobot_simulator import gps_publisher'"

# Test 5: ROS2 메시지 타입 확인
test_step "sensor_msgs/NavSatFix 메시지 타입 확인" \
    "docker run --rm kobot-sim:test bash -c 'source /opt/ros/humble/setup.bash && ros2 interface show sensor_msgs/msg/NavSatFix' | grep -q 'latitude'"

# Test 6: ROS2 워크스페이스 빌드 (Docker 내부)
echo -e "\n${YELLOW}[TEST]${NC} ROS2 워크스페이스 빌드"
docker run --rm \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && source /opt/ros/humble/setup.bash && colcon build --packages-select kobot_simulator" \
    > /tmp/ros2_build.log 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → Build log: /tmp/ros2_build.log"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → Build log: /tmp/ros2_build.log"
    cat /tmp/ros2_build.log
    ((FAILED++))
fi

# Test 7: GPS Publisher 노드 실행 테스트 (5초간 실행)
echo -e "\n${YELLOW}[TEST]${NC} GPS Publisher 노드 실행 (5초)"
docker run --rm \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    -e KOBOT_NAMESPACE=kobot_test \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && \
             source /opt/ros/humble/setup.bash && \
             export PYTHONPATH=/root/ros2_ws/install/kobot_simulator/lib/python3.10/site-packages:\$PYTHONPATH && \
             export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
             timeout 5s /root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/gps_publisher \
                --ros-args \
                -p namespace:=kobot_test \
                -p initial_lat:=35.1158 \
                -p initial_lon:=129.0403 \
                -p scenario:=stationary" \
    > /tmp/gps_publisher.log 2>&1

if [ $? -eq 124 ]; then
    # timeout 명령의 정상 종료 코드 (124)
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → GPS Publisher가 5초간 정상 실행됨"
    echo "  → Log: /tmp/gps_publisher.log"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → GPS Publisher 실행 실패"
    echo "  → Log: /tmp/gps_publisher.log"
    cat /tmp/gps_publisher.log
    ((FAILED++))
fi

# Test 8: GPS 토픽 발행 확인 (별도 컨테이너에서 확인)
echo -e "\n${YELLOW}[TEST]${NC} GPS 토픽 발행 확인 (백그라운드 실행)"
echo "  → GPS Publisher 시작..."

# GPS Publisher 백그라운드 실행
docker run --rm -d \
    --name kobot-gps-test \
    --network bridge \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && \
             source /opt/ros/humble/setup.bash && \
             export PYTHONPATH=/root/ros2_ws/install/kobot_simulator/lib/python3.10/site-packages:\$PYTHONPATH && \
             export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
             /root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/gps_publisher \
                --ros-args \
                -p namespace:=kobot_test \
                -p initial_lat:=35.1158 \
                -p initial_lon:=129.0403" \
    > /dev/null 2>&1

# 3초 대기 (토픽 발행 대기)
sleep 3

# 토픽 리스트 확인
docker exec kobot-gps-test bash -c \
    "source /opt/ros/humble/setup.bash && \
     export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
     ros2 topic list" \
    > /tmp/topic_list.log 2>&1

if grep -q "kobot_test/sensors/gps" /tmp/topic_list.log; then
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → GPS 토픽이 정상적으로 발행됨: /kobot_test/sensors/gps"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → GPS 토픽을 찾을 수 없음"
    echo "  → Topic list:"
    cat /tmp/topic_list.log
    ((FAILED++))
fi

# 컨테이너 정리
docker stop kobot-gps-test > /dev/null 2>&1 || true

echo ""
echo "=========================================="
echo "테스트 결과 요약"
echo "=========================================="
echo -e "통과: ${GREEN}${PASSED}${NC} / 총 $((PASSED + FAILED))개"
echo -e "실패: ${RED}${FAILED}${NC} / 총 $((PASSED + FAILED))개"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 모든 테스트 통과!${NC}"
    echo "Phase 2: ROS2 센서 노드가 정상적으로 작동합니다."
    echo ""
    echo "다음 단계:"
    echo "  - IMU Publisher 구현 (TDD)"
    echo "  - LiDAR Publisher 구현 (TDD)"
    echo "  - System Status Publisher 구현 (TDD)"
    exit 0
else
    echo ""
    echo -e "${RED}❌ 일부 테스트 실패${NC}"
    echo "ROS2 노드 또는 설정을 확인하세요."
    echo ""
    echo "로그 파일:"
    echo "  - /tmp/ros2_build.log"
    echo "  - /tmp/gps_publisher.log"
    echo "  - /tmp/topic_list.log"
    exit 1
fi
