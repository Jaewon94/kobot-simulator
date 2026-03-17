#!/usr/bin/env python3
"""
GPS Publisher 노드

실제 KOBOT의 GPS 센서를 시뮬레이션합니다.
sensor_msgs/NavSatFix 메시지를 발행합니다.

ROS2 토픽 사양:
    - docs/ros2_topic/ros2-gps-topic-spec.md 참조
    - 메시지 타입: sensor_msgs/NavSatFix
    - 좌표계: WGS 84 타원체

발행 데이터:
    - latitude: 위도 [degrees]
    - longitude: 경도 [degrees]
    - altitude: 고도 [m]
    - gps_status: GPS 수신 상태 (0~3)
    - num_satellites: 수신 위성 수
"""

import json
import math
import os
import random

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import NavSatFix, NavSatStatus
from std_msgs.msg import Header, String


class GPSPublisher(Node):
    """
    GPS 센서 데이터를 발행하는 ROS2 노드

    시나리오에 따라 KOBOT의 위치를 시뮬레이션합니다.

    Parameters (ROS2):
        namespace (str): KOBOT namespace (예: kobot1, kobot2, kobot3)
        initial_lat (float): 초기 위도 (default: 35.1158)
        initial_lon (float): 초기 경도 (default: 129.0403)
        initial_alt (float): 초기 고도 (default: 0.0)
        update_rate (float): 발행 주기 [Hz] (default: 0.2, 즉 5초에 1번)
        scenario (str): 시나리오 (patrol, stationary, random)
    """

    def __init__(self):
        super().__init__('gps_publisher')

        # 파라미터 선언 (환경 변수 또는 launch 파일에서 설정)
        self.declare_parameter('namespace', 'kobot_simulator')
        self.declare_parameter('initial_lat', 35.1158)  # 부산항 북항
        self.declare_parameter('initial_lon', 129.0403)
        self.declare_parameter('initial_alt', 0.0)
        self.declare_parameter('scenario', 'patrol')

        # 파라미터 가져오기
        self.namespace = self.get_parameter('namespace').value
        self.lat = self.get_parameter('initial_lat').value
        self.lon = self.get_parameter('initial_lon').value
        self.alt = self.get_parameter('initial_alt').value
        self.scenario = self.get_parameter('scenario').value

        # 발행 주기: 환경 변수 우선, 없으면 기본값 0.2Hz (5초에 1번)
        self.update_rate = float(os.getenv('GPS_RATE', '0.2'))

        # 시뮬레이션 상태
        self.time_elapsed = 0.0
        # 실제 해양 무인로봇 속도: 2노트 = 1.0m/s (저속 순찰)
        # GPS 1Hz 기준 → 1초에 1.0m 이동 = 0.000009도 (위도 1도 = 111km)
        self.speed = 0.00001  # 위도/경도 변화율 (1.0m/s @ 1Hz = 2노트)
        self.heading = 0.0  # 진행 방향 (라디안)

        # 자율주행 상태
        self.target_waypoints = []
        self.current_waypoint_index = 0

        # 정박 기준점 (stationary 모드에서 사용)
        self.stationary_base_lat = self.lat
        self.stationary_base_lon = self.lon
        self.previous_scenario = self.scenario

        # Publisher 생성
        self.publisher = self.create_publisher(
            NavSatFix,
            f'{self.namespace}/sensors/gps',
            10
        )

        # 자율주행 명령 Subscriber 생성
        self.autodrive_cmd_subscriber = self.create_subscription(
            String,
            f'/{self.namespace}/cmd/autodrive',
            self.autodrive_cmd_callback,
            10
        )

        # 타이머 생성 (주기적 발행)
        timer_period = 1.0 / self.update_rate  # seconds
        self.timer = self.create_timer(timer_period, self.timer_callback)

        self.get_logger().info(
            f'GPS Publisher 시작 - {self.namespace}'
        )
        self.get_logger().info(
            f'  초기 위치: ({self.lat:.8f}, {self.lon:.8f}, {self.alt:.2f}m)'
        )
        self.get_logger().info(
            f'  시나리오: {self.scenario}'
        )
        self.get_logger().info(
            f'  발행 주기: {self.update_rate} Hz'
        )

    def timer_callback(self):
        """
        타이머 콜백 - GPS 데이터 발행

        시나리오에 따라 KOBOT 위치 업데이트:
            - patrol: 순찰 경로 이동
            - stationary: 정지 (약간의 노이즈만 추가)
            - random: 랜덤 이동
        """
        # 시나리오 변경 감지: stationary로 전환 시 현재 위치를 기준점으로 설정
        if self.scenario == 'stationary' and self.previous_scenario != 'stationary':
            self.stationary_base_lat = self.lat
            self.stationary_base_lon = self.lon
            self.get_logger().info(
                f'정박 기준점 설정: ({self.stationary_base_lat:.8f}, {self.stationary_base_lon:.8f})'
            )
        self.previous_scenario = self.scenario

        # 시나리오별 위치 업데이트
        if self.scenario == 'autodrive':
            self._update_autodrive_position()
        elif self.scenario == 'idle':
            self._update_idle_position()
        elif self.scenario == 'patrol':
            self._update_patrol_position()
        elif self.scenario == 'stationary':
            self._update_stationary_position()
        elif self.scenario == 'random':
            self._update_random_position()

        # NavSatFix 메시지 생성
        msg = NavSatFix()

        # Header 설정
        msg.header = Header()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'gps_antenna'

        # GPS 상태 설정
        msg.status = NavSatStatus()
        msg.status.status = NavSatStatus.STATUS_GBAS_FIX  # 3 (최고 정확도)
        msg.status.service = NavSatStatus.SERVICE_GPS  # 1 (GPS 사용)

        # 위치 데이터
        msg.latitude = self.lat
        msg.longitude = self.lon
        msg.altitude = self.alt

        # 위치 공분산 (ENU 좌표계)
        # 대각선 공분산: 1m² 정확도 (GBAS 기준)
        msg.position_covariance = [
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0
        ]
        msg.position_covariance_type = NavSatFix.COVARIANCE_TYPE_DIAGONAL_KNOWN

        # 발행
        self.publisher.publish(msg)

        # 로그 (10초마다)
        if int(self.time_elapsed) % 10 == 0:
            self.get_logger().info(
                f'GPS: ({msg.latitude:.8f}, {msg.longitude:.8f}, {msg.altitude:.2f}m) '
                f'[{self.scenario}]'
            )

        self.time_elapsed += 1.0 / self.update_rate

    def _update_patrol_position(self):
        """
        순찰 시나리오 - 원형 경로 이동

        중심점을 기준으로 반지름 500m 원형 경로를 순찰합니다.
        """
        # 원형 경로 계산 (반지름: 0.005도 ≈ 500m)
        radius = 0.005
        angular_speed = 0.01  # rad/s (부드러운 회전)

        # 현재 각도 계산
        angle = self.time_elapsed * angular_speed

        # 초기 위치를 중심으로 원형 경로
        initial_lat = self.get_parameter('initial_lat').value
        initial_lon = self.get_parameter('initial_lon').value

        self.lat = initial_lat + radius * math.cos(angle)
        self.lon = initial_lon + radius * math.sin(angle)

        # Heading 랜덤 회전 (부드러운 회전, 약간의 노이즈 포함)
        heading_change = random.uniform(0.005, 0.015)  # 0.01 ± 0.005 rad/s
        self.heading += heading_change * (1.0 / self.update_rate)
        self.heading = self.heading % (2 * math.pi)  # 0~2π 범위 유지

        # 고도는 약간의 노이즈 추가 (파도 효과)
        self.alt = random.uniform(-0.5, 0.5)

    def _update_stationary_position(self):
        """
        정박 시나리오 - 제자리 (노이즈만 추가)

        GPS 노이즈 시뮬레이션 (약 ±0.1m - 최소 움직임)

        Note: 정박 기준점(stationary_base_lat/lon)을 기준으로 노이즈만 추가
              - 시작 시 stationary: 초기 위치 기준
              - 홈 복귀 후 stationary: 도착 위치 기준
              노이즈가 누적되지 않고 매번 기준점으로 리셋됨
        """
        # 정박 기준점 기준으로 GPS 노이즈만 추가 (drift 방지)
        # GPS 노이즈 (±0.000001도 ≈ ±0.1m, 10cm - 최소 움직임)
        self.lat = self.stationary_base_lat + random.uniform(-0.000001, 0.000001)
        self.lon = self.stationary_base_lon + random.uniform(-0.000001, 0.000001)
        self.alt = random.uniform(-0.02, 0.02)

        # Heading 랜덤 회전 (빠른 회전, 물결/조류 효과)
        heading_change = random.uniform(0.02, 0.05)  # 0.035 ± 0.015 rad/s (빠른 회전)
        self.heading += heading_change * (1.0 / self.update_rate)
        self.heading = self.heading % (2 * math.pi)  # 0~2π 범위 유지

    def _update_idle_position(self):
        """
        일시정지 시나리오 - 현재 위치 유지 (GPS 노이즈만 추가)

        자율주행 일시정지 시 사용. 웨이포인트와 인덱스는 유지하고 위치만 고정.
        약간의 GPS 노이즈만 추가하여 실제 KOBOT의 정지 상태를 시뮬레이션.
        """
        # 현재 위치 유지, GPS 노이즈만 추가 (±0.00001도 ≈ ±1m)
        noise_lat = random.uniform(-0.00001, 0.00001)
        noise_lon = random.uniform(-0.00001, 0.00001)
        self.lat += noise_lat
        self.lon += noise_lon
        self.alt += random.uniform(-0.05, 0.05)

        # Heading 랜덤 회전 (부드러운 회전, 약간의 노이즈 포함)
        heading_change = random.uniform(0.005, 0.015)  # 0.01 ± 0.005 rad/s
        self.heading += heading_change * (1.0 / self.update_rate)
        self.heading = self.heading % (2 * math.pi)  # 0~2π 범위 유지

    def _update_random_position(self):
        """
        랜덤 시나리오 - 무작위 이동

        느린 속도로 무작위 방향 이동
        """
        # Heading 랜덤 회전 (부드러운 회전, 약간의 노이즈 포함)
        heading_change = random.uniform(0.005, 0.015)  # 0.01 ± 0.005 rad/s
        self.heading += heading_change * (1.0 / self.update_rate)
        self.heading = self.heading % (2 * math.pi)  # 0~2π 범위 유지

        # 현재 방향으로 이동
        self.lat += self.speed * math.cos(self.heading)
        self.lon += self.speed * math.sin(self.heading)
        self.alt = random.uniform(-0.5, 0.5)

    def autodrive_cmd_callback(self, msg: String):
        """
        자율주행 명령 콜백

        MQTT Bridge로부터 받은 웨이포인트로 자율주행 시나리오를 시작합니다.
        """
        try:
            command = json.loads(msg.data)
            cmd = command.get('cmd')
            self.get_logger().info(f'자율주행 명령 수신: {cmd}')

            if cmd == 'start':
                waypoints = command.get('waypoints', [])
                if not waypoints:
                    self.get_logger().warn('자율주행 시작 명령에 웨이포인트가 없습니다.')
                    return

                # 재개 vs 신규 시작 구분
                if self.scenario == 'idle' and self.target_waypoints:
                    # 재개: 기존 웨이포인트를 새로운 웨이포인트로 교체하고 인덱스는 0으로 (남은 웨이포인트만 받음)
                    self.target_waypoints = waypoints
                    self.current_waypoint_index = 0
                    self.scenario = 'autodrive'
                    self.get_logger().info(f'자율주행 재개. {len(self.target_waypoints)}개의 남은 웨이포인트를 수신했습니다.')
                else:
                    # 신규 시작: 웨이포인트와 인덱스 모두 초기화
                    self.target_waypoints = waypoints
                    self.current_waypoint_index = 0
                    self.scenario = 'autodrive'
                    self.get_logger().info(f'자율주행 시나리오 시작. {len(self.target_waypoints)}개의 웨이포인트를 수신했습니다.')

            elif cmd == 'stop':
                # 일시정지 시: 웨이포인트와 인덱스 유지, 제자리에서 정지
                # (patrol 모드로 돌아가지 않음 → 시작 위치로 복귀하지 않음)
                self.scenario = 'idle'  # 정지 상태 (새로운 시나리오)
                self.get_logger().info(f'자율주행 일시정지. 현재 위치 유지. (웨이포인트 {self.current_waypoint_index + 1}/{len(self.target_waypoints)} 진행 중)')

        except json.JSONDecodeError:
            self.get_logger().error('자율주행 명령 파싱 실패: 유효하지 않은 JSON 형식입니다.')
        except Exception as e:
            self.get_logger().error(f'자율주행 명령 처리 중 오류 발생: {e}')

    def _update_autodrive_position(self):
        """
        자율주행 시나리오 - 웨이포인트 따라 이동
        """
        if not self.target_waypoints or self.current_waypoint_index >= len(self.target_waypoints):
            # 목표가 없거나 모든 웨이포인트에 도달하면 그 자리에 정박 (홈 복귀 완료)
            self.get_logger().info('모든 웨이포인트에 도달했습니다. 정박 시나리오로 전환합니다.')
            self.scenario = 'stationary'
            self.target_waypoints = []
            return

        # 다음 목표 웨이포인트
        target_wp = self.target_waypoints[self.current_waypoint_index]
        target_lat = target_wp['latitude']
        target_lon = target_wp['longitude']

        # 목표까지의 벡터 계산
        delta_lat = target_lat - self.lat
        delta_lon = target_lon - self.lon
        distance = math.sqrt(delta_lat**2 + delta_lon**2)

        # 도착 반경 (0.000009도 ~= 1m, 정밀한 도착)
        # 속도(1.0m/s)와 동일하게 설정하여 정확한 도착
        arrival_radius = 0.000009

        if distance < arrival_radius:
            # 웨이포인트에 도달
            self.get_logger().info(f'웨이포인트 {self.current_waypoint_index + 1}에 도달했습니다.')
            self.current_waypoint_index += 1

            # 마지막 웨이포인트가 아니면 다음으로 즉시 이동
            if self.current_waypoint_index < len(self.target_waypoints):
                self._update_autodrive_position()
            # 마지막 웨이포인트면 그 자리에 머물러서 백엔드가 GPS 데이터를 받을 수 있게 함
            # (다음 timer_callback에서 stationary 모드로 전환됨)
            return

        # Heading을 목표 방향으로 업데이트 (시각적으로 자연스럽게)
        target_heading = math.atan2(delta_lon, delta_lat)
        self.heading = target_heading

        # 웨이포인트 근처에서 감속 (부드러운 도착)
        # 10m 이내: 속도 50% 감소, 5m 이내: 속도 70% 감소
        slow_down_distance = 0.00009  # 약 10m
        if distance < slow_down_distance:
            speed_factor = max(0.3, distance / slow_down_distance)  # 최소 30% 속도 유지
            effective_speed = self.speed * speed_factor
        else:
            effective_speed = self.speed

        # 목표 방향으로 이동 (단, 목표를 지나치지 않도록 이동 거리 제한)
        move_distance = min(effective_speed, distance)  # 목표까지 거리가 speed보다 작으면 거리만큼만 이동
        self.lat += (delta_lat / distance) * move_distance
        self.lon += (delta_lon / distance) * move_distance
        self.alt = random.uniform(-0.5, 0.5)



def main(args=None):
    """
    GPS Publisher 노드 메인 함수
    """
    rclpy.init(args=args)

    gps_publisher = GPSPublisher()

    try:
        rclpy.spin(gps_publisher)
    except KeyboardInterrupt:
        pass
    finally:
        gps_publisher.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
