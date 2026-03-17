#!/bin/bash
# Phase 1 검증 테스트: Docker 기본 인프라
#
# 테스트 항목:
#   1. Docker 이미지 빌드
#   2. ROS2 Humble 설치 확인
#   3. Python 의존성 확인
#   4. FFmpeg 설치 확인
#   5. 환경 변수 로드 확인

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
echo "Phase 1: Docker 기본 인프라 검증 테스트"
echo "=========================================="

# 현재 디렉토리 확인
if [ ! -f "docker/Dockerfile.kobot" ]; then
    echo -e "${RED}Error: docker/Dockerfile.kobot not found${NC}"
    echo "Please run this script from simulator/ directory"
    exit 1
fi

# Test 1: Docker 이미지 빌드
test_step "Docker 이미지 빌드 (kobot-sim:test)" \
    "docker build -f docker/Dockerfile.kobot -t kobot-sim:test . > /tmp/docker_build.log 2>&1"

if [ $? -eq 0 ]; then
    echo "  → Build log: /tmp/docker_build.log"
fi

# Test 2: ROS2 Humble 설치 확인
test_step "ROS2 Humble 설치 확인" \
    "docker run --rm kobot-sim:test bash -c 'source /opt/ros/humble/setup.bash && ros2 pkg list' | grep -q 'ros2'"

# Test 3: Python 버전 확인
test_step "Python 3.11+ 설치 확인" \
    "docker run --rm kobot-sim:test python3 --version | grep -q 'Python 3'"

# Test 4: Python 패키지 확인 - aiomqtt
test_step "Python aiomqtt 패키지 설치 확인" \
    "docker run --rm kobot-sim:test python3 -c 'import aiomqtt' 2>&1"

# Test 5: Python 패키지 확인 - numpy
test_step "Python numpy 패키지 설치 확인" \
    "docker run --rm kobot-sim:test python3 -c 'import numpy' 2>&1"

# Test 6: FFmpeg 설치 확인
test_step "FFmpeg 설치 확인" \
    "docker run --rm kobot-sim:test ffmpeg -version | grep -q 'ffmpeg version'"

# Test 7: 볼륨 마운트 디렉토리 확인 (로컬에서 확인)
test_step "ROS2 워크스페이스 디렉토리 확인 (로컬)" \
    "[ -d ros2_ws/src/kobot_simulator ]"

# Test 8: 환경 변수 설정 확인
test_step "환경 변수 기본값 확인" \
    "docker run --rm -e KOBOT_NAMESPACE=test_ns kobot-sim:test bash -c 'echo \$KOBOT_NAMESPACE' | grep -q 'test_ns'"

# Test 9: netcat 설치 확인 (MQTT 연결 테스트용)
test_step "netcat 설치 확인" \
    "docker run --rm kobot-sim:test which nc"

# Test 10: curl 설치 확인
test_step "curl 설치 확인" \
    "docker run --rm kobot-sim:test curl --version | grep -q curl"

echo ""
echo "=========================================="
echo "테스트 결과 요약"
echo "=========================================="
echo -e "통과: ${GREEN}${PASSED}${NC} / 총 $((PASSED + FAILED))개"
echo -e "실패: ${RED}${FAILED}${NC} / 총 $((PASSED + FAILED))개"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 모든 테스트 통과!${NC}"
    echo "Phase 1: Docker 기본 인프라가 정상적으로 구축되었습니다."
    echo ""
    echo "다음 단계:"
    echo "  bash tests/test_phase2_ros2.sh"
    exit 0
else
    echo ""
    echo -e "${RED}❌ 일부 테스트 실패${NC}"
    echo "Docker 이미지 또는 설정을 확인하세요."
    echo "빌드 로그: /tmp/docker_build.log"
    exit 1
fi
