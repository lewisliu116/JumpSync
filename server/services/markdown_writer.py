import os
import re
from datetime import datetime
from typing import Set, List
from dotenv import load_dotenv

load_dotenv()

raw_dir = os.environ.get("JUMPSYNC_DATA_DIR", "").strip()
if raw_dir:
    DATA_DIR = os.path.expanduser(raw_dir)
else:
    DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")

def sanitize_filename(name: str) -> str:
    sanitized = re.sub(r'[^\w\s-]', '', name).strip()
    sanitized = re.sub(r'\s+', '-', sanitized)
    return sanitized[:80] if sanitized else "untitled"

def sanitize_path(path: str) -> str:
    if not path: return ""
    parts = [sanitize_filename(p) for p in path.split('/')]
    return '/'.join(p for p in parts if p)

def generate_short_id(uid: str) -> str:
    if uid.startswith("x-coredata") or "/" in uid:
        parts = uid.split("/")
        return parts[-1][:8] if parts[-1] else uid[:6]
    clean = re.sub(r'[^a-zA-Z0-9]', '', uid)
    return clean[:6]

class MarkdownWriter:
    
    @staticmethod
    def write_contact(contact) -> str:
        # Reconstruct full name and display name logic since it was computed on swift side
        full_name = f"{contact.givenName} {contact.familyName}".strip()
        display_name = full_name if full_name else (contact.organizationName if contact.organizationName else "unnamed")
        safe_name = sanitize_filename(display_name)
        short_id = generate_short_id(contact.id)
        filename = f"{safe_name}-{short_id}.md"
        
        dir_path = os.path.join(DATA_DIR, "contacts")
        os.makedirs(dir_path, exist_ok=True)
        
        # Frontmatter
        lines = [
            "---",
            f'id: "{contact.id}"',
            "type: contact",
            "source: apple_contacts",
            f'name: "{full_name}"'
        ]
        
        if contact.emailAddresses:
            emails = ", ".join(f'"{e.value}"' for e in contact.emailAddresses)
            lines.append(f"email: [{emails}]")
        if contact.phoneNumbers:
            phones = ", ".join(f'"{p.value}"' for p in contact.phoneNumbers)
            lines.append(f"phone: [{phones}]")
        if contact.organizationName:
            lines.append(f'company: "{contact.organizationName}"')
        
        if getattr(contact, "modifiedAt", None):
            lines.append(f'modified_at: "{contact.modifiedAt}"')
        
        lines.append(f'synced_at: "{datetime.now().isoformat()}"')
        
        lines.append("---")
        lines.append(f"\n# {full_name}\n")
        if contact.note:
            lines.append(f"\n## Notes\n{contact.note}\n")
            
        content = "\n".join(lines)
        file_path = os.path.join(dir_path, filename)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
            
        return os.path.join("contacts", filename)

    @staticmethod
    def write_reminder(reminder) -> str:
        safe_name = sanitize_filename(reminder.title if reminder.title else "untitled")
        short_id = generate_short_id(reminder.id)
        filename = f"{safe_name}-{short_id}.md"
        
        list_folder = sanitize_filename(reminder.list.lower())
        dir_path = os.path.join(DATA_DIR, "reminders", list_folder)
        os.makedirs(dir_path, exist_ok=True)
        
        lines = [
            "---",
            f'id: "{reminder.id}"',
            "type: reminder",
            "source: apple_reminders",
            f'title: "{reminder.title}"',
            f'list: "{reminder.list}"',
            f'completed: {str(reminder.isCompleted).lower()}',
        ]
        
        if getattr(reminder, "priority", 0) != 0:
            lines.append(f'priority: {reminder.priority}')
        if getattr(reminder, "dueDate", None):
            lines.append(f'due_date: "{reminder.dueDate}"')
        if getattr(reminder, "creationDate", None):
            lines.append(f'created_at: "{reminder.creationDate}"')
        if getattr(reminder, "modificationDate", None):
            lines.append(f'modified_at: "{reminder.modificationDate}"')
            
        lines.append(f'synced_at: "{datetime.now().isoformat()}"')
        lines.append("---")
        lines.append(f"\n# {reminder.title}\n")

        if reminder.notes:
            lines.append(f"\n## Notes\n{reminder.notes}\n")
            
        content = "\n".join(lines)
        file_path = os.path.join(dir_path, filename)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
            
        return os.path.join("reminders", list_folder, filename)

    @staticmethod
    def write_note(note) -> str:
        safe_name = sanitize_filename(note.title if note.title else "untitled")
        short_id = generate_short_id(note.id)
        filename = f"{safe_name}-{short_id}.md"
        
        folder_name = sanitize_path(note.folder.lower() if note.folder else "")
        if not note.folder or note.folder == "Notes":
            dir_path = os.path.join(DATA_DIR, "notes")
            rel_prefix = "notes"
        else:
            dir_path = os.path.join(DATA_DIR, "notes", folder_name)
            rel_prefix = f"notes/{folder_name}"
            
        os.makedirs(dir_path, exist_ok=True)
        
        escaped_title = note.title.replace('"', '\\"') if note.title else "untitled"
        lines = [
            "---",
            f'id: "{note.id}"',
            "type: note",
            "source: apple_notes",
            f'title: "{escaped_title}"',
            f'folder: "{note.folder}"',
        ]
        
        if getattr(note, "creationDate", None):
            lines.append(f'created_at: "{note.creationDate}"')
        if getattr(note, "modificationDate", None):
            lines.append(f'modified_at: "{note.modificationDate}"')
            
        if getattr(note, "tags", None):
            tags_str = ", ".join(f'"{t}"' for t in note.tags)
            lines.append(f'tags: [{tags_str}]')
            
        lines.append(f'synced_at: "{datetime.now().isoformat()}"')
        lines.append("---")
        
        body_content = note.body
        if getattr(note, "attachments", None):
            import base64
            media_dir = os.path.join(DATA_DIR, "notes", "media")
            os.makedirs(media_dir, exist_ok=True)
            body_content += "\n\n## Internal Attachments\n"
            for att in note.attachments:
                att_id = getattr(att, "id", "unknown")
                att_filename = getattr(att, "filename", "attachment")
                b64 = getattr(att, "base64Data", "")
                
                # Use original filename or fallback, make sure it's unique enough
                ext = att_filename.split('.')[-1] if '.' in att_filename else 'bin'
                out_filename = f"{att_id}.{ext}"
                file_out = os.path.join(media_dir, out_filename)
                
                if b64:
                    try:
                        with open(file_out, "wb") as mf:
                            mf.write(base64.b64decode(b64))
                        
                        levels_deep = folder_name.count('/') + 1
                        up_path = "../" * levels_deep
                        rel_media_path = f"{up_path}media/{out_filename}" if note.folder and note.folder != "Notes" else f"media/{out_filename}"
                        if getattr(att, "mimeType", "").startswith("image/"):
                            body_content += f"![{att_filename}]({rel_media_path})\n"
                        else:
                            body_content += f"[{att_filename}]({rel_media_path})\n"
                    except:
                        pass

        lines.append(f"\n# {note.title}\n\n{body_content}\n")
            
        content = "\n".join(lines)
        file_path = os.path.join(dir_path, filename)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
            
        return os.path.join(rel_prefix, filename)

    @staticmethod
    def delete_files(relative_paths: List[str]):
        for rel_path in relative_paths:
            if not rel_path: continue
            file_path = os.path.join(DATA_DIR, rel_path)
            if os.path.exists(file_path):
                try:
                    os.remove(file_path)
                except:
                    pass
