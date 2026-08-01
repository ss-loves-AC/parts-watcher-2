# parts-watcher Setup Guide

## SSH Keys Setup

### Generate SSH Key
```bash
ssh-keygen -t ed25519 -C "balamuru.peri@gmail.com" -f ~/.ssh/github_parts_watcher -N ""
```

### Add Public Key to GitHub

1. Display your public key:
```bash
cat ~/.ssh/github_parts_watcher.pub
```

2. Go to **GitHub Settings → SSH and GPG keys**
   - https://github.com/settings/keys

3. Click **New SSH key**

4. Add the following details:
   - **Title**: `parts-watcher`
   - **Key type**: Authentication Key
   - **Key**: Paste the output from step 1

5. Click **Add SSH key**

### Configure SSH Config

Add this to `~/.ssh/config`:

```
Host github.com-parts-watcher
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_parts_watcher
    IdentitiesOnly yes
```

### Test SSH Connection

```bash
ssh -i ~/.ssh/github_parts_watcher -T git@github.com
```

Expected output:
```
Hi ss-loves-AC! You've successfully authenticated, but GitHub does not provide shell access.
```

## Git Repository Setup

### Configure Local Repository

```bash
cd /path/to/parts-watcher

# Set user info
git config --local user.name "ss-loves-AC"
git config --local user.email "balamuru.peri@gmail.com"

# Configure SSH key for this repo
git config --local core.sshCommand "ssh -i ~/.ssh/github_parts_watcher"
```

### Add Remote and Push

```bash
# Add remote
git remote add origin git@github.com:ss-loves-AC/parts-watcher.git

# Set main branch
git branch -M main

# Push to GitHub
git push -u origin main
```

## Login Steps for New Users

### First Time Setup

1. **Generate SSH Key** (if you don't have one):
   ```bash
   ssh-keygen -t ed25519 -C "your-email@gmail.com"
   ```

2. **Add Public Key to GitHub Account**:
   - Copy your public key: `cat ~/.ssh/id_ed25519.pub`
   - Go to https://github.com/settings/keys
   - Add new SSH key

3. **Clone Repository**:
   ```bash
   git clone git@github.com:ss-loves-AC/parts-watcher.git
   cd parts-watcher
   ```

4. **Configure Git** (first time only):
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your-email@gmail.com"
   ```

5. **Verify Setup**:
   ```bash
   git log
   git remote -v
   ```

### Daily Workflow

```bash
# Pull latest changes
git pull

# Create a feature branch
git checkout -b feature/your-feature-name

# Make changes and commit
git add .
git commit -m "Descriptive commit message"

# Push to GitHub
git push -u origin feature/your-feature-name

# Create Pull Request on GitHub
```

## Troubleshooting

### "Permission denied (publickey)"
- Verify SSH key is added to GitHub: `ssh -T git@github.com`
- Check SSH key location and permissions: `ls -la ~/.ssh/`

### "Repository not found"
- Verify repository exists on GitHub
- Check remote URL: `git remote -v`
- Make sure you have access to the repository

### SSH Key Not Working
```bash
# List available SSH keys
ssh-add -l

# Add SSH key to agent
ssh-add ~/.ssh/github_parts_watcher
```

## Additional Resources

- [GitHub SSH Documentation](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [Git Configuration](https://git-scm.com/book/en/v2/Git-Internals-Environment-Variables)
