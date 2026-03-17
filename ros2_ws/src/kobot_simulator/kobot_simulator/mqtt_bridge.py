#!/usr/bin/env python3
"""
MQTT Bridge 노드 (MQTT v1.7)

ROS2 센서 토픽을 구독하여 MQTT로 전송합니다.
백엔드와의 통신을 담당하는 핵심 브릿지입니다.

통신 흐름:
    ROS2 Topics → MQTT Bridge → MQTT Broker → Backend

MQTT 토픽 구조 (v1.7):
    - koai/{namespace}/gps (0.2Hz - 임시값)
    - koai/{namespace}/imu (0.2Hz - 임시값)
    - koai/{namespace}/lidar (0.33Hz - 임시값)
    - koai/{namespace}/status (0.2Hz - 임시값)
    - koai/{namespace}/cmd/autodrive (명령 수신)
    - koai/{namespace}/ack/autodrive (ACK 발행)

지원 센서:
    - GPS (sensor_msgs/NavSatFix) - Flat JSON, ROS2 원본 필드명
    - IMU (sensor_msgs/Imu) - Flat JSON, ROS2 원본 필드명
    - LiDAR (sensor_msgs/LaserScan) - Flat JSON, 10x 샘플링
    - System Status (std_msgs/String - JSON) - 완전 Flat 구조
"""

import asyncio
import json
import os
from datetime import datetime, timezone

import aiomqtt
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Imu, LaserScan, NavSatFix
from std_msgs.msg import String


