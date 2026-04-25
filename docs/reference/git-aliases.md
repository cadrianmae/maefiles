# Git Aliases Reference

Full reference for the `oh-my-zsh` git plugin aliases available in Mae's zsh.

Quick lookup: `alias | grep git` or `cs git-aliases`.

---

## Essentials

### Everyday

| Alias | Command | Use |
|-------|---------|-----|
| `gst` | `git status` | Check what's changed |
| `gd` | `git diff` | See unstaged changes |
| `gds` | `git diff --staged` | See staged changes |
| `ga` | `git add` | Stage a file |
| `gaa` | `git add --all` | Stage everything |
| `gcmsg "msg"` | `git commit -m "msg"` | Commit with message |
| `gp` | `git push` | Push |
| `gl` | `git pull` | Pull |

### Branches

| Alias | Command | Use |
|-------|---------|-----|
| `gco <branch>` | `git checkout <branch>` | Switch branch |
| `gcb <new>` | `git checkout -b <new>` | Create + switch to new branch |
| `gcm` | `git checkout main` | Jump to main |

### Log

| Alias | Command | Use |
|-------|---------|-----|
| `glog` | `git log --oneline --decorate --graph` | Compact log graph |
| `glola` | pretty graph, all branches | Full history view |

### Danger zone [WARN]

| Alias | Command | Use |
|-------|---------|-----|
| `gpf` | `git push --force-with-lease --force-if-includes` | [OK] Safe force-push |
| `gpf!` | `git push --force` | [WARN] Hard force-push |
| `gpristine` | `git reset --hard && git clean -fdx` | Nuke working tree (+ ignored files) |
| `gwipe` | `git reset --hard && git clean -fd` | Nuke tracked changes |

---

## Full reference

### Status & diff

| Alias | Command |
|-------|---------|
| `g` | `git` |
| `gst` | `git status` |
| `gss` | `git status --short` |
| `gsb` | `git status --short --branch` |
| `gd` | `git diff` |
| `gds` | `git diff --staged` |
| `gdca` | `git diff --cached` |
| `gdcw` | `git diff --cached --word-diff` |
| `gdw` | `git diff --word-diff` |
| `gdup` | `git diff @{upstream}` |
| `gdt` | `git diff-tree --no-commit-id --name-only -r` |
| `gbl` | `git blame -w` |
| `gsh` | `git show` |
| `gsps` | `git show --pretty=short --show-signature` |
| `gcount` | `git shortlog --summary --numbered` |

### Adding & staging

| Alias | Command |
|-------|---------|
| `ga` | `git add` |
| `gaa` | `git add --all` |
| `gapa` | `git add --patch` |
| `gau` | `git add --update` |
| `gav` | `git add --verbose` |
| `gap` | `git apply` |
| `gapt` | `git apply --3way` |
| `grs` | `git restore` |
| `grst` | `git restore --staged` |
| `grss` | `git restore --source` |
| `gru` | `git reset --` |
| `grm` | `git rm` |
| `grmc` | `git rm --cached` |

### Committing

| Alias | Command |
|-------|---------|
| `gc` | `git commit -v` |
| `gc!` | `git commit -v --amend` |
| `gca` | `git commit -v -a` |
| `gca!` | `git commit -v -a --amend` |
| `gcam` | `git commit -a -m` |
| `gcas` | `git commit -a -s` |
| `gcasm` | `git commit -a -s -m` |
| `gcmsg` | `git commit -m` |
| `gcn` | `git commit -v --no-edit` |
| `gcn!` | `git commit -v --no-edit --amend` |
| `gcan!` | `git commit -v -a --no-edit --amend` |
| `gcann!` | `git commit -v -a --date=now --no-edit --amend` |
| `gcans!` | `git commit -v -a -s --no-edit --amend` |
| `gcfu` | `git commit --fixup` |
| `gcs` | `git commit -S` (gpg sign) |
| `gcss` | `git commit -S -s` |
| `gcsm` | `git commit -s -m` |
| `gcssm` | `git commit -S -s -m` |

### Branches

