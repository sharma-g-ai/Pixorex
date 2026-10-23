# LabelReader Backend

## Setup

```bash
cd backend
pip install -r requirements.txt
```

## Configure

Set private values outside the repository. `GOOGLE_APPLICATION_CREDENTIALS`
must point to a service-account JSON file kept outside the project. The
committed key from earlier revisions must be revoked in its issuing account.

```
OPENAI_API_KEY=sk-...
LABEL_READER_BACKEND_TOKEN=<long-random-token>
GOOGLE_APPLICATION_CREDENTIALS=/private/path/google_service_account.json
LABEL_READER_ALLOWED_ORIGINS=http://localhost:3000
```

## Run

```bash
uvicorn main:app --host 127.0.0.1 --port 8000
```

API calls require `Authorization: Bearer <LABEL_READER_BACKEND_TOKEN>`.
API docs are available at http://localhost:8000/docs.
