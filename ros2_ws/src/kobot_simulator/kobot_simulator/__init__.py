"""
KOBOT 시뮬레이터 - ROS2 센서 노드 패키지

실제 KOBOT의 ROS2 토픽 구조를 재현하여 관제 시스템을 테스트합니다.

패키지 구성:
    - gps_publisher: GPS 센서 데이터 발행
    - imu_publisher: IMU 센서 데이터 발행
    - lidar_publisher: LiDAR 센서 데이터 발행
    - system_status_publisher: 시스템 상태 발행
    - scenario_manager: 시뮬레이션 시나리오 관리
"""

__version__ = '0.1.0'