| Alias | Command |
|-------|---------|
| `gb` | `git branch` |
| `gba` | `git branch --all` |
| `gbr` | `git branch --remote` |
| `gbd` | `git branch -d` |
| `gbD` | `git branch -D` |
| `gbm` | `git branch --move` |
| `gbnm` | `git branch --no-merged` |
| `gbg` | List gone branches |
| `gbgd` | Delete gone branches (safe) |
| `gbgD` | Delete gone branches (force) |
| `ggsup` | Set upstream to `origin/<current>` |

### Checkout & switch

| Alias | Command |
|-------|---------|
| `gco` | `git checkout` |
| `gcor` | `git checkout --recurse-submodules` |
| `gcb` | `git checkout -b` |
| `gcB` | `git checkout -B` |
| `gcm` | checkout main |
| `gcd` | checkout develop |
| `gsw` | `git switch` |
| `gswc` | `git switch --create` |
| `gswm` | switch main |
| `gswd` | switch develop |

### Log

| Alias | Command |
|-------|---------|
| `glo` | `git log --oneline --decorate` |
| `glog` | oneline + graph |
| `gloga` | oneline + graph + all |
| `glg` | `git log --stat` |
| `glgp` | `git log --stat -p` |
| `glgg` | `git log --graph` |
| `glgga` | `git log --graph --decorate --all` |
| `glgm` | `git log --graph -n10` |
| `glol` | pretty graph (relative dates) |
| `glola` | pretty graph, all branches |
| `glols` | pretty graph + stat |
| `glod` | pretty graph (absolute dates) |
| `glods` | pretty graph, short dates |
| `glp` | `_git_log_prettily` |
| `gwch` | `git log -p --abbrev-commit --pretty=medium --raw` |
| `grf` | `git reflog` |

### Remote / fetch

| Alias | Command |
|-------|---------|
| `gr` | `git remote` |
| `gra` | `git remote add` |
| `grv` | `git remote -v` |
| `grrm` | `git remote remove` |
| `grmv` | `git remote rename` |
| `grset` | `git remote set-url` |
| `grup` | `git remote update` |
| `gf` | `git fetch` |
| `gfo` | `git fetch origin` |
| `gfa` | `git fetch --all --tags --prune --jobs=10` |

### Push

| Alias | Command |
|-------|---------|
| `gp` | `git push` |
| `gpv` | `git push -v` |
| `gpd` | `git push --dry-run` |
| `gpf` | `git push --force-with-lease --force-if-includes` (safe) |
| `gpf!` | `git push --force` (hard) |
| `gpsup` | push `-u origin <current>` |
| `gpsupf` | `gpsup` + safe force |
| `gpoat` | push all branches + tags to origin |
| `gpod` | `git push origin --delete` |
| `gpu` | `git push upstream` |
| `ggpush` | push origin `<current>` |

### Pull

| Alias | Command |
|-------|---------|
| `gl` | `git pull` |
| `gpr` | `git pull --rebase` |
| `gprv` | `git pull --rebase -v` |
| `gpra` | `git pull --rebase --autostash` |
| `gprav` | `git pull --rebase --autostash -v` |
| `gprom` | rebase-pull `origin/main` |
| `gpromi` | rebase-pull `origin/main` (interactive) |
| `gprum` | rebase-pull `upstream/main` |
| `gprumi` | rebase-pull `upstream/main` (interactive) |
| `glum` | pull upstream main |
| `gluc` | pull upstream `<current>` |
| `ggpull` | pull origin `<current>` |

### Merge

| Alias | Command |
|-------|---------|
| `gm` | `git merge` |
| `gma` | `git merge --abort` |
| `gmc` | `git merge --continue` |
| `gmff` | `git merge --ff-only` |
| `gms` | `git merge --squash` |
| `gmom` | merge `origin/main` |
| `gmum` | merge `upstream/main` |
| `gmtl` | `git mergetool --no-prompt` |
| `gmtlvim` | `git mergetool --no-prompt --tool=vimdiff` |

### Rebase

