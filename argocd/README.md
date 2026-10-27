# Argo CD (GitOps)

Git에 적힌 상태를 클러스터에 맞추는 도구. 클러스터 안에서 저장소를 보고 있다가 달라지면 스스로 반영한다 (Pull 방식).

## 구조 (온프렘)

| 무엇 | 어디 | 누가 바꾸나 |
|---|---|---|
| 앱 차트, values-onprem.yaml | develop 브랜치 `charts/newsbrief` | PR (보호 규칙) |
| 이미지 태그 | deploy/onprem 브랜치 `deploy/tags-onprem.yaml` | deploy-onprem workflow가 자동 커밋 |
| 둘을 합쳐 배포 | Argo CD Application `newsbrief-onprem` (`argocd/newsbrief-onprem.yaml`) | Argo CD |

develop은 보호 규칙이 있어 workflow가 직접 커밋할 수 없다. 그래서 태그만 별도 브랜치에 둔다.

배포 흐름

```
앱 머지 → 앱 CI가 이미지 push → deploy-onprem 호출
→ workflow가 deploy/onprem의 태그 파일 커밋 → Argo CD 새로고침 요청
→ Argo CD가 반영 → workflow가 롤아웃·실행 버전(SHA) 확인
```

workflow는 클러스터를 직접 바꾸지 않는다 (kubectl은 확인·새로고침 요청에만 사용).

## 설치 (1회, k8s-cp 관리자)

```bash
bash onprem/argocd-setup.sh
```

- Argo CD 설치(차트 `argo/argo-cd`, 값 `argocd/values.yaml`) → 태그 브랜치 확인 → Application 적용 → 파드 재시작 여부 확인 → Helm 릴리스 기록 삭제
- 태그 브랜치가 없으면 만들 명령을 출력하고 멈춘다. 맥에서 만든 뒤 다시 실행
- 설치한 차트 버전: (설치 후 기록)

## 화면·관리자 비밀번호

- 주소: `http://<k8s-cp Tailscale IP>:30880` (Tailscale 안에서만, 주소는 팀 채팅으로만 공유)
- 처음 비밀번호 (cp에서만 확인, 채팅·저장소에 올리지 않음):
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  ```
- 로그인 후 User Info → Update Password로 바꾸고, 처음 비밀번호 Secret은 지운다:
  `kubectl -n argocd delete secret argocd-initial-admin-secret`
- 팀원 공유는 Grafana처럼 DM으로

## 장애 시험할 때 (selfHeal 끄기)

selfHeal은 kubectl로 바꾼 상태를 몇 초 안에 Git 기준으로 되돌린다. Redis를 0개로 줄이는 시험(B1 등)이 바로 복구되므로 시험 중에는 끈다.

```bash
# 끄기
kubectl -n argocd patch application newsbrief-onprem --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'
# 시험 끝나고 켜기 (꺼둔 동안 바꾼 것은 이때 Git 기준으로 돌아간다)
kubectl -n argocd patch application newsbrief-onprem --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
```

## 롤백

- deploy-onprem을 이전 SHA로 수동 실행 (태그 파일이 그 SHA로 커밋됨)
- 또는 deploy/onprem 브랜치의 태그 커밋을 되돌리기 (`git revert`)

## 상태 확인

```bash
kubectl -n argocd get application newsbrief-onprem
```

`SYNC STATUS: Synced`, `HEALTH STATUS: Healthy`면 Git과 클러스터가 같다. `OutOfSync`면 누군가 직접 바꿨거나 반영 대기 중이다.
