# When Argo CD's `manifest-generate-paths` Auto-Sync Runs Past a Mid-Sync Commit — reproduction

When It Runs — Run Report #RR15 · Testing what infrastructure actually does.

Run Report: https://whenitruns.substack.com/p/when-argo-cds-manifest-generate-paths

This repository holds the reproduction from the report above: the six Git-repository files and the three Applications printed in its §4 (Reproduction), byte for byte, and the commands its §4 prints, run one step at a time. Nothing here adds versions, configurations, or findings beyond the report.

## Setup pinned in the report

- Argo CD v3.5.3 from the release's official `manifests/install.yaml` (sha256 `7efe2d6bbc03f63623640f1e4198f16c84009d510fb810ef71e56df1b7614ba9`), applied with `kubectl apply -n argocd --server-side --force-conflicts`; the application controller's log level set to `debug` (the key `controller.log.level` in `argocd-cmd-params-cm`), the only setting changed.
- A single-node `kind` cluster on a Linux test VM (GNU coreutils), node image `kindest/node:v1.33.4` (digest-pinned).
- A local Git server, `gitea/gitea:1.27.3` (digest-pinned), on the kind Docker network, holding the repository `wir/rr15`; the hook Jobs use `busybox:1.37.0`.
- Three Applications with automated sync and `targetRevision: HEAD`: `rr15-p1` with the `argocd.argoproj.io/manifest-generate-paths: .` annotation and `selfHeal` off, `rr15-p2` with the annotation and `selfHeal: true`, `rr15-p3` without the annotation (control).
- In the report's lab the test VM had no internet access: the images the cluster runs were served to it from a local registry, `install.yaml` was applied unmodified, and the Git server's image was run by its tag (the linux/amd64 image in the pinned digest, `sha256:d584940b7143982682ac4541509dd628506c2b568221e6af41e5a2ead1de4fe7`, is what ran). On a connected machine the commands below pull as printed.
- Verified on: 2026-09-28 (desk sources re-checked; v3.5.3 was the latest release) · lab measured 2026-09-28 on Argo CD v3.5.3 — re-verification against the then-current release happens at publication.

## Not scripted here

The report describes these without printing a command for them, so they are not scripted:

- the timing of step 3 — the report pushes commit B once all three syncs to A are `Running`, held by their `PreSync` hooks (each hook runs for 60 seconds); `./reproduce.sh 2-poll` runs step 2's query once, so repeat it every 5 seconds and run step 3 when all three show `Running`;
- the watch in step 4 — the report reads every 5 seconds for 360 seconds after each sync to A finishes; `./reproduce.sh 4` reads once, so repeat it on that schedule;
- step 4 for `rr15-p2` and `rr15-p3` — the report's note "(the same for rr15-p2 and rr15-p3)": its four `rr15-p1` lines with `rr15-p1` replaced (the controller-log line already covers all three);
- reading the results side by side — for each Application, the sync status next to its two revisions, the operation's initiator and listed resources, the history length, the ConfigMap's `rev`, the hook Jobs, and the controller's lines.

