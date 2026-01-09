# 🔄 git-sum

> Git Repository Status Summary Tool - Keep all your repos up to date with one command

## 📜 Description

**git-sum** scans configured directories for git repositories and provides a comprehensive summary of their states. It automatically pulls changes when safe, and offers solutions for repos that need attention.

**Key Features:**
- 🔍 **Scan multiple directories** containing git repositories
- ⬇️ **Auto-pull when safe** (clean repos with fast-forward possible)
- 📊 **Clear status summary** with actionable suggestions
- 🖥️ **Cross-platform** - Works on Windows (PowerShell), macOS, and Linux
- ⏰ **Optional autostart** - Run on login to stay updated
- 🎯 **First-time setup wizard** - Easy configuration with folder picker

---

## 📖 Table of Contents

1. [🚀 Quick Install](#-quick-install)
2. [🧑‍💻 Usage](#-usage)
3. [⚙️ Configuration](#-configuration)
4. [🔧 How It Works](#-how-it-works)
5. [🗑️ Uninstallation](#-uninstallation)
6. [💻 Platform Support](#-platform-support)

---

## 🚀 Quick Install

### 🍏 macOS

Copy and run in your terminal:

```bash
ORIGINAL_DIR=$(pwd)
mkdir -p /tmp/git-sum-setup && cd /tmp/git-sum-setup
curl -sO https://raw.githubusercontent.com/Sokrates1989/git-sum/main/setup/macos.sh
bash macos.sh
cd "$ORIGINAL_DIR"
rm -rf /tmp/git-sum-setup
```

### 🐧 Linux

Copy and run in your terminal:

```bash
ORIGINAL_DIR=$(pwd)
mkdir -p /tmp/git-sum-setup && cd /tmp/git-sum-setup
curl -sO https://raw.githubusercontent.com/Sokrates1989/git-sum/main/setup/linux.sh
bash linux.sh
cd "$ORIGINAL_DIR"
rm -rf /tmp/git-sum-setup
```

### 🪟 Windows

Copy and run each command separately in PowerShell (as Administrator for best results):

```powershell
$OriginalDir = Get-Location; $TempDir = "$env:TEMP\git-sum-setup"; New-Item -ItemType Directory -Path $TempDir -Force | Out-Null; Set-Location $TempDir
```

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Sokrates1989/git-sum/main/setup/windows.ps1" -OutFile "windows.ps1"; Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; .\windows.ps1
```

```powershell
$env:PATH = [Environment]::GetEnvironmentVariable("PATH", "User"); Set-Location $OriginalDir; Remove-Item -Recurse -Force $TempDir; git-sum
```

---

## 🧑‍💻 Usage

### Basic Commands

| Command | Description |
|---------|-------------|
| `git-sum` | Check all repos and pull if safe |
| `git-sum -s` / `git-sum --status` | Dry run - show status without pulling |
| `git-sum -a` / `git-sum --add` | Add more folders to watch |
| `git-sum -c` / `git-sum --config` | Open configuration editor |
| `git-sum -as` / `git-sum --autostart` | Configure autostart settings |
| `git-sum -u` / `git-sum --update` | Update to latest version |
| `git-sum -h` / `git-sum --help` | Show help |

### Example Output

```
🔄 git-sum - Scanning repositories...
======================================

📁 Scanning: D:\Development\Code\python
   🔍 Checking: my-api... ✅
   🔍 Checking: my-bot... 📥
      ⬇️  Pulling... Pulled 3 new commit(s)
   🔍 Checking: my-tools... ✏️

═══════════════════════════════════════════════════════════════
📊 Summary
═══════════════════════════════════════════════════════════════

   Total repositories scanned: 3

   ✅ Pulled:      1
   ✅ Up to date:  1
   ✏️  Dirty:       1

───────────────────────────────────────────────────────────────
⚠️  Repositories Needing Attention
───────────────────────────────────────────────────────────────

   ✏️ my-tools
      Branch: main
      Status: Has uncommitted changes
      Path:   D:\Development\Code\python\my-tools
      💡 Commit or stash changes: cd "D:\Development\Code\python\my-tools" && git stash

═══════════════════════════════════════════════════════════════
```

### Status Icons

| Icon | Status | Can Auto-Pull? |
|------|--------|----------------|
| ✅ | Up to date / Pulled | - |
| 📥 | Behind (has updates) | ✅ Yes |
| 📤 | Ahead (needs push) | ❌ No |
| ⚠️ | Diverged (conflicts) | ❌ No |
| ✏️ | Dirty (uncommitted changes) | ❌ No |
| 🔗 | No remote configured | ❌ No |

---

## ⚙️ Configuration

### First-Time Setup

On first run, git-sum will guide you through setup:

1. **Add folders** - Select directories containing your git repos
2. **Autostart** - Optionally run git-sum on login

### Configuration File

Configuration is stored in `config/watched-folders.json`:

```json
{
  "folders": [
    "D:\\Development\\Code\\python",
    "D:\\Development\\Code\\flutter"
  ],
  "settings": {
    "autostart": false,
    "lastRun": "2025-01-08T10:00:00+01:00"
  }
}
```

### Managing Folders

- **Add folders**: `git-sum -a` or through config editor `git-sum -c`
- **Remove folders**: Use config editor `git-sum -c`
- **Browse via GUI**: The folder picker opens your native file explorer

---

## 🔧 How It Works

1. **Scans** first-level subdirectories of configured folders for `.git` directories
2. **Fetches** remote changes (quiet, in background)
3. **Analyzes** each repo's state:
   - Current branch
   - Uncommitted changes
   - Ahead/behind remote
4. **Auto-pulls** if safe (clean + can fast-forward)
5. **Reports** summary with actionable suggestions

### Safe Pull Conditions

git-sum will only auto-pull when:
- ✅ No uncommitted changes
- ✅ Not ahead of remote (nothing to push)
- ✅ Can fast-forward (no diverged history)

---

## 🗑️ Uninstallation

### 🍏 macOS / 🐧 Linux

```bash
# Remove symlink
rm -f /usr/local/bin/git-sum
# Or if installed in ~/.local/bin:
rm -f ~/.local/bin/git-sum

# Remove installation directory
rm -rf ~/tools/git-sum

# Remove autostart (macOS)
rm -f ~/Library/LaunchAgents/com.gitsum.agent.plist

# Remove autostart (Linux)
rm -f ~/.config/autostart/git-sum.desktop
```

### 🪟 Windows

```powershell
# Remove alias from PowerShell profile
notepad $PROFILE
# Delete the line: Set-Alias git-sum "..."

# Remove installation directory
Remove-Item -Recurse -Force "$env:USERPROFILE\tools\git-sum"

# Remove from startup (if enabled)
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\git-sum.lnk" -ErrorAction SilentlyContinue
```

---

## 💻 Platform Support

| Platform | Shell | Status |
|----------|-------|--------|
| 🪟 Windows 10/11 | PowerShell 5.1+ | ✅ Supported |
| 🪟 Windows 10/11 | CMD | ✅ Supported (via wrapper) |
| 🍏 macOS | Bash/Zsh | ✅ Supported |
| 🐧 Linux | Bash | ✅ Supported |

### Prerequisites

- **Git** - Must be installed and in PATH
- **jq** (optional, recommended for Linux/macOS) - Better JSON parsing

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 🧪 Testing

Test scripts are located in the `testing/` directory to keep the repository root clean:

- **Windows PowerShell tests**: `testing/windows/`
- **Platform-specific tests**: Organized by OS

> **Note**: Test scripts are ignored from the root directory by `.gitignore`. All testing should be done within the `testing/` directory structure.

## 📄 License

MIT License - see LICENSE file for details.

---

## 🚀 Summary

✅ **One command to check all your git repos**  
✅ **Auto-pulls when safe**  
✅ **Clear status summary with fix suggestions**  
✅ **Cross-platform support**  
✅ **Easy first-time setup with folder picker**  
✅ **Optional autostart**

Keep all your repos up to date with `git-sum` ✨