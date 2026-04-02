import os
import uuid
from dotenv import load_dotenv
load_dotenv()
from fastapi import FastAPI, Depends, HTTPException, Security
from fastapi.security import APIKeyHeader
from routers import sync
from services.markdown_writer import DATA_DIR

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
