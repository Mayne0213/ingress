# Infrastructure

ArgoCD App of Apps 패턴을 사용한 인프라 관리 repository입니다.

## 구조

```
infrastructure/
├── application.yaml           # App of Apps 루트 Application
├── argocd/
│   ├── repositories.yaml      # ArgoCD repository credentials
│   └── applications/
│       ├── jovies.yaml        # Jovies Application
│       └── portfolio.yaml     # Portfolio Application
└── ingress/
    └── ingress.yaml           # Ingress 설정 (jovies, portfolio, argocd)
```

## 사용 방법

### 🚀 새 서버 초기 설정 (자동화)

새로운 EC2/서버에 모든 것을 자동으로 설치하려면:

```bash
# 1. 이 repository를 clone
git clone https://github.com/Mayne0213/infrastructure.git
cd infrastructure

# 2. 설정 스크립트 실행 (root 권한 필요)
sudo bash setup-new-server.sh
```

이 스크립트는 다음을 자동으로 설치합니다:
- ✅ K3s (Kubernetes)
- ✅ ArgoCD
- ✅ ArgoCD Image Updater
- ✅ Ingress Nginx Controller
- ✅ Nginx 리버스 프록시
- ✅ Infrastructure App of Apps

스크립트 실행 후 DNS를 새 서버 IP로 변경하면 모든 애플리케이션이 자동으로 배포됩니다.

### 수동 초기 설정

루트 Application만 수동으로 생성하면, 나머지는 자동으로 생성됩니다:

```bash
kubectl apply -f application.yaml
```

### Application 추가

1. `argocd/applications/` 폴더에 새 Application YAML 추가
2. Git에 commit & push
3. ArgoCD가 자동으로 감지하여 생성

## App of Apps 패턴

이 repository는 ArgoCD의 App of Apps 패턴을 사용합니다:
- Infrastructure Application이 모든 하위 Application을 관리
- Git이 Single Source of Truth
- 선언적 구조로 인프라 관리

## 서버 이전 체크리스트

새 서버로 이전할 때 확인 사항:

### 설치 전
- [ ] 새 EC2 인스턴스 생성 (권장: t2.large 이상)
- [ ] SSH 키 설정 및 접속 확인
- [ ] 보안 그룹에서 포트 80, 443 오픈

### 설치
- [ ] `sudo bash setup-new-server.sh` 실행
- [ ] ArgoCD admin 비밀번호 저장
- [ ] 모든 구성 요소 설치 확인

### 설치 후
- [ ] DNS 레코드를 새 서버 IP로 변경
  - mayne.kro.kr
  - jovies.kro.kr
  - argocd.kro.kr
- [ ] ArgoCD UI 접속 확인 (http://argocd.kro.kr)
- [ ] 모든 애플리케이션 배포 상태 확인
  ```bash
  kubectl get applications -n argocd
  kubectl get pods -A
  ```
- [ ] 웹사이트 접근 테스트
  - http://mayne.kro.kr
  - http://jovies.kro.kr

### 추가 설정 (선택)
- [ ] SSL/TLS 인증서 설정 (Let's Encrypt)
- [ ] 모니터링 설정 (Prometheus, Grafana)
- [ ] 백업 설정

## 트러블슈팅

### ArgoCD 비밀번호를 잊어버렸을 때
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Nginx 설정 확인
```bash
sudo nginx -t
sudo systemctl status nginx
```

### Ingress Controller 상태 확인
```bash
kubectl get svc -n ingress-nginx
kubectl get pods -n ingress-nginx
```

### 로그 확인
```bash
# Nginx 로그
sudo tail -f /var/log/nginx/k8s-proxy-access.log
sudo tail -f /var/log/nginx/k8s-proxy-error.log

# ArgoCD 로그
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Ingress Controller 로그
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

