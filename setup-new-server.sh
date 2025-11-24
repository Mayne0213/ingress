#!/bin/bash

###############################################################################
# 새 EC2 서버 초기 설정 스크립트
# 용도: K3s, ArgoCD, Nginx 등 필요한 모든 것을 자동으로 설치
# 실행 방법: sudo bash setup-new-server.sh
###############################################################################

set -e  # 에러 발생 시 즉시 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한으로 실행해야 합니다. 'sudo bash setup-new-server.sh'를 사용하세요."
    exit 1
fi

# 시작 메시지
echo "========================================"
echo "  새 서버 초기 설정 스크립트"
echo "========================================"
echo ""

###############################################################################
# 1. 시스템 업데이트
###############################################################################
log_info "1/8 시스템 패키지 업데이트 중..."
apt-get update -y
apt-get upgrade -y

###############################################################################
# 2. K3s 설치
###############################################################################
log_info "2/8 K3s 설치 중..."
if command -v k3s &> /dev/null; then
    log_warn "K3s가 이미 설치되어 있습니다. 건너뜁니다."
else
    curl -sfL https://get.k3s.io | sh -

    # K3s 시작 대기
    log_info "K3s 시작 대기 중..."
    sleep 10

    # kubeconfig 권한 설정
    chmod 644 /etc/rancher/k3s/k3s.yaml

    # 일반 사용자도 kubectl 사용 가능하도록
    if [ -n "$SUDO_USER" ]; then
        mkdir -p /home/$SUDO_USER/.kube
        cp /etc/rancher/k3s/k3s.yaml /home/$SUDO_USER/.kube/config
        chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube
        log_info "kubectl 설정이 /home/$SUDO_USER/.kube/config에 복사되었습니다."
    fi

    log_info "K3s 설치 완료!"
fi

# KUBECONFIG 환경변수 설정
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# K3s 정상 동작 확인
log_info "K3s 상태 확인 중..."
kubectl get nodes

###############################################################################
# 3. ArgoCD 설치
###############################################################################
log_info "3/8 ArgoCD 설치 중..."
if kubectl get namespace argocd &> /dev/null; then
    log_warn "ArgoCD 네임스페이스가 이미 존재합니다. 건너뜁니다."
else
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    log_info "ArgoCD 파드 시작 대기 중... (1-2분 소요)"
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s || log_warn "일부 파드가 준비되지 않았습니다. 계속 진행합니다."

    log_info "ArgoCD 설치 완료!"
fi

###############################################################################
# 4. ArgoCD Image Updater 설치
###############################################################################
log_info "4/8 ArgoCD Image Updater 설치 중..."
if kubectl get deployment argocd-image-updater -n argocd &> /dev/null; then
    log_warn "ArgoCD Image Updater가 이미 설치되어 있습니다. 건너뜁니다."
else
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
    log_info "ArgoCD Image Updater 설치 완료!"
fi

###############################################################################
# 5. Ingress Nginx Controller 설치
###############################################################################
log_info "5/8 Ingress Nginx Controller 설치 중..."
if kubectl get namespace ingress-nginx &> /dev/null; then
    log_warn "Ingress Nginx가 이미 설치되어 있습니다. 건너뜁니다."
else
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

    log_info "Ingress Controller 파드 시작 대기 중..."
    sleep 15
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=300s || log_warn "Ingress Controller 준비 대기 시간 초과"

    log_info "Ingress Nginx Controller 설치 완료!"
fi

# NodePort 확인
log_info "Ingress Controller NodePort 확인 중..."
HTTP_NODEPORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
log_info "HTTP NodePort: $HTTP_NODEPORT"

###############################################################################
# 6. Nginx 설치 및 설정
###############################################################################
log_info "6/8 Nginx 설치 중..."
if command -v nginx &> /dev/null; then
    log_warn "Nginx가 이미 설치되어 있습니다."
else
    apt-get install -y nginx
fi

