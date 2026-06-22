# fakeapp docs

## Usage

Run `make simulate-change COMPONENT=backend` to trigger the fake CI pipeline.

## Components

- `frontend/` — fake frontend (node --check)
- `backend/` — fake backend (python py_compile)
- `infra/` — fake infra (terraform validate)
- `docs/` — fake docs (usage-section check)
- `bot/` — fake bot (node --check)
