# EVE Online API Tools – PowerShell Edition

This PowerShell project provides command-line tools for enhancing your interaction with the EVE Online universe, enabling faster search and route planning capabilities that go beyond the standard in-game features.

## ✨ Features

- **Shortest Route Finder**: `Get-EveSystemPath` calculates the most efficient route between two EVE systems.
- **Advanced System Search**: `Find-EveOnlineSystemByCriteria` enables detailed, property-based searches across the EVE universe.
- **Offline Cache for Speed**: Local JSON files are auto-generated (~8,000 systems) to drastically reduce load times for future queries.

## 🛠 Requirements

- PowerShell (available on Windows by default; Mac users can install via [Homebrew](https://brew.sh) using `brew install --cask powershell`)
- Internet connection with common ports open

## 🚀 Getting Started

1. Clone or download this repository.
2. Open PowerShell and import the main script:
   ```powershell
   .\EveOnlineAPI.ps1
   ```
3. Start exploring:
   - `Get-EveSystemPath`
   - `Find-EveOnlineSystemByCriteria`

The first execution will populate your local directory with:
```
Universe/
└── Systems/
    ├── Amarr.json
    ├── Jita.json
    └── ...(~8000 total)
```

## 📦 Output Format

All output is presented as plain text to the console for simplicity and speed. JSON data is stored locally for caching purposes and can be explored or extended as needed.

## 🤖 About This Project

This is a personal project by [Randall Boyd Ashley](https://github.com/rbashley), created both for personal use and as a showcase of PowerShell proficiency. Contributions are currently closed, but feel free to fork the repo or reach out with feedback.