# Nginx 설정 파일 생성
log_info "Nginx 리버스 프록시 설정 중..."
cat > /etc/nginx/sites-available/k8s-proxy <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    access_log /var/log/nginx/k8s-proxy-access.log;
    error_log /var/log/nginx/k8s-proxy-error.log;

    location / {
        proxy_pass http://127.0.0.1:$HTTP_NODEPORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 타임아웃 설정
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# 심볼릭 링크 생성
if [ -L /etc/nginx/sites-enabled/k8s-proxy ]; then
    log_warn "Nginx k8s-proxy 설정이 이미 활성화되어 있습니다."
else
    ln -s /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
fi

# 기본 설정 제거
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
    log_info "기본 Nginx 설정 제거됨"
fi

# Nginx 설정 테스트
log_info "Nginx 설정 테스트 중..."
nginx -t

# Nginx 재시작 및 자동 시작 활성화
systemctl restart nginx
systemctl enable nginx

log_info "Nginx 설치 및 설정 완료!"

###############################################################################
# 7. Infrastructure App of Apps 배포
###############################################################################
log_info "7/8 Infrastructure App of Apps 배포 중..."

# application.yaml 다운로드 및 적용
log_info "infrastructure repository에서 application.yaml 다운로드 중..."
curl -sfL https://raw.githubusercontent.com/Mayne0213/infrastructure/main/application.yaml -o /tmp/application.yaml

if [ $? -eq 0 ]; then
    kubectl apply -f /tmp/application.yaml
    log_info "Infrastructure Application 배포 완료!"
    log_info "ArgoCD가 자동으로 모든 애플리케이션을 배포합니다. (3-5분 소요)"
else
    log_error "application.yaml 다운로드 실패. 수동으로 배포해야 합니다:"
    log_error "  kubectl apply -f https://raw.githubusercontent.com/Mayne0213/infrastructure/main/application.yaml"
fi

###############################################################################
# 8. 상태 확인
###############################################################################
log_info "8/8 최종 상태 확인 중..."

echo ""
echo "========================================"
echo "  설치 완료!"
echo "========================================"
echo ""

# ArgoCD 초기 비밀번호 가져오기
log_info "ArgoCD 초기 admin 비밀번호:"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
if [ -n "$ARGOCD_PASSWORD" ]; then
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASSWORD"
    echo ""
    log_warn "위 비밀번호를 안전한 곳에 저장하세요!"
else
    log_warn "ArgoCD 비밀번호를 가져올 수 없습니다. ArgoCD가 완전히 시작된 후 다음 명령어로 확인하세요:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
fi

echo ""
log_info "설치된 구성 요소:"
echo "  ✅ K3s (Kubernetes)"
echo "  ✅ ArgoCD"
echo "  ✅ ArgoCD Image Updater"
echo "  ✅ Ingress Nginx Controller (NodePort: $HTTP_NODEPORT)"
echo "  ✅ Nginx 리버스 프록시 (Port 80 → $HTTP_NODEPORT)"
echo "  ✅ Infrastructure App of Apps"
echo ""

log_info "다음 단계:"
echo "  1. DNS 설정을 이 서버의 IP로 변경하세요:"
echo "     - mayne.kro.kr"
echo "     - jovies.kro.kr"
echo "     - argocd.kro.kr"
echo ""
echo "  2. ArgoCD 애플리케이션 상태 확인:"
echo "     kubectl get applications -n argocd"
echo ""
echo "  3. ArgoCD UI 접속 (DNS 설정 후):"
echo "     http://argocd.kro.kr"
echo ""
echo "  4. 배포 상태 모니터링:"
echo "     kubectl get pods -A"
echo ""

log_info "참고: ArgoCD가 모든 애플리케이션을 자동으로 배포하는데 5-10분 정도 걸립니다."
log_info "다음 명령어로 실시간 상태를 확인할 수 있습니다:"
echo "  watch -n 5 'kubectl get pods -A'"

echo ""
echo "========================================"
log_info "설정 완료! 🎉"
echo "========================================"
