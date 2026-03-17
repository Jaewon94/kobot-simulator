#!/bin/bash
# Phase 5 검증 테스트: System Status Publisher 노드
#
# 테스트 항목:
#   1. System Status Publisher 파일 존재 확인
#   2. System Status Publisher 문법 확인
#   3. System Status Publisher import 확인
#   4. std_msgs/String 메시지 타입 확인
#   5. ROS2 워크스페이스 빌드
#   6. System Status Publisher 노드 실행 (5초)
#   7. System Status 토픽 발행 확인

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
echo "Phase 5: System Status Publisher 노드 검증 테스트"
echo "=========================================="

# 현재 디렉토리 확인
if [ ! -d "ros2_ws/src/kobot_simulator" ]; then
    echo -e "${RED}Error: ros2_ws/src/kobot_simulator not found${NC}"
    echo "Please run this script from simulator/ directory"
    exit 1
fi

# Test 1: System Status Publisher 파일 확인
test_step "System Status Publisher 파일 확인" \
    "[ -f ros2_ws/src/kobot_simulator/kobot_simulator/system_status_publisher.py ]"

# Test 2: System Status Publisher Python 문법 확인
test_step "System Status Publisher Python 문법 확인" \
    "python3 -m py_compile ros2_ws/src/kobot_simulator/kobot_simulator/system_status_publisher.py"

# Test 3: System Status Publisher import 확인 (Docker 내부)
test_step "System Status Publisher import 확인 (Docker)" \
    "docker run --rm -v $(pwd)/ros2_ws:/root/ros2_ws kobot-sim:test \
     python3 -c 'import sys; sys.path.insert(0, \"/root/ros2_ws/src/kobot_simulator\"); from kobot_simulator import system_status_publisher'"

# Test 4: ROS2 메시지 타입 확인
test_step "std_msgs/String 메시지 타입 확인" \
    "docker run --rm kobot-sim:test bash -c 'source /opt/ros/humble/setup.bash && ros2 interface show std_msgs/msg/String' | grep -q 'data'"

# Test 5: ROS2 워크스페이스 빌드 (Docker 내부)
echo -e "\n${YELLOW}[TEST]${NC} ROS2 워크스페이스 빌드"
docker run --rm \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && source /opt/ros/humble/setup.bash && colcon build --packages-select kobot_simulator" \
    > /tmp/ros2_system_build.log 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → Build log: /tmp/ros2_system_build.log"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → Build log: /tmp/ros2_system_build.log"
    cat /tmp/ros2_system_build.log
    ((FAILED++))
fi

# Test 6: System Status Publisher 노드 실행 테스트 (5초간 실행)
echo -e "\n${YELLOW}[TEST]${NC} System Status Publisher 노드 실행 (5초)"
docker run --rm \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    -e KOBOT_NAMESPACE=kobot_test \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && \
             source /opt/ros/humble/setup.bash && \
             export PYTHONPATH=/root/ros2_ws/install/kobot_simulator/lib/python3.10/site-packages:\$PYTHONPATH && \
             export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
             timeout 5s /root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/system_status_publisher \
                --ros-args \
                -p namespace:=kobot_test" \
    > /tmp/system_publisher.log 2>&1

if [ $? -eq 124 ]; then
    # timeout 명령의 정상 종료 코드 (124)
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → System Status Publisher가 5초간 정상 실행됨"
    echo "  → Log: /tmp/system_publisher.log"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → System Status Publisher 실행 실패"
    echo "  → Log: /tmp/system_publisher.log"
    cat /tmp/system_publisher.log
    ((FAILED++))
fi

# Test 7: System Status 토픽 발행 확인 (별도 컨테이너에서 확인)
echo -e "\n${YELLOW}[TEST]${NC} System Status 토픽 발행 확인 (백그라운드 실행)"
echo "  → System Status Publisher 시작..."

# System Status Publisher 백그라운드 실행
docker run --rm -d \
    --name kobot-system-test \
    --network bridge \
    -v $(pwd)/ros2_ws:/root/ros2_ws \
    kobot-sim:test \
    bash -c "cd /root/ros2_ws && \
             source /opt/ros/humble/setup.bash && \
             export PYTHONPATH=/root/ros2_ws/install/kobot_simulator/lib/python3.10/site-packages:\$PYTHONPATH && \
             export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
             /root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/system_status_publisher \
                --ros-args \
                -p namespace:=kobot_test" \
    > /dev/null 2>&1

# 3초 대기 (토픽 발행 대기)
sleep 3

# 토픽 리스트 확인
docker exec kobot-system-test bash -c \
    "source /opt/ros/humble/setup.bash && \
     export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:\$AMENT_PREFIX_PATH && \
     ros2 topic list" \
    > /tmp/system_topic_list.log 2>&1

if grep -q "kobot_test/system/status" /tmp/system_topic_list.log; then
    echo -e "${GREEN}✓ PASS${NC}"
    echo "  → System Status 토픽이 정상적으로 발행됨: /kobot_test/system/status"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  → System Status 토픽을 찾을 수 없음"
    echo "  → Topic list:"
    cat /tmp/system_topic_list.log
    ((FAILED++))
fi

# 컨테이너 정리
docker stop kobot-system-test > /dev/null 2>&1 || true

echo ""
echo "=========================================="
echo "테스트 결과 요약"
echo "=========================================="
echo -e "통과: ${GREEN}${PASSED}${NC} / 총 $((PASSED + FAILED))개"
echo -e "실패: ${RED}${FAILED}${NC} / 총 $((PASSED + FAILED))개"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 모든 테스트 통과!${NC}"
    echo "Phase 5: System Status Publisher 노드가 정상적으로 작동합니다."
    echo ""
    echo -e "${GREEN}=========================================="
    echo "✅ 모든 센서 노드 구현 완료!"
    echo "==========================================${NC}"
    echo ""
    echo "구현된 센서 노드:"
    echo "  ✓ GPS Publisher (1 Hz)"
    echo "  ✓ IMU Publisher (50 Hz)"
    echo "  ✓ LiDAR Publisher (10 Hz)"
    echo "  ✓ System Status Publisher (1 Hz)"
    echo ""
    echo "다음 단계:"
    echo "  - MQTT Bridge 구현"
    echo "  - Scenario Manager 구현"
    echo "  - 통합 테스트"
    exit 0
else
    echo ""
    echo -e "${RED}❌ 일부 테스트 실패${NC}"
    echo "System Status Publisher 구현을 확인하세요."
    echo ""
    echo "로그 파일:"
    echo "  - /tmp/ros2_system_build.log"
    echo "  - /tmp/system_publisher.log"
    echo "  - /tmp/system_topic_list.log"
    exit 1
fi
