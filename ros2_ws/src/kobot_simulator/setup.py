from setuptools import setup
import os
from glob import glob

package_name = 'kobot_simulator'

setup(
    name=package_name,
    version='0.1.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        # Launch 파일
        (os.path.join('share', package_name, 'launch'),
            glob('launch/*.launch.py')),
        # Config 파일
        (os.path.join('share', package_name, 'config'),
            glob('config/*.yaml')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='KOBOT Team',
    maintainer_email='dev@example.com',
    description='KOBOT 시뮬레이터 - ROS2 센서 노드 패키지',
    license='MIT',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'gps_publisher = kobot_simulator.gps_publisher:main',
            'imu_publisher = kobot_simulator.imu_publisher:main',
            'lidar_publisher = kobot_simulator.lidar_publisher:main',
            'system_status_publisher = kobot_simulator.system_status_publisher:main',
            'mqtt_bridge = kobot_simulator.mqtt_bridge:main',
            'scenario_manager = kobot_simulator.scenario_manager:main',
        ],
    },
)
