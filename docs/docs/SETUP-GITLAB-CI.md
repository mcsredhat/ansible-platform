# GitLab CI — Self-Hosted Runner Setup (Phase 6)

The pipeline (`.gitlab-ci.yml`) runs on a self-hosted GitLab Runner in the
homelab, using the **shell executor** with **podman** for molecule.

## Where to run it

A dedicated VM is cleanest, but the **control node** works for a homelab —
it already has Ansible and the project. The runner needs:

- internet access (VMnet8 NIC) — it pulls container images and pip packages
- ~2 vCPU / 4 GB RAM for comfortable molecule runs

## 1. Install the runner (RHEL 9)

```bash
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | sudo bash
sudo dnf install -y gitlab-runner
```

## 2. Install the CI toolchain (what the jobs call)

```bash
sudo dnf install -y podman git python3-pip
sudo pip3 install --upgrade \
    ansible-core ansible-lint yamllint \
    "molecule>=24" "molecule-plugins[podman]"
# collections used by the roles:
ansible-galaxy collection install -r requirements.yml
```

Verify: `yamllint --version && ansible-lint --version && molecule --version && podman --version`

## 3. Register the runner

In GitLab: **Project → Settings → CI/CD → Runners → New project runner**
- Tags: `homelab`  (the pipeline's `default.tags` expects this)
- Executor: `shell`

Then on the runner host, paste the registration command GitLab shows, e.g.:

```bash
sudo gitlab-runner register \
  --url https://gitlab.com \
  --token <RUNNER_TOKEN> \
  --executor shell \
  --tag-list homelab \
  --description "homelab-runner"
sudo systemctl enable --now gitlab-runner
```

## 4. Podman for the gitlab-runner user

Molecule runs rootless podman as the `gitlab-runner` user:

```bash
sudo loginctl enable-linger gitlab-runner
sudo -u gitlab-runner podman info >/dev/null && echo "podman OK"
```

If `podman info` fails on subuid/subgid, add ranges:

```bash
echo "gitlab-runner:100000:65536" | sudo tee -a /etc/subuid /etc/subgid
sudo -u gitlab-runner podman system migrate
```

## 5. First pipeline

Push the repo to GitLab (see repo README). The pipeline runs:

| Stage | What it does | Fails when |
|---|---|---|
| lint | `yamllint`, `ansible-lint` | style/practice violations |
| syntax | `--syntax-check` on site.yml + every play | broken imports/typos |
| secrets | `scripts/ci/secrets-scan.sh` | plaintext secret committed, or vault unencrypted |
| molecule | full `molecule test` per role (systemd podman containers) | role fails converge/idempotence/verify |

Notes:
- **wordpress** is excluded from molecule (needs the live data tier); it is
  covered by syntax-check and the deployed platform.
- **php_fpm** is `allow_failure: true` for a known cosmetic idempotence
  exception (dnf module reset) until that task is hardened.

## 6. README badge

```markdown
[![pipeline status](https://gitlab.com/<namespace>/ansible-platform/badges/main/pipeline.svg)](https://gitlab.com/<namespace>/ansible-platform/-/pipelines)
```
