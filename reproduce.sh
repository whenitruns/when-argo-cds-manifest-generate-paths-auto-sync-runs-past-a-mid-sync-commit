#!/usr/bin/env bash
# Run Report #RR15, §4 (Reproduction). Every line of the report's §4 block appears below, in order and exactly as printed.
# Each step runs the commands its lines print, one step per invocation. The six repository files are in gitops/ (this
# repository's copy of them); steps 1 and 3 run their git lines there, in subshells, as printed.
#   ./reproduce.sh 0 | 1 | 2 | 2-poll | 3 | 4 | 5
# Exit codes: step 4's controller-log line ends in grep, which exits 1 when no line matches yet; `docker run` in step 1 and
# the commits in steps 1 and 3 exit non-zero when run a second time (the container or the commit already exists). The
# script runs under `set -uo pipefail` without `-e`, so a non-zero exit does not stop a step; its loops (step 1's healthz
# wait, step 3's refresh loop) have no pipe in their conditions.
set -uo pipefail
cd "$(dirname "$0")"

step_0() {
# 0. Bring up a kind cluster (node k8s v1.33.4) and install Argo CD v3.5.3 from its official install.yaml;
#    set the application controller's log level to debug and restart it; confirm every pod is Ready.
#      kind create cluster --name rr15 --image kindest/node:v1.33.4@sha256:25a6018e48dfcaee478f4a59af81157a437f15e6e140bf103f85a2e7cd0cbbf2
#      kubectl create namespace argocd
#      kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml
#      kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"controller.log.level":"debug"}}'
#      kubectl -n argocd rollout restart statefulset argocd-application-controller
#      kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=300s
#      kubectl -n argocd wait --for=condition=Ready pods --all --timeout=600s
kind create cluster --name rr15 --image kindest/node:v1.33.4@sha256:25a6018e48dfcaee478f4a59af81157a437f15e6e140bf103f85a2e7cd0cbbf2
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"controller.log.level":"debug"}}'
kubectl -n argocd rollout restart statefulset argocd-application-controller
kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=300s
kubectl -n argocd wait --for=condition=Ready pods --all --timeout=600s
}

