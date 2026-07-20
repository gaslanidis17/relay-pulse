# Relay Pulse

A fictional full-stack delivery analytics platform demonstrating operational monitoring, workflow design, diagnostics, and AI-assisted development.

**Everything in this repository is synthetic:** company names, locations, data, users, metrics, thresholds, calculations, and business rules.

## Features

- FastAPI backend and React/TypeScript frontend
- Simulated warehouse connection and deterministic mock-data engine
- Regional and city-level KPI views
- Maps, filters, drill-downs, diagnostics, and exports
- Authentication and session handling
- Cache warming and background refresh patterns
- AI-assisted operational summaries
- Automated tests and Docker support

## Quick start

```bash
bash setup.sh
bash run.sh
```

Open `http://localhost:5173`.

| User | Password |
|---|---|
| `admin` | `pulse-admin-demo` |
| `analyst` | `pulse-analyst-demo` |

The setup script creates a local `users.json` file, which is excluded from Git.

## Stack

- **Backend:** Python, FastAPI
- **Frontend:** React, TypeScript, Vite, Tailwind, Recharts, deck.gl
- **Data:** deterministic synthetic warehouse engine
- **Development:** Claude Code and Codex used for implementation support, testing, debugging, documentation, and public-safe transformation

See [PORTFOLIO.md](./PORTFOLIO.md) for additional context.