class MQTTBridge(Node):
    """
    ROS2 → MQTT 브릿지 노드

    Parameters (ROS2):
        namespace (str): KOBOT namespace (예: kobot1, kobot2, kobot3)
        mqtt_broker_host (str): MQTT 브로커 호스트 (default: localhost)
        mqtt_broker_port (int): MQTT 브로커 포트 (default: 1883)
        mqtt_username (str): MQTT 사용자명 (옵션)
        mqtt_password (str): MQTT 비밀번호 (옵션)
    """

    def __init__(self):
        super().__init__('mqtt_bridge')

        # 파라미터 선언
        self.declare_parameter('namespace', os.getenv('KOBOT_NAMESPACE', 'kobot_simulator'))
        self.declare_parameter('mqtt_broker_host', os.getenv('MQTT_BROKER_HOST', 'localhost'))
        self.declare_parameter('mqtt_broker_port', int(os.getenv('MQTT_BROKER_PORT', '1883')))
        self.declare_parameter('mqtt_username', os.getenv('MQTT_USERNAME', ''))
        self.declare_parameter('mqtt_password', os.getenv('MQTT_PASSWORD', ''))

        # 파라미터 가져오기
        self.namespace = self.get_parameter('namespace').value
        self.mqtt_host = self.get_parameter('mqtt_broker_host').value
        self.mqtt_port = self.get_parameter('mqtt_broker_port').value
        self.mqtt_username = self.get_parameter('mqtt_username').value
        self.mqtt_password = self.get_parameter('mqtt_password').value

        # MQTT 클라이언트 (비동기로 초기화)
        self.mqtt_client = None
        self.mqtt_task = None

        # ROS2 Subscribers 생성
        self.gps_sub = self.create_subscription(
            NavSatFix,
            f'{self.namespace}/sensors/gps',
            self.gps_callback,
            10
        )

        self.imu_sub = self.create_subscription(
            Imu,
            f'{self.namespace}/sensors/imu',
            self.imu_callback,
            10
        )

        self.lidar_sub = self.create_subscription(
            LaserScan,
            f'{self.namespace}/sensors/lidar',
            self.lidar_callback,
            10
        )

        self.status_sub = self.create_subscription(
            String,
            f'{self.namespace}/system/status',
            self.status_callback,
            10
        )

        # Autodrive 명령을 GPS 노드로 전달하기 위한 Publisher
        self.autodrive_cmd_publisher = self.create_publisher(
            String,  # Waypoints JSON을 문자열로 전달
            f'/{self.namespace}/cmd/autodrive',
            10
        )

        # 메시지 큐 (비동기 처리를 위한 큐)
        self.message_queue = asyncio.Queue()

        # 통계
        self.msg_count = {
            'gps': 0,
            'imu': 0,
            'lidar': 0,
            'status': 0
        }

        self.get_logger().info(f'MQTT Bridge 시작 - {self.namespace}')
        self.get_logger().info(f'  MQTT Broker: {self.mqtt_host}:{self.mqtt_port}')

        # MQTT 연결 태스크는 나중에 시작 (이벤트 루프가 실행된 후)
        self.mqtt_task = None

    def _get_kobot_id_from_namespace(self) -> str:
        """namespace를 kobot_id로 변환 (새로운 토픽 구조용)"""
        # namespace가 이미 kobot1, kobot2 형태이므로 그대로 사용
        return self.namespace

    async def mqtt_loop(self):
        """MQTT 연결 및 메시지 전송 루프"""
        while rclpy.ok():
            try:
                # MQTT 클라이언트 생성 및 연결
                client_kwargs = {
                    'hostname': self.mqtt_host,
                    'port': self.mqtt_port
                }

                if self.mqtt_username:
                    client_kwargs['username'] = self.mqtt_username
                    client_kwargs['password'] = self.mqtt_password

                async with aiomqtt.Client(**client_kwargs) as client:
                    self.get_logger().info('MQTT 브로커에 연결됨')

                    # 명령 구독 설정 (새로운 구조만)
                    kobot_id = self._get_kobot_id_from_namespace()
                    command_topic = f"koai/{kobot_id}/cmd/autodrive"
                    
                    await client.subscribe(command_topic, qos=1)
                    self.get_logger().info(f'MQTT 명령 구독: {command_topic}')

                    # 메시지 수신 태스크 시작
                    receive_task = asyncio.create_task(self._receive_commands(client))

                    # 메시지 전송 루프
                    while rclpy.ok():
                        try:
                            # 큐에서 메시지 가져오기 (타임아웃 1초)
                            topic, payload = await asyncio.wait_for(
                                self.message_queue.get(),
                                timeout=1.0
                            )

                            # MQTT로 발행
                            await client.publish(topic, payload)

                            # 통계 업데이트
                            sensor_type = topic.split('/')[-1]
                            if sensor_type in ['gps', 'imu', 'lidar', 'status']:
                                self.msg_count[sensor_type] += 1

                            # 10초마다 통계 로그
                            total = sum(self.msg_count.values())
                            if total % 50 == 0:
                                self.get_logger().info(
                                    f'MQTT 전송 통계: GPS={self.msg_count["gps"]}, '
                                    f'IMU={self.msg_count["imu"]}, '
                                    f'LiDAR={self.msg_count["lidar"]}, '
                                    f'Status={self.msg_count["status"]}'
                                )

                        except asyncio.TimeoutError:
                            # 타임아웃은 정상 (큐가 비어있음)
                            continue

            except Exception as e:
                self.get_logger().error(f'MQTT 연결 실패: {e}')
                await asyncio.sleep(5)  # 5초 후 재연결

    async def _receive_commands(self, client):
        """MQTT 명령 수신 루프"""
        try:
            async for message in client.messages:
                topic = str(message.topic)
                payload = message.payload.decode('utf-8')
                
                self.get_logger().info(f'명령 수신: {topic} - {payload[:100]}...')
                
                # 새로운 명령 포맷 처리
                if '/cmd/autodrive' in topic:
                    await self._handle_autodrive_command(payload, client)
                    
        except Exception as e:
            self.get_logger().error(f'명령 수신 오류: {e}')

    async def _handle_autodrive_command(self, payload: str, client):
        """
        자동주행 명령 처리 및 ACK 발행 (MQTT v1.7)
        
        수신 토픽: koai/{namespace}/cmd/autodrive
        명령 포맷: {"cmd": "start"|"stop", "cmd_id": "...", "waypoints": [...]}
        
        ACK 토픽: koai/{namespace}/ack/autodrive
        ACK 포맷: {"ok": true|false, "cmd_id": "...", "error": "...", "ts_iso": "..."}
        
        지원 명령:
        - start: 자율주행 시작 (waypoints 필요)
        - stop: 자율주행 정지
        """
        try:
            command = json.loads(payload)
            cmd = command.get('cmd')
            cmd_id = command.get('cmd_id', '')
            
            # ACK 응답 준비
            kobot_id = self._get_kobot_id_from_namespace()
            ack_topic = f"koai/{kobot_id}/ack/autodrive"
            timestamp = self._get_iso_timestamp()
            
            if cmd == 'start':
                waypoints = command.get('waypoints', [])
                self.get_logger().info(f'자동주행 시작: 웨이포인트 {len(waypoints)}개')

                # GPS 노드로 전체 명령 전달
                self.autodrive_cmd_publisher.publish(String(data=payload))
                self.get_logger().info(f'GPS 노드로 자동주행 명령 전달: {payload[:100]}...')
                
                # 성공 ACK 발행
                ack_payload = json.dumps({
                    "ok": True,
                    "cmd_id": cmd_id,
                    "error": "",
                    "ts_iso": timestamp
                })
                await client.publish(ack_topic, ack_payload, qos=1)
                self.get_logger().info(f'ACK 발행: {ack_topic} - {ack_payload}')
                    
            elif cmd == 'stop':
                self.get_logger().info('자동주행 정지 명령 수신')

                # GPS 노드로 stop 명령 전달
                self.autodrive_cmd_publisher.publish(String(data=payload))
                self.get_logger().info(f'GPS 노드로 자동주행 정지 명령 전달: {payload}')

                # 성공 ACK 발행
                ack_payload = json.dumps({
                    "ok": True,
                    "cmd_id": cmd_id,
                    "error": "",
                    "ts_iso": timestamp
                })
                await client.publish(ack_topic, ack_payload, qos=1)
                self.get_logger().info(f'ACK 발행: {ack_topic} - {ack_payload}')
                
            else:
                # 알 수 없는 명령
                error_payload = json.dumps({
                    "ok": False,
                    "cmd_id": cmd_id,
                    "error": "unknown command (use start|stop)",
                    "ts_iso": timestamp
                })
                await client.publish(ack_topic, error_payload, qos=1)
                self.get_logger().warn(f'오류 ACK 발행: {ack_topic} - {error_payload}')
                
        except json.JSONDecodeError as e:
            # JSON 파싱 오류
            kobot_id = self._get_kobot_id_from_namespace()
            ack_topic = f"koai/{kobot_id}/ack/autodrive"
            error_payload = json.dumps({
                "ok": False,
                "cmd_id": "",
                "error": "payload must be JSON like {\"cmd\":\"start\"}",
                "ts_iso": self._get_iso_timestamp()
            })
            await client.publish(ack_topic, error_payload, qos=1)
            self.get_logger().error(f'JSON 파싱 오류 ACK 발행: {ack_topic} - {error_payload}')
        except Exception as e:
            # 기타 오류
            kobot_id = self._get_kobot_id_from_namespace()
            ack_topic = f"koai/{kobot_id}/ack/autodrive"
            cmd_id = ""
            try:
                command = json.loads(payload)
                cmd_id = command.get('cmd_id', '')
            except:
                pass
            error_payload = json.dumps({
                "ok": False,
                "cmd_id": cmd_id,
                "error": f"internal error: {str(e)}",
                "ts_iso": self._get_iso_timestamp()
            })
            await client.publish(ack_topic, error_payload, qos=1)
            self.get_logger().error(f'오류 ACK 발행: {ack_topic} - {error_payload}')


    def gps_callback(self, msg: NavSatFix):
        """GPS 메시지 콜백"""
        kobot_id = self._get_kobot_id_from_namespace()
        mqtt_topic = f'koai/{kobot_id}/gps'
        mqtt_payload = self._convert_gps_to_mqtt(msg)

        # 비동기 큐에 추가
        try:
            self.message_queue.put_nowait((mqtt_topic, mqtt_payload))
        except asyncio.QueueFull:
            self.get_logger().warn('MQTT 메시지 큐가 가득 참 (GPS)')

    def imu_callback(self, msg: Imu):
        """IMU 메시지 콜백"""
        kobot_id = self._get_kobot_id_from_namespace()
        mqtt_topic = f'koai/{kobot_id}/imu'
        mqtt_payload = self._convert_imu_to_mqtt(msg)

        try:
            self.message_queue.put_nowait((mqtt_topic, mqtt_payload))
        except asyncio.QueueFull:
            self.get_logger().warn('MQTT 메시지 큐가 가득 참 (IMU)')

    def lidar_callback(self, msg: LaserScan):
        """LiDAR 메시지 콜백"""
        kobot_id = self._get_kobot_id_from_namespace()
        mqtt_topic = f'koai/{kobot_id}/lidar'
        mqtt_payload = self._convert_lidar_to_mqtt(msg)

        try:
            self.message_queue.put_nowait((mqtt_topic, mqtt_payload))
        except asyncio.QueueFull:
            self.get_logger().warn('MQTT 메시지 큐가 가득 참 (LiDAR)')

    def status_callback(self, msg: String):
        """System Status 메시지 콜백"""
        self.get_logger().debug(f'Status callback received: {msg.data[:50]}...')
        kobot_id = self._get_kobot_id_from_namespace()
        mqtt_topic = f'koai/{kobot_id}/status'
        mqtt_payload = self._convert_status_to_mqtt(msg)

        try:
            self.message_queue.put_nowait((mqtt_topic, mqtt_payload))
        except asyncio.QueueFull:
            self.get_logger().warn('MQTT 메시지 큐가 가득 참 (Status)')

    def _convert_gps_to_mqtt(self, msg: NavSatFix) -> str:
        """
        GPS 메시지를 MQTT JSON으로 변환 (MQTT v1.7)
        
        - Flat 구조: ts_iso, header, status, latitude/longitude/altitude, position_covariance
        - ROS2 원본 필드명 유지
        - 발행 주기: 0.2Hz (5초에 1번) - 임시값
        """
        data = {
            "ts_iso": self._get_iso_timestamp(),
            "header": {
                "stamp": {
                    "sec": msg.header.stamp.sec,
                    "nanosec": msg.header.stamp.nanosec
                },
                "frame_id": msg.header.frame_id
            },
            "status": {
                "status": msg.status.status,
                "service": msg.status.service
            },
            "latitude": msg.latitude,
            "longitude": msg.longitude,
            "altitude": msg.altitude,
            "position_covariance": list(msg.position_covariance),
            "position_covariance_type": msg.position_covariance_type
        }
        return json.dumps(data)

    def _convert_imu_to_mqtt(self, msg: Imu) -> str:
        """
        IMU 메시지를 MQTT JSON으로 변환 (MQTT v1.7)
        
        - Flat 구조: ts_iso, header, orientation, angular_velocity, linear_acceleration, covariances
        - ROS2 원본 필드명 유지
        - frame_id: "imu" (고정값)
        - 발행 주기: 0.2Hz (5초에 1번) - 임시값
        """
        data = {
            "ts_iso": self._get_iso_timestamp(),
            "header": {
                "stamp": {
                    "sec": msg.header.stamp.sec,
                    "nanosec": msg.header.stamp.nanosec
                },
                "frame_id": "imu"
            },
            "orientation": {
                "x": msg.orientation.x,
                "y": msg.orientation.y,
                "z": msg.orientation.z,
                "w": msg.orientation.w
            },
            "orientation_covariance": list(msg.orientation_covariance),
            "angular_velocity": {
                "x": msg.angular_velocity.x,
                "y": msg.angular_velocity.y,
                "z": msg.angular_velocity.z
            },
            "angular_velocity_covariance": list(msg.angular_velocity_covariance),
            "linear_acceleration": {
                "x": msg.linear_acceleration.x,
                "y": msg.linear_acceleration.y,
                "z": msg.linear_acceleration.z
            },
            "linear_acceleration_covariance": list(msg.linear_acceleration_covariance)
        }
        return json.dumps(data)

    def _convert_lidar_to_mqtt(self, msg: LaserScan) -> str:
        """
        LiDAR 메시지를 MQTT JSON으로 변환 (MQTT v1.7)
        
        - Flat 구조: ts_iso, header, angle_*, range_*, ranges, intensities
        - ROS2 원본 필드명 유지
        - 10x 샘플링: MQTT 메시지 크기 축소 (~800 bytes)
        - frame_id: "lidar" (고정값)
        - 발행 주기: 0.33Hz (3초에 1번) - 임시값
        """
        # LiDAR 데이터는 크므로 10배 샘플링 (10개마다 1개씩)
        sample_rate = 10
        sampled_ranges = list(msg.ranges[::sample_rate])
        sampled_intensities = list(msg.intensities[::sample_rate]) if msg.intensities else []

        data = {
            "ts_iso": self._get_iso_timestamp(),
            "header": {
                "stamp": {
                    "sec": msg.header.stamp.sec,
                    "nanosec": msg.header.stamp.nanosec
                },
                "frame_id": "lidar"
            },
            "angle_min": msg.angle_min,
            "angle_max": msg.angle_max,
            "angle_increment": msg.angle_increment * sample_rate,  # 샘플링으로 인한 증가
            "time_increment": msg.time_increment,
            "scan_time": msg.scan_time,
            "range_min": msg.range_min,
            "range_max": msg.range_max,
            "ranges": sampled_ranges,
            "intensities": sampled_intensities
        }
        return json.dumps(data)

    def _convert_status_to_mqtt(self, msg: String) -> str:
        """
        System Status 메시지를 MQTT JSON으로 변환 (배터리 전용)

        - 1차년도: 배터리 정보만 전송
        - Flat 구조: ts_iso, header, battery_percentage (다른 센서와 동일한 구조)
        - 발행 주기: 0.2Hz (5초에 1번)
        """
        # msg.data는 이미 올바른 형식의 JSON string (system_status_publisher에서 생성)
        # ts_iso, header, battery_percentage가 포함되어 있으므로 그대로 반환
        return msg.data

    def _get_iso_timestamp(self) -> str:
        """현재 시각을 ISO 8601 형식으로 반환"""
        return datetime.now(timezone.utc).isoformat()

    def _ros_time_to_iso(self, stamp) -> str:
        """ROS2 Time을 ISO 8601 형식으로 변환"""
        timestamp = stamp.sec + stamp.nanosec * 1e-9
        dt = datetime.fromtimestamp(timestamp, tz=timezone.utc)
        return dt.isoformat()

    def destroy_node(self):
        """노드 종료 시 MQTT 연결 정리"""
        if self.mqtt_task:
            self.mqtt_task.cancel()
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)

    mqtt_bridge = MQTTBridge()

    # 비동기 이벤트 루프 생성 및 MQTT 태스크 시작
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    mqtt_bridge.mqtt_task = loop.create_task(mqtt_bridge.mqtt_loop())

    try:
        # ROS2 spin을 별도 스레드에서 실행
        import threading
        spin_thread = threading.Thread(target=rclpy.spin, args=(mqtt_bridge,), daemon=True)
        spin_thread.start()

        # 비동기 루프 실행
        loop.run_forever()

    except KeyboardInterrupt:
        pass
    finally:
        if mqtt_bridge.mqtt_task:
            mqtt_bridge.mqtt_task.cancel()
        mqtt_bridge.destroy_node()
        rclpy.shutdown()
        loop.close()


if __name__ == '__main__':
    main()
