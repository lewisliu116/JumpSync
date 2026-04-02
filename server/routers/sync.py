from fastapi import APIRouter
from models.schemas import SyncPayloadContact, SyncPayloadReminder, SyncPayloadNote
from services.markdown_writer import MarkdownWriter

router = APIRouter()
writer = MarkdownWriter()

@router.put("/contacts")
def sync_contacts(payload: SyncPayloadContact):
    import os, glob
    from services.markdown_writer import DATA_DIR, generate_short_id
    
    def delete_by_ids(ids: list, subfolder: str):
        for uid in ids:
            short_id = generate_short_id(uid)
            # recursively search subfolder for file ending in short_id.md
            search_path = os.path.join(DATA_DIR, subfolder, "**", f"*-{short_id}.md")
            for f in glob.glob(search_path, recursive=True):
                try: os.remove(f)
                except: pass

    delete_by_ids(payload.deleted, "contacts")

    for contact in payload.changed:
        writer.write_contact(contact)
        
    return {"status": "success", "written": len(payload.changed)}

@router.put("/reminders")
def sync_reminders(payload: SyncPayloadReminder):
    from services.markdown_writer import MarkdownWriter, DATA_DIR, generate_short_id
    import os, glob
    
    def delete_by_ids(ids: list, subfolder: str):
        for uid in ids:
            short_id = generate_short_id(uid)
            search_path = os.path.join(DATA_DIR, subfolder, "**", f"*-{short_id}.md")
            for f in glob.glob(search_path, recursive=True):
                try: os.remove(f)
                except: pass

    delete_by_ids(payload.deleted, "reminders")
    
    for reminder in payload.changed:
        writer.write_reminder(reminder)
        
    return {"status": "success"}

@router.put("/notes")
def sync_notes(payload: SyncPayloadNote):
    from services.markdown_writer import MarkdownWriter, DATA_DIR, generate_short_id
    import os, glob
    
    def delete_by_ids(ids: list, subfolder: str):
        for uid in ids:
            short_id = generate_short_id(uid)
            search_path = os.path.join(DATA_DIR, subfolder, "**", f"*-{short_id}.md")
            for f in glob.glob(search_path, recursive=True):
                try: os.remove(f)
                except: pass

    delete_by_ids(payload.deleted, "notes")
    
    for note in payload.changed:
        writer.write_note(note)
        
    return {"status": "success"}
