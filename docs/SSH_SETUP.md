# SSH Key Management for Homelab

This guide covers SSH key setup and management for accessing Proxmox and cluster nodes.

## Problem: Permission Denied (publickey)

When you see:
```
ssh -p 2222 root@192.168.0.20
root@192.168.0.20: Permission denied (publickey).
```

This means the SSH server requires key authentication and your key isn't loaded.

## Solution: SSH Agent Configuration

### Manual Method (Temporary)

```bash
# Start SSH agent
eval "$(ssh-agent -s)"

# Add your SSH key
ssh-add ~/.ssh/workm4

# Now SSH works
ssh -p 2222 root@192.168.0.20
```

### Automatic Method (Permanent)

Add this to your `~/.zshrc` or `~/.bashrc`:

```bash
# SSH Agent Configuration
# Automatically start SSH agent and load keys
SSH_ENV="$HOME/.ssh/agent-environment"

function start_agent {
    echo "Initializing new SSH agent..."
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    echo "succeeded"
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    /usr/bin/ssh-add ~/.ssh/workm4
}

# Source SSH agent environment if it exists, otherwise start new agent
if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    # Test if agent PID is still valid
    ps -p ${SSH_AGENT_PID} > /dev/null || {
        start_agent
    }
else
    start_agent
fi

# Helpful aliases for your homelab
alias proxmox='ssh -p 2222 root@192.168.0.20'
alias rke-master='ssh ubuntu@192.168.0.201'
alias rke-worker1='ssh ubuntu@192.168.0.202'
alias rke-worker2='ssh ubuntu@192.168.0.203'
alias rke-worker3='ssh ubuntu@192.168.0.204'
alias rke-worker4='ssh ubuntu@192.168.0.205'
alias rke-worker5='ssh ubuntu@192.168.0.206'
alias rke-worker6='ssh ubuntu@192.168.0.207'
```

After adding, reload your shell:
```bash
source ~/.zshrc
```

## Benefits

1. **Automatic key loading** - No manual ssh-add needed
2. **Single agent** - Reuses existing agent if running
3. **Persistent across terminals** - Works in all new terminal windows
4. **Convenient aliases** - Quick access to all nodes

## Using the Aliases

```bash
# Access Proxmox
proxmox

# Access master node
rke-master

# Access any worker
rke-worker3
```

## SSH Config Alternative

You can also create `~/.ssh/config`:

```
Host proxmox
    HostName 192.168.0.20
    Port 2222
    User root
    IdentityFile ~/.ssh/workm4

Host rke-master
    HostName 192.168.0.201
    User ubuntu
    IdentityFile ~/.ssh/workm4

Host rke-worker-*
    User ubuntu
    IdentityFile ~/.ssh/workm4

Host rke-worker-1
    HostName 192.168.0.202

Host rke-worker-2
    HostName 192.168.0.203

Host rke-worker-3
    HostName 192.168.0.204

Host rke-worker-4
    HostName 192.168.0.205

Host rke-worker-5
    HostName 192.168.0.206

Host rke-worker-6
    HostName 192.168.0.207
```

Then use:
```bash
ssh proxmox
ssh rke-master
ssh rke-worker-3
```

## Troubleshooting

### Agent not starting
```bash
# Kill existing agents
pkill ssh-agent

# Remove environment file
rm ~/.ssh/agent-environment

# Reload shell
source ~/.zshrc
```

### Wrong key loaded
```bash
# List loaded keys
ssh-add -l

# Remove all keys
ssh-add -D

# Add correct key
ssh-add ~/.ssh/workm4
```

### Permission issues
```bash
# Fix permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/workm4
chmod 644 ~/.ssh/workm4.pub
```