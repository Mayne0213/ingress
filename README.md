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

### 초기 설정

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