step_1() {
# 1. Start a local Git server on the kind Docker network, wait until it answers (at most 2 minutes), then
#    push the six repository files below as wir/rr15 in one commit (commit A), from a folder named gitops
#    that holds them (apps/p1/, apps/p2/, apps/p3/).
#      docker run -d --name rr15-git --network kind -p 127.0.0.1:3000:3000 -e GITEA__security__INSTALL_LOCK=true gitea/gitea:1.27.3@sha256:87a67ee09d3ae0d1df5fda5dcda3e2a1f9236a45b0a59025d6e00e46adc43bef
#      for i in $(seq 1 120); do curl -sf http://localhost:3000/api/healthz >/dev/null && break; sleep 1; done
#      docker exec -u git rr15-git gitea admin user create --username wir --password rr15-pass-1 --email wir@example.com --admin --must-change-password=false
#      curl -s -u wir:rr15-pass-1 -H 'Content-Type: application/json' -d '{"name":"rr15"}' http://localhost:3000/api/v1/user/repos
#      (cd gitops && git init -b main && git add . && git -c user.name=wir -c user.email=wir@example.com commit -m 'rr15 A' && git push http://wir:rr15-pass-1@localhost:3000/wir/rr15.git main)
docker run -d --name rr15-git --network kind -p 127.0.0.1:3000:3000 -e GITEA__security__INSTALL_LOCK=true gitea/gitea:1.27.3@sha256:87a67ee09d3ae0d1df5fda5dcda3e2a1f9236a45b0a59025d6e00e46adc43bef
for i in $(seq 1 120); do curl -sf http://localhost:3000/api/healthz >/dev/null && break; sleep 1; done
docker exec -u git rr15-git gitea admin user create --username wir --password rr15-pass-1 --email wir@example.com --admin --must-change-password=false
curl -s -u wir:rr15-pass-1 -H 'Content-Type: application/json' -d '{"name":"rr15"}' http://localhost:3000/api/v1/user/repos
(cd gitops && git init -b main && git add . && git -c user.name=wir -c user.email=wir@example.com commit -m 'rr15 A' && git push http://wir:rr15-pass-1@localhost:3000/wir/rr15.git main)
}

step_2() {
# 2. T0: create the three Applications (applications.yaml below) and poll every 5 s.
#      kubectl apply -f applications.yaml
#      kubectl -n argocd get applications rr15-p1 rr15-p2 rr15-p3 -o custom-columns=NAME:.metadata.name,PHASE:.status.operationState.phase,SYNC:.status.sync.status,SYNC_REV:.status.sync.revision
kubectl apply -f applications.yaml
kubectl -n argocd get applications rr15-p1 rr15-p2 rr15-p3 -o custom-columns=NAME:.metadata.name,PHASE:.status.operationState.phase,SYNC:.status.sync.status,SYNC_REV:.status.sync.revision
}

step_2_poll() {
# 2 (the poll) — step 2's read-only query, repeatable every 5 s.
kubectl -n argocd get applications rr15-p1 rr15-p2 rr15-p3 -o custom-columns=NAME:.metadata.name,PHASE:.status.operationState.phase,SYNC:.status.sync.status,SYNC_REV:.status.sync.revision
}

step_3() {
# 3. When all three syncs to A are Running (held by their PreSync hooks), make commit B, push it, and
#    request a normal refresh of each Application.
#      (cd gitops && sed -i 's/"A"/"B"/g; s/rev=A/rev=B/' apps/p*/cm.yaml apps/p*/presync.yaml && git -c user.name=wir -c user.email=wir@example.com commit -am 'rr15 B' && git push http://wir:rr15-pass-1@localhost:3000/wir/rr15.git main)
#      for n in 1 2 3; do kubectl -n argocd annotate application rr15-p$n argocd.argoproj.io/refresh=normal --overwrite; done
(cd gitops && sed -i 's/"A"/"B"/g; s/rev=A/rev=B/' apps/p*/cm.yaml apps/p*/presync.yaml && git -c user.name=wir -c user.email=wir@example.com commit -am 'rr15 B' && git push http://wir:rr15-pass-1@localhost:3000/wir/rr15.git main)
for n in 1 2 3; do kubectl -n argocd annotate application rr15-p$n argocd.argoproj.io/refresh=normal --overwrite; done
}

step_4() {
# 4. For 360 s after each sync to A finishes (every 5 s): the operation, the sync status and revisions,
#    the history, the ConfigMap, the hook Jobs, and the controller's lines for the three Applications.
#      kubectl -n argocd get application rr15-p1 -o jsonpath='{.status.sync.status} {.status.sync.revision} {.status.operationState.syncResult.revision} {.status.operationState.phase} {.status.operationState.operation.initiatedBy.automated} {.status.operationState.operation.sync.resources}{"\n"}'
#      kubectl -n argocd get application rr15-p1 -o json | jq '.status.history | length'
#      kubectl -n rr15-p1 get configmap rr15-cm -o jsonpath='{.data.rev}{"\n"}'
#      kubectl -n rr15-p1 get jobs -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.uid} {.metadata.creationTimestamp} {.metadata.labels.rr15/rev}{"\n"}{end}'
#      kubectl -n argocd logs statefulset/argocd-application-controller --timestamps | grep -E 'rr15-p[123]' | grep -E 'Skipping auto-sync|Already attempted sync|Initiated automated sync|[Ss]ync operation to'
#    (the same for rr15-p2 and rr15-p3)
kubectl -n argocd get application rr15-p1 -o jsonpath='{.status.sync.status} {.status.sync.revision} {.status.operationState.syncResult.revision} {.status.operationState.phase} {.status.operationState.operation.initiatedBy.automated} {.status.operationState.operation.sync.resources}{"\n"}'
kubectl -n argocd get application rr15-p1 -o json | jq '.status.history | length'
kubectl -n rr15-p1 get configmap rr15-cm -o jsonpath='{.data.rev}{"\n"}'
kubectl -n rr15-p1 get jobs -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.uid} {.metadata.creationTimestamp} {.metadata.labels.rr15/rev}{"\n"}{end}'
kubectl -n argocd logs statefulset/argocd-application-controller --timestamps | grep -E 'rr15-p[123]' | grep -E 'Skipping auto-sync|Already attempted sync|Initiated automated sync|[Ss]ync operation to'
}

step_5() {
# 5. Delete the test cluster and the Git server (our cluster and container only).
#      kind delete cluster --name rr15
#      docker rm -f rr15-git
kind delete cluster --name rr15
docker rm -f rr15-git
}

case "${1:-}" in
  0) step_0 ;;
  1) step_1 ;;
  2) step_2 ;;
  2-poll) step_2_poll ;;
  3) step_3 ;;
  4) step_4 ;;
  5) step_5 ;;
  *) echo "usage: $0 0 | 1 | 2 | 2-poll | 3 | 4 | 5  (one step per run; see README for the order)"; exit 2 ;;
esac