| Alias | Command |
|-------|---------|
| `grb` | `git rebase` |
| `grba` | `git rebase --abort` |
| `grbc` | `git rebase --continue` |
| `grbs` | `git rebase --skip` |
| `grbi` | `git rebase -i` |
| `grbo` | `git rebase --onto` |
| `grbm` | rebase onto main |
| `grbd` | rebase onto develop |
| `grbom` | rebase onto `origin/main` |
| `grbum` | rebase onto `upstream/main` |

### Cherry-pick & revert

| Alias | Command |
|-------|---------|
| `gcp` | `git cherry-pick` |
| `gcpa` | `git cherry-pick --abort` |
| `gcpc` | `git cherry-pick --continue` |
| `grev` | `git revert` |
| `greva` | `git revert --abort` |
| `grevc` | `git revert --continue` |

### Stash

| Alias | Command |
|-------|---------|
| `gsta` | `git stash push` |
| `gstall` | `git stash --all` |
| `gstp` | `git stash pop` |
| `gstaa` | `git stash apply` |
| `gstl` | `git stash list` |
| `gsts` | `git stash show -p` |
| `gstd` | `git stash drop` |
| `gstc` | `git stash clear` |

### Reset

| Alias | Command |
|-------|---------|
| `grh` | `git reset` |
| `grhh` | `git reset --hard` |
| `grhs` | `git reset --soft` |
| `grhk` | `git reset --keep` |
| `groh` | `git reset origin/<current> --hard` |

### Tags

| Alias | Command |
|-------|---------|
| `gta` | `git tag -a` |
| `gts` | `git tag -s` |
| `gtv` | `git tag \| sort -V` |
| `gtl` | list tags matching prefix |
| `gdct` | describe latest tag |

### Worktrees

| Alias | Command |
|-------|---------|
| `gwt` | `git worktree` |
| `gwta` | `git worktree add` |
| `gwtls` | `git worktree list` |
| `gwtmv` | `git worktree move` |
| `gwtrm` | `git worktree remove` |

### Submodules

| Alias | Command |
|-------|---------|
| `gsi` | `git submodule init` |
| `gsu` | `git submodule update` |
| `gcl` | `git clone --recurse-submodules` |
| `gclf` | shallow clone with submodules, no blobs |

### Bisect

| Alias | Command |
|-------|---------|
| `gbs` | `git bisect` |
| `gbss` | `git bisect start` |
| `gbsg` | `git bisect good` |
| `gbsb` | `git bisect bad` |
| `gbsn` | `git bisect new` |
| `gbso` | `git bisect old` |
| `gbsr` | `git bisect reset` |

### Apply patches (am)

| Alias | Command |
|-------|---------|
| `gam` | `git am` |
| `gama` | `git am --abort` |
| `gamc` | `git am --continue` |
| `gams` | `git am --skip` |
| `gamscp` | `git am --show-current-patch` |

### Config & ignore

| Alias | Command |
|-------|---------|
| `gcf` | `git config --list` |
| `gignore` | `git update-index --assume-unchanged` |
| `gunignore` | `git update-index --no-assume-unchanged` |
| `gignored` | list assume-unchanged files |
| `gfg` | `git ls-files \| grep` |

### SVN bridge

| Alias | Command |
|-------|---------|
| `gsd` | `git svn dcommit` |
| `gsr` | `git svn rebase` |

### GUI & help

| Alias | Command |
|-------|---------|
| `gg` | `git gui citool` |
| `gga` | `git gui citool --amend` |
| `gk` | `gitk --all --branches` |
| `gke` | `gitk --all` from reflog |
| `ghh` | `git help` |

### Navigation

| Alias | Command |
|-------|---------|
| `grt` | `cd` to repo root |

### Danger zone [WARN]

| Alias | Command | What it does |
|-------|---------|--------------|
| `gpf!` | `git push --force` | Hard force-push — can overwrite others' work |
| `gwipe` | `git reset --hard && git clean -fd` | Nuke tracked + untracked |
| `gpristine` | `git reset --hard && git clean -fdx` | Nuke everything incl. `.gitignore`d files |
| `gwip` | WIP commit (bypasses hooks + signing) | Quick save-point — pair with `gunwip` to undo |
| `gunwip` | Undo last `gwip` commit | Resets `HEAD~1` if last msg matches `--wip--` |
