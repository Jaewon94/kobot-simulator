#!/usr/bin/env python3
"""
IMU Publisher 노드

실제 KOBOT의 IMU(관성측정장치) 센서를 시뮬레이션합니다.
sensor_msgs/Imu 메시지를 발행합니다.

ROS2 토픽 사양:
    - docs/ros2_topic/ros2-imu-topic-spec.md 참조
    - 메시지 타입: sensor_msgs/Imu
    - 좌표계: body frame (FLU - Forward Left Up)

발행 데이터:
    - orientation: 자세 (쿼터니언)
    - angular_velocity: 각속도 [rad/s]
    - linear_acceleration: 선형 가속도 [m/s²]
"""

import math
import os
import random

import rclpy
from rclpy.node import Node
from scipy.spatial.transform import Rotation
from sensor_msgs.msg import Imu
from std_msgs.msg import Header


class IMUPublisher(Node):
    """
    IMU 센서 데이터를 발행하는 ROS2 노드

    시나리오에 따라 KOBOT의 자세와 가속도를 시뮬레이션합니다.

    Parameters (ROS2):
        namespace (str): KOBOT namespace (예: kobot1, kobot2, kobot3)
        update_rate (float): 발행 주기 [Hz] (default: 0.2)
        scenario (str): 시나리오 (patrol, stationary, random)
    """

    def __init__(self):
        super().__init__('imu_publisher')

        # 파라미터 선언
        self.declare_parameter('namespace', 'kobot_simulator')
        self.declare_parameter('scenario', 'patrol')

        # 파라미터 가져오기
        self.namespace = self.get_parameter('namespace').value
        self.scenario = self.get_parameter('scenario').value

        # 발행 주기: 환경 변수 우선, 없으면 기본값 0.2Hz (5초)
        self.update_rate = float(os.getenv('IMU_RATE', '0.2'))

        # 시뮬레이션 상태
        self.time_elapsed = 0.0
        self.roll = 0.0   # 롤 (좌우 기울기) [rad]
        self.pitch = 0.0  # 피치 (전후 기울기) [rad]
        self.yaw = 0.0    # 요 (방향각) [rad]
        self.angular_vel = [0.0, 0.0, 0.0]  # [rad/s]
        self.linear_acc = [0.0, 0.0, 9.81]  # [m/s²] (중력 포함)

        # Publisher 생성
        self.publisher = self.create_publisher(
            Imu,
            f'{self.namespace}/sensors/imu',
            10
        )

        # 타이머 생성
        timer_period = 1.0 / self.update_rate
        self.timer = self.create_timer(timer_period, self.timer_callback)

        self.get_logger().info(f'IMU Publisher 시작 - {self.namespace}')
        self.get_logger().info(f'  시나리오: {self.scenario}')
        self.get_logger().info(f'  발행 주기: {self.update_rate} Hz')

    def timer_callback(self):
        """IMU 데이터 발행"""
        if self.scenario == 'patrol':
            self._update_patrol_motion()
        elif self.scenario == 'stationary':
            self._update_stationary_motion()
        elif self.scenario == 'random':
            self._update_random_motion()

        # Imu 메시지 생성
        msg = Imu()
        msg.header = Header()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'imu_link'

        # 자세 (쿼터니언)
        r = Rotation.from_euler('xyz', [self.roll, self.pitch, self.yaw])
        quat = r.as_quat()  # [x, y, z, w]
        msg.orientation.x = quat[0]
        msg.orientation.y = quat[1]
        msg.orientation.z = quat[2]
        msg.orientation.w = quat[3]
        msg.orientation_covariance = [0.01] * 9  # 대각 행렬

        # 각속도
        msg.angular_velocity.x = self.angular_vel[0]
        msg.angular_velocity.y = self.angular_vel[1]
        msg.angular_velocity.z = self.angular_vel[2]
        msg.angular_velocity_covariance = [0.001] * 9

        # 선형 가속도
        msg.linear_acceleration.x = self.linear_acc[0]
        msg.linear_acceleration.y = self.linear_acc[1]
        msg.linear_acceleration.z = self.linear_acc[2]
        msg.linear_acceleration_covariance = [0.01] * 9

        self.publisher.publish(msg)

        # 10초마다 로그 출력
        if int(self.time_elapsed * 50) % 500 == 0:
            self.get_logger().info(
                f'IMU: Roll={math.degrees(self.roll):.1f}° '
                f'Pitch={math.degrees(self.pitch):.1f}° '
                f'Yaw={math.degrees(self.yaw):.1f}° [{self.scenario}]'
            )

        self.time_elapsed += 1.0 / self.update_rate

    def _update_patrol_motion(self):
        """순찰 시나리오 - 회전 및 전진 운동"""
        # 요(yaw) 랜덤 회전 (부드러운 회전, 약간의 노이즈 포함)
        yaw_change = random.uniform(0.005, 0.015)  # 0.01 ± 0.005 rad/s
        self.yaw += yaw_change * (1.0 / self.update_rate)
        self.yaw = (self.yaw + math.pi) % (2 * math.pi) - math.pi  # -π ~ π 범위로 정규화

        # 파도에 의한 롤/피치 흔들림
        wave_freq = 0.5  # Hz
        self.roll = 0.1 * math.sin(2 * math.pi * wave_freq * self.time_elapsed)
        self.pitch = 0.05 * math.cos(2 * math.pi * wave_freq * self.time_elapsed)

        # 각속도
        self.angular_vel = [
            0.1 * math.cos(2 * math.pi * wave_freq * self.time_elapsed),  # roll rate
            0.05 * math.sin(2 * math.pi * wave_freq * self.time_elapsed),  # pitch rate
            yaw_change + random.uniform(-0.01, 0.01)  # yaw rate
        ]

        # 선형 가속도 (전진 + 중력 + 노이즈)
        self.linear_acc = [
            0.5 + random.uniform(-0.1, 0.1),  # x: 전진 가속도
            random.uniform(-0.2, 0.2),         # y: 측면 가속도
            9.81 + random.uniform(-0.1, 0.1)   # z: 중력 + 노이즈
        ]

    def _update_stationary_motion(self):
        """정박 시나리오 - 미세한 흔들림만"""
        # 정박 중 미세한 파도 흔들림
        wave_freq = 0.2  # Hz
        self.roll = 0.02 * math.sin(2 * math.pi * wave_freq * self.time_elapsed)
        self.pitch = 0.01 * math.cos(2 * math.pi * wave_freq * self.time_elapsed)

        # Yaw 랜덤 회전 (부드러운 회전, 약간의 노이즈 포함)
        yaw_change = random.uniform(0.005, 0.015)  # 0.01 ± 0.005 rad/s
        self.yaw += yaw_change * (1.0 / self.update_rate)
        self.yaw = (self.yaw + math.pi) % (2 * math.pi) - math.pi

        # 미세한 각속도
        self.angular_vel = [
            random.uniform(-0.01, 0.01),
            random.uniform(-0.01, 0.01),
            random.uniform(-0.001, 0.001)
        ]

        # 중력 + 미세 노이즈
        self.linear_acc = [
            random.uniform(-0.05, 0.05),
            random.uniform(-0.05, 0.05),
            9.81 + random.uniform(-0.05, 0.05)
        ]

    def _update_random_motion(self):
        """랜덤 시나리오 - 무작위 운동"""
        # 자세 변화 (부드러운 회전)
        self.roll += random.uniform(-0.01, 0.01) * (1.0 / self.update_rate)
        self.pitch += random.uniform(-0.01, 0.01) * (1.0 / self.update_rate)

        # Yaw 랜덤 회전 (부드러운 회전, 약간의 노이즈 포함)
        yaw_change = random.uniform(0.005, 0.015)  # 0.01 ± 0.005 rad/s
        self.yaw += yaw_change * (1.0 / self.update_rate)

        # 각도 범위 제한
        self.roll = max(-math.pi/4, min(math.pi/4, self.roll))
        self.pitch = max(-math.pi/4, min(math.pi/4, self.pitch))
        self.yaw = (self.yaw + math.pi) % (2 * math.pi) - math.pi

        # 랜덤 각속도
        self.angular_vel = [
            random.uniform(-0.5, 0.5),
            random.uniform(-0.5, 0.5),
            random.uniform(-0.5, 0.5)
        ]

        # 랜덤 선형 가속도
        self.linear_acc = [
            random.uniform(-1.0, 1.0),
            random.uniform(-1.0, 1.0),
            9.81 + random.uniform(-0.5, 0.5)
        ]


def main(args=None):
    rclpy.init(args=args)
    imu_publisher = IMUPublisher()

    try:
        rclpy.spin(imu_publisher)
    except KeyboardInterrupt:
        pass
    finally:
        imu_publisher.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
