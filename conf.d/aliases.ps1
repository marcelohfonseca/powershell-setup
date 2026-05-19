# ─────────────────────────────────────────────────────────────
# Navigation
# ─────────────────────────────────────────────────────────────

function .. { Set-Location .. }
function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }

function dev { Set-Location ~/dev }

Set-Alias c Clear-Host

# ─────────────────────────────────────────────────────────────
# Eza / Listing
# ─────────────────────────────────────────────────────────────

function l {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -lh --group-directories-first --icons
        return
    }

    Get-ChildItem -Force
}

function la {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -lha --group-directories-first --icons
        return
    }

    Get-ChildItem -Force -Hidden
}

function lt {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --tree --level=2 --long --icons --git
        return
    }

    Get-ChildItem -Recurse -Depth 2 -Force
}

function lta {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --tree --level=2 --long --icons --git -a
        return
    }

    Get-ChildItem -Recurse -Depth 2 -Force -Hidden
}

# ─────────────────────────────────────────────────────────────
# FZF
# ─────────────────────────────────────────────────────────────

function ff {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Warning 'fzf nao instalado.'
        return
    }

    if (Get-Command bat -ErrorAction SilentlyContinue) {
        fzf --preview "bat --style=numbers --color=always {}"
        return
    }

    fzf
}

# ─────────────────────────────────────────────────────────────
# Docker
# ─────────────────────────────────────────────────────────────

Set-Alias d docker

function dps { docker ps }
function dpa { docker ps -a }
function di { docker images }
function dv { docker volume ls }

function dstopall {
    docker stop $(docker ps -q)
}

function dprune {
    docker system prune
}

function dprunea {
    docker system prune -a
}

# Docker Desktop no Windows geralmente dispensa start/stop
# mas você pode usar:

function drestart {
    Restart-Service com.docker.service
}

# ─────────────────────────────────────────────────────────────
# Git
# ─────────────────────────────────────────────────────────────

Set-Alias g git

function gs {
    git status -sb
}

function ga {
    git add $args
}

function gb {
    git branch
}

function gc {
    git commit $args
}

function gl {
    git pull --no-verify-signatures
}

function gp {
    git push
}

function gm {
    git merge --no-verify-signatures
}

function glog {
    git log --oneline --graph --decorate --all
}

# ─────────────────────────────────────────────────────────────
# Python
# ─────────────────────────────────────────────────────────────

Set-Alias py python

function ipy {
    ipython
}

function venv {
    python -m venv .venv
    act
}

function act {
    . .\.venv\Scripts\Activate.ps1
}

function pipu {
    python -m pip install --upgrade pip
}

function ipk {
    pip install ipykernel
}

# ─────────────────────────────────────────────────────────────
# Tools
# ─────────────────────────────────────────────────────────────

Set-Alias bat bat

function code. {
    code .
}

# ─────────────────────────────────────────────────────────────
# PowerShell profile
# ─────────────────────────────────────────────────────────────

function profile {
    code $PROFILE
}

function reload {
    . $PROFILE
}

# ─────────────────────────────────────────────────────────────
# Linux-like helpers
# ─────────────────────────────────────────────────────────────

function touch {
    New-Item -ItemType File -Path $args
}

function mkcd {
    param($dir)

    New-Item -ItemType Directory -Path $dir
    Set-Location $dir
}

function which {
    Get-Command $args
}

function pwdc {
    (Get-Location).Path | Set-Clipboard
}

function open {
    explorer .
}