Steps 1 and 3 run their git lines inside `gitops/` (the report's "a folder named gitops"), which leaves a nested Git repository there.

## Files

| File | From the report |
|---|---|
| `gitops/apps/p1/cm.yaml`, `gitops/apps/p1/presync.yaml` | §4 — the two repository files, byte for byte |
| `gitops/apps/p2/`, `gitops/apps/p3/` | §4 — "the same two files, byte for byte" |
| `applications.yaml` | §4 — the three Applications for step 2, byte for byte |
| `reproduce.sh` | §4 — every line of its block, with the commands it prints, one step per run |

## Run order

With Docker, `kind`, `kubectl`, `git`, `curl` and `jq` on a test machine (all times UTC):

1. `./reproduce.sh 0` — the `kind` cluster `rr15`, Argo CD v3.5.3 from its official install.yaml, the controller's log level at `debug`; every Argo CD pod Ready.
2. `./reproduce.sh 1` — start the Git server, wait (at most 2 minutes) until `http://localhost:3000/api/healthz` answers, then the user, the repository and commit A.
3. `./reproduce.sh 2` — T0: the three Applications; then `./reproduce.sh 2-poll` every 5 seconds.
4. When all three syncs to A are `Running`, `./reproduce.sh 3` — commit B, push, and a normal refresh of each Application.
5. `./reproduce.sh 4` — every 5 seconds for 360 seconds after each sync to A finishes.
6. `./reproduce.sh 5` — delete the cluster `rr15` and the Git server.

## Expected observation

From the report (§3):

> **Installation and design check:** the seven Argo CD pods were Ready with no restarts, and every container running the Argo CD image ran `quay.io/argoproj/argocd@sha256:5a7367b15ab5c9fcce917954ec74527c8e401671756611654a9d998d9fff0662` (the linux/amd64 image in the pinned `v3.5.3` index); after the log-level change and the controller's restart, the controller's environment had `ARGOCD_APPLICATION_CONTROLLER_LOGLEVEL=debug` and its log had debug lines. A server-side dry run of `applications.yaml` stored the annotation `argocd.argoproj.io/manifest-generate-paths: .` on P1 and P2 only, `selfHeal: true` on P2 only (P1 and P3: `automated: {}`), and `targetRevision: HEAD` on all three. Commit A (`02aaa02b05faade7413013a3d464b3920649fbd8`) was pushed at 10:26:04.9, and T0 was 10:26:05.4. At the first poll after T0 (10:26:10.4), each Application's sync to A was `Running` — started at 10:26:06, with the message "waiting for completion of hook batch/Job/rr15-presync" — and its `PreSync` Job for A was active.

> **B compared while A was running:** commit B (`c66c50c7914e31f0d9a3996d52977e751c2f3a7f`) was pushed at 10:26:25.7 (T0 + 20.3 s), and the refresh loop ran from 10:26:25.73 to 10:26:25.89. At the poll before (10:26:25.4), all three Applications showed `status.sync.revision` at A; at the next poll (10:26:30.4, T0 + 25 s), all three showed it at B while their syncs to A were still `Running`. The three syncs to A finished at 10:27:09 — the controller logged "Sync operation to 02aaa02b05faade7413013a3d464b3920649fbd8 succeeded" for P1, P2 and P3 at 10:27:09.78, 10:27:09.76 and 10:27:09.81.

> **P1 — annotation, `selfHeal` off:** no new sync operation started in the 360 seconds after the sync to A finished. In all 72 polls of that window (10:27:10.4 to 10:33:05.4), the operation state was still that of the sync to A, the sync status was `OutOfSync`, `status.sync.revision` was B while `status.operationState.syncResult.revision` was A, the ConfigMap's `rev` was `"A"`, the only Job was the `PreSync` Job for A, and `status.history` had one entry, for A. The controller compared P1 three times in that window — twice right after the sync to A (10:27:09.80 and 10:27:09.84) and once at 10:30:31.96, when the previous comparison had expired — and each time logged `Already attempted sync: revisions [c66c50c7914e31f0d9a3996d52977e751c2f3a7f] have no changes` at Debug and `Skipping auto-sync: most recent sync already to [c66c50c7914e31f0d9a3996d52977e751c2f3a7f]` at Info.

> **P2 — annotation, `selfHeal` on:** right after the sync to A, the controller logged `Already attempted sync: revisions [c66c50c7914e31f0d9a3996d52977e751c2f3a7f] have no changes` (Debug, 10:27:09.79) and then `Initiated automated sync to 'c66c50c7914e31f0d9a3996d52977e751c2f3a7f'` (10:27:09.80). That operation, with `initiatedBy.automated` set, listed two resources in `sync.resources` — the ConfigMap `rr15-cm` and the Job `rr15-presync` — and its result applied the ConfigMap only (`configmap/rr15-cm configured`); it finished at 10:27:10 and was logged at Info as `Partial sync operation to c66c50c7914e31f0d9a3996d52977e751c2f3a7f succeeded`. The ConfigMap's `rev` became `"B"` and the Application `Synced` (poll at 10:27:10.4). No `PreSync` Job for B was created — the Job in `rr15-p2` stayed the one for A, with the same UID, for the rest of the window — and `status.history` kept its one entry, for A.

> **P3 — no annotation (control):** right after the sync to A, the controller logged `Already attempted sync: comparing synced revisions to [c66c50c7914e31f0d9a3996d52977e751c2f3a7f]` (Info, 10:27:09.84) and `Initiated automated sync to 'c66c50c7914e31f0d9a3996d52977e751c2f3a7f'` (10:27:09.86). That automated operation listed no resources (a full sync): a `PreSync` Job for B (`rr15/rev: "B"`) was created at 10:27:12 and succeeded, the sync finished at 10:28:14 (`Sync operation to c66c50c7914e31f0d9a3996d52977e751c2f3a7f succeeded`), the ConfigMap's `rev` became `"B"` and the Application `Synced` (poll at 10:28:15.4), and `status.history` grew from one entry to two, the second for B.

> "Auto-synced" in this section means a new sync operation for B started by the controller (its `initiatedBy.automated` set); "partial" means that operation listed resources in `sync.resources`; "the hook ran for B" means a Job `rr15-presync` labeled `rr15/rev: "B"` was created; "a history entry" means `status.history` grew by one.

The report's own limits (§6):

> **The 3.3 line and other 3.4 releases.** We measured v3.5.3 only; v3.4.9 has the same automated-sync call by the source, and the issue says the behavior appeared after an upgrade from v3.3.9 to v3.4.2. Neither v3.4.9 nor the 3.3 line was measured.

> **Webhooks.** We requested each refresh by hand; with a Git webhook, when the new commit is compared depends on the webhook's timing, which we did not measure.

> **Other source types and multi-source applications.** Our applications use plain manifests from one Git source; the issue says Helm sources are affected too, and a maintainer reproduced it with a Helm chart from Git — we measured neither, nor applications with several sources.

> **After the window.** We watched each application for 360 seconds after its sync to A; what happens later — for instance when the next commit that changes the path arrives — was not measured in this report.

> **Other paths and annotation values.** We used the annotation value `.` (the application's own path) and a commit that changes every file of each path; other values and partial changes were not measured.

---

The team behind When It Runs maintains its own test environments and re-verifies findings when new releases change things; that is what the "Verified on" date means.

Licensed under the Apache License 2.0 — see `LICENSE`.
