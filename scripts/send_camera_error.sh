#!/bin/bash
# ============================================================
# 카메라 에러 MQTT 시뮬레이터 (v5.12)
#
# 코아이 KOBOT이 카메라 에러를 백엔드에 보내는 방식을 시뮬레이션합니다.
# 실제 운영에서는 KOBOT의 ROS2 노드가 이 메시지를 발행합니다.
#
# 사용법:
#   # 기본 (kobot1, cam1, STREAM_TIMEOUT 에러)
#   ./send_camera_error.sh
#
#   # 특정 KOBOT + 카메라 + 에러 코드
#   ./send_camera_error.sh kobot2 cam3 ENCODING_ERROR "H264 인코딩 실패"
#
#   # 반복 발생 (5초 간격으로 3번)
#   ./send_camera_error.sh kobot1 cam1 STREAM_TIMEOUT "" 3 5
#
# MQTT 토픽: koai/{namespace}/error/camera
# QoS: 1 (최소 1회 전달 보장)
#
# 코아이 참고사항:
#   - 토픽 구조는 반드시 koai/{namespace}/error/camera 형식
#   - data.camera: cam1~cam5 중 하나
#   - data.error_code: 자유 형식 (아래 예시 참고)
#   - data.error_message: 사람이 읽을 수 있는 에러 설명
#   - data.details: 선택사항, 추가 디버깅 정보
#
# 에러 코드 예시 (코아이에서 정의):
#   STREAM_TIMEOUT    - RTMP 스트림 전송 타임아웃
#   ENCODING_ERROR    - 영상 인코딩 실패
#   DEVICE_ERROR      - 카메라 하드웨어 에러
#   RESOLUTION_ERROR  - 해상도 변경 실패
#   NETWORK_ERROR     - 네트워크 전송 에러
#   LOW_FRAMERATE     - 프레임레이트 저하 (10fps 이하)
# ============================================================

set -e

# 파라미터 (기본값 포함)
NAMESPACE="${1:-kobot1}"
CAMERA="${2:-cam1}"
ERROR_CODE="${3:-STREAM_TIMEOUT}"
ERROR_MESSAGE="${4:-}"
REPEAT="${5:-1}"
INTERVAL="${6:-0}"

# MQTT 브로커 설정
MQTT_HOST="${MQTT_HOST:-localhost}"
MQTT_PORT="${MQTT_PORT:-1883}"

# 에러 코드별 기본 메시지
if [ -z "$ERROR_MESSAGE" ]; then
    case "$ERROR_CODE" in
        STREAM_TIMEOUT)    ERROR_MESSAGE="RTMP 스트림 전송 타임아웃 (30초 초과)" ;;
        ENCODING_ERROR)    ERROR_MESSAGE="H264 인코딩 실패 — 카메라 재시작 필요" ;;
        DEVICE_ERROR)      ERROR_MESSAGE="카메라 디바이스 응답 없음 (/dev/video0)" ;;
        RESOLUTION_ERROR)  ERROR_MESSAGE="1280x720 해상도 설정 실패" ;;
        NETWORK_ERROR)     ERROR_MESSAGE="RTMP 서버 연결 불가 (connection refused)" ;;
        LOW_FRAMERATE)     ERROR_MESSAGE="프레임레이트 저하 (현재 5fps, 기준 15fps)" ;;
        *)                 ERROR_MESSAGE="알 수 없는 카메라 에러: ${ERROR_CODE}" ;;
    esac
fi

TOPIC="koai/${NAMESPACE}/error/camera"

echo "============================================"
echo "📹 카메라 에러 시뮬레이터"
echo "============================================"
echo "  MQTT Broker: ${MQTT_HOST}:${MQTT_PORT}"
echo "  Topic:       ${TOPIC}"
echo "  Namespace:   ${NAMESPACE}"
echo "  Camera:      ${CAMERA}"
echo "  Error Code:  ${ERROR_CODE}"
echo "  Message:     ${ERROR_MESSAGE}"
echo "  Repeat:      ${REPEAT}회 (간격: ${INTERVAL}초)"
echo "============================================"
echo ""

for i in $(seq 1 "$REPEAT"); do
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    PAYLOAD=$(cat <<EOF
{
    "type": "camera_error",
    "namespace": "${NAMESPACE}",
    "timestamp": "${TIMESTAMP}",
    "data": {
        "camera": "${CAMERA}",
        "error_code": "${ERROR_CODE}",
        "error_message": "${ERROR_MESSAGE}",
        "details": {
            "retry_count": ${i},
            "uptime_seconds": $((RANDOM % 3600 + 60))
        }
    }
}
EOF
)

    echo "[${i}/${REPEAT}] ${TIMESTAMP} — ${NAMESPACE}/${CAMERA} ${ERROR_CODE}"

    # mosquitto_pub 또는 Docker exec로 발행
    if command -v mosquitto_pub &> /dev/null; then
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "$TOPIC" -q 1 \
            -m "$PAYLOAD"
    elif docker ps --format '{{.Names}}' | grep -q "mosquitto\|mqtt"; then
        # Docker 컨테이너 내부에서 발행
        CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "mosquitto|mqtt" | head -1)
        docker exec "$CONTAINER" mosquitto_pub \
            -h localhost -p 1883 \
            -t "$TOPIC" -q 1 \
            -m "$PAYLOAD"
    else
        echo "❌ mosquitto_pub 명령어를 찾을 수 없습니다."
        echo "   설치: brew install mosquitto  또는  apt install mosquitto-clients"
        exit 1
    fi

    echo "   ✅ 전송 완료"

    # 반복 시 대기
    if [ "$i" -lt "$REPEAT" ] && [ "$INTERVAL" -gt 0 ]; then
        sleep "$INTERVAL"
    fi
done

echo ""
echo "🏁 완료 — ${REPEAT}건 카메라 에러 전송"
