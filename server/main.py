import os
import uuid
from dotenv import load_dotenv
load_dotenv()
from fastapi import FastAPI, Depends, HTTPException, Security, Request
from fastapi.security import APIKeyHeader
from routers import sync
from services.markdown_writer import DATA_DIR
import time

# Load API Key from environment or generate a dynamic UUID session key
API_KEY = os.getenv("JUMPSYNC_API_KEY")

print("\n" + "="*60)
print(f"🧠 MAC CLOUD SYNC: FASTAPI SERVER BOOTUP")
print(f"📁 STORAGE DIRECTORY: {DATA_DIR}")

if not API_KEY:
    API_KEY = str(uuid.uuid4())
    print(f"⚠️  NO API KEY PROVIDED. GENERATED EPHEMERAL KEY:")
    print(f"🔑 {API_KEY}")
    print(f"👉 Set JUMPSYNC_API_KEY environment variable to persist this.")

print("="*60 + "\n")

app = FastAPI(title="MacCloudSync Server")

@app.middleware("http")
async def log_requests(request: Request, call_next):
    cl = request.headers.get("content-length", "unknown")
    client_ip = request.client.host if request.client else "unknown"
    print(f"[HTTP-IN] {request.method} {request.url.path} from {client_ip} (Content-Length: {cl})")
    t0 = time.time()
    response = await call_next(request)
    duration = time.time() - t0
    print(f"[HTTP-OUT] {request.method} {request.url.path} -> {response.status_code} ({duration:.2f}s)")
    return response

# Mac App sends its 'API Key' field via standard OAuth 'Bearer' strings
api_key_header = APIKeyHeader(name="Authorization", auto_error=True)

def verify_api_key(auth_header: str = Security(api_key_header)):
    token = auth_header.replace("Bearer ", "").strip()
    if token != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API Key")
    return token

# Lock the sync router completely behind this newly generated key!
app.include_router(sync.router, prefix="/api/sync", tags=["sync"], dependencies=[Depends(verify_api_key)])

@app.get("/api/health")
def health_check():
    return {"status": "ok"}
