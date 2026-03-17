#!/bin/bash
set -e

# KOBOT ID 확인 (환경 변수 또는 첫 번째 인자)
KOBOT_ID=${1:-001}

# ROS2 환경 설정
cd /root/ros2_ws
source /opt/ros/humble/setup.bash

# ROS2 워크스페이스 빌드 (최초 1회)
if [ ! -f "/root/ros2_ws/install/setup.bash" ]; then
    echo "[KOBOT-$KOBOT_ID] Building ROS2 workspace..."
    colcon build --symlink-install

    echo "[KOBOT-$KOBOT_ID] Installing Python package metadata..."
    cd /root/ros2_ws/src/kobot_simulator
    pip3 install -e . -q
    cd /root/ros2_ws
fi

source /root/ros2_ws/install/setup.bash
export PYTHONPATH=/root/ros2_ws/install/kobot_simulator/lib/python3.10/site-packages:$PYTHONPATH
export AMENT_PREFIX_PATH=/root/ros2_ws/install/kobot_simulator:$AMENT_PREFIX_PATH

# KOBOT별 환경 변수 설정
NAMESPACE_VAR="KOBOT_${KOBOT_ID}_NAMESPACE"
INITIAL_LAT_VAR="KOBOT_${KOBOT_ID}_INITIAL_LAT"
INITIAL_LON_VAR="KOBOT_${KOBOT_ID}_INITIAL_LON"
INITIAL_ALT_VAR="KOBOT_${KOBOT_ID}_INITIAL_ALT"
SCENARIO_VAR="KOBOT_${KOBOT_ID}_SCENARIO"
USERNAME_VAR="KOBOT_${KOBOT_ID}_USERNAME"
PASSWORD_VAR="KOBOT_${KOBOT_ID}_PASSWORD"

# 환경 변수 값 가져오기
NAMESPACE=${!NAMESPACE_VAR}
INITIAL_LAT=${!INITIAL_LAT_VAR}
INITIAL_LON=${!INITIAL_LON_VAR}
INITIAL_ALT=${!INITIAL_ALT_VAR}
SCENARIO=${!SCENARIO_VAR}
MQTT_USERNAME=${!USERNAME_VAR}
MQTT_PASSWORD=${!PASSWORD_VAR}

# 환경 변수 확인
echo "[KOBOT-$KOBOT_ID] Namespace: $NAMESPACE"
echo "[KOBOT-$KOBOT_ID] MQTT Broker: $MQTT_BROKER:$MQTT_PORT"
echo "[KOBOT-$KOBOT_ID] Starting all sensor nodes..."

# 센서 노드 시작 (백그라운드)
# 발행 주기 조정: DB 부하 감소를 위해 3~5초 간격으로 설정
# GPS: 3초에 1번 (0.33 Hz)
/root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/gps_publisher \
  --ros-args \
  -p namespace:=$NAMESPACE \
  -p initial_lat:=$INITIAL_LAT \
  -p initial_lon:=$INITIAL_LON \
  -p initial_alt:=$INITIAL_ALT \
  -p scenario:=$SCENARIO \
  -p update_rate:=0.33 &

# IMU: 2초에 1번 (0.5 Hz) - 원래 50Hz였으나 시뮬레이션에서는 과도
/root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/imu_publisher \
  --ros-args \
  -p namespace:=$NAMESPACE \
  -p scenario:=$SCENARIO \
  -p update_rate:=0.5 &

# LiDAR: 3초에 1번 (0.33 Hz) - 원래 10Hz였으나 시뮬레이션에서는 과도
/root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/lidar_publisher \
  --ros-args \
  -p namespace:=$NAMESPACE \
  -p scenario:=$SCENARIO \
  -p update_rate:=0.33 &

# System Status: 5초에 1번 (0.2 Hz) - 배터리, CPU 등은 자주 변하지 않음
/root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/system_status_publisher \
  --ros-args \
  -p namespace:=$NAMESPACE \
  -p scenario:=$SCENARIO \
  -p update_rate:=0.2 &

# MQTT Bridge 시작 대기
sleep 3
echo "[KOBOT-$KOBOT_ID] Starting MQTT Bridge..."

# MQTT Bridge 시작 (백그라운드)
/root/ros2_ws/install/kobot_simulator/lib/kobot_simulator/mqtt_bridge \
  --ros-args \
  -p namespace:=$NAMESPACE \
  -p mqtt_broker_host:=$MQTT_BROKER \
  -p mqtt_broker_port:=$MQTT_PORT \
  -p mqtt_username:=$MQTT_USERNAME \
  -p mqtt_password:=$MQTT_PASSWORD &

# 카메라 스트리밍 자동 시작 (환경 변수로 제어)
if [ "$CAMERA_AUTO_START" = "true" ]; then
  echo "[KOBOT-$KOBOT_ID] CAMERA_AUTO_START=true, starting camera streaming..."
  sleep 2  # MQTT Bridge 안정화 대기

  # 카메라 스크립트가 존재하는지 확인
  if [ -f "/root/camera/fake_stream.sh" ]; then
    nohup bash /root/camera/fake_stream.sh "$NAMESPACE" "$MEDIAMTX_HOST" "$MEDIAMTX_RTMP_PORT" \
      > /tmp/camera_${NAMESPACE}.log 2>&1 &
    echo "[KOBOT-$KOBOT_ID] Camera streaming started (PID: $!)"
    echo "[KOBOT-$KOBOT_ID] Camera log: /tmp/camera_${NAMESPACE}.log"
  else
    echo "[KOBOT-$KOBOT_ID] WARNING: Camera script not found at /root/camera/fake_stream.sh"
  fi
else
  echo "[KOBOT-$KOBOT_ID] CAMERA_AUTO_START=false, camera streaming disabled"
  echo "[KOBOT-$KOBOT_ID] To start manually: bash /root/camera/fake_stream.sh $NAMESPACE $MEDIAMTX_HOST $MEDIAMTX_RTMP_PORT"
fi

# 컨테이너가 종료되지 않도록 대기
wait
