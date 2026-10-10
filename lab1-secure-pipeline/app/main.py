from fastapi import FastAPI

app = FastAPI()


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}
