"""Transactional bounded jobs and retry results, including derived source/audio.

Raw uploads have no separate stored file. Cached conversion results contain
rendered SVG previews or normalized raster sources for the documented retry window.
"""
import hashlib
import hmac
import json
import secrets
import sqlite3
import time
from .errors import TouchMapError

class Store:
    def __init__(self,settings):
        self.settings=settings;settings.state_dir.mkdir(parents=True,exist_ok=True)
        self.path=settings.state_dir/"jobs.sqlite3"
        with self.connection() as db:
            db.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS pairing (hash TEXT PRIMARY KEY, expires REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS sessions (hash TEXT PRIMARY KEY, expires REAL NOT NULL, analyses INTEGER DEFAULT 0, requests INTEGER DEFAULT 0);
            CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, session TEXT NOT NULL, fingerprint TEXT NOT NULL, state TEXT NOT NULL, result TEXT, expires REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS budget (id INTEGER PRIMARY KEY CHECK(id=1), reserved REAL NOT NULL, generations INTEGER NOT NULL);
            INSERT OR IGNORE INTO budget VALUES (1,0,0);
            CREATE TABLE IF NOT EXISTS throttle (key TEXT PRIMARY KEY, start REAL NOT NULL, count INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS audio_cache (key TEXT PRIMARY KEY, result TEXT NOT NULL, expires REAL NOT NULL);
            """)

    def connection(self):
        db=sqlite3.connect(self.path,timeout=10);db.row_factory=sqlite3.Row;return db

    def cleanup(self,startup=False):
        with self.connection() as db:
            now=time.time()
            for table in ("pairing","sessions","audio_cache"):
                db.execute(f"DELETE FROM {table} WHERE expires<?",(now,))
            # Keep expired request tombstones for one day to prevent accidental rebilling.
            db.execute("UPDATE jobs SET state='expired',result=NULL WHERE expires<? AND state!='outcome_unknown'",(now,))
            db.execute("DELETE FROM jobs WHERE expires<?",(now-86400,))
            db.execute("DELETE FROM throttle WHERE start<?",(now-60,))
            if startup:db.execute("UPDATE jobs SET state='outcome_unknown',result=NULL WHERE state='running'")

    def hash_token(self,value):
        return hmac.new((self.settings.signing_key or "loopback-only-local-development").encode(),value.encode(),hashlib.sha256).hexdigest()

    def pairing_code(self):
        code=secrets.token_urlsafe(9)
        with self.connection() as db:db.execute("INSERT INTO pairing VALUES (?,?)",(self.hash_token(code),time.time()+300))
        return code

    def pair(self,code):
        digest=self.hash_token(code);now=time.time()
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row=db.execute("SELECT * FROM pairing WHERE hash=?",(digest,)).fetchone()
            if not row or row["expires"]<now:raise TouchMapError("pairing_invalid","Pairing code is invalid, expired or already used",401)
            db.execute("DELETE FROM pairing WHERE hash=?",(digest,))
            token=secrets.token_urlsafe(32);expires=now+self.settings.session_seconds
            db.execute("INSERT INTO sessions(hash,expires) VALUES (?,?)",(self.hash_token(token),expires))
        return {"token":token,"expiresAt":int(expires)}

    def authenticate(self,token):
        digest=self.hash_token(token)
        with self.connection() as db:row=db.execute("SELECT * FROM sessions WHERE hash=?",(digest,)).fetchone()
        if not row or row["expires"]<time.time():raise TouchMapError("session_expired","Pair again to start an authenticated session",401)
        return digest

    def throttle(self,key,limit=60):
        now=time.time()
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row=db.execute("SELECT * FROM throttle WHERE key=?",(key,)).fetchone()
            if row and row["start"]+60>now:
                if row["count"]>=limit:raise TouchMapError("rate_limit","Request rate limit reached",429)
                db.execute("UPDATE throttle SET count=count+1 WHERE key=?",(key,))
            else:db.execute("INSERT OR REPLACE INTO throttle VALUES (?,?,1)",(key,now))

    def begin(self,request_id,session,fingerprint,analysis=False,reserve=0):
        self.cleanup()
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row=db.execute("SELECT * FROM jobs WHERE id=?",(request_id,)).fetchone()
            if row:
                if row["session"]!=session or row["fingerprint"]!=fingerprint:raise TouchMapError("idempotency_conflict","Request ID belongs to a different input or session",409)
                if row["state"]=="complete":return json.loads(row["result"])
                raise TouchMapError(row["state"],"Request is "+row["state"]+"; inspect status or explicitly retry with a new request ID",409)
            if db.execute("SELECT count(*) FROM jobs").fetchone()[0]>=10000:raise TouchMapError("job_limit","Bounded job store is full",429)
            db.execute("INSERT OR IGNORE INTO sessions(hash,expires) VALUES (?,?)",(session,time.time()+self.settings.session_seconds))
            s=db.execute("SELECT * FROM sessions WHERE hash=?",(session,)).fetchone()
            if analysis and s["analyses"]>=self.settings.analyses_per_session:raise TouchMapError("session_limit","Analysis session allowance exhausted",429)
            budget=db.execute("SELECT * FROM budget WHERE id=1").fetchone()
            if reserve and (budget["reserved"]+reserve>self.settings.spend_ceiling_usd or budget["generations"]>=self.settings.generation_ceiling):raise TouchMapError("spend_limit","Operator generation allowance reached",429)
            db.execute("UPDATE budget SET reserved=reserved+?,generations=generations+? WHERE id=1",(reserve,1 if reserve else 0))
            db.execute("UPDATE sessions SET analyses=analyses+?,requests=requests+1 WHERE hash=?",(int(analysis),session))
            db.execute("INSERT INTO jobs VALUES (?,?,?,'running',NULL,?)",(request_id,session,fingerprint,time.time()+self.settings.retry_window_seconds))
        return None

    def finish(self,request_id,result):
        with self.connection() as db:
            cursor=db.execute("UPDATE jobs SET state='complete',result=? WHERE id=? AND state='running'",(json.dumps(result),request_id))
            if cursor.rowcount!=1:raise TouchMapError("cancelled","Late result discarded because this job was cancelled",409)

    def fail(self,request_id,code):
        with self.connection() as db:db.execute("UPDATE jobs SET state=?,result=NULL WHERE id=? AND state='running'",("outcome_unknown" if code=="outcome_unknown" else "failed",request_id))

    def job(self,request_id,session,cancel=False):
        self.cleanup()
        with self.connection() as db:
            row=db.execute("SELECT * FROM jobs WHERE id=? AND session=?",(request_id,session)).fetchone()
            if not row:raise TouchMapError("job_missing","Job not found",404)
            if cancel:
                db.execute("UPDATE jobs SET state='cancelled',result=NULL WHERE id=?",(request_id,))
                return {"requestId":request_id,"state":"cancelled"}
            return {"requestId":request_id,"state":row["state"],"result":json.loads(row["result"]) if row["result"] else None}

    def audio(self,key,value=None):
        with self.connection() as db:
            if value is not None:db.execute("INSERT OR REPLACE INTO audio_cache VALUES (?,?,?)",(key,json.dumps(value),time.time()+self.settings.retry_window_seconds));return value
            row=db.execute("SELECT * FROM audio_cache WHERE key=? AND expires>?",(key,time.time())).fetchone()
            return json.loads(row["result"]) if row else None
