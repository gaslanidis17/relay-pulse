# Relay Pulse — Portfolio Demo

Relay Pulse is a fictional, full-stack delivery analytics application built to demonstrate operational problem-solving, workflow design, data visualization, and AI-assisted development.

## Public-safe design

- All data is deterministic and synthetic.
- All companies, regions, cities, users, thresholds, metrics, and business rules are fictional.
- The public version contains no credentials, local logs, user database, private repository history, internal URLs, or employer documentation.
- The application defaults to a simulated warehouse through `DATA_SOURCE=mock`.

## What the project demonstrates

- FastAPI backend with caching and background refresh patterns
- React and TypeScript frontend with filters, maps, drill-downs, and exports
- Authentication and role-aware session handling
- Operational KPI monitoring and issue diagnostics
- AI-assisted summary workflows
- Testable synthetic-data generation
- Docker and cross-platform setup

## Quick start

```bash
bash setup.sh
bash run.sh
```

Open `http://localhost:5173`.

## Demo accounts

`setup.sh` creates the local `users.json` file from `users.json.example`.

| User | Password |
|------|----------|
| `admin` | `pulse-admin-demo` |
| `analyst` | `pulse-analyst-demo` |

These credentials are only for the local fictional demo.

## Technical notes

| Component | Purpose |
|---|---|
| `backend/app/services/mock_data_engine.py` | Generates deterministic synthetic records |
| `backend/app/config.py` | Fictional market and city configuration |
| `frontend/src/lib/lexicon.ts` | Fictional product and interface terminology |
| `.env.example` | Safe local configuration template |

## How I built it

I defined the operational problem, user flows, data structure, access rules, and testing criteria. I used Claude Code and Codex to accelerate implementation, debugging, testing, documentation, and the conversion of the portfolio version into a fully synthetic public demo. I reviewed the code and validated the final workflow myself.

## Before publishing

Create a new GitHub repository and commit this cleaned folder as a fresh initial commit. Do not reuse history from a private or work-related repository.
