#!/bin/bash
# Add this to your ~/.zshrc to automatically manage SSH agent and keys

# SSH Agent Management
# This ensures only one ssh-agent runs and persists across terminal sessions

# Set the SSH agent environment file
SSH_ENV="$HOME/.ssh/agent-environment"

# Function to start the SSH agent
function start_agent {
    echo "Initializing new SSH agent..."
    # Start the agent
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    echo "succeeded"
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    # Add your key(s)
    /usr/bin/ssh-add ~/.ssh/workm4
}

# Check if agent is running
if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    # Test if agent PID is still valid
    ps -p ${SSH_AGENT_PID} > /dev/null || {
        start_agent
    }
else
    start_agent
fi

# Optional: Add aliases for common SSH connections
alias proxmox='ssh -p 2222 root@192.168.0.20'
alias rke-master='ssh ubuntu@192.168.0.201'
alias rke-worker1='ssh ubuntu@192.168.0.202'
alias rke-worker2='ssh ubuntu@192.168.0.203'