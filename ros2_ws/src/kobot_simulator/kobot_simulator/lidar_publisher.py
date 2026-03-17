#!/usr/bin/env python3
"""
LiDAR Publisher 노드

실제 KOBOT의 2D LiDAR 센서를 시뮬레이션합니다.
sensor_msgs/LaserScan 메시지를 발행합니다.

ROS2 토픽 사양:
    - docs/ros2_topic/ros2-lidar-topic-spec.md 참조
    - 메시지 타입: sensor_msgs/LaserScan
    - 좌표계: lidar_link (전방 0°)

발행 데이터:
    - ranges: 거리 측정값 배열 [m]
    - intensities: 반사 강도 배열
    - angle_min/max: 스캔 각도 범위 [rad]
    - angle_increment: 각도 증분 [rad]
    - scan_time: 스캔 주기 [s]
    - range_min/max: 유효 거리 범위 [m]
"""

import math
import os
import random

import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import LaserScan
from std_msgs.msg import Header


class LiDARPublisher(Node):
    """
    2D LiDAR 센서 데이터를 발행하는 ROS2 노드

    시나리오에 따라 KOBOT 주변 장애물을 시뮬레이션합니다.

    Parameters (ROS2):
        namespace (str): KOBOT namespace (예: kobot1, kobot2, kobot3)
        update_rate (float): 발행 주기 [Hz] (default: 0.33)
        scenario (str): 시나리오 (patrol, stationary, random)
        num_readings (int): 스캔 포인트 수 (default: 360)
        angle_min (float): 최소 각도 [deg] (default: 0)
        angle_max (float): 최대 각도 [deg] (default: 360)
        range_min (float): 최소 유효 거리 [m] (default: 0.1)
        range_max (float): 최대 유효 거리 [m] (default: 30.0)
    """

    def __init__(self):
        super().__init__('lidar_publisher')

        # 파라미터 선언
        self.declare_parameter('namespace', 'kobot_simulator')
        self.declare_parameter('scenario', 'patrol')
        self.declare_parameter('num_readings', 360)
        self.declare_parameter('angle_min', 0.0)      # degrees
        self.declare_parameter('angle_max', 360.0)    # degrees
        self.declare_parameter('range_min', 0.1)      # meters
        self.declare_parameter('range_max', 30.0)     # meters

        # 파라미터 가져오기
        self.namespace = self.get_parameter('namespace').value
        self.scenario = self.get_parameter('scenario').value

        # 발행 주기: 환경 변수 우선, 없으면 기본값 0.33Hz (3초)
        self.update_rate = float(os.getenv('LIDAR_RATE', '0.33'))
        self.num_readings = self.get_parameter('num_readings').value
        angle_min_deg = self.get_parameter('angle_min').value
        angle_max_deg = self.get_parameter('angle_max').value
        self.range_min = self.get_parameter('range_min').value
        self.range_max = self.get_parameter('range_max').value

        # 각도를 라디안으로 변환
        self.angle_min = math.radians(angle_min_deg)
        self.angle_max = math.radians(angle_max_deg)
        self.angle_increment = (self.angle_max - self.angle_min) / self.num_readings

        # 시뮬레이션 상태
        self.time_elapsed = 0.0
        self.obstacle_positions = []  # [(angle, distance), ...]
        self._initialize_obstacles()

        # Publisher 생성
        self.publisher = self.create_publisher(
            LaserScan,
            f'{self.namespace}/sensors/lidar',
            10
        )

        # 타이머 생성
        timer_period = 1.0 / self.update_rate
        self.timer = self.create_timer(timer_period, self.timer_callback)

        self.get_logger().info(f'LiDAR Publisher 시작 - {self.namespace}')
        self.get_logger().info(f'  시나리오: {self.scenario}')
        self.get_logger().info(f'  발행 주기: {self.update_rate} Hz')
        self.get_logger().info(f'  스캔 범위: {angle_min_deg}° ~ {angle_max_deg}°')
        self.get_logger().info(f'  거리 범위: {self.range_min}m ~ {self.range_max}m')

    def _initialize_obstacles(self):
        """시나리오에 따라 장애물 초기화"""
        if self.scenario == 'patrol':
            # 순찰 시나리오: 원형 경계 + 몇 개의 장애물
            self.obstacle_positions = [
                (math.radians(0), 15.0),    # 전방 장애물
                (math.radians(45), 10.0),   # 우측전방 장애물
                (math.radians(315), 10.0),  # 좌측전방 장애물
            ]
        elif self.scenario == 'stationary':
            # 정박 시나리오: 부두 벽면 + 주변 선박
            self.obstacle_positions = [
                (math.radians(90), 5.0),    # 좌측 부두
                (math.radians(270), 5.0),   # 우측 부두
                (math.radians(180), 8.0),   # 후방 선박
            ]
        elif self.scenario == 'random':
            # 랜덤 시나리오: 무작위 장애물
            num_obstacles = random.randint(3, 7)
            self.obstacle_positions = [
                (random.uniform(0, 2*math.pi), random.uniform(3.0, 20.0))
                for _ in range(num_obstacles)
            ]

    def timer_callback(self):
        """LiDAR 스캔 데이터 발행"""
        if self.scenario == 'patrol':
            self._update_patrol_obstacles()
        elif self.scenario == 'random':
            if random.random() < 0.05:  # 5% 확률로 장애물 업데이트
                self._initialize_obstacles()

        # LaserScan 메시지 생성
        msg = LaserScan()
        msg.header = Header()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'lidar_link'

        msg.angle_min = self.angle_min
        msg.angle_max = self.angle_max
        msg.angle_increment = self.angle_increment
        msg.time_increment = 0.0  # 동시 스캔 가정
        msg.scan_time = 1.0 / self.update_rate
        msg.range_min = self.range_min
        msg.range_max = self.range_max

        # ranges 배열 생성
        ranges = np.full(self.num_readings, self.range_max)  # 기본값: 최대 거리
        intensities = np.zeros(self.num_readings)

        # 각 각도에 대해 스캔 시뮬레이션
        for i in range(self.num_readings):
            angle = self.angle_min + i * self.angle_increment
            distance = self._simulate_range(angle)
            ranges[i] = distance

            # 거리에 따른 강도 계산 (가까울수록 강함)
            if distance < self.range_max:
                intensities[i] = max(0, 1.0 - (distance / self.range_max))

        msg.ranges = ranges.tolist()
        msg.intensities = intensities.tolist()

        self.publisher.publish(msg)

        # 5초마다 로그 출력
        if int(self.time_elapsed * 10) % 50 == 0:
            min_range = np.min(ranges)
            avg_range = np.mean(ranges[ranges < self.range_max])
            self.get_logger().info(
                f'LiDAR: Min={min_range:.2f}m, Avg={avg_range:.2f}m [{self.scenario}]'
            )

        self.time_elapsed += 1.0 / self.update_rate

    def _simulate_range(self, angle: float) -> float:
        """
        주어진 각도에서의 거리 측정 시뮬레이션

        Args:
            angle: 스캔 각도 [rad]

        Returns:
            측정 거리 [m]
        """
        min_distance = self.range_max

        # 장애물 체크
        for obs_angle, obs_distance in self.obstacle_positions:
            # 각도 차이 계산 (±10도 범위 내에서 장애물 감지)
            angle_diff = abs(self._normalize_angle(angle - obs_angle))
            if angle_diff < math.radians(10):
                # 가우시안 분포로 장애물 크기 모델링
                distance = obs_distance + random.gauss(0, 0.3)  # ±30cm 노이즈
                distance = max(self.range_min, min(self.range_max, distance))
                min_distance = min(min_distance, distance)

        # 노이즈 추가 (센서 특성)
        if min_distance < self.range_max:
            min_distance += random.gauss(0, 0.05)  # ±5cm 측정 노이즈

        # 가끔 무효 측정 (inf)
        if random.random() < 0.01:  # 1% 확률로 무효 측정
            return float('inf')

        return max(self.range_min, min(self.range_max, min_distance))

    def _normalize_angle(self, angle: float) -> float:
        """각도를 -π ~ π 범위로 정규화"""
        while angle > math.pi:
            angle -= 2 * math.pi
        while angle < -math.pi:
            angle += 2 * math.pi
        return angle

    def _update_patrol_obstacles(self):
        """순찰 시나리오 - 장애물이 움직임"""
        # 장애물이 천천히 회전하는 효과
        angular_speed = 0.01  # rad/s
        dt = 1.0 / self.update_rate

        updated_obstacles = []
        for obs_angle, obs_distance in self.obstacle_positions:
            # 각도 약간 변경
            new_angle = self._normalize_angle(obs_angle + angular_speed * dt * random.choice([-1, 1]))
            # 거리 약간 변경
            new_distance = obs_distance + random.uniform(-0.1, 0.1)
            new_distance = max(3.0, min(20.0, new_distance))
            updated_obstacles.append((new_angle, new_distance))

        self.obstacle_positions = updated_obstacles


def main(args=None):
    rclpy.init(args=args)
    lidar_publisher = LiDARPublisher()

    try:
        rclpy.spin(lidar_publisher)
    except KeyboardInterrupt:
        pass
    finally:
        lidar_publisher.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
