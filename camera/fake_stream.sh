#!/bin/bash
# KOBOT 시뮬레이터 카메라 스트리밍 스크립트
#
# FFmpeg을 사용하여 3채널 카메라 스트림을 MediaMTX로 전송합니다.
# 실제 KOBOT의 카메라를 시뮬레이션하기 위해 각 카메라별로 다른 테스트 패턴을 사용합니다.
#
# 📸 카메라 구성:
#   - cam1: 주행용 카메라 (컬러 바 패턴)
#   - cam2: 인식용 카메라 1 (Mandelbrot 프랙탈 애니메이션)
#   - cam3: 인식용 카메라 2 (Game of Life 애니메이션)
#
# 사용법:
#   bash fake_stream.sh <KOBOT_NAMESPACE> <MEDIAMTX_HOST> <MEDIAMTX_PORT>
#
# 예시:
#   bash fake_stream.sh kobot_a1b2c3d4e5f6 mediamtx 1935
#   bash fake_stream.sh kobot_a1b2c3d4e5f6 192.168.1.100 1935

set -e

# ============================================================================
# 환경 변수 검증
# ============================================================================
if [ -z "$1" ]; then
    echo "Error: KOBOT_NAMESPACE is required"
    echo "Usage: bash fake_stream.sh <KOBOT_NAMESPACE> <MEDIAMTX_HOST> <MEDIAMTX_PORT>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: MEDIAMTX_HOST is required"
    echo "Usage: bash fake_stream.sh <KOBOT_NAMESPACE> <MEDIAMTX_HOST> <MEDIAMTX_PORT>"
    exit 1
fi

KOBOT_NAMESPACE=${1}
MEDIAMTX_HOST=${2}
MEDIAMTX_PORT=${3:-1935}

# 환경 변수에서 카메라 설정 로드 (기본값 포함)
CAMERA_RESOLUTION=${CAMERA_RESOLUTION:-1280x720}
CAMERA_FPS=${CAMERA_FPS:-30}
CAMERA_BITRATE=${CAMERA_BITRATE:-2M}

echo "=========================================="
echo "KOBOT Camera Streaming Simulator"
echo "=========================================="
echo "Namespace:    ${KOBOT_NAMESPACE}"
echo "MediaMTX:     ${MEDIAMTX_HOST}:${MEDIAMTX_PORT}"
echo "Resolution:   ${CAMERA_RESOLUTION}"
echo "FPS:          ${CAMERA_FPS}"
echo "Bitrate:      ${CAMERA_BITRATE}"
echo "=========================================="

# ============================================================================
# 카메라 스트리밍 함수
# ============================================================================
# FFmpeg을 사용하여 각 카메라별로 다른 테스트 패턴을 RTMP로 스트리밍합니다.
#
# 인자:
#   $1: 카메라 번호 (1, 2, 3)
#
# RTMP URL 형식:
#   rtmp://{MEDIAMTX_HOST}:{MEDIAMTX_PORT}/koai/{namespace}/live/cam{1~3}
stream_camera() {
    local CAM_NUM=$1
    local RTMP_URL="rtmp://${MEDIAMTX_HOST}:${MEDIAMTX_PORT}/koai/${KOBOT_NAMESPACE}/live/cam${CAM_NUM}"

    echo "[Camera ${CAM_NUM}] Starting stream to ${RTMP_URL}"

    # 카메라별로 다른 테스트 패턴 선택
    case ${CAM_NUM} in
        1)
            # 📹 CAM1: 주행용 카메라 - 컬러 바 패턴 (testsrc2)
            # 움직이는 그라데이션으로 주행 화면 시뮬레이션
            local VIDEO_FILTER="testsrc2=size=${CAMERA_RESOLUTION}:rate=${CAMERA_FPS}"
            local CAM_DESC="CAM1 (Navigation)"
            local CAM_COLOR="yellow"
            ;;
        2)
            # 📹 CAM2: 인식용 카메라 1 - RGB 테스트 패턴
            # 컬러 그라데이션으로 객체 인식 시뮬레이션
            local VIDEO_FILTER="rgbtestsrc=size=${CAMERA_RESOLUTION}:rate=${CAMERA_FPS}"
            local CAM_DESC="CAM2 (Recognition-1)"
            local CAM_COLOR="cyan"
            ;;
        3)
            # 📹 CAM3: 인식용 카메라 2 - Game of Life 애니메이션
            # 셀룰러 오토마타로 동적 환경 시뮬레이션
            local VIDEO_FILTER="life=size=${CAMERA_RESOLUTION}:rate=${CAMERA_FPS}:random_seed=1"
            local CAM_DESC="CAM3 (Recognition-2)"
            local CAM_COLOR="lime"
            ;;
        *)
            echo "[Camera ${CAM_NUM}] Error: Invalid camera number"
            return 1
            ;;
    esac

    # FFmpeg 테스트 패턴 생성 및 RTMP 스트리밍
    # 1. 카메라별 고유 테스트 패턴 생성 (testsrc2, mandelbrot, life)
    # 2. drawtext: 카메라 정보 오버레이 (namespace, 카메라 설명, 타임스탬프)
    # 3. H.264 인코딩 (baseline profile, 낮은 레이턴시)
    # 4. RTMP 전송 (reconnect on error)
    ffmpeg \
        -re \
        -f lavfi \
        -i "${VIDEO_FILTER}" \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='${KOBOT_NAMESPACE}':fontcolor=white:fontsize=20:box=1:boxcolor=black@0.7:\
