# Circuit IDE

A modern, VS Code-style AI-powered IDE built with Python and PySide6. Features dual AI provider support (Cisco Circuit API and Claude/Anthropic), integrated Git management, and a professional code editor with syntax highlighting.

![Circuit IDE](assets/icon.png)

## Features

- **Dual AI Provider Support**: Switch between Cisco Circuit API and Claude (Anthropic) seamlessly
- **VS Code-style Interface**: Familiar layout with activity bar, file explorer, tabs, and status bar
- **Code Editor**: Syntax highlighting, line numbers, minimap, find/replace, and linting integration
- **Git Integration**: Full source control with branch management, commit, push, pull, and diff viewer
- **Theme Support**: Multiple dark themes (VS Code Dark, Monokai, Nord, Dracula)
- **Real-time Linting**: Python linting with pylint/ruff/flake8 integration
- **Token Tracking**: Monitor AI usage with token counts and cost estimates

## Quick Start

### Prerequisites

- Python 3.11 or higher
- pip (Python package manager)
- Git (for version control features)

### Windows (One-Click Install)

1. **Download or clone** the repository
2. **Double-click `install-windows.bat`** - it will:
   - Check that Python is installed
   - Install all dependencies automatically
   - Create a `run-circuit-ide.bat` launcher
   - Offer to launch Circuit IDE immediately
3. **Next time**, just double-click `run-circuit-ide.bat` to start

> **Note:** Make sure "Add Python to PATH" was checked when you installed Python.
> Download Python from [python.org](https://www.python.org/downloads/) if needed.

### macOS / Linux

1. **Clone the repository:**
   ```bash
   git clone https://github.com/JackRiebel/Circuit-IDE.git
   cd Circuit-IDE
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Run the application:**
   ```bash
   python circuit_ide_gui/main.py
   ```

### First Launch

1. Open a project folder via **File > Open Folder** or click "Open Folder" on the welcome screen
2. Go to **Settings** (gear icon in activity bar) to configure your AI provider:
   - For **Cisco Circuit**: Enter your Client ID, Client Secret, and App Key
   - For **Claude/Anthropic**: Enter your Anthropic API key
3. Start chatting with the AI in the right panel!

## Configuration

### AI Providers

#### Cisco Circuit API
Get credentials from: https://developer.cisco.com/site/ai-ml/
- Navigate to "Manage Circuit API Keys" > "View"
- You'll need: Client ID, Client Secret, and App Key

#### Anthropic/Claude
Get an API key from: https://console.anthropic.com/
- Create an account and generate an API key
- Supports Claude Sonnet 4, Opus 4, and other models

### Settings Location

Settings are stored in:
- **macOS**: `~/.config/circuit-ide-gui/settings.json`
- **Linux**: `~/.config/circuit-ide-gui/settings.json`
- **Windows**: `%APPDATA%\circuit-ide-gui\settings.json`

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + O` | Open folder |
| `Cmd/Ctrl + S` | Save file |
| `Cmd/Ctrl + F` | Find in file |
| `Cmd/Ctrl + G` | Go to line |
| `Cmd/Ctrl + W` | Close tab |
| `Cmd/Ctrl + Tab` | Next tab |
| `Cmd/Ctrl + Shift + Tab` | Previous tab |

## Project Structure

```
circuit-ide/
├── circuit_ide_gui/          # Main GUI application
│   └── main.py               # Application entry point
├── circuit_agent/            # Core agent package (CLI)
│   ├── agent.py              # CircuitAgent class
│   ├── cli.py                # CLI interface
│   ├── config.py             # Configuration management
│   ├── streaming.py          # SSE response parsing
│   ├── security.py           # Secret detection, audit
│   └── tools/                # Tool implementations
├── assets/                   # Icons and images
│   ├── icon.svg              # App icon (SVG)
│   └── icon.png              # App icon (PNG)
├── docs/                     # Documentation
├── tests/                    # Test suite
├── pyproject.toml            # Project configuration
└── README.md                 # This file
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| PySide6 | >=6.6.0 | Qt GUI framework |
| httpx | >=0.25.0 | HTTP client for API calls |
| pygments | >=2.17.0 | Syntax highlighting |
| anthropic | >=0.18.0 | Anthropic Claude API (optional) |

## Git Integration

The Git panel provides:
- **Branch Management**: View and switch branches
- **Staging**: Stage individual files or all changes
- **Commits**: Write commit messages and commit
- **Sync**: Pull from and push to remote
- **History**: View recent commits
- **Diff Viewer**: See changes before committing

Git uses your system's git configuration, so make sure you have:
- Git installed and in your PATH
- GitHub/GitLab credentials configured (SSH key or credential helper)

## Themes

Available themes:
- **VS Code Dark** (default)
- **Monokai**
- **Nord**
- **Dracula**

Change themes in Settings > Theme.

## Troubleshooting

### "AI agent not connected"
- Check your API credentials in Settings
- Ensure you have internet connectivity
- Verify the API service is available

### Git operations failing
- Ensure git is installed: `git --version`
- Check git credentials are configured: `git config --list`
- For GitHub, set up SSH keys or use credential helper

### Font warnings on startup
The app tries to use Monospace/Consolas fonts. If unavailable, it falls back to system fonts. This warning can be safely ignored.

## Development

### Running Tests
```bash
python -m pytest tests/
```

### Building for Distribution

**Standalone executable (all platforms):**
```bash
pip install pyinstaller
pyinstaller --onefile --windowed circuit_ide_gui/main.py
```

**Flutter desktop app (Windows):**
```
Double-click build-windows.bat
```
Requires Flutter SDK and Visual Studio with C++ Desktop workload.

## License

MIT License - See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Run tests: `python -m pytest`
5. Commit: `git commit -m "Add feature"`
6. Push: `git push origin feature-name`
7. Open a Pull Request
