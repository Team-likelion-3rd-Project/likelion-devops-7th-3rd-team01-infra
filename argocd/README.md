# Argo CD (GitOps)

Git에 적힌 상태를 클러스터에 맞추는 도구. 클러스터 안에서 저장소를 보고 있다가 달라지면 스스로 반영한다 (Pull 방식).

## 구조 (온프렘)

| 브랜치 | 내용 | 누가 바꾸나 |
|---|---|---|
| develop | 앱 차트 `charts/newsbrief`, `values-onprem.yaml` | PR (보호 규칙) |
| deploy/onprem | develop 내용 + 이미지 태그 `deploy/tags-onprem.yaml` | workflow만 (사람이 직접 커밋하지 않음) |

Argo CD Application `newsbrief-onprem`(`argocd/newsbrief-onprem.yaml`)은 **deploy/onprem 하나만** 읽는다.

- develop은 보호 규칙이 있어 workflow가 직접 커밋할 수 없다 → 태그는 다른 브랜치에 둔다
- Argo CD는 한 앱에서 같은 저장소의 다른 브랜치를 같이 읽지 못한다 → deploy/onprem에 develop을 합쳐 한 브랜치로 만든다

배포 흐름

```
앱 머지 → 앱 CI가 이미지 push → deploy-onprem 호출
→ workflow가 deploy/onprem에 develop을 합치고 태그 파일 커밋
→ Argo CD가 3분 안에 반영 → workflow가 롤아웃·실행 버전(SHA) 확인

infra develop 머지(차트·values 변경) → sync-deploy-onprem이 deploy/onprem에 합침 → Argo CD가 3분 안에 반영
```

workflow는 클러스터를 직접 바꾸지 않는다 (kubectl은 확인에만 사용).
배포 SA에 Argo CD Application 권한은 주지 않는다. Application을 수정할 수 있으면 배포 대상(네임스페이스·클러스터)까지 바꿀 수 있어서다. 그래서 새로고침 요청 없이 Argo CD의 3분 확인 주기를 기다린다.
deploy/onprem은 PR로 develop에 합치지 않는다 (GitHub의 "Compare & pull request" 안내는 무시).

## 설치 (1회, k8s-cp 관리자)

```bash
bash onprem/argocd-setup.sh
```

- Argo CD 설치(차트 `argo/argo-cd`, 값 `argocd/values.yaml`) → 태그 브랜치 확인 → Application 적용 → 파드 재시작 여부 확인 → Helm 릴리스 기록 삭제
- 태그 브랜치가 없으면 만들 명령을 출력하고 멈춘다. 맥에서 만든 뒤 다시 실행
- 설치한 차트 버전: argo/argo-cd 10.11.6 (2026-10-27)

## deploy/onprem 브랜치 보호

운영 배포 기준이므로 force push·삭제를 막는다 (Settings → Branches → Add rule, 패턴 `deploy/onprem`).

- Allow force pushes: 끔, Allow deletions: 끔
- Require a pull request: **켜지 않는다** (workflow가 직접 커밋해야 함)

## deploy/onprem 브랜치를 새로 만들 때 (지워졌거나 처음 설치)

cp에서 지금 실행 중인 태그를 확인한다.

```bash
kubectl -n news get deploy api frontend -o jsonpath='{range .items[*]}{.metadata.name} {.spec.template.spec.containers[0].image}{"\n"}{end}'
```

맥(또는 push 권한이 있는 곳)에서 develop을 기준으로 만든다.

```bash
git checkout develop && git pull
git checkout -b deploy/onprem
mkdir -p deploy
cat > deploy/tags-onprem.yaml <<'TAGS'
# deploy-onprem workflow가 갱신한다. Argo CD가 이 파일의 태그로 온프렘에 배포한다
backend:
  image:
    tag: "<백엔드 SHA 40자리>"
frontend:
  image:
    tag: "<프론트 SHA 40자리>"
TAGS
git add deploy/tags-onprem.yaml && git commit -m "deploy(onprem): 초기 태그" && git push -u origin deploy/onprem
git checkout develop
```

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