boxborderw=5:x=10:y=10,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='${CAM_DESC}':fontcolor=${CAM_COLOR}:fontsize=36:box=1:boxcolor=black@0.7:\
boxborderw=5:x=(w-text_w)/2:y=60,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='%{localtime\:%Y-%m-%d %H\\\\:%M\\\\:%S}':fontcolor=white:fontsize=18:box=1:boxcolor=black@0.7:\
boxborderw=5:x=10:y=h-th-10" \
        -c:v libx264 \
        -preset ultrafast \
        -tune zerolatency \
        -profile:v baseline \
        -b:v ${CAMERA_BITRATE} \
        -maxrate ${CAMERA_BITRATE} \
        -bufsize $((2 * ${CAMERA_BITRATE%M} * 1024))k \
        -g $((CAMERA_FPS * 2)) \
        -keyint_min ${CAMERA_FPS} \
        -sc_threshold 0 \
        -pix_fmt yuv420p \
        -f flv \
        -reconnect 1 \
        -reconnect_at_eof 1 \
        -reconnect_streamed 1 \
        -reconnect_delay_max 5 \
        "${RTMP_URL}" \
        2>&1 | while IFS= read -r line; do
            echo "[Camera ${CAM_NUM}] ${line}"
        done &

    # 프로세스 ID 저장
    local PID=$!
    echo "[Camera ${CAM_NUM}] Started with PID: ${PID} (Pattern: ${VIDEO_FILTER%%=*})"

    # PID를 전역 배열에 저장 (종료 시 정리용)
    CAMERA_PIDS+=($PID)
}

# ============================================================================
# 시그널 핸들러 (정리 작업)
# ============================================================================
cleanup() {
    echo ""
    echo "=========================================="
    echo "Stopping camera streams..."
    echo "=========================================="

    for pid in "${CAMERA_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Killing process: ${pid}"
            kill "$pid" 2>/dev/null || true
        fi
    done

    echo "All camera streams stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM

# ============================================================================
# 3채널 카메라 스트리밍 시작
# ============================================================================
CAMERA_PIDS=()

# MediaMTX 연결 대기 (최대 30초)
echo "Waiting for MediaMTX to be ready..."
WAIT_TIMEOUT=30
WAIT_COUNT=0
while ! nc -z ${MEDIAMTX_HOST} ${MEDIAMTX_PORT} 2>/dev/null; do
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $WAIT_COUNT -ge $WAIT_TIMEOUT ]; then
        echo "Error: MediaMTX not available after ${WAIT_TIMEOUT} seconds"
        echo "Please check:"
        echo "  1. MediaMTX is running: docker ps | grep mediamtx"
        echo "  2. MEDIAMTX_HOST=${MEDIAMTX_HOST} is correct"
        echo "  3. Port ${MEDIAMTX_PORT} is accessible"
        exit 1
    fi
done
echo "MediaMTX is ready!"

# 각 채널별로 약간의 지연을 두고 시작 (동시 시작으로 인한 부하 방지)
echo ""
echo "Starting camera streams with unique patterns..."
echo "  📹 CAM1: testsrc2 (Color bars - Navigation)"
echo "  📹 CAM2: mandelbrot (Fractal - Recognition-1)"
echo "  📹 CAM3: life (Game of Life - Recognition-2)"
echo ""

stream_camera 1
sleep 2

stream_camera 2
sleep 2

stream_camera 3
sleep 2

echo ""
echo "=========================================="
echo "All camera streams started successfully!"
echo "=========================================="
echo "RTMP URLs (KOBOT → MediaMTX):"
echo "  Camera 1: rtmp://${MEDIAMTX_HOST}:${MEDIAMTX_PORT}/koai/${KOBOT_NAMESPACE}/live/cam1"
echo "  Camera 2: rtmp://${MEDIAMTX_HOST}:${MEDIAMTX_PORT}/koai/${KOBOT_NAMESPACE}/live/cam2"
echo "  Camera 3: rtmp://${MEDIAMTX_HOST}:${MEDIAMTX_PORT}/koai/${KOBOT_NAMESPACE}/live/cam3"
echo ""
echo "WebRTC URLs (Client playback):"
echo "  Camera 1: http://${MEDIAMTX_HOST}:8889/koai/${KOBOT_NAMESPACE}/live/cam1/whep"
echo "  Camera 2: http://${MEDIAMTX_HOST}:8889/koai/${KOBOT_NAMESPACE}/live/cam2/whep"
echo "  Camera 3: http://${MEDIAMTX_HOST}:8889/koai/${KOBOT_NAMESPACE}/live/cam3/whep"
echo "=========================================="
echo ""
echo "Press Ctrl+C to stop all streams..."

# 메인 프로세스 유지 (카메라 스트림 모니터링)
while true; do
    # 모든 카메라 프로세스가 살아있는지 확인
    ALL_ALIVE=true
    for pid in "${CAMERA_PIDS[@]}"; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "Warning: Camera process ${pid} died. Restarting all streams..."
            ALL_ALIVE=false
            break
        fi
    done

    # 하나라도 죽었다면 모두 재시작
    if [ "$ALL_ALIVE" = false ]; then
        cleanup
        exec "$0" "$@"  # 스크립트 자체를 재실행
    fi

    sleep 5
done
