#!/usr/bin/env python3
"""
System Status Publisher 노드

실제 KOBOT의 시스템 상태를 시뮬레이션합니다.
std_msgs/String (JSON) 메시지를 발행합니다.

ROS2 토픽 사양:
    - docs/ros2_topic/ros2-system-status-topic-spec.md 참조
    - 메시지 타입: std_msgs/String (JSON 형식)

발행 데이터 (JSON):
    - battery_voltage: 배터리 전압 [V]
    - battery_percentage: 배터리 잔량 [%]
    - cpu_usage: CPU 사용률 [%]
    - memory_usage: 메모리 사용률 [%]
    - temperature: 시스템 온도 [°C]
    - disk_usage: 디스크 사용률 [%]
    - network_status: 네트워크 상태 (connected/disconnected)
    - gps_fix: GPS 상태 (true/false)
"""

import json
import os
import random
import time
from datetime import datetime, timezone

import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class SystemStatusPublisher(Node):
    """
    시스템 상태 데이터를 발행하는 ROS2 노드

    시나리오에 따라 KOBOT의 시스템 상태를 시뮬레이션합니다.

    Parameters (ROS2):
        namespace (str): KOBOT namespace (예: kobot1, kobot2, kobot3)
        update_rate (float): 발행 주기 [Hz] (default: 0.2)
        scenario (str): 시나리오 (patrol, stationary, random)
    """

    def __init__(self):
        super().__init__('system_status_publisher')

        # 파라미터 선언
        self.declare_parameter('namespace', 'kobot_simulator')
        self.declare_parameter('scenario', 'patrol')

        # 파라미터 가져오기
        self.namespace = self.get_parameter('namespace').value
        self.scenario = self.get_parameter('scenario').value

        # 발행 주기: 환경 변수 우선, 없으면 기본값 0.2Hz (5초)
        update_rate = float(os.getenv('STATUS_RATE', '0.2'))

        # 시뮬레이션 상태 (배터리만)
        self.start_time = time.time()
        self.battery_voltage = 24.0  # 24V 시스템 (계산용, MQTT 전송 안 함)
        # 초기 배터리: 환경 변수로 설정 가능 (테스트용)
        self.battery_percentage = float(os.getenv('INITIAL_BATTERY', '100.0'))

        # Publisher 생성
        self.publisher = self.create_publisher(
            String,
            f'{self.namespace}/system/status',
            10
        )

        # 타이머 생성
        timer_period = 1.0 / update_rate
        self.timer = self.create_timer(timer_period, self.timer_callback)

        self.get_logger().info(f'System Status Publisher 시작 - {self.namespace}')
        self.get_logger().info(f'  시나리오: {self.scenario}')
        self.get_logger().info(f'  발행 주기: {update_rate} Hz')

    def timer_callback(self):
        """시스템 상태 데이터 발행"""
        elapsed_time = time.time() - self.start_time

        # 시나리오에 따라 상태 업데이트
        if self.scenario == 'patrol':
            self._update_patrol_status(elapsed_time)
        elif self.scenario == 'stationary':
            self._update_stationary_status(elapsed_time)
        elif self.scenario == 'random':
            self._update_random_status(elapsed_time)

        # JSON 데이터 생성 (배터리만, 다른 센서와 동일한 구조)
        now = self.get_clock().now().to_msg()
        status_data = {
            'ts_iso': datetime.now(timezone.utc).isoformat(),
            'header': {
                'stamp': {
                    'sec': now.sec,
                    'nanosec': now.nanosec
                },
                'frame_id': 'status'
            },
            'battery_percentage': round(self.battery_percentage, 1)
        }

        # String 메시지 생성
        msg = String()
        msg.data = json.dumps(status_data)

        self.publisher.publish(msg)

        # 로그 출력 (매 발행마다)
        self.get_logger().info(
            f'System: Battery={self.battery_percentage:.1f}% [{self.scenario}]'
        )

    def _update_patrol_status(self, elapsed_time: float):
        """순찰 시나리오 - 높은 활동량"""
        # 배터리 방전 (환경 변수로 조정 가능, 기본: 시간당 60% 방전)
        # DISCHARGE_RATE_PER_HOUR: 시간당 방전 퍼센트 (예: 600 = 6초당 1%)
        discharge_per_hour = float(os.getenv('DISCHARGE_RATE_PER_HOUR', '60.0'))
        discharge_rate = discharge_per_hour / 3600.0  # %/s
        initial_battery = float(os.getenv('INITIAL_BATTERY', '100.0'))
        self.battery_percentage = max(0, initial_battery - elapsed_time * discharge_rate)
        self.battery_voltage = 24.0 * (self.battery_percentage / 100.0) + 20.0  # 20V ~ 24V (계산용)

    def _update_stationary_status(self, elapsed_time: float):
        """정박 시나리오 - 낮은 활동량 (충전)"""
        # 배터리 충전 (시간당 5% 충전, 95% 이하일 때)
        if self.battery_percentage < 95.0:
            charge_rate = 5.0 / 3600.0  # 충전 중
            self.battery_percentage = min(100.0, self.battery_percentage + charge_rate)
        else:
            discharge_rate = 2.0 / 3600.0
            self.battery_percentage = max(0, 100.0 - elapsed_time * discharge_rate)

        self.battery_voltage = 24.0 * (self.battery_percentage / 100.0) + 20.0  # 계산용

    def _update_random_status(self, elapsed_time: float):
        """랜덤 시나리오 - 무작위 배터리 변화"""
        # 배터리 (방전만, 약간의 랜덤 노이즈)
        self.battery_percentage += random.uniform(-0.5, -0.1)  # 방전만 (0.1~0.5% 감소)
        self.battery_percentage = max(0, min(100, self.battery_percentage))
        self.battery_voltage = 24.0 * (self.battery_percentage / 100.0) + 20.0  # 계산용
        self.disk_usage = max(20.0, min(95.0, self.disk_usage))

        # 네트워크 상태
        if random.random() < 0.1:
            self.network_status = 'disconnected'
        else:
            self.network_status = 'connected'

        # GPS Fix
        self.gps_fix = random.random() > 0.1


def main(args=None):
    rclpy.init(args=args)
    system_status_publisher = SystemStatusPublisher()

    try:
        rclpy.spin(system_status_publisher)
    except KeyboardInterrupt:
        pass
    finally:
        system_status_publisher.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
