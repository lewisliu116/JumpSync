from fastapi import APIRouter
from models.schemas import SyncPayloadContact, SyncPayloadReminder, SyncPayloadNote
from services.markdown_writer import MarkdownWriter

router = APIRouter()
writer = MarkdownWriter()

def _optimized_delete_by_ids(ids: list, subfolder: str):
    import os
    from services.markdown_writer import DATA_DIR, generate_short_id
    if not ids:
        return
    target_dir = os.path.join(DATA_DIR, subfolder)
    if not os.path.isdir(target_dir):
        return
    short_ids = {generate_short_id(uid) for uid in ids}
    for root, dirs, files in os.walk(target_dir):
        for filename in files:
            if filename.endswith(".md"):
                base = filename[:-3]
                dash_idx = base.rfind("-")
                if dash_idx != -1 and base[dash_idx + 1:] in short_ids:
                    try:
                        os.remove(os.path.join(root, filename))
                    except:
                        pass

@router.put("/contacts")
def sync_contacts(payload: SyncPayloadContact):
    print(f"[SYNC] /contacts PUT: {len(payload.changed)} changed, {len(payload.deleted)} deleted")
    _optimized_delete_by_ids(payload.deleted, "contacts")
    for contact in payload.changed:
        writer.write_contact(contact)
    return {"status": "success", "written": len(payload.changed)}

@router.get("/reminders")
def pull_reminders():
    """Bidirectional pull: return all reminders currently stored on the server
    (including any server-side edits) so the macOS client can reconcile them
    back into Apple Reminders via EventKit."""
    from services.markdown_reader import read_reminders
    return {"reminders": read_reminders()}

@router.put("/reminders")
def sync_reminders(payload: SyncPayloadReminder):
    print(f"[SYNC] /reminders PUT: {len(payload.changed)} changed, {len(payload.deleted)} deleted")
    _optimized_delete_by_ids(payload.deleted, "reminders")
    for reminder in payload.changed:
        writer.write_reminder(reminder)
    return {"status": "success"}

@router.put("/notes")
def sync_notes(payload: SyncPayloadNote):
    print(f"[SYNC] /notes PUT: {len(payload.changed)} changed, {len(payload.deleted)} deleted")
    _optimized_delete_by_ids(payload.deleted, "notes")
    for i, note in enumerate(payload.changed):
        writer.write_note(note)
        if (i + 1) % 50 == 0 or (i + 1) == len(payload.changed):
            print(f"[SYNC] Written {i + 1}/{len(payload.changed)} notes")
    return {"status": "success", "written": len(payload.changed)}
