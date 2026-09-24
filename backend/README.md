# LabelReader Backend

## Setup

```bash
cd backend
pip install -r requirements.txt
```

## Configure

Edit `.env` and set your OpenAI API key:
```
OPENAI_API_KEY=sk-...
```

## Run

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

API docs available at http://localhost:8000/docs
