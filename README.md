# JumpSync

A zero-dependency, native macOS menu bar app that hyper-syncs Apple Contacts, Reminders, and Notes into raw Markdown files, alongside a high-performance Python FastAPI backend for remote AI-driven Entity Linking and Knowledge Graphs.

## Architecture Structure

```
MacCloudSync/
├── macos/          # Zero-dependency macOS menu bar client (SwiftUI)
└── server/         # Remote sync receiver & AI CRM Server (Python FastAPI)
```

## Phase 1-4: macOS Client

The macOS App runs 100% natively, requiring NO external Homebrew libraries or CLI tools (like `remindctl` or `memo`). It hooks deeply into Apple's internal databases (`CNContactStore`, `EventKit`, and native `AppleScript` isolation engines) to pull data instantaneously.

### Build & Run

Open the project directly in Xcode (recommended):
```bash
cd macos
open JumpSync.xcodeproj
```

*Build and Run (`⌘R`)* to install it directly to your macOS Menu Bar.

### Capabilities

- **Local Mode**: Compiles your entire Apple ecosystem into perfect, orphan-managed `.md` files natively isolated in `~/Documents/JumpSync/`.
- **Remote Mode**: Bypasses local storage and seamlessly streams compressed incremental `SyncPayload` diffs directly to the Python FastAPI server.

### Permissions

On first launch, macOS will securely prompt you to authorize:
- **Contacts** Access 
- **Reminders** Access
- **Automation** Access (to allow JumpSync to securely index the Notes app)

---

## Phase 5-6: FastAPI Remote Sync Server

The Python Server acts as the remote "Brain" of the operation. It automatically receives incremental CRUD lifecycle updates from the macOS app, instantly re-compiles the updated records into formatted Markdown files on the server's local drive, and silently hunts down and purges deleted local "ghost" files dynamically via glob searching.

### 1. Install & Activate Dependencies

From a fresh terminal, spin up the python virtual environment:
```bash
cd server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Run the Uvicorn Server

Launch the web layer locally on port `8000`. You can optionally define the API Key and the output data directory using environment variables. If left blank, it will automatically generate an ephemeral UUID API key and default storage to `server/data/`.

```bash
# Optional: Set a persistent API key and an external storage folder
export JUMPSYNC_API_KEY="my-secret-key-123"
export JUMPSYNC_DATA_DIR="/Users/liuxiao/Dropbox/JumpSync-Data"

uvicorn main:app --reload
```

### 3. Connect the macOS App

1. Open the running **JumpSync** app from your Mac's top Menu Bar.
2. Navigate to the **Configuration** tab.
3. Switch the **Output Mode** dropdown to `Remote Server`.
4. Verify the **Server URL** field points to `http://127.0.0.1:8000`.
5. Click **Sync Now**! 
   
You will watch the API payload `PUT` requests dynamically stream into your active Uvicorn terminal as the server begins depositing the raw markdown correctly inside the `MacCloudSync/server/data/` folder hierarchy!
