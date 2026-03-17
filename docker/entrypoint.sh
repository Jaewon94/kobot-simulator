#!/bin/bash
# KOBOT 시뮬레이터 컨테이너 시작 스크립트
#
# 실행 순서:
# 1. ROS2 센서 노드 및 명령 수신 노드 시작
# 2. MQTT Bridge 시작 (ROS2 ↔ MQTT 변환)
# 3. FFmpeg 카메라 스트리밍 시작 (3채널)

set -e

# ROS2 환경 로드
source /opt/ros/humble/setup.bash

# ROS2 워크스페이스가 빌드되어 있으면 로드
if [ -f "/root/ros2_ws/install/setup.bash" ]; then
    source /root/ros2_ws/install/setup.bash
fi

# 환경 변수 출력 (디버깅용)
echo "======================================"
echo "🤖 Starting KOBOT Simulator"
echo "======================================"
echo "   Namespace: $KOBOT_NAMESPACE"
echo "   Name: $KOBOT_NAME"
echo "   Initial Position: ($INITIAL_LAT, $INITIAL_LON, $INITIAL_ALT)"
echo "   Scenario: $SCENARIO"
echo "   MQTT Broker: $MQTT_BROKER:$MQTT_PORT"
echo "   MediaMTX: $MEDIAMTX_HOST:$MEDIAMTX_PORT"
echo "   ROS_DOMAIN_ID: $ROS_DOMAIN_ID"
echo "======================================"

# 1단계: ROS2 워크스페이스 빌드 (최초 1회 또는 변경 시)
if [ ! -f "/root/ros2_ws/install/setup.bash" ]; then
    echo "📦 Building ROS2 workspace..."
    cd /root/ros2_ws
    colcon build --symlink-install

    # Python 패키지 메타데이터 생성 (entry_points 인식을 위해 필수)
    echo "📦 Installing Python package metadata..."
    cd /root/ros2_ws/src/kobot_simulator
    pip3 install -e . -q

    cd /root/ros2_ws
    source /root/ros2_ws/install/setup.bash
    cd /root
fi

# 2단계: ROS2 센서 노드 시작 (백그라운드)
echo "🚀 Starting ROS2 sensor nodes..."
if [ -f "/root/ros2_ws/install/setup.bash" ]; then
    ros2 launch kobot_simulator kobot.launch.py \
        namespace:=$KOBOT_NAMESPACE \
        initial_lat:=$INITIAL_LAT \
        initial_lon:=$INITIAL_LON \
        initial_alt:=$INITIAL_ALT \
        scenario:=$SCENARIO &

    ROS2_PID=$!
    echo "✅ ROS2 nodes started (PID: $ROS2_PID)"
else
    echo "⚠️  ROS2 workspace not built yet. Skipping ROS2 nodes..."
fi

# 3단계: MQTT Bridge 시작 (백그라운드)
sleep 5  # ROS2 노드 초기화 대기
echo "🌉 Starting MQTT Bridge..."

python3 /root/mqtt_bridge/ros2_to_mqtt.py \
    --namespace $KOBOT_NAMESPACE \
    --broker $MQTT_BROKER \
    --port $MQTT_PORT \
    --username $MQTT_USERNAME \
    --password $MQTT_PASSWORD &

MQTT_ROS2_PID=$!
echo "✅ MQTT Bridge (ROS2→MQTT) started (PID: $MQTT_ROS2_PID)"

python3 /root/mqtt_bridge/mqtt_to_ros2.py \
    --namespace $KOBOT_NAMESPACE \
    --broker $MQTT_BROKER \
    --port $MQTT_PORT \
    --username $MQTT_USERNAME \
    --password $MQTT_PASSWORD &

MQTT2_ROS2_PID=$!
echo "✅ MQTT Bridge (MQTT→ROS2) started (PID: $MQTT2_ROS2_PID)"

# 4단계: FFmpeg 카메라 스트리밍 시작 (백그라운드)
sleep 5  # MQTT Bridge 초기화 대기
echo "📹 Starting camera streams..."

bash /root/camera/fake_stream.sh \
    $KOBOT_NAMESPACE \
    $MEDIAMTX_HOST \
    $MEDIAMTX_PORT &

CAMERA_PID=$!
echo "✅ Camera streams started (PID: $CAMERA_PID)"

# 5단계: 메인 프로세스 유지 (컨테이너 종료 방지)
echo "======================================"
echo "✅ KOBOT Simulator is running!"
echo "======================================"
echo ""
echo "Press Ctrl+C to stop..."

# 모든 백그라운드 프로세스 대기
wait
