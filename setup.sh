#!/bin/bash
# KOBOT 시뮬레이터 초기 설정 스크립트
# 사용법: bash setup.sh

set -e

echo "=== KOBOT 시뮬레이터 초기 설정 ==="
echo ""

# .env.simulator.prod 파일 생성
ENV_FILE=".env.simulator.prod"

if [ -f "$ENV_FILE" ]; then
    echo "[!] $ENV_FILE 파일이 이미 존재합니다."
    read -p "    덮어쓰시겠습니까? (y/N): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "    설정을 건너뜁니다."
        echo ""
        echo "=== 시뮬레이터 시작 방법 ==="
        echo "  docker compose -f docker-compose.simulator-prod.yml up -d"
        exit 0
    fi
fi

# example 파일 복사
cp .env.simulator.example "$ENV_FILE"

echo ""
echo "[1/3] 관제 서버 주소 설정"
read -p "      관제 서버 IP 또는 도메인: " server_host

if [ -z "$server_host" ]; then
    echo "      서버 주소가 비어있습니다. 나중에 $ENV_FILE 파일을 직접 수정해주세요."
else
    # MQTT_BROKER, MEDIAMTX_HOST 설정
    sed -i.bak "s|MQTT_BROKER=host.docker.internal|MQTT_BROKER=$server_host|" "$ENV_FILE"
    sed -i.bak "s|MEDIAMTX_HOST=host.docker.internal|MEDIAMTX_HOST=$server_host|" "$ENV_FILE"
    echo "      MQTT_BROKER=$server_host"
    echo "      MEDIAMTX_HOST=$server_host"
fi

echo ""
echo "[2/3] MQTT 비밀번호 설정"
read -p "      KOBOT 비밀번호 (전달받은 값 입력): " mqtt_password

if [ -z "$mqtt_password" ]; then
    echo "      비밀번호가 비어있습니다. 나중에 $ENV_FILE 파일을 직접 수정해주세요."
else
    sed -i.bak "s|PASSWORD=your_password_here|PASSWORD=$mqtt_password|" "$ENV_FILE"
    echo "      5대 KOBOT 비밀번호 설정 완료"
fi

echo ""
echo "[3/3] MQTT 포트 설정"
read -p "      MQTT 포트 (기본 1883, Enter로 건너뛰기): " mqtt_port

if [ -n "$mqtt_port" ]; then
    sed -i.bak "s|MQTT_PORT=1883|MQTT_PORT=$mqtt_port|" "$ENV_FILE"
    echo "      MQTT_PORT=$mqtt_port"
else
    echo "      기본값 사용: 1883"
fi

# 백업 파일 제거
rm -f "$ENV_FILE.bak"

echo ""
echo "=== 설정 완료 ==="
echo ""

read -p "시뮬레이터를 바로 시작할까요? (Y/n): " start_now

if [ "$start_now" != "n" ] && [ "$start_now" != "N" ]; then
    echo ""
    echo "시뮬레이터 시작 중..."
    docker compose -f docker-compose.simulator-prod.yml up -d
    echo ""
    echo "로그 확인:"
    echo "  docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-011"
    echo ""
    echo "전체 중지:"
    echo "  docker compose -f docker-compose.simulator-prod.yml down"
else
    echo ""
    echo "시뮬레이터 시작:"
    echo "  docker compose -f docker-compose.simulator-prod.yml up -d"
    echo ""
    echo "로그 확인:"
    echo "  docker compose -f docker-compose.simulator-prod.yml logs -f kobot-sim-prod-011"
    echo ""
    echo "전체 중지:"
    echo "  docker compose -f docker-compose.simulator-prod.yml down"
fi

echo ""
echo "설정 수정이 필요하면 $ENV_FILE 파일을 직접 편집해주세요."
