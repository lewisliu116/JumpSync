from typing import List, Optional
from pydantic import BaseModel

class LabeledValue(BaseModel):
    label: str
    value: str

class LabeledAddress(BaseModel):
    label: str
    street: str
    city: str
    state: str
    postalCode: str
    country: str

class SyncableContact(BaseModel):
    id: str
    givenName: str
    familyName: str
    organizationName: str
    jobTitle: str
    emailAddresses: List[LabeledValue]
    phoneNumbers: List[LabeledValue]
    postalAddresses: List[LabeledAddress]
    birthday: Optional[str] = None
    note: Optional[str] = None
    socialProfiles: List[LabeledValue]
    urlAddresses: List[LabeledValue]
    imageDataBase64: Optional[str] = None
    modifiedAt: Optional[str] = None

class SyncableReminder(BaseModel):
    id: str
    title: str
    notes: Optional[str] = None
    dueDate: Optional[str] = None
    priority: int
    list: str
    isCompleted: bool
    completionDate: Optional[str] = None
    creationDate: Optional[str] = None
    modificationDate: Optional[str] = None

class SyncableAttachment(BaseModel):
    id: str
    filename: str
    mimeType: str
    base64Data: str

class SyncableNote(BaseModel):
    id: str
    title: str
    body: str
    folder: str
    tags: Optional[List[str]] = None
    attachments: Optional[List[SyncableAttachment]] = None
    creationDate: Optional[str] = None
    modificationDate: Optional[str] = None

# Wrapper payloads that exactly match the Swift app's `ChangeResult`
class SyncPayloadContact(BaseModel):
    changed: List[SyncableContact]
    deleted: List[str]

class SyncPayloadReminder(BaseModel):
    changed: List[SyncableReminder]
    deleted: List[str]

class SyncPayloadNote(BaseModel):
    changed: List[SyncableNote]
    deleted: List[str]
